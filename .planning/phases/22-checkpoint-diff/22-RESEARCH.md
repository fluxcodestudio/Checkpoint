# Phase 22: Checkpoint Diff Command - Research

**Researched:** 2026-02-16
**Domain:** Bash CLI — backup snapshot comparison using Unix diff/rsync tooling
**Confidence:** HIGH

<research_summary>
## Summary

Researched how established backup tools (restic, borg) present diff output and how to implement snapshot comparison in Checkpoint's rsync-based backup architecture. The domain is well-understood (standard Unix tooling), so this research focuses on **UX patterns from mature tools** and **mapping them to Checkpoint's specific backup structure**.

Checkpoint's backup architecture uses rsync with `--backup --suffix=.TIMESTAMP` which creates a specific directory layout: `files/` holds current file copies, `archived/` holds previous versions with timestamp suffixes. This differs from tools like restic/borg which use deduplication, but the comparison problem is the same.

**Primary recommendation:** Use `rsync --dry-run --itemize-changes` for current-vs-backup comparison, and filesystem scanning of archived/ timestamps for backup-vs-backup comparison. Adopt restic's single-character change indicators (`+`, `-`, `M`) for clean output. Support `--json` output for scripting.
</research_summary>

<standard_stack>
## Standard Stack

This phase uses **only standard Unix tools** — no external dependencies required.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| rsync --dry-run | Compare current working dir to backup files/ mirror | Already used by Checkpoint for backups; --itemize-changes gives precise change types |
| diff (GNU/BSD) | Optional: show content-level diffs for specific files | Standard Unix; available on all target platforms |
| find | Scan archived/ directory for timestamped versions | Standard Unix; needed to discover available snapshots |
| stat | Get file metadata (size, mtime) for comparison | Standard Unix; already wrapped in compat.sh |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| shasum -a 256 | Hash comparison for identical-size files | Already implemented in `get_file_hash()` in file-ops.sh |
| date | Parse/format timestamps from archived file suffixes | Standard Unix; needed for snapshot discovery |
| column / printf | Format tabular output | Standard Unix; for aligned output |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| rsync --dry-run | Manual find + stat comparison | rsync handles excludes, permissions, symlinks automatically |
| find for snapshot discovery | Manifest JSON files | Manifests exist (.checkpoint-manifest.json) but only for latest backup; archived/ scanning more reliable for historical comparison |
| Custom diff formatting | External tools (delta, difftastic) | Would add dependencies; plain diff output is sufficient for file-level comparison |

**Installation:** No new dependencies. All tools already available on macOS and Linux.
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Checkpoint's Backup Directory Structure
```
backups/
├── databases/           # Timestamped DB snapshots: "ProjectName - MM.DD.YY - HH:MM.db.gz"
├── files/               # Current mirror of backed-up files (rsync destination)
├── archived/            # Previous file versions with timestamp suffixes
│   ├── src/
│   │   └── app.js.20260216_143022_12345    # archived version
│   │   └── app.js.20260215_120000_54321    # older archived version
│   └── .env.20260210_090000_11111
├── .checkpoint-manifest.json    # Latest backup manifest
├── .hash-cache                  # SHA256 cache for file comparison
└── backup.log
```

**Key insight:** Each file in `archived/` has a suffix `.YYYYMMDD_HHMMSS_PID`. The PID suffix prevents collisions but means we need pattern matching, not exact timestamp lookup.

### Pattern 1: Three Comparison Modes (from restic/borg UX)
**What:** Support three distinct comparison operations
**When to use:** Always — these cover all user needs

1. **current-vs-backup** (`checkpoint diff`): Compare working directory against last backup
   - Uses `rsync --dry-run --itemize-changes` against `files/`
   - Shows what would be backed up on next run
   - Most common use case

2. **backup-vs-backup** (`checkpoint diff --snapshot <timestamp>`): Compare current backup against a specific point in time
   - Reconstructs historical state from `files/` + `archived/` entries
   - Shows what changed between then and now in the backup

3. **file history** (`checkpoint history <file>`): Show all versions of a specific file
   - Already partially implemented in `list_file_versions_sorted()` in backup-discovery.sh
   - Extend with size diff and content diff options

### Pattern 2: Restic-Style Output Format
**What:** Single-character change indicators for clean, scannable output
**When to use:** Default text output mode

