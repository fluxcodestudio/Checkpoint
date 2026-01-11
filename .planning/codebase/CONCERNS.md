# Codebase Concerns

**Analysis Date:** 2026-01-10

## Tech Debt

**Configuration Schema Not Functional (bash 3.2 compatibility):**
- Issue: `BACKUP_CONFIG_SCHEMA` associative array commented out for macOS compatibility
- Files: `lib/backup-lib.sh` (lines 1912-1966), `bin/backup-config.sh`
- Why: Associative arrays require bash 4.0+, macOS ships with bash 3.2
- Impact: Configuration validation functions reference non-existent schema; `config_get_schema()`, `config_validate_file()`, `config_get_all_values()` silently fail
- Fix approach: Implement bash 3.2-compatible schema using indexed arrays or JSON file

**TODO Comment - Acknowledged but Unresolved:**
- Issue: TODO at line 1915 of `lib/backup-lib.sh`: "Implement bash 3.2-compatible config schema"
- Files: `lib/backup-lib.sh`
- Why: Known issue, not yet addressed
- Impact: Core configuration validation is broken on macOS
- Fix approach: Implement alternative schema storage (JSON or indexed array)

## Known Bugs

**Config Schema Functions Reference Empty Array:**
- Symptoms: Configuration validation silently passes invalid configs
- Trigger: Any call to `config_validate_value()` or `config_get_schema()`
- Files: `lib/backup-lib.sh` (line 2049, 2132, 2243)
- Workaround: Manual configuration validation
- Root cause: Schema array is commented out but functions still reference it

## Security Considerations

**Information Disclosure via Notifications:**
- Risk: Project names and backup status visible in system notification center
- Files: `lib/backup-lib.sh` (lines 115-118)
- Current mitigation: None
- Recommendations: Option to redact project names in notifications

**Shell Metacharacter in Error Messages:**
- Risk: File paths with special characters in failure logs could cause issues if displayed in shell context
- Files: `lib/backup-lib.sh` (line 558) - writes to failure log
- Current mitigation: JSON escaping for JSON output
- Recommendations: Consistent escaping for all output formats

## Performance Bottlenecks

**Multiple Find Operations in Cleanup Analysis:**
- Problem: `generate_cleanup_recommendations()` runs multiple `find` operations
- Files: `lib/backup-lib.sh` (lines 1854-1875)
- Measurement: With 1000s of backups, analysis takes minutes
- Cause: Sequential directory traversals for expired, duplicate, and orphaned files
- Improvement path: Combine into single traversal with in-memory filtering

## Fragile Areas

**Symlink Resolution in Script Loading:**
- Files: `bin/backup-now.sh` (lines 12-17), all bin scripts
- Why fragile: Complex while loop to resolve symlinks before sourcing libraries
- Common failures: Breaks if symlink chain is circular or target doesn't exist
- Safe modification: Test with both symlinked and direct execution
- Test coverage: Covered in compatibility tests

**JSON Parsing Without jq:**
- Files: `lib/backup-lib.sh` (lines 729-838) - `show_backup_failures()`
- Why fragile: Uses grep/sed patterns to parse JSON
- Common failures: Breaks with escaped quotes, multi-line values, special characters
- Safe modification: Add jq as optional dependency for complex parsing
- Test coverage: Limited

## Scaling Limits

**File-Based State:**
- Current capacity: Works well for <10,000 files per project
- Limit: Very large projects may slow down file scanning
- Symptoms at limit: Slow backup-status, slow daemon cycle detection
- Scaling path: Add incremental file tracking, cache file hashes

**Single-Threaded Backup:**
- Current capacity: Adequate for typical projects
- Limit: Large database backups block file backup
- Symptoms at limit: Long backup times for projects with large DBs
- Scaling path: Parallel database and file backup (background jobs)

## Dependencies at Risk

**rclone External Dependency:**
- Risk: Required for cloud backup, not bundled
- Impact: Cloud backup feature unavailable if rclone not installed
- Migration plan: None needed (optional feature), but should improve error messaging

## Missing Critical Features

**Cloud Backup Rotation:**
- Problem: No retention policy for cloud backups
- Files: `lib/cloud-backup.sh` - missing `CLOUD_RETENTION_DAYS`
- Current workaround: Manual cleanup via cloud provider UI
- Blocks: Production use with limited cloud storage
- Implementation complexity: Medium (add rotation to existing cloud sync)

**Installer Rollback:**
- Problem: Failed upgrade may leave system in broken state
- Files: `bin/install-global.sh`
- Current workaround: Manual restoration from backup
- Blocks: Safe automated updates
- Implementation complexity: Medium (backup before upgrade, restore on failure)

## Test Coverage Gaps

**Missing Test Files (Per TODO.md):**
- What's not tested:
  - `tests/integration/test-github-push.sh` - NOT FOUND
  - `tests/integration/test-database-types.sh` - NOT FOUND
  - `tests/stress/test-concurrent-backups.sh` - NOT FOUND
  - `tests/stress/test-interrupted-backup.sh` - NOT FOUND
  - `tests/stress/test-large-files.sh` - NOT FOUND
- Risk: Cannot verify concurrent safety, multi-database support, edge cases
- Priority: High (README claims 100% coverage)
- Difficulty to test: Medium (requires test fixtures and mocks)

**Configuration Validation Path:**
- What's not tested: Schema-based config validation
- Files: Functions in `lib/backup-lib.sh` (2045-2260)
- Risk: Invalid configurations accepted without warning
- Priority: Medium
- Difficulty to test: Low (once schema is implemented)

## Documentation Gaps

**No Error Recovery Guide:**
- What's missing: Step-by-step recovery procedures
- Files: `docs/` - no RECOVERY.md or TROUBLESHOOTING.md
- Impact: Users stuck when backups fail
- Fix: Add troubleshooting guide with common errors and solutions

**API Documentation Incomplete:**
- What's missing: Full function documentation for `lib/*.sh`
- Files: `docs/API.md`
- Impact: Contributors unclear on available functions
- Fix: Generate API docs from source comments

---

*Concerns audit: 2026-01-10*
*Update as issues are fixed or new ones discovered*
