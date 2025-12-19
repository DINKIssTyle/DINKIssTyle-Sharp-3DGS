import Foundation
import simd

struct GaussianSplat {
    var position: SIMD3<Float>
    var scale: SIMD3<Float>
    var color: SIMD4<Float> // RGB + Opacity
    var rotation: SIMD4<Float> // Quaternion (x, y, z, w)
}

class SplatLoader {
    struct Property {
        let name: String
        let type: DataType
        let offset: Int
    }
    
    enum DataType {
        case float, double, int, uint, short, ushort, char, uchar
        
        var size: Int {
            switch self {
            case .float, .int, .uint: return 4
            case .double: return 8
            case .short, .ushort: return 2
            case .char, .uchar: return 1
            }
        }
    }

    static func load(from url: URL) throws -> [GaussianSplat] {
        let data = try Data(contentsOf: url)
        
        guard let markerRange = data.range(of: "end_header".data(using: .utf8)!) else {
             throw NSError(domain: "SplatLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid PLY Header"])
        }
        
        var offset = markerRange.upperBound
        if offset < data.count {
            if data[offset] == 0x0D { offset += 1; if offset < data.count && data[offset] == 0x0A { offset += 1 } }
            else if data[offset] == 0x0A { offset += 1 }
        }
        
        // Parse Header
        let headerData = data.subdata(in: 0..<markerRange.lowerBound)
        let headerString = String(decoding: headerData, as: UTF8.self)
        let lines = headerString.components(separatedBy: "\n")
        