```
+  src/new-feature.js          (1.2 KB)
-  src/old-module.js           (856 B)
M  src/app.js                  (2.1 KB → 2.3 KB)
M  .env                        (128 B → 135 B)

Files:  1 new, 1 removed, 2 modified
```

Change indicators (from restic, widely adopted):
- `+` Added (exists in newer, not in older)
- `-` Removed (exists in older, not in newer)
- `M` Modified (content changed)
- `U` Metadata only (permissions, timestamps — optional, show with `--metadata`)

### Pattern 3: Snapshot Discovery from Archived Files
**What:** Extract available "snapshot" timestamps from archived/ directory
**When to use:** For backup-vs-backup comparison and listing available snapshots

```bash
# Extract unique timestamps from archived/ file suffixes
# Format: YYYYMMDD_HHMMSS (ignore PID suffix)
find "$ARCHIVED_DIR" -type f | sed 's/.*\.\([0-9]\{8\}_[0-9]\{6\}\)_[0-9]*/\1/' | sort -u
```

This gives us a list of "snapshot points" — times when backups occurred and archived old versions.

### Pattern 4: CLI Integration (New Subcommand)
**What:** Add `diff` as a subcommand to `checkpoint`
**When to use:** Integrate into existing CLI structure

```
checkpoint diff                          # Current working dir vs last backup
checkpoint diff --snapshot 20260215      # Current backup vs specific date
checkpoint diff --from 20260214 --to 20260215  # Between two snapshots
checkpoint history <file>                # All versions of a file
checkpoint diff --json                   # JSON output for scripting
```

