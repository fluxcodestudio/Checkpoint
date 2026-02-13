---
phase: 12-bootstrap-deduplication
plan: 01
subsystem: infra
tags: [bash, bootstrap, symlink-resolution, deduplication]

# Dependency graph
requires:
  - phase: 11-modularize-foundation
    provides: Thin module loader pattern, include guards
provides:
  - Shared bin/bootstrap.sh for script initialization
  - 17 migrated scripts using standardized bootstrap
  - Global install symlink support for bootstrap.sh
affects: [native-file-watcher, linux-systemd-support]

# Tech tracking
tech-stack:
  added: []
  patterns: [bootstrap-pattern, BASH_SOURCE-1-caller-resolution]

key-files:
  created: [bin/bootstrap.sh]
  modified: [bin/install-global.sh, bin/uninstall-global.sh, bin/backup-all-projects.sh, bin/backup-cleanup.sh, bin/backup-cloud-config.sh, bin/backup-config.sh, bin/backup-daemon.sh, bin/backup-failures.sh, bin/backup-now.sh, bin/backup-pause.sh, bin/backup-restore.sh, bin/backup-scan-malware.sh, bin/backup-status.sh, bin/backup-update.sh, bin/backup-watch.sh, bin/backup-watcher.sh, bin/install-integrations.sh, bin/install-skills.sh, bin/smart-backup-trigger.sh]

key-decisions:
  - "BASH_SOURCE[1] resolves caller through symlinks — key trick eliminating duplication"
  - "bootstrap.sh lives in bin/ alongside scripts it bootstraps"
  - "17 scripts migrated (not 18 — checkpoint-watchdog.sh had no symlink pattern)"

patterns-established:
  - "Bootstrap pattern: source \"$(dirname \"${BASH_SOURCE[0]}\")/bootstrap.sh\" as first init line"
  - "Exports SCRIPT_DIR, LIB_DIR, PROJECT_ROOT after symlink resolution"

issues-created: []

# Metrics
duration: 7min
completed: 2026-02-13
---

# Phase 12 Plan 01: Bootstrap Deduplication Summary

**Extracted duplicated symlink resolution into shared bin/bootstrap.sh; migrated 17 scripts, eliminating ~154 lines of boilerplate**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-13T06:48:00Z
- **Completed:** 2026-02-13T06:55:09Z
- **Tasks:** 2
- **Files modified:** 20

## Accomplishments
- Created `bin/bootstrap.sh` (36 lines) with `BASH_SOURCE[1]` caller resolution, include guard, and `SCRIPT_DIR`/`LIB_DIR`/`PROJECT_ROOT` exports
- Migrated 17 bin/ scripts from duplicated symlink resolution to single bootstrap source line
- Updated install-global.sh and uninstall-global.sh for bootstrap.sh symlink support
- Eliminated ~211 lines of duplicated boilerplate (net ~154 lines saved)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create bootstrap.sh and update install/uninstall** - `269f205` (feat)
2. **Task 2: Migrate 17 bin/ scripts to shared bootstrap** - `dfde41f` (feat)

## Files Created/Modified
- `bin/bootstrap.sh` - Shared script initialization (36 lines, include guard, symlink resolution)
- `bin/install-global.sh` - Added bootstrap.sh symlink creation
- `bin/uninstall-global.sh` - Added bootstrap.sh to removal list
- `bin/backup-all-projects.sh` - Migrated to bootstrap
- `bin/backup-cleanup.sh` - Migrated to bootstrap
- `bin/backup-cloud-config.sh` - Migrated to bootstrap
- `bin/backup-config.sh` - Migrated to bootstrap
- `bin/backup-daemon.sh` - Migrated to bootstrap (+ removed redundant LIB_DIR reassignment)
- `bin/backup-failures.sh` - Migrated to bootstrap
- `bin/backup-now.sh` - Migrated to bootstrap
- `bin/backup-pause.sh` - Migrated to bootstrap
- `bin/backup-restore.sh` - Migrated to bootstrap
- `bin/backup-scan-malware.sh` - Migrated to bootstrap
- `bin/backup-status.sh` - Migrated to bootstrap (+ removed SCRIPT_DIR reassignment in cloud section)
- `bin/backup-update.sh` - Migrated to bootstrap
- `bin/backup-watch.sh` - Migrated to bootstrap
- `bin/backup-watcher.sh` - Migrated to bootstrap
- `bin/install-integrations.sh` - Migrated to bootstrap
- `bin/install-skills.sh` - Migrated to bootstrap
- `bin/smart-backup-trigger.sh` - Migrated to bootstrap

## Decisions Made
- `BASH_SOURCE[1]` used to resolve the caller (not `BASH_SOURCE[0]`) — this is the key trick that makes shared bootstrap work
- bootstrap.sh placed in `bin/` alongside scripts (not `lib/`) for simple relative sourcing
- 17 scripts migrated instead of planned 18 — checkpoint-watchdog.sh had no symlink resolution pattern to replace

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] checkpoint-watchdog.sh has no symlink pattern**
- **Found during:** Task 2 (script migration)
- **Issue:** Plan listed 18 scripts but checkpoint-watchdog.sh uses hardcoded `$HOME/.local/bin/checkpoint` paths, not the symlink resolution pattern
- **Fix:** Skipped migration (nothing to replace). 17 scripts migrated instead of 18.
- **Verification:** Script unchanged, no regression

**2. [Rule 1 - Bug] Removed redundant LIB_DIR reassignment in backup-daemon.sh**
- **Found during:** Task 2 (backup-daemon.sh migration)
- **Issue:** Line 70 had `LIB_DIR="$SCRIPT_DIR/../lib"` which would override bootstrap's pwd-normalized value
- **Fix:** Removed redundant line, updated CLOUD_LIB to use bootstrap-provided `$LIB_DIR`
- **Verification:** bash -n passes, script works correctly

**3. [Rule 1 - Bug] Removed SCRIPT_DIR reassignment in backup-status.sh**
- **Found during:** Task 2 (backup-status.sh migration)
- **Issue:** Cloud status section had `SCRIPT_DIR="$(dirname "$0")"` that would override bootstrap's symlink-resolved value, breaking global installs
- **Fix:** Replaced with direct `$LIB_DIR` reference
- **Verification:** bash -n passes, --help works

**4. [Rule 1 - Bug] backup-watch.sh/backup-watcher.sh reclassified**
- **Found during:** Task 2 (script categorization)
- **Issue:** Plan categorized these as Category A (backup-lib.sh), but they source config files
- **Fix:** Treated as Category B (replace symlink block only) — correct behavior
- **Verification:** Both scripts work correctly

---

**Total deviations:** 4 auto-fixed (all Rule 1 - bugs/corrections)
**Impact on plan:** All corrections necessary for accuracy. No scope creep.

## Issues Encountered
None — all deviations were minor corrections handled inline.

## Next Phase Readiness
- Phase 12 complete — all 1 plan executed
- Shared bootstrap pattern established for all future bin/ scripts
- Ready for Phase 13: Native File Watcher Daemon

---
*Phase: 12-bootstrap-deduplication*
*Completed: 2026-02-13*
