# /checkpoint - Automated Backup Command Center

Use AskUserQuestion with ONE question:

## Question: "Checkpoint - What would you like to do?"
Header: "Action"

Options:
1. **⚡ Quick Actions** - "Backup now, restore, pause/resume"
2. **⚙️ Settings** - "Configure global and project settings"
3. **📦 Backup Management** - "View history, cleanup, restore points"
4. **☁️ Cloud Sync** - "Configure and manage cloud backups"
5. **🔧 All Commands** - "See complete command reference"
6. **🔄 Updates & Maintenance** - "Check updates, system health"

## Actions

### If "Quick Actions":
Ask follow-up question:
- "Backup Now" → Run `checkpoint --status` then `backup-now`
- "Restore Files" → Run `backup-restore`
- "View Status" → Run `backup-status`
- "Pause Backups" → Run `backup-pause`
- "Resume Backups" → Run `backup-pause --resume`
- "Quick Cleanup" → Run `backup-cleanup --preview`

### If "Settings":
Ask follow-up question:
- "Edit Global Settings" → Run `checkpoint --global`
- "Configure This Project" → Run `checkpoint --project`
- "Cloud Backup Setup" → Run `backup-cloud-config`
- "View Current Config" → Show `.backup-config.sh` content

### If "Backup Management":
Ask follow-up question:
- "View Backup History" → Run `backup-status --timeline`
- "Clean Old Backups" → Run `backup-cleanup --preview` then optionally `backup-cleanup`
- "Verify Backups" → Check backup directory integrity
- "Restore Point Info" → Show available restore points

### If "Cloud Sync":
Ask follow-up question:
- "Configure Cloud Storage" → Run `backup-cloud-config`
- "Sync Now" → Trigger manual cloud sync
- "View Sync Status" → Show last sync time and status
- "Test Connection" → Verify cloud connection

### If "All Commands":
Show command reference:

**Status & Info:**
- `checkpoint` - Interactive dashboard
- `checkpoint --status` - Quick status view
- `backup-status` - Full status dashboard

**Backup Operations:**
- `backup-now` - Run backup immediately
- `backup-restore` - Restore from backups
- `backup-cleanup` - Clean old backups

**Configuration:**
- `checkpoint --global` - Edit global settings
- `checkpoint --project` - Configure project
- `backup-cloud-config` - Cloud storage setup
- `configure-project <path>` - Configure specific project

**Maintenance:**
- `backup-update` - Update to latest version
- `backup-pause` - Pause/resume automation
- `backup-uninstall` - Uninstall Checkpoint

### If "Updates & Maintenance":
First run `backup-update --check-only` to check for updates.

Then ask follow-up question:
- "Install Update" → Run `backup-update`
- "Check System Health" → Run `checkpoint --status` and verify
- "View Changelog" → Show CHANGELOG.md
- "Reinstall" → Guide through reinstallation

## Quick Status Check

Always start by running:
```bash
checkpoint --status
```

This shows:
- Installation mode (global/per-project)
- Project configuration status
- Last backup time
- Retention policies
- Cloud sync status
- Available commands

## System Info

| Feature | Status |
|---------|--------|
| Version | 2.2.0 |
| Database Support | SQLite, PostgreSQL, MySQL, MongoDB |
| Cloud Providers | Any rclone-compatible (40+ services) |
| Auto-backup | Hourly via LaunchAgent (macOS) |
| Test Coverage | 100% (164/164 tests passing) |

Run `/checkpoint` anytime to manage backups or check status.
