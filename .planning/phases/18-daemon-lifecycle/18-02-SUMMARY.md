---
phase: 18-daemon-lifecycle
plan: 02
subsystem: daemon
tags: [staleness-detection, notifications, cooldown, watchdog, health-monitoring]

# Dependency graph
requires:
  - phase: 18-daemon-lifecycle
    provides: atomic heartbeat writes and watchdog self-heartbeat (18-01)
  - phase: 13-native-file-watcher
    provides: projects-registry.sh and list_projects()
  - phase: 15-linux-systemd-support
    provides: cross-platform notifications via compat.sh
provides:
  - Per-project backup staleness detection with tiered severity
  - Notification cooldown system preventing alert fatigue
  - Reusable should_notify() cooldown function
affects: [18-03-service-templates]

# Tech tracking
tech-stack:
  added: []
  patterns: [tiered-notification-with-cooldown, per-severity-state-files]

key-files:
  created: []
  modified: [bin/checkpoint-watchdog.sh]

key-decisions:
  - "Cooldown tracked via state files in ~/.checkpoint/notify-cooldown/ for persistence across restarts"
  - "Warning cooldown 4h, critical cooldown 2h — escalating urgency = shorter cooldown"
  - "Daemon restart notifications NOT cooldown-gated — always immediate"
  - "Staleness check every 5 minutes via loop counter, not every 60s heartbeat cycle"

patterns-established:
  - "Notification cooldown: per-severity per-context state files with timestamp comparison"
  - "Tiered health: reuse existing HEALTH_WARNING_HOURS/HEALTH_ERROR_HOURS thresholds"

issues-created: []

# Metrics
duration: 4min
completed: 2026-02-14
---

# Phase 18 Plan 02: Backup Staleness Notifications Summary

**Per-project backup staleness detection with tiered warning/critical notifications and anti-fatigue cooldown system in checkpoint-watchdog**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-14T05:10:11Z
- **Completed:** 2026-02-14T05:13:53Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Watchdog now monitors all registered projects for backup staleness using existing health thresholds
- Tiered notifications: warning (>24h) and critical (>72h) with severity-appropriate messaging
- Notification cooldown prevents alert fatigue: 4h for warnings, 2h for critical
- Cooldown state persists across watchdog restarts via state files

## Task Commits

Each task was committed atomically:

1. **Task 2: Add notification cooldown system** - `b0238b1` (feat) — implemented first for dependency ordering
2. **Task 1: Add per-project backup staleness detection** - `f682720` (feat)

## Files Created/Modified
- `bin/checkpoint-watchdog.sh` - Added staleness detection, cooldown system, library sources, main loop integration

## Decisions Made
- Implemented cooldown system (Task 2) before staleness detection (Task 1) for dependency ordering — should_notify() must be defined before main loop calls it
- Reused existing `get_project_health()` and `list_projects()` rather than duplicating health logic

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## Next Phase Readiness
- Staleness detection and notification foundation complete
- Ready for 18-03 (service template KeepAlive fix + auto-start on install)

---
*Phase: 18-daemon-lifecycle*
*Completed: 2026-02-14*
