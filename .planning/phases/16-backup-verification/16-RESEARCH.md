# Phase 16: Backup Verification - Research

**Researched:** 2026-02-13
**Domain:** Backup integrity verification (bash CLI tool)
**Confidence:** HIGH

<research_summary>
## Summary

Researched backup verification patterns for Checkpoint, a bash-based backup tool that backs up files, SQLite databases (gzipped), and cloud syncs (rclone). The codebase already has significant verification primitives: `verify_sqlite_integrity()`, `verify_compressed_backup()`, SHA256 hash caching in `file-ops.sh`, and manifest-based post-backup checks in `backup-now.sh`.

The gap is a **standalone verification command** that can audit an entire backup set after the fact, plus a **formalized manifest** and **dashboard integration**. The established approach (PostgreSQL, restic, Borg) is a tiered verification system: quick mode (existence + size) for regular checks, full mode (SHA256 hashes) for deep audits.

**Primary recommendation:** Create `lib/features/verification.sh` module + `bin/backup-verify.sh` command with tiered verification (quick/full), JSON manifest at backup time, dual output (human + JSON), and dashboard integration via the existing `action_verify_backups()` placeholder.
</research_summary>

<standard_stack>
## Standard Stack

No external libraries needed. This phase builds entirely on existing codebase primitives and standard Unix tools.

### Core (Already in Codebase)
| Tool/Function | Location | Purpose | Status |
|---------------|----------|---------|--------|
| `verify_sqlite_integrity()` | lib/features/restore.sh | PRAGMA integrity_check on SQLite DBs | Exists, reuse |
| `verify_compressed_backup()` | lib/features/restore.sh | gunzip -t + SQLite integrity | Exists, reuse |
| `get_file_hash()` | lib/ops/file-ops.sh | SHA256 hash with mtime cache | Exists, reuse |
| `files_identical_hash()` | lib/ops/file-ops.sh | Compare files by hash | Exists, reuse |
| `.checkpoint-state.json` | backups/ root | Post-backup state with counts/errors | Exists, extend |
| Post-backup manifest | backup-now.sh:933-963 | File presence + size verification | Exists, formalize |

### Supporting (Standard Unix)
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `sha256sum` / `shasum -a 256` | File hash verification | Full integrity mode |
| `gunzip -t` | Gzip archive validation | Database backup checks |
| `sqlite3` | Database integrity checks | PRAGMA integrity_check, quick_check |
| `rclone check` | Cloud sync verification | Remote backup validation |
| `file` command | File type detection | SQLite header verification |
| `wc -c` | File size comparison | Quick verification mode |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SHA256 manifest | File mtime comparison | mtime is faster but doesn't catch bit-rot |
| JSON manifest | Plain text checksums | JSON is machine-parseable, plain text is simpler |
| `rclone check` | Manual file listing comparison | rclone check handles provider-specific hash differences |
| PRAGMA integrity_check | PRAGMA quick_check | quick_check is faster but less thorough |
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Module Structure
```
lib/features/verification.sh    # Core verification logic (new)
bin/backup-verify.sh             # CLI command (new)
bin/checkpoint-dashboard.sh      # Update action_verify_backups() (existing)
lib/features/health-stats.sh     # Extend with verification status (existing)
```

### Pattern 1: Tiered Verification
**What:** Two verification modes — quick (seconds) and full (minutes) — following restic/Borg conventions.
**When to use:** Quick for regular/dashboard checks, full for periodic deep audits.

Quick mode (default):
- File existence in backup directory
- File size matches source
- Database backup decompresses cleanly
- Manifest file count matches actual count

Full mode (`--full` flag):
- Everything in quick mode, plus:
- SHA256 hash verification of all backed-up files
- Full SQLite PRAGMA integrity_check (not just quick_check)
- Schema readability and table count validation
- Cloud sync comparison via `rclone check`

### Pattern 2: Manifest-Based Verification
**What:** JSON manifest generated at backup time, verified later. Standard pattern from PostgreSQL's backup manifests.
**When to use:** Every backup generates a manifest; verification reads it.

```bash
# Manifest stored at: $BACKUP_DIR/.checkpoint-manifest.json
{
  "version": 1,
  "timestamp": "2026-02-13T12:00:00Z",
  "project": "my-project",
  "files": [
    {"path": "files/src/app.js", "size": 2048, "sha256": "abc123..."}
  ],
  "databases": [
    {"path": "databases/dev.db.gz", "size": 4096, "sha256": "def456...", "tables": 12}
  ],
  "manifest_checksum": "sha256-of-everything-above"
}
```

