# Architecture

**Analysis Date:** 2026-02-12

## Pattern Overview

**Overall:** Layered Monolithic CLI Application

**Key Characteristics:**
- Modular bash scripts with clear layer separation
- Library-based code sharing via `source`
- File-based state (no database for internal state)
- Daemon + on-demand execution model
- Progressive feature loading (optional dependencies)

## Layers

**CLI Layer (bin/):**
- Purpose: User-facing commands and entry points
- Contains: 31 executable scripts — backup triggers, installers, dashboard, config managers
- Key files: `bin/backup-now.sh` (1,427 lines), `bin/backup-daemon.sh` (678 lines), `bin/backup-config.sh` (1,126 lines), `bin/checkpoint-dashboard.sh` (653 lines), `bin/backup-restore.sh` (983 lines)
- Depends on: Service layer (lib/)
- Used by: User CLI, LaunchAgent, Claude Code hooks

**Service Layer (lib/):**
- Purpose: Core business logic and domain services
- Contains: 13 library modules — config management, database detection, cloud sync, retention, restore
- Key files: `lib/backup-lib.sh` (3,216 lines), `lib/database-detector.sh` (1,163 lines), `lib/auto-configure.sh` (1,290 lines)
- Depends on: System tools (git, sqlite3, rclone, etc.)
- Used by: CLI layer exclusively

**Integration Layer (integrations/):**
- Purpose: Editor, shell, and tool integrations
- Contains: Shell, VS Code, tmux, vim, git, direnv integration scripts
- Key files: `integrations/shell/backup-shell-integration.sh`, `integrations/lib/notification.sh`, `integrations/lib/integration-core.sh`
- Depends on: Service layer for backup operations
- Used by: External tools (editors, shells, git hooks)

**Template Layer (templates/):**
- Purpose: Configuration templates and defaults
- Contains: Config templates, plist files, skill definitions
- Key files: `templates/backup-config.sh`, `templates/backup-config.yaml`, `templates/com.checkpoint.watchdog.plist`
- Used by: Installation scripts, auto-configure

**Storage Layer (backups/):**
- Purpose: Backup data storage
- Contains: `files/` (current), `archived/` (timestamped), `databases/` (compressed)
- Managed by: Service layer functions
- Lifecycle: Managed by retention policy (`lib/retention-policy.sh`)

## Data Flow

**Manual Backup (`backup-now`):**

1. User runs `backup-now` (or hook triggers it)
2. Script resolves paths, sources `lib/backup-lib.sh` + optional libraries
3. `load_backup_config()` reads `.backup-config.sh` or `.backup-config.yaml`
4. Pre-flight checks: drive verification, lock acquisition, interval check
5. Database detection and backup (`lib/database-detector.sh`)
6. File change detection (git diff or filesystem scan with hash comparison)
7. Changed files copied to `backups/files/`, old versions archived to `backups/archived/`
8. Cloud upload triggered if enabled (`lib/cloud-backup.sh`)
9. Retention policy applied (`lib/retention-policy.sh`)
10. State updated, notifications sent, lock released

**Daemon Backup (`backup-daemon`):**

1. LaunchAgent starts `bin/checkpoint-watchdog.sh`
2. Watchdog monitors registered projects (`~/.config/checkpoint/projects.json`)
3. For each project: checks interval, acquires lock, runs backup cycle
4. Heartbeat file updated at `~/.checkpoint/daemon.heartbeat`
5. Cleanup and retention applied after successful backup

**State Management:**
- File-based: Lock files, heartbeat files, state JSON
- Lock directory: `~/.claudecode-backups/locks/{PROJECT_NAME}.lock/` (atomic mkdir)
- No persistent in-memory state — each invocation loads config fresh

## Key Abstractions

**Configuration System:**
- Purpose: Unified config loading with format migration
- Implementation: `lib/backup-lib.sh:load_backup_config()` — supports both bash and YAML formats
- Pattern: Source-based (bash config) or parsed (YAML config) with fallback chain

**Database Detector:**
- Purpose: Universal database discovery and backup
- Implementation: `lib/database-detector.sh` — detect + backup for 4 DB engines
- Pattern: Convention-based detection (file extensions, ports, docker-compose)

**Cloud Sync:**
- Purpose: Off-site backup with fallback chain
- Implementation: `lib/cloud-backup.sh` — cloud folder → rclone API → local queue
- Pattern: Fallback chain with progressive degradation

**Retention Policy:**
- Purpose: Time Machine-style tiered snapshot management
- Implementation: `lib/retention-policy.sh` — classify, prune, keep representatives
- Pattern: Rule-based classification (hourly/daily/weekly/monthly tiers)

## Entry Points

**Primary CLI:**
- `bin/backup-now.sh` — Manual backup trigger
- `bin/checkpoint.sh` — Command center (routes to subcommands)
- `bin/checkpoint-dashboard.sh` — Interactive TUI dashboard
- `bin/backup-config.sh` — Configuration management

**Daemon:**
- `bin/checkpoint-watchdog.sh` — LaunchAgent guardian process
- `bin/backup-daemon.sh` — Per-project backup daemon
- `bin/backup-all-projects.sh` — Global multi-project daemon

**Installation:**
- `bin/install.sh` — Per-project installer
- `bin/install-global.sh` — System-wide installer

**Hooks:**
- `.claude/hooks/backup-on-commit.sh` — Claude Code commit trigger
- `bin/smart-backup-trigger.sh` — Generic hook trigger

## Error Handling

**Strategy:** `set -euo pipefail` + structured error codes + notification dispatch

**Patterns:**
- All scripts use `set -euo pipefail` (strict mode)
- 15 structured error codes with human-readable names (`lib/backup-lib.sh`)
- `map_error_to_code()` and `get_error_suggestion()` for actionable error messages
- Lock-based concurrency prevention (atomic `mkdir` for locks)
- Stale lock detection and cleanup
- Fallback chains: cloud folder → rclone → local queue

## Cross-Cutting Concerns

**Logging:**
- File-based: `$BACKUP_DIR/backup.log`, `~/.checkpoint/logs/watchdog.log`
- Functions: `log_info()`, `log_error()`, `log_warn()`, `log_verbose()` in CLI scripts
- Color-coded terminal output via ANSI escape codes

**Notifications:**
- Cross-platform: `integrations/lib/notification.sh`
- macOS: `osascript`, Linux: `notify-send`/`kdialog`/`zenity`, WSL: PowerShell
- Throttling: Spam prevention built-in

**Configuration Validation:**
- `bin/backup-config.sh:mode_validate()` — Validates all config options
- Range checks, format validation, existence checks
- Helpful error messages with fix suggestions

---

*Architecture analysis: 2026-02-12*
*Update when major patterns change*
