---
phase: 17-error-logging
plan: 01
subsystem: logging
tags: [bash, logging, log-rotation, debug-mode, module-system]

# Dependency graph
requires:
  - phase: 11-modularize-foundation
    provides: module loader, include guards, @requires/@provides pattern
  - phase: 15-linux-systemd
    provides: platform compat layer (get_file_size)
provides:
  - lib/core/logging.sh centralized logging module
  - log_error/warn/info/debug/trace convenience functions
  - Size-based log rotation (5 files, 10MB each)
  - parse_log_flags for --debug/--trace/--quiet CLI args
  - SIGUSR1 debug toggle for daemon
  - _init_checkpoint_logging() post-config initialization
  - backup_log() delegation to structured logging
affects: [17-02-core-migration, 17-03-library-migration, 17-04-cli-migration, 18-daemon-lifecycle]

# Tech tracking
tech-stack:
  added: []
  patterns: [centralized-logging, log-level-filtering, size-based-rotation, debug-toggle]

key-files:
  created: [lib/core/logging.sh]
  modified: [lib/backup-lib.sh, lib/core/config.sh, lib/core/output.sh]

key-decisions:
  - "Logging loads BEFORE config.sh — self-contained with env var defaults so it can log config load errors"
  - "_init_checkpoint_logging() called by scripts after load_backup_config() rather than at source time"
  - "backup_log() delegates to log_info/warn/error but keeps legacy file-write for backward compat"
  - "get_file_size with wc -c fallback for rotation — defensive against compat.sh not being loaded"

patterns-established:
  - "Log format: [YYYY-MM-DD HH:MM:SS] [LEVEL] [context] message"
  - "Log levels: ERROR=0, WARN=1, INFO=2, DEBUG=3, TRACE=4"
  - "CLI flags: --debug, --trace, --quiet parsed by parse_log_flags()"

issues-created: []

# Metrics
duration: 5 min
completed: 2026-02-14
---

# Phase 17 Plan 01: Logging Foundation Summary

**Centralized bash logging module with 5 log levels, size-based rotation (5x10MB), debug toggle, and backward-compatible integration into module loader + config + output**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-14T01:17:14Z
- **Completed:** 2026-02-14T01:21:58Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Created lib/core/logging.sh with include guard, 5 log levels, init_logging, _log core writer, 5 convenience functions, log_set_context, _rotate_log, parse_log_flags, _toggle_debug_level
- Integrated as first core module in backup-lib.sh loader chain (before error-codes.sh)
- Added CHECKPOINT_LOG_LEVEL and CHECKPOINT_LOG_MAX_SIZE config defaults
- Updated backup_log() to delegate to structured logging while maintaining backward compatibility

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lib/core/logging.sh** - `c8932c9` (feat)
2. **Task 2: Integrate logging into module loader, config, and output** - `3b6ea6c` (feat)

## Files Created/Modified
- `lib/core/logging.sh` - New centralized logging module (219 lines)
- `lib/backup-lib.sh` - Added logging.sh as first core module, added _init_checkpoint_logging()
- `lib/core/config.sh` - Added CHECKPOINT_LOG_LEVEL and CHECKPOINT_LOG_MAX_SIZE defaults
- `lib/core/output.sh` - Added backup_log() delegation to log_info/warn/error

## Decisions Made
- Logging loads before config.sh — self-contained with env var defaults so it can log config load errors
- _init_checkpoint_logging() called by scripts after load_backup_config() rather than at source time
- backup_log() delegates to structured logging but keeps legacy file-write for backward compatibility
- get_file_size with wc -c fallback for rotation — defensive against compat.sh not being loaded

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness
- Logging foundation complete, ready for core script migration (17-02)
- All existing scripts continue to work without changes
- New log_* functions available for migration in subsequent plans

---
*Phase: 17-error-logging*
*Completed: 2026-02-14*
