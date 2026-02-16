---
phase: 13-native-file-watcher
plan: 01
subsystem: infra
tags: [bash, file-watcher, cross-platform, fswatch, inotifywait, poll]

# Dependency graph
requires:
  - phase: 12-bootstrap-deduplication
    provides: Shared bootstrap.sh pattern, SCRIPT_DIR/LIB_DIR exports
  - phase: 11-modularize-foundation
    provides: Module loader pattern, include guards
provides:
  - Cross-platform file watcher abstraction (lib/platform/file-watcher.sh)
  - Platform-agnostic backup-watcher.sh using unified watcher interface
  - Expanded exclude patterns (27 patterns, up from 14)
affects: [13-02-PLAN (session detection), 13-03-PLAN (hook removal)]

# Tech tracking
tech-stack:
  added: []
  patterns: [platform-wrapper, detect-and-dispatch, include-guard-standalone-module]

key-files:
  created: [lib/platform/file-watcher.sh]
  modified: [bin/backup-watcher.sh]

key-decisions:
  - "file-watcher.sh is standalone module, NOT loaded by backup-lib.sh loader"
  - "inotifywait uses close_write,create,delete,move (not modify) to avoid event storms"
  - "inotifywait patterns combined with | alternation in single --exclude flag"
  - "Poll fallback uses find -newer with RETURN trap cleanup"
  - "WATCHER_BACKEND global exported by start_watcher for consumer logging"

patterns-established:
  - "Platform wrapper: detect_watcher() -> start_watcher() dispatch to backend"
  - "lib/platform/ directory for platform-specific abstractions"
  - "check_watcher_available() for user-friendly install suggestions"

issues-created: []

# Metrics
duration: 5min
completed: 2026-02-13
---

# Phase 13 Plan 01: Cross-Platform File Watcher Summary

**Created lib/platform/file-watcher.sh abstraction layer; integrated into backup-watcher.sh replacing hardcoded fswatch; expanded exclude patterns from 14 to 27.**

## Performance

- **Duration:** 5 min
- **Completed:** 2026-02-13
- **Tasks:** 2
- **Files created:** 1
- **Files modified:** 1

## Accomplishments
- Created `lib/platform/file-watcher.sh` (277 lines) with 7 functions: `detect_watcher`, `_watcher_fswatch`, `_watcher_inotifywait`, `_build_inotify_exclude`, `_watcher_poll`, `start_watcher`, `check_watcher_available`
- Platform detection: fswatch (macOS), inotifywait (Linux), poll fallback (universal)
- Integrated platform wrapper into `bin/backup-watcher.sh` replacing all hardcoded fswatch logic
- Expanded DEFAULT_EXCLUDES from 14 to 27 patterns with category comments
- Removed FSWATCH_EXCLUDES loop and FSWATCH_PID; replaced with unified WATCHER_PID and start_watcher
- All code Bash 3.2 compatible (no associative arrays, mapfile, coproc, |&, ${var,,})

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lib/platform/file-watcher.sh** - `0452266` (feat)
2. **Task 2: Integrate platform watcher into backup-watcher.sh** - `7729b0d` (feat)

## Files Created/Modified
- `lib/platform/file-watcher.sh` - Cross-platform file watcher abstraction (277 lines, 7 functions)
- `bin/backup-watcher.sh` - Replaced hardcoded fswatch with platform wrapper, expanded excludes

## Decisions Made
- `lib/platform/file-watcher.sh` placed in new `lib/platform/` directory for platform-specific code
- Module is standalone (not loaded by backup-lib.sh) -- sourced directly by backup-watcher.sh
- `WATCHER_BACKEND` set as global variable by `start_watcher()` for consumer code to reference in logs
- Poll fallback includes find exclusions for .git, node_modules, .DS_Store, __pycache__, dist/, build/

## Deviations from Plan

None. Both tasks completed as specified.

## Verification Results

- `bash -n lib/platform/file-watcher.sh`: PASSED
- `bash -n bin/backup-watcher.sh`: PASSED
- `detect_watcher` returns correct backend (poll on this machine without fswatch)
- `_build_inotify_exclude "\.git" "node_modules" "dist/"` returns `(\.git|node_modules|dist/)`
- All 7 functions defined and accessible after source
- No FSWATCH_PID or FSWATCH_EXCLUDES references remain in backup-watcher.sh
- 27 exclude patterns present in DEFAULT_EXCLUDES
- WATCHER_EXCLUDES from config still appended correctly
- `check_watcher_available` provides platform-specific install suggestions

## Next Phase Readiness
- Plan 13-01 complete
- Ready for Plan 13-02: Session detection + interval pre-check migration from smart-backup-trigger.sh

---
*Phase: 13-native-file-watcher*
*Completed: 2026-02-13*
