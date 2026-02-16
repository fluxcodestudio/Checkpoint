---
phase: 08-monitoring-enhancements
plan: 02
subsystem: monitoring
tags: [bash, dashboard, error-panel, health-trends, recovery]

requires:
  - phase: 08-01
    provides: Error code system with get_error_description(), get_error_suggestion()
  - phase: 06-02
    provides: Dashboard table display patterns
provides:
  - Error details panel with codes, descriptions, file paths, and fix suggestions
  - Quick-fix commands generated from error categories
  - Health trend indicators (improving/stable/declining)
  - Verbose mode with trend column
affects: [configuration-ux, future-alerting]

tech-stack:
  added: []
  patterns: [grep-based JSON parsing, trend calculation from logs]

key-files:
  created: []
  modified:
    - lib/global-status.sh
    - bin/backup-dashboard.sh

key-decisions:
  - "Pure bash JSON parsing via grep/sed instead of jq dependency"
  - "Trend based on success/failure ratio from backup.log"

patterns-established:
  - "Error panel pattern: code + description + file + fix"
  - "Quick-fix generation from error category prefixes (EPERM, EDISK, ECONF, EDB)"

issues-created: []

duration: 4min
completed: 2026-01-12
---

# Phase 8 Plan 2: Dashboard Error Panel and Health Trends Summary

**Enhanced dashboard with error details panel, quick-fix commands, and health trend indicators for self-service recovery**

## Performance

- **Duration:** 4 min
- **Started:** 2026-01-12T01:48:19Z
- **Completed:** 2026-01-12T01:52:43Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Error details panel shows codes, descriptions, file paths, and fix suggestions
- Quick-fix commands generated based on error category (permissions, disk, config, database)
- Health trend calculation from backup history (improving/stable/declining)
- Trend column in verbose mode with arrow indicators (↗/→/↘)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add error details panel to dashboard** - `436e762` (feat)
2. **Task 2: Add quick-fix commands and health trends** - `ce96f9a` (feat)

## Files Created/Modified

- `lib/global-status.sh` - Added get_project_backup_dir(), get_project_errors(), exports
- `bin/backup-dashboard.sh` - Added display_error_panel(), display_quick_fixes(), get_project_health_trend(), format_health_trend(), verbose mode trend column

## Decisions Made

- Used pure bash string parsing (grep/sed) for JSON extraction instead of jq dependency
- Health trend calculation based on success/failure ratio in backup.log
- Error categories mapped to fix commands: EPERM→chmod, EDISK→df/cleanup, ECONF→init, EDB→reinit

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## Next Phase Readiness

- Dashboard now provides actionable recovery guidance
- Ready for 08-03-PLAN.md (Configurable alerts and quiet hours)
- Error code system from 08-01 fully integrated with dashboard

---
*Phase: 08-monitoring-enhancements*
*Completed: 2026-01-12*
