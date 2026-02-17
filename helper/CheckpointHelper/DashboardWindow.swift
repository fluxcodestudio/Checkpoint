import Cocoa
import SwiftUI

// MARK: - Dashboard Window Controller

class DashboardWindowController: NSWindowController {

    static let shared = DashboardWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Checkpoint"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.setFrameAutosaveName("CheckpointDashboard")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 420)
        window.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)

        super.init(window: window)

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

// MARK: - Brand Colors

extension Color {
    static let cpBg = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let cpSurface = Color(red: 0.12, green: 0.12, blue: 0.15)
    static let cpSurfaceHover = Color(red: 0.15, green: 0.15, blue: 0.19)
    static let cpBorder = Color.white.opacity(0.06)
    static let cpTextPrimary = Color.white
    static let cpTextSecondary = Color.white.opacity(0.5)
    static let cpTextTertiary = Color.white.opacity(0.3)
    static let cpAccent = Color(red: 0.65, green: 0.40, blue: 1.0)         // Vivid purple
    static let cpAccentWarm = Color(red: 1.0, green: 0.55, blue: 0.25)    // Warm orange
    static let cpWarning = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let cpDanger = Color(red: 0.96, green: 0.36, blue: 0.36)
    static let cpBlue = Color(red: 0.35, green: 0.55, blue: 1.0)
}

// MARK: - Shield Logo

struct CheckpointShield: View {
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let img = NSImage(named: "checkpoint-logo") {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                // Fallback if image not found
                Image(systemName: "shield.checkmark.fill")
                    .font(.system(size: size, weight: .medium))
                    .foregroundColor(.cpAccent)
            }
        }
    }
}

