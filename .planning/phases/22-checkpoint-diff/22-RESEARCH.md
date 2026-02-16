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

**Key insight:** Archived files have **two** suffix patterns (verified against real data):
- **With PID:** `.YYYYMMDD_HHMMSS_XXXXX` (from `backup-now.sh`, 48 files found)
- **Without PID:** `.YYYYMMDD_HHMMSS` (from `backup-daemon.sh`, 11 files found)

The existing `extract_timestamp()` in `retention-policy.sh` (line 81) **only handles the with-PID pattern**. The diff command must handle both.

**Real examples from this project's archived/ directory:**
```
CONTEXT_DIGEST.md.20260216_043343_72545    # with PID (backup-now.sh)
CONTEXT_DIGEST.md.20260216_041304          # without PID (daemon)
bin/backup-now.sh.20260216_031101          # without PID (daemon)
.claude/settings.local.json.20260216_043343_72545  # nested path, with PID
```

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

### Pitfall 1: Two Different Timestamp Suffix Formats (VERIFIED BUG)
**What goes wrong:** Archived files have TWO patterns: `.YYYYMMDD_HHMMSS_PID` (from `backup-now.sh`) and `.YYYYMMDD_HHMMSS` (from `backup-daemon.sh`). Code that only handles one pattern misses ~18% of archived files.
**Why it happens:** `backup-now.sh` appends `_$$` (PID) to prevent collisions; `backup-daemon.sh` does not.
**How to avoid:** Use regex that handles both: `\.([0-9]{8}_[0-9]{6})(_[0-9]+)?$`
**Warning signs:** Files from daemon backups missing from snapshot discovery; existing `extract_timestamp()` in `retention-policy.sh:81` has this exact bug (missing pattern for no-PID suffix)
**Impact:** This should be fixed in `extract_timestamp()` as part of this phase, not just in the diff command

### Pitfall 2: Archived Directory Mirrors Source Structure
**What goes wrong:** `archived/` preserves the full relative path (e.g., `archived/src/components/Button.js.TIMESTAMP`). Walking it naively misses nested directories.
**Why it happens:** rsync `--backup-dir` preserves source directory structure
**How to avoid:** Use `find "$ARCHIVED_DIR" -type f` for full recursive scan; strip `$ARCHIVED_DIR/` prefix and timestamp suffix to reconstruct original paths
**Warning signs:** Missing files in diff output, especially nested files

### Pitfall 3: rsync --dry-run Reports Metadata-Only Changes as Modifications (VERIFIED)
**What goes wrong:** `rsync -i --dry-run` reports permission/timestamp changes even when content is identical. Verified output shows `.d..t.... ./` for directory timestamp changes and `>f..t....` for time-only file changes.
**Why it happens:** rsync --archive syncs permissions and timestamps by default
**How to avoid:** Filter to only `>f` lines (file transfers) for the diff output. Further filter: `>f++++++++` = new file, any other `>f` = modified. Ignore `.d` (directory) and `.f` (no-change metadata) lines. For content-only diffs, could add `--checksum` flag to rsync (slower but accurate).
**Warning signs:** `>f..t....` entries (time-only) — these ARE real changes (file was touched) but may confuse users. Consider `--content-only` flag to suppress time-only changes.

### Pitfall 4: Large Archived Directories = Slow Scan
**What goes wrong:** Projects with many files and long retention create thousands of entries in archived/. Scanning all of them for snapshot discovery is slow.
**Why it happens:** 60-day retention with hourly backups = potentially thousands of archived versions per file
**How to avoid:** Cache snapshot list; use `find -maxdepth 1` for top-level scan first; offer `--recent N` flag to limit to last N snapshots
**Warning signs:** Diff command takes >5 seconds on large projects

### Pitfall 5: Deleted File Detection Requires --delete Flag
**What goes wrong:** Without `--delete` in the rsync dry-run, files that exist in the backup but NOT in the working directory won't show up in the diff.
**Why it happens:** By default rsync only shows files that would be transferred (source → dest). `--delete` adds `*deleting` lines for dest-only files.
**How to avoid:** Always use `rsync --delete --dry-run` for current-vs-backup comparison. Parse `*deleting` lines separately from `>f` lines. Verified format: `*deleting   TESTING-REPORT.md` (with spaces before filename).
**Warning signs:** Diff shows no removed files even when user knows they deleted things

