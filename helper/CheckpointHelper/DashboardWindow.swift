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

                // Global status — user-friendly language
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.daemonRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.daemonRunning ? "Backups Active" : "Backups Paused")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Individual project backup banner
            if !viewModel.backingUpProjects.isEmpty && !viewModel.isSyncing {
                VStack(spacing: 6) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Backing up\u{2026}")
                            .font(.headline)
                        Spacer()
                    }
                    ForEach(Array(viewModel.backingUpProjects), id: \.self) { projectId in
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text((projectId as NSString).lastPathComponent)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }

                    // Phase description
                    HStack {
                        Text(viewModel.backupProgressPhaseText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if viewModel.backupProgressTotal > 0 {
                            Text("\u{2022} \(viewModel.backupProgressTotal) files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    ProgressView(value: Double(viewModel.backupProgressPercent), total: 100)
                        .tint(.blue)
                }
                .padding()
                .background(Color.blue.opacity(0.08))

                Divider()
            }

            // Sync progress banner (backup-all)
            if viewModel.isSyncing {
                VStack(spacing: 6) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing \(viewModel.syncIndex) of \(viewModel.syncTotal) projects\u{2026}")
                            .font(.headline)
                        Spacer()
                    }

                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(viewModel.syncCurrentProject)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Label("\(viewModel.syncBackedUp) done", systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                        if viewModel.syncFailed > 0 {
                            Label("\(viewModel.syncFailed) failed", systemImage: "xmark.circle")
                                .foregroundColor(.red)
                        }
                        if viewModel.syncSkipped > 0 {
                            Label("\(viewModel.syncSkipped) skipped", systemImage: "minus.circle")
                                .foregroundColor(.orange)
                        }
                        Spacer()
                    }
                    .font(.caption)

                    // Progress bar
                    ProgressView(value: Double(viewModel.syncIndex), total: Double(max(viewModel.syncTotal, 1)))
                        .tint(.blue)
                }
                .padding()
                .background(Color.blue.opacity(0.08))

                Divider()
            }

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
                    ProjectRow(
                        project: project,
                        isCurrentlySyncing: viewModel.isSyncing && viewModel.syncCurrentProject == project.name,
                        isSyncDone: viewModel.isSyncing && viewModel.completedProjects.contains(project.name),
                        isBackingUpIndividually: viewModel.backingUpProjects.contains(project.id),
                        isSyncingGlobally: viewModel.isSyncing,
                        onBackup: {
                            viewModel.backupProject(project)
                        },
                        onRevealInFinder: {
                            viewModel.revealInFinder(project)
                        },
                        onViewBackupFolder: {
                            viewModel.viewBackupFolder(project)
                        },
                        onViewLog: {
                            viewModel.viewLog(project)
                        },
                        onToggleEnabled: {
                            viewModel.toggleEnabled(project)
                        }
                    )
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
                .keyboardShortcut("b", modifiers: .command)

                Button(action: { viewModel.showingSettings = true }) {
                    Label("Settings", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)

                Spacer()

                Button(action: viewModel.refresh) {
                    switch viewModel.refreshState {
                    case .idle:
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    case .refreshing:
                        Label("Refreshing", systemImage: "arrow.triangle.2.circlepath")
                    case .done:
                        Label("Updated", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                if viewModel.daemonRunning {
                    Button(action: viewModel.stopDaemon) {
                        Label("Pause Backups", systemImage: "pause.fill")
                    }
                } else {
                    Button(action: viewModel.startDaemon) {
                        Label("Resume Backups", systemImage: "play.fill")
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
            viewModel.startHeartbeatPolling()
        }
        .onDisappear {
            viewModel.stopHeartbeatPolling()
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.daemonError != nil },
            set: { if !$0 { viewModel.daemonError = nil } }
        )) {
            Button("OK") { viewModel.daemonError = nil }
        } message: {
            Text(viewModel.daemonError ?? "")
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView(isPresented: $viewModel.showingSettings)
        }
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: ProjectInfo
    var isCurrentlySyncing: Bool = false
    var isSyncDone: Bool = false
    var isBackingUpIndividually: Bool = false
    var isSyncingGlobally: Bool = false
    let onBackup: () -> Void
    let onRevealInFinder: () -> Void
    let onViewBackupFolder: () -> Void
    let onViewLog: () -> Void
    let onToggleEnabled: () -> Void

    @State private var isHovered = false

    /// Row is actively doing work (spinner state)
    private var isActive: Bool {
        isCurrentlySyncing || isBackingUpIndividually
    }

    /// Backup button should be disabled
    private var isBusy: Bool {
        isActive || isSyncingGlobally
    }

    var body: some View {
        HStack {
            // Status icon -- spinner when actively syncing or backing up
            if isActive {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20)
            } else if isSyncDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .frame(width: 20)
            } else {
                Image(systemName: project.statusIcon)
                    .foregroundColor(project.statusColor)
                    .frame(width: 20)
            }

            // Project info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .fontWeight(.medium)
                        .foregroundColor(isActive ? .blue : .primary)
                    if let stats = project.statsText {
                        Text(stats)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                Text(project.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Last backup
            VStack(alignment: .trailing, spacing: 2) {
                if isBackingUpIndividually {
                    Text("Backing up\u{2026}")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else if isCurrentlySyncing {
                    Text("Syncing\u{2026}")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    HStack(spacing: 4) {
                        Text(project.lastBackupText)
                            .font(.caption)
                        // Last backup result indicator
                        switch project.lastBackupResult {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption2)
                        case .partial:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption2)
                        case .unknown:
                            EmptyView()
                        }
                    }
                }
            }

            // Backup button -- fades in on hover, spins while backing up
            Button(action: onBackup) {
                if isBackingUpIndividually {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)
            .opacity(isActive || isHovered ? 1.0 : 0.3)
            .help(isBusy ? "Backup in progress" : "Backup now")
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            onRevealInFinder()
        }
        .contextMenu {
            Button {
                onBackup()
            } label: {
                Label("Backup Now", systemImage: "arrow.clockwise")
            }
            .disabled(isBusy)

            Divider()

            Button {
                onRevealInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                onViewBackupFolder()
            } label: {
                Label("View Backup Folder", systemImage: "folder.badge.gearshape")
            }

            Button {
                onViewLog()
            } label: {
                Label("View Backup Log", systemImage: "doc.text")
            }

            Divider()

            Button {
                onToggleEnabled()
            } label: {
                Label(
                    project.enabled ? "Disable Backup" : "Enable Backup",
                    systemImage: project.enabled ? "pause.circle" : "play.circle"
                )
            }
        }
    }
}

// MARK: - Backup Result

enum BackupResult {
    case success
    case partial
    case failed
    case unknown
}

// MARK: - Settings View

struct SettingsView: View {
    @Binding var isPresented: Bool
    @StateObject private var settings = SettingsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    settings.save()
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Schedule
                    SettingsSection(title: "Schedule", icon: "clock") {
                        HStack {
                            Text("Backup every")
                            Picker("", selection: $settings.backupInterval) {
                                Text("30 minutes").tag(1800)
                                Text("1 hour").tag(3600)
                                Text("2 hours").tag(7200)
                                Text("4 hours").tag(14400)
                                Text("8 hours").tag(28800)
                                Text("24 hours").tag(86400)
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }

                        HStack {
                            Text("Trigger after idle for")
                            Picker("", selection: $settings.idleThreshold) {
                                Text("5 minutes").tag(300)
                                Text("10 minutes").tag(600)
                                Text("15 minutes").tag(900)
                                Text("30 minutes").tag(1800)
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                    }

                    // Retention
                    SettingsSection(title: "Retention", icon: "calendar.badge.clock") {
                        HStack {
                            Text("Keep database backups for")
                            Picker("", selection: $settings.dbRetentionDays) {
                                Text("7 days").tag(7)
                                Text("14 days").tag(14)
                                Text("30 days").tag(30)
                                Text("60 days").tag(60)
                                Text("90 days").tag(90)
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }

                        HStack {
                            Text("Keep file versions for")
                            Picker("", selection: $settings.fileRetentionDays) {
                                Text("14 days").tag(14)
                                Text("30 days").tag(30)
                                Text("60 days").tag(60)
                                Text("90 days").tag(90)
                                Text("180 days").tag(180)
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }

                    // What to Backup
                    SettingsSection(title: "What to Backup", icon: "doc.on.doc") {
                        Toggle("Environment files (.env)", isOn: $settings.backupEnvFiles)
                        Toggle("Credentials (.pem, .key, credentials.json)", isOn: $settings.backupCredentials)
                        Toggle("IDE settings (.vscode, .idea)", isOn: $settings.backupIdeSettings)
                    }

                    // Notifications
                    SettingsSection(title: "Notifications", icon: "bell") {
                        Toggle("Show desktop notifications", isOn: $settings.desktopNotifications)
                        Toggle("Only notify on failures", isOn: $settings.notifyOnFailureOnly)
                            .disabled(!settings.desktopNotifications)
                    }

                    // Advanced
                    SettingsSection(title: "Advanced", icon: "gearshape.2") {
                        HStack {
                            Text("Database compression")
                            Picker("", selection: $settings.compressionLevel) {
                                Text("Low (faster)").tag(1)
                                Text("Medium").tag(3)
                                Text("Default").tag(6)
                                Text("Maximum (slower)").tag(9)
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }

                        Toggle("Debug logging", isOn: $settings.debugMode)
                    }
                }
                .padding()
            }
        }
        .frame(width: 480, height: 520)
    }
}

// MARK: - Settings Section Helper

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(.leading, 4)
        }
    }
}

// MARK: - Settings View Model

class SettingsViewModel: ObservableObject {
    // Schedule
    @Published var backupInterval: Int = 3600
    @Published var idleThreshold: Int = 600

    // Retention
    @Published var dbRetentionDays: Int = 30
    @Published var fileRetentionDays: Int = 60

    // What to Backup
    @Published var backupEnvFiles: Bool = true
    @Published var backupCredentials: Bool = true
    @Published var backupIdeSettings: Bool = true

    // Notifications
    @Published var desktopNotifications: Bool = false
    @Published var notifyOnFailureOnly: Bool = true

    // Advanced
    @Published var compressionLevel: Int = 6
    @Published var debugMode: Bool = false

    private let configURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/checkpoint/config.sh")
    }()

    /// Raw lines of the config file, preserved for writing back
    private var rawLines: [String] = []

    init() {
        load()
    }

    func load() {
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        rawLines = contents.components(separatedBy: "\n")

        let values = parseShellConfig(contents)

        if let v = values["DEFAULT_BACKUP_INTERVAL"], let n = Int(v) { backupInterval = n }
        if let v = values["DEFAULT_SESSION_IDLE_THRESHOLD"], let n = Int(v) { idleThreshold = n }
        if let v = values["DEFAULT_DB_RETENTION_DAYS"], let n = Int(v) { dbRetentionDays = n }
        if let v = values["DEFAULT_FILE_RETENTION_DAYS"], let n = Int(v) { fileRetentionDays = n }
        if let v = values["DEFAULT_BACKUP_ENV_FILES"] { backupEnvFiles = v == "true" }
        if let v = values["DEFAULT_BACKUP_CREDENTIALS"] { backupCredentials = v == "true" }
        if let v = values["DEFAULT_BACKUP_IDE_SETTINGS"] { backupIdeSettings = v == "true" }
        if let v = values["DESKTOP_NOTIFICATIONS"] { desktopNotifications = v == "true" }
        if let v = values["NOTIFY_ON_FAILURE_ONLY"] { notifyOnFailureOnly = v == "true" }
        if let v = values["COMPRESSION_LEVEL"], let n = Int(v) { compressionLevel = n }
        if let v = values["DEBUG_MODE"] { debugMode = v == "true" }
    }

    func save() {
        // Update values in the raw lines, preserving comments and structure
        let updates: [(String, String)] = [
            ("DEFAULT_BACKUP_INTERVAL", "\(backupInterval)"),
            ("DEFAULT_SESSION_IDLE_THRESHOLD", "\(idleThreshold)"),
            ("DEFAULT_DB_RETENTION_DAYS", "\(dbRetentionDays)"),
            ("DEFAULT_FILE_RETENTION_DAYS", "\(fileRetentionDays)"),
            ("DEFAULT_BACKUP_ENV_FILES", backupEnvFiles ? "true" : "false"),
            ("DEFAULT_BACKUP_CREDENTIALS", backupCredentials ? "true" : "false"),
            ("DEFAULT_BACKUP_IDE_SETTINGS", backupIdeSettings ? "true" : "false"),
            ("DESKTOP_NOTIFICATIONS", desktopNotifications ? "true" : "false"),
            ("NOTIFY_ON_FAILURE_ONLY", notifyOnFailureOnly ? "true" : "false"),
            ("COMPRESSION_LEVEL", "\(compressionLevel)"),
            ("DEBUG_MODE", debugMode ? "true" : "false"),
        ]

        for (key, value) in updates {
            updateLine(key: key, value: value)
        }

        let output = rawLines.joined(separator: "\n")
        try? output.write(to: configURL, atomically: true, encoding: .utf8)
    }

    /// Parse KEY=VALUE lines from shell config, stripping quotes
    private func parseShellConfig(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            var value = String(parts[1])
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    /// Update a specific KEY=VALUE line in rawLines, preserving the line position
    private func updateLine(key: String, value: String) {
        for i in rawLines.indices {
            let trimmed = rawLines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key)=") {
                rawLines[i] = "\(key)=\(value)"
                return
            }
        }
        // Key not found - append before the last empty lines
        rawLines.append("\(key)=\(value)")
    }
}

