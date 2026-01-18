import Cocoa

/// Manages the menu bar status item and dropdown menu
class MenuBarManager: NSObject {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    private var statusMenuItem: NSMenuItem?
    private var lastBackupMenuItem: NSMenuItem?
    private var projectMenuItem: NSMenuItem?

    private let heartbeatMonitor = HeartbeatMonitor()
    private let notificationManager = NotificationManager()

    // MARK: - Setup

    func setup() {
        print("MenuBarManager.setup() called")

        // Create status item with fixed length
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        print("Status item created: \(statusItem != nil)")

        if let button = statusItem?.button {
            print("Button found, setting title")
            // Use simple text - most reliable
            button.title = "CP"
            button.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            print("Title set to: \(button.title)")
        } else {
            print("ERROR: No button on status item!")
        }

        // Create menu
        menu = NSMenu()
        setupMenu()
        statusItem?.menu = menu
        print("Menu attached: \(statusItem?.menu != nil)")

        // Start monitoring
        heartbeatMonitor.delegate = self
        heartbeatMonitor.startMonitoring()
        print("Setup complete")
    }

    // MARK: - Menu Setup

    private func setupMenu() {
        guard let menu = menu else { return }

        menu.removeAllItems()

        // Status section
        statusMenuItem = NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu.addItem(statusMenuItem!)

        lastBackupMenuItem = NSMenuItem(title: "Last backup: --", action: nil, keyEquivalent: "")
        lastBackupMenuItem?.isEnabled = false
        menu.addItem(lastBackupMenuItem!)

        projectMenuItem = NSMenuItem(title: "Project: --", action: nil, keyEquivalent: "")
        projectMenuItem?.isEnabled = false
        menu.addItem(projectMenuItem!)

        menu.addItem(NSMenuItem.separator())

        // Actions
        let backupNowItem = NSMenuItem(title: "Backup Now", action: #selector(backupNow), keyEquivalent: "b")
        backupNowItem.target = self
        menu.addItem(backupNowItem)

        let dashboardItem = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem.separator())

        // Daemon control submenu
        let controlSubmenu = NSMenu()

        let startItem = NSMenuItem(title: "Start Daemon", action: #selector(startDaemon), keyEquivalent: "")
        startItem.target = self
        controlSubmenu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Daemon", action: #selector(stopDaemon), keyEquivalent: "")
        stopItem.target = self
        controlSubmenu.addItem(stopItem)

        let restartItem = NSMenuItem(title: "Restart Daemon", action: #selector(restartDaemon), keyEquivalent: "r")
        restartItem.target = self
        controlSubmenu.addItem(restartItem)

        let controlItem = NSMenuItem(title: "Daemon Control", action: nil, keyEquivalent: "")
        controlItem.submenu = controlSubmenu
        menu.addItem(controlItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Checkpoint Helper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func backupNow() {
        updateStatus(text: "Backing up...")
        DaemonController.runBackupNow { [weak self] success, output in
            if success {
                self?.notificationManager.showNotification(
                    title: "Backup Complete",
                    body: "Manual backup finished successfully"
                )
            } else {
                self?.notificationManager.showNotification(
                    title: "Backup Failed",
                    body: output.prefix(100).description
                )
            }
        }
    }

    @objc private func openDashboard() {
        DaemonController.openDashboard()
    }

    @objc private func startDaemon() {
        if DaemonController.start() {
            notificationManager.showNotification(
                title: "Daemon Started",
                body: "Checkpoint backup daemon is now running"
            )
        }
    }

    @objc private func stopDaemon() {
        if DaemonController.stop() {
            notificationManager.showNotification(
                title: "Daemon Stopped",
                body: "Checkpoint backup daemon has been stopped"
            )
        }
    }

    @objc private func restartDaemon() {
        if DaemonController.restart() {
            notificationManager.showNotification(
                title: "Daemon Restarted",
                body: "Checkpoint backup daemon has been restarted"
            )
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - UI Updates

    private func updateStatus(text: String) {
        statusMenuItem?.title = "Status: \(text)"
    }

    private func updateIcon(for status: HeartbeatMonitor.DaemonStatus) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let tintColor: NSColor?

        switch status {
        case .healthy:
            symbolName = "checkmark.shield.fill"
            tintColor = .systemGreen
        case .syncing:
            symbolName = "arrow.triangle.2.circlepath"
            tintColor = .systemBlue
        case .error:
            symbolName = "exclamationmark.shield.fill"
            tintColor = .systemRed
        case .stopped:
            symbolName = "stop.fill"
            tintColor = .systemGray
        case .stale:
            symbolName = "exclamationmark.triangle.fill"
            tintColor = .systemOrange
        case .missing:
            symbolName = "questionmark.circle"
            tintColor = .systemGray
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: status.rawValue) {
            button.image = image
            button.contentTintColor = tintColor
        }
    }
}

// MARK: - HeartbeatMonitorDelegate

extension MenuBarManager: HeartbeatMonitorDelegate {

    func heartbeatUpdated(data: HeartbeatMonitor.HeartbeatData) {
        DispatchQueue.main.async { [weak self] in
            // Update status text
            self?.updateStatus(text: data.status.rawValue.capitalized)

            // Update last backup
            if let lastBackup = data.lastBackup {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relative = formatter.localizedString(for: lastBackup, relativeTo: Date())
                self?.lastBackupMenuItem?.title = "Last backup: \(relative)"
            } else {
                self?.lastBackupMenuItem?.title = "Last backup: Never"
            }

            // Update project
            if let project = data.project {
                self?.projectMenuItem?.title = "Project: \(project)"
            } else {
                self?.projectMenuItem?.title = "Project: --"
            }

            // Update icon
            self?.updateIcon(for: data.status)
        }
    }

    func heartbeatStatusChanged(from oldStatus: HeartbeatMonitor.DaemonStatus,
                                 to newStatus: HeartbeatMonitor.DaemonStatus,
                                 data: HeartbeatMonitor.HeartbeatData) {

        // Show notification for important status changes
        switch newStatus {
        case .error:
            notificationManager.showNotification(
                title: "Checkpoint Error",
                body: data.error ?? "Backup daemon encountered an error"
            )
        case .stale:
            notificationManager.showNotification(
                title: "Checkpoint Warning",
                body: "Backup daemon may have stopped responding"
            )
        case .stopped:
            notificationManager.showNotification(
                title: "Checkpoint Stopped",
                body: "Backup daemon has stopped"
            )
        case .healthy:
            if oldStatus == .error || oldStatus == .stale {
                notificationManager.showNotification(
                    title: "Checkpoint Recovered",
                    body: "Backup daemon is healthy again"
                )
            }
        default:
            break
        }
    }
}