// MARK: - SwiftUI Dashboard View

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        ZStack {
            // Base background
            Color.cpBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Draggable title bar region
                Color.clear
                    .frame(height: 28)

                // Header
                headerView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                // Active banners
                if !viewModel.backingUpProjects.isEmpty && !viewModel.isSyncing {
                    backupBanner
                }
                if viewModel.isSyncing {
                    syncBanner
                }

                // Projects list
                if viewModel.projects.isEmpty {
                    emptyState
                } else {
                    projectsList
                }

                // Footer toolbar
                footerView
            }
        }
        .frame(minWidth: 520, minHeight: 420)
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
        .onChange(of: viewModel.showingAbout) { showing in
            if showing {
                let dashboardWindow = NSApp.windows.first { $0.title == "Checkpoint" || $0.frameAutosaveName == "CheckpointDashboard" }
                AboutPanelController.shared.show(relativeTo: dashboardWindow, onClose: {
                    viewModel.showingAbout = false
                })
            } else {
                AboutPanelController.shared.close()
            }
        }
        .sheet(isPresented: $viewModel.showingUpdateCheck) {
            UpdateCheckView(isPresented: $viewModel.showingUpdateCheck, result: viewModel.updateCheckResult)
        }
        .sheet(isPresented: $viewModel.showingHelp) {
            HelpView(isPresented: $viewModel.showingHelp)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            CheckpointShield(size: 30)

            Text("Checkpoint")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundColor(.cpTextPrimary)

            Spacer()

            // Status pill
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.daemonRunning ? Color.cpAccent : Color.cpDanger)
                    .frame(width: 7, height: 7)
                    .shadow(color: viewModel.daemonRunning ? .cpAccent.opacity(0.5) : .cpDanger.opacity(0.5), radius: 4)
                Text(viewModel.daemonRunning ? "Active" : "Paused")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(viewModel.daemonRunning ? .cpAccent : .cpDanger)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill((viewModel.daemonRunning ? Color.cpAccent : Color.cpDanger).opacity(0.12))
                    .overlay(
                        Capsule()
                            .strokeBorder((viewModel.daemonRunning ? Color.cpAccent : Color.cpDanger).opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - Backup Banner

    private var backupBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.cpAccentWarm)
                Text("Backing up\u{2026}")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.cpAccentWarm)
                Spacer()
            }
            ForEach(Array(viewModel.backingUpProjects), id: \.self) { projectId in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.cpAccentWarm.opacity(0.7))
                        .font(.system(size: 10))
                    Text((projectId as NSString).lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.cpTextPrimary)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Text(viewModel.backupProgressPhaseText)
                    .font(.system(size: 11))
                    .foregroundColor(.cpTextSecondary)
                if viewModel.backupProgressTotal > 0 {
                    Text("\u{2022} \(viewModel.backupProgressTotal) files")
                        .font(.system(size: 11))
                        .foregroundColor(.cpTextSecondary)
                }
                Spacer()
            }

            ProgressView(value: Double(viewModel.backupProgressPercent), total: 100)
                .tint(.cpAccentWarm)
                .scaleEffect(y: 0.6)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.cpAccent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.cpAccent.opacity(0.15), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Sync Banner

    private var syncBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.cpAccentWarm)
                Text("Syncing \(viewModel.syncIndex) of \(viewModel.syncTotal)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.cpAccentWarm)
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.cpAccentWarm.opacity(0.7))
                    .font(.system(size: 10))
                Text(viewModel.syncCurrentProject)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.cpTextPrimary)
                Spacer()
            }

            HStack(spacing: 14) {
                Label("\(viewModel.syncBackedUp)", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.cpAccent)
                if viewModel.syncFailed > 0 {
                    Label("\(viewModel.syncFailed)", systemImage: "xmark.circle.fill")
                        .foregroundColor(.cpDanger)
                }
                if viewModel.syncSkipped > 0 {
                    Label("\(viewModel.syncSkipped)", systemImage: "minus.circle.fill")
                        .foregroundColor(.cpWarning)
                }
                Spacer()
            }
            .font(.system(size: 11, weight: .medium))

            ProgressView(value: Double(viewModel.syncIndex), total: Double(max(viewModel.syncTotal, 1)))
                .tint(.cpAccentWarm)
                .scaleEffect(y: 0.6)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.cpAccent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.cpAccent.opacity(0.15), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.cpTextTertiary)
            Text("No projects configured")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.cpTextSecondary)
            Text("Run backup-now in a project directory")
                .font(.system(size: 12))
                .foregroundColor(.cpTextTertiary)
            Spacer()
        }
    }

    // MARK: - Projects List

    private var projectsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.projects) { project in
                    ProjectRow(
                        project: project,
                        isCurrentlySyncing: viewModel.isSyncing && viewModel.syncCurrentProject == project.name,
                        isSyncDone: viewModel.isSyncing && viewModel.completedProjects.contains(project.name),
                        isBackingUpIndividually: viewModel.backingUpProjects.contains(project.id),
                        isSyncingGlobally: viewModel.isSyncing,
                        onBackup: { viewModel.backupProject(project) },
                        onRevealInFinder: { viewModel.revealInFinder(project) },
                        onViewBackupFolder: { viewModel.viewBackupFolder(project) },
                        onViewLog: { viewModel.viewLog(project) },
                        onToggleEnabled: { viewModel.toggleEnabled(project) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 0) {
            // Action bar
            HStack(spacing: 10) {
                // Backup All
                Button(action: viewModel.backupAll) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Backup All")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(CPButtonStyle(accent: .cpAccent))
                .disabled(viewModel.isBackingUp)
                .keyboardShortcut("b", modifiers: .command)

                // Settings
                Button(action: { viewModel.dismissAllModals(); viewModel.showingSettings = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "gear")
                            .font(.system(size: 11))
                        Text("Settings")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(CPButtonStyle(accent: .cpTextSecondary))
                .keyboardShortcut(",", modifiers: .command)

                Spacer()

                // Help
                Button(action: { viewModel.dismissAllModals(); viewModel.showingHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(CPIconButtonStyle())
                .help("How it Works")

                // Info / About
                Button(action: { viewModel.dismissAllModals(); viewModel.showingAbout = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(CPIconButtonStyle())

                // Check for Updates
                Button(action: { viewModel.dismissAllModals(); viewModel.checkForUpdates() }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(CPIconButtonStyle())
                .help("Check for Updates")

                // Refresh
                Button(action: viewModel.refresh) {
                    HStack(spacing: 4) {
                        switch viewModel.refreshState {
                        case .idle:
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                        case .refreshing:
                            ProgressView()
                                .controlSize(.mini)
                        case .done:
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cpAccent)
                        }
                    }
                }
                .buttonStyle(CPIconButtonStyle())
                .keyboardShortcut("r", modifiers: .command)

                // Pause / Resume
                if viewModel.daemonRunning {
                    Button(action: viewModel.stopDaemon) {
                        HStack(spacing: 5) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 9))
                            Text("Pause")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(CPButtonStyle(accent: .cpTextSecondary))
                } else {
                    Button(action: viewModel.startDaemon) {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text("Resume")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(CPButtonStyle(accent: .cpAccent, filled: true))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Attribution bar
            HStack {
                Spacer()
                Text("A product of ")
                    .font(.system(size: 10))
                    .foregroundColor(.cpTextTertiary)
                +
                Text("FluxCode.Studio")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.cpAccent.opacity(0.7))
                Spacer()
            }
            .padding(.bottom, 8)
            .onTapGesture {
                if let url = URL(string: "https://fluxcode.studio") {
                    NSWorkspace.shared.open(url)
                }
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .background(Color.cpSurface.opacity(0.7))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.cpBorder).frame(height: 0.5)
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

    private var isActive: Bool {
        isCurrentlySyncing || isBackingUpIndividually
    }

    private var isBusy: Bool {
        isActive || isSyncingGlobally
    }

    private var rowStatusColor: Color {
        if isActive { return .cpAccentWarm }
        if isSyncDone { return .cpAccent }
        return project.statusColor
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator — thin colored bar on left edge
            RoundedRectangle(cornerRadius: 1.5)
                .fill(rowStatusColor)
                .frame(width: 3, height: 32)
                .shadow(color: rowStatusColor.opacity(0.4), radius: 3, x: 0, y: 0)

            // Status icon
            ZStack {
                if isActive {
                    ProgressView()
                        .controlSize(.small)
                } else if isSyncDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cpAccent)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: project.statusIcon)
                        .foregroundColor(project.statusColor)
                        .font(.system(size: 14))
                }
            }
            .frame(width: 18)

            // Project info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isActive ? .cpAccentWarm : .cpTextPrimary)
                        .lineLimit(1)

                    if let stats = project.statsText {
                        Text(stats)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.cpTextTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.05))
                            )
                    }
                }
                Text(project.path)
                    .font(.system(size: 11))
                    .foregroundColor(.cpTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            // Last backup time + result
            VStack(alignment: .trailing, spacing: 2) {
                if isBackingUpIndividually {
                    Text("Backing up\u{2026}")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cpAccentWarm)
                } else if isCurrentlySyncing {
                    Text("Syncing\u{2026}")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cpAccentWarm)
                } else {
                    HStack(spacing: 4) {
                        Text(project.lastBackupText)
                            .font(.system(size: 11))
                            .foregroundColor(.cpTextSecondary)
                        resultIcon
                    }
                }
            }

            // Backup button
            Button(action: onBackup) {
                if isBackingUpIndividually {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cpTextSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isActive || isHovered ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .frame(width: 24)
            .help(isBusy ? "Backup in progress" : "Backup now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.cpSurfaceHover : Color.cpSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isHovered ? Color.cpBorder : .clear, lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            onRevealInFinder()
        }
        .contextMenu {
            Button { onBackup() } label: {
                Label("Backup Now", systemImage: "arrow.clockwise")
            }
            .disabled(isBusy)

            Divider()

            Button { onRevealInFinder() } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button { onViewBackupFolder() } label: {
                Label("View Backup Folder", systemImage: "folder.badge.gearshape")
            }

            Button { onViewLog() } label: {
                Label("View Backup Log", systemImage: "doc.text")
            }

            Divider()

            Button { onToggleEnabled() } label: {
                Label(
                    project.enabled ? "Disable Backup" : "Enable Backup",
                    systemImage: project.enabled ? "pause.circle" : "play.circle"
                )
            }
        }
    }

    @ViewBuilder
    private var resultIcon: some View {
        switch project.lastBackupResult {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.cpAccent)
                .font(.system(size: 11))
        case .partial:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.cpWarning)
                .font(.system(size: 11))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.cpDanger)
                .font(.system(size: 11))
        case .unknown:
            EmptyView()
        }
    }
}

