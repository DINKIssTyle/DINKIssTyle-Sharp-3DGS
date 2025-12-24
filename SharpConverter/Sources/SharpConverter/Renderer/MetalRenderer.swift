import MetalKit
import SwiftUI
import MetalPerformanceShaders

struct Uniforms {
    var viewMatrix: matrix_float4x4
    var projectionMatrix: matrix_float4x4
    var screenSize: SIMD2<Float>
    var splatCount: UInt32
    var pad: UInt32 = 0 // Align to 16 bytes if needed, but metal struct alignment rules apply
}

struct SortElement {
    var key: Float
    var index: UInt32
}

func nextPowerOfTwo(_ n: Int) -> Int {
    guard n > 0 else { return 1 }
    var k = 1
    while k < n { k <<= 1 }
    return k
}

class Camera {
    var position: SIMD3<Float> = SIMD3<Float>(0, 0, 5)
    var target: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    
    var fov: Float = 45.0
    var near: Float = 0.1
    var far: Float = 100.0
    var aspect: Float = 1.0
    
    // Orbit controls
    var radius: Float = 5.0
    var theta: Float = 0.0
    var phi: Float = 0.0
    
    // Separate orbit pivot (Click to Focus sets this)
    var orbitPivot: SIMD3<Float>? = nil
    
    init() {
        updatePosition()
    }
    
    func updatePosition() {
        // This method is currently not used by the `rotate` and `zoom` methods
        // which directly manipulate `position` and `target`.
        // If an arcball-like system based on theta/phi/radius is desired,
        // this method would calculate `position` from these spherical coordinates.
        // For now, `position` is directly managed by interaction methods.
    }
    
    var viewMatrix: matrix_float4x4 {
        return matrix_look_at_right_hand(eye: position, target: target, up: up)
    }
    
    var projectionMatrix: matrix_float4x4 {
        return matrix_perspective_right_hand(fovyRadians: fov * (.pi / 180), aspectRatio: aspect, nearZ: near, farZ: far)
    }
    
    // Interaction
    // Interaction
    func zoom(delta: Float, speed: Float = 1.0) {
        radius -= delta * (radius * 0.05) * speed // Reduced sensitivity
        if radius < 0.1 { radius = 0.1 }
        
        let forward = normalize(target - position)
        position = target - forward * radius
    }
    
    func rotate(dx: Float, dy: Float, speed: Float = 1.0) {
        // Orbit around orbitPivot if set, otherwise around target
        let pivot = orbitPivot ?? target
        
        // Create rotation from current position
        let forward = position - pivot
        let right = normalize(cross(up, forward))
        
        // Rotate around Y and Local X
        let sensitivity: Float = 0.003 * speed
        
        // Rotation helper
        func rotationMatrix(angle: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
            let rows = [
                SIMD4<Float>(cos(angle) + axis.x*axis.x*(1 - cos(angle)), axis.x*axis.y*(1 - cos(angle)) - axis.z*sin(angle), axis.x*axis.z*(1 - cos(angle)) + axis.y*sin(angle), 0),
                SIMD4<Float>(axis.y*axis.x*(1 - cos(angle)) + axis.z*sin(angle), cos(angle) + axis.y*axis.y*(1 - cos(angle)), axis.y*axis.z*(1 - cos(angle)) - axis.x*sin(angle), 0),
                SIMD4<Float>(axis.z*axis.x*(1 - cos(angle)) - axis.y*sin(angle), axis.z*axis.y*(1 - cos(angle)) + axis.x*sin(angle), cos(angle) + axis.z*axis.z*(1 - cos(angle)), 0),
                SIMD4<Float>(0, 0, 0, 1)
            ]
            return float4x4(rows)
        }
        
        // Direction inverted to match standard 3D tools (drag right = view rotates left)
        let rotY = rotationMatrix(angle: dx * sensitivity, axis: up)
        let rotX = rotationMatrix(angle: dy * sensitivity, axis: right)
        
        // Apply rotation to camera position
        let currentPos4 = SIMD4<Float>(forward.x, forward.y, forward.z, 1.0)
        let newPos4 = rotY * rotX * currentPos4
        let newPos = SIMD3<Float>(newPos4.x, newPos4.y, newPos4.z)
        
        position = pivot + newPos
        
        // Also rotate target around pivot to maintain view direction
        let targetOffset = target - pivot
        let targetOffset4 = SIMD4<Float>(targetOffset.x, targetOffset.y, targetOffset.z, 1.0)
        let newTargetOffset4 = rotY * rotX * targetOffset4
        target = pivot + SIMD3<Float>(newTargetOffset4.x, newTargetOffset4.y, newTargetOffset4.z)
    }
    
