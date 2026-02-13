---
phase: 13-native-file-watcher
plan: 02
subsystem: infra
tags: [bash, session-detection, debounce, robustness, file-watcher]

# Dependency graph
requires:
  - phase: 13-native-file-watcher
    provides: Cross-platform file watcher abstraction (lib/platform/file-watcher.sh)
provides:
  - Session detection in backup-watcher.sh (check_new_session, should_backup_now, update_session_time)
  - Backup interval pre-check before daemon spawn
  - Drive verification check in watcher
  - 8 robustness bug fixes (process substitution, FD cleanup, SIGHUP, double-cleanup guard, log rotation, health check, PID reuse, error handling)
affects: [13-03-PLAN (hook removal), 13-04-PLAN (install/uninstall updates)]

# Tech tracking
tech-stack:
  added: []
  patterns: [session-idle-detection, pre-check-before-spawn, cleanup-guard-pattern, log-rotation-on-startup]

key-files:
  created: []
  modified: [bin/backup-watcher.sh, bin/backup-watch.sh]

key-decisions:
  - "Session tracked by file changes (superset of Claude Code prompts) for editor-agnostic detection"
  - "Pre-check is advisory — daemon's own interval check remains as defense-in-depth"
  - "Process substitution replaces pipeline to fix PID capture bug"
  - "Cleanup guard pattern (CLEANUP_DONE) prevents double execution on SIGTERM+EXIT"

patterns-established:
  - "Cleanup guard: CLEANUP_DONE=false check at top of cleanup()"
  - "Timer subshell FD isolation: exec 0<&- 1>/dev/null"
  - "Log rotation on startup: check size, mv to .old"

issues-created: []

# Metrics
duration: 5min
completed: 2026-02-13
---

# Phase 13 Plan 02: Session Detection Migration + 8 Bug Fixes Summary

**Migrated session detection, interval pre-check, and drive verification from smart-backup-trigger.sh into backup-watcher.sh; fixed 8 robustness bugs including process substitution, SIGHUP trap, double-cleanup guard, log rotation, and project dir health check.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-13T21:07:11Z
- **Completed:** 2026-02-13T21:12:01Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Watcher now self-contained with session awareness: detects new sessions on startup, triggers immediate backup if idle > threshold
- Pre-checks backup interval and drive availability before spawning daemon (saves unnecessary process spawns)
- Updates session timestamp on every file change event (editor-agnostic activity tracking)
- Fixed 8 robustness bugs: process substitution, FD inheritance, SIGHUP, double cleanup, log rotation, project dir health check, PID reuse detection, timer error handling

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate session detection and interval logic** - `a286255` (feat)
2. **Task 2: Fix 8 robustness bugs** - `c49eab1` (fix)

## Files Created/Modified
- `bin/backup-watcher.sh` - Added session detection functions, startup backup logic, 8 bug fixes
- `bin/backup-watch.sh` - Bug 7 fix: PID reuse detection via process name verification

## Decisions Made
- Session tracking uses file changes instead of Claude Code prompts (superset of editor activity)
- Pre-check in watcher is advisory only; daemon's BACKUP_INTERVAL check preserved as defense-in-depth
- Process substitution chosen over named pipe for Bash 3.2 compatibility and simplicity
- Cleanup guard pattern chosen to prevent double-execution (SIGTERM fires cleanup, then EXIT fires it again)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## Next Phase Readiness
- Plan 13-02 complete
- backup-watcher.sh now has full session detection + interval pre-check + 8 robustness fixes
- Ready for Plan 13-03: Hook removal (delete .claude/hooks/*, smart-backup-trigger.sh, templates/claude-settings.json)

---
*Phase: 13-native-file-watcher*
*Completed: 2026-02-13*