// MARK: - Custom Button Styles

struct CPButtonStyle: ButtonStyle {
    var accent: Color = .cpTextSecondary
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(filled ? .cpBg : accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(filled ? accent : accent.opacity(configuration.isPressed ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(filled ? .clear : accent.opacity(0.2), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CPIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.cpTextSecondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.cpTextSecondary.opacity(configuration.isPressed ? 0.15 : 0.08))
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
        ZStack {
            Color.cpBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Text("Settings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.cpTextPrimary)
                    Spacer()
                    Button("Done") {
                        settings.save()
                        isPresented = false
                    }
                    .buttonStyle(CPButtonStyle(accent: .cpAccent, filled: true))
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.cpBorder).frame(height: 0.5)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        SettingsSection(title: "Schedule", icon: "clock") {
                            SettingRow(label: "Backup every") {
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

                            SettingRow(label: "Trigger after idle") {
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

                        SettingsSection(title: "Retention", icon: "calendar.badge.clock") {
                            SettingRow(label: "Database backups") {
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

                            SettingRow(label: "File versions") {
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

                        SettingsSection(title: "What to Backup", icon: "doc.on.doc") {
                            Toggle("Environment files (.env)", isOn: $settings.backupEnvFiles)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                            Toggle("Credentials (.pem, .key)", isOn: $settings.backupCredentials)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                            Toggle("IDE settings (.vscode, .idea)", isOn: $settings.backupIdeSettings)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                        }

                        SettingsSection(title: "Notifications", icon: "bell") {
                            Toggle("Desktop notifications", isOn: $settings.desktopNotifications)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                            Toggle("Only on failures", isOn: $settings.notifyOnFailureOnly)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                                .disabled(!settings.desktopNotifications)
                                .opacity(settings.desktopNotifications ? 1 : 0.4)
                        }

                        SettingsSection(title: "Cloud Encryption", icon: "lock.shield") {
                            Toggle("Encrypt cloud backups", isOn: $settings.encryptionEnabled)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                                .onChange(of: settings.encryptionEnabled) { newValue in
                                    if !newValue {
                                        settings.showEncryptionWarning = true
                                    }
                                }

                            if settings.encryptionEnabled {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.cpAccent)
                                    Text("Files are encrypted with age before cloud upload")
                                        .font(.system(size: 11))
                                        .foregroundColor(.cpTextSecondary)
                                }
                            }
                        }
                        .alert("Disable Encryption?", isPresented: $settings.showEncryptionWarning) {
                            Button("Keep Enabled") {
                                settings.encryptionEnabled = true
                            }
                            Button("Disable", role: .destructive) {
                                // Stay disabled
                            }
                        } message: {
                            Text("Disabling encryption means your backup files will be stored in plaintext on cloud storage. Anyone with access to your cloud account could read your source code, credentials, and environment files.")
                        }

                        SettingsSection(title: "Advanced", icon: "gearshape.2") {
                            SettingRow(label: "Compression") {
                                Picker("", selection: $settings.compressionLevel) {
                                    Text("Low").tag(1)
                                    Text("Medium").tag(3)
                                    Text("Default").tag(6)
                                    Text("Maximum").tag(9)
                                }
                                .labelsHidden()
                                .frame(width: 120)
                            }

                            Toggle("Debug logging", isOn: $settings.debugMode)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 480, height: 520)
    }
}

// MARK: - About Panel (custom NSPanel for transparent overflow)

class AboutPanelController: NSObject, NSWindowDelegate {
    static let shared = AboutPanelController()
    private var panel: NSPanel?
    private var onCloseCallback: (() -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(relativeTo parentWindow: NSWindow?, onClose: (() -> Void)? = nil) {
        self.onCloseCallback = onClose

        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let logoOverhang: CGFloat = 56
        let cardWidth: CGFloat = 320
        let cardHeight: CGFloat = 320
        let totalHeight = logoOverhang + cardHeight

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: cardWidth, height: totalHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        // Center on parent window
        if let parent = parentWindow {
            let parentFrame = parent.frame
            let x = parentFrame.midX - cardWidth / 2
            let y = parentFrame.midY - totalHeight / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        let aboutView = AboutView(onClose: { [weak self] in
            self?.close()
        })
        let hostView = NSHostingView(rootView: aboutView)
        panel.contentView = hostView

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
        onCloseCallback?()
        onCloseCallback = nil
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        onCloseCallback?()
        onCloseCallback = nil
    }
}

struct AboutView: View {
    let onClose: () -> Void

    private let logoSize: CGFloat = 112
    private let logoOverhang: CGFloat = 56
    private let cardHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            // Logo floating above the card
            CheckpointShield(size: logoSize)
                .padding(.bottom, -logoOverhang)
                .zIndex(1)

            // Card body
            VStack(spacing: 14) {
                Spacer().frame(height: logoOverhang + 4)

                Text("Checkpoint")
                    .font(.system(size: 33, weight: .bold))
                    .foregroundColor(.cpTextPrimary)

                Text("Automated Developer Backup System")
                    .font(.system(size: 13))
                    .foregroundColor(.cpTextSecondary)

                Divider()
                    .background(Color.cpBorder)
                    .padding(.horizontal, 30)

                VStack(spacing: 8) {
                    Text("Designed by Jon Rezin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.cpTextPrimary)

                    Text("for FluxCode Studio")
                        .font(.system(size: 12))
                        .foregroundColor(.cpTextSecondary)

                    Text("fluxcode.studio")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cpAccent)
                        .onTapGesture {
                            if let url = URL(string: "https://fluxcode.studio") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                }

                VStack(spacing: 4) {
                    Text("github.com/fluxcodestudio/Checkpoint")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cpTextTertiary)
                        .onTapGesture {
                            if let url = URL(string: "https://github.com/fluxcodestudio/Checkpoint") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }

                    Text("Polyform Noncommercial License")
                        .font(.system(size: 10))
                        .foregroundColor(.cpTextTertiary)
                }

                Button("Close", action: onClose)
                    .buttonStyle(CPButtonStyle(accent: .cpTextSecondary))
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 6)
            }
            .frame(width: 320, height: cardHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cpBg)
            )
        }
        .frame(width: 320, height: logoOverhang + cardHeight)
        .background(Color.clear)
    }
}

// MARK: - Update Check View

struct UpdateCheckView: View {
    @Binding var isPresented: Bool
    let result: DashboardViewModel.UpdateCheckResult?

    var body: some View {
        VStack(spacing: 16) {
            Text("Check for Updates")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.cpTextPrimary)
                .padding(.top, 20)

            Spacer()

            Group {
                switch result {
                case .checking, .none:
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Checking GitHub\u{2026}")
                            .font(.system(size: 12))
                            .foregroundColor(.cpTextSecondary)
                    }

                case .upToDate(let version):
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.cpAccent)
                        Text("You\u{2019}re up to date!")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.cpTextPrimary)
                        Text("Current version: \(version)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.cpTextTertiary)
                    }

                case .updateAvailable(let local, let remote):
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.cpAccentWarm)
                        Text("Update Available")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.cpTextPrimary)
                        HStack(spacing: 8) {
                            Text(local)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.cpTextTertiary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(.cpTextTertiary)
                            Text(remote)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.cpAccent)
                        }
                        Text("Run `checkpoint update` to update")
                            .font(.system(size: 11))
                            .foregroundColor(.cpTextSecondary)
                            .padding(.top, 4)
                    }

                case .error(let msg):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.cpWarning)
                        Text("Could not check")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.cpTextPrimary)
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(.cpTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            Spacer()

            Button("Close") { isPresented = false }
                .buttonStyle(CPButtonStyle(accent: .cpTextSecondary))
                .keyboardShortcut(.cancelAction)
                .padding(.bottom, 20)
        }
        .frame(width: 300, height: 280)
        .background(Color.cpBg)
    }
}

