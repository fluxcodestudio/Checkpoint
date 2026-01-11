# Checkpoint v2.3.0 - Complete Task List

**Status Key:** `[ ]` Pending | `[~]` In Progress | `[x]` Complete | `[-]` Skipped

---

## Previously Completed (v2.2.2)

### Phase 1-3: Bug Fixes (DONE)
- [x] Bug #1: backup_errors initialization
- [x] Bug #2: Lock race condition
- [x] Bug #3: Temp file cleanup
- [x] Issue #4: Database verification
- [x] Issue #5: Timestamp collision
- [x] Issue #6: File size limits
- [x] Issue #7: Symlink safety
- [x] Issue #8: LaunchAgent orphans
- [x] Issue #9: First backup detection
- [x] Issue #11: Config self-backup
- [x] Issue #12: Database exit codes
- [x] Issue #13: UTC timestamps

---

## Phase 1: Claude Code Skills (CRITICAL)

### 1.1 checkpoint skill
- [ ] Create `.claude/skills/checkpoint/` directory
- [ ] Create `skill.json` with metadata
- [ ] Create `run.sh` that launches dashboard

### 1.2 backup-update skill
- [ ] Create `.claude/skills/backup-update/` directory
- [ ] Create `skill.json` with metadata
- [ ] Create `run.sh` that updates system

### 1.3 backup-pause skill
- [ ] Create `.claude/skills/backup-pause/` directory
- [ ] Create `skill.json` with metadata
- [ ] Create `run.sh` for pause/resume

### 1.4 uninstall skill
- [ ] Create `.claude/skills/uninstall/` directory
- [ ] Create `skill.json` with metadata
- [ ] Create `run.sh` that uninstalls

---

## Phase 2: Test Suite (HIGH)

### 2.1 GitHub Push Tests
- [ ] Create `tests/integration/test-github-push.sh`
- [ ] Test push with commits
- [ ] Test push without commits
- [ ] Test interval enforcement
- [ ] Test auth failure handling

### 2.2 Concurrent Backup Tests
- [ ] Create `tests/stress/test-concurrent-backups.sh`
- [ ] Test simultaneous backup start
- [ ] Test lock acquisition
- [ ] Test stale lock cleanup
- [ ] Test PID file validation

### 2.3 Interrupted Backup Tests
- [ ] Create `tests/stress/test-interrupted-backup.sh`
- [ ] Test kill during file copy
- [ ] Test kill during DB backup
- [ ] Test state consistency
- [ ] Test partial file cleanup

### 2.4 Database Type Tests
- [ ] Create `tests/integration/test-database-types.sh`
- [ ] Test SQLite detection
- [ ] Test PostgreSQL detection (mock)
- [ ] Test MySQL detection (mock)
- [ ] Test MongoDB detection (mock)
- [ ] Test backup verification

### 2.5 Large File Tests
- [ ] Create `tests/stress/test-large-files.sh`
- [ ] Test files > 100MB
- [ ] Test skip behavior with warning
- [ ] Test BACKUP_LARGE_FILES override
- [ ] Test deep directory structures

---

## Phase 3: Version Consistency (HIGH)

- [ ] Verify VERSION = 2.3.0
- [ ] Add v2.3.0 section to CHANGELOG.md
- [ ] Update README.md version references
- [ ] Update any hardcoded versions in scripts

---

## Phase 4: Cloud Backup Rotation (MEDIUM)

### 4.1 Implement retention
- [ ] Add CLOUD_RETENTION_DAYS to templates/backup-config.sh
- [ ] Implement rotation in lib/cloud-backup.sh
- [ ] Delete old cloud backups after retention period
- [ ] Add minimum backup count protection

### 4.2 Add cleanup command
- [ ] Add --cloud flag to bin/backup-cleanup.sh
- [ ] Implement cloud cleanup logic
- [ ] Add dry-run support for cloud cleanup
- [ ] Show statistics on space reclaimed

---

## Phase 5: Installer Robustness (MEDIUM)

### 5.1 Rollback mechanism
- [ ] Backup existing installation before upgrade
- [ ] Implement rollback on failure
- [ ] Add clear error messages with recovery steps

### 5.2 PATH validation
- [ ] Check if ~/.local/bin is in PATH
- [ ] Provide shell-specific instructions if missing
- [ ] Verify commands accessible after install

### 5.3 Dependency checks
- [ ] Validate each dependency installed correctly
- [ ] Fail fast with clear message
- [ ] Suggest brew/apt installation commands

---

## Phase 6: Verification Tests (HIGH)

### 6.1 Verify v2.2.2 fixes work
- [ ] Test backup_errors initialization (set -u)
- [ ] Test atomic lock mechanism (concurrent start)
- [ ] Test temp file cleanup (simulate failure)
- [ ] Test database verification (gunzip -t)
- [ ] Test timestamp collision (rapid backups)
- [ ] Test symlink handling (create and skip)
- [ ] Test orphan detection (remove project dir)
- [ ] Test .DS_Store filtering (empty dir check)
- [ ] Test config self-backup (verify in backup)
- [ ] Test UTC timestamps (USE_UTC_TIMESTAMPS=true)

---

## Phase 7: Finalization

- [ ] Run full test suite (all existing + new)
- [ ] Update documentation for new features
- [ ] Copy to global installation
- [ ] Git commit all changes
- [ ] Push to GitHub
- [ ] Create git tag v2.3.0

---

## Summary Progress

| Phase | Total | Complete | Remaining |
|-------|-------|----------|-----------|
| Previous (v2.2.2) | 12 | 12 | 0 |
| Skills (P1) | 12 | 0 | 12 |
| Tests (P2) | 22 | 0 | 22 |
| Versions (P3) | 4 | 0 | 4 |
| Cloud (P4) | 8 | 0 | 8 |
| Installer (P5) | 9 | 0 | 9 |
| Verification (P6) | 10 | 0 | 10 |
| Final (P7) | 6 | 0 | 6 |
| **TOTAL** | **83** | **12** | **71** |

---

## Notes

- v2.2.2 bug fixes already implemented and pushed
- Focus now on completing missing components
- Skills are CRITICAL - Claude Code integration broken without them
- Phase 4 tests validate all claimed fixes
