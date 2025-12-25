---
name: checkpoint
description: Open Checkpoint backup system control panel. Use when managing backups, checking backup status, configuring backup settings, restoring files, or updating the backup system.
---

# Checkpoint - Automated Backup Command Center

Interactive TUI dashboard for managing all aspects of the Checkpoint backup system.

## When to use this skill

- Check backup status and health
- Run backups immediately
- Restore files or databases
- Configure backup settings (global or per-project)
- Clean up old backups
- Update Checkpoint to latest version
- Pause/resume automatic backups
- Manage cloud sync

## What it does

Opens an interactive dialog-based menu system with:

1. **Quick Actions** - Backup now, restore, pause/resume
2. **Settings** - Configure global and project settings
3. **Backup Management** - View history, cleanup, restore points
4. **Cloud Sync** - Configure and manage cloud backups
5. **All Commands** - Complete command reference
6. **Updates & Maintenance** - Check for updates, system health

## Examples

```bash
/checkpoint              # Opens interactive dashboard
/checkpoint --status     # Quick status view
/checkpoint --update     # Check for updates
```

## Requirements

- Checkpoint v2.2.0+ installed globally
- Dialog or whiptail for TUI (auto-installed)
- Bash 4.0+ recommended (auto-upgrade offered)
