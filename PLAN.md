# Checkpoint v2.3.0 - Comprehensive Completion Plan

**Date:** 2025-12-27
**Version:** 2.2.2 → 2.3.0
**Scope:** Complete all gaps, create missing components, verify fixes

---

## Executive Summary

Comprehensive audit revealed critical gaps in the system:
- 4 missing Claude Code skills
- 5 missing Phase 4 test files
- Version inconsistencies
- Cloud backup rotation not implemented
- Installer lacking robustness
- Fixes claimed but unverified

This plan addresses ALL gaps to achieve production-ready status.

---

## Phase 1: Missing Claude Code Skills (CRITICAL)

### 1.1 Create checkpoint skill
**Location:** `.claude/skills/checkpoint/`
**Files:**
- `skill.json` - Skill metadata and configuration
- `run.sh` - Execute checkpoint dashboard

### 1.2 Create backup-update skill
**Location:** `.claude/skills/backup-update/`
**Files:**
- `skill.json` - Skill metadata
- `run.sh` - Update backup system to latest version

### 1.3 Create backup-pause skill
**Location:** `.claude/skills/backup-pause/`
**Files:**
- `skill.json` - Skill metadata
- `run.sh` - Pause/resume backup operations

### 1.4 Create uninstall skill
**Location:** `.claude/skills/uninstall/`
**Files:**
- `skill.json` - Skill metadata
- `run.sh` - Uninstall backup system from project

---

## Phase 2: Phase 4 Test Suite (HIGH)

### 2.1 test-github-push.sh
**Location:** `tests/integration/test-github-push.sh`
**Test Cases:**
- Push with unpushed commits
- Push with no commits (should skip)
- Push interval enforcement
- Authentication failure handling
- Remote URL validation

### 2.2 test-concurrent-backups.sh
**Location:** `tests/stress/test-concurrent-backups.sh`
**Test Cases:**
- Two backups starting simultaneously
- Lock acquisition race condition
- Stale lock cleanup
- PID file validation
- Lock timeout handling

### 2.3 test-interrupted-backup.sh
**Location:** `tests/stress/test-interrupted-backup.sh`
**Test Cases:**
- Kill during file copy
- Kill during database backup
- State consistency after crash
- Partial file cleanup
- Resume after interruption

### 2.4 test-database-types.sh
**Location:** `tests/integration/test-database-types.sh`
**Test Cases:**
- SQLite detection and backup
- PostgreSQL detection (mock)
- MySQL detection (mock)
- MongoDB detection (mock)
- Backup verification

### 2.5 test-large-files.sh
**Location:** `tests/stress/test-large-files.sh`
**Test Cases:**
- Files > MAX_BACKUP_FILE_SIZE (100MB)
- Skip behavior with warning
- BACKUP_LARGE_FILES override
- Binary file handling
- Deep directory structures

---

## Phase 3: Version Consistency (HIGH)

### 3.1 Align all version references
**Files to Update:**
- `VERSION` - Already 2.3.0
- `CHANGELOG.md` - Add 2.3.0 section
- `README.md` - Update version badges
- `bin/backup-status.sh` - Version display
- `PLAN.md` - This file
- `TODO.md` - Update references

---

## Phase 4: Cloud Backup Rotation (MEDIUM)

### 4.1 Implement cloud retention policy
**File:** `lib/cloud-backup.sh`
**Features:**
- `CLOUD_RETENTION_DAYS` config option (default: 30)
- Delete old cloud backups after retention period
- Skip deletion if below minimum count
- Log rotation actions

### 4.2 Add cloud cleanup command
**File:** `bin/backup-cleanup.sh`
**Features:**
- `--cloud` flag for cloud-only cleanup
- `--dry-run` for preview
- Statistics on space reclaimed

---

## Phase 5: Installer Robustness (MEDIUM)

### 5.1 Add rollback on failure
**File:** `bin/install-global.sh`
**Features:**
- Backup existing installation before upgrade
- Rollback to previous version on failure
- Clear error messages

