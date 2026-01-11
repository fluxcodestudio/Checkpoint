---
phase: 04-fallback-chain
plan: 02
subsystem: infra
tags: [queue, retry, offline, reliability, rclone]

# Dependency graph
requires:
  - phase: 04-01-fallback-detection
    provides: RCLONE_SYNC_PENDING export, three-tier fallback
provides:
  - File-based queue system for offline scenarios
  - enqueue_backup_sync(), process_backup_queue(), dequeue_entry()
  - Automatic retry with exponential backoff (max 5 retries)
  - Opportunistic queue processing on each backup run
affects: [backup-now, daemon]

# Tech tracking
tech-stack:
  added: []
  patterns: [file-based-queue, opportunistic-retry, background-processing]

key-files:
  created: [lib/backup-queue.sh]
  modified: [bin/backup-now.sh]

key-decisions:
  - "File-based queue with timestamp prefix for oldest-first processing"
  - "Max 5 retries before moving to .failed for manual review"
  - "Opportunistic processing (3 entries per backup run, non-blocking)"

patterns-established:
  - "Queue entry format: key=value pairs sourced directly"
  - "Background processing with & for non-blocking retry"

issues-created: []

# Metrics
duration: 3min
completed: 2026-01-11
---

# Phase 4 Plan 02: Local Queue for Offline Scenarios Summary

**File-based queue system with automatic retry for failed cloud syncs when connectivity restores**

## Performance

- **Duration:** 3 min
- **Started:** 2026-01-11T10:26:33Z
- **Completed:** 2026-01-11T10:29:33Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created lib/backup-queue.sh with complete queue infrastructure
- Queue entries use simple key=value format, sourced directly (no parsing overhead)
- Timestamp prefix ensures oldest-first processing
- Retry count with max 5 attempts before moving to .failed
- Integrated queue into backup-now.sh for automatic enqueue/process

## Task Commits

Each task was committed atomically:

1. **Task 1: Create queue infrastructure and enqueue function** - `738d411` (feat)
2. **Task 2: Add queue processor with retry on connectivity** - `e441fac` (feat)

**Plan metadata:** (pending)

## Files Created/Modified
- `lib/backup-queue.sh` - New file with queue management functions
- `bin/backup-now.sh` - Added queue integration for RCLONE_SYNC_PENDING

## Decisions Made
- File-based queue is simpler than database/JSON for bash (source files directly)
- Timestamp prefix ensures FIFO processing without sorting logic
- 5 retry max prevents infinite loops while preserving entries for manual review
- Non-blocking background processing prevents backup slowdown

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## Next Phase Readiness
- Phase 4 (Fallback Chain) complete
- Full reliability chain operational: cloud folder -> rclone API -> local queue
- Ready for Phase 5: Tiered Retention

---
*Phase: 04-fallback-chain*
*Completed: 2026-01-11*
