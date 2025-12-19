import AVFoundation
import Metal

class VideoExporter {
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var size: CGSize = .zero
    
    func start(outputURL: URL, width: Int, height: Int) throws {
        self.size = CGSize(width: width, height: height)
        
        // Remove existing file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        assetWriterInput?.expectsMediaDataInRealTime = false
        
        if assetWriter!.canAdd(assetWriterInput!) {
            assetWriter!.add(assetWriterInput!)
        } else {
             print("VideoExporter: Cannot add input to writer")
             throw NSError(domain: "VideoExporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add input"])
        }
        
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        if assetWriter!.startWriting() {
            assetWriter!.startSession(atSourceTime: .zero)
            print("VideoExporter: Started writing session")
        } else {
            print("VideoExporter: Failed to start writing. Error: \(String(describing: assetWriter?.error))")
            throw assetWriter?.error ?? NSError(domain: "VideoExporter", code: -1, userInfo: nil)
        }
    }
    
    func append(texture: MTLTexture, time: TimeInterval) async throws {
        guard let input = assetWriterInput, let adaptor = adaptor else { 
            print("VideoExporter: Input or Adaptor missing")
            return 
        }
        
        var waitCount = 0
        while !input.isReadyForMoreMediaData {
             if waitCount % 10 == 0 {
                 print("VideoExporter: Waiting for input ready... Status: \(String(describing: assetWriter?.status.rawValue)) Error: \(String(describing: assetWriter?.error))")
             }
             waitCount += 1
             
             if assetWriter?.status == .failed {
                 throw assetWriter?.error ?? NSError(domain: "VideoExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "AssetWriter failed"])
             }
             
             try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        print("VideoExporter: Input Ready. Making Pixel Buffer...")
        if let pixelBuffer = makePixelBuffer(from: texture) {
            print("VideoExporter: Buffer Created. Appending at \(time)...")
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            if !adaptor.append(pixelBuffer, withPresentationTime: cmTime) {
                print("Failed to append buffer: \(String(describing: assetWriter?.error))")
            } else {
                print("VideoExporter: Appended frame at \(time)")
            }
        } else {
            print("VideoExporter: Failed to make pixel buffer")
        }
    }
    
    func finish() async {
        assetWriterInput?.markAsFinished()
        await assetWriter?.finishWriting() 
    }
    
    private func makePixelBuffer(from texture: MTLTexture) -> CVPixelBuffer? {
        // Assume texture is BGRA8Unorm
        // We need to copy bytes from texture to CVPixelBuffer
        
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let pixelData = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let region = MTLRegionMake2D(0, 0, Int(size.width), Int(size.height))
        
        texture.getBytes(pixelData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        return buffer
    }
}
