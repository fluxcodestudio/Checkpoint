---
phase: 14-security-hardening
plan: 01
subsystem: security
tags: [sha256, curl, rclone, download-verification, supply-chain]

# Dependency graph
requires:
  - phase: 11-modularize
    provides: module loader pattern, include guards, _CHECKPOINT_LIB_DIR resolution
  - phase: 12-bootstrap
    provides: bootstrap.sh SCRIPT_DIR/LIB_DIR exports
provides:
  - lib/security/secure-download.sh module with compute_sha256, download_and_verify, download_with_checksums, secure_install_rclone
  - All rclone installations use SHA256-verified download pattern
affects: [14-03-self-update-integrity, security-hardening]

# Tech tracking
tech-stack:
  added: []
  patterns: [download-verify-execute, GPG-clearsigned-checksum-parsing, cross-platform-sha256]

key-files:
  created: [lib/security/secure-download.sh]
  modified: [lib/dependency-manager.sh, lib/cloud-backup.sh, bin/backup-cloud-config.sh]

key-decisions:
  - "SHA256 only (no GPG) for v1 — keeps implementation simple, covers MITM/truncation attacks"
  - "Standalone module loaded on-demand — not added to backup-lib.sh loader, sourced inside install_rclone functions"
  - "Homebrew path preserved for macOS — already safe via package manager verification"
  - "Fallback install to ~/.local/bin when sudo unavailable — with PATH warning"

patterns-established:
  - "download-verify-execute: always download to temp, verify hash, then move to target"
  - "GPG clearsigned stripping: sed pattern to extract checksums from GPG-wrapped SHA256SUMS files"

issues-created: []

# Metrics
duration: 3min
completed: 2026-02-13
---

# Phase 14 Plan 01: Secure Download Library Summary

**Created lib/security/secure-download.sh with SHA256 download verification and migrated all 3 curl|bash rclone installations to download-verify-execute pattern**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-13T21:50:09Z
- **Completed:** 2026-02-13T21:53:29Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Created new lib/security/secure-download.sh module with 4 functions: compute_sha256, download_and_verify, download_with_checksums, secure_install_rclone
- Eliminated all 3 curl|bash rclone installation patterns (including 1 curl|sudo bash) across dependency-manager.sh, cloud-backup.sh
- Updated manual install suggestions from curl|bash commands to rclone.org website URLs
- Preserved Homebrew installation path for macOS (already safe via package manager)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lib/security/secure-download.sh module** - `bbc1716` (feat)
2. **Task 2: Replace all curl|bash rclone patterns with secure installer** - `d3ebc59` (feat)

**Plan metadata:** `19f5b28` (docs: complete plan)

## Files Created/Modified
- `lib/security/secure-download.sh` - New security module: SHA256 verification, secure download, rclone installer
- `lib/dependency-manager.sh` - Replaced 2 curl|bash lines with secure_install_rclone, updated manual install suggestion
- `lib/cloud-backup.sh` - Replaced 2 curl|bash lines with secure_install_rclone, kept Homebrew path
- `bin/backup-cloud-config.sh` - Updated fallback install message to website URL

## Decisions Made
- SHA256 only (no GPG) for v1 — keeps implementation simple while covering MITM and truncation attacks
- Module loaded on-demand inside install_rclone() — not added to global backup-lib.sh loader
- Homebrew path preserved for macOS — package manager already provides verification
- Install fallback to ~/.local/bin when sudo unavailable — with PATH warning to user

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## Next Phase Readiness
- Secure download pattern established and available for 14-03 (self-update integrity)
- All rclone installations now verified — supply chain attack surface eliminated
- Ready for 14-02 (credential provider abstraction)

---
*Phase: 14-security-hardening*
*Completed: 2026-02-13*
