# Checkpoint

**A code guardian for developing projects. A little peace of mind goes a long way.**

Automated, intelligent backup system for any development environment. Battle-tested with comprehensive test coverage, cloud backup support, and multi-platform integrations.

**Version:** 2.1.0
**Test Coverage:** 164/164 (100%)
**License:** MIT

---

## Features

### Core Capabilities
- **Organized Backup Structure** — Databases, current files, and archived versions in separate folders
- **Smart Change Detection** — Only backs up modified files
- **Database Snapshots** — Compressed timestamped backups (SQLite supported)
- **Version Archiving** — Old versions preserved when files change (not deleted)
- **Critical File Coverage** — Backs up .env, credentials, IDE settings, notes (kept out of Git)
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

# Navigate to YOUR project
cd /path/to/your/project

# Run installer
/path/to/Checkpoint/bin/install.sh
```

The installer will:
1. Configure backup settings (project name, database, retention)
2. Create `.backup-config.sh` in your project
3. Set up automated backups
4. Run initial backup

### Cloud Backup Setup (Optional)

```bash
# Run cloud configuration wizard
./bin/backup-cloud-config.sh
```

Choose provider (Dropbox/GDrive/OneDrive/iCloud), configure rclone, done!

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

All commands available in `bin/` directory:

| Command | Description |
|---------|-------------|
| `backup-status.sh` | View backup health, statistics, cloud status |
| `backup-now.sh` | Trigger immediate backup |
| `backup-config.sh` | Configure backup settings |
| `backup-restore.sh` | Restore from backups |
| `backup-cleanup.sh` | Manage old backups and disk space |
| `backup-cloud-config.sh` | Configure cloud backup |
| `install.sh` | Install Checkpoint in project |
| `uninstall.sh` | Uninstall Checkpoint |

### Command Examples

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
- ✅ Critical files (.env, credentials, keys)

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
BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=true
```

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
| `rclone` | Optional | Cloud backups | `brew install rclone` |
| `launchctl` | macOS only | Scheduling | Pre-installed on macOS |

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
A: Currently SQLite. PostgreSQL/MySQL would need dump commands (PRs welcome!).

---

## Documentation

- **[Cloud Backup Guide](docs/CLOUD-BACKUP.md)** - Complete cloud setup, providers, troubleshooting
- **[Commands Reference](docs/COMMANDS.md)** - All commands and options
- **[Integrations Guide](docs/INTEGRATIONS.md)** - Shell, Git, Vim, VS Code, Tmux
- **[API Reference](docs/API.md)** - Library functions for developers
- **[Development Guide](docs/DEVELOPMENT.md)** - Contributing guidelines
- **[Migration Guide](docs/MIGRATION.md)** - Upgrading from older versions
- **[Testing Guide](docs/TESTING.md)** - Running tests (164/164 passing)

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
│   ├── backup-cloud-config.sh    # Cloud setup
│   ├── backup-daemon.sh
│   ├── install.sh
│   └── uninstall.sh
├── lib/                          # Core libraries
│   ├── backup-lib.sh
│   └── cloud-backup.sh           # Cloud functions
├── integrations/                 # Universal integrations
│   ├── shell/
│   ├── git/
│   ├── vim/
│   ├── vscode/
│   └── tmux/
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

**Test Coverage: 100% (164/164 tests passing)**

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
**License:** MIT

Built from real-world usage with comprehensive testing and cloud backup support.

---

## License

MIT License — see [LICENSE](LICENSE) file for details.
