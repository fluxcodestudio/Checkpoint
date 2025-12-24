# ClaudeCode Project Backups

**Automated, intelligent backup system for any project** — Built for Claude Code, works everywhere.

Developed from real-world SUPERSTACK usage, battle-tested with 150+ files, database backups, and multi-computer workflows.

---

## Features

### Core Capabilities
- **Organized Backup Structure** — Separate folders for databases, current files, and archived versions
- **Smart Change Detection** — Only backs up modified files, not everything every time
- **Database Snapshots** — Compressed timestamped database backups (SQLite supported)
- **Version Archiving** — When a file changes, old version moves to archive (not deleted)
- **Critical File Coverage** — Backs up .env, credentials, IDE settings, notes (kept out of GitHub)
- **Drive Verification** — Ensures you're backing up to the correct external drive
- **Dual Triggers** — Hourly daemon + first-prompt detection for new sessions
- **Graceful Degradation** — Works even when external drive disconnected

### Backup Structure

```
backups/
├── databases/           # Compressed timestamped snapshots
│   ├── MyApp - 12.23.25 - 10:45.db.gz
│   └── MyApp - 12.23.25 - 14:30.db.gz
├── files/               # Current versions (uncompressed, accessible)
│   ├── src/
│   │   └── app.py
│   ├── .env
│   └── credentials.json
└── archived/            # Old versions (when replaced)
    ├── src/app.py.20251223_104500
    └── .env.20251222_093015
```

