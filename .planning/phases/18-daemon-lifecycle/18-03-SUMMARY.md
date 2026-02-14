---
phase: 18-daemon-lifecycle
plan: 03
subsystem: daemon
tags: [launchd, plist, keepalive, auto-start, install, watchdog]

# Dependency graph
requires:
  - phase: 18-daemon-lifecycle
    provides: atomic heartbeat writes (18-01), staleness notifications (18-02)
  - phase: 15-linux-systemd-support
    provides: daemon-manager.sh install_daemon/start_daemon API
provides:
  - KeepAlive/SuccessfulExit=false plist pattern allowing clean daemon stops
  - Auto-start on install for immediate backup protection
  - Watchdog installation in install-global.sh
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [launchd-successfulexit-keepalive, auto-start-after-install]

key-files:
  created: []
  modified: [templates/com.checkpoint.watchdog.plist, templates/launchd-watcher.plist, bin/install-global.sh, bin/install.sh]

key-decisions:
  - "SuccessfulExit=false instead of bare KeepAlive=true — allows intentional stops"
  - "No ThrottleInterval added — launchd default 10s matches systemd RestartSec=10s"
  - "Auto-start failures are non-critical — RunAtLoad catches on next login"

patterns-established:
  - "launchd KeepAlive: use SuccessfulExit=false dict, never bare true"
  - "Install scripts: always start_daemon after install_daemon for immediate activation"

issues-created: []

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 18 Plan 03: Service Template Fixes + Auto-Start Summary

**KeepAlive/SuccessfulExit=false in plist templates for clean daemon stops, plus auto-start in install scripts for immediate backup protection**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T05:14:48Z
- **Completed:** 2026-02-14T05:16:40Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Both plist templates now use SuccessfulExit=false — intentional stops (exit 0) no longer trigger auto-restart
- install-global.sh now installs AND starts both global daemon and watchdog
- install.sh starts per-project daemon and watcher immediately after registration
- No reboot needed for backup protection to begin

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix KeepAlive in plist templates** - `26eac70` (feat)
2. **Task 2: Add auto-start to install scripts** - `f657e78` (feat)

## Files Created/Modified
- `templates/com.checkpoint.watchdog.plist` - KeepAlive changed to SuccessfulExit=false dict
- `templates/launchd-watcher.plist` - KeepAlive changed to SuccessfulExit=false dict
- `bin/install-global.sh` - Added watchdog installation + auto-start both services
- `bin/install.sh` - Added auto-start daemon and watcher after registration

## Decisions Made
- No ThrottleInterval added — launchd's default 10s throttle is sufficient and matches systemd's RestartSec=10s
- Auto-start failures treated as non-critical (⚠️ message) — RunAtLoad will catch on next login

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## Next Phase Readiness
- Phase 18 complete — all 3 plans done
- v2.5 Architecture & Independence milestone complete — all 8 phases (11-18) finished

---
*Phase: 18-daemon-lifecycle*
*Completed: 2026-02-14*
