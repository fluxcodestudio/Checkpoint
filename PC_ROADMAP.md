# Windows Port Roadmap — Checkpoint Backup System

**Status:** Deferred — awaiting Windows test machine
**Created:** 2026-02-26
**Architecture:** Finalized (hybrid native UI + bundled MSYS2 bash engine)

---

## Architecture Decision

**Hybrid approach:** Native Windows for everything users see (Inno Setup installer, C# WPF tray app, Windows Task Scheduler, Toast notifications). Bundled MSYS2 bash runtime (~80MB) for the backup engine — proven scripts run in background, users never interact with a shell.

This ships fastest while feeling fully native. One codebase to maintain.

## Directory Structure

```
windows/
├── installer/
│   ├── checkpoint-setup.iss       # Inno Setup script
│   └── checkpoint-icon.ico        # Windows icon
├── tray-app/
│   ├── CheckpointTray.csproj      # .NET 8 WPF project
│   ├── App.xaml / App.xaml.cs     # Entry point, single-instance mutex
│   ├── TrayIcon.cs                # System tray icon + context menu
│   ├── DashboardWindow.xaml/.cs   # Dashboard popup (port of SwiftUI DashboardView)
│   ├── HeartbeatMonitor.cs        # Port of HeartbeatMonitor.swift
│   ├── DaemonController.cs        # schtasks control (port of DaemonController.swift)
│   └── ToastNotifier.cs           # Windows Toast notifications
├── scripts/
│   ├── install-service.ps1        # Register Task Scheduler jobs
│   ├── uninstall-service.ps1      # Remove Task Scheduler jobs
│   └── send-toast.ps1             # Toast notification helper (called from bash)
├── bin/
│   ├── backup-now.cmd             # CMD wrapper → bash backup-now.sh
│   ├── checkpoint.cmd             # CMD wrapper → bash checkpoint.sh
│   └── backup-status.cmd          # CMD wrapper → bash backup-status.sh
├── templates/
│   ├── daemon-task.xml            # Task Scheduler XML: hourly daemon
│   ├── watchdog-task.xml          # Task Scheduler XML: watchdog at login
│   └── watcher-task.xml           # Task Scheduler XML: file watcher
└── build/
    ├── bundle-msys2.ps1           # Download/prepare minimal MSYS2 runtime
    └── build-installer.ps1        # Build tray app + create .exe installer
```

---

## Implementation Phases

### Phase 1 — MSYS2 Runtime Bundle + Bash Verification

**Goal:** Prove `backup-now.sh` runs on Windows via CMD wrapper.

1. **`bundle-msys2.ps1`** — Download MSYS2 base, install `bash coreutils findutils gawk sed grep gzip rsync git`, strip docs/man/i18n. Target ~80MB. Add `age` and `rclone` Windows binaries.
2. **CMD wrappers** — Thin `.cmd` files that set `HOME=%USERPROFILE%` and invoke bash:
   ```cmd
   @echo off
   set "HOME=%USERPROFILE%"
   "%~dp0..\runtime\usr\bin\bash.exe" --login "%~dp0..\scripts\bin\backup-now.sh" %*
   ```
3. **Smoke test** — Run `backup-now.cmd` in a test project, verify backup completes.

### Phase 2 — Bash Script Modifications (8 files)

| File | Change | LOC |
|------|--------|-----|
| `lib/platform/compat.sh` | Add `MSYS_NT-*` case: GNU stat works, notification via `send-toast.ps1` | +25 |
| `lib/platform/daemon-manager.sh` | Add full `schtasks` backend: detect/install/uninstall/start/stop/status/list | +120 |
| `lib/platform/file-watcher.sh` | Route MSYS2 to poll backend (already works universally) | +10 |
| `lib/security/credential-provider.sh` | Add `cmdkey` backend for Windows Credential Manager | +35 |
| `lib/cloud-folder-detector.sh` | Add Windows paths: Dropbox (`%APPDATA%\Dropbox\info.json`), OneDrive (`%USERPROFILE%\OneDrive`), Google Drive, iCloud via `cygpath` | +60 |
| `bin/bootstrap.sh` | Add `normalize_path()` using `cygpath -u` when on MSYS2 | +15 |
| `bin/backup-daemon.sh` | Guard launchctl watchdog restart with `detect_init_system` dispatch | +10 |
| `bin/backup-update.sh` | Same launchctl guard | +8 |

**Key contract:** All bash scripts use Unix paths internally. CMD wrappers set `HOME=%USERPROFILE%`. `cygpath -u` at entry points, `cygpath -w` when writing Task Scheduler XML.

### Phase 3 — Windows Task Scheduler Templates + PowerShell Scripts

- **Daemon task**: Hourly `TimeTrigger`, runs `bash.exe backup-all-projects.sh`, `IgnoreNew` for concurrent runs
- **Watchdog task**: `LogonTrigger`, infinite runtime, restart on failure (1 min / 10 retries)
- **`install-service.ps1`**: Read XML templates, substitute placeholders, call `Register-ScheduledTask`
- **`send-toast.ps1`**: Windows Toast via `Windows.UI.Notifications` WinRT API

### Phase 4 — C# WPF Tray Application (.NET 8, single-file ~15MB)

Direct ports of the macOS Swift components:

| C# File | Swift Original | Key Functions |
|---------|---------------|---------------|
| `HeartbeatMonitor.cs` | `HeartbeatMonitor.swift` | Same enum, same thresholds (120s/24h/72h), same adaptive polling (2s/5s), reads `%USERPROFILE%\.checkpoint\daemon.heartbeat` |
| `DaemonController.cs` | `DaemonController.swift` | `IsRunning/Start/Stop/Restart/RunBackupNow` via `schtasks.exe` |
| `TrayIcon.cs` | `MenuBarManager.swift` | System tray icon, context menu matching macOS order |
| `DashboardWindow.xaml` | `DashboardWindow.swift` | Project list, progress bars, dark theme (`#141415` bg, `#A666FF` accent) |
| `ToastNotifier.cs` | `NotificationManager.swift` | Backup success/failure/stale notifications |

Icon states: green (healthy), blue (syncing), orange (warning), red (error), grey (stopped).

### Phase 5 — Inno Setup Installer

1. Extract MSYS2 runtime → `{app}\runtime\`
2. Extract bash scripts → `{app}\scripts\`
3. Copy tray app → `{app}\CheckpointTray.exe`
4. Add `{app}\bin\` to user PATH
5. Register Task Scheduler jobs via `install-service.ps1`
6. Add tray app to Windows Startup
7. Post-install: auto-configure to discover projects

Settings: `PrivilegesRequired=lowest` (no admin), min Windows 10 1809.

### Phase 6 — Website Updates

- Add Windows download button to `index.html`
- Add Windows section to `docs.html`
- Update structured data: `"operatingSystem": "macOS, Linux, Windows"`
- Update `llms.txt` / `llms-full.txt`

### Phase 7 — Testing

| Test Case | Expected |
|-----------|----------|
| Install on clean Windows 10/11 | Files extracted, PATH set, tasks registered, tray starts |
| `backup-now` from CMD/PowerShell | Backup completes |
| SQLite/PostgreSQL/MySQL/MongoDB backup | Correct dump files |
| Cloud folder detection (Dropbox, OneDrive, GDrive) | Paths detected |
| Task Scheduler daemon fires hourly | Heartbeat updated |
| Watchdog restarts dead daemon | Within 1 min |
| Tray icon shows correct status colors | Green/orange/red |
| Dashboard opens with project list | Renders correctly |
| Toast notifications fire | On success/fail |
| Uninstall removes everything | Tasks, PATH, files cleaned |
| Upgrade preserves config | Re-registers tasks |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| AV flags MSYS2 binaries | Code-sign installer |
| SmartScreen blocks unsigned .exe | Get code signing cert or document bypass |
| 260-char path limit | Enable `LongPathsEnabled` in installer |
| `HOME` mismatch | CMD wrappers set `HOME=%USERPROFILE%` |
| `schtasks.exe` not in MSYS2 PATH | Use `"${SYSTEMROOT}/System32/schtasks.exe"` |
| PowerShell execution policy | Call with `-ExecutionPolicy Bypass` |

---

## Prerequisites to Start

- [ ] Access to a Windows 10 or 11 machine for development and testing
- [ ] .NET 8 SDK installed on Windows
- [ ] Inno Setup 6.x installed on Windows
- [ ] Visual Studio or VS Code with C# extension
