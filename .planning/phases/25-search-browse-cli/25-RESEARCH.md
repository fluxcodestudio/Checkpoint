# Phase 25: Backup Search & Browse CLI - Research

**Researched:** 2026-02-16
**Domain:** Bash CLI tools — interactive backup browsing, file search, version history
**Confidence:** HIGH

<research_summary>
## Summary

Researched patterns for building interactive backup search/browse/history CLI commands in bash. The existing Checkpoint codebase already has strong foundations: `backup-discovery.sh` provides `list_file_versions_sorted()` and `list_database_backups_sorted()`, `backup-diff.sh` provides `discover_snapshots()`, and the CLI follows a consistent `checkpoint-*.sh` + bootstrap pattern.

The standard approach for interactive browsing is fzf with preview windows, falling back to bash `select` when fzf is unavailable. For searching across snapshots, grep/ripgrep with pre-filtering by date range is the established pattern. Industry-standard backup tools (restic, borg) use a two-level hierarchy: list snapshots first, then drill into files — this maps well to Checkpoint's existing archived/ structure.

**Primary recommendation:** Build three commands (`browse`, `search`, `history`) using fzf for interactive selection with bash `select` fallback. Leverage existing discovery functions heavily — most of the data plumbing already exists.
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

### Anti-Patterns to Avoid
- **Dumping all files across all snapshots at once:** Always filter first (by date, by file pattern)
- **Requiring fzf:** Must work without it via bash select fallback
- **Searching compressed/encrypted files by default:** Too slow; search metadata/paths first, content only when explicitly requested
- **Building a custom fuzzy matcher:** fzf does this perfectly
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
</code_examples>

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

1. **Should `checkpoint browse` be a single multi-mode fzf session or separate drill-down commands?**
   - What we know: fzf supports switching views via --bind, but it adds complexity. Separate commands are simpler and more composable.
   - What's unclear: User preference for single interactive session vs pipeline-style commands
   - Recommendation: Start with separate commands (`browse` for snapshot selection, `search` for content, `history` for file versions). Add combined interactive mode later if needed.

2. **Should content search decrypt .age files by default?**
   - What we know: Decryption adds significant latency. Users may not realize their backups are encrypted.
   - What's unclear: How common is encryption usage among Checkpoint users?
   - Recommendation: Skip encrypted files by default with a notice. Offer `--decrypt` flag to include them. Show count of skipped encrypted files.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Checkpoint codebase analysis — backup-discovery.sh, backup-diff.sh, encryption.sh, checkpoint.sh CLI patterns, retention-policy.sh timestamp handling
- fzf GitHub repository and official documentation — preview, multi-select, key bindings, shell integration
- restic official documentation — snapshots, ls, find, diff command patterns
- borg official documentation — list, diff, format strings, JSON output patterns

### Secondary (MEDIUM confidence)
- ripgrep benchmark analysis (burntsushi.net) — performance comparisons verified against documentation
- CLI UX best practices (clig.dev, Atlassian) — output format trinity, progressive disclosure patterns
- fzf practical guides (thevaluable.dev) — preview window patterns, key binding customization

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
