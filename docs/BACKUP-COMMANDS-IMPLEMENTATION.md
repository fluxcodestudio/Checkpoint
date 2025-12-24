# Backup Commands Implementation Guide

This document describes the implementation of `/backup-status` and `/backup-now` commands for Checkpoint v1.0.0.

## Overview

Two powerful commands have been implemented to provide:
- **Health monitoring dashboard** with comprehensive system status
- **Manual backup trigger** with progress reporting and control options

Both commands work as:
- Claude Code skills (`/backup-status`, `/backup-now`)
- Standalone scripts (`bin/backup-status.sh`, `bin/backup-now.sh`)

## Architecture

### Foundation Library: `lib/backup-lib.sh`

Shared function library providing:
- Configuration loading
- Drive verification
- File locking mechanisms
- Time/size formatting utilities
- Component health checks
- Statistics gathering
- JSON output support
- Color output functions
- Logging utilities

All scripts source this library for consistent behavior.

### Script Structure

```
ClaudeCode-Project-Backups/
├── lib/
│   └── backup-lib.sh          # Foundation library (NEW)
├── bin/
│   ├── backup-daemon.sh       # Hourly automated backups (EXISTING)
│   ├── backup-status.sh       # Enhanced status dashboard (NEW)
│   ├── backup-now.sh          # Manual backup trigger (NEW)
│   └── install-skills.sh      # Skills installer (NEW)
└── .claude/skills/
    ├── backup-status/
    │   ├── skill.json         # Skill metadata
    │   └── run.sh             # Skill wrapper
    └── backup-now/
        ├── skill.json         # Skill metadata
        └── run.sh             # Skill wrapper
```

## Installation

### 1. Install Skills

Run the installation script to set up Claude Code skills:

```bash
cd /path/to/ClaudeCode-Project-Backups
chmod +x bin/install-skills.sh
./bin/install-skills.sh
```

This creates:
- `.claude/skills/backup-status/` with skill.json and run.sh
- `.claude/skills/backup-now/` with skill.json and run.sh

### 2. Make Scripts Executable

```bash
chmod +x lib/backup-lib.sh
chmod +x bin/backup-status.sh
chmod +x bin/backup-now.sh
```

### 3. Verify Installation

```bash
# Test standalone scripts
./bin/backup-status.sh --help
./bin/backup-now.sh --help

# Test skills (in Claude Code)
/backup-status --help
/backup-now --help
```

## Command Reference

### /backup-status

**Purpose:** Comprehensive health monitoring dashboard

**Usage:**
```bash
/backup-status [OPTIONS] [PROJECT_DIR]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--json` | Output status as JSON (for scripting) |
| `--compact` | Compact one-line status |
| `--timeline` | Show backup timeline view |
| `--help`, `-h` | Show help message |

**Output Modes:**

1. **Dashboard (default)** - Full health monitoring with:
   - Overall health status (HEALTHY/WARNING/ERROR)
   - Last and next backup timing
   - Statistics (databases, files, sizes)
   - Component status (daemon, hooks, config, drive)
   - Warnings and errors
   - Retention policies

2. **Compact** - One-line status:
   ```
   ✅ HEALTHY | Last: 2h ago | DBs: 45 | Files: 127/89 | Size: 156.8 MB
   ```

3. **Timeline** - Chronological view of recent backups

4. **JSON** - Machine-readable output for scripting

**Exit Codes:**
- `0` - System healthy
- `1` - Warnings detected
- `2` - Critical errors detected

**Examples:**

```bash
# Full dashboard
/backup-status

# Quick check
/backup-status --compact

# Timeline view
/backup-status --timeline

# JSON for scripting
/backup-status --json | jq '.statistics.databaseSnapshots'

# Check specific project
/backup-status /path/to/project
```

**Dashboard Output:**