**Why this structure?**
- **databases/** — Compressed for space, timestamped for history
- **files/** — Uncompressed so you can open/read them directly
- **archived/** — Old versions preserved when files change

---

## Requirements

### Platform Support
- **macOS** — Full support (LaunchAgent for automatic backups)
- **Linux** — Partial support (manual/cron-based backups, no LaunchAgent)

### Dependencies
| Tool | Required | Purpose | Installation |
|------|----------|---------|--------------|
| `bash` | ✅ Yes | Script execution | Pre-installed on macOS/Linux |
| `git` | ✅ Yes | Change detection | `brew install git` (macOS) |
| `sqlite3` | Conditional | Database backups | `brew install sqlite3` (macOS) |
| `gzip` | ✅ Yes | Compression | Pre-installed on macOS/Linux |
| `launchctl` | macOS only | Daemon scheduling | Pre-installed on macOS |

**Note:** The installer will check for required dependencies and warn if any are missing.

---

## Quick Start

### Installation

```bash
# Download and extract ClaudeCode-Project-Backups
# (via git clone, direct download, or your preferred method)

# Navigate to YOUR project that you want to back up
cd /path/to/your/project

# Run the installer from the backup tool location
/path/to/ClaudeCode-Project-Backups/bin/install.sh
```

The installer will:
1. Ask configuration questions (project name, database path, retention, etc.)
2. Create `.backup-config.sh` in your project
3. Install backup scripts to `.claude/` directory
4. Set up LaunchAgent for hourly backups
5. Configure Claude Code hooks for prompt-triggered backups
6. Run initial backup

### Verification

```bash
# Check status
/path/to/ClaudeCode-Project-Backups/bin/status.sh

# View backups
ls -la backups/databases/
ls -la backups/files/
ls -la backups/archived/
```

---

## Configuration

Installation creates `.backup-config.sh` in your project with all settings:

```bash
# Project
PROJECT_NAME="MyApp"
PROJECT_DIR="/path/to/project"

# Database
DB_PATH="/path/to/database.db"
DB_TYPE="sqlite"  # or "none"

# Retention
DB_RETENTION_DAYS=30      # Keep database backups 30 days
FILE_RETENTION_DAYS=60    # Keep archived files 60 days

# Triggers
BACKUP_INTERVAL=3600           # 1 hour (in seconds)
SESSION_IDLE_THRESHOLD=600     # 10 minutes = new session

# Drive Verification (for external drives)
DRIVE_VERIFICATION_ENABLED=true
DRIVE_MARKER_FILE="/path/to/.backup-drive-marker"

# Optional Features
AUTO_COMMIT_ENABLED=false  # Auto-commit to git after backup

# Critical Files to Backup (even if gitignored)
BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=true
BACKUP_LOCAL_NOTES=true
BACKUP_LOCAL_DATABASES=true
```

Edit this file anytime to change settings.

---

## How It Works

### Dual Trigger System

**1. Hourly Daemon (macOS LaunchAgent)**
- Runs every hour in the background
- Checks if backup needed (change detection)
- Coordinates with prompt triggers to avoid duplicates

**2. Claude Code Hook (First Prompt)**
- Fires on every user prompt
- Detects new session (>10 minutes idle)
- Triggers immediate backup on first prompt
- Then coordinates with hourly daemon

**Coordination:** Shared state file prevents duplicate backups

### Backup Process

1. **Drive Verification** (if enabled)
   - Check if marker file exists
   - Skip if wrong/missing drive

2. **Database Backup** (if changed)
   - Compare size + modification time
   - Create compressed snapshot with timestamp
   - Store in `databases/` folder

3. **File Backup** (changed files only)
   - Get git diff (modified, staged, untracked)
   - Add critical gitignored files (.env, credentials, etc.)
   - For each changed file:
     - If exists in `files/`: Compare content
     - If changed: Move old to `archived/` with timestamp
     - Copy new version to `files/`
     - If new: Copy to `files/`

4. **Cleanup**
   - Remove database backups older than retention
   - Remove archived files older than retention
   - Remove empty directories

5. **Optional: Git Commit** (if enabled)
   - Auto-commit changes to git

### What Gets Backed Up

**Always:**
- Modified tracked files
- Staged files
- Untracked files (not in .gitignore)

**Conditionally (if enabled):**
- .env and .env.* files
- Credentials (*.pem, *.key, credentials.json, secrets.*)
- IDE settings (.vscode/settings.json, .vscode/launch.json)
- Local notes (NOTES.md, TODO.local.md, *.private.md)
- Local databases (*.db, *.sqlite, *.sql)

**Never:**
- Files inside `backups/` directory itself
- Files explicitly in .gitignore (unless in critical file list)

---

## Usage

### Manual Backup

```bash
cd /path/to/your/project
./.claude/backup-daemon.sh
```

### Restore Files

```bash
# Interactive menu
/path/to/ClaudeCode-Project-Backups/bin/restore.sh

# Or specify project
/path/to/ClaudeCode-Project-Backups/bin/restore.sh /path/to/project
```

**Restore options:**
- Database: Choose from timestamped snapshots
- Files: Restore current or specific archived version

### Check Status

```bash
/path/to/ClaudeCode-Project-Backups/bin/status.sh
```

**Shows:**
- Project info and configuration
- Component health
- LaunchAgent status
- Drive status (if verification enabled)
- Backup statistics (counts, sizes, last backup time)
- Recent activity from log
- Health check (warnings for issues)

### Uninstall

```bash
/path/to/ClaudeCode-Project-Backups/bin/uninstall.sh
```

**Removes:**
- Backup scripts
- LaunchAgent
- Configuration

**Keeps:**
- All backup data in `backups/` folder
- Logs

---

## Multi-Computer Workflow

**Scenario:** External drive physically moves between desktop and laptop

**Setup:**
1. Install on both computers: `install.sh` on each machine
2. Enable drive verification on both
3. Same marker file path on both computers
4. Both write to same GitHub repo

**How it works:**
1. Unplug drive from Desktop, plug into Laptop
2. Start Claude Code session on Laptop
3. First prompt triggers backup immediately
4. Hourly backups continue while working
5. Drive verification ensures correct drive
6. Coordination prevents duplicate backups

**Key:** Only one computer connected to drive at a time (physical constraint)

---

## Architecture

### File Structure

```
ClaudeCode-Project-Backups/
├── bin/
│   ├── backup-daemon.sh           # Main backup engine
│   ├── smart-backup-trigger.sh    # Claude Code hook integration
│   ├── install.sh                 # Interactive installer
│   ├── restore.sh                 # Restore utility
│   ├── status.sh                  # Status checker
│   └── uninstall.sh               # Uninstaller
├── templates/
│   ├── backup-config.sh           # Configuration template
│   └── pre-database.sh            # Database safety hook
├── docs/
│   └── INTEGRATION.md             # Integration guide
├── examples/
│   └── sample-config.sh           # Example configurations
└── README.md                      # This file
```

### Project Installation

After running `install.sh`, your project has:

```
your-project/
├── .claude/
│   ├── backup-daemon.sh           # Copy of main daemon
│   └── hooks/
│       ├── backup-trigger.sh      # Prompt trigger
│       └── pre-database.sh        # Safety hook (if DB)
├── .backup-config.sh              # Project-specific config
├── backups/                       # Backup data (gitignored)
│   ├── databases/
│   ├── files/
│   ├── archived/
│   └── backup.log
└── .gitignore                     # Updated with backups/
```

### State Files

**Global (shared across projects):**
```
~/.claudecode-backups/
├── state/
│   ├── .last-backup-time          # Coordination timestamp
│   └── .current-session-time      # Session detection
└── logs/
    └── backup-fallback.log        # Fallback when drive disconnected
```

**Per-Project:**
```
backups/
├── .backup-state                  # Database change tracking
└── backup.log                     # Backup activity log
```

---

## Troubleshooting

### No backups running

**Check status:**
```bash
./bin/status.sh
```

**Common issues:**
- LaunchAgent not loaded: `launchctl load ~/Library/LaunchAgents/com.claudecode.backup.PROJECT.plist`
- Drive not connected (if verification enabled)
- No changes detected (working as designed)

### Backups not triggering on prompt

**Check Claude Code settings:**
```bash
cat ~/.config/claude/settings.json
```

**Should include:**
```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/project/.claude/hooks/backup-trigger.sh",
            "timeout": 1
          }
        ]
      }
    ]
  }
}
```

### Drive verification failing

**Check marker file:**
```bash
ls -la /path/to/.backup-drive-marker
```

**Create if missing:**
```bash
touch /path/to/.backup-drive-marker
```

### Database backups failing

**Check database path:**
```bash
ls -la "$DB_PATH"  # From .backup-config.sh
```

**Check SQLite:**
```bash
sqlite3 "$DB_PATH" ".schema"
```

### Files not being backed up

**Check what changed:**
```bash
cd /path/to/project
git status
git diff
```

**Check critical file patterns:**
```bash
find . -name ".env" -o -name "*.pem"
```

---

## FAQ

**Q: Does this work on Windows/Linux?**
A: Currently macOS only (uses LaunchAgent). Linux support would need systemd timers. PRs welcome.

**Q: What happens if I disconnect the drive mid-backup?**
A: Graceful degradation — logs to fallback location, skips backup, retries next cycle.

**Q: Can I backup to cloud storage?**
A: Not built-in, but you can sync `backups/` folder to Dropbox/iCloud/etc.

**Q: How much space do backups use?**
A: Databases compressed (~90% smaller). Files uncompressed. Archived versions add up over time. Retention policies help.

**Q: Can I use this without Claude Code?**
A: Yes. Just the hourly daemon works standalone. Claude Code hooks are optional.

**Q: What if I have multiple projects?**
A: Install separately in each project. Each gets own config, LaunchAgent, backups.

**Q: How do I restore a file?**
A: Run `restore.sh`, choose "File", enter path, select version (current or archived timestamp).

**Q: Can I change retention policies after installation?**
A: Yes. Edit `.backup-config.sh` in your project, change `DB_RETENTION_DAYS` and `FILE_RETENTION_DAYS`.

**Q: What database types are supported?**
A: Currently SQLite. PostgreSQL/MySQL support would require dump commands.

---

## Credits

**Author:** Jon Rezin
**Developed for:** SUPERSTACK token optimization project
**License:** MIT

Built from real-world usage managing 150+ files, database backups, and multi-computer workflows with external drives.

---

## License

MIT License — see LICENSE file for details
