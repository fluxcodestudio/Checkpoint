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
        // Apply float-on-top preference
        let floatOnTop = UserDefaults.standard.bool(forKey: "floatOnTop")
        window?.level = floatOnTop ? .floating : .normal
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CheckpointShowOnboarding"))) { _ in
            viewModel.showingOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CheckpointAddProject"))) { _ in
            viewModel.addProject()
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
        .sheet(isPresented: $viewModel.showingCloudBrowse) {
            if let project = viewModel.cloudBrowseProject {
                CloudBrowseView(isPresented: $viewModel.showingCloudBrowse, projectName: project.name)
            }
        }
        .sheet(isPresented: $viewModel.showingLogViewer) {
            if let project = viewModel.logViewerProject {
                LogViewerView(isPresented: $viewModel.showingLogViewer, project: project)
            }
        }
        .sheet(isPresented: $viewModel.showingOnboarding) {
            OnboardingView(isPresented: $viewModel.showingOnboarding, onAddProject: {
                viewModel.showingOnboarding = false
                viewModel.addProject()
            })
        }
        .alert("Remove Project", isPresented: $viewModel.showingRemoveConfirm) {
            Button("Cancel", role: .cancel) {
                viewModel.removeTargetProject = nil
            }
            Button("Remove", role: .destructive) {
                viewModel.confirmRemoveProject()
            }
        } message: {
            Text("Remove \(viewModel.removeTargetProject?.name ?? "") from Checkpoint? Backups will not be deleted.")
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
        let isCloud = viewModel.isCloudPhase
        let tintColor: Color = isCloud ? .cpBlue : .cpAccentWarm
        let bgColor: Color = isCloud ? .cpBlue : .cpAccent

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(tintColor)
                Text(isCloud ? "Uploading to cloud\u{2026}" : "Backing up\u{2026}")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tintColor)
                Spacer()
            }
            ForEach(Array(viewModel.backingUpProjects), id: \.self) { projectId in
                HStack(spacing: 6) {
                    Image(systemName: isCloud ? "cloud.fill" : "arrow.right.circle.fill")
                        .foregroundColor(tintColor.opacity(0.7))
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
                if !isCloud && viewModel.backupProgressTotal > 0 {
                    Text("\u{2022} \(viewModel.backupProgressTotal) files")
                        .font(.system(size: 11))
                        .foregroundColor(.cpTextSecondary)
                }
                Spacer()
            }

            ProgressView(value: Double(viewModel.backupProgressPercent), total: 100)
                .tint(tintColor)
                .scaleEffect(y: 0.6)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(bgColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(bgColor.opacity(0.15), lineWidth: 0.5)
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
            Text("Add a project folder to start backing up")
                .font(.system(size: 12))
                .foregroundColor(.cpTextTertiary)

            Button(action: viewModel.addProject) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13))
                    Text("Add Project")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(CPButtonStyle(accent: .cpAccent, filled: true))
            .padding(.top, 4)

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
                        onToggleEnabled: { viewModel.toggleEnabled(project) },
                        onBrowseCloud: { viewModel.browseCloud(project) },
                        onRemove: { viewModel.removeProject(project) }
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

                // Add Project
                Button(action: viewModel.addProject) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(CPButtonStyle(accent: .cpAccent))

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
    var onBrowseCloud: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

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

                if project.lastBackupResult == .failed && project.failureCount > 0 {
                    HStack(spacing: 4) {
                        Text("\(project.failureCount) file(s) failed")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.cpDanger)
                            .onTapGesture { onViewLog() }
                        if project.llmPrompt != nil {
                            Button(action: {
                                if let prompt = project.llmPrompt {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(prompt, forType: .string)
                                }
                            }) {
                                Text("Copy for AI")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.cpAccent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.cpAccent.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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

            if let browseCloud = onBrowseCloud {
                Divider()

                Button { browseCloud() } label: {
                    Label("Browse Cloud Backups", systemImage: "cloud")
                }
            }

            Divider()

            Button { onToggleEnabled() } label: {
                Label(
                    project.enabled ? "Disable Backup" : "Enable Backup",
                    systemImage: project.enabled ? "pause.circle" : "play.circle"
                )
            }

            if let remove = onRemove {
                Divider()

                Button(role: .destructive, action: remove) {
                    Label("Remove Project", systemImage: "trash")
                }
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

// MARK: - Schedule Helpers

private func scheduleDescription(_ schedule: String) -> String {
    switch schedule {
    case "@every-30min": return "Backs up every 30 minutes, all day"
    case "@hourly": return "Backs up once per hour, all day"
    case "@every-2h": return "Backs up every 2 hours, all day"
    case "@every-4h": return "Backs up every 4 hours, all day"
    case "@workhours": return "Every 30 min, Mon-Fri 9 AM - 5 PM"
    case "@weekdays": return "Hourly on weekdays only"
    case "@daily": return "Once per day at midnight"
    default: return "Custom cron schedule"
    }
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

                        SettingsSection(title: "Schedule", icon: "clock", tooltip: "Controls when and how often your projects are backed up. Pick a preset that fits your workflow.") {
                            SettingRow(label: "Schedule preset") {
                                Picker("", selection: $settings.backupSchedule) {
                                    Text("Every 30 min").tag("@every-30min")
                                    Text("Hourly").tag("@hourly")
                                    Text("Every 2 hours").tag("@every-2h")
                                    Text("Every 4 hours").tag("@every-4h")
                                    Text("Work hours (9-5 weekdays)").tag("@workhours")
                                    Text("Weekdays only").tag("@weekdays")
                                    Text("Daily").tag("@daily")
                                }
                                .labelsHidden()
                                .frame(width: 200)
                            }

                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.cpTextSecondary)
                                Text(scheduleDescription(settings.backupSchedule))
                                    .font(.system(size: 11))
                                    .foregroundColor(.cpTextSecondary)
                            }

                            SettingRow(label: "Fallback interval") {
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

                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.cpTextSecondary)
                                Text("Used when schedule is inactive (e.g., outside work hours)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.cpTextSecondary)
                            }
                        }

                        SettingsSection(title: "Retention", icon: "calendar.badge.clock", tooltip: "How long old backups are kept before being cleaned up. Longer = more history but more disk space.") {
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

                        SettingsSection(title: "What to Backup", icon: "doc.on.doc", tooltip: "Choose which sensitive file types to include. These are excluded by default in most backup tools.") {
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

                        SettingsSection(title: "Notifications", icon: "bell", tooltip: "Get macOS notifications when backups complete or fail. Useful for catching issues early.") {
                            Toggle("Desktop notifications", isOn: $settings.desktopNotifications)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                            Toggle("Only on failures", isOn: $settings.notifyOnFailureOnly)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                                .disabled(!settings.desktopNotifications)
                                .opacity(settings.desktopNotifications ? 1 : 0.4)
                        }

                        SettingsSection(title: "Cloud Encryption", icon: "lock.shield", tooltip: "Encrypts files locally before uploading to cloud storage. Your data stays private even if the cloud is compromised.") {
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

                        SettingsSection(title: "Window", icon: "macwindow", tooltip: "Controls dashboard window behavior. Float on top keeps it visible above other windows.") {
                            Toggle("Float on top", isOn: $settings.floatOnTop)
                                .toggleStyle(.switch)
                                .tint(.cpAccent)
                                .onChange(of: settings.floatOnTop) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "floatOnTop")
                                    DashboardWindowController.shared.window?.level = newValue ? .floating : .normal
                                    NotificationCenter.default.post(name: NSNotification.Name("CheckpointFloatOnTopChanged"), object: nil)
                                }
                        }

                        SettingsSection(title: "Advanced", icon: "gearshape.2", tooltip: "Fine-tune compression and enable debug logging. Higher compression saves disk space but slows backups.") {
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
                        text: "Register projects with the + Add button in the dashboard, or `checkpoint add /path/to/project` from the CLI. Remove with right-click \u{2192} Remove Project, or `checkpoint remove`. Use `checkpoint list` to see all projects."
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
                        text: "Sync backups to Dropbox, Google Drive, OneDrive, iCloud, or any rclone-compatible provider. Files are compressed with gzip and encrypted with age before upload. Parallel encryption across multiple CPU cores for large backups."
                    )

                    helpSection(
                        icon: "arrow.down.circle",
                        title: "Cloud Restore",
                        text: "Browse and download files from cloud backups with `checkpoint cloud browse`. Files are auto-decrypted and decompressed on download. Download individual files or entire backups as a zip."
                    )

                    helpSection(
                        icon: "play.circle",
                        title: "Dashboard Controls",
                        text: "Use + Add to register a new project folder. Backup All triggers an immediate backup. Pause/Resume controls the daemon. Right-click any project for actions including Remove Project and View Log."
                    )

                    helpSection(
                        icon: "terminal",
                        title: "CLI Commands",
                        text: "`checkpoint add <path>` \u{2014} register a project\n`checkpoint remove <path>` \u{2014} unregister a project\n`checkpoint list` \u{2014} list all projects\n`checkpoint status` \u{2014} view backup status\n`checkpoint history` \u{2014} browse backup history\n`checkpoint search` \u{2014} search across backups\n`checkpoint cloud browse` \u{2014} browse cloud backups"
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

// MARK: - Cloud Browse View

struct CloudBrowseView: View {
    @Binding var isPresented: Bool
    let projectName: String
    @StateObject private var viewModel = CloudBrowseViewModel()

    var body: some View {
        ZStack {
            Color.cpBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Image(systemName: "cloud")
                        .font(.system(size: 14))
                        .foregroundColor(.cpBlue)
                    Text("Cloud Backups")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.cpTextPrimary)
                    Text("\u{2014} \(projectName)")
                        .font(.system(size: 14))
                        .foregroundColor(.cpTextSecondary)
                    Spacer()
                    Button("Done") { isPresented = false }
                        .buttonStyle(CPButtonStyle(accent: .cpAccent, filled: true))
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.cpBorder).frame(height: 0.5)
                }

                // Content
                switch viewModel.state {
                case .loading:
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.regular)
                        Text("Loading cloud index\u{2026}")
                            .font(.system(size: 12))
                            .foregroundColor(.cpTextSecondary)
                    }
                    Spacer()

                case .error(let msg):
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.cpWarning)
                        Text(msg)
                            .font(.system(size: 13))
                            .foregroundColor(.cpTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    Spacer()

                case .noCloud:
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "cloud.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.cpTextTertiary)
                        Text("No cloud backups found")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.cpTextSecondary)
                        Text("Run a backup with cloud sync enabled to see backups here.")
                            .font(.system(size: 12))
                            .foregroundColor(.cpTextTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    Spacer()

                case .loaded:
                    // Backup selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.backups) { backup in
                                Button(action: { viewModel.selectBackup(backup.id) }) {
                                    VStack(spacing: 2) {
                                        Text(backup.displayDate)
                                            .font(.system(size: 11, weight: .medium))
                                        Text("\(backup.filesCount) files")
                                            .font(.system(size: 10))
                                            .foregroundColor(.cpTextTertiary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(viewModel.selectedBackupId == backup.id ? Color.cpAccent.opacity(0.2) : Color.cpSurface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(viewModel.selectedBackupId == backup.id ? Color.cpAccent.opacity(0.5) : Color.cpBorder, lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(viewModel.selectedBackupId == backup.id ? .cpAccent : .cpTextPrimary)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 10)

                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.cpTextTertiary)
                        TextField("Search files\u{2026}", text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(.cpTextPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.cpSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.cpBorder, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 16)

                    // Snapshot context bar
                    if let backup = viewModel.selectedBackup {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(.cpTextTertiary)
                            Text("Snapshot: \(backup.fullDate)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.cpTextSecondary)
                            Text("\u{2022}")
                                .foregroundColor(.cpTextTertiary)
                                .font(.system(size: 8))
                            Text("\(backup.filesCount) files, \(backup.databasesCount) db")
                                .font(.system(size: 11))
                                .foregroundColor(.cpTextTertiary)
                            Text("\u{2022}")
                                .foregroundColor(.cpTextTertiary)
                                .font(.system(size: 8))
                            Text(backup.sizeText)
                                .font(.system(size: 11))
                                .foregroundColor(.cpTextTertiary)
                            if backup.encrypted {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.cpAccent.opacity(0.6))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                    }

                    // File list
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            if !viewModel.filteredFiles.isEmpty {
                                cloudSectionHeader("FILES")
                                ForEach(viewModel.filteredFiles) { file in
                                    cloudFileRow(file)
                                }
                            }
                            if !viewModel.filteredDatabases.isEmpty {
                                cloudSectionHeader("DATABASES")
                                ForEach(viewModel.filteredDatabases) { db in
                                    cloudDatabaseRow(db)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }

                    // Footer with download buttons
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.cpBorder).frame(height: 0.5)
                        HStack(spacing: 10) {
                            if let progress = viewModel.downloadProgress {
                                ProgressView(value: progress.fraction)
                                    .tint(.cpAccent)
                                    .frame(maxWidth: .infinity)
                                Text(progress.label)
                                    .font(.system(size: 11))
                                    .foregroundColor(.cpTextSecondary)
                            } else {
                                Button(action: viewModel.downloadAll) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.system(size: 11))
                                        Text("Download All")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                }
                                .buttonStyle(CPButtonStyle(accent: .cpTextSecondary))

                                Button(action: viewModel.downloadZip) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "doc.zipper")
                                            .font(.system(size: 11))
                                        Text("Download Zip")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                }
                                .buttonStyle(CPButtonStyle(accent: .cpAccent, filled: true))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(Color.cpSurface.opacity(0.7))
                }
            }
        }
        .frame(width: 560, height: 500)
        .onAppear {
            viewModel.projectName = projectName
            viewModel.loadIndex()
        }
    }

    private func cloudSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.cpTextTertiary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func cloudFileRow(_ file: CloudFileEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 12))
                .foregroundColor(.cpTextTertiary)
                .frame(width: 16)
            Text(file.path)
                .font(.system(size: 12))
                .foregroundColor(.cpTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(file.sizeText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.cpTextTertiary)
            Button(action: { viewModel.downloadFile(file) }) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.cpAccent)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.downloadProgress != nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
        )
    }

    private func cloudDatabaseRow(_ db: CloudDatabaseEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cylinder")
                .font(.system(size: 12))
                .foregroundColor(.cpTextTertiary)
                .frame(width: 16)
            Text(db.path)
                .font(.system(size: 12))
                .foregroundColor(.cpTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let tables = db.tables, !tables.isEmpty {
                Text(tables)
                    .font(.system(size: 10))
                    .foregroundColor(.cpTextTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.05))
                    )
            }
            Spacer(minLength: 8)
            Text(db.sizeText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.cpTextTertiary)
            Button(action: { viewModel.downloadDatabase(db) }) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.cpAccent)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.downloadProgress != nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Cloud Browse View Model