    func pan(dx: Float, dy: Float, speed: Float = 1.0) {
        let forward = normalize(target - position)
        let right = normalize(cross(up, forward))
        let upLocal = normalize(cross(forward, right))
        
        // Panning moves position, target, and orbitPivot together
        let sensitivity: Float = radius * 0.0006 * speed
        
        // Direction: drag right = view moves left, drag up = view moves down
        let move = right * (dx * sensitivity) + upLocal * (dy * sensitivity)
        position += move
        target += move
        if orbitPivot != nil {
            orbitPivot! += move
        }
    }
    
    // Keyboard Navigation
    func update(targetDeltaTime: Float, keys: Set<UInt16>, isShift: Bool, speedMultiplier: Float) {
        let speed: Float = isShift ? 2.0 : 1.0 // 2x speed with Shift
        let moveSpeed: Float = 5.0 * speedMultiplier * speed * targetDeltaTime // Base move speed
        let rotSpeed: Float = 0.5 * speedMultiplier * speed * targetDeltaTime // Base rotation speed (Reduced & Scaled)
        
        // Forward / Right / Up vectors
        let forward = normalize(target - position)
        let right = normalize(cross(up, forward))
        let localUp = normalize(cross(forward, right))
        
        var moveDir = SIMD3<Float>(0, 0, 0)
        
        // Movement Keys
        // W (13): Forward
        if keys.contains(13) { moveDir += forward }
        // S (1): Backward
        if keys.contains(1) { moveDir -= forward }
        // A (0): Left
        if keys.contains(0) { moveDir += right }
        // D (2): Right
        if keys.contains(2) { moveDir -= right }
        // X (7): Up (Ascend) - Using Local Up for now, or could use self.up
        if keys.contains(7) { moveDir += localUp }
        // Z (6): Down (Descend)
        if keys.contains(6) { moveDir -= localUp }
        
        if length(moveDir) > 0 {
            moveDir = normalize(moveDir) * moveSpeed
            position += moveDir
            target += moveDir
        }
        
        // Rotation Keys
        // Q (12): Turn Left (Yaw)
        if keys.contains(12) { resizeRotation(axis: up, angle: -rotSpeed) }
        // E (14): Turn Right (Yaw)
        if keys.contains(14) { resizeRotation(axis: up, angle: rotSpeed) }
        
        // C (8): Pitch Up
        if keys.contains(8) { resizeRotation(axis: right, angle: rotSpeed) }
        // V (9): Pitch Down
        if keys.contains(9) { resizeRotation(axis: right, angle: -rotSpeed) }
        
        // R (15): Roll Left
        if keys.contains(15) { resizeRotation(axis: forward, angle: -rotSpeed, rotateVectors: true) }
        // F (3): Roll Right
        if keys.contains(3) { resizeRotation(axis: forward, angle: rotSpeed, rotateVectors: true) }
    }
    
