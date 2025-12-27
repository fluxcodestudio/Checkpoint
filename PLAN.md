# Checkpoint v2.2.2 - Critical Fixes Plan

**Date:** 2025-12-26
**Version:** 2.2.1 → 2.2.2
**Scope:** Fix 23 identified issues across 5 severity categories

---

## Executive Summary

Critical system review identified bugs, edge cases, and architectural gaps that need addressing. This plan prioritizes fixes by severity and implements them systematically.

---

## Phase 1: Critical Bugs (Immediate)

### 1.1 Uninitialized Variable `backup_errors`
**File:** `bin/backup-now.sh`
**Problem:** Variable used at lines 423, 443, 447 without initialization
**Solution:** Add `backup_errors=0` initialization after `init_backup_state` call (line 405)
**Risk:** Script crash with `set -u`

### 1.2 Race Condition in Lock Acquisition
**File:** `bin/backup-daemon.sh`
**Problem:** Gap between `mkdir` and PID write allows race condition
**Solution:**
- Write PID to temp file first
- Atomically move into lock directory
- Or use `flock` if available
**Risk:** Duplicate backups, lock corruption

### 1.3 Temp File Cleanup on Failure
**File:** `bin/backup-daemon.sh`
**Problem:** SQLite temp backup left in `/tmp` if gzip fails
**Solution:**
- Use `mktemp` for secure temp file
- Add trap to clean up on exit/error
- Move cleanup to finally block
**Risk:** Sensitive data exposure in world-readable `/tmp`

---

## Phase 2: High Priority Issues

### 2.1 Database Backup Verification
**File:** `lib/database-detector.sh`
**Problem:** No verification that compressed backup is valid
**Solution:** Add `gunzip -t "$backup_file"` after each database backup
**Risk:** Corrupted backups undetected

### 2.2 Timestamp Collision Prevention
**File:** `bin/backup-now.sh`
**Problem:** Same-second backups overwrite each other
**Solution:** Add PID or random suffix: `${timestamp}_$$` or `${timestamp}_${RANDOM}`
**Risk:** Lost backup versions

### 2.3 File Size Limits
**Files:** `bin/backup-now.sh`, `templates/backup-config.sh`
**Problem:** Huge files (logs, videos) fill storage
**Solution:**
- Add `MAX_BACKUP_FILE_SIZE` config (default: 100MB)
- Skip files exceeding limit with warning
- Add `BACKUP_LARGE_FILES` override option
**Risk:** Storage exhaustion

### 2.4 Symlink Handling
**File:** `bin/backup-now.sh`
**Problem:** `cp` follows symlinks, can backup system files or loop
**Solution:**
- Use `cp -P` to not follow symlinks
- Or skip symlinks entirely with `-type f` (already in find)
- Add symlink detection and warning
**Risk:** Security issue, infinite loops

### 2.5 LaunchAgent Orphan Detection
**Files:** `bin/backup-daemon.sh`, `bin/uninstall.sh`
**Problem:** Deleted projects leave orphan LaunchAgents
**Solution:**
- Daemon checks if PROJECT_DIR exists, self-disables if not
- Uninstall removes all LaunchAgents for project
- Add `backup-cleanup --orphans` command
**Risk:** Wasted resources, error noise

---

## Phase 3: Medium Priority Issues

### 3.1 First Backup Detection Fix
**File:** `bin/backup-now.sh`
**Problem:** `.DS_Store` in empty directory breaks detection
**Solution:** Filter `.DS_Store` and other system files in emptiness check:
```bash
if [ -z "$(ls -A "$FILES_DIR" 2>/dev/null | grep -v '^\\.DS_Store$')" ]; then
```

### 3.2 Backup Configuration Self-Backup
**File:** `bin/backup-now.sh`
**Problem:** Deleted config = system breaks, no recovery
**Solution:** Always backup `.backup-config.sh` to `FILES_DIR/`

