# Technology Stack

**Analysis Date:** 2026-01-10

## Languages

**Primary:**
- Bash 3.2+ - All application code (`bin/*.sh`, `lib/*.sh`, `integrations/*/*.sh`)

**Secondary:**
- HTML5/CSS3 - Website (`website/index.html`, `website/style.css`)
- JavaScript (vanilla, client-side) - Website forms (`website/index.html`)

## Runtime

**Environment:**
- Bash 3.2+ (macOS default) - `lib/dependency-manager.sh`
- Bash 4.0+ recommended for TUI features with `dialog`
- macOS (primary) with Linux support (Debian/Ubuntu/RedHat)
- WSL support via PowerShell

**Package Manager:**
- No traditional package managers (pure bash)
- Manual installation via shell scripts
- Dependencies installed via system package managers:
  - Homebrew (macOS) - `lib/dependency-manager.sh`
  - apt-get (Debian/Ubuntu) - `lib/dependency-manager.sh`
  - yum (RedHat/CentOS) - `lib/dependency-manager.sh`
  - pacman (Arch Linux) - `lib/dependency-manager.sh`

## Frameworks

**Core:**
- None (vanilla Node.js CLI pattern, pure bash)

**Testing:**
- Custom bash test framework - `tests/test-framework.sh`
- No external test dependencies

**Build/Dev:**
- No build framework (pure bash executables)
- Git hooks integration - `integrations/git/hooks/`

## Key Dependencies

**Critical (External Tools):**
- SQLite3 - `lib/database-detector.sh` (database backup)
- PostgreSQL (pg_dump) - `lib/database-detector.sh` (database backup)
- MySQL (mysqldump) - `lib/database-detector.sh` (database backup)
- MongoDB (mongodump) - `lib/database-detector.sh` (database backup)
- rclone (40+ cloud providers) - `lib/cloud-backup.sh`

**System Tools:**
- dialog (TUI menus) - `lib/dependency-manager.sh`
- launchctl (macOS daemon management) - `bin/install.sh`, `bin/backup-daemon.sh`
- git - version control and auto-push features

**Notification Systems:**
- osascript (macOS) - `integrations/lib/notification.sh`
- notify-send (Linux GNOME) - `integrations/lib/notification.sh`
- kdialog (KDE) - `integrations/lib/notification.sh`
- zenity (GNOME) - `integrations/lib/notification.sh`
- PowerShell (WSL) - `integrations/lib/notification.sh`

## Configuration

**Environment:**
- Per-project: `.backup-config.sh` - `templates/backup-config.sh`
- Global config: `~/.config/checkpoint/projects.json` - `lib/projects-registry.sh`
- Environment variables (.env detection) - `lib/database-detector.sh`
- YAML configuration parsing supported

**Build:**
- No build configuration (interpreted bash)
- Executable scripts require `chmod +x`

## Platform Requirements

**Development:**
- macOS/Linux/Windows (via WSL)
- bash 3.2+ required
- No external dependencies for core functionality

**Production:**
- Distributed as git repository or zip download
- Installed via `bin/install.sh` or `bin/install-global.sh`
- LaunchAgent daemon for automated backups (macOS)
- Cron support for Linux/WSL

---

*Stack analysis: 2026-01-10*
*Update after major dependency changes*
