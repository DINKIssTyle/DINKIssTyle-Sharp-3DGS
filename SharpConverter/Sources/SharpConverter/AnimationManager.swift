import SwiftUI
import Combine
import simd

struct Keyframe: Identifiable, Codable {
    var id = UUID()
    var frame: Int
    var position: SIMD3<Float>
    var target: SIMD3<Float>
    var up: SIMD3<Float>
}

class AnimationManager: ObservableObject {
    @Published var keyframes: [Keyframe] = []
    @Published var currentFrame: Int = 0
    @Published var totalFrames: Int = 300
    @Published var fps: Int = 30
    @Published var exportHeight: Int = 720 // Default resolution height (p)
    @Published var isPlaying: Bool = false
    @Published var captureKeyframeTrigger: Bool = false { // Trigger to capture current camera state
        didSet {
            if captureKeyframeTrigger {
                onFrameChanged?()
            }
        }
    }
    
    var onFrameChanged: (() -> Void)? // Callback for redraw
    
    // Playback
    private var timer: AnyCancellable?
    
    // Sort keyframes by frame index
    func sortKeyframes() {
        keyframes.sort { $0.frame < $1.frame }
    }
    
    func addKeyframe(frame: Int, camera: Camera) {
        // Remove existing keyframe at this frame if any
        keyframes.removeAll { $0.frame == frame }
        
        let kf = Keyframe(frame: frame, position: camera.position, target: camera.target, up: camera.up)
        keyframes.append(kf)
        sortKeyframes()
    }
    
    func removeKeyframe(at frame: Int) {
        keyframes.removeAll { $0.frame == frame }
    }
    
    func togglePlay() {
        isPlaying.toggle()
        if isPlaying {
            startPlayback()
        } else {
            stopPlayback()
        }
    }
    
    func startPlayback() {
        timer?.cancel()
        timer = Timer.publish(every: 1.0 / Double(fps), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.currentFrame < self.totalFrames {
                    self.currentFrame += 1
                } else {
                    self.currentFrame = 0 
                }
                self.onFrameChanged?()
            }
    }
    
    func stopPlayback() {
        timer?.cancel()
        isPlaying = false
    }
    
    func resetAllKeyframes() {
        keyframes.removeAll()
        currentFrame = 0
    }
    
    @Published var isScrubbing: Bool = false
    
    // Interpolate Camera State
    func getCameraState(for frame: Int) -> (position: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>)? {
        guard !keyframes.isEmpty else { return nil }
        
        // Find surrounding keyframes
        // previous KF <= frame
        // next KF > frame
        
        // 1. Exact match
        if let match = keyframes.first(where: { $0.frame == frame }) {
            return (match.position, match.target, match.up)
        }
        
        // 2. Before first
        if let first = keyframes.first, frame < first.frame {
             return (first.position, first.target, first.up)
        }
        
        // 3. After last
        if let last = keyframes.last, frame > last.frame {
            return (last.position, last.target, last.up)
        }
        
        // 4. Interpolate
        var prev: Keyframe?
        var next: Keyframe?
        
        for kf in keyframes {
            if kf.frame < frame {
                prev = kf
            } else if kf.frame > frame {
                next = kf
                break // Found the immediate next
            }
        }
        
        if let p = prev, let n = next {
            let t = Float(frame - p.frame) / Float(n.frame - p.frame)
            
            // Linear Interpolation for vectors
            let pos = mix(p.position, n.position, t: t)
            let tgt = mix(p.target, n.target, t: t)
            let up = mix(p.up, n.up, t: t) // Should ideally be slerp-like for up vector, but mix is ok for small changes
            
            return (pos, tgt, simd_normalize(up))
        }
        
        return nil
    }
}

// SIMD mix helper
func mix(_ x: SIMD3<Float>, _ y: SIMD3<Float>, t: Float) -> SIMD3<Float> {
    return x + (y - x) * t
}
