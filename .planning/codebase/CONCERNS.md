# Codebase Concerns

**Analysis Date:** 2026-02-12

## Tech Debt

**Monolithic foundation library:**
- Issue: `lib/backup-lib.sh` is 3,216 lines — handles config, validation, file ops, error codes, notifications, state, malware scanning, locking
- Files: `lib/backup-lib.sh`
- Why: Organic growth across v1.0-v1.2 milestones
- Impact: Difficult to navigate, high cognitive load when modifying
- Fix approach: Extract into focused modules (e.g., `lib/config.sh`, `lib/error-codes.sh`, `lib/file-ops.sh`)

**Large CLI scripts:**
- Issue: Several bin/ scripts exceed 700 lines
- Files: `bin/backup-now.sh` (1,427 lines), `bin/install.sh` (1,383 lines), `bin/backup-config.sh` (1,126 lines), `bin/backup-restore.sh` (983 lines)
- Why: Complex workflows with inline help text and argument parsing
- Impact: Hard to maintain and test individual pieces
- Fix approach: Extract reusable functions to lib/ modules

**Duplicate symlink resolution:**
- Issue: Same 7-line symlink resolution pattern copy-pasted in every bin/ script
- Files: `bin/backup-now.sh`, `bin/backup-daemon.sh`, `bin/backup-config.sh`, `bin/backup-status.sh`, and ~20 more
- Why: Each script needs to find its own location independently
- Impact: Changes must be applied to 20+ files
- Fix approach: Extract to a bootstrap file sourced via relative path

## Known Bugs

**Dashboard verify backups stub:**
- Symptoms: "Verify Backups" menu option shows "Coming soon!" message
- Trigger: Select "Verify Backups" in checkpoint-dashboard
- File: `bin/checkpoint-dashboard.sh` (line 431)
- Workaround: None — feature not implemented
- Root cause: Placeholder left during dashboard implementation

## Security Considerations

**Piping curl to bash:**
- Risk: Man-in-the-middle attack during rclone installation
- Files: `lib/cloud-backup.sh` (lines 42, 46), `lib/dependency-manager.sh` (lines 273, 284)
- Current mitigation: Only runs during explicit user-initiated install
- Recommendations: Download script, verify checksum, then execute

**Database credentials in config:**
- Risk: MySQL/PostgreSQL passwords stored in `.backup-config.sh` (plaintext)
- Files: `lib/database-detector.sh` (lines 152-162)
- Current mitigation: Config files are gitignored
- Recommendations: Use system keychain or environment variables for credentials

**Hardcoded cloud folder paths:**
- Risk: Assumes specific cloud folder locations (could miss custom paths)
- File: `lib/auto-configure.sh` — `CLOUD_FOLDERS` array with hardcoded `$HOME/Dropbox`, `$HOME/Google Drive`, etc.
- Current mitigation: User can manually configure cloud path
- Recommendations: Allow user-specified cloud folder paths in config

## Performance Bottlenecks

**Silent error suppression:**
- Problem: Heavy use of `2>/dev/null` across critical operations
- Files: `bin/backup-now.sh` (77 occurrences), `bin/backup-daemon.sh` (52), `lib/cloud-backup.sh` (9)
- Cause: Defensive programming to avoid noisy error output
- Improvement path: Log suppressed errors to debug log file instead of discarding

**Large file hash computation:**
- Problem: SHA-256 computation on every file for change detection
- File: `lib/backup-lib.sh` (line 1307) — `shasum -a 256` for each file
- Cause: Hash-based comparison for non-git files
- Current mitigation: mtime cache avoids re-hashing unchanged files (O(1) for unchanged)
- Improvement path: Only hash files where mtime changed (already implemented in v1.1)

## Fragile Areas

**YAML parser (pure bash):**
- File: `lib/backup-lib.sh` — YAML parsing implemented in bash
- Why fragile: Bash is not designed for structured data parsing; complex YAML may break
- Common failures: Nested YAML, multi-line values, special characters
- Safe modification: Test with varied YAML inputs; consider `yq` as optional dependency
- Test coverage: Basic YAML parsing tested in unit tests

**Database detector heuristics:**
- File: `lib/database-detector.sh`
- Why fragile: Detection based on file extensions, ports, docker-compose parsing
- Common failures: Non-standard database locations, custom ports, unusual container names
- Safe modification: Add detection patterns without removing existing ones
- Test coverage: Integration tests cover standard scenarios

## Scaling Limits

**Single-threaded backup:**
- Current capacity: Sequential file processing
- Limit: Slow for projects with thousands of files
- Symptoms at limit: Backup takes minutes instead of seconds
- Scaling path: Parallel file copy (already partially implemented with parallel git detection in v1.1)

**Project registry (JSON file):**
- File: `~/.config/checkpoint/projects.json`
- Current capacity: Works fine for dozens of projects
- Limit: JSON parsing in bash becomes slow with hundreds of projects
- Scaling path: Use `jq` for efficient JSON operations (already optional dependency)

## Dependencies at Risk

**No critical dependency risks identified.**
- rclone: Actively maintained, large community
- System tools (sqlite3, pg_dump, etc.): Stable, part of official distributions
- dialog/whiptail: Stable, standard Unix utilities

## Missing Critical Features

**Backup integrity verification:**
- Problem: No automated verification that backups are complete and uncorrupted
- File: `bin/checkpoint-dashboard.sh` (line 431) — stub showing "coming soon"
- Current workaround: Manual file inspection
- Blocks: Users can't confirm backup health without manual checks
- Implementation complexity: Medium — verify file counts, database integrity checks (partially implemented in `lib/backup-lib.sh:verify_sqlite_integrity()`)

**Linux systemd support:**
- Problem: Daemon only supports macOS LaunchAgent
- Files: `templates/com.checkpoint.watchdog.plist` (macOS only)
- Current workaround: Manual cron setup on Linux
- Blocks: Seamless Linux daemon experience
- Implementation complexity: Low — create systemd unit file template

## Test Coverage Gaps

**Cloud backup end-to-end:**
- What's not tested: Full rclone upload/download cycle with real cloud provider
- Risk: Cloud sync could fail silently in production
- Priority: Medium
- Difficulty to test: Requires cloud credentials and network access in test environment

**Concurrent backup race conditions:**
- What's not tested: Multiple backup processes competing for same project simultaneously
- Risk: Lock mechanism may have edge cases
- Priority: Low (lock mechanism tested, but not under real concurrency pressure)
- Difficulty to test: Need to simulate parallel process execution

---

*Concerns audit: 2026-02-12*
*Update as issues are fixed or new ones discovered*
