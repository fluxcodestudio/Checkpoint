<div align="center">

<img src=".github/assets/checkpoint-logo.png" alt="Checkpoint Logo" width="200"/>

# Checkpoint

**A code guardian for developing projects. A little peace of mind goes a long way.**

Automated, intelligent backup system for any development environment. Battle-tested with comprehensive test coverage, cloud backup support, and multi-platform integrations.

**Version:** 2.2.0
**Test Coverage:** 164/164 (100%)
**License:** GPL v3

</div>

---

## What's New in v2.2.0

🚀 **Universal Database Support**
- Auto-detects PostgreSQL, MySQL, MongoDB (in addition to SQLite)
- Distinguishes local vs remote databases
- Progressive installation of database tools (pg_dump, mysqldump, mongodump)

⚡ **Lightning-Fast Installation**
- Streamlined wizard: 5 questions, ~20 seconds
- All questions upfront → uninterrupted installation
- Clear progress indicators: [1/5] [2/5] [3/5] [4/5] [5/5]
- One consolidated approval for all dependencies

🎯 **Improved UX**
- Clean, minimal output
- Smart defaults (no more 15+ questions)
- Per-project mode now includes all commands in `./bin/`
- Better error messages and progress feedback

---

## Features

### Core Capabilities
- **Organized Backup Structure** — Databases, current files, and archived versions in separate folders
- **Smart Change Detection** — Only backs up modified files
- **Works Without Git** — Automatic fallback for non-git directories (uses filesystem scan + mtime)
- **Instant Failure Alerts** — Native macOS notifications when backup fails (spam-prevented, actionable)
- **Universal Database Detection** — Auto-detects and backs up SQLite, PostgreSQL, MySQL, MongoDB (local only)
- **Database Snapshots** — Compressed timestamped backups with proper tools (sqlite3, pg_dump, mysqldump, mongodump)
- **Version Archiving** — Old versions preserved when files change (not deleted)
- **Critical File Coverage** — Backs up .env, credentials, cloud configs (AWS, GCP), Terraform secrets, IDE settings, notes, local overrides (kept out of Git)
- **Cloud Backup** — Off-site protection via rclone (Dropbox, Google Drive, OneDrive, iCloud)
- **Drive Verification** — Ensures backing up to correct external drive
- **Automated Triggers** — Hourly daemon + session detection
- **Universal Integrations** — Works with Shell, Git, Vim, VS Code, Tmux
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
git clone https://github.com/nizernoj/Checkpoint.git
cd Checkpoint

# Run installer
./bin/install.sh
```

**Choose Installation Mode:**

**1. Global (Recommended)**
- Install once, use everywhere
- Commands available system-wide: `backup-now`, `backup-status`, etc.
- Easy updates: `git pull && ./bin/install.sh`
- Installs to: `/usr/local` or `~/.local`

**2. Per-Project**
- Self-contained in project directory
- Portable (copy project = copy backup system)
- No system modifications
- Good for: shared systems, containers

**The installer is fast and streamlined (5 questions, ~20 seconds):**

1. **Auto-detects databases** (SQLite, PostgreSQL, MySQL, MongoDB)
   - Shows what was found
   - "Back up these databases? (Y/n)"

2. **Cloud backup?** (optional)
   - One-time approval to install rclone if needed

3. **Hourly backups?** (macOS LaunchAgent)

4. **Claude Code integration?** (optional)

5. **Run initial backup?**

Then installs without interruption:
```
[1/5] Creating configuration... ✓
[2/5] Installing scripts... ✓
[3/5] Configuring .gitignore... ✓
→ Running initial backup... ✓
✅ Done!
```

### Cloud Backup Setup

**During Installation:**
- Installer asks: "Do you want cloud backup?"
- If yes → Auto-installs rclone → Configure provider

**After Installation:**
```bash
# Enable cloud backup later
backup-cloud-config  # (global mode)
# or
./bin/backup-cloud-config.sh  # (per-project mode)
```

**What Happens:**
- Checks for rclone, auto-installs if missing (with permission)
- Choose provider: Dropbox, Google Drive, OneDrive, iCloud
- OAuth authentication via browser
- Configure backup path
- Done!

### Verification

```bash
# Check status
./bin/backup-status.sh