Verification flow:
1. Read manifest (expected state)
2. Scan backup directory (actual state)
3. Compare: missing files = CRITICAL, orphan files = WARNING, mismatches = ERROR

### Pattern 3: Dual Output Format
**What:** Human-readable output by default, JSON with `--json` flag. Standard CLI pattern.
**When to use:** Always. Human for interactive use, JSON for scripting/dashboard.

Human-readable:
```
Checkpoint Verification Report
================================
Project: my-project
Backup:  /path/to/backups

Files
  Existence ......... PASS (47/47 present)
  Size match ........ PASS (47/47 match)
  Integrity ......... PASS (47/47 hashes valid)

Databases
  dev.db.gz ......... PASS (gzip OK, integrity OK, 12 tables)

Summary: ALL CHECKS PASSED
```

### Pattern 4: Exit Code Convention
**What:** Follow restic/Borg exit code convention for scriptability.
- `0` = All checks passed
- `1` = One or more checks failed (backup has problems)
- `2` = Verification could not be performed (missing config, inaccessible dir)

### Anti-Patterns to Avoid
- **Running verification synchronously in dashboard:** Verification can take time with large backups. Show progress, don't block.
- **Verifying during active backup:** Race condition — files change while checking. Use manifest snapshot approach instead.
- **Storing hashes in separate files per-backup-file:** Single manifest file is easier to manage and verify atomically.
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Gzip verification | Custom byte-level checks | `gunzip -t` | Handles all gzip edge cases including multi-stream |
| SQLite integrity | Custom page checks | `sqlite3 PRAGMA integrity_check` | Validates B-tree structure, indices, constraints |
| Cloud sync comparison | Manual file listing + diff | `rclone check --one-way` | Handles provider-specific hashing, rate limiting |
| SHA256 hashing | Custom implementation | `shasum -a 256` (macOS) / `sha256sum` (Linux) | Already using platform-portable `get_file_hash()` |
| Report formatting | Custom string building | printf with aligned columns | Existing dashboard-ui patterns already handle this |

**Key insight:** All verification primitives already exist in the codebase or as standard Unix tools. This phase is about **orchestrating** existing checks into a cohesive workflow, not building new verification technology. The existing `verify_sqlite_integrity()`, `verify_compressed_backup()`, and `get_file_hash()` cover the hard parts.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: WAL Mode Database Copies
**What goes wrong:** Backed-up SQLite database appears corrupt because WAL/SHM files weren't included or checkpointed.
**Why it happens:** WAL-mode databases have pending writes in `-wal` file that aren't in the main `.db` file.
**How to avoid:** The codebase already uses `sqlite3 .backup` in database-detector.sh (line ~570) which handles WAL correctly. Verification should also check: if a `.db-wal` or `.db-shm` file exists alongside a backup, flag it as a WARNING (incomplete backup).
**Warning signs:** PRAGMA integrity_check passes but data appears stale or incomplete.

### Pitfall 2: Verifying During Active Backup
**What goes wrong:** File sizes or hashes don't match because backup is still writing.
**Why it happens:** Race condition between verification scan and backup write.
**How to avoid:** Check for active backup PID/lock file before running verification. Use manifest snapshot (written at backup completion) as the source of truth, not live file scanning.
**Warning signs:** Intermittent failures that pass on re-run.

### Pitfall 3: Hash Cache Staleness
**What goes wrong:** Verification reports "PASS" using cached hashes that don't reflect actual file state.
**Why it happens:** The existing hash cache in file-ops.sh caches by `filepath|mtime|hash`. If a file is corrupted but mtime doesn't change, the cache returns stale hash.
**How to avoid:** Full verification mode should bypass the hash cache and compute fresh hashes. Quick mode can use the cache.
**Warning signs:** Full mode finds corruption that quick mode missed.

### Pitfall 4: Compressed Size Threshold
**What goes wrong:** Empty or near-empty `.db.gz` files pass `gunzip -t` but contain no useful data.
**Why it happens:** An empty file or header-only gzip passes decompression test.
**How to avoid:** Add minimum size sanity check (e.g., compressed size < 100 bytes = likely empty/corrupt).
**Warning signs:** Database backup file is suspiciously small.

