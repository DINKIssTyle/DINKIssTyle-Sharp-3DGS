#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 scale [[attribute(1)]];
    float4 color [[attribute(2)]]; // RGB + Opacity
    float4 rotation [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
    float3 conic;
};

struct Uniforms {
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float2 screenSize;
    uint splatCount;
};

// Quaternion rotation matrix helper
// Input: q stores {w, x, y, z} in {x, y, z, w} components (standard PLY order)
float3x3 buildRotation(float4 q) {
    float w = q.x;
    float x = q.y;
    float y = q.z;
    float z = q.w;
    
    return float3x3(
        1.0 - 2.0*(y*y + z*z),  2.0*(x*y - w*z),        2.0*(x*z + w*y),
        2.0*(x*y + w*z),        1.0 - 2.0*(x*x + z*z),  2.0*(y*z - w*x),
        2.0*(x*z - w*y),        2.0*(y*z + w*x),        1.0 - 2.0*(x*x + y*y)
    );
}

// Bitonic Sort
struct SortElement {
    float key; // Distance squared
    uint index; // Original index
};

kernel void calc_distances(device SortElement* sortBuffer [[buffer(0)]],
                           constant float3* positions [[buffer(1)]],
                           constant Uniforms& uniforms [[buffer(2)]],
                           uint id [[thread_position_in_grid]]) {
    if (id >= uniforms.splatCount) {
        sortBuffer[id].key = 1.0e20; // Infinity for padding
        sortBuffer[id].index = 0;
        return;
    }

    float3 pos = positions[id];
    float4 viewPos = uniforms.viewMatrix * float4(pos, 1.0);
    // Sort Ascending View Z (Back to Front)
    sortBuffer[id].key = viewPos.z;
    sortBuffer[id].index = id;
}

kernel void bitonic_sort_step(device SortElement* sortBuffer [[buffer(0)]],
                              constant uint& j [[buffer(1)]],
                              constant uint& k [[buffer(2)]],
                              uint id [[thread_position_in_grid]]) {
    uint ixj = id ^ j;
    
    if (ixj > id) {
        if ((id & k) == 0) {
            if (sortBuffer[id].key > sortBuffer[ixj].key) { // Ascending
                SortElement temp = sortBuffer[id];
                sortBuffer[id] = sortBuffer[ixj];
                sortBuffer[ixj] = temp;
            }
        } else {
            if (sortBuffer[id].key < sortBuffer[ixj].key) { // Descending
                SortElement temp = sortBuffer[id];
                sortBuffer[id] = sortBuffer[ixj];
                sortBuffer[ixj] = temp;
            }
        }
    }
}

// Vertex Shader modified for Covariance Rendering with Safety