# View backups
ls -la backups/databases/
ls -la backups/files/
```

---

## Commands

**Global Mode:** Commands available system-wide
**Per-Project Mode:** Run from `bin/` directory
**Claude Code:** All commands available as slash commands (`/checkpoint`, `/backup-now`, etc.)

### Main Control Panel

Use `/checkpoint` (Claude Code) or `backup-status` for quick overview:

```bash
/checkpoint              # Control panel with status and updates
backup-status            # Detailed system health
```

### All Commands

| Command | Global | Per-Project | Description |
|---------|--------|-------------|-------------|
| `backup-status` | ✓ | `./bin/backup-status.sh` | View backup health, statistics, cloud status |
| `backup-now` | ✓ | `./bin/backup-now.sh` | Trigger immediate backup |
| `backup-restore` | ✓ | `./bin/backup-restore.sh` | Restore from backups |
| `backup-cleanup` | ✓ | `./bin/backup-cleanup.sh` | Manage old backups and disk space |
| `backup-update` | ✓ | `./bin/backup-update.sh` | Update Checkpoint from GitHub |
| `backup-pause` | ✓ | `./bin/backup-pause.sh` | Pause/resume automatic backups |
| `backup-cloud-config` | ✓ | `./bin/backup-cloud-config.sh` | Configure cloud backup |
| `install.sh` | N/A | `./bin/install.sh` | Install Checkpoint |
| `uninstall.sh` | ✓ | `./bin/uninstall.sh` | Uninstall Checkpoint |

### Command Examples

**Control Panel (Claude Code):**
```bash
/checkpoint                          # Status, updates, help
/checkpoint --update                 # Update Checkpoint
/checkpoint --check-update           # Check for updates
```

**Check Status:**
```bash
./bin/backup-status.sh
./bin/backup-status.sh --compact
```

**Manual Backup:**
```bash
./bin/backup-now.sh
./bin/backup-now.sh --force          # Ignore change detection
./bin/backup-now.sh --local-only     # Skip cloud upload
```

**Update System:**
```bash
./bin/backup-update.sh               # Update from GitHub
./bin/backup-update.sh --check-only  # Check without installing
```

**Pause/Resume:**
```bash
./bin/backup-pause.sh                # Pause automatic backups
./bin/backup-pause.sh --resume       # Resume backups
./bin/backup-pause.sh --status       # Check if paused
```

**Configure Cloud:**
```bash
./bin/backup-cloud-config.sh         # Interactive wizard
```

**Restore:**
```bash
./bin/backup-restore.sh              # Interactive menu
./bin/backup-restore.sh --help       # See all options
```

**Cleanup:**
```bash
./bin/backup-cleanup.sh              # Preview cleanup
./bin/backup-cleanup.sh --execute    # Execute cleanup
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
- ✅ Database backups (~2MB compressed each)
- ✅ Critical files (.env, credentials, keys, cloud configs, Terraform secrets, local overrides)

**Optional:**
- ❌ Project files (already in Git)

**Estimated Storage:**
- 10MB database → 2MB compressed
- 30 days retention → ~60MB total
- **Fits in all free tiers!**

### Setup

```bash
# Run wizard
./bin/backup-cloud-config.sh
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

### Usage

Cloud uploads happen **automatically** after each local backup (in background).

```bash
# Normal backup (includes cloud if enabled)
./bin/backup-now.sh

# Skip cloud for one backup
./bin/backup-now.sh --local-only

# Check cloud status
./bin/backup-status.sh
# Shows: "Cloud: 2 hours ago"
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
DB_TYPE="sqlite"  # or "none"
DB_RETENTION_DAYS=30

# Files
FILE_RETENTION_DAYS=60

