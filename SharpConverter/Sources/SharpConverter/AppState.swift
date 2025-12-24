import Foundation
import AppKit

class AppState: ObservableObject {
    @Published var isSetupComplete: Bool = false
    @Published var isSetupRunning: Bool = false
    @Published var isProcessing: Bool = false
    @Published var canView: Bool = false
    @Published var currentPlyPath: String? = nil
    @Published var showViewer: Bool = false
    @Published var setupRunner = ProcessRunner()
    @Published var processRunner = ProcessRunner()
    
    // Paths
    var rootDir: String {
        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0]
        
        let sharpSwiftURL = docDir.appendingPathComponent("Sharp Swift")
        let sharpBrushURL = docDir.appendingPathComponent("Sharp Brush")
        
        // 1. If Sharp Swift already exists, use it
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: sharpSwiftURL.path, isDirectory: &isDir) && isDir.boolValue {
            return sharpSwiftURL.path
        }
        
        // 2. Check for potential migration from Sharp Brush
        if fileManager.fileExists(atPath: sharpBrushURL.path, isDirectory: &isDir) && isDir.boolValue {
            let hasMlSharp = fileManager.fileExists(atPath: sharpBrushURL.appendingPathComponent("ml-sharp").path)
            let hasModels = fileManager.fileExists(atPath: sharpBrushURL.appendingPathComponent("models").path)
            
            if hasMlSharp && hasModels {
                // Perform Migration
                do {
                    print("Migrating 'Sharp Brush' to 'Sharp Swift'...")
                    try fileManager.moveItem(at: sharpBrushURL, to: sharpSwiftURL)
                    return sharpSwiftURL.path
                } catch {
                    print("Failed to migrate folder: \(error)")
                }
            }
        }
        
        // 3. Fallback: Create/Use Sharp Swift
        try? fileManager.createDirectory(at: sharpSwiftURL, withIntermediateDirectories: true, attributes: nil)
        return sharpSwiftURL.path
    }
    
    var venvPath: String { "\(rootDir)/.venv" }
    var mlSharpPath: String { "\(rootDir)/ml-sharp" }
    var binPath: String { "\(rootDir)/bin" }
    
    // We expect the brush binary to be bundled inside the App bundle
    // checking Bundle.module (for SwiftPM) or Bundle.main
    var brushBinPath: String {
        // 1. Check Bundle.main (safest for App Bundles)
        // If the binary was copied directly to Resources (common in App builds)
        if let mainPath = Bundle.main.path(forResource: "brush", ofType: nil) {
            return mainPath
        }

        // 2. Check Documents/Sharp Swift/bin/brush (User/Setup created)
        let docPath = "\(binPath)/brush"
        if FileManager.default.fileExists(atPath: docPath) {
            return docPath
        }
        
        // 3. Manually check for SwiftPM resource bundle without using Bundle.module (which crashes if missing)
        // The bundle name is usually "PackageName_TargetName.bundle"
        let bundleName = "SharpConverter_SharpConverter"
        
        // Check inside Bundle.main.resourceURL
        if let resourceURL = Bundle.main.resourceURL {
            let bundleURL = resourceURL.appendingPathComponent(bundleName).appendingPathExtension("bundle")
            if let bundle = Bundle(url: bundleURL),
               let bundledPath = bundle.path(forResource: "brush", ofType: nil, inDirectory: "Resources") {
                return bundledPath
            }
        }
         
        // Check for "brush" directly in the standard Resources directory of the main bundle
        // (Sometimes SwiftPM copies resources to the root of Resources in the app bundle)
        if let resourceURL = Bundle.main.resourceURL {
             let directPath = resourceURL.appendingPathComponent("brush").path
             if FileManager.default.fileExists(atPath: directPath) {
                 return directPath
             }
        }

        // 4. Fallback (Return Documents path so validation fails gracefully instead of crashing)
        return docPath
    }
    
    func checkSetup() {
        let pythonPath = "\(venvPath)/bin/python"
        let hasVenv = FileManager.default.fileExists(atPath: pythonPath)
        // Check for model file
        let modelPath = "\(rootDir)/models/sharp_2572gikvuh.pt"
        let hasModel = FileManager.default.fileExists(atPath: modelPath)
        
        // Check for brush binary
        // SKIP for Native Port: We don't strictly need the rust binary anymore
        // let brushPath = self.brushBinPath 
        // let hasBrush = FileManager.default.fileExists(atPath: brushPath)
        
        DispatchQueue.main.async {
            self.isSetupComplete = hasVenv && hasModel // && hasBrush
        }
    }
    
    func runSetup() {
        Task {
            await MainActor.run { 
                self.isSetupRunning = true 
                // Clear previous logs to show fresh start
                self.setupRunner.logs = ""
            }
            
            do {
                self.setupRunner.log("Starting Setup...")
                
                // Create directories
                try? FileManager.default.createDirectory(atPath: "\(rootDir)/models", withIntermediateDirectories: true, attributes: nil)
                try? FileManager.default.createDirectory(atPath: "\(rootDir)/bin", withIntermediateDirectories: true, attributes: nil)

                // 1. Download Model
                let modelPath = "\(rootDir)/models/sharp_2572gikvuh.pt"
                if !FileManager.default.fileExists(atPath: modelPath) {
                    self.setupRunner.log("Downloading Model...")
                     try await self.setupRunner.runCommand("/usr/bin/curl", arguments: ["-o", modelPath, "https://ml-site.cdn-apple.com/models/sharp/sharp_2572gikvuh.pt"])
                }
                
                // 2. Build Brush Viewer (Optional: Only if source exists)
                let brushSourceStart = "/Users/dinki/Documents/GitHub/DINKIssTyle-Sharp-3DGS/brush"
                let brushBinDest = "\(binPath)/brush"
                
                if FileManager.default.fileExists(atPath: brushSourceStart) {
                    if !FileManager.default.fileExists(atPath: brushBinDest) {
                        self.setupRunner.log("Building Brush Viewer from source...")
                        // We need to find cargo. It's likely in ~/.cargo/bin/cargo
                        let cargoPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cargo/bin/cargo"
                        
                        if FileManager.default.fileExists(atPath: cargoPath) {
                            // Build command: cargo build --release --no-default-features --bin brush
                            // Running in the brush source directory
                             try await self.setupRunner.runCommand(cargoPath, arguments: ["build", "--release", "--no-default-features", "--bin", "brush"], currentDirectoryPath: brushSourceStart)
                             
                             // Copy binary
                             let sourceBin = "\(brushSourceStart)/target/release/brush"
                             if FileManager.default.fileExists(atPath: sourceBin) {
                                 if FileManager.default.fileExists(atPath: brushBinDest) {
                                     try FileManager.default.removeItem(atPath: brushBinDest)
                                 }
                                 try FileManager.default.copyItem(atPath: sourceBin, toPath: brushBinDest)
                                 self.setupRunner.log("Brush Viewer built and installed successfully.")
                             } else {
                                 self.setupRunner.log("Build failed: Binary not found at \(sourceBin)")
                                 // Don't throw, just log warning as it's optional
                             }
                        } else {
                            self.setupRunner.log("Cargo not found at \(cargoPath). Skipping Brush build.")
                        }
                    }
                } else {
                    self.setupRunner.log("Brush source not found at \(brushSourceStart). Skipping build.")
                }

                // 3. Venv
                let pythonBin = "\(venvPath)/bin/python"
                let reqTxt = "\(venvPath)/pyvenv.cfg" 
                
                // Effective Python Search (3.13 down to 3.11)
                let candidates = [
                    "/opt/homebrew/bin/python3.13",
                    "/usr/local/bin/python3.13",
                    "/opt/homebrew/bin/python3.12",
                    "/usr/local/bin/python3.12",
                    "/opt/homebrew/bin/python3.11",
                    "/usr/local/bin/python3.11",
                    "/opt/homebrew/bin/python3", // Fallback to brew default
                ]
                
                var chosenPython = "/usr/bin/python3" // Last resort (likely 3.9 on macOS)
                for cand in candidates {
                    if FileManager.default.fileExists(atPath: cand) {
                        chosenPython = cand
                        break
                    }
                }
                
                self.setupRunner.log("Selected Python: \(chosenPython)")
                
                // If venv doesn't exist OR if we want to force re-creation (maybe check version?)
                if FileManager.default.fileExists(atPath: venvPath) {
                     self.setupRunner.log("Removing existing venv to ensure correct Python version...")
                     try? FileManager.default.removeItem(atPath: venvPath)
                }
                
                if !FileManager.default.fileExists(atPath: pythonBin) {
                   self.setupRunner.log("Creating venv with \(chosenPython)...")
                   try await self.setupRunner.runCommand(chosenPython, arguments: ["-m", "venv", venvPath])
                }
                
                // 4. Install Dependencies
                self.setupRunner.log("Installing Dependencies...")
                 try await self.setupRunner.runCommand(pythonBin, arguments: ["-m", "ensurepip"])
                 try await self.setupRunner.runCommand(pythonBin, arguments: ["-m", "pip", "install", "--upgrade", "pip"])
                 
                let mlSharpPath = "\(rootDir)/ml-sharp"
                if !FileManager.default.fileExists(atPath: mlSharpPath) {
                     self.setupRunner.log("Cloning ml-sharp...")
                     try await self.setupRunner.runCommand("/usr/bin/git", arguments: ["clone", "https://github.com/apple/ml-sharp.git", mlSharpPath])
                }
                
                 try await self.setupRunner.runCommand(pythonBin, arguments: ["-m", "pip", "install", "."], currentDirectoryPath: mlSharpPath)
                
                self.setupRunner.log("Setup Complete!")
                checkSetup()
                
            } catch {
                self.setupRunner.log("Setup Failed: \(error)")
            }
            
            await MainActor.run { self.isSetupRunning = false }
        }
    }
    
    func processImage(imagePath: String) {
        Task {
            DispatchQueue.main.async {
                self.isProcessing = true
                self.processRunner.log("Processing \(imagePath)...")
            }
            
            do {
                let outDir = "\(rootDir)/output"
                try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true, attributes: nil)
                
                let pythonBin = "\(venvPath)/bin/python"
                let sharpScript = "\(venvPath)/bin/sharp" 
                
                // Construct args
                var args = ["predict", "-i", imagePath, "-o", outDir]
                let modelPath = "\(rootDir)/models/sharp_2572gikvuh.pt"
                if FileManager.default.fileExists(atPath: modelPath) {
                    args.append(contentsOf: ["-c", modelPath])
                }
                
                // Explicitly use MPS (Apple Silicon GPU)
                args.append(contentsOf: ["--device", "mps"])
                
                // If sharp binary script exists, use it. Otherwise use python -m sharp
                if FileManager.default.fileExists(atPath: sharpScript) {
                    try await self.processRunner.runCommand(sharpScript, arguments: args)
                } else {
                    self.processRunner.log("Sharp binary not found in venv")
                    throw NSError(domain: "App", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sharp binary not found in venv"])
                }
                
                // Find PLY (Get the most recent one)
                let fileManager = FileManager.default
                let files = try fileManager.contentsOfDirectory(atPath: outDir)
                
                // Filter for .ply files and find the most recently modified one
                let plyFile = files
                    .filter { $0.hasSuffix(".ply") }
                    .max { f1, f2 in
                        let p1 = "\(outDir)/\(f1)"
                        let p2 = "\(outDir)/\(f2)"
                        let d1 = (try? fileManager.attributesOfItem(atPath: p1)[.modificationDate] as? Date) ?? Date.distantPast
                        let d2 = (try? fileManager.attributesOfItem(atPath: p2)[.modificationDate] as? Date) ?? Date.distantPast
                        return d1 < d2
                    }
                
                if let plyFile = plyFile {
                    let fullPath = "\(outDir)/\(plyFile)"
                    
                    // Post-process PLY to fix orientation (negate X and Y coordinates)
                    self.processRunner.log("Fixing PLY orientation...")
                    self.fixPlyOrientation(at: fullPath)
                    
                    DispatchQueue.main.async {
                        self.currentPlyPath = fullPath
                        self.canView = true
                        self.processRunner.log("Generated: \(fullPath)")
                        
                        // Auto-launch viewer
                        self.launchViewer()
                    }
                }
                
            } catch {
                self.processRunner.log("Error: \(error)")
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
    
    func launchViewer() {
        guard let _ = currentPlyPath else { return }
        DispatchQueue.main.async {
            self.showViewer = true
        }
    }
    
    /// Fix PLY orientation by negating X and Y coordinates
    /// Sharp generates PLY with horizontal mirror + vertical flip
    func fixPlyOrientation(at path: String) {
        guard let data = FileManager.default.contents(atPath: path) else {
            processRunner.log("Error: Cannot read PLY file")
            return
        }
        
        // Find end_header marker
        guard let headerEnd = data.range(of: "end_header".data(using: .utf8)!) else {
            processRunner.log("Error: Invalid PLY header")
            return
        }
        
        var dataOffset = headerEnd.upperBound
        // Skip newline after end_header
        if dataOffset < data.count {
            if data[dataOffset] == 0x0D { dataOffset += 1 }
            if dataOffset < data.count && data[dataOffset] == 0x0A { dataOffset += 1 }
        }
        
        // Parse header to find vertex count and stride
        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        let headerString = String(decoding: headerData, as: UTF8.self)
        let lines = headerString.components(separatedBy: "\n")
        
        var vertexCount = 0
        var stride = 0
        var xOffset = -1
        var yOffset = -1
        var zOffset = -1
        var inVertexElement = false
        var currentOffset = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.hasPrefix("element vertex") {
                inVertexElement = true
                let parts = trimmed.components(separatedBy: " ")
                if let count = Int(parts.last ?? "") {
                    vertexCount = count
                }
            } else if trimmed.hasPrefix("element ") {
                inVertexElement = false
            }
            
            if inVertexElement && trimmed.hasPrefix("property") {
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 3 {
                    let typeStr = parts[1]
                    let name = parts[2]
                    
                    var typeSize = 0
                    switch typeStr {
                    case "float", "float32", "int", "int32", "uint", "uint32":
                        typeSize = 4
                    case "double", "float64":
                        typeSize = 8
                    case "short", "int16", "ushort", "uint16":
                        typeSize = 2
                    case "char", "int8", "uchar", "uint8":
                        typeSize = 1
                    default:
                        break
                    }
                    
                    if name == "x" { xOffset = currentOffset }
                    if name == "y" { yOffset = currentOffset }
                    if name == "z" { zOffset = currentOffset }
                    
                    currentOffset += typeSize
                }
            }
        }
        
        stride = currentOffset
        
        guard xOffset >= 0 && yOffset >= 0 && zOffset >= 0 && stride > 0 && vertexCount > 0 else {
            processRunner.log("Error: Cannot parse PLY structure (x:\(xOffset), y:\(yOffset), z:\(zOffset), stride:\(stride), count:\(vertexCount))")
            return
        }
        
        processRunner.log("Fixing \(vertexCount) vertices (stride:\(stride), x:\(xOffset), y:\(yOffset), z:\(zOffset))...")
        
        // Create mutable copy
        var mutableData = data
        
        mutableData.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            
            for i in 0..<vertexCount {
                let vertexStart = dataOffset + i * stride
                
                // X is kept as-is (no mirror needed)
                
                // Negate Y (fix vertical flip)
                let yPtr = base + vertexStart + yOffset
                var yVal = yPtr.assumingMemoryBound(to: Float.self).pointee
                yVal = -yVal
                yPtr.assumingMemoryBound(to: Float.self).pointee = yVal
                
                // Negate Z (to face forward instead of backward)
                let zPtr = base + vertexStart + zOffset
                var zVal = zPtr.assumingMemoryBound(to: Float.self).pointee
                zVal = -zVal
                zPtr.assumingMemoryBound(to: Float.self).pointee = zVal
            }
        }
        
        // Write back
        do {
            try mutableData.write(to: URL(fileURLWithPath: path))
            processRunner.log("PLY orientation fixed successfully")
        } catch {
            processRunner.log("Error writing fixed PLY: \(error)")
        }
    }
}
