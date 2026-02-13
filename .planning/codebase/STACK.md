# Technology Stack

**Analysis Date:** 2026-02-12

## Languages

**Primary:**
- Bash 3.2+ — All application code (~59,860 lines across `bin/`, `lib/`, `integrations/`, `tests/`)

**Secondary:**
- YAML — Modern configuration format (`templates/backup-config.yaml`)
- JSON — Integration metadata (`integrations/vscode/tasks.json`, `.claude/skills/checkpoint/skill.json`)
- XML/Plist — macOS daemon configuration (`templates/com.checkpoint.watchdog.plist`)
- AppleScript — macOS notifications and login items (via `osascript` in `bin/checkpoint-watchdog.sh`, `bin/install-helper.sh`)

## Runtime

**Environment:**
- Bash 3.2+ (macOS default) — minimum requirement
- Bash 4.0+ recommended — for TUI dashboard with `dialog` support
- Version check: `check_bash_version()` in `lib/dependency-manager.sh`

**Package Manager:**
- No application-level package manager (pure bash, no npm/pip)
- System dependencies installed via Homebrew (macOS), apt/yum/dnf (Linux), or curl scripts

## Frameworks

**Core:**
- None (vanilla Bash CLI application)

**Testing:**
- Custom bash test framework — `tests/test-framework.sh`
- Assertions: `assert_equals()`, `assert_contains()`, `assert_file_exists()`, `assert_success()`
- 290+ tests across unit, integration, E2E, compatibility, and stress categories

**Build/Dev:**
- No build step — scripts run directly
- ShellCheck for static analysis (directives in test files)

## Key Dependencies

**Required (system tools):**
- `git` — Version control detection (`lib/backup-lib.sh`)
- `find`, `grep`, `sed`, `awk`, `sort` — Standard Unix utilities
- `tar`, `gzip` — File compression (`lib/backup-lib.sh`)
- `shasum` — Hash-based file comparison (`lib/backup-lib.sh`)

**Optional (progressive installation via `lib/dependency-manager.sh`):**
- `rclone` (~50MB) — Cloud storage sync, 40+ providers (`lib/cloud-backup.sh`)
- `sqlite3` — SQLite database backup (`lib/database-detector.sh`)
- `pg_dump`/`pg_restore` — PostgreSQL backup (`lib/database-detector.sh`)
- `mysqldump` — MySQL backup (`lib/database-detector.sh`)
- `mongodump`/`mongorestore` — MongoDB backup (`lib/database-detector.sh`)
- `dialog`/`whiptail` (~500KB) — TUI dashboard menus (`lib/dashboard-ui.sh`)
- `jq` — JSON processing (`bin/backup-cloud-config.sh`)
- `curl` — HTTP client for rclone installation

## Configuration

**Environment:**
- Per-project: `.backup-config.sh` (bash format) or `.backup-config.yaml` (YAML format)
- Global: `~/.config/checkpoint/config.sh`
- Project registry: `~/.config/checkpoint/projects.json`
- Key env vars: `CLAUDECODE_BACKUP_ROOT`, `PROJECT_DIR`, `BACKUP_DIR`, `BACKUP_INTERVAL`

**Templates:**
- `templates/backup-config.sh` — Bash config template
- `templates/backup-config.yaml` — YAML config template
- `templates/global-config-template.sh` — Global defaults

## Platform Requirements

**Development:**
- macOS (primary target) — launchd, osascript, Homebrew
- Linux supported — notify-send, apt/yum/dnf
- WSL supported — PowerShell notifications

**Production:**
- Installed via `bin/install-global.sh` (global) or `bin/install.sh` (per-project)
- Daemon via macOS LaunchAgent (`~/Library/LaunchAgents/com.checkpoint.watchdog.plist`)
- No containerization or cloud deployment

---

*Stack analysis: 2026-02-12*
*Update after major dependency changes*
