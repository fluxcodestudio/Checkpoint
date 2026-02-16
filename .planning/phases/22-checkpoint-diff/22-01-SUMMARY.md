---
phase: 22-checkpoint-diff
plan: 01
subsystem: backup-diff
tags: [rsync, diff, bash, retention, backup-discovery]

requires:
  - phase: 21-storage-warnings
    provides: pre-flight gate check pattern in backup pipeline
provides:
  - Core diff library (discover_snapshots, compare_current_to_backup, format_diff_text/json, get_file_at_snapshot)
  - Fixed extract_timestamp() supporting all timestamp patterns
  - Centralized backup excludes via get_backup_excludes()
affects: [22-checkpoint-diff-plan-02, backup-now]

tech-stack:
  added: []
  patterns: [rsync dry-run itemize-changes parsing, global array return pattern for bash functions]

key-files:
  created: [lib/features/backup-diff.sh]
  modified: [lib/retention-policy.sh, lib/core/config.sh]

key-decisions:
  - "Used relative BASH_SOURCE path for config sourcing instead of _CHECKPOINT_LIB_DIR (inconsistent fallback values)"

patterns-established:
  - "Global DIFF_ADDED/DIFF_MODIFIED/DIFF_REMOVED arrays as function return interface (bash can't return arrays)"
  - "rsync --itemize-changes parsing pattern for file comparison"

issues-created: []

duration: 4min
completed: 2026-02-16
---

# Phase 22 Plan 01: Core Diff Library Summary

**Fixed extract_timestamp() 3-pattern bug, centralized backup excludes in config.sh, and built backup-diff.sh with rsync dry-run comparison and restic-style formatting**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-16T23:25:09Z
- **Completed:** 2026-02-16T23:29:14Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Fixed extract_timestamp() to handle `.YYYYMMDD_HHMMSS` pattern (no PID) — 11 of 62 archived files were affected
- Added get_backup_excludes() to config.sh — 9 standard exclude patterns for rsync
- Created backup-diff.sh library with 5 functions: discover_snapshots, compare_current_to_backup, format_diff_text, format_diff_json, get_file_at_snapshot

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix extract_timestamp() bug and centralize backup excludes** - `a796ec1` (fix)
2. **Task 2: Create backup-diff.sh library with core diff functions** - `822ed1c` (feat)

**Plan metadata:** (pending)

## Files Created/Modified
- `lib/retention-policy.sh` - Added no-PID timestamp pattern between existing patterns
- `lib/core/config.sh` - Added get_backup_excludes() function returning 9 --exclude args
- `lib/features/backup-diff.sh` - New 310-line library with 5 core diff functions

## Decisions Made
- Used relative BASH_SOURCE path for config sourcing in backup-diff.sh instead of _CHECKPOINT_LIB_DIR — the variable has inconsistent fallback values across lib/core/ vs lib/features/

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Config sourcing path**
- **Found during:** Task 2 (backup-diff.sh creation)
- **Issue:** _CHECKPOINT_LIB_DIR resolves differently in lib/core/ vs lib/features/ contexts
- **Fix:** Used `$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/config.sh` for reliable sourcing
- **Files modified:** lib/features/backup-diff.sh
- **Verification:** Source succeeds in both standalone and loader-sourced contexts
- **Committed in:** 822ed1c (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (blocking), 0 deferred
**Impact on plan:** Minor sourcing path adjustment, no scope creep.

## Issues Encountered
None

## Next Phase Readiness
- All 5 library functions ready for CLI wiring in Plan 02
- discover_snapshots, compare_current_to_backup, format_diff_text/json, get_file_at_snapshot all verified
- No blockers

---
*Phase: 22-checkpoint-diff*
*Completed: 2026-02-16*
