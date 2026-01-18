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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().delegate = notificationManager

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setShieldIcon(color: .systemGray)  // Start gray until we know status

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

    private func setShieldIcon(color: NSColor) {
        guard let button = statusItem.button else { return }

        // Always use shield icon
        if let image = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: "Checkpoint") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let configuredImage = image.withSymbolConfiguration(config) ?? image
            button.image = configuredImage
            button.contentTintColor = color
        } else {
            button.title = "CP"
        }
    }

    private func buildMenu() {
        menu = NSMenu()

        // Daemon status (at top)
        daemonStatusMenuItem = NSMenuItem(title: "● Daemon: Checking...", action: nil, keyEquivalent: "")
        daemonStatusMenuItem.isEnabled = false
        menu.addItem(daemonStatusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Backup status section
        statusMenuItem = NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        lastBackupMenuItem = NSMenuItem(title: "Last backup: --", action: nil, keyEquivalent: "")
        lastBackupMenuItem.isEnabled = false
        menu.addItem(lastBackupMenuItem)

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
                self.daemonStatusMenuItem.title = "● Daemon: Running"
                self.daemonStatusMenuItem.attributedTitle = self.coloredText("● Daemon: Running", bulletColor: .systemGreen)
            } else {
                self.daemonStatusMenuItem.title = "● Daemon: Stopped"
                self.daemonStatusMenuItem.attributedTitle = self.coloredText("● Daemon: Stopped", bulletColor: .systemRed)
            }
        }
    }

    private func coloredText(_ text: String, bulletColor: NSColor) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        // Color just the bullet
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
                    self?.setShieldIcon(color: .systemGreen)
                } else {
                    self?.notificationManager.showNotification(title: "Backup Failed", body: String(output.prefix(100)))
                    self?.statusMenuItem.title = "Status: Error"
                    self?.setShieldIcon(color: .systemRed)
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

    // MARK: - Icon Updates

    func updateStatusIcon(for status: HeartbeatMonitor.DaemonStatus) {
        let color: NSColor
        switch status {
        case .healthy:
            color = .systemGreen
        case .syncing:
            color = .systemBlue
        case .error:
            color = .systemRed
        case .stale:
            color = .systemOrange
        case .stopped, .missing:
            color = .systemGray
        }
        setShieldIcon(color: color)
    }
}

// MARK: - HeartbeatMonitorDelegate

extension AppDelegate: HeartbeatMonitorDelegate {
    func heartbeatUpdated(data: HeartbeatMonitor.HeartbeatData) {
        DispatchQueue.main.async {
            self.statusMenuItem.title = "Status: \(data.status.rawValue.capitalized)"

            if let lastBackup = data.lastBackup {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relative = formatter.localizedString(for: lastBackup, relativeTo: Date())
                self.lastBackupMenuItem.title = "Last backup: \(relative)"
            }

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
        case .stopped:
            notificationManager.showNotification(title: "Checkpoint Stopped", body: "Daemon has stopped")
        default:
            break
        }
    }
}
