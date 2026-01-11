---
phase: 05-tiered-retention
plan: 01
subsystem: backup
tags: [bash, retention, time-machine, tiered-storage, pruning]

# Dependency graph
requires:
  - phase: 01-cloud-destination
    provides: backup directory structure (files/, archived/, databases/)
provides:
  - Tiered retention policy engine (hourly/daily/weekly/monthly classification)
  - Pruning candidate identification for Time Machine-style snapshot management
  - Retention statistics and space savings calculation
affects: [05-02, 06-dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns: [tiered-retention, epoch-based-classification, group-by-key-keep-oldest]

key-files:
  created: [lib/retention-policy.sh]
  modified: []

key-decisions:
  - "Keep oldest snapshot per tier group (not newest) for better historical coverage"
  - "Use file mtime as fallback when timestamp not parseable from filename"
  - "Approximate months as 30 days for tier boundary calculations"

patterns-established:
  - "Tiered retention: hourly(24h) → daily(7d) → weekly(4w) → monthly(12m) → expired"
  - "Group key functions: get_day_key, get_week_key, get_month_key for tier grouping"

issues-created: []

# Metrics
duration: 2min
completed: 2026-01-11
---

# Phase 5 Plan 1: Retention Policy Engine Summary

**Time Machine-style tiered retention library with hourly/daily/weekly/monthly classification and pruning candidate identification**

## Performance

- **Duration:** 2 min
- **Started:** 2026-01-11T10:38:41Z
- **Completed:** 2026-01-11T10:40:46Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Created lib/retention-policy.sh with 9 functions for tiered retention management
- Tier classification: timestamps classified into hourly/daily/weekly/monthly/expired based on age
- Pruning logic: keeps oldest snapshot per tier group, identifies all others as prune candidates
- Statistics functions for retention distribution and space savings calculation

## Task Commits

Each task was committed atomically:

1. **Task 1: Create retention policy library with tier classification** - `4bbe05a` (feat)
2. **Task 2: Add pruning candidate identification functions** - `cc809c6` (feat)

**Plan metadata:** (pending)

## Files Created/Modified

- `lib/retention-policy.sh` - Tiered retention policy library with Time Machine-style snapshot management

### Functions Implemented

| Function | Purpose |
|----------|---------|
| `classify_retention_tier()` | Classify timestamp into hourly/daily/weekly/monthly/expired |
| `extract_timestamp()` | Parse timestamp from archived filename patterns |
| `get_day_key()` | Group by day (YYYYMMDD) |
| `get_week_key()` | Group by ISO week (YYYY-WXX) |
| `get_month_key()` | Group by month (YYYYMM) |
| `should_keep_as_representative()` | Determine if snapshot is tier representative |
| `find_tiered_pruning_candidates()` | Identify files eligible for pruning |
| `get_retention_stats()` | Return tier distribution statistics |
| `calculate_tiered_savings()` | Calculate bytes that would be freed |

## Decisions Made

- **Keep oldest per group:** When selecting tier representative, keep oldest snapshot (not newest) for better historical coverage
- **Fallback to mtime:** When timestamp can't be parsed from filename, use file modification time
- **Approximate months:** Use 30-day approximation for monthly tier boundaries (simpler than calendar months)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- Retention policy library ready for integration with cleanup.sh
- Ready for 05-02: Cleanup and pruning automation

---
*Phase: 05-tiered-retention*
*Completed: 2026-01-11*