vertex VertexOut splatVertex(uint vertexID [[vertex_id]],
                             uint instanceID [[instance_id]],
                             constant Uniforms &uniforms [[buffer(4)]],
                             device const float3* positions [[buffer(0)]],
                             device const float3* scales [[buffer(1)]],
                             device const float4* colors [[buffer(2)]],
                             device const float4* rotations [[buffer(3)]],
                             device const SortElement* sortBuffer [[buffer(5)]]) 
{
    VertexOut out;
    uint id = sortBuffer[instanceID].index;
    
    // 1. Load Data
    float3 center = positions[id];
    float4 rawColor = colors[id];
    float3 scale = scales[id];
    float4 rot = rotations[id]; 
    float opacity = rawColor.a;

    // 2. View Space
    float4 viewPos4 = uniforms.viewMatrix * float4(center, 1.0);
    float3 viewPos = viewPos4.xyz;
    
    // Cull if behind camera (Z > 0 in Right-Handed View Space)
    if (viewPos.z > 0.0f) {
        out.position = float4(0,0,2,1);
        return out;
    }
    
    // 3. Covariance 3D (Sigma)
    float3x3 R = buildRotation(rot);
    float3x3 S = float3x3(scale.x, 0, 0, 0, scale.y, 0, 0, 0, scale.z);
    float3x3 M = R * S;
    float3x3 Sigma = M * transpose(M); 
    
    // 4. Project to 2D Covariance (Cov2D)
    // J * W * Sigma * W' * J'
    
    // W: World-to-Camera Rotation part of View Matrix
    float3x3 W = float3x3(
        uniforms.viewMatrix[0].xyz, 
        uniforms.viewMatrix[1].xyz, 
        uniforms.viewMatrix[2].xyz
    );
    
    // J: Jacobian of Perspective Projection
    // We need focal length in PIXELS
    // Projection (0,0) is 1/tan(fov/2) / aspect => 1/tan(fov/2) * height/width * width/2 ??
    // Standard approach:
    // P[0][0] = 2n / w = 1 / (aspect * tan(fov/2))
    // P[1][1] = 2n / h = 1 / tan(fov/2)
    // ScreenX = (NDC.x * 0.5 + 0.5) * Width
    
    // Accurate Focal Length Calculation from Projection Matrix
    // P00 = 2 * fx / Width => fx = P00 * Width / 2
    // P11 = 2 * fy / Height => fy = P11 * Height / 2
    float focal_x = uniforms.projectionMatrix[0][0] * uniforms.screenSize.x * 0.5;
    float focal_y = uniforms.projectionMatrix[1][1] * uniforms.screenSize.y * 0.5;
    
    float x = viewPos.x;
    float y = viewPos.y;
    float z = viewPos.z;
    
    // Approximation of Jacobian (dropping some small terms for stability)
    // J = [ fx/z  0     -fx*x/z^2 ]
    //     [ 0     fy/z  -fy*y/z^2 ]
    //     [ 0     0     0         ]
    float3x3 J = float3x3(
        focal_x / z, 0, -(focal_x * x) / (z * z),
        0, focal_y / z, -(focal_y * y) / (z * z),
        0, 0, 0
    );
    
    // T = J * W
    // But W is already applied if we transform Sigma to View Space first?
    // Actually standard Equation is: Cov' = J * W * Sigma * W^t * J^t
    // Let's compute T = J * W
    float3x3 T = J * W;
    
    // Cov2D = T * Sigma * T^t
    float3x3 Cov2D = T * Sigma * transpose(T);
    
    // Extract 2x2 Covariance
    // Add small epsilon to diagonal to ensure invertibility
    float cov_a = Cov2D[0][0] + 0.3f;
    float cov_b = Cov2D[0][1];
    float cov_c = Cov2D[1][1] + 0.3f;
    
    // 5. Compute Eigenvalues for Quad Dimensions
    float det = cov_a * cov_c - cov_b * cov_b;
    if (det <= 0.0f) {
        out.position = float4(0,0,2,1); return out;
    }
    
    float mid = 0.5 * (cov_a + cov_c);
    float term = 0.5 * sqrt(max(0.1f, (cov_a - cov_c)*(cov_a - cov_c) + 4.0 * cov_b * cov_b));
    float lambda1 = mid + term;
    float lambda2 = mid - term; // can be negative if det < 0, but we checked det
    
    // Radius (Screen Pixels) = 3 sigma (99% confidence)
    float radius = ceil(3.0 * sqrt(max(lambda1, lambda2)));
    
    // 6. Generate Quad Vertices (Pixel Space)
    float2 corner; 
    if (vertexID == 0) corner = float2(-1, -1);
    else if (vertexID == 1) corner = float2(1, -1);
    else if (vertexID == 2) corner = float2(-1, 1);
    else corner = float2(1, 1);
    
    float2 screenOffset = corner * radius;
    
    // 7. Final Projection
    float4 clipPos = uniforms.projectionMatrix * viewPos4;
    // Perform perspective divide manually to add offset in Screen Space (NDC)
    float2 ndcCenter = clipPos.xy / clipPos.w;
    
    // NDCOffset = ScreenOffset / ScreenSize * 2
    float2 ndcOffset = (screenOffset / uniforms.screenSize) * 2.0;
    
    out.position = float4(ndcCenter + ndcOffset, clipPos.z / clipPos.w, 1.0);
    out.uv = screenOffset; // Passed in pixel units for conic calc? No, usually unit [-radius, radius]
    
    // Standard approach: Pass offset in pixels to fragment, reconstruct power
    out.uv = screenOffset; 
    out.color = float4(rawColor.rgb, opacity);
    
    // Precompute Conic (Inverse Covariance)
    float det_inv = 1.0 / det;
    out.conic = float3(cov_c * det_inv, -cov_b * det_inv, cov_a * det_inv);
    
    return out;
}

fragment float4 splatFragment(VertexOut in [[stage_in]]) {
    float3 conic = in.conic;
    float opacity = in.color.a;
    float2 d = in.uv; // d is vector from center in pixels
    
    // Power = -0.5 * (x^T * Sigma^-1 * x)
    // Sigma^-1 = Conic = [c.x c.y; c.y c.z]
    float power = -0.5 * (conic.x * d.x * d.x + (conic.y + conic.y) * d.x * d.y + conic.z * d.y * d.y);
    
    if (power > 0.0f) discard_fragment();
    
    float alpha = min(0.99f, opacity * exp(power));
    
    if (alpha <= 1.0/255.0) discard_fragment();
    
    // Premultiplied Alpha
    return float4(in.color.rgb * alpha, alpha);
}
