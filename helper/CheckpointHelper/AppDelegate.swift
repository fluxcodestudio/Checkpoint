import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {

    // Strong references
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    let heartbeatMonitor = HeartbeatMonitor()
    let notificationManager = NotificationManager()

    // Menu items that need updating
    var statusMenuItem: NSMenuItem!
    var lastBackupMenuItem: NSMenuItem!
    var daemonStatusMenuItem: NSMenuItem!
    var watchdogStatusMenuItem: NSMenuItem!
    var stalenessMenuItem: NSMenuItem!

    // Sync progress menu items (hidden when idle)
    var syncProgressMenuItem: NSMenuItem!
    var syncCurrentProjectMenuItem: NSMenuItem!
    var syncCountersMenuItem: NSMenuItem!

    // Cache last-known sync progress to handle heartbeat write gaps
    private var cachedSyncIndex: Int = 0
    private var cachedSyncTotal: Int = 0
    private var cachedSyncProject: String = ""
    private var cachedSyncBackedUp: Int = 0
    private var cachedSyncFailed: Int = 0
    private var cachedSyncSkipped: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().delegate = notificationManager

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusBarIcon(tint: .white)  // Start white until we know status

        // Build menu
        buildMenu()
        statusItem.menu = menu

        // Start monitoring daemon heartbeat
        heartbeatMonitor.delegate = self
        heartbeatMonitor.startMonitoring()

        // Check daemon status immediately
        updateDaemonStatus()

        // Auto-start daemon if not running
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if !DaemonController.isRunning() {
                _ = DaemonController.start()
                DispatchQueue.main.async {
                    self.updateDaemonStatus()
                }
            }
        }
    }

    private func setStatusBarIcon(tint: NSColor?) {
        guard let button = statusItem.button else { return }

        // Load custom Checkpoint logo icon (white on transparent, not template)
        if let image = Self.loadStatusBarIcon() {
            image.isTemplate = false
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else {
            // Fallback to SF Symbol if custom icon not found
            if let image = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: "Checkpoint") {
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                let configuredImage = image.withSymbolConfiguration(config) ?? image
                button.image = configuredImage
            } else {
                button.title = "CP"
            }
        }

        // Tint not used with non-template image — color is baked into the PNG
    }

    /// Find the status bar icon from bundle Resources, using multiple search strategies
    private static func loadStatusBarIcon() -> NSImage? {
        // Strategy 1: Bundle.main (works when launched as proper .app)
        if let path = Bundle.main.path(forResource: "StatusBarIconTemplate", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }

        // Strategy 2: Executable-relative path (works for command-line-built Swift apps)
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let resourcesDir = execURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        let iconPath = resourcesDir.appendingPathComponent("StatusBarIconTemplate.png").path
        if let image = NSImage(contentsOfFile: iconPath) {
            return image
        }

        // Strategy 3: Check @2x variant
        let icon2xPath = resourcesDir.appendingPathComponent("StatusBarIconTemplate@2x.png").path
        if let image = NSImage(contentsOfFile: icon2xPath) {
            return image
        }

        return nil
    }

    private func buildMenu() {
        menu = NSMenu()

        // Daemon status (at top)
        daemonStatusMenuItem = NSMenuItem(title: "Daemon: Checking...", action: nil, keyEquivalent: "")
        daemonStatusMenuItem.isEnabled = false
        menu.addItem(daemonStatusMenuItem)

        // Watchdog status
        watchdogStatusMenuItem = NSMenuItem(title: "Watchdog: Checking...", action: nil, keyEquivalent: "")
        watchdogStatusMenuItem.isEnabled = false
        menu.addItem(watchdogStatusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Backup status section
        statusMenuItem = NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // Sync progress items (hidden when idle)
        syncCurrentProjectMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        syncCurrentProjectMenuItem.isEnabled = false
        syncCurrentProjectMenuItem.isHidden = true
        menu.addItem(syncCurrentProjectMenuItem)

        syncCountersMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        syncCountersMenuItem.isEnabled = false
        syncCountersMenuItem.isHidden = true
        menu.addItem(syncCountersMenuItem)

        lastBackupMenuItem = NSMenuItem(title: "Last backup: --", action: nil, keyEquivalent: "")
        lastBackupMenuItem.isEnabled = false
        menu.addItem(lastBackupMenuItem)

        stalenessMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stalenessMenuItem.isEnabled = false
        stalenessMenuItem.isHidden = true
        menu.addItem(stalenessMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Actions
        let backupItem = NSMenuItem(title: "Backup Now", action: #selector(backupNow), keyEquivalent: "b")
        backupItem.target = self
        menu.addItem(backupItem)

        let dashboardItem = NSMenuItem(title: "Show Dashboard", action: #selector(showDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let terminalItem = NSMenuItem(title: "Open in Terminal", action: #selector(openTerminal), keyEquivalent: "t")
        terminalItem.target = self
        menu.addItem(terminalItem)

        menu.addItem(NSMenuItem.separator())

        // Daemon control submenu
        let controlMenu = NSMenu()

        let startItem = NSMenuItem(title: "Start Daemon", action: #selector(startDaemon), keyEquivalent: "")
        startItem.target = self
        controlMenu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Daemon", action: #selector(stopDaemon), keyEquivalent: "")
        stopItem.target = self
        controlMenu.addItem(stopItem)

        let restartItem = NSMenuItem(title: "Restart Daemon", action: #selector(restartDaemon), keyEquivalent: "")
        restartItem.target = self
        controlMenu.addItem(restartItem)

        let controlItem = NSMenuItem(title: "Daemon Control", action: nil, keyEquivalent: "")
        controlItem.submenu = controlMenu
        menu.addItem(controlItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updateDaemonStatus() {
        let isRunning = DaemonController.isRunning()
        DispatchQueue.main.async {
            if isRunning {
                self.daemonStatusMenuItem.title = "Daemon: Running"
                self.daemonStatusMenuItem.attributedTitle = self.coloredText("Daemon: Running", bulletColor: .systemGreen)
            } else {
                self.daemonStatusMenuItem.title = "Daemon: Stopped"
                self.daemonStatusMenuItem.attributedTitle = self.coloredText("Daemon: Stopped", bulletColor: .systemRed)
            }
        }

        // Also check watchdog
        let watchdogData = heartbeatMonitor.readWatchdogStatus()
        DispatchQueue.main.async {
            switch watchdogData.status {
            case .healthy:
                self.watchdogStatusMenuItem.title = "Watchdog: Active"
                self.watchdogStatusMenuItem.attributedTitle = self.coloredText("Watchdog: Active", bulletColor: .systemGreen)
            case .stale:
                self.watchdogStatusMenuItem.title = "Watchdog: Stale"
                self.watchdogStatusMenuItem.attributedTitle = self.coloredText("Watchdog: Stale", bulletColor: .systemOrange)
            default:
                self.watchdogStatusMenuItem.title = "Watchdog: Inactive"
                self.watchdogStatusMenuItem.attributedTitle = self.coloredText("Watchdog: Inactive", bulletColor: .systemGray)
            }
        }
    }

    private func coloredText(_ text: String, bulletColor: NSColor) -> NSAttributedString {
        let fullText = "\u{25CF} \(text)"
        let attributed = NSMutableAttributedString(string: fullText)
        attributed.addAttribute(.foregroundColor, value: bulletColor, range: NSRange(location: 0, length: 1))
        return attributed
    }

    // MARK: - Actions

    @objc func backupNow() {
        statusMenuItem.title = "Status: Backing up..."
        DaemonController.runBackupNow { [weak self] success, output in
            DispatchQueue.main.async {
                if success {
                    self?.notificationManager.showNotification(title: "Backup Complete", body: "Backup finished successfully")
                    self?.statusMenuItem.title = "Status: Healthy"
                    self?.setStatusBarIcon(tint: .systemGreen)
                } else {
                    self?.notificationManager.showNotification(title: "Backup Failed", body: String(output.prefix(100)))
                    self?.statusMenuItem.title = "Status: Error"
                    self?.setStatusBarIcon(tint: .systemRed)
                }
            }
        }
    }

    @objc func showDashboard() {
        DashboardWindowController.shared.showDashboard()
    }

    @objc func openTerminal() {
        DaemonController.openDashboard()
    }

    @objc func startDaemon() {
        if DaemonController.start() {
            notificationManager.showNotification(title: "Daemon Started", body: "Backup daemon is now running")
            updateDaemonStatus()
        }
    }

    @objc func stopDaemon() {
        if DaemonController.stop() {
            notificationManager.showNotification(title: "Daemon Stopped", body: "Backup daemon has been stopped")
            updateDaemonStatus()
        }
    }

    @objc func restartDaemon() {
        if DaemonController.restart() {
            notificationManager.showNotification(title: "Daemon Restarted", body: "Backup daemon has been restarted")
            updateDaemonStatus()
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Sync Progress

    private func updateSyncProgress(data: HeartbeatMonitor.HeartbeatData) {
        // Update cache when sync fields are present
        if let index = data.syncingProjectIndex { cachedSyncIndex = index }
        if let total = data.syncingTotalProjects { cachedSyncTotal = total }
        if let project = data.syncingCurrentProject, !project.isEmpty { cachedSyncProject = project }
        if let backedUp = data.syncingBackedUp { cachedSyncBackedUp = backedUp }
        if let failed = data.syncingFailed { cachedSyncFailed = failed }
        if let skipped = data.syncingSkipped { cachedSyncSkipped = skipped }

        if data.isSyncing {
            // Show progress in status line
            statusMenuItem.title = "Status: Syncing \(cachedSyncIndex) of \(cachedSyncTotal) projects\u{2026}"

            // Current project
            syncCurrentProjectMenuItem.title = "  \u{25B8} \(cachedSyncProject)"
            syncCurrentProjectMenuItem.isHidden = false

            // Counters
            var parts: [String] = []
            parts.append("done \(cachedSyncBackedUp)")
            parts.append("failed \(cachedSyncFailed)")
            if cachedSyncSkipped > 0 {
                parts.append("skipped \(cachedSyncSkipped)")
            }
            syncCountersMenuItem.title = "  \(parts.joined(separator: " \u{00B7} "))"
            syncCountersMenuItem.isHidden = false
        } else {
            // Hide sync detail items when idle
            syncCurrentProjectMenuItem.isHidden = true
            syncCountersMenuItem.isHidden = true

            // Reset cache
            cachedSyncIndex = 0
            cachedSyncTotal = 0
            cachedSyncProject = ""
            cachedSyncBackedUp = 0
            cachedSyncFailed = 0
            cachedSyncSkipped = 0
        }
    }

    // MARK: - Icon Updates

    func updateStatusIcon(for status: HeartbeatMonitor.DaemonStatus) {
        // nil = system default (white on dark, black on light menu bar)
        // Only tint for warning/error states
        let color: NSColor?
        switch status {
        case .healthy:
            color = .white
        case .syncing:
            color = .systemBlue
        case .error:
            color = .systemRed
        case .stale:
            color = .systemOrange
        case .backupsStale:
            color = .systemYellow
        case .stopped, .missing:
            color = .systemGray
        }
        setStatusBarIcon(tint: color)
    }

    // MARK: - Staleness UI

    func updateStalenessDisplay(data: HeartbeatMonitor.HeartbeatData) {
        guard let lastBackup = data.lastBackup else {
            stalenessMenuItem.isHidden = true
            return
        }

        let hoursSinceBackup = Date().timeIntervalSince(lastBackup) / 3600

        if hoursSinceBackup > 72 {
            stalenessMenuItem.title = "CRITICAL: No backup in \(Int(hoursSinceBackup))h"
            stalenessMenuItem.attributedTitle = NSAttributedString(
                string: "CRITICAL: No backup in \(Int(hoursSinceBackup))h",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            stalenessMenuItem.isHidden = false
        } else if hoursSinceBackup > 24 {
            stalenessMenuItem.title = "Warning: No backup in \(Int(hoursSinceBackup))h"
            stalenessMenuItem.attributedTitle = NSAttributedString(
                string: "Warning: No backup in \(Int(hoursSinceBackup))h",
                attributes: [.foregroundColor: NSColor.systemOrange]
            )
            stalenessMenuItem.isHidden = false
        } else {
            stalenessMenuItem.isHidden = true
        }
    }
}

// MARK: - HeartbeatMonitorDelegate

extension AppDelegate: HeartbeatMonitorDelegate {
    func heartbeatUpdated(data: HeartbeatMonitor.HeartbeatData) {
        DispatchQueue.main.async {
            // Update sync progress (may override status title during sync)
            self.updateSyncProgress(data: data)

            // Only set generic status title when NOT syncing (sync sets its own)
            if !data.isSyncing {
                self.statusMenuItem.title = "Status: \(data.status.rawValue.capitalized)"
            }

            if let lastBackup = data.lastBackup {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relative = formatter.localizedString(for: lastBackup, relativeTo: Date())
                self.lastBackupMenuItem.title = "Last backup: \(relative)"
            }

            self.updateStalenessDisplay(data: data)
            self.updateStatusIcon(for: data.status)
            self.updateDaemonStatus()
        }
    }

    func heartbeatStatusChanged(from oldStatus: HeartbeatMonitor.DaemonStatus,
                                 to newStatus: HeartbeatMonitor.DaemonStatus,
                                 data: HeartbeatMonitor.HeartbeatData) {
        switch newStatus {
        case .error:
            notificationManager.showNotification(title: "Checkpoint Error", body: data.error ?? "Daemon error")
        case .stale:
            notificationManager.showNotification(title: "Checkpoint Warning", body: "Daemon may have stopped")
        case .backupsStale:
            let hours = data.lastBackup.map { Int(Date().timeIntervalSince($0) / 3600) } ?? 0
            notificationManager.showNotification(
                title: "Checkpoint Warning",
                body: "No successful backup in \(hours) hours"
            )
        case .stopped:
            notificationManager.showNotification(title: "Checkpoint Stopped", body: "Daemon has stopped")
        default:
            break
        }
    }
}
