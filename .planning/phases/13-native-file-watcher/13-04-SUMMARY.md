---
phase: 13-native-file-watcher
plan: 04
subsystem: infra
tags: [bash, hooks, install, uninstall, decoupling]

# Dependency graph
requires:
  - phase: 13-native-file-watcher
    provides: Session detection migrated to backup-watcher.sh (Plan 02), config template updated (Plan 03)
provides:
  - Complete Claude Code hook removal (5 files deleted, 3 scripts cleaned)
  - Editor-agnostic backup system (no Claude Code dependency)
  - Cleaned install/uninstall scripts (~291 lines of hook code removed)
affects: [14-PLAN (security hardening)]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified: [bin/install.sh, bin/uninstall.sh, bin/install-global.sh]

key-decisions:
  - "Complete hook removal — no optional fallback kept"
  - "Watcher LaunchAgent installation preserved in install.sh"

patterns-established: []

issues-created: []

# Metrics
duration: 5min
completed: 2026-02-13
---

# Phase 13 Plan 04: Hook Removal + Install Script Cleanup Summary

**Deleted 5 hook-related files (189 lines) and removed ~291 lines of hook code from install/uninstall/install-global scripts — completing the decoupling from Claude Code.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-13T21:16:29Z
- **Completed:** 2026-02-13T21:20:58Z
- **Tasks:** 2
- **Files deleted:** 5
- **Files modified:** 3

## Accomplishments
- Deleted all 5 hook-related files: 3 hook scripts, smart-backup-trigger.sh, claude-settings.json template
- Removed ~135 lines of hook code from install.sh (question, dir creation, script copying, HOOKS_ENABLED logic, settings.json generation, global hooks migration)
- Removed ~44 lines from uninstall.sh (hook deletion, jq-based settings cleanup)
- Removed ~112 lines from install-global.sh (entire SESSION-START HOOKS section)
- All watcher/daemon/LaunchAgent installation code preserved
- Checkpoint is now fully editor-agnostic — no Claude Code dependency

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete hook files and smart-backup-trigger.sh** - `6de82d1` (feat)
2. **Task 2: Remove hook code from install scripts** - `70ea6f9` (feat)

## Files Deleted
- `.claude/hooks/backup-on-edit.sh` - Replaced by native file watcher
- `.claude/hooks/backup-on-commit.sh` - Replaced by native file watcher
- `.claude/hooks/backup-on-stop.sh` - Replaced by debounce-based backup
- `bin/smart-backup-trigger.sh` - Logic migrated to backup-watcher.sh
- `templates/claude-settings.json` - Hook configuration no longer needed

## Files Modified
- `bin/install.sh` - Removed 6 hook-related sections (~135 lines)
- `bin/uninstall.sh` - Removed hook deletion and settings cleanup (~44 lines)
- `bin/install-global.sh` - Removed SESSION-START HOOKS section (~112 lines)

## Decisions Made
- Complete hook removal with no optional fallback — watcher fully replaces hooks
- Watcher LaunchAgent installation preserved in install.sh

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## Phase 13 Complete

All 4 plans finished:
1. **13-01:** Cross-platform file watcher abstraction (lib/platform/file-watcher.sh)
2. **13-02:** Session detection migration + 8 robustness bug fixes
3. **13-03:** Cross-platform CLI + config template update
4. **13-04:** Hook removal + install script cleanup

Checkpoint is now fully editor-agnostic with native file watching support on macOS (fswatch), Linux (inotifywait), and universal poll fallback.

## Next Phase Readiness
- Phase 13 complete, ready for Phase 14: Security Hardening
- No blockers or concerns

---
*Phase: 13-native-file-watcher*
*Completed: 2026-02-13*