### 3.3 Database Exit Code Verification
**File:** `lib/database-detector.sh`
**Problem:** `pg_dump`/`mysqldump` failures not properly detected
**Solution:** Capture exit codes explicitly, fail on non-zero

### 3.4 UTC Timestamps for Consistency
**Files:** Multiple
**Problem:** Local time causes issues when traveling
**Solution:** Use `date -u` for all backup timestamps
**Note:** Keep human-readable local time in logs

---

## Phase 4: Testing Gaps

### 4.1 GitHub Auto-Push Tests
**Location:** `tests/integration/test-github-push.sh`
**Coverage:**
- Push with unpushed commits
- Push with no commits
- Push interval enforcement
- Authentication failure handling

### 4.2 Concurrent Backup Tests
**Location:** `tests/stress/test-concurrent-backups.sh`
**Coverage:**
- Two backups starting simultaneously
- Lock acquisition race
- Stale lock cleanup

### 4.3 Interrupted Backup Tests
**Location:** `tests/stress/test-interrupted-backup.sh`
**Coverage:**
- Kill during file copy
- Kill during database backup
- State consistency after crash

### 4.4 Multi-Database Tests
**Location:** `tests/integration/test-database-types.sh`
**Coverage:**
- PostgreSQL detection and backup
- MySQL detection and backup
- MongoDB detection and backup

### 4.5 Large File Tests
**Location:** `tests/stress/test-large-files.sh`
**Coverage:**
- Files > MAX_BACKUP_FILE_SIZE
- Binary file handling
- Very deep directory structures

---

## Phase 5: Architectural Improvements (v2.3 Candidates)

### 5.1 Additional Trigger Layers
**Options:**
- Git hooks (pre-commit, post-commit) - install by default
- File watcher (fswatch) - optional
- Shorter daemon interval (15 min option)

### 5.2 Health Monitoring
**Solution:**
- Heartbeat file updated on each backup
- Stale detection (no backup in 2+ hours)
- Notification on health issues
- `backup-status --health` command

### 5.3 Sensitive File Encryption
**Solution:**
- Optional encryption for cloud uploads
- Use `gpg` or `openssl` for `.env`, credentials
- Key management strategy

---

## Implementation Order

1. **Critical Bugs (Phase 1)** - Today
   - 1.1 → 1.2 → 1.3

2. **High Priority (Phase 2)** - Today
   - 2.1 → 2.2 → 2.3 → 2.4 → 2.5

3. **Medium Priority (Phase 3)** - Today
   - 3.1 → 3.2 → 3.3 → 3.4

4. **Testing (Phase 4)** - After fixes
   - Run existing tests
   - Add new test files

5. **Architecture (Phase 5)** - v2.3
   - Separate release

---

## Version Bump

After all Phase 1-3 fixes:
- Update VERSION to 2.2.2
- Update CHANGELOG.md
- Create git tag v2.2.2

---

## Files to Modify

| File | Changes |
|------|---------|
| `bin/backup-now.sh` | Bugs #1, #5, #6, #7, #9, #11 |
| `bin/backup-daemon.sh` | Bugs #2, #3, #8 |
| `lib/database-detector.sh` | Issues #4, #12 |
| `lib/backup-lib.sh` | Issue #13 (UTC timestamps) |
| `templates/backup-config.sh` | Issue #6 (MAX_FILE_SIZE) |
| `bin/uninstall.sh` | Issue #8 (orphan cleanup) |

---

## Rollback Plan

If issues arise:
1. Git revert to v2.2.1
2. Re-run global install
3. Document failure for fix

---

## Success Criteria

- [ ] All 3 critical bugs fixed
- [ ] All 5 high priority issues fixed
- [ ] All 5 medium priority issues fixed
- [ ] Existing tests pass (164/164)
- [ ] New tests added for GitHub push, concurrency
- [ ] Version bumped to 2.2.2