        var vertexCount = 0
        var properties: [Property] = []
        var currentStride = 0
        var isLittleEndian = true
        var inVertexElement = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("format") {
                if trimmed.contains("binary_big_endian") { isLittleEndian = false }
            }
            if trimmed.hasPrefix("element") {
                if trimmed.hasPrefix("element vertex") {
                    inVertexElement = true
                    let parts = trimmed.components(separatedBy: " ")
                    if let count = Int(parts.last ?? "") { vertexCount = count }
                } else {
                    inVertexElement = false
                }
            }
            if inVertexElement && trimmed.hasPrefix("property") {
                let parts = trimmed.components(separatedBy: " ")
                // Format: property <type> <name>
                if parts.count >= 3 {
                    let typeStr = parts[1]
                    let name = parts[2]
                    var type: DataType = .float
                    
                    switch typeStr {
                    case "float", "float32": type = .float
                    case "double", "float64": type = .double
                    case "int", "int32": type = .int
                    case "uint", "uint32": type = .uint
                    case "short", "int16": type = .short
                    case "ushort", "uint16": type = .ushort
                    case "char", "int8": type = .char
                    case "uchar", "uint8": type = .uchar
                    default: continue // Skip unknown types
                    }
                    
                    properties.append(Property(name: name, type: type, offset: currentStride))
                    currentStride += type.size
                }
            }
        }
        
        let expectedSize = offset + (vertexCount * currentStride)
        print("DEBUG: Header Info - Offset: \(offset), VertexCount: \(vertexCount), Stride: \(currentStride), Endian: \(isLittleEndian ? "Little" : "Big")")
        print("DEBUG: File Size: \(data.count), Expected Body Size: \(vertexCount * currentStride)")
        
        if data.count < expectedSize {
             print("WARNING: File is smaller than expected! Missing \(expectedSize - data.count) bytes.")
        } else {
             print("DEBUG: File size check OK. (Extra bytes: \(data.count - expectedSize))")
        }
        
        // Property Mapping
        func getProp(_ name: String) -> Property? { properties.first { $0.name == name } }
        
        let p_x = getProp("x"); let p_y = getProp("y"); let p_z = getProp("z")
        let p_sx = getProp("scale_0"); let p_sy = getProp("scale_1"); let p_sz = getProp("scale_2")
        let p_r0 = getProp("rot_0"); let p_r1 = getProp("rot_1"); let p_r2 = getProp("rot_2"); let p_r3 = getProp("rot_3")
        let p_opac = getProp("opacity")
        let p_dc0 = getProp("f_dc_0"); let p_dc1 = getProp("f_dc_1"); let p_dc2 = getProp("f_dc_2")
        // Support standard color names too
        let p_red = getProp("red"); let p_green = getProp("green"); let p_blue = getProp("blue")
        
        var splats: [GaussianSplat] = []
        splats.reserveCapacity(vertexCount)
        
        try data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            guard let baseAddr = ptr.baseAddress else { return }
            var currentPtr = baseAddr + offset
            
            // Helper to read unaligned value
            func readUnaligned<T>(_ ptr: UnsafeRawPointer, as type: T.Type) -> T where T: Numeric {
                 var val: T = 0
                 withUnsafeMutableBytes(of: &val) { valBuf in
                     valBuf.copyBytes(from: UnsafeRawBufferPointer(start: ptr, count: MemoryLayout<T>.size))
                 }
                 return val
            }

            // Helper to read value as Float
            func readFloat(_ p: Property?, _ ptr: UnsafeRawPointer) -> Float {
                guard let p = p else { return 0 }
                let valPtr = ptr + p.offset
                switch p.type {
                case .float: return readUnaligned(valPtr, as: Float.self)
                case .uchar: return Float(readUnaligned(valPtr, as: UInt8.self)) / 255.0
                case .char: return Float(readUnaligned(valPtr, as: Int8.self)) / 127.0
                case .ushort: return Float(readUnaligned(valPtr, as: UInt16.self)) / 65535.0
                case .short: return Float(readUnaligned(valPtr, as: Int16.self)) / 32767.0
                case .double: return Float(readUnaligned(valPtr, as: Double.self))
                default: return 0 // Implement others if needed
                }
            }
            // Helper for non-normalized read (e.g. position, scale)
            func readVal(_ p: Property?, _ ptr: UnsafeRawPointer) -> Float {
                guard let p = p else { return 0 }
                let valPtr = ptr + p.offset
                switch p.type {
                case .float: return readUnaligned(valPtr, as: Float.self)
                case .double: return Float(readUnaligned(valPtr, as: Double.self))
                case .uchar: return Float(readUnaligned(valPtr, as: UInt8.self))
                // ... others
                default: return 0
                }
            }

            for _ in 0..<vertexCount {
                if currentPtr + currentStride > baseAddr + data.count { break }
                
                let x = readVal(p_x, currentPtr)
                let y = readVal(p_y, currentPtr)
                let z = readVal(p_z, currentPtr)
                
                let opac = readVal(p_opac, currentPtr)
                
                var r: Float = 0
                var g: Float = 0
                var b: Float = 0
                
                // Color: Prefer f_dc (SH) but fallback to red/green/blue (uchar)
                if let _ = p_dc0 {
                    let dc0 = readVal(p_dc0, currentPtr)
                    let dc1 = readVal(p_dc1, currentPtr)
                    let dc2 = readVal(p_dc2, currentPtr)
                    r = 0.5 + 0.28209 * dc0
                    g = 0.5 + 0.28209 * dc1
                    b = 0.5 + 0.28209 * dc2
                } else if let _ = p_red {
                    r = readFloat(p_red, currentPtr) // Normalized 0-1
                    g = readFloat(p_green, currentPtr)
                    b = readFloat(p_blue, currentPtr)
                }
                
                let s0 = exp(readVal(p_sx, currentPtr))
                let s1 = exp(readVal(p_sy, currentPtr))
                let s2 = exp(readVal(p_sz, currentPtr))
                
                let r0 = readVal(p_r0, currentPtr)
                let r1 = readVal(p_r1, currentPtr)
                let r2 = readVal(p_r2, currentPtr)
                let r3 = readVal(p_r3, currentPtr)

                splats.append(GaussianSplat(
                    position: SIMD3<Float>(x, y, z),
                    scale: SIMD3<Float>(s0, s1, s2),
                    color: SIMD4<Float>(max(0, min(1, r)), max(0, min(1, g)), max(0, min(1, b)), 1.0 / (1.0 + exp(-opac))),
                    rotation: SIMD4<Float>(r0, r1, r2, r3)
                ))
                
                currentPtr += currentStride
            }
        }
        
        print("Loaded \(splats.count) splats from PLY")
        return splats
    }
}
