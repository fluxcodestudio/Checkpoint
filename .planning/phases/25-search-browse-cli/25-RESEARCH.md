# Phase 25: Backup Search & Browse CLI - Research

**Researched:** 2026-02-16
**Domain:** Bash CLI tools — interactive backup browsing, file search, version history
**Confidence:** HIGH

<research_summary>
## Summary

Researched patterns for building interactive backup search/browse/history CLI commands in bash. The existing Checkpoint codebase already has strong foundations: `backup-discovery.sh` provides `list_file_versions_sorted()` and `list_database_backups_sorted()`, `backup-diff.sh` provides `discover_snapshots()`, and the CLI follows a consistent `checkpoint-*.sh` + bootstrap pattern.

The standard approach for interactive browsing is fzf with preview windows, falling back to bash `select` when fzf is unavailable. For searching across snapshots, grep/ripgrep with pre-filtering by date range is the established pattern. Industry-standard backup tools (restic, borg) use a two-level hierarchy: list snapshots first, then drill into files — this maps well to Checkpoint's existing archived/ structure.

**Primary recommendation:** Build three commands (`browse`, `search`, `history`) using fzf for interactive selection with bash `select` fallback. Leverage existing discovery functions heavily — most of the data plumbing already exists.

**Critical finding from deep dive:** `checkpoint history` and `checkpoint diff --list-snapshots` already exist in checkpoint-diff.sh. Phase 25 should EXTEND these with interactive fzf browsing, add `search` as a new command, and upgrade `browse` to a snapshot file explorer — not re-implement what exists.
</research_summary>

<standard_stack>
## Standard Stack

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| fzf | Interactive fuzzy finder/selector | De facto standard for interactive CLI selection; preview windows, multi-select, key bindings |
| grep/ripgrep | Content search across snapshots | grep is universal; rg is 4-40x faster for large trees |
| diff | File version comparison | Universal, unified diff format understood everywhere |
| bash `select` | Fallback interactive menu | Built into bash itself, zero dependencies |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| dialog | TUI menus | Already used in Checkpoint for config wizards |
| tree | Directory visualization | Preview window in browse mode |
| zgrep | Search compressed files | When searching .gz backup archives |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| fzf | skim (sk) | Rust-based fzf clone, nearly identical API; fzf has wider adoption |
| fzf | dialog --menu | No fuzzy search, no preview, but already a dependency |
| ripgrep | parallel xargs grep | rg faster out of box, but grep+xargs is more portable |

### No Installation Required
fzf is the only new external tool. All other dependencies (grep, diff, bash select, dialog) already exist in the Checkpoint ecosystem or are system-provided. fzf detection with graceful fallback means it's optional.
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Project Structure
```
bin/
├── checkpoint-search.sh     # Search, browse, history CLI (new)
└── checkpoint.sh            # Add routing for search/browse/history subcommands

lib/features/
└── backup-discovery.sh      # EXISTING - already has list_file_versions_sorted(),
                             #   list_database_backups_sorted(), discover_snapshots()
```

### Pattern 1: Two-Level Browse Hierarchy (from restic/borg)
**What:** List snapshots first, then drill into files within selected snapshot
**When to use:** `checkpoint browse` command
**How it maps to Checkpoint:**
- Level 1: `discover_snapshots($archived_dir)` → list timestamps
- Level 2: List files matching that timestamp in archived/ directory
- Preview: Show file metadata, size, encryption status

### Pattern 2: fzf with Graceful Fallback
**What:** Detect fzf availability, fall back to bash select
**When to use:** Any interactive selection
**Example:**
```bash
select_item() {
    local prompt="$1"; shift
    local items=("$@")

    if command -v fzf >/dev/null 2>&1; then
        printf '%s\n' "${items[@]}" | fzf --prompt="$prompt " --preview='...'
    else
        PS3="$prompt "
        select item in "${items[@]}"; do
            [[ -n "$item" ]] && echo "$item" && break
        done
    fi
}
```

### Pattern 3: Output Format Trinity (from CLI best practices)
**What:** Human-readable default, --json for scripts, --plain for piping
**When to use:** All commands that produce listings
**Example:**
```bash
# Human-readable (default, TTY detected)
checkpoint history src/main.sh
# → Colored table with timestamps, sizes, relative times

# JSON for scripts
checkpoint history --json src/main.sh
# → JSON array of version objects

# Plain for piping to fzf/grep/xargs
checkpoint history --plain src/main.sh
# → One path per line, no color
```

