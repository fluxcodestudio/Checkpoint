---
phase: 08-monitoring-enhancements
plan: 01
subsystem: monitoring
tags: [error-codes, notifications, bash]

# Dependency graph
requires:
  - phase: 06
    provides: notification system, backup-state.json structure
provides:
  - Standardized error code catalog (18 codes)
  - Error-to-code mapping function
  - Actionable fix suggestions in notifications
affects: [dashboard, alerts]

# Tech tracking
tech-stack:
  added: []
  patterns: [error-code-catalog, fix-suggestion-mapping]

key-files:
  created: []
  modified: [lib/backup-lib.sh, bin/backup-now.sh]

key-decisions:
  - "Bash 3.2 compatible: indexed arrays with pipe-delimited format instead of associative arrays"
  - "18 error codes covering 6 categories: PERM, DISK, CONF, DB, NET, FILE"

patterns-established:
  - "Error code format: E{CATEGORY}{NUMBER} (e.g., EPERM001, EDISK002)"
  - "Backward compatibility via map_error_to_code() for legacy error strings"

issues-created: []

# Metrics
duration: 4min
completed: 2026-01-12
---

# Phase 8 Plan 01: Structured Error Codes Summary

**18 categorized error codes with actionable fix suggestions in failure notifications**

## Performance

- **Duration:** 4 min
- **Started:** 2026-01-12T01:42:03Z
- **Completed:** 2026-01-12T01:46:34Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Error code catalog with 18 codes across 6 categories (EPERM, EDISK, ECONF, EDB, ENET, EFILE)
- Helper functions: `get_error_description()`, `get_error_suggestion()`, `format_error_with_fix()`, `map_error_to_code()`
- Notifications now include actionable fix suggestions (truncated for display)
- Backward compatible with existing error strings via mapping function

## Task Commits

1. **Task 1: Create error code catalog with fix suggestions** - `3bb9e13` (feat)
2. **Task 2: Integrate error codes into failure tracking** - `2402b24` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `lib/backup-lib.sh` - Added ERROR_CATALOG array and helper functions, updated notify_backup_failure()
- `bin/backup-now.sh` - Updated all add_file_failure() calls to use standardized error codes

## Decisions Made

- Used bash 3.2-compatible indexed arrays with pipe-delimited format (CODE|DESC|FIX) instead of associative arrays
- Truncate fix suggestions in notifications (50 chars first failure, 40 chars escalation) to fit macOS notification limits

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## Next Phase Readiness

- Error code system operational
- Ready for 08-02: Dashboard error panel and health trends
- Error codes can be displayed in dashboard failures list

---
*Phase: 08-monitoring-enhancements*
*Completed: 2026-01-12*
