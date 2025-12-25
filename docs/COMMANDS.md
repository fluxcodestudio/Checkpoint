# Command Reference

Complete reference for Checkpoint command system.

---

## Table of Contents

- [Overview](#overview)
- [Command Index](#command-index)
- [`/checkpoint` - Control Panel](#checkpoint---control-panel)
- [`/backup-config` - Configuration Management](#backup-config---configuration-management)
- [`/backup-status` - Health Monitoring](#backup-status---health-monitoring)
- [`/backup-now` - Manual Backup](#backup-now---manual-backup)
- [`/backup-restore` - Restore Wizard](#backup-restore---restore-wizard)
- [`/backup-cleanup` - Space Management](#backup-cleanup---space-management)
- [`/backup-update` - System Updates](#backup-update---system-updates)
- [`/backup-pause` - Pause/Resume](#backup-pause---pauseresume)
- [`/uninstall` - Uninstall Checkpoint](#uninstall---uninstall-checkpoint)
- [Configuration Schema](#configuration-schema)
- [Use Case Examples](#use-case-examples)
- [Troubleshooting](#troubleshooting)

---

## Overview

Checkpoint v2.2.0 introduces a comprehensive command system for managing backups through an intuitive CLI. All commands support both interactive (TUI) and programmatic modes.

### Quick Start

```bash
# Control panel (status, updates, help)
/checkpoint

# Interactive configuration wizard
/backup-config wizard

# Check backup health
/backup-status

# Trigger immediate backup
/backup-now

# Restore from backup
/backup-restore

# Clean up old backups
/backup-cleanup

# Update Checkpoint
/checkpoint --update
```

### Installation Location

Commands are installed to:
- **Global:** `/usr/local/bin/backup-*` (symlinked to package)
- **Per-project:** `.claude/commands/` (local overrides)

---

## Command Index

| Command | Description | Interactive Mode | Flags |
|---------|-------------|------------------|-------|
| `/checkpoint` | Control panel & status | ✅ Dashboard | `--update`, `--status`, `--check-update` |
| `/backup-config` | Manage configuration | ✅ Wizard & TUI | `--get`, `--set`, `--validate`, `--migrate` |
| `/backup-status` | View system health | ✅ Dashboard | `--json`, `--verbose`, `--check` |
| `/backup-now` | Trigger manual backup | ❌ No | `--force`, `--dry-run`, `--db-only`, `--files-only` |
| `/backup-restore` | Restore files/database | ✅ Wizard | `--database`, `--file`, `--list` |
| `/backup-cleanup` | Manage disk space | ✅ Preview mode | `--preview`, `--force`, `--recommend` |
| `/backup-update` | Update from GitHub | ❌ No | `--check-only`, `--force` |
| `/backup-pause` | Pause/resume backups | ❌ No | `--resume`, `--status` |
| `/uninstall` | Uninstall Checkpoint | ✅ Confirmation | `--keep-backups`, `--force` |

---

## `/checkpoint` - Control Panel

### Synopsis

```bash
/checkpoint [OPTIONS]
```

### Description

Main control panel for Checkpoint. Displays system status, checks for updates, and provides quick access to all commands.

### Default Output

```bash
/checkpoint
```

**Output:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Checkpoint Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Version: v2.2.0
✓ You're running the latest version: v2.2.0

Status: ✅ ACTIVE

Backups are running normally.
Last backup: 45 minutes ago
Next backup: 15 minutes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Available Commands:
  /checkpoint --update       Check and install updates
  /backup-now              Create backup immediately
  /backup-pause            Pause automatic backups
  /backup-restore          Restore from backup
  /backup-cleanup          Clean old backups
```

### Options

| Flag | Description | Example |
|------|-------------|---------|
| `--update` | Check and install updates | `/checkpoint --update` |
| `--status` | Show status (same as default) | `/checkpoint --status` |
| `--check-update` | Check for updates only | `/checkpoint --check-update` |

### Examples

**Example 1: Check status**
```bash
/checkpoint
```

**Example 2: Update Checkpoint**
```bash
/checkpoint --update
```

**Output:**
```
ℹ  Update available: v2.2.0 → v2.3.0

ℹ  Starting update...
✓ Downloaded v2.3.0
✓ Extracted update
✓ Updated successfully
```

**Example 3: Check for updates without installing**
```bash
/checkpoint --check-update
```

---

## `/backup-config` - Configuration Management

### Synopsis

```bash
/backup-config [MODE] [OPTIONS]
```

### Modes

#### Interactive Wizard (Default)

Guided setup for new installations:

```bash
/backup-config wizard
```

**Features:**
- Step-by-step configuration
- Real-time validation
- Default suggestions
- Path auto-completion
- Drive detection

**Example Session:**

```
┌─────────────────────────────────────────┐
│ Checkpoint Setup       │
│ Version 1.1.0                           │
└─────────────────────────────────────────┘

Project Configuration
━━━━━━━━━━━━━━━━━━━━
→ Project name: MyApp
→ Project directory: /Volumes/Drive/MyApp [detected]
→ Backup location: /Volumes/Drive/MyApp/backups [recommended]

Database Configuration
━━━━━━━━━━━━━━━━━━━━
→ Enable database backups? (y/n) [y]: y
→ Database type: (1) SQLite (2) None [1]: 1
→ Database path: /Users/me/.myapp/data.db

Retention Policy
━━━━━━━━━━━━━━━━━━━━
→ Database retention (days) [30]: 30
→ File retention (days) [60]: 60

✅ Configuration saved to .backup-config.yaml
```

#### TUI Editor

Visual configuration editor for existing installations:

```bash
/backup-config
# or
/backup-config edit
```

**Features:**
- Live YAML editor with syntax highlighting
- Section-based navigation
- Validation on save
- Diff preview
- Rollback capability

**Keys:**
- `Tab` / `Shift+Tab` - Navigate sections
- `Enter` - Edit field
- `Ctrl+S` - Save changes
- `Ctrl+Q` - Quit without saving
- `Ctrl+V` - Validate configuration

#### Get/Set Mode

Programmatic access for scripts:

```bash
# Get single value
/backup-config --get project.name

# Get section
/backup-config --get retention

# Set value
/backup-config --set retention.database_days=90

# Set multiple values
/backup-config --set \
    project.name=NewName \
    retention.file_days=120
```

**Output Format:**

```bash
# Single value
MyApp

# Section (YAML)
database_days: 30
file_days: 60

# JSON output
/backup-config --get retention --json
{"database_days": 30, "file_days": 60}
```

### Options

| Flag | Description | Example |
|------|-------------|---------|
| `--get KEY` | Get configuration value | `--get project.name` |
| `--set KEY=VALUE` | Set configuration value | `--set retention.database_days=90` |
| `--validate` | Validate configuration | `--validate` |
| `--migrate` | Migrate from bash to YAML | `--migrate` |
| `--template` | Generate config template | `--template minimal` |
| `--json` | Output as JSON | `--get project --json` |
| `--reset` | Reset to defaults | `--reset` |
| `--backup` | Create config backup | `--backup` |

### Examples

**Example 1: Check current project name**
```bash
/backup-config --get project.name
# Output: MyApp
```

**Example 2: Update retention policy**
```bash
/backup-config --set retention.database_days=90 retention.file_days=180
# Output: ✅ Configuration updated
```

**Example 3: Validate configuration**
```bash
/backup-config --validate
# Output:
# ✅ Configuration valid
#
# Summary:
#   - Project: MyApp
#   - Database: SQLite (/path/to/db.db)
#   - Retention: DB=30d, Files=60d
#   - Drive verification: Enabled
```

**Example 4: Migrate from v1.0**
```bash
/backup-config --migrate
# Output:
# 🔄 Migrating .backup-config.sh → .backup-config.yaml
# ✅ Migration complete
# ✅ Backup created: .backup-config.sh.backup
#
# Next steps:
#   - Test configuration: /backup-status
#   - Remove old config: rm .backup-config.sh.backup
```

**Example 5: Generate minimal template**
```bash
/backup-config --template minimal > my-config.yaml
```

### Configuration Templates

Available templates:
- `minimal` - Bare minimum settings
- `standard` - Recommended defaults
- `paranoid` - Maximum retention
- `external-drive` - Multi-computer setup
- `no-database` - Files only

---

## `/backup-status` - Health Monitoring

### Synopsis

```bash
/backup-status [OPTIONS]
```

### Default Output

```
┌─────────────────────────────────────────────────────┐
│ Checkpoint - Health Dashboard      │
│ MyApp (v1.1.0)                                      │
└─────────────────────────────────────────────────────┘

System Health
━━━━━━━━━━━━━
✅ Configuration: Valid
✅ LaunchAgent: Running (PID 12345)
✅ External Drive: Connected
✅ Backup Directory: Writable
⚠️  Disk Space: 12.5 GB free (low)

Backup Statistics
━━━━━━━━━━━━━━━━━
  Databases: 42 snapshots (1.2 GB)
  Files: 156 files (843 MB)
  Archived: 89 versions (432 MB)
  Total Size: 2.5 GB

Last Backup: 45 minutes ago
Next Scheduled: 15 minutes

Recent Activity (last 24h)
━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ 12:30 PM - Backup completed (12 files, 1 database)
  ✅ 11:30 AM - Backup completed (3 files)
  ⏭️  10:30 AM - Backup skipped (no changes)
  ✅ 09:30 AM - Backup completed (5 files, 1 database)

Warnings & Recommendations
━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚠️  Disk space low (12.5 GB free)
     → Run /backup-cleanup to free space

  ℹ️  15 archived files older than retention policy
     → Run /backup-cleanup --preview to review

Health Score: 85/100 (Good)
```

### Options

| Flag | Description | Example |
|------|-------------|---------|
| `--json` | Output as JSON | `--json` |
| `--verbose` | Detailed component status | `--verbose` |
| `--check COMPONENT` | Check specific component | `--check daemon` |
| `--warnings-only` | Show only warnings | `--warnings-only` |
| `--refresh` | Force refresh statistics | `--refresh` |

### Components Checked

1. **Configuration**
   - YAML syntax valid
   - Required fields present
   - Paths exist and accessible

2. **LaunchAgent (Daemon)**
   - Loaded in launchctl
   - Process running
   - Not crashed recently

3. **External Drive**
   - Marker file exists (if enabled)
   - Drive writable
   - Sufficient space

4. **Backup Directory**
   - Directory structure exists
   - Permissions correct
   - Not corrupted

5. **Database Connection**
   - Database file exists
   - SQLite accessible
   - No corruption

6. **Git Integration**
   - Git repository detected
   - Working tree clean
   - No uncommitted critical files

### JSON Output

```bash
/backup-status --json
```

```json
{
  "version": "1.1.0",
  "project": "MyApp",
  "health": {
    "score": 85,
    "status": "good",
    "components": {
      "configuration": {"status": "ok", "message": "Valid"},
      "daemon": {"status": "ok", "message": "Running", "pid": 12345},
      "drive": {"status": "ok", "message": "Connected"},
      "backup_dir": {"status": "ok", "message": "Writable"},
      "disk_space": {"status": "warning", "message": "Low (12.5 GB)", "bytes": 13421772800}
    }
  },
  "statistics": {
    "databases": {"count": 42, "size_bytes": 1288490188},
    "files": {"count": 156, "size_bytes": 884080640},
    "archived": {"count": 89, "size_bytes": 452984832},
    "total_size_bytes": 2625555660
  },
  "last_backup": {
    "timestamp": 1735059000,
    "time_ago": "45 minutes ago",
    "files_backed_up": 12,
    "database_backed_up": true
  },
  "next_backup": {
    "timestamp": 1735062600,
    "time_until": "15 minutes"
  },
  "warnings": [
    {
      "type": "disk_space",
      "severity": "warning",
      "message": "Disk space low (12.5 GB free)",
      "recommendation": "Run /backup-cleanup to free space"
    }
  ]
}
```

### Examples

**Example 1: Quick health check**
```bash
/backup-status --check daemon
# ✅ Daemon: Running (PID 12345)
```

**Example 2: Show only warnings**
```bash
/backup-status --warnings-only
# ⚠️  Disk space low (12.5 GB free)
# ℹ️  15 archived files older than retention policy
```

**Example 3: Verbose mode**
```bash
/backup-status --verbose
# (Shows detailed logs, process info, file counts per directory, etc.)
```

---

## `/backup-now` - Manual Backup

### Synopsis

```bash
/backup-now [OPTIONS]
```

### Description

Triggers an immediate backup, bypassing the normal scheduling and change detection.

### Default Behavior

```bash
/backup-now
```

**Output:**
```
🔄 Starting manual backup...

[1/4] Verifying drive...
  ✅ Drive connected and writable

[2/4] Backing up database...
  ✅ Database snapshot created (1.2 MB)
  📦 MyApp - 12.24.25 - 14:30.db.gz

[3/4] Backing up files...
  ✅ 12 files backed up
  📁 src/app.py (updated)
  📁 src/config.py (updated)
  📁 .env (critical file)
  ... 9 more files

[4/4] Cleaning up...
  ✅ Removed 3 old database snapshots
  ✅ Removed 7 archived files

✅ Backup completed in 2.3s
   Database: 1 snapshot (1.2 MB)
   Files: 12 files (543 KB)
   Archived: 8 old versions
```

### Options

| Flag | Description | Use Case |
|------|-------------|----------|
| `--force` | Bypass change detection | Force backup even if no changes |
| `--dry-run` | Preview without executing | Test what would be backed up |
| `--db-only` | Database only | Quick database snapshot |
| `--files-only` | Files only | Skip database backup |
| `--no-cleanup` | Skip retention cleanup | Faster backup |
| `--verbose` | Detailed logging | Debugging |
| `--quiet` | Minimal output | Scripting |

### Examples

**Example 1: Force backup (even if no changes)**
```bash
/backup-now --force
```

**Example 2: Preview mode (dry-run)**
```bash
/backup-now --dry-run
```

**Output:**
```
🔍 DRY RUN - No changes will be made

Would backup:
  📦 Database: MyApp.db (changed, 2.3 MB)
  📁 src/app.py (modified)
  📁 .env (critical file)
  📁 credentials.json (critical file)

Would archive:
  🗄️  src/app.py.20251223_143000 (old version)

Would clean up:
  🗑️  2 database snapshots (older than 30 days)
  🗑️  5 archived files (older than 60 days)

Estimated space used: 2.5 MB
```

**Example 3: Database only**
```bash
/backup-now --db-only
# ✅ Database snapshot created (1.2 MB)
```

**Example 4: Quiet mode for scripts**
```bash
/backup-now --quiet && echo "Backup OK" || echo "Backup failed"
```

### Concurrency Handling

If another backup is running:

```bash
/backup-now
```

**Output:**
```
⏸️  Another backup is currently running (PID 12345)
   Started: 30 seconds ago

Options:
  - Wait and retry automatically
  - Cancel this backup attempt

Choose [w/c]: w

⏳ Waiting for backup to complete...
✅ Previous backup completed
🔄 Starting manual backup...
[continues normally...]
```

---

## `/backup-restore` - Restore Wizard

### Synopsis

```bash
/backup-restore [OPTIONS]
```

### Interactive Wizard (Default)

```bash
/backup-restore
```

**Session:**

```
┌─────────────────────────────────────────┐
│ Checkpoint - Restore   │
│ MyApp                                   │
└─────────────────────────────────────────┘

⚠️  WARNING: This will replace current data
   Creating safety backup first...
   ✅ Safety backup: backups/.pre-restore-20251224-143000/

Restore Type
━━━━━━━━━━━━
  1) Database
  2) File(s)
  3) Full project restore

Choose [1-3]: 1

Database Restore
━━━━━━━━━━━━━━━━
Available snapshots:

  1) MyApp - 12.24.25 - 14:30.db.gz (1.2 MB) [30 min ago]
  2) MyApp - 12.24.25 - 13:30.db.gz (1.2 MB) [1 hour ago]
  3) MyApp - 12.24.25 - 12:30.db.gz (1.2 MB) [2 hours ago]
  4) MyApp - 12.23.25 - 18:45.db.gz (1.1 MB) [1 day ago]
  ... 38 more

Choose snapshot [1-42]: 2

Confirm Restore
━━━━━━━━━━━━━━━
  Source: MyApp - 12.24.25 - 13:30.db.gz
  Target: /Users/me/.myapp/data.db
  Current size: 2.3 MB
  Restore size: 1.2 MB

  ⚠️  This will REPLACE your current database

Proceed? [y/N]: y

🔄 Restoring database...
  ✅ Decompressing snapshot
  ✅ Verifying integrity
  ✅ Replacing database
  ✅ Restore completed

✅ Database restored successfully
   From: 13:30 snapshot (1 hour ago)
   Safety backup: backups/.pre-restore-20251224-143000/
```

### Direct Restore Mode

```bash
# Restore specific database
/backup-restore --database "12.24.25 - 13:30"

# Restore specific file
/backup-restore --file src/app.py

# Restore file to specific version
/backup-restore --file src/app.py --version 20251223_143000

# List available backups
/backup-restore --list
```

### Options

| Flag | Description | Example |
|------|-------------|---------|
| `--database` | Restore database by timestamp | `--database "12.24.25 - 13:30"` |
| `--file` | Restore specific file | `--file src/app.py` |
| `--version` | Specific archived version | `--version 20251223_143000` |
| `--list` | List available backups | `--list` |
| `--no-backup` | Skip pre-restore backup | `--no-backup` (dangerous) |
| `--force` | No confirmation prompt | `--force` (scripting) |

### Examples

**Example 1: List available database backups**
```bash
/backup-restore --list --database
```

**Example 2: Restore latest database**
```bash
/backup-restore --database latest
```

**Example 3: Restore file to specific version**
```bash
/backup-restore --file .env --version 20251223_120000
```

**Example 4: Full project restore**
```bash
/backup-restore --full --from "12.23.25 - 18:45"
```

### Safety Features

1. **Pre-restore Backup**
   - Automatic safety backup before restore
   - Stored in `backups/.pre-restore-TIMESTAMP/`
   - Can be disabled with `--no-backup`

2. **Integrity Verification**
   - Decompression validation
   - File size checks
   - Database integrity test (SQLite)

3. **Rollback Capability**
   - If restore fails, original restored automatically
   - Safety backup preserved for manual rollback

---

## `/backup-cleanup` - Space Management

### Synopsis

```bash
/backup-cleanup [OPTIONS]
```

### Default Behavior (Preview Mode)

```bash
/backup-cleanup
```

**Output:**

```
┌─────────────────────────────────────────────────────┐
│ Checkpoint - Cleanup Preview       │
│ MyApp                                               │
└─────────────────────────────────────────────────────┘

Current Usage
━━━━━━━━━━━━━
  Databases: 42 snapshots (1.2 GB)
  Archived Files: 89 versions (432 MB)
  Total: 2.5 GB

Retention Policy
━━━━━━━━━━━━━━━━
  Database: Keep 30 days
  Files: Keep 60 days

Cleanup Preview
━━━━━━━━━━━━━━━

Database Snapshots to Remove (older than 30 days):
  🗑️  MyApp - 11.20.25 - 14:30.db.gz (1.1 MB)
  🗑️  MyApp - 11.19.25 - 16:20.db.gz (1.1 MB)
  🗑️  MyApp - 11.18.25 - 09:15.db.gz (1.0 MB)
  ... 5 more (8 total)

Archived Files to Remove (older than 60 days):
  🗑️  src/app.py.20251020_143000 (12 KB)
  🗑️  .env.20251019_120000 (456 bytes)
  🗑️  config.json.20251018_160000 (2.1 KB)
  ... 12 more (15 total)

Space to Reclaim: 9.2 MB
  Databases: 8.4 MB (8 files)
  Archived: 821 KB (15 files)

Recommendations
━━━━━━━━━━━━━━━
  ℹ️  Consider reducing database retention from 30 to 21 days
     Would free an additional 12.5 MB (10 snapshots)

  ℹ️  3 large archived files detected:
     - src/data/large_export.csv.20251201_100000 (45 MB)
     - src/assets/video.mp4.20251128_140000 (120 MB)
     - Consider excluding large files from backups

To execute cleanup:
  /backup-cleanup --execute
```

### Execute Mode

```bash
/backup-cleanup --execute
```

**Output:**
```
🗑️  Cleaning up old backups...

[1/2] Removing old database snapshots...
  ✅ Removed 8 snapshots (8.4 MB freed)

[2/2] Removing old archived files...
  ✅ Removed 15 archived files (821 KB freed)

✅ Cleanup completed
   Space freed: 9.2 MB
   Databases removed: 8
   Files removed: 15
```

### Options

| Flag | Description | Example |
|------|-------------|---------|
| `--preview` | Preview mode (default) | `--preview` |
| `--execute` | Execute cleanup | `--execute` |
| `--force` | No confirmation | `--force` |
| `--recommend` | Show recommendations only | `--recommend` |
| `--age DAYS` | Custom age threshold | `--age 90` |
| `--size SIZE` | Free specific amount | `--size 100MB` |

### Examples

**Example 1: Preview cleanup**
```bash
/backup-cleanup
# (Shows preview, no changes)
```

**Example 2: Execute with confirmation**
```bash
/backup-cleanup --execute
# Proceed with cleanup? [y/N]: y
```

**Example 3: Force cleanup (no prompt)**
```bash
/backup-cleanup --execute --force
```

**Example 4: Custom retention**
```bash
/backup-cleanup --execute --age 90
# Remove files older than 90 days (override config)
```

**Example 5: Free specific amount**
```bash
/backup-cleanup --execute --size 500MB
# Remove oldest files until 500MB freed
```

**Example 6: Recommendations only**
```bash
/backup-cleanup --recommend
```

**Output:**
```
Recommendations
━━━━━━━━━━━━━━━
  ℹ️  Reduce database retention: 30d → 21d (saves 12.5 MB)
  ℹ️  Exclude large files: *.mp4, *.csv (saves 165 MB)
  ℹ️  Enable compression for archived files (saves ~60%)
```

### Smart Cleanup Strategies

1. **Age-based** (default)
   - Respects retention policies
   - Removes oldest first

2. **Size-based**
   - Removes largest files first
   - Useful for emergency space recovery

3. **Hybrid**
   - Removes old + large files
   - Balanced approach

---

## `/backup-update` - System Updates

### Synopsis

```bash
/backup-update [OPTIONS]
```

### Description

Check for and install Checkpoint updates from GitHub releases. Supports both global and per-project installations.

### Default Behavior

```bash
/backup-update
```

**Output:**
```
🔍 Checking for updates...

Current version: v2.2.0
Latest version: v2.3.0

ℹ  Update available!

Changelog:
  - Universal database support (PostgreSQL, MySQL, MongoDB)
  - Streamlined installation wizard
  - Auto-update notifications

📥 Downloading update...
✓ Downloaded Checkpoint-v2.3.0.tar.gz (2.3 MB)

📦 Installing update...
✓ Extracted files
✓ Updated binaries
✓ Reloaded LaunchAgent

✅ Successfully updated to v2.3.0

To verify: /checkpoint --status
```

### Options

| Flag | Description | Example |
|------|-------------|---------|
| `--check-only` | Check without installing | `--check-only` |
| `--force` | Skip confirmation prompts | `--force` |

### Examples

**Example 1: Check for updates**
```bash
/backup-update --check-only
```

**Output:**
```
✓ You're running the latest version: v2.2.0
```

**Example 2: Force update without prompts**
```bash
/backup-update --force
```

### Update Process

1. Checks GitHub for latest release
2. Compares with current version
3. Downloads release archive
4. Backs up current installation
5. Extracts and installs update
6. Reloads LaunchAgent if needed
7. Verifies installation

---

## `/backup-pause` - Pause/Resume

### Synopsis

```bash
/backup-pause [OPTIONS]
```

### Description

Temporarily pause or resume automatic backups. Manual backups with `/backup-now` still work when paused.

### Default Behavior (Pause)

```bash
/backup-pause
```

**Output:**
```
⏸️  Pausing automatic backups...

✓ LaunchAgent unloaded
✓ Pause state saved

Automatic backups are now paused.
Manual backups still available: /backup-now

To resume: /backup-pause --resume
```

### Resume Backups

```bash
/backup-pause --resume
```

**Output:**
```
▶️  Resuming automatic backups...

✓ LaunchAgent loaded
✓ Pause state cleared

Automatic backups resumed.
Next backup: in ~5 minutes
```

### Check Status

```bash
/backup-pause --status
```

**Output:**
```
Status: ⏸️  PAUSED

Automatic backups paused since: 2025-12-25 14:30
Paused for: 2 hours 15 minutes

To resume: /backup-pause --resume
```

### Options

| Flag | Description | Example |
|------|-------------|---------|
| `--resume` | Resume automatic backups | `/backup-pause --resume` |
| `--status` | Show current pause status | `/backup-pause --status` |

### Examples

**Example 1: Pause during heavy work**
```bash
/backup-pause
# Do intensive work without hourly backups...
/backup-pause --resume
```

**Example 2: Check if paused**
```bash
/backup-pause --status
```

---

## `/uninstall` - Uninstall Checkpoint

### Synopsis

```bash
/uninstall [OPTIONS]
```

### Description

Safely uninstall Checkpoint from your system. Removes binaries, LaunchAgents, and optionally backup files.

### Default Behavior

```bash
/uninstall
```

**Session:**
```
⚠️  This will uninstall Checkpoint

The following will be removed:
  - LaunchAgent (~/Library/LaunchAgents/com.checkpoint.backup.plist)
  - Global commands (/usr/local/bin/backup-*)
  - Skills (.claude/skills/*)

The following will be kept:
  - Backup files (backups/)
  - Configuration (.backup-config.yaml)

Proceed? [y/N]: y

🗑️  Uninstalling Checkpoint...

[1/3] Stopping LaunchAgent...
  ✓ Unloaded com.checkpoint.backup

[2/3] Removing binaries...
  ✓ Removed /usr/local/bin/backup-config
  ✓ Removed /usr/local/bin/backup-status
  ✓ Removed /usr/local/bin/backup-now
  ... (8 more)

[3/3] Removing skills...
  ✓ Removed .claude/skills/checkpoint
  ✓ Removed .claude/skills/backup-*
  ... (10 more)

✅ Checkpoint uninstalled successfully

Your backups are preserved in: backups/
To reinstall: ./bin/install.sh
```

### Complete Removal (Including Backups)

```bash
/uninstall --no-keep-backups
```

**Warning:**
```
⚠️  WARNING: This will DELETE all backup files!

The following will be PERMANENTLY DELETED:
  - backups/ (2.5 GB, 156 files)
  - .backup-config.yaml

This action CANNOT be undone!

Type 'DELETE' to confirm: DELETE

🗑️  Removing everything...
[continues...]
```

### Options

| Flag | Description | Example |
|------|-------------|---------|
| `--keep-backups` | Keep backup files (default) | `--keep-backups` |
| `--no-keep-backups` | Delete all backups | `--no-keep-backups` |
| `--force` | Skip confirmation prompts | `--force` |

### Examples

**Example 1: Uninstall but keep backups**
```bash
/uninstall
```

**Example 2: Complete removal**
```bash
/uninstall --no-keep-backups
```

**Example 3: Force uninstall (scripting)**
```bash
/uninstall --force
```

### What Gets Removed

**Always Removed:**
- LaunchAgent plist files
- Global commands in /usr/local/bin
- Claude Code skills
- Shell integrations

**Kept by Default:**
- Backup files (backups/)
- Configuration files (.backup-config.yaml)
- Database snapshots

**Removed with `--no-keep-backups`:**
- All backup files
- All configuration files
- Database snapshots
- Archived files

---

## Configuration Schema

### YAML Structure

```yaml
# .backup-config.yaml

project:
  name: "MyApp"
  directory: "/Volumes/Drive/MyApp"

backup:
  directory: "/Volumes/Drive/MyApp/backups"

  # Scheduling
  interval: 3600  # 1 hour (seconds)
  session_idle_threshold: 600  # 10 minutes

  # Critical files (even if gitignored)
  critical_files:
    env_files: true
    credentials: true
    ide_settings: false
    local_notes: false
    local_databases: false

database:
  enabled: true
  type: "sqlite"  # sqlite | postgresql | mysql | none
  path: "/Users/me/.myapp/data.db"

  # Advanced
  compression: true
  backup_method: "copy"  # copy | dump

retention:
  database_days: 30
  file_days: 60

  # Advanced
  keep_minimum: 3  # Always keep at least 3 backups
  size_limit: "10GB"  # Max total backup size

drive:
  verification_enabled: true
  marker_file: "/Volumes/Drive/MyApp/.backup-drive-marker"

  # Graceful degradation
  fallback_enabled: true
  fallback_location: "~/.claudecode-backups/fallback"

git:
  auto_commit: false
  commit_message: "Auto-backup: {timestamp}"
  auto_push: false

notifications:
  enabled: false
  methods: ["terminal", "macos"]  # terminal | macos | email
  on_success: false
  on_failure: true

logging:
  level: "info"  # debug | info | warning | error
  file: "{backup_dir}/backup.log"
  max_size: "10MB"
  rotate: true
```

### Validation Rules

1. **Required Fields**
   - `project.name`
   - `project.directory`
   - `backup.directory`

2. **Path Validation**
   - All paths must be absolute
   - Parent directories must exist
   - Write permissions required

3. **Type Validation**
   - Booleans: `true` / `false`
   - Integers: No decimals
   - Paths: Must start with `/` or `~`

4. **Range Validation**
   - `retention.*_days`: 1-365
   - `backup.interval`: 300-86400 (5 min - 24 hours)

### Migration from Bash Config

Automatic migration:

```bash
/backup-config --migrate
```

**Process:**
1. Reads `.backup-config.sh`
2. Converts to YAML format
3. Validates new config
4. Backs up old config (`.backup-config.sh.backup`)
5. Writes `.backup-config.yaml`

**Compatibility:**
- Both formats supported
- YAML takes precedence if both exist
- Bash config deprecated in v2.0

---

## Use Case Examples

### Use Case 1: New Project Setup

```bash
# Step 1: Run wizard
/backup-config wizard

# Step 2: Verify configuration
/backup-status

# Step 3: Test backup
/backup-now --dry-run

# Step 4: Execute first backup
/backup-now

# Step 5: Verify
/backup-status
```

### Use Case 2: Emergency Restore

```bash
# Check what's available
/backup-restore --list

# Restore database
/backup-restore --database latest

# Restore critical file
/backup-restore --file .env --version latest
```

### Use Case 3: Disk Space Management

```bash
# Preview cleanup
/backup-cleanup

# Get recommendations
/backup-cleanup --recommend

# Execute cleanup
/backup-cleanup --execute

# Verify space freed
/backup-status
```

### Use Case 4: Configuration Update

```bash
# Edit interactively
/backup-config

# Or set specific values
/backup-config --set retention.database_days=90

# Validate
/backup-config --validate

# Test
/backup-status --check configuration
```

### Use Case 5: Migration from v1.0

```bash
# Migrate configuration
/backup-config --migrate

# Verify
/backup-config --validate

# Test
/backup-now --dry-run

# Check status
/backup-status
```

### Use Case 6: Scheduled Maintenance

```bash
#!/bin/bash
# Weekly maintenance script

# Check health
/backup-status --warnings-only

# Cleanup old backups
/backup-cleanup --execute --force

# Force full backup
/backup-now --force

# Send summary
/backup-status --json > backup-report.json
```

---

## Troubleshooting

### Common Issues

#### Issue: Command not found

**Symptom:**
```bash
/backup-config
# -bash: /backup-config: No such file or directory
```

**Solution:**
```bash
# Check installation
which backup-config

# Reinstall if needed
cd /path/to/Checkpoint
./bin/install.sh
```

#### Issue: Configuration validation fails

**Symptom:**
```bash
/backup-config --validate
# ❌ Validation failed: project.directory does not exist
```

**Solution:**
```bash
# Check path
/backup-config --get project.directory

# Fix path
/backup-config --set project.directory=/correct/path

# Validate again
/backup-config --validate
```

#### Issue: Backup fails with "Drive not found"

**Symptom:**
```bash
/backup-now
# ❌ Drive verification failed: Marker file not found
```

**Solution:**
```bash
# Check marker file
ls -la $(backup-config --get drive.marker_file)

# Create marker
touch /Volumes/Drive/.backup-drive-marker

# Or disable verification
/backup-config --set drive.verification_enabled=false
```

#### Issue: Restore shows no backups

**Symptom:**
```bash
/backup-restore --list
# No backups found
```

**Solution:**
```bash
# Check backup directory
/backup-config --get backup.directory
ls -la /path/to/backups

# Verify backups exist
find /path/to/backups -name "*.db.gz"
find /path/to/backups/archived -type f
```

#### Issue: Cleanup removes nothing

**Symptom:**
```bash
/backup-cleanup --execute
# No files to remove
```

**Solution:**
```bash
# Check retention policy
/backup-config --get retention

# Preview with custom age
/backup-cleanup --age 7  # Show files older than 7 days
```

### Debugging

**Enable verbose logging:**

```bash
/backup-config --set logging.level=debug
```

**Check logs:**

```bash
tail -f $(backup-config --get logging.file)
```

**Test individual components:**

```bash
/backup-status --check daemon
/backup-status --check drive
/backup-status --check configuration
```

### Getting Help

**View command help:**
```bash
/backup-config --help
/backup-status --help
/backup-now --help
/backup-restore --help
/backup-cleanup --help
```

**Check version:**
```bash
/backup-status --version
```

**Report issues:**
Include in bug report:
- Output of `/backup-status --json`
- Relevant logs from `backup.log`
- Your configuration (`/backup-config --get`)
- Command that failed with full output

---

## Quick Reference

### Configuration
```bash
/backup-config wizard          # Setup wizard
/backup-config                 # Edit config
/backup-config --get KEY       # Get value
/backup-config --set KEY=VAL   # Set value
/backup-config --validate      # Validate config
/backup-config --migrate       # Migrate from v1.0
```

### Status & Health
```bash
/backup-status                 # Full dashboard
/backup-status --json          # JSON output
/backup-status --check COMP    # Check component
/backup-status --warnings-only # Warnings only
```

### Manual Backup
```bash
/backup-now                    # Normal backup
/backup-now --force            # Force backup
/backup-now --dry-run          # Preview mode
/backup-now --db-only          # Database only
/backup-now --files-only       # Files only
```

### Restore
```bash
/backup-restore                # Interactive wizard
/backup-restore --list         # List backups
/backup-restore --database     # Restore database
/backup-restore --file PATH    # Restore file
```

### Cleanup
```bash
/backup-cleanup                # Preview mode
/backup-cleanup --execute      # Execute cleanup
/backup-cleanup --recommend    # Show recommendations
/backup-cleanup --size 100MB   # Free 100MB
```

---

**Version:** 2.2.0
**Last Updated:** 2025-12-25