### 5.2 Add PATH validation
**File:** `bin/install-global.sh`
**Features:**
- Check if `~/.local/bin` is in PATH
- Provide instructions to add to PATH
- Verify commands accessible after install

### 5.3 Improve dependency checks
**File:** `bin/install-global.sh`
**Features:**
- Validate each dependency installed correctly
- Fail fast with clear error message
- Suggest installation commands

---

## Phase 6: Verify Claimed Fixes (HIGH)

### 6.1 Test backup_errors initialization
- Verify variable initialized before use
- Run with `set -u` and confirm no errors

### 6.2 Test atomic lock mechanism
- Run two backups simultaneously
- Verify only one acquires lock
- Check PID file is correct

### 6.3 Test temp file cleanup
- Simulate gzip failure
- Verify temp files cleaned up
- Check no data left in /tmp

### 6.4 Test database verification
- Create intentionally corrupted backup
- Verify gunzip -t catches it
- Check error reported

### 6.5 Test timestamp collision
- Run rapid backups
- Verify unique filenames with PID suffix
- No overwrites

### 6.6 Test symlink handling
- Create symlink to system file
- Verify skipped with warning
- No data from symlink target

### 6.7 Test orphan detection
- Remove project directory
- Run daemon
- Verify self-disable and cleanup

### 6.8 Test .DS_Store filtering
- Create directory with only .DS_Store
- Verify detected as empty/first backup

### 6.9 Test config self-backup
- Verify .backup-config.sh in backup
- Delete and restore
- System works after restore

### 6.10 Test UTC timestamps
- Set USE_UTC_TIMESTAMPS=true
- Verify backup filenames use UTC
- Compare with local time

---

## Implementation Order

1. **Phase 1: Skills** (30 min)
   - Create 4 skill directories
   - Add skill.json and run.sh for each

2. **Phase 2: Tests** (1 hour)
   - Create 5 test files
   - Implement test cases

3. **Phase 3: Versions** (10 min)
   - Update all version references

4. **Phase 4: Cloud Rotation** (30 min)
   - Implement retention policy
   - Add cleanup command

5. **Phase 5: Installer** (30 min)
   - Add rollback mechanism
   - Add PATH validation
   - Improve dependency checks

6. **Phase 6: Verification** (1 hour)
   - Run all verification tests
   - Fix any failures

---

## Files to Create

| File | Purpose |
|------|---------|
| `.claude/skills/checkpoint/skill.json` | Checkpoint skill config |
| `.claude/skills/checkpoint/run.sh` | Checkpoint skill runner |
| `.claude/skills/backup-update/skill.json` | Update skill config |
| `.claude/skills/backup-update/run.sh` | Update skill runner |
| `.claude/skills/backup-pause/skill.json` | Pause skill config |
| `.claude/skills/backup-pause/run.sh` | Pause skill runner |
| `.claude/skills/uninstall/skill.json` | Uninstall skill config |
| `.claude/skills/uninstall/run.sh` | Uninstall skill runner |
| `tests/integration/test-github-push.sh` | GitHub push tests |
| `tests/stress/test-concurrent-backups.sh` | Concurrency tests |
| `tests/stress/test-interrupted-backup.sh` | Interruption tests |
| `tests/integration/test-database-types.sh` | Database type tests |
| `tests/stress/test-large-files.sh` | Large file tests |

## Files to Modify

| File | Changes |
|------|---------|
| `CHANGELOG.md` | Add 2.3.0 section |
| `README.md` | Update version references |
| `lib/cloud-backup.sh` | Add retention/rotation |
| `bin/backup-cleanup.sh` | Add --cloud flag |
| `bin/install-global.sh` | Add rollback, PATH check |

---

## Success Criteria

- [ ] 4 Claude Code skills created and functional
- [ ] 5 Phase 4 test files created
- [ ] All tests pass
- [ ] Version consistent across all files (2.3.0)
- [ ] Cloud backup rotation implemented
- [ ] Installer has rollback and validation
- [ ] All v2.2.2 fixes verified working
- [ ] Git commit and push complete

---

## Rollback Plan

If issues arise:
1. Git revert to previous commit
2. Document failure
3. Fix and retry

---
