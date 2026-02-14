---
phase: 17-error-logging
plan: 02
subsystem: logging
tags: [bash, logging, structured-logging, debug-mode, stderr-capture]

# Dependency graph
requires:
  - phase: 17-error-logging
    provides: lib/core/logging.sh module with log_error/warn/info/debug/trace, parse_log_flags, SIGUSR1 toggle
provides:
  - backup-now.sh structured logging with --debug/--trace flags
  - backup-daemon.sh structured logging with SIGUSR1 debug toggle
  - checkpoint-watchdog.sh structured logging with SIGUSR1 debug toggle and PID file
  - cli_* renamed functions preserving colored terminal output
affects: [17-03-library-migration, 17-04-cli-migration, 18-daemon-lifecycle]

# Tech tracking
tech-stack:
  added: []
  patterns: [stderr-to-logfile-redirect, cli-vs-log-function-separation, watchdog-pid-file, daemon-sigusr1-toggle]

key-files:
  created: []
  modified: [bin/backup-now.sh, bin/backup-daemon.sh, bin/checkpoint-watchdog.sh]

key-decisions:
  - "Renamed local log_* functions to cli_* to avoid shadowing module functions while preserving colored terminal output"
  - "daemon_log() kept for backward compat — delegates to log_info() while maintaining dual-log architecture"
  - "Watchdog sources logging.sh directly (doesn't use backup-lib.sh), calls init_logging() with explicit params"
  - "Removed watchdog manual log rotation — logging.sh handles rotation now"

patterns-established:
  - "cli_* functions for user-facing colored output, log_* for structured file logging"
  - "log_trace for per-cycle/per-file loop noise, log_debug for per-operation details"
  - "stderr -> ${_CHECKPOINT_LOG_FILE:-/dev/null} for git/rsync/find operations"

issues-created: []

# Metrics
duration: 9 min
completed: 2026-02-14
---

# Phase 17 Plan 02: Core Script Migration Summary

**Migrated 3 core backup scripts (~170 combined 2>/dev/null occurrences) to structured logging with --debug/--trace CLI flags and SIGUSR1 runtime debug toggle**

## Performance

- **Duration:** 9 min
- **Started:** 2026-02-14T01:25:13Z
- **Completed:** 2026-02-14T01:35:08Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Migrated backup-now.sh: replaced ~50+ `2>/dev/null` with stderr-to-logfile redirects, added --debug/--trace/--quiet flags, renamed 5 local log functions to cli_* to avoid shadowing
- Migrated backup-daemon.sh: replaced ~25+ `2>/dev/null`, added SIGUSR1 debug toggle, renamed custom log() to daemon_log() with delegation to log_info()
- Migrated checkpoint-watchdog.sh: removed custom log() with manual rotation, replaced all calls with log_info/warn/error, added SIGUSR1 toggle and PID file at ${STATE_DIR}/watchdog.pid

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate backup-now.sh to structured logging** - `0ec9d85` (feat)
2. **Task 2: Migrate daemon and watchdog to structured logging** - `1b889d5` (feat)

## Files Created/Modified
- `bin/backup-now.sh` - Structured logging, --debug/--trace flags, cli_* renamed functions, stderr-to-logfile redirects for git/rsync/find/cp/rclone
- `bin/backup-daemon.sh` - Structured logging, SIGUSR1 toggle, daemon_log() delegation, stderr-to-logfile redirects for git/sqlite3/find
- `bin/checkpoint-watchdog.sh` - Direct logging.sh sourcing, removed manual rotation, PID file for signal delivery, log_trace for per-cycle heartbeat

## Decisions Made
- Renamed local log_*/log_verbose functions to cli_* to avoid shadowing module functions while preserving colored terminal output
- daemon_log() kept for backward compat — daemon has dual-log architecture (legacy file + structured), removing legacy path would break existing monitoring
- Watchdog sources logging.sh directly since it doesn't use backup-lib.sh — calls init_logging() with explicit parameters
- Removed watchdog's LOG_DIR/MAX_LOG_SIZE variables and manual rotation logic — logging.sh handles rotation

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Watchdog sources logging.sh directly**
- **Found during:** Task 2 (checkpoint-watchdog.sh migration)
- **Issue:** Watchdog only uses compat.sh and daemon-manager.sh, not backup-lib.sh — _init_checkpoint_logging() not available
- **Fix:** Source logging.sh directly, call init_logging() with explicit parameters instead of _init_checkpoint_logging()
- **Files modified:** bin/checkpoint-watchdog.sh
- **Verification:** bash -n passes, log output correct
- **Committed in:** 1b889d5

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minor adaptation for watchdog's different sourcing pattern. No scope creep.

## Issues Encountered

None.

## Next Phase Readiness
- Core backup scripts fully migrated to structured logging
- Ready for library module migration (17-03)
- Patterns established: cli_* vs log_* separation, stderr-to-logfile redirect, SIGUSR1 toggle

---
*Phase: 17-error-logging*
*Completed: 2026-02-14*
