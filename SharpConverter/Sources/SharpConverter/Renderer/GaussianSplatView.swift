import SwiftUI
import MetalKit

struct GaussianSplatView: NSViewRepresentable {
    var url: URL?
    @Binding var fov: Double
    @Binding var moveSpeed: Double
    @Binding var enablePickToFocus: Bool
    @Binding var resetCameraTrigger: Bool
    @Binding var exportTrigger: Bool
    @Binding var exportURL: URL?
    @Binding var exportWidth: Int
    @Binding var exportHeight: Int
    var animationManager: AnimationManager?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSView {
// ...
// (No changes in makeNSView needed here, but keeping context correct)
// ...
        print("DEBUG: makeNSView called")
        let container = NSView()
        
        // Use custom interactive view
        let mtkView = InteractiveMTKView()
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = true // Enable static rendering
        mtkView.isPaused = true // Start paused
        
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            mtkView.device = metalDevice
        }
        
        container.addSubview(mtkView)
        NSLayoutConstraint.activate([
            mtkView.topAnchor.constraint(equalTo: container.topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            mtkView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        
        context.coordinator.renderer = MetalRenderer(metalKitView: mtkView)
        
        if let url = context.coordinator.parent.url {
            context.coordinator.renderer?.load(url: url)
            context.coordinator.lastLoadedURL = url
        }
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // print("DEBUG: updateNSView called. Frame: \(nsView.frame)")
        
        if let renderer = context.coordinator.renderer {
            renderer.camera.fov = Float(fov)
            renderer.moveSpeedMultiplier = Float(moveSpeed)
            renderer.enablePickToFocus = enablePickToFocus
            renderer.animationManager = animationManager // Pass manager
            
            // Setup Animation Redraw Callback
            animationManager?.onFrameChanged = { [weak renderer] in
                renderer?.view?.setNeedsDisplay(renderer?.view?.bounds ?? .zero)
            }
            
            renderer.view?.setNeedsDisplay(renderer.view?.bounds ?? .zero)
            
            if resetCameraTrigger {
                renderer.resetCamera()
                DispatchQueue.main.async {
                    resetCameraTrigger = false
                }
            }
            
            if exportTrigger, let url = exportURL {
                renderer.startExport(to: url)
                DispatchQueue.main.async {
                    exportTrigger = false
                }
            }
        }
        
        if let url = url, url != context.coordinator.lastLoadedURL {
            context.coordinator.renderer?.load(url: url)
            context.coordinator.lastLoadedURL = url
            
            // Try to grab focus when new content loads
            DispatchQueue.main.async {
                if let container = nsView as? NSView, let mtkView = container.subviews.first as? InteractiveMTKView {
                    mtkView.window?.makeFirstResponder(mtkView)
                }
            }
        }
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var parent: GaussianSplatView
        var renderer: MetalRenderer?
        var lastLoadedURL: URL?
        
        init(_ parent: GaussianSplatView) {
            self.parent = parent
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer?.mtkView(view, drawableSizeWillChange: size)
        }
        
        func draw(in view: MTKView) {
            renderer?.draw(in: view)
        }
    }
}

// Subclass to handle input events
class InteractiveMTKView: MTKView {
    
    private var isMouseDown = false
    private var activityTimer: Timer?
    
    override var acceptsFirstResponder: Bool { return true }
    
    private func updateRenderState() {
        guard let renderer = self.delegate as? MetalRenderer else { return }
        
        // Render if any key is pressed or mouse is down
        let shouldRender = !renderer.pressedKeys.isEmpty || isMouseDown
        
        // If we want to render, we unpause
        if shouldRender {
            self.isPaused = false
            activityTimer?.invalidate()
            activityTimer = nil
        } else {
            // If nothing is happening, pause immediately
            // (Or maybe wait a small delay to finish animations?)
            self.isPaused = true
        }
    }
    
    private func wakeUpRender(duration: TimeInterval = 0.5) {
        self.isPaused = false
        activityTimer?.invalidate()
        activityTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.updateRenderState()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        // Focus
        self.window?.makeFirstResponder(self)
        isMouseDown = true
        
        // Picking
        if let renderer = self.delegate as? MetalRenderer {
            // Only pick if enabled
            if renderer.enablePickToFocus {
                let localPoint = self.convert(event.locationInWindow, from: nil)
                let viewSize = SIMD2<Float>(Float(self.bounds.width), Float(self.bounds.height))
                let screenPoint = SIMD2<Float>(Float(localPoint.x), Float(localPoint.y))
                
                // Perform pick on background thread? Or main is fine since it's O(N) array scan.
                // 1M points ~ 10ms. Main thread is OK for responsiveness.
                renderer.pick(at: screenPoint, viewSize: viewSize)
            }
        }
        
        updateRenderState()
    }
    
    override func mouseUp(with event: NSEvent) {
        isMouseDown = false
        updateRenderState()
    }
    
    override func becomeFirstResponder() -> Bool {
        print("DEBUG: InteractiveMTKView became first responder")
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        print("DEBUG: InteractiveMTKView resigned first responder")
        return true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let renderer = self.delegate as? MetalRenderer else { return }
        
        let dx = Float(event.deltaX)
        let dy = Float(event.deltaY)
        
        // Left click rotate
        renderer.camera.rotate(dx: dx, dy: dy, speed: renderer.moveSpeedMultiplier)
    }
    
    override func rightMouseDragged(with event: NSEvent) {
         guard let renderer = self.delegate as? MetalRenderer else { return }
         let dx = Float(event.deltaX)
         let dy = Float(event.deltaY)
         renderer.camera.pan(dx: dx, dy: dy, speed: renderer.moveSpeedMultiplier)
    }
    
    override func otherMouseDragged(with event: NSEvent) {
        guard let renderer = self.delegate as? MetalRenderer else { return }
        let dx = Float(event.deltaX)
        let dy = Float(event.deltaY)
        renderer.camera.pan(dx: dx, dy: dy, speed: renderer.moveSpeedMultiplier)
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard let renderer = self.delegate as? MetalRenderer else { return }
        let delta = Float(event.scrollingDeltaY) * 0.01
        renderer.camera.zoom(delta: delta, speed: renderer.moveSpeedMultiplier)
        wakeUpRender(duration: 0.2)
    }
    
    override func magnify(with event: NSEvent) {
        guard let renderer = self.delegate as? MetalRenderer else { return }
        let delta = Float(event.magnification)
        renderer.camera.zoom(delta: delta, speed: renderer.moveSpeedMultiplier)
        wakeUpRender(duration: 0.2)
    }
    
    // Keyboard Handling
    override func keyDown(with event: NSEvent) {
        // print("DEBUG: KeyDown \(event.keyCode)")
        guard let renderer = self.delegate as? MetalRenderer else { return }
        
        // Add key to set (using keyCode)
        renderer.pressedKeys.insert(event.keyCode)
        updateRenderState()
    }
    
    override func keyUp(with event: NSEvent) {
        guard let renderer = self.delegate as? MetalRenderer else { return }
        
        // Remove key from set
        renderer.pressedKeys.remove(event.keyCode)
        updateRenderState()
    }
    
    override func flagsChanged(with event: NSEvent) {
        guard let renderer = self.delegate as? MetalRenderer else { return }
        
        // Check for Shift key
        renderer.isShiftPressed = event.modifierFlags.contains(.shift)
        wakeUpRender(duration: 0.1) // Just render a frame to be safe if anything depended on shift
    }
}
