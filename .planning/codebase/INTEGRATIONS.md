# External Integrations

**Analysis Date:** 2026-02-12

## APIs & External Services

**Cloud Storage (via rclone):**
- 40+ cloud providers supported — Dropbox, Google Drive, OneDrive, iCloud
  - SDK/Client: `rclone` CLI tool
  - Auth: OAuth via browser (interactive `rclone config`)
  - Config: `~/.config/rclone/rclone.conf`
  - Integration: `lib/cloud-backup.sh`, `bin/backup-cloud-config.sh`

**Cloud Folder Sync (zero-API):**
- Dropbox, Google Drive, OneDrive, iCloud desktop apps
  - Integration: `lib/cloud-folder-detector.sh` auto-detects sync folders
  - Paths checked: `$HOME/Dropbox`, `$HOME/Google Drive`, `$HOME/Library/CloudStorage`, `$HOME/iCloud Drive`, `$HOME/OneDrive`
  - No API calls — relies on desktop app file sync

## Data Storage

**Databases (backup targets, not dependencies):**
- SQLite — `lib/database-detector.sh:detect_sqlite()`
  - Client: `sqlite3` CLI
  - Detection: File extension scan (`.db`, `.sqlite`, `.sqlite3`)
- PostgreSQL — `lib/database-detector.sh:detect_postgresql()`
  - Client: `pg_dump`/`pg_restore`
  - Remote: Neon, Supabase support (v2.4.0)
- MySQL — `lib/database-detector.sh:detect_mysql()`
  - Client: `mysqldump`
  - Remote: PlanetScale support (v2.4.0)
- MongoDB — `lib/database-detector.sh:detect_mongodb()`
  - Client: `mongodump`/`mongorestore`
  - Remote: MongoDB Atlas support (v2.4.0)

**File Storage:**
- Local filesystem — `backups/files/` (current versions), `backups/archived/` (timestamped versions)
- External drives — Drive verification via marker file (`lib/backup-lib.sh`)
- Cloud folders — Primary off-site destination

**State Files:**
- `~/.checkpoint/daemon.heartbeat` — Daemon health
- `~/.claudecode-backups/state/{PROJECT_NAME}/` — Per-project state
- `~/.claudecode-backups/locks/{PROJECT_NAME}.lock/` — Concurrent backup prevention
- `~/.claudecode-backups/logs/` — Backup and fallback logs

## Authentication & Identity

Not applicable — Checkpoint is a local tool with no user authentication.

## Monitoring & Observability

**Notifications:**
- macOS: `osascript` (AppleScript `display notification`) — `integrations/lib/notification.sh`
- Linux: `notify-send` (D-Bus), `kdialog` (KDE), `zenity` (GNOME)
- WSL: `powershell.exe` toast notifications
- Fallback: Terminal bell
- Spam prevention: Notification throttling built-in

**Logging:**
- File-based: `$BACKUP_DIR/backup.log`, `~/.checkpoint/logs/watchdog.log`
- Structured error codes: 15 error types with fix suggestions (`lib/backup-lib.sh`)
- Dashboard: Health trends, error panels (`lib/dashboard-status.sh`)

## CI/CD & Deployment

**Hosting:**
- Local installation only — no server deployment
- Global install: `bin/install-global.sh` (symlinks to `/usr/local/bin/`)
- Per-project: `bin/install.sh` (local to project directory)

**Automation:**
- macOS LaunchAgent: `templates/com.checkpoint.watchdog.plist`
  - Label: `com.checkpoint.watchdog`
  - RunAtLoad: true, KeepAlive: true
  - Binary: `bin/checkpoint-watchdog.sh`

## Editor & Tool Integrations

**Claude Code:**
- Skill: `.claude/skills/checkpoint/skill.json` (v2.3.0)
  - Triggers: `/checkpoint`, `/backup-dashboard`, `/backup-status`
  - Execution: `.claude/skills/checkpoint/run.sh`
- Hooks: `.claude/hooks/backup-on-commit.sh`, `.claude/hooks/backup-on-edit.sh`, `.claude/hooks/backup-on-stop.sh`
  - Input: JSON via stdin (parsed with `jq`)

**VS Code:**
- Tasks: `integrations/vscode/tasks.json`
- Keybindings: `integrations/vscode/keybindings.json`
- Installer: `integrations/vscode/install-vscode.sh`

**Shell (Bash/Zsh):**
- Prompt integration: `integrations/shell/backup-shell-integration.sh`
- Auto-backup on directory change (debounced)
- Status display: emoji, compact, or verbose modes

**tmux:**
- Status bar: `integrations/tmux/backup-tmux-status.sh`
- Installer: `integrations/tmux/install-tmux.sh`

**Git:**
- Hook integration: `integrations/git/install-git-hooks.sh`
- Auto-backup on commits

**Vim/Neovim:**
- Plugin: `integrations/vim/`

**direnv:**
- Auto-load: `integrations/direnv/.envrc`

## Docker Integration

- Auto-detects `docker-compose.yml` in projects
- Backs up databases from Docker containers (PostgreSQL, MySQL, MongoDB)
- Config: `BACKUP_DOCKER_DATABASES=true`, `AUTO_START_DOCKER=true`, `STOP_DOCKER_AFTER_BACKUP=true`
- Implementation: `lib/database-detector.sh`

## Environment Configuration

**Development:**
- No env vars required for basic operation
- Optional: `CLAUDECODE_BACKUP_ROOT`, `BACKUP_DIR`, `BACKUP_INTERVAL`
- Config generated on first run via auto-configure

**Production (same as dev):**
- All configuration via `.backup-config.sh` or `.backup-config.yaml`
- Secrets: Database connection strings in config files (gitignored)

## Webhooks & Callbacks

Not applicable — Checkpoint operates locally with no incoming/outgoing webhooks.

---

*Integration audit: 2026-02-12*
*Update when adding/removing external services*
