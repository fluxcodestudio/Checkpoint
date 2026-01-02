# Checkpoint v2.2.2 - Task List

**Status Key:** `[ ]` Pending | `[~]` In Progress | `[x]` Complete | `[-]` Skipped

---

## Phase 1: Critical Bugs

### Bug #1: Uninitialized `backup_errors`
- [x] Add `backup_errors=0` after line 405 in `bin/backup-now.sh`
- [x] Verify script runs without `set -u` errors

### Bug #2: Lock Race Condition
- [x] Modify lock acquisition in `bin/backup-daemon.sh`
- [x] Write PID atomically (temp file + rename)
- [x] Test concurrent execution

### Bug #3: Temp File Cleanup
- [x] Use `mktemp` for secure temp files in `bin/backup-daemon.sh`
- [x] Add trap for cleanup on EXIT/ERR
- [x] Verify cleanup on gzip failure

---

## Phase 2: High Priority Issues

### Issue #4: Database Verification
- [x] Add `gunzip -t` verification in `lib/database-detector.sh`
- [x] Add SQLite integrity check option
- [x] Log verification status

### Issue #5: Timestamp Collision
- [x] Add PID suffix to archive timestamps in `bin/backup-now.sh`
- [x] Update format: `${timestamp}_$$`
- [x] Verify no collisions in rapid succession

### Issue #6: File Size Limits
- [x] Add `MAX_BACKUP_FILE_SIZE=104857600` (100MB) to `templates/backup-config.sh`
- [x] Add size check in file backup loop
- [x] Log skipped large files with warning
- [x] Add `BACKUP_LARGE_FILES=false` override option

### Issue #7: Symlink Safety
- [x] Add symlink detection before copy
- [x] Skip symlinks with warning
- [x] Log symlink paths for user awareness

### Issue #8: LaunchAgent Orphans
- [x] Add project directory check at start of `bin/backup-daemon.sh`
- [x] Self-disable if project missing
- [x] Add orphan detection to `bin/uninstall.sh`
- [x] Clean up orphaned LaunchAgents

---

## Phase 3: Medium Priority Issues

### Issue #9: First Backup Detection
- [x] Filter `.DS_Store` from emptiness check
- [x] Use more robust empty directory detection

### Issue #11: Config Self-Backup
- [x] Add `.backup-config.sh` to critical files list
- [x] Ensure config backed up to `FILES_DIR/`

### Issue #12: Database Exit Codes
- [x] Add explicit exit code capture for pg_dump
- [x] Add explicit exit code capture for mysqldump
- [x] Add explicit exit code capture for mongodump
- [x] Fail backup on non-zero exit

### Issue #13: UTC Timestamps
- [x] Audit all timestamp usages
- [x] Add optional USE_UTC_TIMESTAMPS config
- [x] Keep human-readable local time as default

---

## Phase 4: Testing

### Test #14: GitHub Auto-Push
- [ ] Create `tests/integration/test-github-push.sh`
- [ ] Test push with commits
- [ ] Test push without commits
- [ ] Test interval enforcement

### Test #15: Concurrent Backups
- [ ] Create `tests/stress/test-concurrent-backups.sh`
- [ ] Test two simultaneous backup starts
- [ ] Verify lock prevents duplicates

### Test #16: Interrupted Backup
- [ ] Create `tests/stress/test-interrupted-backup.sh`
- [ ] Test kill during operation
- [ ] Verify state consistency

### Test #17: Multi-Database
- [ ] Create `tests/integration/test-database-types.sh`
- [ ] Mock PostgreSQL detection
- [ ] Mock MySQL detection
- [ ] Mock MongoDB detection

### Test #18: Large Files
- [ ] Create `tests/stress/test-large-files.sh`
- [ ] Test files > MAX_BACKUP_FILE_SIZE
- [ ] Verify skip behavior

---

## Phase 5: Finalization

### Version Update
- [x] Bump VERSION to 2.2.2
- [x] Update CHANGELOG.md
- [x] Update README.md version references
- [ ] Create git tag v2.2.2

### Issue #19: Bash 3.2 Compatibility (Added during audit)
- [x] Refactor `bin/checkpoint-dashboard.sh` to avoid `declare -A`
- [x] Use eval-based variable storage for status cache
- [x] Verify smoke tests pass on macOS default bash

### Global Installation Update
- [ ] Copy fixed files to `~/.local/lib/checkpoint/`
- [ ] Verify all commands work
- [ ] Run smoke tests

### Commit and Push
- [ ] Commit all changes
- [ ] Push to GitHub
- [ ] Verify CI passes (if applicable)

---

## Summary Progress

| Phase | Total | Complete | Remaining |
|-------|-------|----------|-----------|
| Critical (P1) | 7 | 7 | 0 |
| High (P2) | 12 | 12 | 0 |
| Medium (P3) | 8 | 8 | 0 |
| Testing (P4) | 11 | 0 | 11 |
| Final (P5) | 10 | 6 | 4 |
| **TOTAL** | **48** | **33** | **15** |

---

## Notes

- ✅ Phase 1-3 COMPLETE (all code fixes done)
- ✅ Issue #19 (Bash 3.2 compatibility) FIXED during comprehensive audit
- ✅ README.md version updated to 2.2.2
- Phase 4 tests can be added after fixes verified manually
- Phase 5 finalizes release (commit/push remaining)
