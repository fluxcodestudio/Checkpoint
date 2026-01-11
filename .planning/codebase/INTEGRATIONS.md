# External Integrations

**Analysis Date:** 2026-01-10

## APIs & External Services

**GitHub API:**
- Purpose: Auto-update from releases, version checking
- SDK/Client: curl via bash
- Auth: Public API (no auth required)
- Endpoints used:
  - `https://api.github.com/repos/nizernoj/Checkpoint/releases/latest`
  - `https://github.com/nizernoj/Checkpoint/archive/refs/tags/v{version}.tar.gz`
- Location: `bin/backup-update.sh`

**Email/Newsletter:**
- Sendy (self-hosted email marketing) - `website/index.html`
  - Endpoint: `SENDY_URL_HERE/subscribe`
  - List ID: `SENDY_LIST_ID_HERE`
  - Method: POST form submission
- Mailto fallback for contact form - `website/index.html`
  - Format: `mailto:YOUR_EMAIL_HERE?subject=...&body=...`

**External APIs:**
- None (self-contained backup system)

## Data Storage

**Databases (Detection & Backup):**
- SQLite - `lib/database-detector.sh`
  - Detection: `.db`, `.sqlite`, `.sqlite3` files
  - Backup: sqlite3 `.backup` command
  - Client: sqlite3 CLI
- PostgreSQL - `lib/database-detector.sh`
  - Detection: `.env` DATABASE_URL parsing
  - Backup: pg_dump
  - Client: PostgreSQL CLI tools
- MySQL - `lib/database-detector.sh`
  - Detection: `.env` DATABASE_URL parsing
  - Backup: mysqldump
  - Client: MySQL CLI tools
- MongoDB - `lib/database-detector.sh`
  - Detection: `.env` MONGODB_URI parsing
  - Backup: mongodump
  - Client: MongoDB tools

**File Storage (Local):**
- Project backups: `$PROJECT_DIR/backups/`
  - Structure: `databases/`, `files/`, `archived/`
- Global state: `~/.claudecode-backups/`
  - Structure: `state/`, `logs/`

**Cloud Storage (via rclone):**
- Dropbox - `lib/cloud-backup.sh`
- Google Drive - `lib/cloud-backup.sh`
- OneDrive - `lib/cloud-backup.sh`
- iCloud - `lib/cloud-backup.sh`
- AWS S3 - supported by rclone
- Azure Blob Storage - supported by rclone
- 40+ total providers via rclone

**Caching:**
- None (file-based state only)

## Authentication & Identity

**Auth Provider:**
- None (local CLI tool, no user authentication)

**OAuth Integrations:**
- None

## Monitoring & Observability

**Error Tracking:**
- Local JSON state files - `$STATE_DIR/$PROJECT_NAME/backup-state.json`
- Failure logs with suggested fixes
- No external error tracking service

**Analytics:**
- None

**Logs:**
- Local log files: `$BACKUP_DIR/backup.log`
- Fallback: `~/.claudecode-backups/logs/backup-fallback.log`
- No external log aggregation

## CI/CD & Deployment

**Hosting:**
- GitHub repository - https://github.com/nizernoj/Checkpoint
- Static website (no server-side)

**CI Pipeline:**
- None configured
- Manual testing via `tests/run-all-tests.sh`

## Environment Configuration

**Development:**
- No required env vars (all configuration via `.backup-config.sh`)
- Optional: DATABASE_URL, MONGODB_URI (for database detection)
- Secrets location: None required

**Staging:**
- N/A (local CLI tool)

**Production:**
- Configuration: `.backup-config.sh` in project root
- Global config: `~/.config/checkpoint/projects.json`

## System Integration (macOS)

**LaunchAgent Daemon:**
- Location: `~/Library/LaunchAgents/com.claudecode.backup.{PROJECT_NAME}.plist`
- Purpose: Hourly automated backups
- Control: `bin/backup-daemon.sh start|stop|status`
- Setup: `bin/install.sh` or `bin/install-global.sh`

## Desktop Notifications

**macOS:**
- Tool: osascript (AppleScript)
- Location: `integrations/lib/notification.sh`
- Sound: "Glass" (configurable)

**Linux GNOME:**
- Tool: notify-send (Freedesktop)
- Location: `integrations/lib/notification.sh`

**Linux KDE:**
- Tool: kdialog
- Location: `integrations/lib/notification.sh`

**WSL:**
- Tool: PowerShell
- Location: `integrations/lib/notification.sh`

## IDE & Editor Integrations

**VS Code:**
- Location: `integrations/vscode/`
- Files:
  - `tasks.json` - Custom tasks
  - `keybindings.json` - Keybindings
  - `install-vscode.sh` - Installer

**Vim/Neovim:**
- Location: `integrations/vim/`
- Purpose: Status bar integration

**Tmux:**
- Location: `integrations/tmux/`
- Purpose: Status bar segment

## Shell Integrations

**Bash/Zsh:**
- Location: `integrations/shell/`
- Features: Aliases, completion, prompt integration

**Direnv:**
- Location: `integrations/direnv/.envrc`
- Purpose: Per-directory environment isolation

## Git Hooks

**Pre-commit:**
- Location: `integrations/git/hooks/pre-commit`
- Purpose: Backup before commit

**Post-commit:**
- Location: `integrations/git/hooks/post-commit`
- Purpose: Status update after commit

**Pre-push:**
- Location: `integrations/git/hooks/pre-push`
- Purpose: Backup before push

## Claude Code Integration

**Skills Framework:**
- Location: `.claude/skills/`
- Skills:
  - `checkpoint/` - Command center dashboard
  - `backup-pause/` - Pause/resume backups
  - `backup-update/` - Update system
  - `uninstall/` - Clean uninstall

## Web Resources

**Google Fonts:**
- Location: `website/index.html`
- Families: Inter, JetBrains Mono
- Usage: Website typography

---

*Integration audit: 2026-01-10*
*Update when adding/removing external services*
