<div align="center">

<img src=".github/assets/checkpoint-logo.png" alt="Checkpoint Logo" width="200"/>

# Checkpoint

**Automated backup tool for developers — protect your source code, databases, and project files.**

A set-and-forget backup system that runs in the background on macOS and Linux. Checkpoint automatically backs up your project files, databases (SQLite, PostgreSQL, MySQL, MongoDB), and critical configs (.env, credentials, keys) every hour. Includes encrypted cloud sync, a native macOS dashboard, and full restore/search capabilities.

**Version:** 2.6.0 &nbsp;|&nbsp; **Tests:** 164/164 (100%) &nbsp;|&nbsp; **License:** [Polyform Noncommercial](https://polyformproject.org/licenses/noncommercial/1.0.0/) &nbsp;|&nbsp; **By:** [FluxCode Studio](https://fluxcode.studio)

[Website](https://checkpoint.fluxcode.studio) &nbsp;·&nbsp; [Documentation](https://checkpoint.fluxcode.studio/docs.html) &nbsp;·&nbsp; [Download](https://github.com/fluxcodestudio/Checkpoint/archive/refs/heads/main.zip)

</div>

> **TL;DR:** Install once, run `backup-now` in any project directory, forget about it. Your code, databases, and secrets are backed up hourly with optional encrypted cloud sync. Think of it as Time Machine for your development projects.

---

## Why Checkpoint?

Most backup solutions aren't built for developers. Checkpoint is:

- **Git isn't backup** — Git doesn't protect .env files, databases, untracked files, or work-in-progress code you haven't committed
- **Time Machine is too broad** — It backs up everything, not just what matters for your projects
- **Cloud sync isn't versioned** — Dropbox/iCloud sync your current state but don't keep historical versions
- **Cron scripts are fragile** — They break silently, have no monitoring, and require maintenance

Checkpoint handles all of this: automatic hourly backups of files + databases, encrypted cloud upload, version history, search/restore, health monitoring, and a native macOS dashboard — all from one `backup-now` command.

---

## What's New in v2.6.0

<details open>
<summary><strong>v2.6.0 — Encrypted Cloud Sync, Compression & Cloud Restore</strong></summary>

**End-to-End Encrypted Cloud Backups**
- All cloud files encrypted with `age` before upload — zero plaintext on cloud storage
- Compressible files (source code, JSON, text) compressed before encryption: `file → gzip → age → .gz.age`
- Already-compressed formats (images, video, archives) encrypted without compression: `file → age → .age`
- Automatic stale variant cleanup — no duplicate `.age` / `.gz.age` files

**Parallel Encryption Engine**
- Auto-detects CPU cores, uses half for encryption (e.g., 12 workers on 24-core machine)
- Activates automatically when 100+ files need encrypting (first-time backups, large projects)
- Falls back to sequential for small batches (typical hourly incremental backups)
- 10-12x speedup for initial project backups

**Cloud Browse & Restore (`checkpoint cloud`)**
- `checkpoint cloud list` — list all cloud backups with timestamps and file counts
- `checkpoint cloud browse PROJECT` — interactive file browser with fzf support
- `checkpoint cloud download FILE` — download and auto-decrypt individual files
- `checkpoint cloud download-all` — download entire backup with optional zip output
- `checkpoint cloud sync-index` — refresh cloud inventory cache
- `checkpoint cloud setup` — interactive setup wizard for new machines
- All commands support `--json` flag for programmatic use

**Cloud Manifest System**
- Each backup uploads a manifest (`.checkpoint-manifests/{backup_id}.json`) for instant inventory
- Cloud index (`.checkpoint-cloud-index.json`) tracks all backups per project
- Local caching at `~/.checkpoint/cloud-cache/` — fast repeat access without re-downloading

**Dashboard Cloud Features**
- Cloud Browse modal — visual file browser with search, download buttons, and progress
- Cloud upload phase indicators — distinct "Uploading to cloud..." and "Encrypting..." banners
- Blue tint during cloud phases to distinguish from local backup progress
- Version history (`archived/`) now synced to cloud alongside current files

**Bulk Operations**
- `encrypt-cloud-bulk.sh` — parallel encrypt all plaintext files on cloud (12 workers)
- `compress-cloud-bulk.sh` — convert existing `.age` to `.gz.age` for compressible formats
- Both scripts support `--dry-run`, `--project NAME`, and `--jobs N` flags

</details>

<details>
<summary><strong>v2.5.1 — Dashboard UX Overhaul & Global Settings</strong></summary>

**Menu Bar Dashboard**
- Right-click context menu on project rows: Backup Now, Reveal in Finder, View Backup Folder, View Backup Log, Enable/Disable
- Double-click any project row to open it in Finder
- Hover effect on backup buttons (fade in on hover)
- Last backup result indicators: green checkmark (success), orange warning (partial), red X (failed)
- Keyboard shortcuts: `⌘B` Backup All, `⌘R` Refresh, `⌘,` Settings
- Refresh button shows green "Updated" checkmark for visual feedback
- User-friendly labels: "Backups Active/Paused" instead of daemon jargon

**Settings Modal (`⌘,`)**
- In-app settings sheet reads/writes `~/.config/checkpoint/config.sh`
- Schedule: backup interval, idle threshold
- Retention: database and file retention periods
- What to Backup: toggle .env files, credentials, IDE settings
- Notifications: desktop notifications, failure-only mode
- Advanced: database compression level, debug logging

**Global Config Wired to Backup Scripts**
- `~/.config/checkpoint/config.sh` defaults now apply as fallbacks in all backup scripts
- Per-project `.backup-config.sh` always overrides global defaults
- `COMPRESSION_LEVEL` controls gzip compression in database backups
- `DEBUG_MODE` enables debug-level logging globally
- `DESKTOP_NOTIFICATIONS` toggles the macOS notification system

**Bug Fixes**
- Progress polling auto-stops after 30 minutes (prevents infinite polling if backup hangs)
- Individual project backup disabled during global Backup All (prevents conflicts)
- Daemon start/stop shows error alert on failure

</details>

<details>
<summary><strong>v2.5.0 — Daemon Lifecycle & Health Monitoring</strong></summary>

**Daemon Reliability**
- Atomic heartbeat writes prevent partial-read corruption
- Watchdog self-monitoring with its own heartbeat
- KeepAlive/SuccessfulExit — daemons auto-restart on crash but not on clean stop
- Auto-start daemons immediately after installation (no reboot required)
- Post-update migration patches existing installations automatically

**Backup Staleness Detection**
- Warning alert if no successful backup in 24 hours
- Critical alert if no successful backup in 72 hours
- Notification cooldown system prevents alert fatigue (4h warning, 2h critical)

**Modular Architecture**
- Refactored from monolithic `backup-lib.sh` to modular library structure
- `lib/core/` — config, logging, error codes, output formatting
- `lib/ops/` — file operations, initialization, state management
- `lib/features/` — change detection, cleanup, health stats, restore, verification
- `lib/platform/` — daemon management, file watcher, compatibility
- `lib/security/` — credential provider, secure downloads
- `lib/ui/` — formatting, time/size utilities

**Native File Watcher**
- Real-time file change detection using `fswatch` (macOS) / `inotifywait` (Linux)
- Replaces session-start hooks with continuous monitoring
- Configurable debounce and ignore patterns

**Structured Logging**
- Machine-parseable JSON log output
- Log levels: DEBUG, INFO, WARN, ERROR
- Context-aware logging with component tags

**Full Linux Support**
- Native systemd service units (daemon, watchdog, watcher)
- `systemctl --user` integration for user-level services
- Cross-platform daemon manager handles launchd, systemd, and cron

**Security Hardening**
- Secure download verification with checksums
- Credential provider abstraction
- Malware scanning integration

**Backup Verification**
- Post-backup integrity checks
- Verify backup completeness and file counts

</details>

<details>
<summary><strong>v2.4.0 — Remote & Docker Database Backup</strong></summary>

- Remote database backup: Neon, Supabase, PlanetScale, MongoDB Atlas with SSL
- Docker database backup: auto-detect from docker-compose.yml
- Auto-start local databases for backup, stop after
- Machine tracking: hostname, OS, model in state files
- Session-start hooks for high-activity projects

</details>

<details>
<summary><strong>v2.3.x — Global Multi-Project System</strong></summary>

- Auto-registration: `backup-now` in any directory auto-creates config
- Single global daemon backs up ALL projects hourly
- Projects registry in `~/.config/checkpoint/projects.json`
- `backup-all` command for all registered projects
- Interactive command center via `/checkpoint` skill

</details>

<details>
<summary><strong>v2.2.x — Universal Database Support</strong></summary>

- Auto-detects PostgreSQL, MySQL, MongoDB (plus SQLite)
- Progressive installation of database tools
- Streamlined 5-question installer (~20 seconds)
- Per-project mode with all commands in `./bin/`

</details>

---

## Features

### Core Capabilities
- **Organized Backup Structure** — Databases, current files, and archived versions in separate folders
- **Smart Change Detection** — Only backs up modified files
- **Works Without Git** — Automatic fallback for non-git directories (filesystem scan + mtime)
- **Failure Notifications** — Native macOS notifications when backup fails (spam-prevented, actionable)
- **Staleness Alerts** — Warning at 24h, critical at 72h without successful backup
- **Universal Database Detection** — Auto-detects SQLite, PostgreSQL, MySQL, MongoDB (local, remote, Docker)
- **Remote Database Backup** — Cloud databases (Neon, Supabase, PlanetScale, MongoDB Atlas) with SSL
- **Docker Database Backup** — Auto-detect and backup databases from Docker containers
- **Database Snapshots** — Compressed timestamped backups with proper tools (sqlite3, pg_dump, mysqldump, mongodump)
- **Multi-Computer Support** — Graceful handling when databases don't exist on current machine
- **Version Archiving** — Old versions preserved when files change
- **Critical File Coverage** — .env, credentials, cloud configs, Terraform secrets, IDE settings
- **Cloud Backup** — Off-site protection via cloud folder (Dropbox) or rclone (Google Drive, OneDrive, iCloud)
- **Cloud Encryption** — All cloud files encrypted with `age` before upload, with gzip compression for compressible formats
- **Parallel Encryption** — Auto-scales to half CPU cores when 100+ files need encrypting (10-12x speedup)
- **Cloud Browse & Restore** — Browse, search, and download files from cloud backups via CLI or dashboard
- **Cloud Manifests** — Instant cloud inventory without downloading files
- **Backup Verification** — Post-backup integrity checks
- **Native File Watcher** — Real-time change detection via fswatch/inotifywait
- **Daemon Health Monitoring** — Watchdog process with heartbeat tracking and auto-restart
- **Storage Monitoring** — Pre-backup disk space checks with warnings and cleanup suggestions
- **Search & Browse** — CLI search across all backup history with interactive fzf mode
- **Native macOS Dashboard** — SwiftUI menu bar app with project status, settings, and live progress
- **Cross-Platform** — macOS (launchd) and Linux (systemd) with cron fallback
- **100% Test Coverage** — All functionality validated

### Backup Structure

```
backups/
├── databases/           # Compressed timestamped snapshots
│   ├── MyApp-2025.12.24-10.45.12.db.gz
│   └── MyApp-2025.12.24-14.30.45.db.gz
├── files/               # Current versions (uncompressed, readable)
│   ├── src/
│   ├── .env
│   └── credentials.json
└── archived/            # Old versions with timestamps
    ├── src/app.py.20251223_104500
    └── .env.20251222_093015
```

**Why this structure?**
- **databases/** — Compressed (~90% smaller), timestamped history
- **files/** — Uncompressed so you can open/read directly
- **archived/** — Old versions preserved when changed

---

## Quick Start

### Installation

```bash
# Clone repository
git clone https://github.com/fluxcodestudio/Checkpoint.git
cd Checkpoint

# Run installer (global mode recommended)
./bin/install-global.sh
```

### Using Checkpoint

After global installation, just run `backup-now` in any project:

```bash
cd /your/project
backup-now
```

**That's it!** Checkpoint will:
1. Auto-create configuration (`.backup-config.sh`)
2. Register the project in the global registry
3. Back up immediately
4. Include in hourly automatic backups

### Installation Modes

**1. Global (Recommended)**
- Install once, use everywhere
- Commands available system-wide: `backup-now`, `backup-all`, `backup-status`, etc.
- Single daemon backs up ALL projects hourly
- Watchdog monitors daemon health with auto-restart
- Easy updates: `git pull && ./bin/install-global.sh`

**2. Per-Project**
- Self-contained in project directory
- Portable (copy project = copy backup system)
- No system modifications
- Good for: shared systems, containers

**The installer is fast and streamlined (6 questions, ~30 seconds):**

1. **Auto-detects databases** (SQLite, PostgreSQL, MySQL, MongoDB)
2. **Cloud backup?** (optional, auto-installs rclone)
3. **Hourly backups?** (daemon schedule)
4. **Claude Code integration?** (optional)
5. **GitHub auto-push?** (optional, configurable frequency)
6. **Run initial backup?**

### Cloud Backup Setup

**During Installation:**
- Installer asks: "Do you want cloud backup?"
- If yes: auto-installs rclone, configure provider

**After Installation:**
```bash
backup-cloud-config       # global mode
./bin/backup-cloud-config.sh  # per-project mode
```

### Verification

```bash
backup-status             # global mode
./bin/backup-status.sh    # per-project mode

ls -la backups/databases/
ls -la backups/files/
```

---

## Commands

**Global Mode:** Commands available system-wide
**Per-Project Mode:** Run from `bin/` directory

### All Commands

| Command | Global | Per-Project | Description |
|---------|--------|-------------|-------------|
| `backup-now` | yes | `./bin/backup-now.sh` | Backup current project (auto-creates config if new) |
| `backup-all` | yes | — | Backup ALL registered projects |
| `backup-status` | yes | `./bin/backup-status.sh` | View backup health and statistics |
| `backup-restore` | yes | `./bin/backup-restore.sh` | Restore from backups |
| `backup-cleanup` | yes | `./bin/backup-cleanup.sh` | Manage old backups and disk space |
| `backup-update` | yes | `./bin/backup-update.sh` | Update Checkpoint from GitHub |
| `backup-pause` | yes | `./bin/backup-pause.sh` | Pause/resume automatic backups |
| `backup-verify` | yes | `./bin/backup-verify.sh` | Verify backup integrity |
| `backup-cloud-config` | yes | `./bin/backup-cloud-config.sh` | Configure cloud backup |
| `checkpoint cloud` | yes | `./bin/checkpoint-cloud.sh` | Cloud browse, download, restore |
| `checkpoint add <path>` | yes | — | Register a project for backup |
| `checkpoint remove <path>` | yes | — | Unregister a project |
| `checkpoint list` | yes | — | List all registered projects |
| `backup-watch` | yes | `./bin/backup-watch.sh` | Start native file watcher |
| `install.sh` | N/A | `./bin/install.sh` | Install per-project |
| `uninstall.sh` | yes | `./bin/uninstall.sh` | Uninstall Checkpoint |

### Command Examples

**Check Status:**
```bash
backup-status
backup-status --compact
```

**Manual Backup:**
```bash
backup-now
backup-now --force          # Ignore change detection
backup-now --local-only     # Skip cloud upload
```

**Update System:**
```bash
backup-update               # Update from GitHub
backup-update --check-only  # Check without installing
```

**Pause/Resume:**
```bash
backup-pause                # Pause automatic backups
backup-pause --resume       # Resume backups
backup-pause --status       # Check if paused
```

**Restore:**
```bash
backup-restore              # Interactive menu
backup-restore --help       # See all options
```

**Project Management:**
```bash
checkpoint add /path/to/project   # Register a new project
checkpoint list                   # List all projects with status
checkpoint list --json            # Machine-readable output
checkpoint remove /path/to/project  # Unregister a project
```

**Cloud Browse & Restore:**
```bash
checkpoint cloud list                    # List all cloud backups
checkpoint cloud browse MyProject        # Interactive file browser
checkpoint cloud browse MyProject --latest  # Browse latest backup
checkpoint cloud download .env -p MyProject  # Download + auto-decrypt
checkpoint cloud download-all -p MyProject --zip  # Download all as zip
checkpoint cloud sync-index              # Refresh cloud cache
```

**Cleanup:**
```bash
backup-cleanup              # Preview cleanup
backup-cleanup --execute    # Execute cleanup
```

**Orphan Cleanup:**
```bash
uninstall.sh --cleanup-orphans    # Remove daemons for deleted projects
uninstall.sh --orphans --dry-run  # Preview without removing
```

---

## Cloud Backup

### Supported Providers

| Provider | Free Tier | Monthly Cost | Best For |
|----------|-----------|--------------|----------|
| **Google Drive** | 15GB | $2/100GB | Most generous free tier |
| **Dropbox** | 2GB | $12/2TB | Small databases |
| **OneDrive** | 5GB | $2/100GB | Microsoft ecosystem |
| **iCloud Drive** | 5GB | $1/50GB | macOS users |

### Smart Upload Strategy

**Always Uploaded (Recommended):**
- Database backups (~2MB compressed each)
- Critical files (.env, credentials, keys, cloud configs, Terraform secrets)

**Optional:**
- Project files (already in Git)

**Estimated Storage:**
- 10MB database -> 2MB compressed
- 30 days retention -> ~60MB total
- **Fits in all free tiers!**

### Setup

```bash
backup-cloud-config
```

Follow prompts:
1. Choose: Local only / Cloud only / Both
2. Select cloud provider
3. Install rclone (if needed)
4. Configure rclone remote
5. Choose what to upload
6. Done!

Configuration saved to `.backup-config.sh`:

```bash
BACKUP_LOCATION="both"           # local | cloud | both
CLOUD_PROVIDER="gdrive"          # dropbox | gdrive | onedrive | icloud
CLOUD_REMOTE_NAME="mygdrive"
CLOUD_BACKUP_PATH="/Backups/MyProject"
CLOUD_SYNC_DATABASES=true        # Upload DBs
CLOUD_SYNC_CRITICAL=true         # Upload .env, credentials
CLOUD_SYNC_FILES=false           # Skip large files
```

### Encryption & Compression

Cloud backups are **always encrypted** using [age](https://age-encryption.org/) (a modern, audited encryption tool). No plaintext files are ever stored on cloud storage.

```
Source file → gzip (if compressible) → age encrypt → upload
   .env     →  .env.gz              →  .env.gz.age → Dropbox ✓
   photo.jpg → (skip gzip)          →  photo.jpg.age → Dropbox ✓
```

- **Compressible files** (code, text, JSON, config): `file → gzip → age → .gz.age`
- **Already-compressed files** (images, video, archives, fonts): `file → age → .age`
- Encryption key stored locally at `~/.config/checkpoint/age-key.txt`
- **Parallel encryption** kicks in automatically when 100+ files need processing

### Cloud Restore

Download and auto-decrypt files from any cloud backup:

```bash
# Browse and download interactively
checkpoint cloud browse MyProject

# Download a single file (auto-decrypts)
checkpoint cloud download .env --project MyProject --backup-id latest

# Download everything as a decrypted zip
checkpoint cloud download-all --project MyProject --zip
```

The dashboard also provides a visual Cloud Browse modal for point-and-click file download.

### Usage

Cloud uploads happen **automatically** after each local backup (in background).

```bash
# Normal backup (includes cloud if enabled)
backup-now

# Skip cloud for one backup
backup-now --local-only

# Check cloud status
backup-status

# Browse cloud backups
checkpoint cloud list
```

See [docs/CLOUD-BACKUP.md](docs/CLOUD-BACKUP.md) for complete guide.

---

## Configuration

### Basic Configuration

After installation, `.backup-config.sh` in your project contains:

```bash
# Project
PROJECT_NAME="MyApp"
PROJECT_DIR="/path/to/project"
BACKUP_DIR="$PROJECT_DIR/backups"

# Database
DB_PATH="/path/to/database.db"
DB_TYPE="sqlite"  # or "auto" or "none"
DB_RETENTION_DAYS=30

# Files
FILE_RETENTION_DAYS=60

# Automation
BACKUP_INTERVAL=3600              # 1 hour
SESSION_IDLE_THRESHOLD=600        # 10 minutes

# Drive Verification
DRIVE_VERIFICATION_ENABLED=true
DRIVE_MARKER_FILE="/Volumes/Drive/.backup-drive-marker"

# GitHub Auto-Push
GIT_AUTO_PUSH_ENABLED=false
GIT_PUSH_INTERVAL=7200           # 2 hours

# Critical Files
BACKUP_ENV_FILES=true              # .env, .env.*
BACKUP_CREDENTIALS=true            # Keys, certs, cloud configs, Terraform
BACKUP_IDE_SETTINGS=true           # .vscode/, .idea/
BACKUP_LOCAL_NOTES=true            # NOTES.md, TODO.local.md
BACKUP_LOCAL_DATABASES=true        # *.db, *.sqlite (non-primary)
```

Edit anytime to change settings.

### Global Configuration

Global defaults apply to all projects (per-project settings override these):

```bash
# ~/.config/checkpoint/config.sh

# Schedule
DEFAULT_BACKUP_INTERVAL=3600          # Default backup interval (seconds)
DEFAULT_SESSION_IDLE_THRESHOLD=600    # Default idle threshold (seconds)

# Retention
DEFAULT_DB_RETENTION_DAYS=30          # Database backup retention
DEFAULT_FILE_RETENTION_DAYS=60        # Archived file retention

# What to Backup
DEFAULT_BACKUP_ENV_FILES=true         # .env files
DEFAULT_BACKUP_CREDENTIALS=true       # Keys, certs, cloud configs
DEFAULT_BACKUP_IDE_SETTINGS=true      # .vscode/, .idea/

# Notifications
DESKTOP_NOTIFICATIONS=false           # macOS desktop notifications
NOTIFY_ON_FAILURE_ONLY=true           # Only notify on failures

# Advanced
COMPRESSION_LEVEL=6                   # gzip level (1-9) for database backups
DEBUG_MODE=false                      # Enable debug logging globally
```

Edit via the **Settings** button in the menu bar dashboard (`⌘,`), or directly in the file.

---

## Failure Notifications

**Never miss a backup failure** — get instant notifications when something goes wrong.

### How It Works

**When Backup Fails:**
1. Native notification appears immediately
2. Shows error count and type
3. Plays warning sound ("Basso" on macOS)
4. Includes actionable message: "Run 'backup-status' to check"

**When Backup Recovers:**
1. Success notification appears
2. Confirms backup is working again
3. Plays success sound ("Glass" on macOS)

**Staleness Detection (v2.5):**
- Warning alert if no successful backup in 24 hours
- Critical alert if no successful backup in 72 hours
- Cooldown prevents repeated alerts (4h for warnings, 2h for critical)

**Spam Prevention:**
- Only notifies **once** on first failure
- Won't spam you every hour while issue persists
- Automatically clears when backup succeeds

### Configuration

Notifications are **enabled by default**. To disable:

```bash
# In .backup-config.sh
NOTIFICATIONS_ENABLED=false
```

---

## Universal Integrations

Checkpoint works anywhere — not just Claude Code!

### Available Integrations

| Integration | Auto-Trigger | Visual Status | Setup |
|-------------|--------------|---------------|-------|
| **Shell (Bash/Zsh)** | On `cd` | Prompt indicator | `./integrations/shell/install.sh` |
| **Git Hooks** | Pre-commit | Messages | `./integrations/git/install-git-hooks.sh` |
| **Vim/Neovim** | On save | Statusline | See `integrations/vim/README.md` |
| **VS Code** | — | — | `./integrations/vscode/install-vscode.sh` |
| **Tmux** | 60s refresh | Status bar | `./integrations/tmux/install-tmux.sh` |
| **Direnv** | On enter | — | `./integrations/direnv/install.sh` |

### Menu Bar App (macOS)

Native macOS menu bar app for managing backups without the terminal.

**Install:**
```bash
cd Checkpoint/helper && bash build.sh
cp -r CheckpointHelper.app /Applications/
open /Applications/CheckpointHelper.app
```

**Features:**
- Status indicator in menu bar (green = active, red = paused)
- Dashboard shows all projects with backup status and last result
- Add Project button — select a folder from the GUI, no terminal needed
- Right-click any project: Backup Now, Reveal in Finder, View Log, Remove Project, Enable/Disable
- In-app log viewer with filtering (All / Errors / Warnings) and "Copy for AI Help" button
- Error detail display — failed file counts shown inline with one-click LLM prompt copy
- First-launch onboarding wizard — guided 3-step setup for new users
- Double-click project to open in Finder
- Settings modal (`⌘,`) for global configuration
- Keyboard shortcuts: `⌘B` Backup All, `⌘R` Refresh
- Live progress during backups with phase descriptions
- Pause/Resume automatic backups
- Notification taps open the SwiftUI dashboard (not Terminal)

### Shell Integration

Shows backup status in prompt, auto-triggers on `cd`:

```bash
./integrations/shell/install.sh
source ~/.bashrc  # or ~/.zshrc

# Now you have:
user@host ~/project $           # Status in prompt
bs                              # Quick status check
bn                              # Quick backup
```

### Git Hooks

Auto-backup before every commit:

```bash
cd /your/project
/path/to/Checkpoint/integrations/git/install-git-hooks.sh
```

See [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) for all integrations.

---

## Requirements

### Platform Support
- **macOS** — Full support (launchd, fswatch, notifications)
- **Linux** — Full support (systemd, inotifywait, cron fallback)

### Dependencies

| Tool | Required | Purpose | Installation |
|------|----------|---------|--------------|
| `bash` 3.2+ | Yes | Script execution | Pre-installed |
| `git` | Yes | Change detection | `brew install git` / `apt install git` |
| `sqlite3` | Conditional | Database backups | `brew install sqlite3` / `apt install sqlite3` |
| `gzip` | Yes | Compression | Pre-installed |
| `rclone` | Optional | Cloud backups (API mode) | Auto-installed when enabled |
| `age` | Optional | Cloud encryption | `brew install age` / auto-installed |
| `fzf` | Optional | Interactive browsing | `brew install fzf` / `apt install fzf` |
| `fswatch` | Optional | File watcher (macOS) | `brew install fswatch` |
| `inotify-tools` | Optional | File watcher (Linux) | `apt install inotify-tools` |

---

## How It Works

### Project Discovery

When you run `checkpoint --auto` or the installer's auto-configure, Checkpoint scans your system for projects:

| Pass | What | Max Depth | How |
|------|------|-----------|-----|
| **Git repos** | Directories containing `.git` | 5 levels | `find -name .git` (maxdepth 6 to reach `.git` inside the project) |
| **Non-git projects** | Directories with project indicators (package.json, Cargo.toml, Dockerfile, etc.) | 4 levels | Checks for 28 file indicators |
| **External volumes** | `/Volumes/*/Developer`, `/Volumes/*/Projects`, `/Volumes/*/Code` | 5 levels | macOS only, git repos |
| **Desktop/Documents** | `~/Desktop`, `~/Documents` | 5 levels | git repos only |

**Depth limits explained:** A depth of 5 means Checkpoint will find `~/Projects/clients/acme/2025/webapp/.git` but **not** projects nested 6+ levels deep. Non-git projects use depth 4 because indicators like `Makefile` become ambiguous deeper in a directory tree (they could appear inside build artifacts or submodules rather than at a project root).

**If your project isn't discovered automatically:**
```bash
# Manually add any project regardless of depth
checkpoint add /path/to/deeply/nested/project
# Or just run backup-now from the project directory
cd /path/to/deeply/nested/project && backup-now
```

Manually added projects work identically to auto-discovered ones — they're registered in the global registry and included in all future hourly backups.

### Backup Process

1. **Drive Verification** (if enabled)
   - Check marker file exists
   - Skip if wrong/missing drive

2. **Database Backup** (if changed)
   - Compare size + modification time
   - Create compressed snapshot: `MyApp-2025.12.24-10.45.12.db.gz`

3. **File Backup** (changed only)
   - Get git diff (modified, staged, untracked)
   - Add critical files (.env, credentials)
   - Archive old versions to `archived/`
   - Copy new versions to `files/`

4. **Verification** (v2.5)
   - Post-backup integrity checks
   - Validate backup completeness

5. **Cloud Upload** (if enabled)
   - Sync files to cloud folder or via rclone
   - Compress compressible files with gzip
   - Encrypt all files with `age` (parallel when 100+ files)
   - Upload manifest and update cloud index
   - Clean up plaintext and stale encrypted variants

6. **Cleanup**
   - Remove old database backups (>30 days)
   - Remove old archived files (>60 days)

### Automation

**Hourly Daemon:**
- Runs every hour (launchd on macOS, systemd on Linux, cron fallback)
- Checks for changes before backing up
- Coordinates to avoid duplicate backups

**File Watcher:**
- Detects file changes in real-time via fswatch/inotifywait
- Configurable debounce interval
- Triggers backup on significant changes

**Watchdog (v2.5):**
- Monitors daemon health via heartbeat files
- Auto-restarts crashed daemons (KeepAlive/Restart=on-failure)
- Staleness detection with configurable thresholds
- Notification cooldown prevents alert fatigue

**Cloud Uploads:**
- Background process after local backup
- Doesn't block or slow down backups
- Automatic retry on failure

---

## Troubleshooting

### Cloud Backup Issues

**"rclone not installed"**
```bash
brew install rclone
# or
curl https://rclone.org/install.sh | bash
```

**"Cloud remote not found"**
```bash
rclone config         # Configure remote
rclone listremotes    # List configured remotes
```

**"Connection failed"**
```bash
rclone lsd remotename:    # Test connection
```

### General Issues

**No backups running**
```bash
backup-status             # Check status
```

**Drive not found**
```bash
ls -la /path/to/.backup-drive-marker
touch /path/to/.backup-drive-marker  # Create if missing
```

**Orphaned daemons (deleted projects still have running daemons)**
```bash
uninstall.sh --cleanup-orphans    # Find and remove orphans
uninstall.sh --orphans --dry-run  # Preview first
```

See [docs/CLOUD-BACKUP.md](docs/CLOUD-BACKUP.md) for cloud troubleshooting.

---

## FAQ

**Q: Does this work on Linux?**
A: Yes! v2.5 has full Linux support with native systemd service units. Cron fallback available for systems without systemd.

**Q: Does cloud backup slow down my backups?**
A: No. Cloud uploads run in background and don't block local backups.

**Q: What happens if I lose internet?**
A: Local backups continue normally. Cloud uploads queue and retry when connection restored.

**Q: How much does cloud storage cost?**
A: Free tier works for most projects! Google Drive: 15GB free, Dropbox: 2GB free.

**Q: Are cloud backups encrypted?**
A: Yes. All cloud files are encrypted with `age` before upload. Compressible files are also gzipped first for smaller uploads. No plaintext is ever stored on cloud storage. Your encryption key stays local at `~/.config/checkpoint/age-key.txt`.

**Q: How do I restore from cloud?**
A: Use `checkpoint cloud browse PROJECT` for an interactive file browser (with fzf support), or `checkpoint cloud download FILE` for individual files. Files are automatically decrypted and decompressed on download. You can also use the Cloud Browse modal in the dashboard.

**Q: What if I lose my encryption key?**
A: Without the key, cloud backups cannot be decrypted. Back up `~/.config/checkpoint/age-key.txt` securely (password manager, printed copy, etc.). Local backups are not encrypted and remain accessible.

**Q: Can I use this without Claude Code?**
A: Yes! Hourly daemon + integrations work standalone. Claude Code is not required.

**Q: What if I have multiple projects?**
A: Use global mode. One daemon backs up all registered projects. Run `backup-now` in any project to register it.

**Q: How do I restore a file?**
A: Run `backup-restore`, choose file, select version.

**Q: Can I change retention after setup?**
A: Yes. Edit `.backup-config.sh`, change `DB_RETENTION_DAYS` and `FILE_RETENTION_DAYS`.

**Q: What databases are supported?**
A: SQLite, PostgreSQL, MySQL, and MongoDB. Auto-detects all databases and installs required tools (pg_dump, mysqldump, mongodump) progressively.

**Q: How do I update Checkpoint?**
A: Run `backup-update`. Updates automatically from GitHub, including migrating existing installations.

**Q: Can I pause backups temporarily?**
A: Yes! Use `backup-pause` to pause (manual backups still work). Resume with `backup-pause --resume`.

**Q: What if a daemon crashes?**
A: The watchdog detects crashes via heartbeat monitoring and the KeepAlive/Restart policy auto-restarts the daemon. You'll get a notification if backups go stale.

**Q: Is there a GUI?**
A: Yes! The CheckpointHelper menu bar app (macOS) provides a dashboard with project status, backup controls, and settings. Build it from `helper/` and copy to Applications.

**Q: Can I change global defaults for all projects?**
A: Yes. Edit `~/.config/checkpoint/config.sh` or use the Settings button (`⌘,`) in the menu bar app. Per-project settings in `.backup-config.sh` always override globals.

**Q: How do I uninstall?**
A: Global: `./bin/uninstall-global.sh`. Per-project: `./bin/uninstall.sh`. Backup data is preserved by default.

**Q: What about orphaned daemons from deleted projects?**
A: Run `uninstall.sh --cleanup-orphans` to find and remove daemons for projects that no longer exist.

**Q: Why wasn't my project auto-discovered?**
A: Auto-discovery scans up to 5 levels deep for git repos and 4 levels for non-git projects. Projects nested deeper than this aren't found automatically — use `checkpoint add /path/to/project` or run `backup-now` from the project directory to register it manually.

---

## Documentation

- **[Cloud Backup Guide](docs/CLOUD-BACKUP.md)** — Complete cloud setup, providers, troubleshooting
- **[Commands Reference](docs/COMMANDS.md)** — All commands and options
- **[Integrations Guide](docs/INTEGRATIONS.md)** — Shell, Git, Vim, VS Code, Tmux
- **[API Reference](docs/API.md)** — Library functions for developers
- **[Development Guide](docs/DEVELOPMENT.md)** — Contributing guidelines
- **[Migration Guide](docs/MIGRATION.md)** — Upgrading from older versions
- **[Testing Guide](docs/TESTING.md)** — Running tests

---

## Architecture

### Repository Structure

```
Checkpoint/
├── bin/                              # Command scripts
│   ├── backup-now.sh                 # Manual backup
│   ├── backup-status.sh              # Status display
│   ├── backup-restore.sh             # File restoration
│   ├── backup-cleanup.sh             # Retention management
│   ├── backup-update.sh              # Self-update + migration
│   ├── backup-pause.sh               # Pause/resume
│   ├── backup-verify.sh              # Backup integrity checks
│   ├── backup-watch.sh               # Native file watcher
│   ├── backup-cloud-config.sh        # Cloud setup
│   ├── checkpoint-cloud.sh           # Cloud browse/download/restore
│   ├── encrypt-cloud-bulk.sh         # Bulk encrypt cloud files (parallel)
│   ├── compress-cloud-bulk.sh        # Bulk compress .age → .gz.age (parallel)
│   ├── backup-daemon.sh              # Hourly backup daemon
│   ├── backup-all-projects.sh        # Multi-project backup
│   ├── checkpoint-watchdog.sh         # Daemon health monitor
│   ├── install-global.sh             # Global installer
│   ├── install.sh                    # Per-project installer
│   ├── uninstall.sh                  # Per-project uninstaller
│   └── uninstall-global.sh           # Global uninstaller
├── lib/                              # Modular library
│   ├── core/                         # Foundation
│   │   ├── config.sh                 # Configuration loading
│   │   ├── logging.sh                # Structured logging
│   │   ├── error-codes.sh            # Error code definitions
│   │   └── output.sh                 # Output formatting
│   ├── ops/                          # Operations
│   │   ├── file-ops.sh               # File backup operations
│   │   ├── init.sh                   # Initialization
│   │   └── state.sh                  # State management
│   ├── features/                     # Feature modules
│   │   ├── change-detection.sh       # Smart change detection
│   │   ├── cleanup.sh                # Retention cleanup
│   │   ├── health-stats.sh           # Health statistics
│   │   ├── restore.sh                # Restore operations
│   │   ├── verification.sh           # Backup verification
│   │   ├── encryption.sh            # age encryption helpers
│   │   ├── cloud-restore.sh         # Cloud download/decrypt/restore
│   │   ├── cloud-destinations.sh    # Three-tier cloud transport
│   │   └── ...
│   ├── platform/                     # Platform abstraction
│   │   ├── daemon-manager.sh         # launchd/systemd/cron
│   │   ├── file-watcher.sh           # fswatch/inotifywait
│   │   └── compat.sh                 # Cross-platform compat
│   ├── security/                     # Security modules
│   │   ├── credential-provider.sh    # Credential management
│   │   └── secure-download.sh        # Verified downloads
│   └── ui/                           # UI utilities
│       ├── formatting.sh             # Output formatting
│       └── time-size-utils.sh        # Time/size helpers
├── integrations/                     # Editor/shell integrations
│   ├── shell/                        # Bash/Zsh prompt
│   ├── git/                          # Git hooks
│   ├── vim/                          # Vim/Neovim
│   ├── vscode/                       # VS Code
│   ├── tmux/                         # Tmux status bar
│   └── direnv/                       # Direnv
├── templates/                        # Service templates
│   ├── launchd-watcher.plist         # macOS file watcher
│   ├── com.checkpoint.watchdog.plist # macOS watchdog
│   ├── systemd-daemon.service        # Linux backup daemon
│   ├── systemd-daemon.timer          # Linux backup timer
│   ├── systemd-watchdog.service      # Linux watchdog
│   └── systemd-watcher.service       # Linux file watcher
├── helper/                           # macOS menu bar app
│   ├── CheckpointHelper/             # Swift source (SwiftUI dashboard)
│   └── build.sh                      # Build script
├── .claude/skills/                   # Claude Code skills
├── docs/                             # Documentation
└── tests/                            # Test suite (164 tests)
```

### Project After Installation

```
your-project/
├── .backup-config.sh            # Configuration
├── backups/                     # Backup data (gitignored)
│   ├── databases/
│   ├── files/
│   ├── archived/
│   └── backup.log
└── .gitignore                   # Updated
```

---

## Testing

**Test Coverage: 100% (164/164 tests passing)**

```bash
# Run all tests
./tests/run-all-tests.sh

# Individual test suites:
./tests/unit/test-core-functions.sh
./tests/integration/test-backup-restore-workflow.sh
./tests/integration/test-cloud-backup.sh
./tests/e2e/test-user-journeys.sh
./tests/compatibility/test-bash-compatibility.sh
./tests/stress/test-edge-cases.sh
./tests/smoke-test.sh
```

See [docs/TESTING.md](docs/TESTING.md) for details.

---

## Credits

**Author:** Jon Rezin
**Company:** [FluxCode Studio](https://fluxcode.studio) (Fluxcode Studio LLC)
**Repository:** https://github.com/fluxcodestudio/Checkpoint
**License:** [Polyform Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)

---

## License

Polyform Noncommercial License 1.0.0 — see [LICENSE](LICENSE) file for details.

Checkpoint is free to use for any noncommercial purpose. Commercial use requires written permission from Fluxcode Studio LLC. Attribution is required in all cases.