// MARK: - View Model

class DashboardViewModel: ObservableObject {
    @Published var projects: [ProjectInfo] = []
    @Published var daemonRunning = false
    @Published var isBackingUp = false
    @Published var backingUpProjects: Set<String> = []
    @Published var daemonError: String?
    @Published var showingSettings = false
    @Published var refreshState: RefreshState = .idle

    enum RefreshState {
        case idle, refreshing, done
    }

    // Individual project backup progress (from progress file)
    @Published var backupProgressPercent: Int = 0
    @Published var backupProgressPhase: String = ""
    @Published var backupProgressTotal: Int = 0

    var backupProgressPhaseText: String {
        switch backupProgressPhase {
        case "initializing": return "Initializing\u{2026}"
        case "scanning":     return "Scanning for changes\u{2026}"
        case "preparing":    return "Preparing files\u{2026}"
        case "copying":      return "Copying files\u{2026}"
        case "verifying":    return "Verifying integrity\u{2026}"
        case "manifest":     return "Writing manifest\u{2026}"
        case "finalizing":   return "Finalizing\u{2026}"
        default:             return "Working\u{2026}"
        }
    }

    // Live sync progress from heartbeat
    @Published var syncIndex: Int = 0
    @Published var syncTotal: Int = 0
    @Published var syncCurrentProject: String = ""
    @Published var syncBackedUp: Int = 0
    @Published var syncFailed: Int = 0
    @Published var syncSkipped: Int = 0
    @Published var isSyncing: Bool = false
    @Published var completedProjects: Set<String> = []