### Anti-Patterns to Avoid
- **Full tree walk for every comparison:** Use rsync --dry-run (it's optimized for this)
- **Storing snapshot metadata separately:** The archived/ directory IS the metadata; don't duplicate it
- **Comparing file contents by default:** Size + mtime comparison first; hash only when sizes match (already implemented in `files_identical_hash()`)
- **Interactive diff viewer:** Keep it simple output to stdout; users can pipe to `less` or `delta`
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Directory tree comparison | Custom find + stat loops | `rsync --dry-run -i` | rsync handles symlinks, permissions, excludes, and edge cases we'd miss |
| File content hashing | Custom hash function | Existing `get_file_hash()` in file-ops.sh | Already has mtime-based caching for performance |
| File identity comparison | Size-only check | Existing `files_identical_hash()` in file-ops.sh | Already does size-first-then-hash optimization |
| Version listing for a file | Custom archive scanner | Existing `list_file_versions_sorted()` in backup-discovery.sh | Already handles both current and archived versions |
| Timestamp formatting | Custom date parsing | Existing `format_relative_time()` in time-size-utils.sh | Already handles "2 hours ago" style formatting |
| Size formatting | Custom byte formatter | Existing `format_bytes()` in time-size-utils.sh | Already handles KB/MB/GB conversion |
| Config loading | Custom config reader | Existing `load_backup_config()` in config.sh | Already handles global defaults, project overrides, security checks |

**Key insight:** Most building blocks already exist in the Checkpoint library. The diff command is primarily a **composition** of existing utilities with new output formatting. The only truly new code is snapshot reconstruction from archived/ timestamps and rsync dry-run parsing.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Timestamp-PID Suffix Parsing
**What goes wrong:** Archived files have `.YYYYMMDD_HHMMSS_PID` suffixes. The PID part varies, so naive timestamp extraction fails.
**Why it happens:** PID was added to prevent collisions during concurrent backups.
**How to avoid:** Strip PID when grouping by snapshot time: `sed 's/\.\([0-9]\{8\}_[0-9]\{6\}\)_[0-9]*$/.\1/'`
**Warning signs:** Files from the same backup appearing as different snapshots

### Pitfall 2: Archived Directory Mirrors Source Structure
**What goes wrong:** `archived/` preserves the full relative path (e.g., `archived/src/components/Button.js.TIMESTAMP`). Walking it naively misses nested directories.
**Why it happens:** rsync `--backup-dir` preserves source directory structure
**How to avoid:** Use `find "$ARCHIVED_DIR" -type f` for full recursive scan; strip `$ARCHIVED_DIR/` prefix and timestamp suffix to reconstruct original paths
**Warning signs:** Missing files in diff output, especially nested files

### Pitfall 3: rsync --dry-run Counts Metadata Changes Too
**What goes wrong:** `rsync -i --dry-run` reports permission/timestamp changes even when content is identical. Output looks like files changed when they didn't.
**Why it happens:** rsync --archive syncs permissions and timestamps by default
**How to avoid:** Filter itemize output: only show lines starting with `>f` (file transfer), not `.d` (directory) or permission-only changes; or use `--size-only` flag
**Warning signs:** Lots of "modified" files that users know haven't changed

### Pitfall 4: Large Archived Directories = Slow Scan
**What goes wrong:** Projects with many files and long retention create thousands of entries in archived/. Scanning all of them for snapshot discovery is slow.
**Why it happens:** 60-day retention with hourly backups = potentially thousands of archived versions per file
**How to avoid:** Cache snapshot list; use `find -maxdepth 1` for top-level scan first; offer `--recent N` flag to limit to last N snapshots
**Warning signs:** Diff command takes >5 seconds on large projects

### Pitfall 5: Missing Backup Directory
**What goes wrong:** User runs `checkpoint diff` in a project without backups configured, or backup directory is on disconnected drive
**Why it happens:** New project or external drive backup
**How to avoid:** Check `load_backup_config()` succeeds and backup dirs exist before attempting diff; use existing `check_drive()` for drive verification
**Warning signs:** Cryptic error messages instead of helpful "no backups found" message
</common_pitfalls>

<code_examples>
## Code Examples

### rsync --dry-run for Current-vs-Backup Comparison
```bash
# Source: rsync man page, verified for Checkpoint's architecture
# Compare working directory against backup files/ mirror
rsync --archive --no-links --dry-run --itemize-changes \
    --out-format="%i %n" \
    "$PROJECT_DIR/" "$FILES_DIR/" 2>/dev/null | \
    grep '^>f' | while IFS= read -r line; do
        # Parse rsync itemize format: >f.st...... filename
        local change_type="${line:0:11}"
        local filename="${line:12}"

        if [[ "$change_type" == *'++++++++'* ]]; then
            echo "+  $filename"    # New file
        else
            echo "M  $filename"    # Modified file
        fi
    done
```

### Discover Available Snapshots from Archived Directory
```bash
# Extract unique backup timestamps from archived/ file suffixes
discover_snapshots() {
    local archived_dir="$1"

    find "$archived_dir" -type f 2>/dev/null | \
        sed -n 's/.*\.\([0-9]\{8\}_[0-9]\{6\}\)_[0-9]*/\1/p' | \
        sort -u -r  # Most recent first
}

# Example output:
# 20260216_143022
# 20260216_120000
# 20260215_180000
```

### Reconstruct File State at a Snapshot Time
```bash
# For a given timestamp, determine which version of a file was current
# Logic: The archived version CLOSEST TO BUT NOT AFTER the target time
#        is the one that was replaced AT that time. The previous version
#        (or current files/ copy if no older archive exists) was live.
get_file_at_snapshot() {
    local file_path="$1"
    local target_timestamp="$2"   # YYYYMMDD_HHMMSS
    local files_dir="$3"
    local archived_dir="$4"

    local base_name=$(basename "$file_path")
    local dir_name=$(dirname "$file_path")

    # Find all archived versions, sorted newest first
    local versions=()
    while IFS= read -r version; do
        local ts=$(echo "$version" | sed -n 's/.*\.\([0-9]\{8\}_[0-9]\{6\}\)_[0-9]*/\1/p')
        if [[ "$ts" > "$target_timestamp" ]]; then
            # This version was archived AFTER our target time
            # So this IS the version that existed at target time
            echo "$version"
            return 0
        fi
    done < <(find "$archived_dir/$dir_name" -name "${base_name}.*" -type f 2>/dev/null | sort -r)

    # No archived version after target = current files/ copy existed at target
    if [[ -f "$files_dir/$file_path" ]]; then
        echo "$files_dir/$file_path"
        return 0
    fi

    return 1  # File didn't exist at target time
}
```

### Summary Statistics (restic-style)
```bash
# Print summary line after diff output
print_diff_summary() {
    local added="$1" removed="$2" modified="$3"

    local parts=()
    [[ $added -gt 0 ]] && parts+=("$added new")
    [[ $removed -gt 0 ]] && parts+=("$removed removed")
    [[ $modified -gt 0 ]] && parts+=("$modified modified")

    if [[ ${#parts[@]} -eq 0 ]]; then
        echo "No differences found."
    else
        local IFS=', '
        echo ""
        echo "Files: ${parts[*]}"
    fi
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Text-only diff output | JSON output option (--json) | Standard since restic/borg | Enables scripting, piping to jq, integration with dashboards |
| No snapshot labeling | Human-readable snapshot labels | borg 2.0 | Users prefer "2 hours ago" over "20260216_143022" |
| Separate diff commands | Unified subcommand with modes | restic pattern | `diff` without args = most common case (current vs backup) |

**Established patterns from mature tools:**
- **restic:** `+/-/M/U/T` single-char indicators, `--metadata` flag for optional metadata diffs, `--json` output
- **borg:** Byte-level added/removed counts per file, `--content-only` to suppress metadata, `--json-lines` for streaming JSON, `--sort` option
- Both support comparing any two snapshots by ID/timestamp

**Applicable to Checkpoint:**
- Adopt restic's simpler single-character indicators (borg's byte-level detail is overkill for file-copy backups)
- Support `--json` for scripting (not `--json-lines` — Checkpoint diffs are small enough for single JSON output)
- Support relative time display ("2 hours ago") using existing `format_relative_time()`
</sota_updates>

<open_questions>
## Open Questions

1. **Snapshot reconstruction accuracy**
   - What we know: Archived files have timestamps of when they were replaced, but the "before" state requires working backwards through the archive chain
   - What's unclear: Whether timestamp ordering is always reliable (clock skew, timezone changes, PID collisions)
   - Recommendation: For v1, support current-vs-backup comparison only (uses rsync --dry-run, no reconstruction needed). Add backup-vs-backup in a follow-up if users request it.

2. **Content-level diffs**
   - What we know: `checkpoint diff` should show which files changed; users may also want to see *what* changed inside a file
   - What's unclear: Whether to show inline content diffs or just list changed files
   - Recommendation: Default to file-list-only (like restic/borg). Add `checkpoint diff --content <file>` to show actual content diff of a specific file against its backup copy.

3. **Database snapshot diffing**
   - What we know: Database backups are `.db.gz` compressed SQLite snapshots with timestamps in the filename
   - What's unclear: How to meaningfully diff two database snapshots (schema changes? row counts?)
   - Recommendation: For v1, show database snapshots as a timeline only (list available snapshots with sizes/dates). Actual DB diffing is a much larger problem — defer it.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Checkpoint codebase: `bin/backup-now.sh` — rsync backup execution with `--backup --suffix` pattern
- Checkpoint codebase: `lib/features/backup-discovery.sh` — existing `list_file_versions_sorted()`
- Checkpoint codebase: `lib/ops/file-ops.sh` — existing `get_file_hash()`, `files_identical_hash()`
- rsync man page — `--dry-run`, `--itemize-changes`, `--out-format` options

### Secondary (MEDIUM confidence)
- [restic diff man page](https://manpages.ubuntu.com/manpages/jammy/man1/restic-diff.1.html) — output format (`+/-/M/U/T`), `--metadata` flag, `--json` output
- [borg diff documentation](https://borgbackup.readthedocs.io/en/stable/usage/diff.html) — byte-level diff, `--content-only`, `--json-lines`, `--sort` options
- [rsync dry-run patterns](https://www.baeldung.com/linux/rsync-output-changed-files-list) — `--itemize-changes` format for directory comparison

### Tertiary (LOW confidence - needs validation)
- None — all findings verified against official sources or codebase
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Unix diff/rsync/find (standard tools)
- Ecosystem: restic + borg UX patterns for output formatting
- Patterns: Three comparison modes, snapshot discovery, output formatting
- Pitfalls: Timestamp parsing, large archives, rsync metadata noise

**Confidence breakdown:**
- Standard stack: HIGH — all standard Unix tools, no new dependencies
- Architecture: HIGH — patterns verified from both codebase analysis and restic/borg docs
- Pitfalls: HIGH — derived from codebase analysis of actual backup structure
- Code examples: HIGH — rsync patterns verified against man page, Checkpoint patterns verified against codebase

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days — Unix tooling is stable; no ecosystem churn)
</metadata>

---

*Phase: 22-checkpoint-diff*
*Research completed: 2026-02-16*
*Ready for planning: yes*