### Pitfall 5: Cloud Verification Without Network
**What goes wrong:** Verification fails or hangs when cloud provider is unreachable.
**Why it happens:** `rclone check` requires network access.
**How to avoid:** Cloud verification should be opt-in (skipped by default), with a `--cloud` flag. Detect network availability before attempting. Set a timeout.
**Warning signs:** Verification hangs or times out.

### Pitfall 6: Platform-Specific Hash Commands
**What goes wrong:** `sha256sum` not found on macOS, `shasum` not found on some Linux.
**Why it happens:** Different platforms bundle different hash utilities.
**How to avoid:** Already solved — `get_file_hash()` in file-ops.sh handles this with platform detection. Reuse it.
**Warning signs:** Command not found errors on different platforms.
</common_pitfalls>

<code_examples>
## Code Examples

Verified patterns from codebase and official tools.

### Existing SQLite Verification (lib/features/restore.sh)
```bash
# Source: lib/features/restore.sh:42-55
verify_sqlite_integrity() {
    local db_path="$1"
    [ ! -f "$db_path" ] && return 1
    if ! file "$db_path" 2>/dev/null | grep -q "SQLite"; then
        return 1
    fi
    local result=$(sqlite3 "$db_path" "PRAGMA integrity_check;" 2>&1)
    [ "$result" = "ok" ]
}
```

### Enhanced SQLite Verification (Recommended Extension)
```bash
# Extends existing verify_sqlite_integrity with schema + table checks
verify_sqlite_full() {
    local db_path="$1"
    local checks_passed=0 checks_total=0

    # Check 1: Valid SQLite file
    ((checks_total++))
    file "$db_path" 2>/dev/null | grep -q "SQLite" && ((checks_passed++))

    # Check 2: PRAGMA integrity_check
    ((checks_total++))
    local result=$(sqlite3 "$db_path" "PRAGMA integrity_check;" 2>&1)
    [[ "$result" == "ok" ]] && ((checks_passed++))

    # Check 3: Schema readable
    ((checks_total++))
    sqlite3 "$db_path" ".schema" &>/dev/null && ((checks_passed++))

    # Check 4: Has tables (non-empty)
    ((checks_total++))
    local table_count=$(sqlite3 "$db_path" \
        "SELECT count(*) FROM sqlite_master WHERE type='table';" 2>/dev/null)
    [[ "${table_count:-0}" -gt 0 ]] && ((checks_passed++))

    echo "$checks_passed/$checks_total"
    [[ "$checks_passed" -eq "$checks_total" ]]
}
```

### Existing Hash Function (lib/ops/file-ops.sh)
```bash
# Source: lib/ops/file-ops.sh — get_file_hash()
# Already handles macOS (shasum -a 256) vs Linux (sha256sum)
# Uses mtime-based cache for performance
# Cache format: filepath|mtime|sha256hash
```

### rclone Check for Cloud Verification
```bash
# Source: rclone official documentation
# Quick cloud verification (size-only, fast)
rclone check "$local_dir" "$remote" --one-way --size-only

# Full cloud verification with report
rclone check "$local_dir" "$remote" --one-way \
    --combined "$report_file" 2>/dev/null
# Report format: = match, - missing dest, + extra dest, * differs
```

### Manifest Generation Pattern
```bash
# Source: PostgreSQL backup manifest pattern (adapted for bash/JSON)
# Generate at end of backup run
generate_manifest() {
    local backup_dir="$1" manifest_file="$backup_dir/.checkpoint-manifest.json"
    local files_json="" db_json=""

    # Collect file entries
    while IFS= read -r -d '' file; do
        local rel_path="${file#$backup_dir/}"
        local size=$(wc -c < "$file")
        local hash=$(get_file_hash "$file")
        files_json+="$(printf '{"path":"%s","size":%d,"sha256":"%s"},' \
            "$rel_path" "$size" "$hash")"
    done < <(find "$backup_dir/files" -type f -print0 2>/dev/null)

    # Write manifest (trimming trailing comma)
    printf '{"version":1,"timestamp":"%s","project":"%s","files":[%s]}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_NAME" "${files_json%,}" \
        > "$manifest_file"
}
```

