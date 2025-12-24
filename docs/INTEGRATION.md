# Integration Guide

How to integrate ClaudeCode Project Backups with different workflows and tools.

---

## Table of Contents

- [Claude Code Integration](#claude-code-integration)
- [External Drive Workflows](#external-drive-workflows)
- [Git Integration](#git-integration)
- [Database Integration](#database-integration)
- [Custom Workflows](#custom-workflows)

---

## Claude Code Integration

### Automatic Hook Setup

The installer automatically configures Claude Code hooks in `~/.config/claude/settings.json`:

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

### Manual Hook Configuration

If you have existing hooks, merge the backup trigger:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/existing/hook.sh",
            "timeout": 2
          },
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

**Hook Behavior:**
- Fires on every user prompt
- Detects new session (>10 min idle)
- Triggers backup on first prompt of session
- Runs in background (non-blocking)
- Coordinates with hourly daemon

### Session Detection

**Time-based approach:**
- Tracks last prompt timestamp
- >10 minutes idle = new session
- Immediate backup on first prompt
- Then hourly until next idle period

**Why this works:**
- `/resume` still fires UserPromptSubmit
- PPID changes are unreliable
- Time-based is simple and robust

---

## External Drive Workflows

### Single Computer + External Drive

**Setup:**
```bash
# During install
Enable external drive verification? (y/n) [n]: y
Drive marker file path: /Volumes/MyDrive/project/.backup-drive-marker
```

**Behavior:**
- Backups run only when drive connected
- Marker file verification ensures correct drive
- Graceful skip when drive disconnected
- Logs to fallback location if drive missing

### Multi-Computer + Mobile Drive

**Scenario:** External drive moves between Desktop and Laptop

**Setup on Desktop:**
```bash
cd /Volumes/WorkDrive/MyProject
/path/to/ClaudeCode-Project-Backups/bin/install.sh

# Configuration
Project name: MyProject
Database path: ~/.myapp/data.db
Enable external drive verification? y
Drive marker file: /Volumes/WorkDrive/MyProject/.backup-drive-marker
```

**Setup on Laptop:**
```bash
# Same steps, same paths
cd /Volumes/WorkDrive/MyProject
/path/to/ClaudeCode-Project-Backups/bin/install.sh

# IMPORTANT: Same marker file path
Drive marker file: /Volumes/WorkDrive/MyProject/.backup-drive-marker
```

**Workflow:**
1. Unplug drive from Desktop
2. Plug into Laptop
3. Open Claude Code session
4. First prompt triggers backup
5. Hourly backups continue
6. Desktop daemon skips (no drive)
7. Laptop daemon runs normally

**Key Points:**
- Same marker file on both computers
- Only one computer connected at a time
- Drive verification prevents wrong backups
- Coordination prevents duplicates

### Network Drive (NAS/Server)

**Setup:**
```bash
# Mount network drive first
# Then install normally

cd /Volumes/NetworkDrive/MyProject
/path/to/ClaudeCode-Project-Backups/bin/install.sh

# Disable drive verification (always mounted)
Enable external drive verification? n
```

**Considerations:**
- Network latency affects backup speed
- Ensure drive auto-mounts on login
- Test failover when network disconnects

---

## Git Integration

### Auto-Commit After Backup

**Enable during install:**
```bash
Enable auto-commit to git after backup? y
```

**Or edit `.backup-config.sh`:**
```bash
AUTO_COMMIT_ENABLED=true
GIT_COMMIT_MESSAGE="Auto-backup: $(date '+%Y-%m-%d %H:%M')"
```

**Behavior:**
- After backing up files, runs `git add -A`
- Commits with timestamp message
- Pushes are manual (not automatic)

**Use Case:** Keep local git history synced with backups

### Gitignore Configuration

**Automatically added during install:**
```
# ClaudeCode Project Backups
backups/
.backup-config.sh

# Critical files (backed up locally, not to GitHub)
.env
.env.*
*.pem
*.key
credentials.json
secrets.*
```

**Why:**
- Backups stay local (too large for GitHub)
- Critical files backed up locally, excluded from GitHub
- Configuration stays local (project-specific paths)

### Pre-Commit Hook Integration

**Trigger backup before commit:**

Create `.git/hooks/pre-commit`:
```bash
#!/bin/bash
# Trigger backup before commit

if [ -f "./.claude/backup-daemon.sh" ]; then
    echo "Running backup before commit..."
    ./.claude/backup-daemon.sh > /dev/null 2>&1 &
fi

exit 0
```

Make executable:
```bash
chmod +x .git/hooks/pre-commit
```

---

## Database Integration

### SQLite

**Supported out-of-box:**
```bash
# During install
Database path: ~/.myapp/data/app.db
```

**Backup method:**
- Uses SQLite `.backup` command
- Creates clean copy (not raw file copy)
- Compresses with gzip (~90% smaller)

**Safety hook:**
- Blocks DROP TABLE, TRUNCATE, destructive operations
- Installed automatically if database configured
- Edit `.claude/hooks/pre-database.sh` to customize patterns

### PostgreSQL (Future Support)

**Current workaround:**

Add to `.backup-config.sh`:
```bash
# PostgreSQL backup (manual)
backup_database() {
    timestamp=$(date '+%m.%d.%y - %H:%M')
    backup_file="$DATABASE_DIR/${PROJECT_NAME} - ${timestamp}.sql.gz"

    pg_dump -U username dbname | gzip > "$backup_file"
}
```

### MySQL (Future Support)

**Current workaround:**

Add to `.backup-config.sh`:
```bash
# MySQL backup (manual)
backup_database() {
    timestamp=$(date '+%m.%d.%y - %H:%M')
    backup_file="$DATABASE_DIR/${PROJECT_NAME} - ${timestamp}.sql.gz"

    mysqldump -u username -p password dbname | gzip > "$backup_file"
}
```

---

## Custom Workflows

### Backup to Cloud Storage

**Sync backups to Dropbox/iCloud:**

Add to LaunchAgent or cron:
```bash
# After backup completes
rsync -az backups/ ~/Dropbox/ProjectBackups/
```

**Or use rclone:**
```bash
rclone sync backups/ remote:backups/
```

### Custom Retention Policies

**Per-file-type retention:**

Edit `cleanup_old_backups()` in `.claude/backup-daemon.sh`:
```bash
cleanup_old_backups() {
    # Critical files: 90 days
    find "$ARCHIVED_DIR" -name "*.env.*" -mtime +90 -delete

    # Code files: 60 days
    find "$ARCHIVED_DIR" -name "*.py.*" -mtime +60 -delete

    # Logs: 30 days
    find "$ARCHIVED_DIR" -name "*.log.*" -mtime +30 -delete

    # Everything else: default
    find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} -delete
}
```

### Notifications on Backup

**macOS notification after backup:**

Add to `.claude/backup-daemon.sh` at end of main execution:
```bash
# Send notification
osascript -e 'display notification "Backup completed successfully" with title "ClaudeCode Backups"'
```

**Email notification:**
```bash
# Email on completion
echo "Backup completed: $db_count databases, $current_files files" | \
    mail -s "Backup Complete: $PROJECT_NAME" your@email.com
```

### Selective File Backup

**Only backup specific file types:**

Edit `backup_changed_files()` in `.claude/backup-daemon.sh`:
```bash
# Only Python and config files
find . -type f \( -name "*.py" -o -name "*.yml" -o -name "*.json" \) >> "$changed_files"
```

**Exclude specific directories:**
```bash
# Skip node_modules, venv, etc.
find . -type f -not -path "*/node_modules/*" -not -path "*/venv/*" >> "$changed_files"
```

---

## Advanced Integration

### CI/CD Pipeline Integration

**Backup before deployment:**

`.github/workflows/deploy.yml`:
```yaml
jobs:
  deploy:
    steps:
      - name: Backup before deploy
        run: |
          ./.claude/backup-daemon.sh

      - name: Deploy
        run: |
          ./deploy.sh
```

### Docker Integration

**Backup from inside container:**

`Dockerfile`:
```dockerfile
# Install backup system
COPY ClaudeCode-Project-Backups /backups-system
RUN /backups-system/bin/install.sh /app

# Run backups in container
CMD ["/app/.claude/backup-daemon.sh"]
```

### Remote Backup Server

**Sync to remote server after backup:**

Add to `.claude/backup-daemon.sh`:
```bash
# After backup completes
rsync -avz -e "ssh -i ~/.ssh/backup_key" \
    backups/ user@backup-server:/backups/$PROJECT_NAME/
```

---

## Troubleshooting Integration

### Claude Code hooks not firing

**Check settings:**
```bash
cat ~/.config/claude/settings.json | jq '.hooks'
```

**Test hook manually:**
```bash
/path/to/project/.claude/hooks/backup-trigger.sh
echo $?  # Should be 0
```

### LaunchAgent not running

**Check if loaded:**
```bash
launchctl list | grep com.claudecode.backup
```

**View logs:**
```bash
tail -f ~/.claudecode-backups/logs/PROJECT-daemon.log
```

**Reload:**
```bash
launchctl unload ~/Library/LaunchAgents/com.claudecode.backup.PROJECT.plist
launchctl load ~/Library/LaunchAgents/com.claudecode.backup.PROJECT.plist
```

### Drive verification failing

**Check marker file:**
```bash
ls -la /path/to/.backup-drive-marker
```

**Verify path in config:**
```bash
grep DRIVE_MARKER_FILE .backup-config.sh
```

**Disable verification temporarily:**
```bash
# Edit .backup-config.sh
DRIVE_VERIFICATION_ENABLED=false
```

---

## Best Practices

1. **Test restore process** — Verify you can actually restore before relying on backups
2. **Monitor backup logs** — Check `backups/backup.log` regularly
3. **Test drive disconnection** — Ensure graceful failover works
4. **Version control config** — Track `.backup-config.sh` changes (but not in public repos)
5. **Document custom changes** — If you modify scripts, document why
6. **Regular cleanup** — Retention policies are automated, but monitor disk space
7. **Backup the backups** — Sync to cloud storage for redundancy

---

## Getting Help

- Check logs: `tail -f backups/backup.log`
- Run status check: `./bin/status.sh`
- For bugs or feature requests, refer to your distribution source documentation
