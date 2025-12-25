# Migration Guide: v1.0.x → v1.1.0

Guide for upgrading from Checkpoint v1.0.x to v1.1.0.

---

## Table of Contents

- [Overview](#overview)
- [What's New in v1.1.0](#whats-new-in-v110)
- [Breaking Changes](#breaking-changes)
- [Migration Process](#migration-process)
- [Configuration Changes](#configuration-changes)
- [Command Migration](#command-migration)
- [Rollback Instructions](#rollback-instructions)
- [FAQ](#faq)

---

## Overview

**Version 1.1.0** introduces a comprehensive command system and modern YAML configuration while maintaining full backward compatibility with v1.0.x installations.

### Key Changes

- **New:** Command system (`/backup-config`, `/backup-status`, etc.)
- **New:** YAML configuration format
- **New:** Foundation library (`lib/backup-lib.sh`)
- **Enhanced:** Status monitoring and health checks
- **Improved:** Error messages and help text

### Compatibility

✅ **Backward Compatible**
- Existing `.backup-config.sh` files continue to work
- All v1.0.x scripts and workflows unchanged
- LaunchAgents and hooks compatible
- Backup data format unchanged

⚠️ **Deprecation Notice**
- Bash config (`.backup-config.sh`) deprecated in v2.0
- Migrate to YAML for future features
- Both formats supported in v1.1.x

---

## What's New in v1.1.0

### 1. Command System

**Before (v1.0.x):**
```bash
# Check status
/path/to/Checkpoint/bin/status.sh

# Trigger backup
./.claude/backup-daemon.sh

# Restore
/path/to/Checkpoint/bin/restore.sh
```

**After (v1.1.0):**
```bash
# Check status
/backup-status

# Trigger backup
/backup-now

# Restore
/backup-restore

# New: Configure
/backup-config

# New: Cleanup
/backup-cleanup
```

### 2. YAML Configuration

**Before (v1.0.x):**
```bash
# .backup-config.sh
PROJECT_NAME="MyApp"
PROJECT_DIR="/path/to/project"
DB_PATH="/path/to/db.db"
DB_RETENTION_DAYS=30
FILE_RETENTION_DAYS=60
```

**After (v1.1.0):**
```yaml
# .backup-config.yaml
project:
  name: "MyApp"
  directory: "/path/to/project"

database:
  enabled: true
  path: "/path/to/db.db"

retention:
  database_days: 30
  file_days: 60
```

### 3. Enhanced Status Dashboard

**v1.0.x:** Basic text output
**v1.1.0:** Rich dashboard with health scoring, warnings, and recommendations

### 4. Foundation Library

**New:** Shared utilities in `lib/backup-lib.sh`
- YAML parsing
- Configuration validation
- Common helper functions
- Reusable across commands

---

## Breaking Changes

### None

**v1.1.0 has ZERO breaking changes** for existing installations.

Your v1.0.x installation will continue working without modification.

### Deprecation Warnings

When using `.backup-config.sh` with v1.1.0:

```bash
/backup-status
```

**Output:**
```
⚠️  Using legacy configuration format (.backup-config.sh)
   Consider migrating to YAML: /backup-config --migrate
   Legacy format will be removed in v2.0
```

**Suppressing Warnings:**

```bash
# Set environment variable
export BACKUP_SUPPRESS_LEGACY_WARNING=1
```

---

## Migration Process

### Option 1: Automatic Migration (Recommended)

**Step 1: Backup current configuration**
```bash
cd /path/to/your/project
cp .backup-config.sh .backup-config.sh.manual-backup
```

**Step 2: Run migration command**
```bash
/backup-config --migrate
```

**Output:**
```
🔄 Migrating configuration...

Reading: .backup-config.sh
  ✅ 15 settings loaded

Converting to YAML format
  ✅ Schema validated
  ✅ Paths verified

Backing up old config
  ✅ .backup-config.sh → .backup-config.sh.backup

Writing new config
  ✅ .backup-config.yaml created

Validation
  ✅ Configuration valid
  ✅ All paths accessible
  ✅ Permissions correct

✅ Migration completed successfully

Next steps:
  1. Test: /backup-status
  2. Test: /backup-now --dry-run
  3. Remove backup: rm .backup-config.sh.backup
```

**Step 3: Verify migration**
```bash
# Check configuration
/backup-config --validate

# Test backup
/backup-now --dry-run

# Check status
/backup-status
```

**Step 4: Test backup**
```bash
/backup-now --force
```

**Step 5: Cleanup (optional)**
```bash
# After confirming everything works
rm .backup-config.sh.backup
```

### Option 2: Manual Migration

**Step 1: Create YAML template**
```bash
/backup-config --template standard > .backup-config.yaml
```

**Step 2: Edit YAML file**
```bash
nano .backup-config.yaml
# Copy values from .backup-config.sh
```

**Step 3: Validate**
```bash
/backup-config --validate
```

**Step 4: Test**
```bash
/backup-now --dry-run
```

**Step 5: Rename old config**
```bash
mv .backup-config.sh .backup-config.sh.backup
```

### Option 3: Keep Using Bash Config

No action required. v1.1.0 fully supports `.backup-config.sh`.

**Note:** New features may require YAML config.

---

## Configuration Changes

### Field Mapping

| v1.0 Bash Variable | v1.1 YAML Path | Notes |
|-------------------|----------------|-------|
| `PROJECT_NAME` | `project.name` | Same value |
| `PROJECT_DIR` | `project.directory` | Same value |
| `BACKUP_DIR` | `backup.directory` | Same value |
| `DB_PATH` | `database.path` | Same value |
| `DB_TYPE` | `database.type` | Same value |
| `DB_RETENTION_DAYS` | `retention.database_days` | Same value |
| `FILE_RETENTION_DAYS` | `retention.file_days` | Same value |
| `BACKUP_INTERVAL` | `backup.interval` | Same value |
| `SESSION_IDLE_THRESHOLD` | `backup.session_idle_threshold` | Same value |
| `DRIVE_VERIFICATION_ENABLED` | `drive.verification_enabled` | true/false instead of boolean |
| `DRIVE_MARKER_FILE` | `drive.marker_file` | Same value |
| `AUTO_COMMIT_ENABLED` | `git.auto_commit` | true/false instead of boolean |
| `BACKUP_ENV_FILES` | `backup.critical_files.env_files` | Nested structure |
| `BACKUP_CREDENTIALS` | `backup.critical_files.credentials` | Nested structure |
| `BACKUP_IDE_SETTINGS` | `backup.critical_files.ide_settings` | Nested structure |

### New Fields in v1.1

Available in YAML config only:

```yaml
# Advanced retention
retention:
  keep_minimum: 3        # Always keep at least 3 backups
  size_limit: "10GB"     # Max total backup size

# Database compression
database:
  compression: true      # Compress database backups
  backup_method: "copy"  # copy | dump

# Notifications (new feature)
notifications:
  enabled: false
  methods: ["terminal", "macos"]
  on_success: false
  on_failure: true

# Logging configuration
logging:
  level: "info"          # debug | info | warning | error
  max_size: "10MB"
  rotate: true
```

### Example: Complete Migration

**Before (.backup-config.sh):**
```bash
PROJECT_NAME="MyApp"
PROJECT_DIR="/Volumes/Drive/MyApp"
BACKUP_DIR="/Volumes/Drive/MyApp/backups"

DB_PATH="/Users/me/.myapp/data.db"
DB_TYPE="sqlite"

DB_RETENTION_DAYS=30
FILE_RETENTION_DAYS=60

BACKUP_INTERVAL=3600
SESSION_IDLE_THRESHOLD=600

DRIVE_VERIFICATION_ENABLED=true
DRIVE_MARKER_FILE="/Volumes/Drive/.backup-marker"

AUTO_COMMIT_ENABLED=false

BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=false
BACKUP_LOCAL_NOTES=false
BACKUP_LOCAL_DATABASES=false
```

**After (.backup-config.yaml):**
```yaml
project:
  name: "MyApp"
  directory: "/Volumes/Drive/MyApp"

backup:
  directory: "/Volumes/Drive/MyApp/backups"
  interval: 3600
  session_idle_threshold: 600

  critical_files:
    env_files: true
    credentials: true
    ide_settings: false
    local_notes: false
    local_databases: false

database:
  enabled: true
  type: "sqlite"
  path: "/Users/me/.myapp/data.db"
  compression: true

retention:
  database_days: 30
  file_days: 60

drive:
  verification_enabled: true
  marker_file: "/Volumes/Drive/.backup-marker"

git:
  auto_commit: false
```

---

## Command Migration

### Status Checking

**v1.0.x:**
```bash
/path/to/Checkpoint/bin/status.sh
```

**v1.1.0:**
```bash
/backup-status

# Or with options
/backup-status --json
/backup-status --verbose
/backup-status --check daemon
```

### Manual Backup

**v1.0.x:**
```bash
cd /path/to/project
./.claude/backup-daemon.sh
```

**v1.1.0:**
```bash
/backup-now

# Or with options
/backup-now --force
/backup-now --dry-run
/backup-now --db-only
```

### Restore

**v1.0.x:**
```bash
/path/to/Checkpoint/bin/restore.sh
# (Interactive menu)
```

**v1.1.0:**
```bash
/backup-restore

# Or direct mode
/backup-restore --database latest
/backup-restore --file src/app.py
```

### Configuration

**v1.0.x:**
```bash
# Manual editing
nano .backup-config.sh
```

**v1.1.0:**
```bash
# Interactive editor
/backup-config

# Or programmatic
/backup-config --set retention.database_days=90
/backup-config --get project.name
```

### New Commands (v1.1.0 Only)

```bash
# Cleanup
/backup-cleanup

# Config validation
/backup-config --validate

# Config migration
/backup-config --migrate
```

---

## Rollback Instructions

If you need to revert to v1.0.x:

### Method 1: Restore Old Config

```bash
# If you have backup
cp .backup-config.sh.backup .backup-config.sh

# Remove YAML config
rm .backup-config.yaml

# Test
./.claude/backup-daemon.sh
```

### Method 2: Downgrade Installation

```bash
# Checkout v1.0.x
cd /path/to/Checkpoint
git checkout v1.0.1

# Reinstall
cd /path/to/your/project
/path/to/Checkpoint/bin/install.sh
```

**Note:** Your backup data is unchanged and compatible with all versions.

---

## FAQ

### Q: Do I have to migrate?

**A:** No. v1.1.0 fully supports `.backup-config.sh`. Migration is optional but recommended for new features.

### Q: Will my existing backups still work?

**A:** Yes. The backup data format is unchanged. All existing backups are compatible.

### Q: Can I use both config formats?

**A:** Yes, but YAML takes precedence. Not recommended.

### Q: What happens to my LaunchAgent?

**A:** No changes needed. LaunchAgent configuration remains the same.

### Q: Do I need to reinstall?

**A:** Only if you want to use the new commands. The installer will update commands while preserving your configuration.

### Q: Will v1.1.0 change my backup schedule?

**A:** No. All scheduling and intervals remain identical.

### Q: Can I migrate back to bash config?

**A:** Not automatically, but you can manually recreate `.backup-config.sh` and remove `.backup-config.yaml`.

### Q: What if migration fails?

**A:** The original `.backup-config.sh` is backed up to `.backup-config.sh.backup`. Simply restore it:
```bash
cp .backup-config.sh.backup .backup-config.sh
```

### Q: Are there performance differences?

**A:** Minimal. YAML parsing adds ~10ms overhead. Negligible in normal operation.

### Q: Can I use v1.1.0 commands with v1.0.x config?

**A:** Yes. Commands detect and support both formats.

### Q: What about custom modifications to scripts?

**A:** Document customizations before upgrading. Review changes in v1.1.0 and reapply customizations if needed.

---

## Migration Checklist

Use this checklist to ensure successful migration:

### Pre-Migration

- [ ] Backup current configuration: `cp .backup-config.sh .backup-config.sh.manual-backup`
- [ ] Document any custom script modifications
- [ ] Note current backup schedule and retention policies
- [ ] Verify current backups are accessible: `ls -la backups/`
- [ ] Check disk space: `df -h`

### Migration

- [ ] Run migration: `/backup-config --migrate`
- [ ] Review migration output for errors
- [ ] Validate new config: `/backup-config --validate`
- [ ] Compare old and new configs side-by-side

### Testing

- [ ] Check status: `/backup-status`
- [ ] Preview backup: `/backup-now --dry-run`
- [ ] Test actual backup: `/backup-now --force`
- [ ] Verify backup created: `ls -la backups/databases/ backups/files/`
- [ ] Test restore: `/backup-restore --list`
- [ ] Check LaunchAgent: `launchctl list | grep backup`

### Post-Migration

- [ ] Monitor logs for 24 hours: `tail -f backups/backup.log`
- [ ] Confirm scheduled backups running
- [ ] Test drive disconnection (if using external drive)
- [ ] Test Claude Code hook trigger
- [ ] Remove old config backup (if all working): `rm .backup-config.sh.backup`

### Rollback Plan (if needed)

- [ ] Backup location: `.backup-config.sh.manual-backup`
- [ ] Rollback command: `cp .backup-config.sh.manual-backup .backup-config.sh && rm .backup-config.yaml`
- [ ] Test rollback: `./.claude/backup-daemon.sh`

---

## Migration Support

### Debugging Migration Issues

**Enable debug logging:**
```bash
/backup-config --set logging.level=debug --migrate
```

**Check migration errors:**
```bash
cat backups/backup.log | grep ERROR
```

**Validate both configs:**
```bash
# Old format (bash)
bash -n .backup-config.sh

# New format (YAML)
/backup-config --validate
```

### Common Migration Errors

#### Error: "Cannot parse .backup-config.sh"

**Cause:** Syntax error in bash config

**Solution:**
```bash
# Check syntax
bash -n .backup-config.sh

# Fix errors, then retry
/backup-config --migrate
```

#### Error: "Path does not exist"

**Cause:** Configuration references non-existent path

**Solution:**
```bash
# Check paths in config
/backup-config --get database.path

# Create missing directories
mkdir -p /path/to/missing/dir

# Retry migration
/backup-config --migrate
```

#### Error: "Permission denied"

**Cause:** Insufficient permissions for backup directory

**Solution:**
```bash
# Check permissions
ls -la backups/

# Fix permissions
chmod 755 backups/
chmod 644 .backup-config.yaml

# Retry
/backup-config --migrate
```

---

## Version Compatibility Matrix

| Feature | v1.0.0 | v1.0.1 | v1.1.0 |
|---------|--------|--------|--------|
| Bash config (.sh) | ✅ | ✅ | ✅ (deprecated) |
| YAML config (.yaml) | ❌ | ❌ | ✅ |
| Command system | ❌ | ❌ | ✅ |
| Foundation library | ❌ | ❌ | ✅ |
| File locking | ❌ | ✅ | ✅ |
| LaunchAgent | ✅ | ✅ | ✅ |
| Claude Code hooks | ✅ | ✅ | ✅ |
| Drive verification | ✅ | ✅ | ✅ |
| Database backups | ✅ | ✅ | ✅ |
| File archiving | ✅ | ✅ | ✅ |

**Backup Data Compatibility:** All versions use identical backup format. Data is fully interchangeable.

---

## Getting Help

### Before Reporting Issues

1. Check logs: `tail -f backups/backup.log`
2. Run status check: `/backup-status --verbose`
3. Validate config: `/backup-config --validate`
4. Review this migration guide

### Include in Bug Report

- Output of `/backup-status --json`
- Migration command output
- Contents of `.backup-config.sh` (sanitize sensitive data)
- Contents of `.backup-config.yaml` (sanitize sensitive data)
- Relevant log entries from `backups/backup.log`

---

**Version:** 1.1.0
**Last Updated:** 2025-12-24
