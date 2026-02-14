import Foundation

/// Monitors the daemon heartbeat file for health status
class HeartbeatMonitor {

    // MARK: - Types

    enum DaemonStatus: String {
        case healthy
        case syncing
        case error
        case stopped
        case stale          // heartbeat older than threshold
        case backupsStale   // daemon alive but no recent backup
        case missing        // no heartbeat file
    }

    struct HeartbeatData {
        let timestamp: Date
        let status: DaemonStatus
        let project: String?
        let lastBackup: Date?
        let lastBackupFiles: Int
        let error: String?
        let pid: Int?
    }

    // MARK: - Properties

    private let heartbeatPath: URL
    private let watchdogHeartbeatPath: URL
    private let staleThreshold: TimeInterval = 120       // 2 minutes for daemon heartbeat
    private let backupWarningThreshold: TimeInterval = 24 * 3600   // 24 hours
    private let backupCriticalThreshold: TimeInterval = 72 * 3600  // 72 hours
    private var timer: Timer?
    private var lastStatus: DaemonStatus = .missing

    weak var delegate: HeartbeatMonitorDelegate?

    // MARK: - Init

    init(heartbeatPath: URL? = nil) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let checkpointDir = homeDir.appendingPathComponent(".checkpoint")

        if let path = heartbeatPath {
            self.heartbeatPath = path
        } else {
            self.heartbeatPath = checkpointDir.appendingPathComponent("daemon.heartbeat")
        }

        self.watchdogHeartbeatPath = checkpointDir.appendingPathComponent("watchdog.heartbeat")
    }

    // MARK: - Public Methods

    func startMonitoring(interval: TimeInterval = 5) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkHeartbeat()
        }
        // Check immediately
        checkHeartbeat()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func readStatus() -> HeartbeatData {
        guard FileManager.default.fileExists(atPath: heartbeatPath.path) else {
            return HeartbeatData(
                timestamp: Date(),
                status: .missing,
                project: nil,
                lastBackup: nil,
                lastBackupFiles: 0,
                error: "Heartbeat file not found",
                pid: nil
            )
        }

        do {
            let data = try Data(contentsOf: heartbeatPath)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return HeartbeatData(
                    timestamp: Date(),
                    status: .error,
                    project: nil,
                    lastBackup: nil,
                    lastBackupFiles: 0,
                    error: "Invalid heartbeat JSON",
                    pid: nil
                )
            }

            let timestamp = Date(timeIntervalSince1970: (json["timestamp"] as? TimeInterval) ?? 0)
            let statusStr = (json["status"] as? String) ?? "error"
            let project = json["project"] as? String
            let lastBackupTs = json["last_backup"] as? TimeInterval
            let lastBackup = lastBackupTs != nil ? Date(timeIntervalSince1970: lastBackupTs!) : nil
            let lastBackupFiles = (json["last_backup_files"] as? Int) ?? 0
            let error = json["error"] as? String
            let pid = json["pid"] as? Int

            // Check if heartbeat is stale (daemon not updating)
            let heartbeatAge = Date().timeIntervalSince(timestamp)
            var status: DaemonStatus

            if heartbeatAge > staleThreshold {
                status = .stale
            } else {
                status = DaemonStatus(rawValue: statusStr) ?? .error
            }

            // If daemon is healthy but backups are stale, flag it
            if status == .healthy, let lastBackup = lastBackup {
                let backupAge = Date().timeIntervalSince(lastBackup)
                if backupAge > backupWarningThreshold {
                    status = .backupsStale
                }
            }

            return HeartbeatData(
                timestamp: timestamp,
                status: status,
                project: project,
                lastBackup: lastBackup,
                lastBackupFiles: lastBackupFiles,
                error: error,
                pid: pid
            )
        } catch {
            return HeartbeatData(
                timestamp: Date(),
                status: .error,
                project: nil,
                lastBackup: nil,
                lastBackupFiles: 0,
                error: error.localizedDescription,
                pid: nil
            )
        }
    }

    /// Read watchdog heartbeat status
    func readWatchdogStatus() -> HeartbeatData {
        guard FileManager.default.fileExists(atPath: watchdogHeartbeatPath.path) else {
            return HeartbeatData(
                timestamp: Date(),
                status: .missing,
                project: nil,
                lastBackup: nil,
                lastBackupFiles: 0,
                error: "Watchdog heartbeat not found",
                pid: nil
            )
        }

        do {
            let data = try Data(contentsOf: watchdogHeartbeatPath)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return HeartbeatData(
                    timestamp: Date(),
                    status: .error,
                    project: nil,
                    lastBackup: nil,
                    lastBackupFiles: 0,
                    error: "Invalid watchdog heartbeat JSON",
                    pid: nil
                )
            }

            let timestamp = Date(timeIntervalSince1970: (json["timestamp"] as? TimeInterval) ?? 0)
            let pid = json["pid"] as? Int

            // Watchdog stale if not updated in 2 minutes
            let age = Date().timeIntervalSince(timestamp)
            let status: DaemonStatus = age > staleThreshold ? .stale : .healthy

            return HeartbeatData(
                timestamp: timestamp,
                status: status,
                project: nil,
                lastBackup: nil,
                lastBackupFiles: 0,
                error: nil,
                pid: pid
            )
        } catch {
            return HeartbeatData(
                timestamp: Date(),
                status: .error,
                project: nil,
                lastBackup: nil,
                lastBackupFiles: 0,
                error: error.localizedDescription,
                pid: nil
            )
        }
    }

    // MARK: - Private Methods

    private func checkHeartbeat() {
        let data = readStatus()

        // Notify delegate of status change
        if data.status != lastStatus {
            delegate?.heartbeatStatusChanged(from: lastStatus, to: data.status, data: data)
            lastStatus = data.status
        }

        // Always notify for updates
        delegate?.heartbeatUpdated(data: data)
    }
}

// MARK: - Delegate Protocol

protocol HeartbeatMonitorDelegate: AnyObject {
    func heartbeatUpdated(data: HeartbeatMonitor.HeartbeatData)
    func heartbeatStatusChanged(from oldStatus: HeartbeatMonitor.DaemonStatus,
                                 to newStatus: HeartbeatMonitor.DaemonStatus,
                                 data: HeartbeatMonitor.HeartbeatData)
}
