import Foundation

class ProcessRunner: ObservableObject {
    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    
    func log(_ message: String) {
        print("[Log]: \(message)") // Ensure logs are visible in Xcode/Terminal console
        DispatchQueue.main.async {
            self.logs += message + "\n"
        }
    }
    
    func runCommand(_ launchPath: String, arguments: [String], currentDirectoryPath: String? = nil) async throws {
        await MainActor.run { self.isRunning = true }
        defer { Task { await MainActor.run { self.isRunning = false } } }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        if let cwd = currentDirectoryPath {
            task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        let outHandle = pipe.fileHandleForReading
        outHandle.readabilityHandler = { pipe in
            if let line = String(data: pipe.availableData, encoding: .utf8), !line.isEmpty {
                self.log(line.trimmingCharacters(in: .newlines))
            }
        }
        
        do {
            try task.run()
            task.waitUntilExit()
            
            outHandle.readabilityHandler = nil
            
            if task.terminationStatus != 0 {
                throw NSError(domain: "ProcessRunner", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Command failed with exit code \(task.terminationStatus)"])
            }
        } catch {
            outHandle.readabilityHandler = nil
            log("Error running command: \(error)")
            throw error
        }
    }
}