### Pattern 4: Progressive Disclosure
**What:** Summary first, drill-down on demand, suggest next steps
**When to use:** All output
**Example:** After listing snapshots, suggest: `Use 'checkpoint browse <timestamp>' to explore files`

### Pattern 5: fzf Drill-Down with Reload (from deep dive)
**What:** Two-level navigation within a single fzf session using `reload` + `change-prompt`
**When to use:** Browse command — select snapshot, then explore files in it
**Example:**
```bash
# Level 1: Show snapshots
# On ENTER: reload with files for that snapshot, change prompt
discover_snapshots "$archived_dir" | fzf \
    --prompt="Snapshots > " \
    --header "ENTER: browse files | CTRL-R: refresh" \
    --preview="find '$archived_dir' -name '*{}*' -type f | head -20" \
    --bind "enter:reload(find '$archived_dir' -name '*{}*' -type f)+change-prompt(Files > )+change-header(ENTER: view file | ESC: back)"
```
**Verdict:** Practical for 2 levels. For 3+ levels, chain separate fzf calls instead.

### Pattern 6: fzf Formatted Columns with Delimiter
**What:** Pipe tab-delimited data into fzf, display formatted columns, search specific fields
**When to use:** Snapshot/version listings with metadata
**Example:**
```bash
# Generate: timestamp\tsize\trelative_time\tpath
# Display all columns, search only path (field 4)
generate_listing | fzf \
    --delimiter '\t' \
    --with-nth 1,2,3,4 \
    --nth 4 \
    --ansi \
    --preview 'cat {4}'
```

### Anti-Patterns to Avoid
- **Dumping all files across all snapshots at once:** Always filter first (by date, by file pattern)
- **Requiring fzf:** Must work without it via bash select fallback
- **Searching compressed/encrypted files by default:** Too slow; search metadata/paths first, content only when explicitly requested
- **Building a custom fuzzy matcher:** fzf does this perfectly
- **Re-implementing history/list-snapshots:** These already work in checkpoint-diff.sh — extend, don't duplicate
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Interactive fuzzy selection | Custom arrow-key menu | fzf | Fuzzy matching, preview, multi-select, key bindings — years of polish |
| File version listing | Custom find+sort+parse | `list_file_versions_sorted()` | Already exists in backup-discovery.sh, handles .age suffix, sorts by mtime |
| Snapshot discovery | Custom timestamp extraction | `discover_snapshots()` | Already exists in backup-diff.sh, handles all timestamp formats |
| Relative time display | Custom date math | `format_relative_time()` | Already exists in time-size-utils.sh |
| Human-readable sizes | Custom byte formatting | `format_bytes()` | Already exists in time-size-utils.sh |
| Encryption awareness | Custom .age detection | `encryption_enabled()` + `decrypt_file()` | Already exists in encryption.sh |
| Exclude patterns | Custom ignore lists | `get_backup_excludes()` | Already centralized in config.sh |
| Bootstrap/path setup | Custom path resolution | `source bootstrap.sh` | Existing pattern for all bin/ scripts |

**Key insight:** The Checkpoint codebase already has ~80% of the data layer needed for search/browse/history. The new work is primarily the **UI/interaction layer** (fzf integration, output formatting, command routing) and **search across content** (grep across archived files). Don't rebuild what backup-discovery.sh and backup-diff.sh already provide.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Performance Death by Searching All Snapshots
**What goes wrong:** `checkpoint search "pattern"` greps through every file in every snapshot — takes minutes on large backup sets
**Why it happens:** Archived/ can contain thousands of file versions across many timestamps
**How to avoid:** Always filter first: by date range (`--since`, `--last N`), by file pattern (`--glob`), by snapshot. Search metadata/paths by default, content search only with explicit `--content` flag
**Warning signs:** Search command taking >5 seconds

### Pitfall 2: Encrypted Files Break Search/Preview
**What goes wrong:** Attempting to grep or preview .age encrypted files produces binary garbage
**Why it happens:** .age files are encrypted binary, not text
**How to avoid:** Detect .age suffix, use `decrypt_file()` to temp file before preview/search. For search, warn user that encrypted files require decryption (slower). Skip encrypted files by default in content search unless `--decrypt` flag is passed
**Warning signs:** Binary content in preview windows, grep matching binary data

### Pitfall 3: fzf Not Available on Server/Minimal Systems
**What goes wrong:** Script errors or crashes when fzf isn't installed
**Why it happens:** fzf is not pre-installed on most systems
**How to avoid:** Always check `command -v fzf` and fall back to bash `select`. Non-interactive mode (`--plain` output) should work with zero external dependencies
**Warning signs:** Script works on dev machine but fails on server