class CloudBrowseViewModel: ObservableObject {
    enum ViewState {
        case loading, loaded, error(String), noCloud
    }

    struct DownloadProgress {
        var fraction: Double
        var label: String
    }

    var projectName: String = ""

    @Published var state: ViewState = .loading
    @Published var backups: [CloudBackupEntry] = []
    @Published var selectedBackupId: String?
    @Published var files: [CloudFileEntry] = []
    @Published var databases: [CloudDatabaseEntry] = []
    @Published var searchText: String = ""
    @Published var downloadProgress: DownloadProgress?

    var filteredFiles: [CloudFileEntry] {
        guard !searchText.isEmpty else { return files }
        let query = searchText.lowercased()
        return files.filter { $0.path.lowercased().contains(query) }
    }

    var filteredDatabases: [CloudDatabaseEntry] {
        guard !searchText.isEmpty else { return databases }
        let query = searchText.lowercased()
        return databases.filter { $0.path.lowercased().contains(query) }
    }

    var selectedBackup: CloudBackupEntry? {
        guard let id = selectedBackupId else { return nil }
        return backups.first { $0.id == id }
    }

    func loadIndex() {
        state = .loading

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.runCheckpointCloud(["list", self.projectName, "--json"])

            DispatchQueue.main.async {
                guard let data = result.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let backupsArray = json["backups"] as? [[String: Any]] else {
                    if result.contains("error") || result.isEmpty {
                        self.state = .noCloud
                    } else {
                        self.state = .error("Could not parse cloud index")
                    }
                    return
                }

                if backupsArray.isEmpty {
                    self.state = .noCloud
                    return
                }

                let encryptionEnabled = json["encryption_enabled"] as? Bool ?? false

                self.backups = backupsArray.compactMap { dict -> CloudBackupEntry? in
                    guard let backupId = dict["backup_id"] as? String else { return nil }
                    return CloudBackupEntry(
                        id: backupId,
                        backupId: backupId,
                        timestamp: dict["timestamp"] as? String ?? "",
                        filesCount: dict["files_count"] as? Int ?? 0,
                        databasesCount: dict["databases_count"] as? Int ?? 0,
                        totalSizeBytes: dict["total_size_bytes"] as? Int ?? 0,
                        encrypted: encryptionEnabled
                    )
                }

                self.state = .loaded

                // Auto-select latest
                if let first = self.backups.first {
                    self.selectBackup(first.id)
                }
            }
        }
    }

    func selectBackup(_ backupId: String) {
        selectedBackupId = backupId

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.runCheckpointCloud(["browse", self.projectName, backupId, "--json"])

            DispatchQueue.main.async {
                guard let data = result.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }

                // Parse files
                if let filesArray = json["files"] as? [[String: Any]] {
                    self.files = filesArray.compactMap { dict -> CloudFileEntry? in
                        guard let path = dict["path"] as? String else { return nil }
                        return CloudFileEntry(
                            id: path,
                            path: path,
                            size: dict["size"] as? Int ?? 0
                        )
                    }
                }

                // Parse databases
                if let dbArray = json["databases"] as? [[String: Any]] {
                    self.databases = dbArray.compactMap { dict -> CloudDatabaseEntry? in
                        guard let path = dict["path"] as? String else { return nil }
                        let tables = dict["tables"] as? Int
                        return CloudDatabaseEntry(
                            id: path,
                            path: path,
                            size: dict["size"] as? Int ?? 0,
                            tables: tables.map { "\($0) tables" }
                        )
                    }
                }
            }
        }
    }

    func downloadFile(_ file: CloudFileEntry) {
        guard let backupId = selectedBackupId else { return }
        downloadProgress = DownloadProgress(fraction: 0.3, label: "Downloading \(file.path)\u{2026}")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let _ = self.runCheckpointCloud([
                "download", file.path,
                "--project", self.projectName,
                "--backup-id", backupId,
                "--json"
            ])

            DispatchQueue.main.async {
                self.downloadProgress = DownloadProgress(fraction: 1.0, label: "Done!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.downloadProgress = nil
                }
            }
        }
    }

    func downloadDatabase(_ db: CloudDatabaseEntry) {
        guard let backupId = selectedBackupId else { return }
        downloadProgress = DownloadProgress(fraction: 0.3, label: "Downloading \(db.path)\u{2026}")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let _ = self.runCheckpointCloud([
                "download", db.path,
                "--project", self.projectName,
                "--backup-id", backupId,
                "--json"
            ])

            DispatchQueue.main.async {
                self.downloadProgress = DownloadProgress(fraction: 1.0, label: "Done!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.downloadProgress = nil
                }
            }
        }
    }

    func downloadAll() {
        guard let backupId = selectedBackupId else { return }
        downloadProgress = DownloadProgress(fraction: 0.1, label: "Downloading all files\u{2026}")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let _ = self.runCheckpointCloud([
                "download-all",
                "--project", self.projectName,
                "--backup-id", backupId,
                "--json"
            ])

            DispatchQueue.main.async {
                self.downloadProgress = DownloadProgress(fraction: 1.0, label: "Done!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.downloadProgress = nil
                }
            }
        }
    }

    func downloadZip() {
        guard let backupId = selectedBackupId else { return }
        downloadProgress = DownloadProgress(fraction: 0.1, label: "Creating zip archive\u{2026}")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let _ = self.runCheckpointCloud([
                "download-all",
                "--project", self.projectName,
                "--backup-id", backupId,
                "--zip",
                "--json"
            ])

            DispatchQueue.main.async {
                self.downloadProgress = DownloadProgress(fraction: 1.0, label: "Done!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.downloadProgress = nil
                }
            }
        }
    }

    private func runCheckpointCloud(_ args: [String]) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(home)/.local/bin/checkpoint",
            "/usr/local/bin/checkpoint"
        ]
        guard let command = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return ""
        }

        let task = Process()
        task.launchPath = command
        task.arguments = ["cloud"] + args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            NSLog("CheckpointHelper: cloud command failed: %@", error.localizedDescription)
            return ""
        }

        // Read output BEFORE waitUntilExit to avoid pipe buffer deadlock
        // (pipe buffer is ~64KB; large output like browse with 36K files is ~4MB)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - Cloud Data Models

