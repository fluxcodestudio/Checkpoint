# Architecture

**Analysis Date:** 2026-01-10

## Pattern Overview

**Overall:** Layered Monolith (CLI + Library Architecture)

**Key Characteristics:**
- Pure bash implementation (no external dependencies for core functionality)
- Library-first design: shared code in `lib/`, executables in `bin/`
- Event-driven CLI with background daemon support
- State-driven: JSON-based backup state tracking and reporting
- Installation modes: Global (system-wide via `~/.local/bin`) or Per-Project

## Layers

```
┌─────────────────────────────────────────────────────────┐
│        USER INTERFACE LAYER (CLI + Claude Skills)        │
│  backup-now, backup-status, checkpoint, restore, etc.   │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│           ORCHESTRATION LAYER (Daemon/Trigger)          │
│  backup-daemon.sh, smart-backup-trigger.sh              │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│          SERVICE LAYER (Core Logic Libraries)           │
│  backup-lib.sh, database-detector.sh, cloud-backup.sh   │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│          INTEGRATION LAYER (Platform Support)           │
│  Shell, Git, Vim, VSCode, Tmux, Direnv hooks           │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│         DATA/STORAGE LAYER (Filesystem Operations)      │
│  Files, databases, compression, cloud storage           │
└─────────────────────────────────────────────────────────┘
```

**Command Layer:**
- Purpose: Parse user input and route to appropriate handler
- Contains: CLI commands, argument parsing, help text
- Location: `bin/*.sh`
- Depends on: Service layer via library sourcing
- Used by: Users, Claude Code skills, cron/launchd

**Service Layer:**
- Purpose: Core business logic for backup operations
- Contains: `backup-lib.sh`, `database-detector.sh`, `cloud-backup.sh`, `dependency-manager.sh`, `projects-registry.sh`
- Location: `lib/*.sh`
- Depends on: File system utilities, external tools
- Used by: Command handlers

**Integration Layer:**
- Purpose: Platform-specific hooks and notifications
- Contains: Shell aliases, git hooks, editor integrations
- Location: `integrations/*/`
- Depends on: Platform detection, notification systems
- Used by: Service layer for notifications

## Data Flow

**CLI Command Execution (backup-now):**

1. User runs: `backup-now [--force|--database-only|--files-only]`
2. Resolve script symlinks → `SCRIPT_DIR`, `LIB_DIR`
3. Source foundation: `backup-lib.sh`
4. Source detectors: `database-detector.sh`, `dependency-manager.sh`
5. Load config: `$PROJECT_DIR/.backup-config.sh`
6. Acquire lock: `acquire_backup_lock()` (prevent concurrent backups)
7. Detect & backup databases: `detect_databases()`, `backup_detected_databases()`
8. Scan & backup files: Copy changed files to `$FILES_DIR/`, archive old versions
9. Release lock: `release_backup_lock()`
10. Generate state: `write_backup_state()` → JSON file
11. Send notification: `send_notification()` (native macOS/Linux)
12. Exit with code: 0 = success, 1 = partial, 2 = failure

**State Management:**
- File-based: All state lives in `~/.claudecode-backups/state/[PROJECT_NAME]/`
- JSON format: `backup-state.json` for machine-readable status
- No persistent in-memory state
- Each command execution is independent

## Key Abstractions

**State Management Functions:**
- `init_backup_state()` - Clear state variables
- `add_file_failure()` - Track individual failures with metadata
- `write_backup_state()` - JSON serialization for retrieval
- `read_backup_state()` - Load previous state

**Locking Pattern:**
- `acquire_backup_lock()` - PID file in `$STATE_DIR`
- `release_backup_lock()` - Cleanup on success/failure
- `get_lock_pid()` - Detect stale locks

**Notification with Escalation:**
- `notify_backup_failure()` - First failure → immediate alert
- `send_notification()` - Native macOS osascript / Linux notify-send
- Recurring → escalate every 3 hours

**Database Detection:**
- `detect_sqlite()`, `detect_postgresql()`, `detect_mysql()`, `detect_mongodb()`
- Auto-discover from `.env` files and common paths
- Type-specific backup tools (sqlite3, pg_dump, mysqldump, mongodump)

## Entry Points

**CLI Entry (Primary Commands):**
- `bin/backup-now.sh` - Force immediate backup
- `bin/backup-status.sh` - Display health dashboard
- `bin/backup-daemon.sh` - Background hourly service
- `bin/backup-restore.sh` - Interactive restore wizard
- `bin/checkpoint.sh` - Command center (TUI)

**Installation:**
- `bin/install.sh` - Per-project or global setup
- `bin/install-global.sh` - System-wide installation
- `bin/install-integrations.sh` - Add platform hooks

**Claude Code Skills:**
- `.claude/skills/checkpoint/` - `/checkpoint` command
- `.claude/skills/backup-pause/` - Pause backups skill
- `.claude/skills/backup-update/` - Update backups skill
- `.claude/skills/uninstall/` - Uninstall skill

## Error Handling

**Strategy:** Throw errors, catch at command level, log and exit

**Patterns:**
- `set -euo pipefail` standard in all scripts
- Services use return codes and stderr for errors
- Command handlers log error with context before exit
- Validation errors shown before execution (fail fast)
- Error tracking: JSON state includes failure details with suggested fixes

## Cross-Cutting Concerns

**Logging:**
- Console output for normal operation
- Log files: `$BACKUP_DIR/backup.log` - `bin/backup-daemon.sh`
- Fallback: `~/.claudecode-backups/logs/backup-fallback.log`
- Color output via helper functions

**Validation:**
- Path validation before file operations
- Database connectivity checks before backup
- Drive marker verification for external drives

**Configuration:**
- Bash sourcing: `.backup-config.sh`
- YAML alternative: `.backup-config.yaml`
- Loaded once at startup, not modified during execution

---

*Architecture analysis: 2026-01-10*
*Update when major patterns change*
