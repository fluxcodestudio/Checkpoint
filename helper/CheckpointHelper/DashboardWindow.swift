import Cocoa
import SwiftUI

// MARK: - Dashboard Window Controller

class DashboardWindowController: NSWindowController {

    static let shared = DashboardWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Checkpoint Dashboard"
        window.center()
        window.setFrameAutosaveName("CheckpointDashboard")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 400)

        super.init(window: window)

        // Set SwiftUI content
        let dashboardView = DashboardView()
        window.contentView = NSHostingView(rootView: dashboardView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showDashboard() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI Dashboard View

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                Text("Checkpoint")
                    .font(.title)
                    .fontWeight(.semibold)
                Spacer()

                // Global status
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.daemonRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.daemonRunning ? "Daemon Running" : "Daemon Stopped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Projects list
            if viewModel.projects.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No projects configured")
                        .font(.headline)
                    Text("Run 'backup-now' in a project directory to configure it")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List(viewModel.projects) { project in
                    ProjectRow(project: project, onBackup: {
                        viewModel.backupProject(project)
                    })
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer actions
            HStack {
                Button(action: viewModel.backupAll) {
                    Label("Backup All", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isBackingUp)

                Button(action: viewModel.openSettings) {
                    Label("Settings", systemImage: "gear")
                }

                Spacer()

                Button(action: viewModel.refresh) {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }

                if viewModel.daemonRunning {
                    Button(action: viewModel.stopDaemon) {
                        Label("Stop Daemon", systemImage: "stop.fill")
                    }
                } else {
                    Button(action: viewModel.startDaemon) {
                        Label("Start Daemon", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            viewModel.refresh()
        }
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: ProjectInfo
    let onBackup: () -> Void

    var body: some View {
        HStack {
            // Status icon
            Image(systemName: project.statusIcon)
                .foregroundColor(project.statusColor)
                .frame(width: 20)

            // Project info
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .fontWeight(.medium)
                Text(project.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Last backup
            VStack(alignment: .trailing, spacing: 2) {
                Text(project.lastBackupText)
                    .font(.caption)
                if let size = project.backupSize {
                    Text(size)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Backup button
            Button(action: onBackup) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Backup now")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - View Model

class DashboardViewModel: ObservableObject {
    @Published var projects: [ProjectInfo] = []
    @Published var daemonRunning = false
    @Published var isBackingUp = false

    private var refreshTimer: Timer?

    init() {
        // Auto-refresh every 30 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        daemonRunning = DaemonController.isRunning()
        loadProjects()
    }

    private func loadProjects() {
        let registryPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/checkpoint/projects.json")

        guard let data = try? Data(contentsOf: registryPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projectsArray = json["projects"] as? [[String: Any]] else {
            projects = []
            return
        }

        projects = projectsArray.compactMap { dict -> ProjectInfo? in
            guard let path = dict["path"] as? String else { return nil }
            let name = (path as NSString).lastPathComponent
            let enabled = dict["enabled"] as? Bool ?? true
            let lastBackup = (dict["last_backup"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

            return ProjectInfo(
                id: path,
                name: name,
                path: path,
                enabled: enabled,
                lastBackup: lastBackup
            )
        }
    }

    func backupProject(_ project: ProjectInfo) {
        isBackingUp = true
        DispatchQueue.global().async {
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", "cd '\(project.path)' && backup-now"]
            try? task.run()
            task.waitUntilExit()

            DispatchQueue.main.async {
                self.isBackingUp = false
                self.refresh()
            }
        }
    }

    func backupAll() {
        isBackingUp = true
        DispatchQueue.global().async {
            _ = DaemonController.start() // Triggers backup-all

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isBackingUp = false
                self.refresh()
            }
        }
    }

    func startDaemon() {
        _ = DaemonController.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.refresh()
        }
    }

    func stopDaemon() {
        _ = DaemonController.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.refresh()
        }
    }

    func openSettings() {
        // Open terminal with checkpoint settings
        DaemonController.openDashboard()
    }
}

// MARK: - Project Info Model

struct ProjectInfo: Identifiable {
    let id: String
    let name: String
    let path: String
    let enabled: Bool
    let lastBackup: Date?
    var backupSize: String? = nil

    var lastBackupText: String {
        guard let date = lastBackup else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var statusIcon: String {
        guard enabled else { return "pause.circle" }
        guard let date = lastBackup else { return "questionmark.circle" }

        let hoursSince = Date().timeIntervalSince(date) / 3600
        if hoursSince < 2 {
            return "checkmark.circle.fill"
        } else if hoursSince < 24 {
            return "checkmark.circle"
        } else if hoursSince < 72 {
            return "exclamationmark.circle"
        } else {
            return "exclamationmark.circle.fill"
        }
    }

    var statusColor: Color {
        guard enabled else { return .secondary }
        guard let date = lastBackup else { return .secondary }

        let hoursSince = Date().timeIntervalSince(date) / 3600
        if hoursSince < 2 {
            return .green
        } else if hoursSince < 24 {
            return .blue
        } else if hoursSince < 72 {
            return .orange
        } else {
            return .red
        }
    }
}