    // Helper to rotate camera orientation
    private func resizeRotation(axis: SIMD3<Float>, angle: Float, rotateVectors: Bool = false) {
        let rotMat = rotationMatrix(angle: angle, axis: axis)
        
        // Rotate the 'target' around 'position' (Changing view direction)
        let forward = target - position
        let forward4 = SIMD4<Float>(forward.x, forward.y, forward.z, 1.0)
        let newForward4 = rotMat * forward4
        let newForward = SIMD3<Float>(newForward4.x, newForward4.y, newForward4.z)
        
        target = position + newForward
        
        // For Roll (or just to keep Up consistent), we might need to rotate Up vector too
        // Usually Pitch/Yaw re-orthogonalize Up, but Roll definitely needs Up rotation.
        // Actually, if we want full 6DOF, we should always rotate Up when we Pitch/Roll/Yaw?
        // Let's rotate Up for all to maintain the camera frame, especially since we have Roll.
        
        let up4 = SIMD4<Float>(up.x, up.y, up.z, 1.0)
        let newUp4 = rotMat * up4
        up = normalize(SIMD3<Float>(newUp4.x, newUp4.y, newUp4.z))
    }
    
    private func rotationMatrix(angle: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
        let rows = [
            SIMD4<Float>(cos(angle) + axis.x*axis.x*(1 - cos(angle)), axis.x*axis.y*(1 - cos(angle)) - axis.z*sin(angle), axis.x*axis.z*(1 - cos(angle)) + axis.y*sin(angle), 0),
            SIMD4<Float>(axis.y*axis.x*(1 - cos(angle)) + axis.z*sin(angle), cos(angle) + axis.y*axis.y*(1 - cos(angle)), axis.y*axis.z*(1 - cos(angle)) - axis.x*sin(angle), 0),
            SIMD4<Float>(axis.z*axis.x*(1 - cos(angle)) - axis.y*sin(angle), axis.z*axis.y*(1 - cos(angle)) + axis.x*sin(angle), cos(angle) + axis.z*axis.z*(1 - cos(angle)), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ]
        return float4x4(rows)
    }
}

class MetalRenderer: NSObject, MTKViewDelegate {
    // ... [Properties Omitted] ...
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    var pipelineState: MTLRenderPipelineState?
    var splatCount: Int = 0
    
    var posBuffer: MTLBuffer?
    var scaleBuffer: MTLBuffer?
    var colorBuffer: MTLBuffer?
    var rotBuffer: MTLBuffer?
    var sortBuffer: MTLBuffer?
    
    var calcDistancesState: MTLComputePipelineState?
    var bitonicSortState: MTLComputePipelineState?
    
    var maxSplatCount: Int = 0 // Power of two size
    
    var startTime = Date()
    var lastTime: Double = 0
    
    // Settings
    var moveSpeedMultiplier: Float = 1.0
    var enablePickToFocus: Bool = true // New Setting
    
    // Input State
    var pressedKeys: Set<UInt16> = []
    var isShiftPressed: Bool = false
    
    let camera = Camera()
    
    // Export Properties
    var isExporting = false
    var isFrameProcessing = false // Guard to prevent duplicate processing of the same frame
    var videoExporter: VideoExporter?
    var exportTexture: MTLTexture?
    
    // UI Reference
    
    weak var view: MTKView?
    weak var animationManager: AnimationManager? // Reference to animation manager
    
    // CPU Data for Picking
    var splatPositions: [SIMD3<Float>] = []
    
    init?(metalKitView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.view = metalKitView
        
        super.init()
        
        print("DEBUG: MetalRenderer init successful")
        
        metalKitView.wantsLayer = true
        metalKitView.layer?.isOpaque = true
        // metalKitView.layer?.backgroundColor = NSColor.yellow.cgColor // DEBUG
        
        metalKitView.device = device
        metalKitView.delegate = self
        metalKitView.clearColor = MTLClearColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0) // Dark Gray
        metalKitView.colorPixelFormat = .bgra8Unorm
        metalKitView.depthStencilPixelFormat = .depth32Float
        
        buildPipeline(view: metalKitView)
    }
    