# Automation
BACKUP_INTERVAL=3600              # 1 hour
SESSION_IDLE_THRESHOLD=600        # 10 minutes

# Drive Verification
DRIVE_VERIFICATION_ENABLED=true
DRIVE_MARKER_FILE="/Volumes/Drive/.backup-drive-marker"

# Critical Files
BACKUP_ENV_FILES=true              # .env, .env.*
BACKUP_CREDENTIALS=true            # Keys, certs, cloud configs, Terraform
BACKUP_IDE_SETTINGS=true           # .vscode/, .idea/
BACKUP_LOCAL_NOTES=true            # NOTES.md, TODO.local.md
BACKUP_LOCAL_DATABASES=true        # *.db, *.sqlite (non-primary)
```

**What's Backed Up:**
- `BACKUP_ENV_FILES`: `.env`, `.env.*` (all environment files)
- `BACKUP_CREDENTIALS`:
  - Certificates: `*.pem`, `*.key`, `*.p12`, `*.pfx`
  - Secrets: `credentials.json`, `secrets.*`
  - Cloud: `.aws/credentials`, `.gcp/*.json`
  - Infrastructure: `terraform.tfvars`, `*.tfvars`, `.firebase/*.json`
  - Local overrides: `*.local.*`, `local.settings.json`, `appsettings.*.json`, `docker-compose.override.yml`
- `BACKUP_IDE_SETTINGS`: `.vscode/settings.json`, `.vscode/launch.json`, `.vscode/extensions.json`, `.idea/workspace.xml`, `.idea/codeStyles/*`
- `BACKUP_LOCAL_NOTES`: `NOTES.md`, `TODO.local.md`, `*.private.md`
- `BACKUP_LOCAL_DATABASES`: Local `*.db`, `*.sqlite`, `*.sql` files (excluding primary database)

Edit anytime to change settings.

### Cloud Configuration

```bash
# Cloud Backup
BACKUP_LOCATION="both"           # local | cloud | both
CLOUD_ENABLED=true
CLOUD_PROVIDER="gdrive"
CLOUD_REMOTE_NAME="mygdrive"
CLOUD_BACKUP_PATH="/Backups/MyProject"
CLOUD_SYNC_DATABASES=true
CLOUD_SYNC_CRITICAL=true
CLOUD_SYNC_FILES=false
```

---

## Failure Notifications

**Never miss a backup failure** - Get instant macOS notifications when something goes wrong.

### How It Works

**When Backup Fails:**
1. Native notification appears immediately
2. Shows error count and type
3. Plays warning sound ("Basso")
4. Includes actionable message: "Run 'backup-status' to check"

**When Backup Recovers:**
1. Success notification appears
2. Confirms backup is working again
3. Plays success sound ("Glass")

**Spam Prevention:**
- Only notifies **ONCE** on first failure
- Won't spam you every hour while issue persists
- Automatically clears when backup succeeds

### Examples

**Failure Notification:**
```
⚠️ Checkpoint Backup Failed
AI_GUARD failed with 1 error(s). Run 'backup-status' to check.
```

**Success After Failure:**
```
✅ Checkpoint Backup Restored
AI_GUARD is working again!
```

### Configuration

Notifications are **enabled by default**. To disable:

```bash
# In .backup-config.sh
NOTIFICATIONS_ENABLED=false
```

### Troubleshooting

**Not receiving notifications?**
1. Check System Preferences → Notifications → Script Editor (allow notifications)
2. Test notification: `osascript -e 'display notification "Test" with title "Checkpoint"'`
3. Verify `NOTIFICATIONS_ENABLED=true` in config

---

## Universal Integrations

Checkpoint works anywhere—not just Claude Code!

### Available Integrations

| Integration | Auto-Trigger | Visual Status | Setup |
|-------------|--------------|---------------|-------|
| **Shell (Bash/Zsh)** | ✅ On `cd` | ✅ Prompt indicator | `./integrations/shell/install.sh` |
| **Git Hooks** | ✅ Pre-commit | ✅ Messages | `./integrations/git/install-git-hooks.sh` |
| **Vim/Neovim** | ✅ On save | ✅ Statusline | See `integrations/vim/README.md` |
| **VS Code** | - | - | `./integrations/vscode/install-vscode.sh` |
| **Tmux** | ⏱️ 60s refresh | ✅ Status bar | `./integrations/tmux/install-tmux.sh` |
| **Direnv** | ✅ On enter | - | `./integrations/direnv/install.sh` |

### Shell Integration

Shows backup status in prompt, auto-triggers on `cd`:

```bash
./integrations/shell/install.sh
source ~/.bashrc  # or ~/.zshrc

# Now you have:
✅ user@host ~/project $           # Status in prompt
bs                                  # Quick status check
bn                                  # Quick backup
```

### Git Hooks

Auto-backup before every commit:

```bash
cd /your/project
/path/to/Checkpoint/integrations/git/install-git-hooks.sh

# Now git commit automatically backs up first!
```

See [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) for all integrations.

---

## Requirements

### Platform Support
- **macOS** — Full support (LaunchAgent, all features)
- **Linux** — Partial support (manual/cron, no LaunchAgent)

### Dependencies

| Tool | Required | Purpose | Installation |
|------|----------|---------|--------------|
| `bash` 3.2+ | ✅ Yes | Script execution | Pre-installed |
| `git` | ✅ Yes | Change detection | `brew install git` |
| `sqlite3` | Conditional | Database backups | `brew install sqlite3` |
| `gzip` | ✅ Yes | Compression | Pre-installed |
| `rclone` | Optional | Cloud backups | **Auto-installed** when you enable cloud backup |
| `launchctl` | macOS only | Scheduling | Pre-installed on macOS |

**Note:** rclone is automatically installed (with your permission) when you choose cloud backup during installation or run `backup-cloud-config`.

---

## How It Works

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

4. **Cloud Upload** (if enabled)
   - Upload in background (doesn't block)
   - Retry on failure
   - Track upload time

5. **Cleanup**
   - Remove old database backups (>30 days)
   - Remove old archived files (>60 days)

### Automation

**Hourly Daemon:**
- Runs every hour (macOS LaunchAgent)
- Checks for changes
- Coordinates to avoid duplicates

**Session Detection:**
- Detects new work session (>10 min idle)
- Triggers immediate backup
- Works with Claude Code hooks

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
./bin/backup-status.sh    # Check status
```

**Drive not found**
```bash
ls -la /path/to/.backup-drive-marker
touch /path/to/.backup-drive-marker  # Create if missing
```

**Files not backed up**
```bash
git status               # See what changed
git diff                 # See file changes
```

See [docs/CLOUD-BACKUP.md](docs/CLOUD-BACKUP.md) for cloud troubleshooting.

---

## FAQ

**Q: Does cloud backup slow down my backups?**
A: No. Cloud uploads run in background and don't block local backups.

**Q: Does this work on Windows/Linux?**
A: macOS fully supported. Linux partial (manual/cron backups, no LaunchAgent).

**Q: What happens if I lose internet?**
A: Local backups continue normally. Cloud uploads queue and retry when connection restored.

**Q: How much does cloud storage cost?**
A: Free tier works for most projects! Google Drive: 15GB free, Dropbox: 2GB free.

**Q: Can I use this without Claude Code?**
A: Yes! Hourly daemon + integrations work standalone. Claude Code hooks optional.

**Q: What if I have multiple projects?**
A: Install in each project. Each gets own config and backups.

**Q: How do I restore a file?**
A: Run `./bin/backup-restore.sh`, choose file, select version.

**Q: Can I change retention after setup?**
A: Yes. Edit `.backup-config.sh`, change `DB_RETENTION_DAYS` and `FILE_RETENTION_DAYS`.

**Q: What databases are supported?**
A: SQLite, PostgreSQL, MySQL, and MongoDB! v2.2.0 auto-detects all databases and installs required tools (pg_dump, mysqldump, mongodump) progressively.

**Q: How do I update Checkpoint?**
A: Use `/checkpoint --update` (Claude Code) or `./bin/backup-update.sh`. Updates automatically from GitHub.

**Q: Can I pause backups temporarily?**
A: Yes! Use `/backup-pause` to pause automatic backups (manual backups still work). Resume with `/backup-pause --resume`.

**Q: What's the `/checkpoint` command?**
A: Control panel showing version, status, updates, and all available commands. Use `/checkpoint --info` to see installation mode (Global vs Per-Project).

**Q: How do I uninstall?**
A: Use `/uninstall` (keeps backups by default) or `./bin/uninstall.sh`. Add `--no-keep-backups` to remove everything.

---

## Documentation

- **[Cloud Backup Guide](docs/CLOUD-BACKUP.md)** - Complete cloud setup, providers, troubleshooting
- **[Commands Reference](docs/COMMANDS.md)** - All commands and options
- **[Integrations Guide](docs/INTEGRATIONS.md)** - Shell, Git, Vim, VS Code, Tmux
- **[API Reference](docs/API.md)** - Library functions for developers
- **[Development Guide](docs/DEVELOPMENT.md)** - Contributing guidelines
- **[Migration Guide](docs/MIGRATION.md)** - Upgrading from older versions
- **[Testing Guide](docs/TESTING.md)** - Running tests (164/164 passing + 115 v2.2.0)
- **[Testing Report](TESTING-REPORT.md)** - Comprehensive v2.2.0 validation results

---

## Architecture

### Repository Structure

```
Checkpoint/
├── bin/                          # Command scripts
│   ├── backup-status.sh
│   ├── backup-now.sh
│   ├── backup-config.sh
│   ├── backup-restore.sh
│   ├── backup-cleanup.sh
│   ├── backup-update.sh          # Update from GitHub (v2.2.0)
│   ├── backup-pause.sh           # Pause/resume (v2.2.0)
│   ├── backup-cloud-config.sh    # Cloud setup
│   ├── backup-daemon.sh
│   ├── install.sh
│   └── uninstall.sh
├── lib/                          # Core libraries
│   ├── backup-lib.sh
│   ├── cloud-backup.sh           # Cloud functions
│   ├── database-detector.sh      # Universal DB detection (v2.2.0)
│   └── dependency-manager.sh     # Progressive installs (v2.2.0)
├── integrations/                 # Universal integrations
│   ├── shell/
│   ├── git/
│   ├── vim/
│   ├── vscode/
│   └── tmux/
├── .claude/skills/              # Claude Code commands (v2.2.0)
│   ├── checkpoint/              # Control panel
│   ├── backup-update/           # Update command
│   ├── backup-pause/            # Pause/resume
│   ├── uninstall/               # Safe uninstall
│   └── [8 more skills]
├── docs/                         # Documentation
├── tests/                        # Test suite (164 tests)
├── templates/
└── examples/
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

**Test Coverage: 100% (164/164 tests passing + 115 v2.2.0 tests)**

```bash
# Run all tests
./tests/run-all-tests.sh

# Test suites:
./tests/unit/test-core-functions.sh              # 22/22
./tests/integration/test-backup-restore-workflow.sh  # 16/16
./tests/integration/test-cloud-backup.sh         # 13/13 (cloud)
./tests/e2e/test-user-journeys.sh                # 34/34
./tests/compatibility/test-bash-compatibility.sh  # 34/36 (2 platform skipped)
./tests/stress/test-edge-cases.sh                # 36/36
./tests/smoke-test.sh                            # 22/22
```

See [docs/TESTING.md](docs/TESTING.md) for details.

---

## Credits

**Author:** Jon Rezin
**Repository:** https://github.com/nizernoj/Checkpoint
**License:** GPL v3

Built from real-world usage with comprehensive testing and cloud backup support.

---

## License

GPL v3 License — see [LICENSE](LICENSE) file for details.

This ensures Checkpoint remains free and open-source for the community forever.
