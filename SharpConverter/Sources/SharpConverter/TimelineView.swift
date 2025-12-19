import SwiftUI

struct TimelineView: View {
    @ObservedObject var animationManager: AnimationManager
    // Callback to capture current camera state
    var onAddKeyframe: () -> Void
    var onExport: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            // Controls Row
            ZStack(alignment: .center) {
                // Background Layer: Left and Right Controls
                HStack {
                    // Left: Keyframe Controls & Playback
                    HStack(spacing: 12) {
                        Button(action: onAddKeyframe) {
                            VStack(spacing: 2) {
                                Image(systemName: "plus.diamond.fill")
                                Text("Add Key")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Add Keyframe at current frame")
                        
                        Button(action: {
                            animationManager.removeKeyframe(at: animationManager.currentFrame)
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "minus.diamond")
                                Text("Del Key")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Remove Keyframe at current frame")
                        .disabled(animationManager.keyframes.first(where: { $0.frame == animationManager.currentFrame }) == nil)
                        
                        Button(action: {
                            animationManager.resetAllKeyframes()
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                Text("Reset")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Remove All Keyframes")
                        
                        Divider().frame(height: 30)
                        
                        // Playback Controls (Moved Left)
                        HStack(spacing: 16) {
                            Button(action: {
                                animationManager.currentFrame = 0
                            }) {
                                Image(systemName: "backward.end.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                animationManager.togglePlay()
                            }) {
                                Image(systemName: animationManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 4)
                    }
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    // Right: Settings & Export
                    HStack(spacing: 12) {
                        // Resolution Menu
                        Menu {
                            Button("360p") { animationManager.exportHeight = 360 }
                            Button("480p") { animationManager.exportHeight = 480 }
                            Button("720p") { animationManager.exportHeight = 720 }
                            Button("1080p") { animationManager.exportHeight = 1080 }
                            Button("2160p (4K)") { animationManager.exportHeight = 2160 }
                        } label: {
                            Text("\(animationManager.exportHeight, format: .number.grouping(.never))p")
                                .font(.caption).bold()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                        }
                        .menuStyle(.borderlessButton)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                        .fixedSize()
                        
                        // FPS Menu
                        Menu {
                            Button("24 FPS") { animationManager.fps = 24 }
                            Button("30 FPS") { animationManager.fps = 30 }
                            Button("60 FPS") { animationManager.fps = 60 }
                        } label: {
                            Text("\(animationManager.fps) FPS")
                                .font(.caption).bold()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                        }
                        .menuStyle(.borderlessButton)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                        .fixedSize()
                        
                        Button(action: onExport) {
                            HStack(spacing: 4) {
                                Image(systemName: "film")
                                Text("Export")
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
                
                // Foreground Layer: Frame Counter (Centered in ZStack)
                HStack(spacing: 0) {
                    Text(String(format: "%03d", animationManager.currentFrame))
                        .font(.monospacedDigit(.body)())
                        .foregroundColor(.secondary)
                        .fixedSize()
                    
                    Text(" / ")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    TextField("Total", value: Binding(
                        get: { animationManager.totalFrames },
                        set: { animationManager.totalFrames = min($0, 999) }
                    ), formatter: {
                        let f = NumberFormatter()
                        f.usesGroupingSeparator = false
                        f.minimumIntegerDigits = 3
                        return f
                    }())
                        .textFieldStyle(.plain)
                        .font(.monospacedDigit(.body)())
                        .frame(width: 35) // Fixed width for 3 digits
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 16)
                .background(Color.black.opacity(0.2))
                .cornerRadius(4)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Timeline Slider / Scrubber
            ZStack {
                // Background Track & Markers
                GeometryReader { geo in
                    let trackWidth = geo.size.width - 12 // Adjust for hypothetical slider thumb inset
                    let xOffset: CGFloat = 6 // Half thumb width approx
                    
                    ZStack(alignment: .leading) {
                         Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)
                            .cornerRadius(2)
                            .padding(.horizontal, 6) // Match slider inset
                         
                         ForEach(animationManager.keyframes) { kf in
                             Circle()
                                 .fill(Color.orange) // Highlight Keyframes
                                 .frame(width: 8, height: 8)
                                 .position(
                                    x: xOffset + (CGFloat(kf.frame) / CGFloat(max(1, animationManager.totalFrames))) * trackWidth,
                                    y: geo.size.height / 2
                                 )
                         }
                    }
                }
                .frame(height: 20) // Match slider height hint
                
                Slider(value: Binding(
                    get: { Double(animationManager.currentFrame) },
                    set: { 
                        animationManager.currentFrame = Int($0)
                        animationManager.onFrameChanged?()
                    }
                ), in: 0...Double(animationManager.totalFrames), onEditingChanged: { editing in
                    animationManager.isScrubbing = editing
                    if editing {
                        animationManager.stopPlayback() // Pause if scrubbing starts
                    }
                }) {
                    EmptyView()
                }
                .accentColor(.blue)
            }
            .frame(height: 20)
            .padding(.horizontal, 10) // Outer padding for easy grabbing
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Material.regular) // Glassy background
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom)
    }
}