### Pitfall 6: Missing Backup Directory
**What goes wrong:** User runs `checkpoint diff` in a project without backups configured, or backup directory is on disconnected drive
**Why it happens:** New project or external drive backup
**How to avoid:** Check `load_backup_config()` succeeds and backup dirs exist before attempting diff; use existing `check_drive()` for drive verification
**Warning signs:** Cryptic error messages instead of helpful "no backups found" message
</common_pitfalls>

<code_examples>
## Code Examples

### rsync Itemize-Changes Format (Verified)
```
# rsync --itemize-changes output format: YXcstpoguax filename
#
# Position 1 (Y): Update type
#   > = transferred to destination (received)
#   < = transferred to source (sent)
#   c = local change/creation (directory)
#   . = not updated (metadata only)
#   * = message (e.g., "*deleting")
#
# Position 2 (X): File type
#   f = regular file, d = directory, L = symlink
#
# Positions 3-11: Attribute changes (letter = changed, . = unchanged, + = new)
#   c=checksum, s=size, t=time, p=perms, o=owner, g=group, u=reserved, a=ACL, x=xattr
#
# VERIFIED against real Checkpoint backup output:
#   >f++++++++  .shellcheckrc        # NEW file (all +)
#   >f.st....   README.md            # MODIFIED (size + time changed)
#   >f..t....   CONTEXT_DIGEST.md    # MODIFIED (time only — treat as modified)
#   >f.stp...   .gitignore           # MODIFIED (size + time + perms)
#   .d..t....   ./                   # DIRECTORY metadata change (ignore)
#   *deleting   TESTING-REPORT.md    # DELETED from backup (only in destination)
```

### rsync --dry-run for Current-vs-Backup Comparison
```bash
# Source: rsync man page + verified against Checkpoint's actual backup
# Compare working directory against backup files/ mirror
# CRITICAL: Use --delete flag to detect files removed from source
rsync --archive --no-links --dry-run --delete --itemize-changes \
    --out-format="%i %n" \
    "$PROJECT_DIR/" "$FILES_DIR/" 2>/dev/null | while IFS= read -r line; do
        if [[ "$line" == '*deleting'* ]]; then
            # File exists in backup but not in working dir
            local filename="${line#\*deleting   }"
            echo "-  $filename"
        elif [[ "$line" == '>f'* ]]; then
            local flags="${line:0:11}"
            local filename="${line:12}"
            if [[ "$flags" == *'++++++++'* ]]; then
                echo "+  $filename"    # New file (not in backup yet)
            else
                echo "M  $filename"    # Modified file
            fi
        fi
        # Ignore directory entries (.d...) and metadata-only changes
    done
```

### Discover Available Snapshots from Archived Directory
```bash
# Extract unique backup timestamps from archived/ file suffixes
# MUST handle BOTH patterns: .YYYYMMDD_HHMMSS_PID and .YYYYMMDD_HHMMSS
discover_snapshots() {
    local archived_dir="$1"

    find "$archived_dir" -type f 2>/dev/null | \
        sed -n 's/.*\.\([0-9]\{8\}_[0-9]\{6\}\)\(_[0-9]*\)\{0,1\}$/\1/p' | \
        sort -u -r  # Most recent first
}

# VERIFIED output from this project's archived/:
# 20260216_175923
# 20260216_155104
# 20260216_043343
# 20260216_041304
# 20260216_031101
# 20260216_020909
# 20260215_192308
# 20260215_183928
# 20260215_170001
# 20260215_165031
```