struct CloudBackupEntry: Identifiable {
    let id: String
    let backupId: String
    let timestamp: String
    let filesCount: Int
    let databasesCount: Int
    let totalSizeBytes: Int
    let encrypted: Bool

    var displayDate: String {
        // Parse from backup_id format: YYYYMMDD_HHMMSS
        guard backupId.count >= 15 else { return backupId }
        let m = backupId.dropFirst(4).prefix(2)
        let d = backupId.dropFirst(6).prefix(2)
        let h = backupId.dropFirst(9).prefix(2)
        let mn = backupId.dropFirst(11).prefix(2)
        return "\(m)/\(d) \(h):\(mn)"
    }

    var fullDate: String {
        // Parse from backup_id format: YYYYMMDD_HHMMSS → "Feb 17, 2026 1:49 AM"
        guard backupId.count >= 15 else { return backupId }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        guard let date = formatter.date(from: String(backupId.prefix(15))) else { return backupId }
        let display = DateFormatter()
        display.dateFormat = "MMM d, yyyy h:mm a"
        return display.string(from: date)
    }

    var sizeText: String { formatSize(totalSizeBytes) }
}

struct CloudFileEntry: Identifiable {
    let id: String
    let path: String
    let size: Int

    var sizeText: String { formatSize(size) }
}

