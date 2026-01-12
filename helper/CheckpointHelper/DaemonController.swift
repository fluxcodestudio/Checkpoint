import Foundation

/// Controls the Checkpoint daemon via launchctl
class DaemonController {

    // MARK: - Constants

    static let globalPlistLabel = "com.checkpoint.global-daemon"
    static let globalPlistPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(globalPlistLabel).plist")
    }()

    // MARK: - Status

    static func isRunning() -> Bool {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", globalPlistLabel]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func getStatus() -> String {
        if !FileManager.default.fileExists(atPath: globalPlistPath.path) {
            return "Not Installed"
        }

        if isRunning() {
            return "Running"
        } else {
            return "Stopped"
        }
    }

    // MARK: - Control

    static func start() -> Bool {
        guard FileManager.default.fileExists(atPath: globalPlistPath.path) else {
            print("LaunchAgent plist not found at \(globalPlistPath.path)")
            return false
        }

        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", globalPlistPath.path]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("Failed to start daemon: \(error)")
            return false
        }
    }

    static func stop() -> Bool {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", globalPlistPath.path]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("Failed to stop daemon: \(error)")
            return false
        }
    }

    static func restart() -> Bool {
        _ = stop()
        // Small delay to ensure clean stop
        Thread.sleep(forTimeInterval: 0.5)
        return start()
    }

    // MARK: - Manual Backup

    static func runBackupNow(completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()

            // Find backup-now command
            let possiblePaths = [
                "/usr/local/bin/backup-now",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/backup-now").path
            ]

            var backupCommand: String?
            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    backupCommand = path
                    break
                }
            }

            guard let command = backupCommand else {
                DispatchQueue.main.async {
                    completion(false, "backup-now command not found")
                }
                return
            }

            task.launchPath = command
            task.arguments = []

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    completion(task.terminationStatus == 0, output)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Dashboard

    static func openDashboard() {
        let possiblePaths = [
            "/usr/local/bin/checkpoint",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/checkpoint").path
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                // Open in Terminal
                let script = """
                tell application "Terminal"
                    activate
                    do script "\(path)"
                end tell
                """
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
                return
            }
        }
    }
}