### Extract Timestamp from Archived Filename (Fixed)
```bash
# IMPORTANT: The existing extract_timestamp() in retention-policy.sh (line 81)
# DOES NOT handle files without PID suffix (e.g., backup-now.sh.20260216_031101).
# The diff command needs this fixed version:
extract_timestamp_fixed() {
    local filename="$1"
    # Pattern 1: name.ext.YYYYMMDD_HHMMSS_PID (from backup-now.sh)
    if [[ "$filename" =~ \.([0-9]{8}_[0-9]{6})_[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
    # Pattern 2: name.ext.YYYYMMDD_HHMMSS (from backup-daemon.sh, no PID)
    elif [[ "$filename" =~ \.([0-9]{8}_[0-9]{6})$ ]]; then
        echo "${BASH_REMATCH[1]}"
    # Pattern 3: name_YYYYMMDD_HHMMSS.ext (database backups)
    elif [[ "$filename" =~ _([0-9]{8}_[0-9]{6})\. ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}
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

    # Find all archived versions, extract timestamps, sort newest first
    while IFS= read -r version; do
        local ts
        ts=$(extract_timestamp_fixed "$(basename "$version")")
        [[ -z "$ts" ]] && continue
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

1. **Snapshot reconstruction accuracy** — PARTIALLY RESOLVED
   - What we know: Archived files have timestamps of when they were replaced. Both PID and no-PID patterns are now understood. Timestamps use LOCAL time by default (UTC opt-in via `USE_UTC_TIMESTAMPS`).
   - What's resolved: Timestamp extraction works with fixed regex. Snapshot discovery verified against real data (10 unique snapshots found in this project).
   - What's still unclear: Mixed UTC/local timestamps in same archive (if config changed mid-stream). Edge case: what happens if multiple backups run in same second without PID suffix (daemon).
   - Recommendation: For v1, support current-vs-backup comparison (rsync --dry-run) and snapshot listing. Snapshot-vs-snapshot comparison as stretch goal.

2. **Content-level diffs** — RESOLVED
   - Decision: Default to file-list-only (like restic/borg). For specific file content diff, user can run `diff <(cat working/file) backups/files/file` manually, or we add `checkpoint diff <file>` to show content diff of a specific file against its backup copy.
   - The backup files/ directory is a plain mirror, so standard `diff` works directly.

3. **Database snapshot diffing** — RESOLVED (DEFERRED)
   - Decision: For v1, show database snapshots as a timeline only (list available snapshots with sizes/dates). Actual DB diffing requires decompressing `.db.gz`, comparing SQLite schemas/data — too complex for this phase.

4. **`extract_timestamp()` bug fix scope** — NEW
   - What we know: `retention-policy.sh:81` has a bug — doesn't handle `.YYYYMMDD_HHMMSS` (no PID) pattern. 11 files in this project's archived/ are affected.
   - What's unclear: Whether fixing `extract_timestamp()` could break existing retention logic (tiered pruning). Likely safe since it would just include more files in pruning consideration.
   - Recommendation: Fix `extract_timestamp()` in this phase as a prerequisite, with test coverage. The diff command needs it, and it fixes a latent bug in retention.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Checkpoint codebase: `bin/backup-now.sh` — rsync backup execution with `--backup --suffix` pattern (line 951: timestamp format, line 1051: rsync flags)
- Checkpoint codebase: `lib/features/backup-discovery.sh` — existing `list_file_versions_sorted()`
- Checkpoint codebase: `lib/ops/file-ops.sh` — existing `get_file_hash()`, `files_identical_hash()`
- Checkpoint codebase: `lib/retention-policy.sh:81` — `extract_timestamp()` with verified bug
- Checkpoint codebase: `backups/archived/` — 62 real archived files inspected, both suffix patterns confirmed
- rsync man page — `--dry-run`, `--itemize-changes`, `--out-format`, `--delete` options
- **Verified rsync output** — ran `rsync --dry-run -i --delete` against actual Checkpoint backup; confirmed `>f++++++++` (new), `>f.st....` (modified), `*deleting` (removed) formats

### Secondary (MEDIUM confidence)
- [restic diff man page](https://manpages.ubuntu.com/manpages/jammy/man1/restic-diff.1.html) — output format (`+/-/M/U/T`), `--metadata` flag, `--json` output
- [borg diff documentation](https://borgbackup.readthedocs.io/en/stable/usage/diff.html) — byte-level diff, `--content-only`, `--json-lines`, `--sort` options
- [rsync itemize-changes reference](https://gist.github.com/sblask/c551442f28d8f700579832ce5a80eca9) — complete YXcstpoguax format documentation
- [rsync dry-run patterns](https://www.baeldung.com/linux/rsync-output-changed-files-list) — `--itemize-changes` format for directory comparison

### Tertiary (LOW confidence - needs validation)
- None — all findings verified against real backup data or official sources
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