struct CloudDatabaseEntry: Identifiable {
    let id: String
    let path: String
    let size: Int
    let tables: String?

    var sizeText: String { formatSize(size) }
}

private func formatSize(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    let kb = Double(bytes) / 1024
    if kb < 1024 { return String(format: "%.0f KB", kb) }
    let mb = kb / 1024
    if mb < 1024 { return String(format: "%.1f MB", mb) }
    let gb = mb / 1024
    return String(format: "%.1f GB", gb)
}

// MARK: - Settings Helpers

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    var tooltip: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
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
                if let tip = tooltip {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.cpTextSecondary.opacity(0.6))
                        .help(tip)
                }
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
    @Published var backupSchedule: String = ""

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

    // Window
    @Published var floatOnTop: Bool = false

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

        // Sync float-on-top from menu bar toggle
        NotificationCenter.default.addObserver(forName: NSNotification.Name("CheckpointFloatOnTopChanged"),
                                               object: nil, queue: .main) { [weak self] _ in
            self?.floatOnTop = UserDefaults.standard.bool(forKey: "floatOnTop")
        }
    }

    func load() {
        // Float on top is stored in UserDefaults (not config.sh) for instant access
        floatOnTop = UserDefaults.standard.bool(forKey: "floatOnTop")

        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        rawLines = contents.components(separatedBy: "\n")

        let values = parseShellConfig(contents)

        if let v = values["DEFAULT_BACKUP_INTERVAL"], let n = Int(v) { backupInterval = n }
        if let v = values["DEFAULT_BACKUP_SCHEDULE"], !v.isEmpty {
            backupSchedule = v
        } else {
            // Infer schedule from interval for existing configs without a schedule
            switch backupInterval {
            case ...1800: backupSchedule = "@every-30min"
            case ...3600: backupSchedule = "@hourly"
            case ...7200: backupSchedule = "@every-2h"
            case ...14400: backupSchedule = "@every-4h"
            default: backupSchedule = "@hourly"
            }
        }
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
            ("DEFAULT_BACKUP_SCHEDULE", backupSchedule.isEmpty ? "@hourly" : backupSchedule),
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
        // Restrict config file permissions to owner-only read/write (0600)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configURL.path
        )
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
    @Published var showingCloudBrowse = false
    @Published var cloudBrowseProject: ProjectInfo?
    @Published var updateCheckResult: UpdateCheckResult?
    @Published var showingLogViewer = false
    @Published var logViewerProject: ProjectInfo?
    @Published var showingOnboarding = false
    @Published var showingRemoveConfirm = false
    @Published var removeTargetProject: ProjectInfo?

    func dismissAllModals() {
        showingSettings = false
        showingHelp = false
        showingUpdateCheck = false
        showingCloudBrowse = false
        cloudBrowseProject = nil
        showingLogViewer = false
        logViewerProject = nil
        showingOnboarding = false
        if showingAbout {
            showingAbout = false
            AboutPanelController.shared.close()
        }
    }

    func browseCloud(_ project: ProjectInfo) {
        dismissAllModals()
        cloudBrowseProject = project
        showingCloudBrowse = true
    }

    func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory to back up"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let projectPath = url.path
        backingUpProjects.insert(projectPath)
        startProgressPolling()

        DispatchQueue.global(qos: .userInitiated).async {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let possiblePaths = [
                "\(home)/.local/bin/backup-now",
                "/usr/local/bin/backup-now"
            ]
            let backupCommand = possiblePaths.first { FileManager.default.fileExists(atPath: $0) }

            guard let command = backupCommand else {
                DispatchQueue.main.async {
                    self.backingUpProjects.remove(projectPath)
                    self.stopProgressPolling()
                    self.daemonError = "backup-now command not found. Is Checkpoint installed?"
                }
                return
            }

            let task = Process()
            task.launchPath = command
            task.arguments = ["--force", projectPath]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                NSLog("CheckpointHelper: addProject backup failed: %@", error.localizedDescription)
            }

            DispatchQueue.main.async {
                self.backingUpProjects.remove(projectPath)
                self.stopProgressPolling()
                self.refresh()
            }
        }
    }

    func removeProject(_ project: ProjectInfo) {
        removeTargetProject = project
        showingRemoveConfirm = true
    }

    func confirmRemoveProject() {
        guard let project = removeTargetProject else { return }

        let registryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/checkpoint/projects.json")

        guard let data = try? Data(contentsOf: registryURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var projectsArray = json["projects"] as? [[String: Any]] else {
            return
        }

        projectsArray.removeAll { ($0["path"] as? String) == project.path }
        json["projects"] = projectsArray

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: registryURL)
        }

        removeTargetProject = nil
        showingRemoveConfirm = false
        refresh()
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
        case "initializing":     return "Initializing\u{2026}"
        case "scanning":         return "Scanning for changes\u{2026}"
        case "preparing":        return "Preparing files\u{2026}"
        case "copying":          return "Copying files\u{2026}"
        case "verifying":        return "Verifying integrity\u{2026}"
        case "manifest":         return "Writing manifest\u{2026}"
        case "finalizing":       return "Finalizing\u{2026}"
        case "cloud_syncing":    return "\u{2601}\u{FE0F} Uploading to cloud\u{2026}"
        case "cloud_databases":  return "\u{2601}\u{FE0F} Uploading databases to cloud\u{2026}"
        case "cloud_files":      return "\u{2601}\u{FE0F} Uploading files to cloud\u{2026}"
        case "cloud_archives":   return "\u{2601}\u{FE0F} Uploading version history to cloud\u{2026}"
        case "cloud_encrypting": return "\u{1F512} Encrypting cloud files\u{2026}"
        default:                 return "Working\u{2026}"
        }
    }

    var isCloudPhase: Bool {
        backupProgressPhase.hasPrefix("cloud_")
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

    private var stateChangeObserver: Any?

    init() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Listen for daemon state changes from the menu bar widget
        stateChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CheckpointDaemonStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        heartbeatTimer?.invalidate()
        progressTimer?.invalidate()
        if let obs = stateChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
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
            info.loadErrorData()

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
            if success {
                NotificationCenter.default.post(name: NSNotification.Name("CheckpointDaemonStateChanged"), object: nil)
            } else {
                self.daemonError = "Could not resume automatic backups. The background service may not be installed yet.\n\nRun 'checkpoint install' in Terminal to set it up."
            }
        }
    }

    func stopDaemon() {
        let success = DaemonController.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.refresh()
            if success {
                NotificationCenter.default.post(name: NSNotification.Name("CheckpointDaemonStateChanged"), object: nil)
            } else {
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
        dismissAllModals()
        logViewerProject = project
        showingLogViewer = true
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
            let fm = FileManager.default

            // Check if this is a git-based install
            let hasGit = fm.fileExists(atPath: installDir + "/.git")

            if hasGit {
                // Git-based install: compare commit hashes
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

                guard let localHash = git(["rev-parse", "HEAD"]), !localHash.isEmpty else {
                    DispatchQueue.main.async {
                        self?.updateCheckResult = .error("Could not read local version at:\n\(installDir)")
                    }
                    return
                }

                let _ = git(["fetch", "origin", "--quiet"])

                guard let remoteHash = git(["rev-parse", "origin/main"]) ?? git(["rev-parse", "origin/master"]),
                      !remoteHash.isEmpty else {
                    DispatchQueue.main.async {
                        self?.updateCheckResult = .error("Could not fetch remote version.\nIs the remote configured?")
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
            } else {
                // Non-git install: compare VERSION file against GitHub API
                let versionPath = installDir + "/VERSION"
                guard let localVersion = try? String(contentsOfFile: versionPath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines), !localVersion.isEmpty else {
                    DispatchQueue.main.async {
                        self?.updateCheckResult = .error("Could not read VERSION file at:\n\(installDir)")
                    }
                    return
                }

                // Fetch latest version from GitHub raw VERSION file
                let rawURL = URL(string: "https://raw.githubusercontent.com/fluxcodestudio/Checkpoint/main/VERSION")!
                let semaphore = DispatchSemaphore(value: 0)
                var remoteVersion: String?
                var fetchError: String?

                let task = URLSession.shared.dataTask(with: rawURL) { data, response, error in
                    defer { semaphore.signal() }
                    if let error = error {
                        fetchError = error.localizedDescription
                        return
                    }
                    guard let data = data,
                          let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        fetchError = "Could not reach GitHub"
                        return
                    }
                    remoteVersion = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                task.resume()
                _ = semaphore.wait(timeout: .now() + 10)

                guard let remote = remoteVersion, !remote.isEmpty else {
                    DispatchQueue.main.async {
                        self?.updateCheckResult = .error(fetchError ?? "Could not check for updates.\nNo internet connection?")
                    }
                    return
                }

                DispatchQueue.main.async {
                    if localVersion == remote {
                        self?.updateCheckResult = .upToDate(version: "v\(localVersion)")
                    } else {
                        self?.updateCheckResult = .updateAvailable(local: "v\(localVersion)", remote: "v\(remote)")
                    }
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
    var lastError: String? = nil
    var failureCount: Int = 0
    var llmPrompt: String? = nil
    var recentErrors: [(date: String, count: Int)] = []

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

    mutating func loadErrorData() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let stateDir = "\(home)/.claudecode-backups/state/\(name)"

        // Read failure sentinel
        let failedPath = "\(stateDir)/.last-backup-failed"
        if let contents = try? String(contentsOfFile: failedPath, encoding: .utf8) {
            let parts = contents.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
            if parts.count >= 2, let count = Int(parts[1]) {
                failureCount = count
                lastError = "\(count) file(s) failed"
            }
        }

        // Read LLM prompt
        let llmPath = "\(stateDir)/.last-backup-llm-prompt"
        if let contents = try? String(contentsOfFile: llmPath, encoding: .utf8) {
            llmPrompt = contents
        }

        // Read error history
        let historyPath = "\(stateDir)/error-history.log"
        if let contents = try? String(contentsOfFile: historyPath, encoding: .utf8) {
            let lines = contents.split(separator: "\n").suffix(10)
            recentErrors = lines.compactMap { line in
                let parts = line.split(separator: "|")
                guard parts.count >= 3 else { return nil }
                let dateStr = String(parts[0])
                let count = Int(parts[2]) ?? 0
                return (date: dateStr, count: count)
            }
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

// MARK: - Log Viewer View

struct LogViewerView: View {
    @Binding var isPresented: Bool
    let project: ProjectInfo
    @StateObject private var viewModel = LogViewerViewModel()

    var body: some View {
        ZStack {
            Color.cpBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundColor(.cpAccent)
                    Text("Backup Log")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.cpTextPrimary)
                    Text("\u{2014} \(project.name)")
                        .font(.system(size: 14))
                        .foregroundColor(.cpTextSecondary)
                    Spacer()
                    Button("Done") { isPresented = false }
                        .buttonStyle(CPButtonStyle(accent: .cpAccent, filled: true))
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.cpBorder).frame(height: 0.5)
                }

                // Filter bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.cpTextTertiary)
                    TextField("Filter\u{2026}", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.cpTextPrimary)

                    Spacer()

                    Picker("", selection: $viewModel.filterLevel) {
                        Text("All").tag(LogViewerViewModel.FilterLevel.all)
                        Text("Errors").tag(LogViewerViewModel.FilterLevel.errors)
                        Text("Warnings").tag(LogViewerViewModel.FilterLevel.warnings)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Error history tab (if available)
                if !project.recentErrors.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(project.recentErrors.enumerated()), id: \.offset) { _, entry in
                                VStack(spacing: 1) {
                                    Text("\(entry.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(entry.count > 0 ? .cpDanger : .cpAccent)
                                    Text(String(entry.date.prefix(10)))
                                        .font(.system(size: 9))
                                        .foregroundColor(.cpTextTertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.cpSurface)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 4)
                }

                // Log lines
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(viewModel.filteredLines.enumerated()), id: \.offset) { index, line in
                                logLineRow(line)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }

                // Footer
                VStack(spacing: 0) {
                    Rectangle().fill(Color.cpBorder).frame(height: 0.5)
                    HStack {
                        Button(action: viewModel.copyForAIHelp) {
                            HStack(spacing: 5) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 11))
                                Text("Copy for AI Help")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .buttonStyle(CPButtonStyle(accent: .cpAccent))

                        Spacer()

                        Text("Showing \(viewModel.filteredLines.count) lines")
                            .font(.system(size: 11))
                            .foregroundColor(.cpTextTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color.cpSurface.opacity(0.7))
            }
        }
        .frame(width: 560, height: 500)
        .onAppear {
            viewModel.loadLog(for: project)
        }
    }

    private func logLineRow(_ line: LogViewerViewModel.LogLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.timestamp)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.cpTextTertiary)
                .frame(width: 120, alignment: .leading)

            Text(line.level)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(line.levelColor)
                .frame(width: 48, alignment: .leading)

            Text(line.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.cpTextPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(line.level == "ERROR" ? Color.cpDanger.opacity(0.08) :
                      line.level == "WARN" ? Color.cpWarning.opacity(0.06) : Color.clear)
        )
    }
}

class LogViewerViewModel: ObservableObject {
    enum FilterLevel {
        case all, errors, warnings
    }

    struct LogLine {
        let timestamp: String
        let level: String
        let message: String

        var levelColor: Color {
            switch level {
            case "ERROR": return .cpDanger
            case "WARN": return .cpWarning
            case "INFO": return .cpAccent
            case "DEBUG": return .cpTextTertiary
            default: return .cpTextSecondary
            }
        }
    }

    @Published var lines: [LogLine] = []
    @Published var searchText: String = ""
    @Published var filterLevel: FilterLevel = .all

    private var projectPath: String = ""

    var filteredLines: [LogLine] {
        var result = lines

        switch filterLevel {
        case .all: break
        case .errors:
            result = result.filter { $0.level == "ERROR" }
        case .warnings:
            result = result.filter { $0.level == "ERROR" || $0.level == "WARN" }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.message.lowercased().contains(query) }
        }

        return result
    }

    func loadLog(for project: ProjectInfo) {
        projectPath = project.path
        let logPath = "\(project.path)/backups/backup.log"

        guard let fileHandle = FileHandle(forReadingAtPath: logPath) else {
            lines = [LogLine(timestamp: "", level: "INFO", message: "No log file found.")]
            return
        }
        defer { fileHandle.closeFile() }

        // Read last ~64KB (up to ~500 lines)
        let fileSize = fileHandle.seekToEndOfFile()
        let maxRead: UInt64 = 65536
        let readOffset: UInt64 = fileSize > maxRead ? fileSize - maxRead : 0
        fileHandle.seek(toFileOffset: readOffset)
        let data = fileHandle.readDataToEndOfFile()
        guard let contents = String(data: data, encoding: .utf8) else { return }

        let rawLines = contents.components(separatedBy: "\n")
        // If we started mid-line, skip the first partial line
        let startIndex = readOffset > 0 ? 1 : 0

        lines = rawLines.dropFirst(startIndex).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }

            // Parse: [YYYY-MM-DD HH:MM:SS] [LEVEL] message
            var timestamp = ""
            var level = "INFO"
            var message = line

            if line.hasPrefix("[") {
                if let tsEnd = line.firstIndex(of: "]") {
                    timestamp = String(line[line.index(after: line.startIndex)..<tsEnd])
                    let rest = String(line[line.index(tsEnd, offsetBy: 2)...]).trimmingCharacters(in: .whitespaces)

                    if rest.hasPrefix("[") {
                        if let lvlEnd = rest.firstIndex(of: "]") {
                            level = String(rest[rest.index(after: rest.startIndex)..<lvlEnd])
                            message = String(rest[rest.index(lvlEnd, offsetBy: 2)...]).trimmingCharacters(in: .whitespaces)
                        }
                    } else {
                        message = rest
                    }
                }
            }

            return LogLine(timestamp: timestamp, level: level, message: message)
        }
    }

    func copyForAIHelp() {
        let errorLines = lines.filter { $0.level == "ERROR" || $0.level == "WARN" }
        let text: String
        if errorLines.isEmpty {
            text = "No errors or warnings found in backup log for: \(projectPath)"
        } else {
            let header = "Backup errors for: \(projectPath)\n\n"
            let body = errorLines.map { "[\($0.timestamp)] [\($0.level)] \($0.message)" }.joined(separator: "\n")
            text = header + body
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var isPresented: Bool
    let onAddProject: () -> Void
    @State private var step: Int = 1
    @State private var selectedPath: String? = nil
    @State private var backupInterval: Int = 3600
    @State private var notificationsEnabled: Bool = true
    @State private var isRunningBackup: Bool = false
    @State private var backupComplete: Bool = false

    var body: some View {
        ZStack {
            Color.cpBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    CheckpointShield(size: 48)
                        .padding(.top, 24)

                    Text("Welcome to Checkpoint")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.cpTextPrimary)

                    Text("Let\u{2019}s set up your first backup in under a minute.")
                        .font(.system(size: 13))
                        .foregroundColor(.cpTextSecondary)

                    Text("Step \(step) of 3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cpTextTertiary)
                        .padding(.top, 4)
                }
                .padding(.bottom, 16)

                Divider().background(Color.cpBorder)

                // Step content
                Group {
                    switch step {
                    case 1:
                        step1View
                    case 2:
                        step2View
                    case 3:
                        step3View
                    default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)

                Divider().background(Color.cpBorder)

                // Footer
                HStack {
                    Button("Skip") { isPresented = false }
                        .buttonStyle(CPButtonStyle(accent: .cpTextSecondary))

                    Spacer()

                    if step < 3 {
                        Button(action: nextStep) {
                            Text("Continue")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(CPButtonStyle(accent: .cpAccent, filled: true))
                        .disabled(step == 1 && selectedPath == nil)
                    } else {
                        Button(action: { isPresented = false }) {
                            Text("Open Dashboard")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(CPButtonStyle(accent: .cpAccent, filled: true))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 420, height: 440)
    }

    // MARK: - Step 1: Select Project

    private var step1View: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.cpAccent)

            Text("Select a project to protect")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.cpTextPrimary)

            if let path = selectedPath {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cpAccent)
                        .font(.system(size: 12))
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.cpTextPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.cpAccent.opacity(0.1))
                )

                Text(path)
                    .font(.system(size: 11))
                    .foregroundColor(.cpTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button(action: chooseFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                    Text(selectedPath == nil ? "Choose Project Folder" : "Change Folder")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(CPButtonStyle(accent: .cpAccent, filled: selectedPath == nil))

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 2: Preferences

    private var step2View: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            HStack {
                Text("Backup interval")
                    .font(.system(size: 13))
                    .foregroundColor(.cpTextPrimary)
                Spacer()
                Picker("", selection: $backupInterval) {
                    Text("30 minutes").tag(1800)
                    Text("1 hour").tag(3600)
                    Text("2 hours").tag(7200)
                    Text("4 hours").tag(14400)
                }
                .labelsHidden()
                .frame(width: 140)
            }

            HStack {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                    .toggleStyle(.switch)
                    .tint(.cpAccent)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Step 3: Complete

    private var step3View: some View {
        VStack(spacing: 16) {
            Spacer()

            if isRunningBackup {
                ProgressView()
                    .controlSize(.regular)
                Text("Running first backup\u{2026}")
                    .font(.system(size: 13))
                    .foregroundColor(.cpTextSecondary)
            } else if backupComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.cpAccent)
                Text("All set!")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.cpTextPrimary)
                Text("Your project is now protected by Checkpoint.")
                    .font(.system(size: 13))
                    .foregroundColor(.cpTextSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.cpAccent)
                Text("Ready to go!")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.cpTextPrimary)
                Text("Your first backup will start automatically.")
                    .font(.system(size: 13))
                    .foregroundColor(.cpTextSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory to back up"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedPath = url.path
    }

    private func nextStep() {
        if step == 1 && selectedPath != nil {
            step = 2
        } else if step == 2 {
            step = 3
            runFirstBackup()
        }
    }

    private func runFirstBackup() {
        guard let path = selectedPath else { return }
        isRunningBackup = true

        DispatchQueue.global(qos: .userInitiated).async {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let possiblePaths = [
                "\(home)/.local/bin/backup-now",
                "/usr/local/bin/backup-now"
            ]
            if let command = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                let task = Process()
                task.launchPath = command
                task.arguments = ["--force", path]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                    task.waitUntilExit()
                } catch {
                    NSLog("Onboarding backup failed: %@", error.localizedDescription)
                }
            }

            DispatchQueue.main.async {
                isRunningBackup = false
                backupComplete = true
            }
        }
    }
}