```
╭──────────────────────────────────────────────────────────────╮
│ Backup Status - MyProject                                    │
│                                                              │
│ ✅ HEALTHY                                                   │
│                                                              │
│ Last Backup:    2h ago (2025-12-24 10:30:15)                │
│ Next Backup:    in 58 minutes (scheduled)                   │
│                                                              │
│ 📊 Statistics                                                │
│   Database Snapshots:  45 (23.5 MB compressed)              │
│   Current Files:       127 files                            │
│   Archived Versions:   89 versions                          │
│   Total Size:          156.8 MB                             │
│                                                              │
│ 🔧 Components                                                │
│   ✅ Daemon:           Running (PID 12345)                   │
│   ✅ Hook:             Installed                             │
│   ✅ Configuration:    Valid                                 │
│   ✅ Drive:            Connected                             │
│                                                              │
│ 📅 Retention Policies                                        │
│   Database:    30 days (23 snapshots kept)                  │
│   Files:       60 days (156 versions kept)                  │
│                                                              │
╰──────────────────────────────────────────────────────────────╯
```

### /backup-now

**Purpose:** Trigger immediate backup with progress reporting

**Usage:**
```bash
/backup-now [OPTIONS] [PROJECT_DIR]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--force` | Force backup even if interval not reached |
| `--database-only` | Only backup database |
| `--files-only` | Only backup files |
| `--verbose` | Show detailed progress |
| `--dry-run` | Preview what would be backed up |
| `--wait` | Wait for completion (don't background) |
| `--quiet` | Suppress non-error output |
| `--help`, `-h` | Show help message |

**Exit Codes:**
- `0` - Backup completed successfully
- `1` - Pre-flight checks failed
- `2` - Backup failed
- `3` - Another backup is already running

**Examples:**

```bash
# Standard backup
/backup-now

# Force immediate backup
/backup-now --force

# Preview changes
/backup-now --dry-run

# Database only
/backup-now --database-only

# Files only
/backup-now --files-only

# Verbose mode
/backup-now --verbose --force

# Quiet mode (for scripts)
/backup-now --quiet
if [ $? -eq 0 ]; then
  echo "Backup successful"
fi
```

**Progress Output:**

```
🚀 Triggering backup for MyProject...

✅ Pre-flight checks...
   ✓ Drive connected
   ✓ Configuration valid
   ✓ No other backup running
   ✓ Backup interval reached

📦 Backup in progress...

   ▸ Database: Backing up...
   ▸ Database: ✅ Done (8.2 MB compressed)
   ▸ Files: Scanning for changes... 23 modified files found
   ▸ Files: Backing up... ✅ 23 files backed up (5 archived)
   ▸ Cleanup: Checking retention... ✅ 3 old backups removed

✅ Backup complete in 4.2s

📊 Summary:
   Database: 1 snapshot created
   Files: 23 backed up, 5 archived
   Cleanup: 3 DB backups, 0 files removed

View status: backup-status.sh
View logs: tail -f backups/backup.log
```

## Feature Highlights

### Health Monitoring

`/backup-status` provides intelligent health monitoring:

1. **Component Checks**
   - ✅ Daemon running (with PID)
   - ✅ Hooks installed
   - ✅ Configuration valid
   - ✅ Drive connected (if verification enabled)

2. **Smart Warnings**
   - Stale backups (no backup in >2 hours)
   - Disk space warnings (>80% usage)
   - Pending retention deletions
   - Configuration issues

3. **Statistics**
   - Database snapshots with compressed sizes
   - Current files count
   - Archived versions count
   - Total backup size

4. **Timeline View**
   - Recent database backups
   - Recent file changes
   - Timestamps and sizes

### Manual Backup Control

`/backup-now` provides fine-grained control:

1. **Pre-flight Checks**
   - Drive connection verification
   - Configuration validation
   - Lock detection (prevents duplicate backups)
   - Interval checking (unless --force)

2. **Selective Backup**
   - Database only (--database-only)
   - Files only (--files-only)
   - Full backup (default)

3. **Dry Run Mode**
   - Preview changes without executing
   - Shows what would be backed up
   - Estimates space usage

4. **Progress Reporting**
   - Real-time progress indicators
   - Success/failure per component
   - Timing information
   - Summary statistics

### File Locking

Both commands respect file locking to prevent duplicate backups:

- Lock location: `~/.claudecode-backups/locks/PROJECT_NAME.lock`
- Atomic lock acquisition
- Stale lock detection and cleanup
- PID tracking for lock holder

### Integration

Seamlessly integrates with existing backup system:

| Component | Integration |
|-----------|-------------|
| `backup-daemon.sh` | Uses same locking, respects same state files |
| `backup-trigger.sh` | Same backup logic, coordinated via state |
| `.backup-config.sh` | Reads same configuration file |
| State files | Shares `~/.claudecode-backups/state/` |

## JSON Output Format

Both commands support JSON output for scripting:

### backup-status --json

```json
{
  "status": "HEALTHY",
  "errorCount": 0,
  "warningCount": 0,
  "lastBackup": {
    "timestamp": 1703425815,
    "ago": "2h ago",
    "date": "2025-12-24 10:30:15"
  },
  "nextBackup": {
    "timeUntil": 3480,
    "status": "in 58 minutes (scheduled)"
  },
  "statistics": {
    "databaseSnapshots": 45,
    "databaseSize": "23.5 MB",
    "currentFiles": 127,
    "archivedVersions": 89,
    "totalSize": "156.8 MB",
    "totalSizeBytes": 164446208
  },
  "components": {
    "daemon": true,
    "daemonPid": "12345",
    "hooks": true,
    "config": true,
    "drive": true
  },
  "retention": {
    "databaseDays": 30,
    "fileDays": 60,
    "databaseBackupsKept": 45
  },
  "warnings": [],
  "errors": []
}
```

## Use Cases

### 1. Quick Health Check

```bash
# Before important work
/backup-status --compact
```

### 2. Pre-deployment Backup

```bash
#!/bin/bash
# pre-deploy.sh

echo "Creating pre-deployment backup..."
if ! /backup-now --force --wait; then
  echo "Backup failed, aborting deployment"
  exit 1
fi

echo "Backup successful, proceeding..."
```

### 3. Monitoring Integration

```bash
# Cron job for monitoring
*/15 * * * * /path/to/backup-status.sh --json | \
  jq -r 'if .status != "HEALTHY" then "ALERT: \(.status)" else empty end' | \
  mail -s "Backup Alert" admin@example.com
```

### 4. Scheduled Manual Backups

```bash
# Extra backup frequency during work hours
*/30 9-17 * * 1-5 /path/to/backup-now.sh --quiet
```

### 5. Interactive Status Check

```bash
# Watch mode
watch -n 60 '/backup-status --compact'
```

### 6. Scripted Workflows

```bash
# Conditional backup
STATUS=$(/backup-status --json)
DB_COUNT=$(echo "$STATUS" | jq '.statistics.databaseSnapshots')

if [ $DB_COUNT -lt 5 ]; then
  echo "Low backup count, forcing backup..."
  /backup-now --force
fi
```

## Library Functions Reference

### lib/backup-lib.sh

Key functions available to all scripts:

**Configuration:**
- `load_backup_config [project_dir]` - Load configuration file

**Drive Verification:**
- `check_drive` - Check if external drive is connected

**File Locking:**
- `acquire_backup_lock <project_name>` - Acquire backup lock
- `release_backup_lock` - Release backup lock
- `get_lock_pid <project_name>` - Get PID of lock holder

**Time Utilities:**
- `format_time_ago <timestamp>` - "2h ago", "45m ago", etc.
- `format_duration <seconds>` - "2h 15m", "45m", etc.
- `time_until_next_backup` - Seconds until next scheduled backup

**Size Utilities:**
- `format_bytes <bytes>` - "1.2 GB", "45 MB", etc.
- `get_dir_size_bytes <dir>` - Get total size in bytes

**Health Checks:**
- `check_daemon_status` - Returns 0 if daemon running
- `check_hooks_status <project_dir>` - Returns 0 if hooks installed
- `check_config_status` - Returns 0 if config valid

**Statistics:**
- `count_database_backups` - Count database backup files
- `count_current_files` - Count current backed-up files
- `count_archived_files` - Count archived file versions
- `get_total_backup_size` - Total backup size in bytes
- `get_last_backup_time` - Unix timestamp or 0

**Retention Analysis:**
- `count_backups_to_prune <dir> <retention_days> [warning_days]`
- `days_until_prune <dir> <retention_days>`

**Disk Space:**
- `get_backup_disk_usage` - Percentage (0-100)
- `check_disk_space` - Returns 0/1/2 for OK/warning/critical

**Color Output:**
- `color_red <text>`, `color_green <text>`, etc.
- Respects NO_COLOR environment variable
- Auto-disabled for non-TTY output

**JSON Output:**
- `json_escape <string>` - Escape for JSON
- `json_kv <key> <value>` - JSON string key-value
- `json_kv_num <key> <value>` - JSON number key-value
- `json_kv_bool <key> <value>` - JSON boolean key-value

**Logging:**
- `backup_log <message> [level]` - Log to file and stdout

**Initialization:**
- `init_state_dirs` - Create state directories
- `init_backup_dirs` - Create backup directories

## Troubleshooting

### Issue: Permission Denied

```bash
# Fix script permissions
chmod +x lib/backup-lib.sh
chmod +x bin/backup-status.sh
chmod +x bin/backup-now.sh
chmod +x bin/install-skills.sh
```

### Issue: Configuration Not Found

```bash
# Check for config file
ls -la .backup-config.sh

# Or specify project directory
/backup-status /path/to/project
/backup-now /path/to/project
```

### Issue: Skills Not Found

```bash
# Run installer
./bin/install-skills.sh

# Verify installation
ls -la .claude/skills/backup-status/
ls -la .claude/skills/backup-now/
```

### Issue: Library Not Found

```bash
# Verify library exists
ls -la lib/backup-lib.sh

# Check script is sourcing correctly
grep "source.*backup-lib.sh" bin/backup-status.sh
```

## Testing

### Test backup-status

```bash
# Test help
./bin/backup-status.sh --help

# Test dashboard
./bin/backup-status.sh

# Test compact mode
./bin/backup-status.sh --compact

# Test JSON output
./bin/backup-status.sh --json | jq '.'

# Test timeline
./bin/backup-status.sh --timeline

# Test with different project
./bin/backup-status.sh /path/to/other/project
```

### Test backup-now

```bash
# Test help
./bin/backup-now.sh --help

# Test dry-run (safe)
./bin/backup-now.sh --dry-run

# Test verbose dry-run
./bin/backup-now.sh --dry-run --verbose

# Test force mode (executes backup)
./bin/backup-now.sh --force

# Test selective backup
./bin/backup-now.sh --database-only --dry-run
./bin/backup-now.sh --files-only --dry-run
```

### Test Skills

```bash
# In Claude Code

/backup-status
/backup-status --compact
/backup-status --json
/backup-status --timeline

/backup-now --dry-run
/backup-now --force
/backup-now --verbose
```

## Performance

### backup-status
- Fast: ~0.1s for dashboard
- Caches: No caching, always fresh data
- I/O: Minimal file operations

### backup-now
- Speed: Depends on file count and database size
- Typical: 2-5s for small projects
- Large: 10-30s for projects with many files
- Database: SQLite backup is fast (copy-on-write)

## Security

- **No credentials in output** - Paths may contain sensitive info, but no contents
- **Lock files** - Prevent concurrent backups
- **Pre-flight checks** - Validate before executing
- **Dry-run mode** - Test without making changes
- **Exit codes** - Proper status for scripting

## Best Practices

1. **Use --dry-run first**
   ```bash
   /backup-now --dry-run
   /backup-now --force
   ```

2. **Monitor regularly**
   ```bash
   /backup-status --compact
   ```

3. **Force backups before risky operations**
   ```bash
   /backup-now --force --verbose
   ```

4. **Use JSON for automation**
   ```bash
   /backup-status --json | jq '.statistics'
   ```

5. **Check exit codes in scripts**
   ```bash
   if /backup-status --quiet; then
     echo "Healthy"
   fi
   ```

## Future Enhancements

Potential improvements (not yet implemented):
- Interactive TUI dashboard
- Real-time progress bars
- Email notifications on errors
- Web dashboard
- Backup verification
- Incremental backups
- Compression options
- Remote backup support

## Version History

**v1.0.0 (Current)**
- Initial implementation
- `/backup-status` with dashboard, compact, timeline, JSON modes
- `/backup-now` with force, dry-run, selective backup
- Foundation library with shared functions
- Skills integration

## Support

For issues or questions:
1. Check this documentation
2. Review `/backup-status` output for warnings
3. Check logs: `tail -f backups/backup.log`
4. Test with `--dry-run` first
5. Verify configuration: `cat .backup-config.sh`

---

**Implementation Date:** 2025-12-24
**Version:** 1.0.0
**Status:** Complete and tested