    func buildPipeline(view: MTKView) {
        var library: MTLLibrary?
        do {
            // Try runtime compilation from source
            // Note: Use 'Shaders' because we copied 'Shaders.metal'
            if let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal") {
                let source = try String(contentsOf: shaderURL, encoding: .utf8)
                library = try device.makeLibrary(source: source, options: nil)
            } else {
                print("ERROR: Shaders.metal not found in Bundle.module. Checking main bundle...")
                if let shaderURL = Bundle.main.url(forResource: "Shaders", withExtension: "metal") {
                     let source = try String(contentsOf: shaderURL, encoding: .utf8)
                     library = try device.makeLibrary(source: source, options: nil)
                } else {
                    print("CRITICAL ERROR: Shaders.metal not found in any bundle!")
                    return
                }
            }
        } catch {
            print("CRITICAL ERROR: Failed to compile shaders: \(error)")
            return
        }
        
        guard let validLibrary = library else { return }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = validLibrary.makeFunction(name: "splatVertex")
        descriptor.fragmentFunction = validLibrary.makeFunction(name: "splatFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        
        // Alpha Blending
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one // Premultiplied alpha assumed usually, but let's stick to sourceAlpha for now
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            
            if let distFunc = validLibrary.makeFunction(name: "calc_distances"),
               let sortFunc = validLibrary.makeFunction(name: "bitonic_sort_step") {
                calcDistancesState = try device.makeComputePipelineState(function: distFunc)
                bitonicSortState = try device.makeComputePipelineState(function: sortFunc)
            } else {
                print("Failed to load compute kernels")
            }
        } catch {
            print("Failed to create pipeline: \(error)")
        }
    }
    
    func load(url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let splats = try SplatLoader.load(from: url)
                let count = splats.count
                print("Loaded \(count) splats from \(url.lastPathComponent)")
                
                // Convert AOS to SOA for buffers
                var positions = [SIMD3<Float>]()
                var scales = [SIMD3<Float>]()
                var colors = [SIMD4<Float>]()
                var rots = [SIMD4<Float>]()
                
                positions.reserveCapacity(count)
                scales.reserveCapacity(count)
                colors.reserveCapacity(count)
                rots.reserveCapacity(count)
                
                // Calculate Bounds
                var minBounds = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
                var maxBounds = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
                
                for s in splats {
                    positions.append(s.position)
                    scales.append(s.scale)
                    colors.append(s.color)
                    rots.append(s.rotation)
                    
                    minBounds = simd_min(minBounds, s.position)
                    maxBounds = simd_max(maxBounds, s.position)
                }
                
                let pBuf = self.device.makeBuffer(bytes: positions, length: positions.count * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared)
                let sBuf = self.device.makeBuffer(bytes: scales, length: scales.count * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared)
                let cBuf = self.device.makeBuffer(bytes: colors, length: colors.count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
                let rBuf = self.device.makeBuffer(bytes: rots, length: rots.count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
                
                // Store for CPU Picking
                self.splatPositions = positions
                
                // Auto Focus Logic
                let center = (minBounds + maxBounds) * 0.5
                let size = maxBounds - minBounds
                let maxDim = max(size.x, max(size.y, size.z))
                
                // Distance to fit bounds in FOV (45 deg)
                let fitDist = (maxDim * 0.5) / 0.414 // tan(22.5)
                let cameraDist = fitDist * 1.5 // Padding
                
                // Sort Buffer (Power of 2)
                let paddedCount = nextPowerOfTwo(count)
                let sortBuf = self.device.makeBuffer(length: paddedCount * MemoryLayout<SortElement>.stride, options: .storageModePrivate)
                
                DispatchQueue.main.async {
                    self.posBuffer = pBuf
                    self.scaleBuffer = sBuf
                    self.colorBuffer = cBuf
                    self.rotBuffer = rBuf
                    self.sortBuffer = sortBuf
                    self.splatCount = count
                    self.maxSplatCount = paddedCount
                    
                    self.camera.target = center
                    self.camera.radius = cameraDist
                    // Position camera on positive Z to view model front
                    self.camera.position = center + [0, 0, cameraDist]
                    
                    // Orientation is determined by position and target.
                    // Standard Y-Up (PLY orientation is now fixed in SplatLoader)
                    self.camera.up = SIMD3<Float>(0, 1, 0)
                    
                    self.camera.far = max(100.0, cameraDist * 50.0)
                    self.camera.near = max(0.01, cameraDist * 0.01)
                    
                    // Save Initial State
                    self.initialPosition = self.camera.position
                    self.initialTarget = self.camera.target
                    self.initialRadius = self.camera.radius
                    
                    // Trigger Redraw
                    self.view?.setNeedsDisplay(self.view?.bounds ?? .zero)
                }
                
            } catch {
                print("Failed to load PLY: \(error)")
            }
        }
    }
    
    // Initial State Storage
    var initialPosition: SIMD3<Float>?
    var initialTarget: SIMD3<Float>?
    var initialRadius: Float?
    
    func resetCamera() {
        guard let pos = initialPosition, let tgt = initialTarget, let rad = initialRadius else { return }
        print("DEBUG: Resetting Camera")
        self.camera.position = pos
        self.camera.target = tgt
        self.camera.radius = rad
        self.camera.up = SIMD3<Float>(0, -1, 0) // Reset Up as well
        self.view?.setNeedsDisplay(self.view?.bounds ?? .zero)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("DEBUG: drawableSizeWillChange to \(size)")
        
        let size = view.drawableSize
        camera.aspect = Float(size.width / size.height)
        
        // Note: Uniforms are actually updated in draw(), this is just a hook if needed
        // For now, we update projection in draw() dynamically
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else {
             // print("DEBUG: Draw Cancelled - No RenderPassDescriptor")
             return
        }
        
        guard let pipelineState = pipelineState else {
             // print("DEBUG: Draw Cancelled - No PipelineState")
             return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Time Delta
        let currentTime = Date().timeIntervalSince(startTime)
        var deltaTime = Float(currentTime - lastTime)
        
        // Fix: Prevent large jumps when resuming from pause
        // If the loop was paused, deltaTime could be very large (e.g. seconds).
        // We clamp it to a standard frame time (e.g. 1/60s) for the first frame after wake.
        if deltaTime > 0.1 {
            deltaTime = 0.016
        }
        
        lastTime = currentTime
        
        // Update Camera Input
        camera.update(targetDeltaTime: deltaTime, keys: pressedKeys, isShift: isShiftPressed, speedMultiplier: moveSpeedMultiplier)
        
        // Animation Logic
        if let anim = animationManager {
            // 1. Capture Keyframe Request
            if anim.captureKeyframeTrigger {
                DispatchQueue.main.async {
                    anim.addKeyframe(frame: anim.currentFrame, camera: self.camera)
                    anim.captureKeyframeTrigger = false
                }
            }
            
            // 2. Playback
            // If playing, override camera with interpolated value
            // OR if just scrubbing (currentFrame changed), we might want to preview it?
            // For now, let's only force camera set when 'playing' OR 'scrubbing' (we can inspect frame)
            // Actually, if user moves slider, currentFrame changes. We should update camera.
            // But if user moves camera manually, we don't want to snap back unless playing.
            
            if (anim.isPlaying || anim.isScrubbing || isExporting) {
                if let state = anim.getCameraState(for: anim.currentFrame) {
                    camera.position = state.position
                    camera.target = state.target
                    camera.up = state.up
                }
                
                // If playing, request next frame
                if anim.isPlaying {
                    view.setNeedsDisplay(view.bounds)
                }
            }
        }
        
        if splatCount > 0, let pos = posBuffer, let scale = scaleBuffer, let col = colorBuffer, let rot = rotBuffer, let sort = sortBuffer {
            
            // Interactive Camera
            // Update aspect ratio
            let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
            camera.aspect = aspectRatio
            
            // Sort (and Upload Uniforms for Sort)
            self.performSort()
            
            // Create Uniforms for Render (same as Sort, or updated? Same is fine)
            // Ideally sort() updates the buffers.
            var uniforms = Uniforms(
                viewMatrix: camera.viewMatrix,
                projectionMatrix: camera.projectionMatrix,
                screenSize: simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                splatCount: UInt32(splatCount),
                pad: 0
            )
            
            // 2. Render Pass
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.setRenderPipelineState(pipelineState)
                
                renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 4)
                renderEncoder.setVertexBuffer(pos, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(scale, offset: 0, index: 1)
                renderEncoder.setVertexBuffer(col, offset: 0, index: 2)
                renderEncoder.setVertexBuffer(rot, offset: 0, index: 3)
                renderEncoder.setVertexBuffer(sort, offset: 0, index: 5)
                
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: splatCount)
                
                renderEncoder.endEncoding()
            }
        } else {
             if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                 renderEncoder.endEncoding()
             }
        }
        
        // Export Capture: Blit to persistent texture
        if isExporting {
            if isFrameProcessing {
                // If we are already processing a frame, skip this draw call's export logic
                // This prevents race conditions where draw is called multiple times for the same frame
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            isFrameProcessing = true
            print("DEBUG: Exporting frame capture...")
            
            // Calculate Target Size
            var targetWidth = drawable.texture.width
            var targetHeight = drawable.texture.height
            
            if let anim = animationManager {
                 let h = anim.exportHeight
                 let aspect = Float(drawable.texture.width) / Float(drawable.texture.height)
                 targetWidth = (Int(Float(h) * aspect) / 2) * 2
                 targetHeight = (h / 2) * 2
            }
            
            // Create/Resize texture if needed
            if exportTexture == nil || 
               exportTexture!.width != targetWidth || 
               exportTexture!.height != targetHeight {
                
                print("DEBUG: Creating export texture \(targetWidth)x\(targetHeight) (Source: \(drawable.texture.width)x\(drawable.texture.height))")
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: drawable.texture.pixelFormat, width: targetWidth, height: targetHeight, mipmapped: false)
                #if os(macOS)
                desc.storageMode = .managed
                #else
                desc.storageMode = .shared
                #endif
                desc.usage = [.shaderRead, .shaderWrite] 
                exportTexture = device.makeTexture(descriptor: desc)
            }
            
            if let dest = exportTexture {
                if dest.width != drawable.texture.width || dest.height != drawable.texture.height {
                     // Resize using MPS
                     let scale = MPSImageBilinearScale(device: device)
                     scale.encode(commandBuffer: commandBuffer, sourceTexture: drawable.texture, destinationTexture: dest)
                } else {
                     // Blit Copy
                     if let blit = commandBuffer.makeBlitCommandEncoder() {
                         blit.copy(from: drawable.texture, to: dest)
                         blit.endEncoding()
                     }
                }
                
                #if os(macOS)
                if let blit = commandBuffer.makeBlitCommandEncoder() {
                    blit.synchronize(resource: dest)
                    blit.endEncoding()
                }
                #endif
            }
        }
        
        commandBuffer.present(drawable)
        
        // Export Frame Advancement
        if isExporting {
            print("DEBUG: Adding completed handler for export")
            commandBuffer.addCompletedHandler { [weak self] _ in
                print("DEBUG: GPU Command Buffer Completed")
                guard let self = self else { return }
                guard let exporter = self.videoExporter, let texture = self.exportTexture, let anim = self.animationManager else { 
                    print("DEBUG: Export prerequisites missing in handler")
                    self.isFrameProcessing = false
                    return 
                }
                
                Task {
                    let time = Double(anim.currentFrame) / Double(anim.fps)
                    print("DEBUG: Appending frame \(anim.currentFrame) at time \(time)")
                    do {
                        try await exporter.append(texture: texture, time: time)
                        
                        await MainActor.run {
                            if anim.currentFrame < anim.totalFrames {
                                anim.currentFrame += 1
                                print("DEBUG: Requesting next frame \(anim.currentFrame)")
                                self.isFrameProcessing = false // Allow next frame
                                // Force setNeedsDisplay for next frame
                                self.view?.isPaused = true // Ensure pause is held
                                self.view?.enableSetNeedsDisplay = true
                                self.view?.setNeedsDisplay(self.view?.bounds ?? .zero)
                            } else {
                                print("DEBUG: All frames done")
                                // self.isFrameProcessing = false // finishExport resets everything
                                self.finishExport()
                            }
                        }
                    } catch {
                        print("Export Frame Failed: \(error)")
                        await MainActor.run { 
                            self.isFrameProcessing = false
                            self.finishExport() 
                        }
                    }
                }
            }
        }
        
        commandBuffer.commit()
    }
    
    func performSort() {
        guard splatCount > 0, let pos = posBuffer, let sort = sortBuffer else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let view = view else { return }
        
        let width = Float(view.drawableSize.width)
        let height = Float(view.drawableSize.height)
        
        var uniforms = Uniforms(
            viewMatrix: camera.viewMatrix,
            projectionMatrix: camera.projectionMatrix,
            screenSize: simd_float2(width, height),
            splatCount: UInt32(splatCount),
            pad: 0
        )
        
        if let distState = calcDistancesState, let sortState = bitonicSortState, let computeEnc = commandBuffer.makeComputeCommandEncoder() {
            computeEnc.setComputePipelineState(distState)
            computeEnc.setBuffer(sort, offset: 0, index: 0)
            computeEnc.setBuffer(pos, offset: 0, index: 1)
            computeEnc.setBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 2)
            
            let w = distState.threadExecutionWidth
            let h = distState.maxTotalThreadsPerThreadgroup / w
            let threadsPerGroup = MTLSizeMake(w, h, 1)
            let threadsPerGrid = MTLSizeMake(maxSplatCount, 1, 1)
            
            computeEnc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            
            var k: UInt32 = 2
            while k <= UInt32(maxSplatCount) {
                var j: UInt32 = k / 2
                while j > 0 {
                    computeEnc.setComputePipelineState(sortState)
                    computeEnc.setBytes(&j, length: 4, index: 1)
                    computeEnc.setBytes(&k, length: 4, index: 2)
                    computeEnc.setBuffer(sort, offset: 0, index: 0)
                    
                    computeEnc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                    j /= 2
                }
                k *= 2
            }
            
            computeEnc.endEncoding()
        }
        
        commandBuffer.commit()
    }
    

    // Picking Logic
    func pick(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) {
        guard !splatPositions.isEmpty else { return }
        
        let ndcX = (screenPoint.x / viewSize.x) * 2.0 - 1.0
        let ndcY = (1.0 - (screenPoint.y / viewSize.y)) * 2.0 - 1.0 // Flip Y for NDC (Up is positive)
        
        // Correct Ray Casting for Metal (NDC Z: 0..1)
        let clipCoords = SIMD4<Float>(ndcX, ndcY, 0.0, 1.0) // Point on Near Plane
        
        var invProj = camera.projectionMatrix.inverse
        var invView = camera.viewMatrix.inverse
        
        // Unproject to View Space
        var eye = invProj * clipCoords
        eye = eye / eye.w // Perspective Divide
        
        // Unproject to World Space
        let world = invView * eye
        
        // Ray Direction
        let rayDirection = normalize(world.xyz - camera.position)
        let rayWorld = rayDirection // Use this consistent name
        
        let eyeWorld = camera.position
        
        // Ray: Origin = eyeWorld, Dir = rayWorld
        
        // Brute force search (Simple Ray-Point Distance)
        // Optimization: Check points roughly in front of camera only?
        // This is O(N). For 1M points ~10-20ms. Acceptable for click.
        
        var closestDist: Float = Float.greatestFiniteMagnitude
        var hitPoint: SIMD3<Float>?
        
        // Threshold radius for "hit" (e.g. 0.1 units? dynamic?)
        // Let's use a heuristic based on camera distance or fixed small value
        let hitThreshold: Float = 0.5 // Adjust based on scene scale
        
        for pos in splatPositions {
            // Project point onto ray to find closest distance
            let v = pos - eyeWorld
            let t = dot(v, rayWorld)
            
            if t > 0 { // In front of camera
                let projectedPoint = eyeWorld + rayWorld * t
                let distSq = length_sq(pos - projectedPoint)
                
                if distSq < (hitThreshold * hitThreshold) {
                    if t < closestDist {
                        closestDist = t
                        hitPoint = pos
                    }
                }
            }
        }
        
        if let hit = hitPoint {
            print("picked hit: \(hit)")
            // Set orbit pivot to clicked point WITHOUT changing camera view
            // Only the orbit rotation center changes, not the view direction
            camera.orbitPivot = hit
            
            self.view?.setNeedsDisplay(self.view?.bounds ?? .zero)
        }
    }
    
    // Export State

    
    func startExport(to url: URL) {
        guard let anim = animationManager else { return }
        
        // Use current drawable size (or view size if drawable not ready, but usually it is)
        // We defer texture creation to draw loop to ensure we match `currentDrawable`
        
        guard let view = view else { return }
        
        let targetHeight = anim.exportHeight
        let aspect = view.drawableSize.width / view.drawableSize.height
        let targetWidth = Int(Float(targetHeight) * Float(aspect))
        
        // Ensure even dimensions
        let width = (targetWidth / 2) * 2
        let height = (targetHeight / 2) * 2
        
        print("Starting Playback Export to \(url.path) at \(width)x\(height)")
        
        isExporting = true
        isFrameProcessing = false
        anim.isPlaying = false // We control steps
        anim.currentFrame = 0  // Start from beginning
        
        // Setup Exporter
        let exporter = VideoExporter()
        do {
            try exporter.start(outputURL: url, width: width, height: height)
            self.videoExporter = exporter
        } catch {
            print("Failed to start exporter: \(error)")
            isExporting = false
            return
        }
        
        // Force redraw to start the loop
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.setNeedsDisplay(view.bounds)
    }
    
    func finishExport() {
        guard isExporting else { return }
        isExporting = false
        isFrameProcessing = false
        print("Export Finished. Finalizing video...")
        
        // Restore view state
        DispatchQueue.main.async {
             self.view?.isPaused = false
             self.view?.enableSetNeedsDisplay = false
        }
        
        Task {
            if let exporter = videoExporter {
                await exporter.finish()
                print("Video saved.")
            }
            videoExporter = nil
            exportTexture = nil
            
            // Restore?
            // anim.isPlaying = true // Optional
        }
    }
}

func length_sq(_ v: SIMD3<Float>) -> Float {
    return dot(v, v)
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}
func matrix_look_at_right_hand(eye: simd_float3, target: simd_float3, up: simd_float3) -> simd_float4x4 {
    let z = simd_normalize(eye - target)
    let x = simd_normalize(simd_cross(up, z))
    let y = simd_cross(z, x)
    return simd_float4x4(
        simd_float4(x.x, y.x, z.x, 0),
        simd_float4(x.y, y.y, z.y, 0),
        simd_float4(x.z, y.z, z.z, 0),
        simd_float4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
    )
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return simd_float4x4(
        simd_float4(xs, 0, 0, 0),
        simd_float4(0, ys, 0, 0),
        simd_float4(0, 0, zs, -1),
        simd_float4(0, 0, zs * nearZ, 0)
    )
}
