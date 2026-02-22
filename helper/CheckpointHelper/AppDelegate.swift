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

    // New menu items
    var projectCountMenuItem: NSMenuItem!
    var pauseResumeMenuItem: NSMenuItem!

    // Float on top toggle (synced via menu item)
    var floatOnTopMenuItem: NSMenuItem!

    // Track previous sync state to detect completion
    private var wasSyncing = false
    private var greenFlashTimer: Timer?

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

        // Listen for daemon state changes from the dashboard
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDaemonStateChanged),
            name: NSNotification.Name("CheckpointDaemonStateChanged"),
            object: nil
        )

        // Auto-start daemon if not running
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if !DaemonController.isRunning() {
                _ = DaemonController.start()
                DispatchQueue.main.async {
                    self.updateDaemonStatus()
                }
            }
        }

        // Listen for float-on-top changes from settings sheet
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFloatOnTopChanged),
            name: NSNotification.Name("CheckpointFloatOnTopChanged"),
            object: nil
        )

        // Auto-open dashboard on first launch (with onboarding)
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                DashboardWindowController.shared.showDashboard()
                // Trigger onboarding via the view model's published property
                // The DashboardView observes showingOnboarding and presents the sheet
                NotificationCenter.default.post(name: NSNotification.Name("CheckpointShowOnboarding"), object: nil)
            }
        }
    }

    private func setStatusBarIcon(tint: NSColor?) {
        guard let button = statusItem.button else { return }

        // Load custom Checkpoint logo icon
        if let baseImage = Self.loadStatusBarIcon() {
            baseImage.size = NSSize(width: 18, height: 18)

            if let tintColor = tint, tintColor != .white {
                // Tint the image by drawing it with a color overlay
                let tinted = NSImage(size: baseImage.size)
                tinted.lockFocus()
                baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size),
                               from: .zero, operation: .sourceOver, fraction: 1.0)
                tintColor.withAlphaComponent(0.85).set()
                NSRect(origin: .zero, size: baseImage.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.isTemplate = false
                button.image = tinted
            } else {
                baseImage.isTemplate = false
                button.image = baseImage
            }
        } else {
            // Fallback to SF Symbol if custom icon not found
            if let image = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: "Checkpoint") {
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                let configuredImage = image.withSymbolConfiguration(config) ?? image
                button.image = configuredImage
                button.contentTintColor = tint
            } else {
                button.title = "CP"
            }
        }
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

        // Project count
        projectCountMenuItem = NSMenuItem(title: "Projects: --", action: nil, keyEquivalent: "")
        projectCountMenuItem.isEnabled = false
        menu.addItem(projectCountMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Actions
        let backupItem = NSMenuItem(title: "Backup All", action: #selector(backupNow), keyEquivalent: "b")
        backupItem.target = self
        menu.addItem(backupItem)

        let addProjectItem = NSMenuItem(title: "Add Project\u{2026}", action: #selector(addProject), keyEquivalent: "a")
        addProjectItem.target = self
        menu.addItem(addProjectItem)

        let dashboardItem = NSMenuItem(title: "Show Dashboard", action: #selector(showDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem.separator())

        // Pause / Resume (matches dashboard)
        pauseResumeMenuItem = NSMenuItem(title: "Pause Backups", action: #selector(togglePauseResume), keyEquivalent: "p")
        pauseResumeMenuItem.target = self
        menu.addItem(pauseResumeMenuItem)

        let terminalItem = NSMenuItem(title: "Open in Terminal", action: #selector(openTerminal), keyEquivalent: "t")
        terminalItem.target = self
        menu.addItem(terminalItem)

        // Float on top toggle
        floatOnTopMenuItem = NSMenuItem(title: "Float on Top", action: #selector(toggleFloatOnTop), keyEquivalent: "f")
        floatOnTopMenuItem.target = self
        floatOnTopMenuItem.state = UserDefaults.standard.bool(forKey: "floatOnTop") ? .on : .off
        menu.addItem(floatOnTopMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Daemon control submenu (advanced)
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
        DaemonController.openTerminal()
    }

    @objc func startDaemon() {
        if DaemonController.start() {
            notificationManager.showNotification(title: "Daemon Started", body: "Backup daemon is now running")
            updateDaemonStatus()
            updatePauseResumeTitle()
            notifyDaemonStateChanged()
        }
    }

    @objc func stopDaemon() {
        if DaemonController.stop() {
            notificationManager.showNotification(title: "Daemon Stopped", body: "Backup daemon has been stopped")
            updateDaemonStatus()
            updatePauseResumeTitle()
            notifyDaemonStateChanged()
        }
    }

    @objc func restartDaemon() {
        if DaemonController.restart() {
            notificationManager.showNotification(title: "Daemon Restarted", body: "Backup daemon has been restarted")
            updateDaemonStatus()
            updatePauseResumeTitle()
            notifyDaemonStateChanged()
        }
    }

    @objc func addProject() {
        // Open dashboard and trigger add project flow
        DashboardWindowController.shared.showDashboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: NSNotification.Name("CheckpointAddProject"), object: nil)
        }
    }

    @objc func togglePauseResume() {
        if DaemonController.isRunning() {
            if DaemonController.stop() {
                notificationManager.showNotification(title: "Backups Paused", body: "Automatic backups are paused")
                updateDaemonStatus()
                updatePauseResumeTitle()
                notifyDaemonStateChanged()
            }
        } else {
            if DaemonController.start() {
                notificationManager.showNotification(title: "Backups Resumed", body: "Automatic backups are active")
                updateDaemonStatus()
                updatePauseResumeTitle()
                notifyDaemonStateChanged()
            }
        }
    }

    private func notifyDaemonStateChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("CheckpointDaemonStateChanged"), object: nil)
    }

    @objc private func handleDaemonStateChanged() {
        DispatchQueue.main.async {
            self.updateDaemonStatus()
            self.updatePauseResumeTitle()
        }
    }

    @objc private func handleFloatOnTopChanged() {
        DispatchQueue.main.async {
            let enabled = UserDefaults.standard.bool(forKey: "floatOnTop")
            self.floatOnTopMenuItem.state = enabled ? .on : .off
            self.applyFloatOnTop(enabled)
        }
    }

    private func updatePauseResumeTitle() {
        let running = DaemonController.isRunning()
        pauseResumeMenuItem?.title = running ? "Pause Backups" : "Resume Backups"
    }

    private func updateProjectCount() {
        let registryPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/checkpoint/projects.json")

        guard let data = try? Data(contentsOf: registryPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [[String: Any]] else {
            projectCountMenuItem?.title = "Projects: 0"
            return
        }

        let enabled = projects.filter { ($0["enabled"] as? Bool) ?? true }.count
        let total = projects.count
        if enabled == total {
            projectCountMenuItem?.title = "Projects: \(total)"
        } else {
            projectCountMenuItem?.title = "Projects: \(enabled) of \(total) active"
        }
    }

    @objc func toggleFloatOnTop() {
        let current = UserDefaults.standard.bool(forKey: "floatOnTop")
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: "floatOnTop")
        floatOnTopMenuItem.state = newValue ? .on : .off
        applyFloatOnTop(newValue)
        // Notify settings sheet so toggle stays in sync
        NotificationCenter.default.post(name: NSNotification.Name("CheckpointFloatOnTopChanged"), object: nil)
    }

    func applyFloatOnTop(_ enabled: Bool) {
        DashboardWindowController.shared.window?.level = enabled ? .floating : .normal
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
        let color: NSColor?
        switch status {
        case .healthy:
            color = .white
        case .syncing:
            // Dashboard orange (cpAccentWarm: 1.0, 0.55, 0.25)
            color = NSColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 1.0)
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
            // Track sync state transitions for green flash
            let currentlySyncing = data.isSyncing
            if self.wasSyncing && !currentlySyncing {
                self.flashGreenIcon()
            }
            self.wasSyncing = currentlySyncing

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
            // Don't override green flash with normal color
            if self.greenFlashTimer == nil {
                self.updateStatusIcon(for: data.status)
            }
            self.updateDaemonStatus()
            self.updatePauseResumeTitle()
            self.updateProjectCount()
        }
    }

    /// Flash icon green for 30 seconds after sync completes, then revert
    private func flashGreenIcon() {
        greenFlashTimer?.invalidate()
        setStatusBarIcon(tint: .systemGreen)
        greenFlashTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.greenFlashTimer = nil
                self?.setStatusBarIcon(tint: .white) // revert to normal
            }
        }
    }

    func heartbeatStatusChanged(from oldStatus: HeartbeatMonitor.DaemonStatus,
                                 to newStatus: HeartbeatMonitor.DaemonStatus,
                                 data: HeartbeatMonitor.HeartbeatData) {
        switch newStatus {
        case .healthy, .syncing:
            // Don't auto-open dashboard — just let the icon color change speak for itself
            break
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

        // Detect sync completion: was syncing → now healthy/not syncing
        if wasSyncing && !data.isSyncing && (newStatus == .healthy || oldStatus == .syncing) {
            DispatchQueue.main.async {
                self.flashGreenIcon()
            }
        }
    }
}
