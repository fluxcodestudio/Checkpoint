---
phase: 14-security-hardening
plan: 02
subsystem: security
tags: [keychain, secret-tool, pass, credentials, database, platform-detection]

# Dependency graph
requires:
  - phase: 14-security-hardening
    provides: secure-download.sh module pattern, lib/security/ directory
  - phase: 11-modularize
    provides: module loader pattern, include guards
provides:
  - credential_store/credential_get/credential_delete API for OS-native secret storage
  - platform-aware backend detection (macOS Keychain, Linux secret-tool, Linux pass, env var)
  - opt-in credential integration in database backup flow
affects: [database-backup, install-setup, daemon]

# Tech tracking
tech-stack:
  added: [macOS security CLI, Linux secret-tool, Linux pass]
  patterns: [credential-provider-abstraction, opt-in-feature-flag, graceful-fallback-chain]

key-files:
  created: [lib/security/credential-provider.sh]
  modified: [lib/database-detector.sh, templates/backup-config.sh]

key-decisions:
  - "Env var fallback on all native backend failures — credential provider never blocks backups"
  - "Opt-in via CHECKPOINT_USE_CREDENTIAL_STORE config flag (default: false)"
  - "Standalone module sourced on-demand, not loaded by backup-lib.sh"

patterns-established:
  - "Credential provider pattern: detect backend → try native → fallback to env var"
  - "Opt-in feature flags in config template with clear documentation"

issues-created: []

# Metrics
duration: 3 min
completed: 2026-02-13
---

# Phase 14 Plan 02: Credential Provider Summary

**Platform-aware credential provider with macOS Keychain, Linux secret-tool/pass, and env var fallback — integrated opt-in into database backup flow**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-13T21:57:01Z
- **Completed:** 2026-02-13T22:00:30Z
- **Tasks:** 2/2
- **Files modified:** 3

## Accomplishments

- Created lib/security/credential-provider.sh (279 lines) with 5 public functions and 3 internal helpers
- Platform detection: macOS Keychain → Linux secret-tool → Linux pass → env var fallback
- Integrated credential store into PostgreSQL, MySQL, and MongoDB backup sections of database-detector.sh
- Added CHECKPOINT_USE_CREDENTIAL_STORE config option (default: false) for opt-in activation

## Task Commits

Each task was committed atomically:

1. **Task 1: Create credential provider module** - `a19dee0` (feat)
2. **Task 2: Integrate into database backup flow** - `242f737` (feat)

**Plan metadata:** (this commit) (docs: complete plan)

## Files Created/Modified

- `lib/security/credential-provider.sh` - Platform-aware credential store/get/delete with backend detection and graceful fallback
- `lib/database-detector.sh` - Added `_get_db_credential()` helper + 3 integration points (PostgreSQL, MySQL, MongoDB)
- `templates/backup-config.sh` - Added `CHECKPOINT_USE_CREDENTIAL_STORE` config option

## Decisions Made

- Env var fallback on all native backend failures — credential provider never blocks backups
- Opt-in via CHECKPOINT_USE_CREDENTIAL_STORE config flag (default: false) — zero disruption to existing users
- Standalone module sourced on-demand, not loaded by backup-lib.sh loader

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added env var fallback in credential_get() for all native backends**

- **Found during:** Task 1 (credential provider implementation)
- **Issue:** Plan specified backend-specific retrieval but didn't explicitly cover the case where native backend exists but fails silently (keychain locked, GPG agent down)
- **Fix:** Added env var check as last resort after any native backend failure — follows stated requirement that provider should NEVER block backup
- **Files modified:** lib/security/credential-provider.sh
- **Verification:** Backend detection works, fallback chain tested
- **Committed in:** a19dee0 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical), 0 deferred
**Impact on plan:** Auto-fix essential for reliability guarantee. No scope creep.

## Issues Encountered

None

## Next Phase Readiness

- Credential provider complete, ready for 14-03 (self-update integrity)
- All security module patterns established in lib/security/

---
*Phase: 14-security-hardening*
*Completed: 2026-02-13*