### Pitfall 4: Timestamp Format Inconsistency
**What goes wrong:** Some archived files have `_PID` suffix, some don't; `.age` suffix complicates extraction
**Why it happens:** Archive naming evolved over time, encryption adds suffix
**How to avoid:** Use existing `extract_timestamp()` from retention-policy.sh — it already handles all formats
**Warning signs:** "No snapshots found" when snapshots clearly exist

### Pitfall 5: Large File Lists Overwhelm Terminal
**What goes wrong:** Printing 10,000+ file paths to terminal scrolls past useful context
**Why it happens:** No pagination or limiting by default
**How to avoid:** Default to `--limit 50` or similar, show count of remaining. In fzf mode this is handled naturally (fzf scrolls). In fallback mode, implement pagination
**Warning signs:** Command output >100 lines in non-fzf mode
</common_pitfalls>

<code_examples>
## Code Examples

### fzf Snapshot Browser with Preview
```bash
# Source: fzf docs + Checkpoint patterns
browse_snapshots() {
    local archived_dir="$1"
    local snapshots
    snapshots=$(discover_snapshots "$archived_dir")

    if [[ -z "$snapshots" ]]; then
        echo "No snapshots found." >&2
        return 1
    fi

    if command -v fzf >/dev/null 2>&1; then
        local selected
        selected=$(echo "$snapshots" | fzf \
            --prompt="Select snapshot > " \
            --preview="echo 'Files in snapshot:'; ls '$archived_dir' | grep {} | head -30" \
            --preview-window="right:50%:wrap")
        echo "$selected"
    else
        local snap_array
        mapfile -t snap_array <<< "$snapshots"
        PS3="Select snapshot: "
        select snap in "${snap_array[@]}"; do
            [[ -n "$snap" ]] && echo "$snap" && break
        done
    fi
}
```

### File History with Existing Discovery Functions
```bash
# Source: Checkpoint backup-discovery.sh patterns
show_file_history() {
    local file_path="$1"
    local files_dir="$FILES_DIR"
    local archived_dir="$ARCHIVED_DIR"

    # Uses existing function — returns mtime|version|created|relative|size_human|path
    local versions
    versions=$(list_file_versions_sorted "$file_path" "$files_dir" "$archived_dir")

    if [[ -z "$versions" ]]; then
        echo "No versions found for: $file_path" >&2
        return 1
    fi

    # Format as table
    printf "%-20s %-10s %-15s %s\n" "TIMESTAMP" "SIZE" "AGE" "PATH"
    printf "%-20s %-10s %-15s %s\n" "---------" "----" "---" "----"
    while IFS='|' read -r mtime version created relative size_human path; do
        printf "%-20s %-10s %-15s %s\n" "$created" "$size_human" "$relative" "$path"
    done <<< "$versions"
}
```

### Search with Scope Filtering
```bash
# Source: restic/borg CLI patterns adapted for Checkpoint
search_backups() {
    local pattern="$1"
    local search_scope="${2:-paths}"  # paths|content
    local archived_dir="$ARCHIVED_DIR"

    case "$search_scope" in
        paths)
            # Fast: search filenames only
            find "$archived_dir" -type f -name "*${pattern}*" | head -50
            ;;
        content)
            # Slower: grep file contents, skip .age files
            if command -v rg >/dev/null 2>&1; then
                rg --glob '!*.age' -l "$pattern" "$archived_dir" | head -50
            else
                grep -rl --exclude='*.age' "$pattern" "$archived_dir" | head -50
            fi
            ;;
    esac
}
```

### fzf Browse with Diff Preview (from deep dive)
```bash
# Source: fzf ADVANCED.md + git-fuzzy patterns
browse_file_versions() {
    local file_path="$1"
    local current_file="$FILES_DIR/$file_path"

    # Pipe version listing into fzf with diff preview
    list_file_versions_sorted "$file_path" "$FILES_DIR" "$ARCHIVED_DIR" | \
        fzf --delimiter '|' \
            --with-nth 3,5,4 \
            --ansi \
            --header $'ENTER: restore | CTRL-D: diff against current\n' \
            --header-first \
            --preview "diff --color=always '$current_file' {6} 2>/dev/null || cat {6}" \
            --preview-window "right:60%:wrap" \
            --bind "ctrl-d:change-preview(diff --color=always '$current_file' {6})" \
            --bind "ctrl-c:change-preview(cat {6})"
}
```