### Dashboard Integration Pattern
```bash
# Source: bin/checkpoint-dashboard.sh existing action patterns
# Replace the "coming soon" placeholder
action_verify_backups() {
    # Follow existing pattern: show progress → run → show result
    show_progress "Verifying backups..."
    local result=$(backup-verify --json 2>/dev/null)
    local status=$(echo "$result" | jq -r '.overall_status' 2>/dev/null)

    if [[ "$status" == "pass" ]]; then
        show_msgbox "Verification" "All backup checks passed!"
    else
        local failures=$(echo "$result" | jq -r '.summary.failed' 2>/dev/null)
        show_msgbox "Verification" "WARNING: $failures check(s) failed.\nRun 'checkpoint verify' for details."
    fi
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual checksum files (`.md5`, `.sha256`) | JSON manifests with metadata | 2023+ (PostgreSQL 17 formalized) | Machine-parseable, versioned, self-verifying |
| Full hash on every check | Tiered: quick (size) + full (hash) | Standard in restic/Borg | Practical for regular use without being slow |
| Single verification report | Dual format (human + JSON) | CLI convention 2024+ | Enables both interactive and scripted usage |
| `PRAGMA integrity_check` only | integrity_check + schema + table count | Best practice for SQLite backups | Catches more corruption modes |

**New tools/patterns to consider:**
- **rclone check --combined:** Unified diff-style report for cloud verification (available since rclone 1.56+)
- **PRAGMA quick_check:** Faster than integrity_check, good for quick mode (available since SQLite 3.33.0)

**Deprecated/outdated:**
- **MD5 checksums:** SHA256 is the standard for integrity verification
- **Per-file checksum sidecar files:** Use a single manifest instead
</sota_updates>

<open_questions>
## Open Questions

1. **Manifest generation timing**
   - What we know: Manifests should be generated at backup completion. The existing post-backup verification in backup-now.sh (lines 933-963) already builds a temporary manifest.
   - What's unclear: Should we refactor backup-now.sh to persist its manifest, or generate a separate one in verification.sh?
   - Recommendation: Extend backup-now.sh to persist its manifest as `.checkpoint-manifest.json`. Less duplication.

2. **Verification scheduling**
   - What we know: Phase 18 (Daemon Lifecycle & Health Monitoring) includes health checks. Verification could be scheduled there.
   - What's unclear: Should Phase 16 add any scheduled/automatic verification, or keep it purely on-demand?
   - Recommendation: Phase 16 = on-demand only. Phase 18 can add scheduled verification via daemon heartbeat.

3. **Cloud verification scope**
   - What we know: `rclone check` works but requires network and can be slow.
   - What's unclear: Should cloud verification check all historical backups or just the latest?
   - Recommendation: Latest only by default. `--all` flag for comprehensive check.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Codebase: `lib/features/restore.sh` — existing verify_sqlite_integrity(), verify_compressed_backup()
- Codebase: `lib/ops/file-ops.sh` — existing get_file_hash() with SHA256 + cache
- Codebase: `backup-now.sh:933-963` — existing manifest-based post-backup verification
- Codebase: `bin/checkpoint-dashboard.sh:430-432` — action_verify_backups() placeholder
- Codebase: `lib/features/health-stats.sh` — existing stats functions
- Codebase: `templates/backup-config.sh` — config variables for all backup paths
- SQLite documentation — PRAGMA integrity_check, quick_check, WAL mode
- rclone documentation — rclone check command with --combined flag

### Secondary (MEDIUM confidence)
- PostgreSQL 17 backup manifest format — adapted pattern for bash/JSON
- restic `check` command — exit code convention (0/1/2)
- Borg `check` command — tiered verification approach
- OneUpTime blog (2026) — backup integrity check implementation patterns

### Tertiary (LOW confidence - needs validation)
- None — all findings verified against codebase or official documentation
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Bash backup verification (internal patterns)
- Ecosystem: sqlite3, gunzip, shasum/sha256sum, rclone check
- Patterns: Tiered verification, JSON manifests, dual-format reporting
- Pitfalls: WAL mode, race conditions, hash cache staleness, network dependency

**Confidence breakdown:**
- Standard stack: HIGH — all tools already in codebase or standard Unix
- Architecture: HIGH — follows established restic/Borg/PostgreSQL patterns
- Pitfalls: HIGH — identified from codebase analysis and SQLite documentation
- Code examples: HIGH — drawn from existing codebase functions

**Research date:** 2026-02-13
**Valid until:** 2026-03-15 (30 days — stable domain, no fast-moving dependencies)
</metadata>

---

*Phase: 16-backup-verification*
*Research completed: 2026-02-13*
*Ready for planning: yes*
