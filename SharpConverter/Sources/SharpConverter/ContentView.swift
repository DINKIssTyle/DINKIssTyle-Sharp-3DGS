import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var appState = AppState()
    @State private var showAbout = false
    
    // Viewer Settings
    @State private var currentFov: Double = 45.0
    @State private var currentSpeed: Double = 0.5
    @State private var enablePickToFocus: Bool = true
    @State private var resetCameraTrigger: Bool = false
    @State private var showTimeline: Bool = false
    @State private var exportTrigger: Bool = false
    @State private var exportURL: URL?
    @State private var showExportSettings: Bool = false
    @State private var exportWidth: Int = 1920
    @State private var exportHeight: Int = 1080
    @State private var exportFPS: Int = 60
    @StateObject private var animationManager = AnimationManager()
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
            // Top Bar
            HStack {
                // Setup Status
                Button(action: {
                    appState.runSetup()
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.isSetupComplete ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(appState.isSetupComplete ? "Ready" : "Setup Required")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
                .disabled(appState.isSetupComplete || appState.isSetupRunning)
                .padding(.leading)
                
                Spacer()
                
                // About Button
                Button(action: {
                    showAbout = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("About Sharp Swift")
                .padding(.trailing, 8)
                
                // Open Button
                Button("Open Image / PLY") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canCreateDirectories = false
                    panel.allowedContentTypes = [UTType.image, UTType(filenameExtension: "ply")!]
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        handleFile(url)
                    }
                }
                .padding(.trailing)
            }
            .frame(height: 44)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Main Content / Viewer Area
            ZStack {
                Color(NSColor.controlBackgroundColor)
                
                // Drop Zone / Idle State
                VStack(spacing: 16) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("Drag & Drop Image or .ply")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    if let ply = appState.currentPlyPath {
                        VStack(spacing: 8) {
                            Text("Last Generated: \(URL(fileURLWithPath: ply).lastPathComponent)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("Open Viewer Again") {
                                appState.launchViewer()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Processing Overlay
                if appState.isProcessing || appState.isSetupRunning {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        
                        Text(appState.isSetupRunning ? "Setting up Environment..." : "Converting Image to 3D Model...")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(appState.isSetupRunning ? "This may take a few minutes." : "Please wait...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(40)
                    .background(Material.ultraThin)
                    .cornerRadius(16)
                    .shadow(radius: 20)
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                providers.first?.loadDataRepresentation(forTypeIdentifier: "public.file-url", completionHandler: { data, error in
                    if let data = data, let path = String(data: data, encoding: .utf8), let url = URL(string: path) {
                         DispatchQueue.main.async {
                             handleFile(url)
                         }
                    }
                })
                return true
            }
        }
        .onAppear {
            appState.checkSetup()
        }
        
        // Viewer Overlay
        if appState.showViewer {
            ZStack(alignment: .top) {
                if let plyPath = appState.currentPlyPath {
                    GaussianSplatView(url: URL(fileURLWithPath: plyPath), 
                                      fov: $currentFov, 
                                      moveSpeed: $currentSpeed, 
                                      enablePickToFocus: $enablePickToFocus, 
                                      resetCameraTrigger: $resetCameraTrigger,
                                      exportTrigger: $exportTrigger,
                                      exportURL: $exportURL,
                                      exportWidth: $exportWidth,
                                      exportHeight: $exportHeight,
                                      animationManager: animationManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                     Text("Error: No PLY Path")
                }
                
                // Top HUD Toolbar
                HStack(spacing: 20) {
                    // Close Button
                    Button(action: {
                        appState.showViewer = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Reset Camera Button
                    Button(action: {
                        resetCameraTrigger = true
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.white)
                            .help("Reset Camera View")
                    }
                    .buttonStyle(.plain)
                    
                    // Pick Focus Toggle
                    Button(action: {
                        enablePickToFocus.toggle()
                    }) {
                        Image(systemName: enablePickToFocus ? "scope" : "scope") // Maybe change icon or just color
                            .foregroundColor(enablePickToFocus ? .yellow : .white.opacity(0.5))
                            .help(enablePickToFocus ? "Click-to-Focus Enabled" : "Click-to-Focus Disabled")
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Timeline Toggle
                    Button(action: {
                        showTimeline.toggle()
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(showTimeline ? .blue : .white)
                            .help("Show/Hide Timeline")
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Speed Control
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .foregroundColor(.white)
                            .help("Movement Speed")
                        
                        Slider(value: $currentSpeed, in: 0.1...3.0)
                            .frame(width: 100)
                        
                        Text(String(format: "%.1fx", currentSpeed))
                            .font(.monospacedDigit(.caption)())
                            .foregroundColor(.white)
                            .frame(width: 35, alignment: .leading)
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // FOV Control
                    HStack(spacing: 8) {
                        Image(systemName: "eye")
                            .foregroundColor(.white)
                            .help("Field of View")
                        
                        Slider(value: $currentFov, in: 30...110)
                            .frame(width: 100)
                        
                        Text("\(Int(currentFov))°")
                            .font(.monospacedDigit(.caption)())
                            .foregroundColor(.white)
                            .frame(width: 30, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Material.ultraThin)
                .cornerRadius(12)
                .padding(.top, 10)
                .shadow(radius: 5)
                
                // Bottom Timeline Panel
                if showTimeline {
                    VStack {
                        Spacer()
                        TimelineView(animationManager: animationManager, onAddKeyframe: {
                             animationManager.captureKeyframeTrigger = true
                        }, onExport: {
                             // Trigger Save Panel directly
                             let panel = NSSavePanel()
                             panel.allowedContentTypes = [.mpeg4Movie]
                             panel.canCreateDirectories = true
                             panel.nameFieldStringValue = "animation.mp4"
                             
                             if panel.runModal() == .OK, let url = panel.url {
                                 exportURL = url
                                 exportTrigger = true
                             }
                        })
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            .transition(.move(edge: .bottom))
        }
    }
    .sheet(isPresented: $showAbout) {
        AboutView(isPresented: $showAbout)
    }
    }
    
    func handleFile(_ url: URL) {
        if url.pathExtension.lowercased() == "ply" {
            // Direct launch
            appState.currentPlyPath = url.path
            appState.launchViewer()
        } else {
            // Assume Image -> Convert
            appState.processImage(imagePath: url.path)
        }
    }
}

struct AboutView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            if let iconPath = Bundle.module.path(forResource: "icon", ofType: "png", inDirectory: "Resources"),
               let nsImage = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 80, height: 80)
            } else {
                 Image(systemName: "app.dashed")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 4) {
                Text("Sharp Swift")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version 1.0.1")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 6) {
                 Text("(C) 2025 DINKI'ssTyle")
                     .fontWeight(.medium)
            }
            .multilineTextAlignment(.center)

            
            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top)
        }
        .padding(30)
    }
}