    private var lastSeenProject: String = ""
    private var refreshTimer: Timer?
    private var heartbeatTimer: Timer?
    private var progressTimer: Timer?
    private var progressStartTime: Date?
    private let heartbeatMonitor = HeartbeatMonitor()
    private let progressFilePath: String = {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.checkpoint/backup-progress.json"
    }()

    /// Maximum time to poll progress before auto-stopping (30 minutes)
    private let progressTimeoutInterval: TimeInterval = 30 * 60

    init() {
        // Auto-refresh project list every 30 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        heartbeatTimer?.invalidate()
        progressTimer?.invalidate()
    }

    func startHeartbeatPolling() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.pollHeartbeat()
        }
        pollHeartbeat()
    }

    func stopHeartbeatPolling() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        isSyncing = false
        completedProjects.removeAll()
        lastSeenProject = ""
    }

    private func pollHeartbeat() {
        let data = heartbeatMonitor.readStatus()
        DispatchQueue.main.async {
            if data.isSyncing {
                self.isSyncing = true
                self.syncIndex = data.syncingProjectIndex ?? self.syncIndex
                self.syncTotal = data.syncingTotalProjects ?? self.syncTotal
                if let proj = data.syncingCurrentProject, !proj.isEmpty {
                    // When current project changes, the previous one is done
                    if !self.lastSeenProject.isEmpty && proj != self.lastSeenProject {
                        self.completedProjects.insert(self.lastSeenProject)
                        // Refresh project list to update "Never" -> real timestamp
                        self.loadProjects()
                    }
                    self.lastSeenProject = proj
                    self.syncCurrentProject = proj
                }
                self.syncBackedUp = data.syncingBackedUp ?? self.syncBackedUp
                self.syncFailed = data.syncingFailed ?? self.syncFailed
                self.syncSkipped = data.syncingSkipped ?? self.syncSkipped
            } else if self.isSyncing && data.status != .syncing {
                // Sync just finished
                self.isSyncing = false
                self.isBackingUp = false
                self.completedProjects.removeAll()
                self.lastSeenProject = ""
                self.refresh()
            }
        }
    }

    func refresh() {
        refreshState = .refreshing
        daemonRunning = DaemonController.isRunning()
        loadProjects()
        refreshState = .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.refreshState == .done {
                self.refreshState = .idle
            }
        }
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

        projects = projectsArray.compactMap({ dict -> ProjectInfo? in
            guard let path = dict["path"] as? String else { return nil }
            let name = (path as NSString).lastPathComponent
            let enabled = dict["enabled"] as? Bool ?? true
            let lastBackup: Date?
            if let ts = dict["last_backup"] as? TimeInterval {
                lastBackup = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
            } else if let str = dict["last_backup"] as? String {
                lastBackup = ISO8601DateFormatter().date(from: str)
            } else {
                lastBackup = nil
            }

            var info = ProjectInfo(
                id: path,
                name: name,
                path: path,
                enabled: enabled,
                lastBackup: lastBackup
            )

            // Read file count, size, and last backup result from manifest/logs
            info.loadBackupStats()

            return info
        }).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func backupProject(_ project: ProjectInfo) {
        guard !backingUpProjects.contains(project.id) else { return }
        guard !isSyncing else { return }
        backingUpProjects.insert(project.id)
        startProgressPolling()

        DispatchQueue.global(qos: .userInitiated).async {
            let home = FileManager.default.homeDirectoryForCurrentUser.path

            // Find backup-now command (same pattern as DaemonController.runBackupNow)
            let possiblePaths = [
                "\(home)/.local/bin/backup-now",
                "/usr/local/bin/backup-now"
            ]
            let backupCommand = possiblePaths.first { FileManager.default.fileExists(atPath: $0) }

            guard let command = backupCommand else {
                NSLog("CheckpointHelper: backup-now command not found")
                DispatchQueue.main.async {
                    self.backingUpProjects.remove(project.id)
                    self.stopProgressPolling()
                }
                return
            }

            let task = Process()
            task.launchPath = command
            task.arguments = ["--force", project.path]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                NSLog("CheckpointHelper: started backup for %@, pid=%d", project.name, task.processIdentifier)
                task.waitUntilExit()
                NSLog("CheckpointHelper: backup for %@ finished, exit=%d", project.name, task.terminationStatus)
            } catch {
                NSLog("CheckpointHelper: backupProject launch failed: %@", error.localizedDescription)
            }

            DispatchQueue.main.async {
                self.backingUpProjects.remove(project.id)
                self.stopProgressPolling()
                self.refresh()
            }
        }
    }

    private func startProgressPolling() {
        progressTimer?.invalidate()
        progressStartTime = Date()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.pollProgress()
        }
    }

    private func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
        progressStartTime = nil
        backupProgressPercent = 0
        backupProgressPhase = ""
        backupProgressTotal = 0
    }

    private func pollProgress() {
        // Timeout: auto-stop polling after 30 minutes to prevent infinite polling
        if let startTime = progressStartTime,
           Date().timeIntervalSince(startTime) > progressTimeoutInterval {
            NSLog("CheckpointHelper: progress polling timed out after 30 minutes")
            backingUpProjects.removeAll()
            stopProgressPolling()
            refresh()
            return
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: progressFilePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        DispatchQueue.main.async {
            self.backupProgressPercent = (json["percent"] as? Int) ?? self.backupProgressPercent
            self.backupProgressPhase = (json["phase"] as? String) ?? self.backupProgressPhase
            self.backupProgressTotal = (json["total_files"] as? Int) ?? self.backupProgressTotal
        }
    }

    func backupAll() {
        isBackingUp = true
        startHeartbeatPolling()
        DaemonController.runBackupNow { [weak self] success, output in
            // Don't stop polling immediately -- let pollHeartbeat detect the
            // finished state and do a clean transition. Just clear isBackingUp
            // after a short delay to let the final heartbeat be read.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.isBackingUp = false
                self?.pollHeartbeat()
                self?.refresh()
            }
        }
    }

    func startDaemon() {
        let success = DaemonController.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.refresh()
            if !success {
                self.daemonError = "Could not resume automatic backups. The background service may not be installed yet.\n\nRun 'checkpoint install' in Terminal to set it up."
            }
        }
    }

    func stopDaemon() {
        let success = DaemonController.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.refresh()
            if !success {
                self.daemonError = "Could not pause automatic backups. They may already be paused."
            }
        }
    }

    // MARK: - Context Menu Actions

    func revealInFinder(_ project: ProjectInfo) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
    }

    func viewBackupFolder(_ project: ProjectInfo) {
        let backupPath = "\(project.path)/backups"
        if FileManager.default.fileExists(atPath: backupPath) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupPath)
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
        }
    }

    func viewLog(_ project: ProjectInfo) {
        let logPath = "\(project.path)/backups/backup.log"
        if FileManager.default.fileExists(atPath: logPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
        }
    }

    func toggleEnabled(_ project: ProjectInfo) {
        let registryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/checkpoint/projects.json")

        guard let data = try? Data(contentsOf: registryURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var projectsArray = json["projects"] as? [[String: Any]] else {
            return
        }

        // Find and toggle the project's enabled state
        for i in projectsArray.indices {
            if let path = projectsArray[i]["path"] as? String, path == project.path {
                let currentEnabled = projectsArray[i]["enabled"] as? Bool ?? true
                projectsArray[i]["enabled"] = !currentEnabled
                break
            }
        }

        json["projects"] = projectsArray

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: registryURL)
        }

        refresh()
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
    var fileCount: Int? = nil
    var lastBackupResult: BackupResult = .unknown

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

    var statsText: String? {
        guard let count = fileCount else { return backupSize }
        if let size = backupSize {
            return "\(count) files \u{2022} \(size)"
        }
        return "\(count) files"
    }

    mutating func loadBackupStats() {
        let manifestPath = "\(path)/backups/.checkpoint-manifest.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fallback: state file for file count only
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let stateFile = "\(home)/.claudecode-backups/state/\(name)/last-backup.json"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let summary = json["summary"] as? [String: Any],
               let total = summary["total_files"] as? Int {
                fileCount = total
            }
            // Still check log for backup result
            loadBackupResult()
            return
        }

        // File count from totals
        if let totals = json["totals"] as? [String: Any] {
            fileCount = totals["files"] as? Int
        }

        // Total size: sum files + databases from manifest
        // Use NSNumber to handle both Int and Double from JSON
        var totalBytes: Int64 = 0
        if let fileArray = json["files"] as? [[String: Any]] {
            for entry in fileArray {
                if let n = entry["size"] as? NSNumber {
                    totalBytes += n.int64Value
                }
            }
        }
        if let dbArray = json["databases"] as? [[String: Any]] {
            for entry in dbArray {
                if let n = entry["size"] as? NSNumber {
                    totalBytes += n.int64Value
                }
            }
        }
        if totalBytes > 0 {
            backupSize = formatBytes(totalBytes)
        }

        loadBackupResult()
    }

    /// Check the last 500 bytes of backup.log for error/warning markers
    private mutating func loadBackupResult() {
        guard lastBackup != nil else { return }
        let logPath = "\(path)/backups/backup.log"
        guard let fileHandle = FileHandle(forReadingAtPath: logPath) else { return }
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()
        let readOffset: UInt64 = fileSize > 500 ? fileSize - 500 : 0
        fileHandle.seek(toFileOffset: readOffset)
        let tailData = fileHandle.readDataToEndOfFile()
        guard let tail = String(data: tailData, encoding: .utf8) else { return }

        if tail.contains("[ERROR]") {
            lastBackupResult = .failed
        } else if tail.contains("[WARN]") {
            lastBackupResult = .partial
        } else {
            lastBackupResult = .success
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
}