// MARK: - Help View

struct HelpView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.cpAccent)
                Text("How Checkpoint Works")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.cpTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(Color.cpBorder)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpSection(
                        icon: "clock.arrow.circlepath",
                        title: "Automatic Backups",
                        text: "Checkpoint runs a background daemon that automatically backs up your registered projects on a schedule. No manual intervention needed."
                    )

                    helpSection(
                        icon: "folder.badge.plus",
                        title: "Project Registration",
                        text: "Register any project directory with `checkpoint add /path/to/project`. Each project is tracked independently with its own backup history."
                    )

                    helpSection(
                        icon: "doc.on.doc",
                        title: "What Gets Backed Up",
                        text: "All source code, configs, and project files. Regeneratable directories (node_modules, .git, build, dist, etc.) are automatically excluded to save space."
                    )

                    helpSection(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Change Detection",
                        text: "Checkpoint uses git status and file fingerprinting to detect changes. Only modified files are copied each cycle, keeping backups fast and incremental."
                    )

                    helpSection(
                        icon: "cloud.fill",
                        title: "Cloud Sync",
                        text: "Optionally sync backups to encrypted cloud storage via rclone. Supports any rclone-compatible provider (S3, B2, Google Drive, etc.)."
                    )

                    helpSection(
                        icon: "play.circle",
                        title: "Dashboard Controls",
                        text: "Use Backup All to trigger an immediate backup of all projects. Pause/Resume controls the background daemon. The status indicator shows if the daemon is running."
                    )

                    helpSection(
                        icon: "terminal",
                        title: "CLI Commands",
                        text: "`checkpoint status` \u{2014} view backup status\n`checkpoint history` \u{2014} browse backup history\n`checkpoint search` \u{2014} search across backups\n`checkpoint restore` \u{2014} restore files from backup"
                    )

                    // Link to repo
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("Full documentation & source code:")
                                .font(.system(size: 11))
                                .foregroundColor(.cpTextTertiary)
                            Text("github.com/fluxcodestudio/Checkpoint")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.cpAccent)
                                .onTapGesture {
                                    if let url = URL(string: "https://github.com/fluxcodestudio/Checkpoint") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .onHover { hovering in
                                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            Divider().background(Color.cpBorder)

            // Footer
            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .buttonStyle(CPButtonStyle(accent: .cpTextSecondary))
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 480)
        .background(Color.cpBg)
    }

    private func helpSection(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.cpAccent)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.cpTextPrimary)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.cpTextSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Settings Helpers

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.cpTextSecondary)
                    .textCase(.uppercase)

            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.cpAccent)
            }

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.cpSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.cpBorder, lineWidth: 0.5)
            )
        }
    }
}

struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.cpTextPrimary)
            Spacer()
            content
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

    // Encryption
    @Published var encryptionEnabled: Bool = true
    @Published var showEncryptionWarning: Bool = false

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
        if let v = values["ENCRYPTION_ENABLED"] { encryptionEnabled = v == "true" }
    }

    func save() {
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
            ("ENCRYPTION_ENABLED", encryptionEnabled ? "true" : "false"),
        ]

        for (key, value) in updates {
            updateLine(key: key, value: value)
        }

        let output = rawLines.joined(separator: "\n")
        try? output.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func parseShellConfig(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            var value = String(parts[1])
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    private func updateLine(key: String, value: String) {
        for i in rawLines.indices {
            let trimmed = rawLines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key)=") {
                rawLines[i] = "\(key)=\(value)"
                return
            }
        }
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
    @Published var showingAbout = false
    @Published var showingHelp = false
    @Published var showingUpdateCheck = false
    @Published var updateCheckResult: UpdateCheckResult?

    func dismissAllModals() {
        showingSettings = false
        showingHelp = false
        showingUpdateCheck = false
        if showingAbout {
            showingAbout = false
            AboutPanelController.shared.close()
        }
    }

    enum UpdateCheckResult {
        case checking
        case upToDate(version: String)
        case updateAvailable(local: String, remote: String)
        case error(String)
    }
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
                    if !self.lastSeenProject.isEmpty && proj != self.lastSeenProject {
                        self.completedProjects.insert(self.lastSeenProject)
                        self.loadProjects()
                    }
                    self.lastSeenProject = proj
                    self.syncCurrentProject = proj
                }
                self.syncBackedUp = data.syncingBackedUp ?? self.syncBackedUp
                self.syncFailed = data.syncingFailed ?? self.syncFailed
                self.syncSkipped = data.syncingSkipped ?? self.syncSkipped
            } else if self.isSyncing && data.status != .syncing {
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

    // MARK: - Update Check

    func checkForUpdates() {
        showingUpdateCheck = true
        updateCheckResult = .checking

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let installDir = self?.findInstallDir() ?? ""
            let dirURL = URL(fileURLWithPath: installDir)

            // Helper to run git commands
            func git(_ args: [String]) -> String? {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                proc.arguments = args
                proc.currentDirectoryURL = dirURL
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    guard proc.terminationStatus == 0 else { return nil }
                } catch { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Get local HEAD
            guard let localHash = git(["rev-parse", "HEAD"]), !localHash.isEmpty else {
                DispatchQueue.main.async {
                    self?.updateCheckResult = .error("Could not read local version at:\n\(installDir)")
                }
                return
            }

            // Fetch latest from remote (uses existing git credentials)
            let _ = git(["fetch", "origin", "--quiet"])

            // Get remote HEAD
            guard let remoteHash = git(["rev-parse", "origin/main"]), !remoteHash.isEmpty else {
                // Try origin/master as fallback
                guard let remoteHashMaster = git(["rev-parse", "origin/master"]), !remoteHashMaster.isEmpty else {
                    DispatchQueue.main.async {
                        self?.updateCheckResult = .error("Could not fetch remote version.\nIs the remote configured?")
                    }
                    return
                }
                let localShort = String(localHash.prefix(7))
                let remoteShort = String(remoteHashMaster.prefix(7))
                DispatchQueue.main.async {
                    if localHash == remoteHashMaster {
                        self?.updateCheckResult = .upToDate(version: localShort)
                    } else {
                        self?.updateCheckResult = .updateAvailable(local: localShort, remote: remoteShort)
                    }
                }
                return
            }

            let localShort = String(localHash.prefix(7))
            let remoteShort = String(remoteHash.prefix(7))

            DispatchQueue.main.async {
                if localHash == remoteHash {
                    self?.updateCheckResult = .upToDate(version: localShort)
                } else {
                    self?.updateCheckResult = .updateAvailable(local: localShort, remote: remoteShort)
                }
            }
        }
    }

    private func findInstallDir() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // 1. Walk up from the app bundle location (works when app lives inside the repo)
        var bundleDir = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        for _ in 0..<5 {
            if fm.fileExists(atPath: bundleDir + "/.git") { return bundleDir }
            bundleDir = (bundleDir as NSString).deletingLastPathComponent
        }

        // 2. Follow the checkpoint symlink to find the source tree
        let symlink = home + "/.local/bin/checkpoint"
        if let resolved = try? fm.destinationOfSymbolicLink(atPath: symlink) {
            var dir = (resolved as NSString).deletingLastPathComponent
            for _ in 0..<5 {
                if fm.fileExists(atPath: dir + "/.git") { return dir }
                dir = (dir as NSString).deletingLastPathComponent
            }
        }

        // 3. Check common install locations
        let candidates = [
            home + "/.local/lib/checkpoint",
            home + "/checkpoint",
            "/usr/local/lib/checkpoint"
        ]
        for path in candidates {
            if fm.fileExists(atPath: path + "/.git") { return path }
        }

        // 4. Check CHECKPOINT_DIR from config
        let configPath = home + "/.checkpoint/config"
        if let contents = try? String(contentsOfFile: configPath, encoding: .utf8) {
            for line in contents.components(separatedBy: "\n") {
                if line.hasPrefix("CHECKPOINT_DIR=") {
                    let val = line.replacingOccurrences(of: "CHECKPOINT_DIR=", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    if fm.fileExists(atPath: val + "/.git") { return val }
                }
            }
        }

        return candidates[0]
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
        guard enabled else { return .cpTextTertiary }
        guard let date = lastBackup else { return .cpTextTertiary }

        let hoursSince = Date().timeIntervalSince(date) / 3600
        if hoursSince < 2 {
            return .cpAccent
        } else if hoursSince < 24 {
            return .cpAccentWarm
        } else if hoursSince < 72 {
            return .cpWarning
        } else {
            return .cpDanger
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
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let stateFile = "\(home)/.claudecode-backups/state/\(name)/last-backup.json"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let summary = json["summary"] as? [String: Any],
               let total = summary["total_files"] as? Int {
                fileCount = total
            }
            loadBackupResult()
            return
        }

        if let totals = json["totals"] as? [String: Any] {
            fileCount = totals["files"] as? Int
        }

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