### List Files at Snapshot (new function needed)
```bash
# Source: Checkpoint archived/ directory structure analysis
list_files_at_snapshot() {
    local archived_dir="$1"
    local timestamp="$2"

    # Find all files matching this timestamp (with or without PID suffix)
    find "$archived_dir" -type f -name "*.${timestamp}*" 2>/dev/null | \
        while read -r path; do
            local relpath="${path#$archived_dir/}"
            # Strip timestamp suffix to get original filename
            local original
            original=$(echo "$relpath" | sed "s/\.${timestamp}\(_[0-9]*\)\?\(\.age\)\?$//")
            local size
            size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null)
            local encrypted=""
            [[ "$path" == *.age ]] && encrypted=" [encrypted]"
            printf "%s\t%s\t%s%s\n" "$original" "$(format_bytes "$size")" "$relpath" "$encrypted"
        done | sort
}
```
</code_examples>

<existing_overlap>
## Existing Functionality (Deep Dive)

### What Already Exists — DO NOT REBUILD

| Feature | Location | Details |
|---------|----------|---------|
| **`checkpoint history <file>`** | checkpoint-diff.sh:236-292 | Lists all versions of a file with table output (# / Version / Date / Age / Size) |
| **`checkpoint diff --list-snapshots`** | checkpoint-diff.sh:155-230 | Lists available snapshots with dates and relative times |
| **`checkpoint diff`** | checkpoint-diff.sh:297-358 | Compares working dir to backup (added/modified/removed) |
| **`--json` output** | checkpoint-diff.sh:176,257,348 | JSON output for all three modes above |
| **`discover_snapshots()`** | backup-diff.sh:39-52 | Extracts unique YYYYMMDD_HHMMSS timestamps from archived/ |
| **`list_file_versions_sorted()`** | backup-discovery.sh:46-85 | Returns pipe-delimited `mtime\|version\|created\|relative\|size_human\|path` |
| **`list_database_backups_sorted()`** | backup-discovery.sh:21-43 | Returns pipe-delimited `created\|relative\|size_human\|filename\|path` |
| **`get_file_at_snapshot()`** | backup-diff.sh:236-312 | Finds the closest archived version at or before a given timestamp |
| **`compare_current_to_backup()`** | backup-diff.sh:62-127 | rsync dry-run, sets DIFF_ADDED/MODIFIED/REMOVED arrays |
| **`format_diff_text/json()`** | backup-diff.sh:137-224 | Formats diff output for display |

### What's MISSING — Phase 25 Scope

| Feature | Description | Dependencies |
|---------|-------------|-------------|
| **`checkpoint browse`** | Interactive fzf snapshot explorer — pick snapshot, browse its files, preview/restore | `discover_snapshots()`, fzf, new UI layer |
| **`checkpoint search <pattern>`** | Search across backup file paths and optionally content | `find`, grep/rg, new command |
| **List files BY snapshot**  | Given a timestamp, list all files that were archived at that point | New function needed — `find "$archived_dir" -name "*.$timestamp*"` |
| **fzf interactive mode for history** | Upgrade existing `checkpoint history` with fzf version picker + diff preview | Existing `list_file_versions_sorted()` + fzf |
| **Content search across snapshots** | grep/rg across archived file contents with .age handling | New function, encryption awareness |
| **Cross-project search** | Search across all 42 registered projects' backups | `projects.json` registry + scoped search |

### CLI Routing (checkpoint.sh Lines 582-695)

Existing routing pattern — new commands insert before `--dashboard`:
```bash
# Existing routes:
diff|--diff)     → exec checkpoint-diff.sh "$@"
history)         → exec checkpoint-diff.sh "history" "$@"
verify|--verify) → exec backup-verify.sh "$@"

# New routes needed:
search|--search)   → exec checkpoint-search.sh "$@"
browse|--browse)   → exec checkpoint-search.sh "browse" "$@"
```

### Real Backup Data Profile (This Project)

| Metric | Value |
|--------|-------|
| Current files in mirror | 202 |
| Archived versions | 62 |
| Total backup size | ~8.8 MB |
| Encrypted (.age) files | 0 |
| Compressed (.db.gz) databases | 0 |
| Timestamp format | `YYYYMMDD_HHMMSS` with optional `_PID` |
| Directory structure | Nested (mirrors project: archived/bin/, archived/lib/, etc.) |
| Registered projects | 42 total |
| Largest project backup | ~650 MB (9 STAR - BE MUSIC: 700+ DB snapshots) |
</existing_overlap>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| bash `select` for menus | fzf with preview | fzf mature since 2020+ | Much better UX for large lists |
| grep for search | ripgrep (rg) | rg stable since 2018 | 4-40x faster on large trees |
| Monolithic JSON output | JSON Lines (--json-lines) | borg/restic pattern | Streaming-friendly for large result sets |
| Plain text output only | Output format trinity (human/json/plain) | CLI best practices 2024+ | Better scripting integration |

**New tools/patterns to consider:**
- **fzf --bind for multi-mode UI**: Single fzf session can switch between views using key bindings (e.g., Ctrl-S for snapshots, Ctrl-F for files)
- **Progressive disclosure**: Show summary, suggest drill-down command — standard UX pattern in modern CLIs

**Deprecated/outdated:**
- **Interactive dialog menus for search**: Dialog is fine for config wizards but poor for search/browse (no fuzzy matching, no preview)
- **Dumping all results at once**: Modern CLIs paginate or use interactive scrolling
</sota_updates>

<open_questions>
## Open Questions

1. **Should `checkpoint browse` use fzf reload for two-level drill-down or chain separate fzf calls?**
   - What we know: fzf `reload` + `change-prompt` works well for 2 levels. Chaining is simpler to maintain but less fluid.
   - Deep dive finding: Single-session is practical for snapshot→files (2 levels). State management gets unwieldy at 3+ levels.
   - Recommendation: Use single-session fzf with `reload` for the snapshot→files drill-down. Fall back to chained calls if `select` is used.

2. **Should content search decrypt .age files by default?**
   - What we know: Decryption adds significant latency. This project has 0 encrypted files, but encryption is a supported feature.
   - Recommendation: Skip encrypted files by default with a notice. Offer `--decrypt` flag to include them.

3. **Should `checkpoint search` support cross-project search?**
   - What we know: 42 projects in registry. Searching all would be very slow (650+ MB for largest project alone).
   - Recommendation: Default to current project. Offer `--all-projects` flag that warns about performance. Optionally `--project NAME` to search specific other projects.

4. **Should this be one script (checkpoint-search.sh) or separate scripts per command?**
   - What we know: Existing pattern uses dedicated scripts (checkpoint-diff.sh, checkpoint-encrypt.sh). But history already routes through checkpoint-diff.sh.
   - Recommendation: Single `checkpoint-search.sh` with modes (search, browse) since they share the fzf infrastructure. History stays in checkpoint-diff.sh but gets an `--interactive` fzf upgrade.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Checkpoint codebase deep dive — checkpoint-diff.sh (359 lines, 3 modes), backup-discovery.sh (86 lines, 2 functions), backup-diff.sh (313 lines, 5 functions), checkpoint.sh routing (lines 582-695), encryption.sh, retention-policy.sh
- Real backup data analysis — 202 current files, 62 archived versions, nested directory structure, YYYYMMDD_HHMMSS_PID timestamp format
- fzf GitHub repo + ADVANCED.md — reload/transform drill-down, preview windows, --delimiter/--with-nth, --header, key bindings
- restic docs — snapshots, ls, find, diff CLI patterns (two-level hierarchy)
- borg docs — list, diff, --format strings, --json-lines streaming output

### Secondary (MEDIUM confidence)
- fzf practical guides (thevaluable.dev) — git explorer patterns, preview modes, color handling
- ripgrep benchmarks (burntsushi.net) — 4-40x faster than grep on large trees
- CLI UX best practices (clig.dev, Atlassian, Evil Martians) — output format trinity, progressive disclosure
- git-fuzzy, forgit, fzf-navigator — real-world fzf file browser implementations on GitHub

### Tertiary (LOW confidence - needs validation)
- None — all findings verified against official sources or existing codebase
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Bash CLI with fzf for interactive browsing
- Ecosystem: fzf, grep/ripgrep, diff, existing Checkpoint discovery functions
- Patterns: Two-level browse hierarchy, output format trinity, fzf+select fallback
- Pitfalls: Performance with large archives, encrypted file handling, fzf availability

**Confidence breakdown:**
- Standard stack: HIGH - fzf is the established tool, grep/diff are universal
- Architecture: HIGH - patterns from restic/borg are proven, existing codebase provides foundations
- Pitfalls: HIGH - verified against Checkpoint's actual backup structure and encryption features
- Code examples: HIGH - based on existing Checkpoint functions and fzf documentation

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days - bash CLI tools are stable ecosystem)
</metadata>

---

*Phase: 25-search-browse-cli*
*Research completed: 2026-02-16*
*Ready for planning: yes*
