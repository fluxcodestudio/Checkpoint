# Phase 19: AI Tool Artifact Backup - Research

**Researched:** 2026-02-16
**Domain:** AI coding tool directory structures, rsync gitignore override patterns
**Confidence:** HIGH

<research_summary>
## Summary

Researched the complete directory structures of all major AI coding tools (Claude Code, Cursor, Aider, Windsurf, Cline, Continue.dev, GitHub Copilot) to determine which files to back up. Each tool creates project-level configuration and session data that is typically gitignored but highly valuable.

Key finding: The implementation is straightforward — append AI tool directories/files to the existing rsync `--files-from` list. No new rsync flags or second pass needed. The main complexity is detecting which tools are present and filtering out cache/temp data.

**Primary recommendation:** After generating the git file list, detect AI tool directories and append them to the `--files-from` list. Exclude known cache directories (`.aider.tags.cache*`, `.windsurf/` cache, `.cline/` cache). Keep it additive — never modify existing backup behavior.
</research_summary>

<standard_stack>
## AI Tool Directory Inventory

### Claude Code
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.claude/settings.local.json` | Config | HIGH | Project permissions, auto-approved commands |
| `.claude/project-memory.md` | Memory | HIGH | Project knowledge accumulates over time |
| `.claude/commands/` | Config | HIGH | Custom slash commands |
| `.claude/skills/` | Config | VERY HIGH | Custom project skills (code + config) |
| `.claude/sessions.json` | Session | LOW | Session PIDs, regenerates |
| `.claude/vibe-state.md` | Session | LOW | Current task state |
| `.claude/.last_branch` | Session | LOW | Git state tracking |
| `.claude/.vibe-session` | Session | LOW | Session UUID |
| `CLAUDE.md` | Config | HIGH | Project instructions (usually committed) |

**Backup pattern:** `.claude/` directory (include all — small, mostly valuable)
**Exclude:** `.claude/.DS_Store`

### Cursor
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.cursor/rules/*.mdc` | Config | HIGH | AI rules in Markdown Cursor format |
| `.cursorrules` | Config | MEDIUM | Legacy rules (deprecated, still supported) |
| `.cursorignore` | Config | HIGH | Security exclusion patterns |
| `.cursorindexingignore` | Config | MEDIUM | Indexing exclusion patterns |

**Backup pattern:** `.cursor/rules/` directory + root-level `.cursor*` files
**Exclude:** `.cursor/` cache data (indexing cache, not in rules/)

### Aider
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.aider.chat.history.md` | History | HIGH | Full conversation history |
| `.aider.input.history` | History | MEDIUM | Command recall history |
| `.aider.conf.yml` | Config | HIGH | Project-specific settings |
| `.aider.model.settings.yml` | Config | HIGH | Model configuration |
| `.aiderignore` | Config | HIGH | Exclusion patterns |
| `.aider.tags.cache.v*` | Cache | NONE | Regenerates automatically |

**Backup pattern:** `.aider*` files EXCEPT `.aider.tags.cache*`
**Exclude:** `.aider.tags.cache.v3/`, `.aider.tags.cache.v4/` (large, regenerates)

### Windsurf
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.windsurf/rules/*.md` | Config | HIGH | Cascade AI rules (6K char limit/file) |
| `.windsurfrules` | Config | MEDIUM | Legacy rules (deprecated) |
| `.codeiumignore` | Config | MEDIUM | Indexing exclusion patterns |

**Backup pattern:** `.windsurf/rules/` directory + `.windsurfrules` + `.codeiumignore`
**Exclude:** `.windsurf/` cache data (indexing, not in rules/)

### Cline
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.clinerules` | Config | HIGH | Single-file AI rules |
| `.clinerules/` | Config | HIGH | Multi-file rules directory (newer format) |
| `.clineignore` | Config | MEDIUM | Exclusion patterns |

**Backup pattern:** `.clinerules` file or `.clinerules/` directory + `.clineignore`

### Continue.dev
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.continuerc.json` | Config | HIGH | Project-specific Continue config |
| `.continuerc.js` | Config | HIGH | Programmatic config |
| `.continuerc.ts` | Config | HIGH | TypeScript config |
| `.continue/` | Config | MEDIUM | Local Continue directory |

**Backup pattern:** `.continuerc.*` files + `.continue/` directory

### GitHub Copilot
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.github/copilot-instructions.md` | Config | HIGH | Repo-wide AI instructions |
| `.github/instructions/*.instructions.md` | Config | HIGH | Path-specific instructions |

**Backup pattern:** `.github/copilot-instructions.md` + `.github/instructions/`
**Note:** `.github/` is often already committed to git, so may already be backed up

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hardcoded tool list | Auto-detect from file patterns | Auto-detect is fragile, new tools need updates anyway |
| Back up everything in `.*/` | Selective backup | Too aggressive, would catch `.git/`, `.venv/`, etc. |
| Separate rsync pass | Append to file list | Two passes = more complexity, worse atomicity |
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Implementation Location in backup-now.sh

The AI artifact detection should happen AFTER the git file list is generated (after line ~870) and BEFORE the rsync call (line ~923). This is the natural insertion point.

```
Current flow:
1. Generate git file list → $filtered_files
2. rsync --files-from=$filtered_files → $FILES_DIR

New flow:
1. Generate git file list → $filtered_files
2. NEW: Detect AI tool artifacts → append to $filtered_files
3. rsync --files-from=$filtered_files → $FILES_DIR (unchanged)
```

### Pattern 1: Append to Existing File List (RECOMMENDED)

**What:** After generating the git-tracked file list, detect AI tool directories and append their paths to the same file list. One rsync call handles everything.

**Why:** Maintains atomic backup, works with existing dual-write secondary rsync, no changes to rsync flags.

```bash
# After filtered_files is populated with git-tracked files...
_append_ai_artifacts() {
    local file_list="$1"
    local project_dir="$2"

    # Directories to include recursively
    local ai_dirs=(.claude .cursor/rules .windsurf/rules .clinerules .continue)

    for dir in "${ai_dirs[@]}"; do
        if [ -d "$project_dir/$dir" ]; then
            # Find all files in dir, output relative paths
            find "$project_dir/$dir" -type f -not -name '.DS_Store' \
                -printf '%P\n' 2>/dev/null | \
                while read -r f; do
                    echo "$dir/$f"
                done >> "$file_list"
        fi
    done

    # Individual files to include
    local ai_files=(
        .aider.chat.history.md
        .aider.input.history
        .aider.conf.yml
        .aider.model.settings.yml
        .aiderignore
        .cursorrules
        .cursorignore
        .cursorindexingignore
        .windsurfrules
        .codeiumignore
        .clinerules
        .clineignore
        .continuerc.json
        .continuerc.js
        .continuerc.ts
        .github/copilot-instructions.md
        CLAUDE.md
    )

    for file in "${ai_files[@]}"; do
        [ -f "$project_dir/$file" ] && echo "$file" >> "$file_list"
    done

    # Also include .github/instructions/ if it exists
    if [ -d "$project_dir/.github/instructions" ]; then
        find "$project_dir/.github/instructions" -name '*.instructions.md' -type f \
            -printf '.github/instructions/%P\n' 2>/dev/null >> "$file_list"
    fi

    # Deduplicate (some files may already be in git)
    sort -u "$file_list" -o "$file_list"
}
```

### Pattern 2: Configuration-Driven (for user control)

```bash
# In project .checkpoint or global config:
AI_ARTIFACT_BACKUP=true          # master toggle
AI_ARTIFACT_EXTRA_DIRS=""        # user-added directories
AI_ARTIFACT_EXTRA_FILES=""       # user-added files
```

### Anti-Patterns to Avoid
- **Globbing `.*/` directories:** Would catch .git/, .venv/, .node_modules/, etc.
- **Using rsync --include/--exclude with --files-from:** They don't interact — include/exclude cannot ADD files to a --files-from list
- **Separate rsync pass:** Breaks atomic backup, complicates dual-write, doubles error handling
- **Parsing .gitignore:** Unnecessary — rsync doesn't read .gitignore. Just add files to the list.
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| .gitignore parsing | Custom parser for .gitignore | Skip entirely — rsync ignores .gitignore | rsync uses its own filter system, not git's |
| Recursive file listing | Custom walk function | `find` with `-printf '%P\n'` | Handles symlinks, permissions, edge cases |
| Deduplication | Custom dedup logic | `sort -u` on the file list | Git files + AI files may overlap if some are committed |
| Tool detection | Complex heuristic | Simple `[ -d ".claude" ]` checks | Each tool has a known, stable directory name |

**Key insight:** The hardest part of this feature is NOT the implementation — it's knowing what each AI tool creates. The implementation itself is ~30 lines of bash that appends paths to an existing file list.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Backing Up Cache Directories
**What goes wrong:** `.aider.tags.cache.v4/` contains a SQLite database that can be 50-200MB and regenerates automatically.
**Why it happens:** Matching `.aider*` too broadly.
**How to avoid:** Explicitly exclude cache patterns: `.aider.tags.cache*`
**Warning signs:** Backup size suddenly jumps 100MB+ for a small project

### Pitfall 2: find -printf Not Available on macOS
**What goes wrong:** GNU `find -printf` doesn't exist on macOS BSD `find`.
**Why it happens:** macOS uses BSD userland, not GNU.
**How to avoid:** Use `find ... | sed "s|^$dir/||"` or the existing platform detection in Checkpoint.
**Warning signs:** `find: -printf: unknown primary or operator`

### Pitfall 3: Trailing Slash Semantics in --files-from
**What goes wrong:** Adding `.claude` (no slash) to --files-from copies only the directory entry, not contents.
**Why it happens:** rsync treats directory paths differently based on trailing slash.
**How to avoid:** List individual files within directories, not directory names.
**Warning signs:** Empty backup directories, 0 files transferred for AI tools

### Pitfall 4: .windsurf/ Cache vs Rules
**What goes wrong:** Backing up all of `.windsurf/` includes indexing cache (can be 100MB+).
**Why it happens:** Only `.windsurf/rules/` is valuable; rest is cache.
**How to avoid:** Target `.windsurf/rules/` specifically, not all of `.windsurf/`.
**Warning signs:** Large backup sizes for Windsurf projects

### Pitfall 5: Race Condition with Active Sessions
**What goes wrong:** Claude Code's `sessions.json` or `.vibe-session` is being written while backup runs.
**Why it happens:** These files update during active sessions.
**How to avoid:** rsync handles this gracefully (exit code 23/24 = partial transfer, non-fatal). Already handled in backup-now.sh.
**Warning signs:** None — existing error handling covers this.
</common_pitfalls>

<code_examples>
## Code Examples

### Complete Implementation for backup-now.sh

```bash
# Source: Custom implementation based on research
# Insert after git file list generation, before rsync call

# ==============================================================================
# STEP 3.5: Include AI tool artifacts (even if gitignored)
# ==============================================================================
if [ "${AI_ARTIFACT_BACKUP:-true}" = "true" ]; then
    _ai_count=0

    # Directories: find files recursively, append relative paths
    for _ai_dir in .claude .cursor/rules .windsurf/rules .clinerules .continue; do
        if [ -d "$_ai_dir" ]; then
            while IFS= read -r _f; do
                [[ "$_f" == *".DS_Store" ]] && continue
                echo "$_f" >> "$filtered_files"
                ((_ai_count++)) || true
            done < <(find "$_ai_dir" -type f 2>/dev/null)
        fi
    done

    # Individual files
    for _ai_file in \
        .aider.chat.history.md .aider.input.history \
        .aider.conf.yml .aider.model.settings.yml .aiderignore \
        .cursorrules .cursorignore .cursorindexingignore \
        .windsurfrules .codeiumignore \
        .clineignore \
        .continuerc.json .continuerc.js .continuerc.ts \
        .github/copilot-instructions.md \
        CLAUDE.md
    do
        if [ -f "$_ai_file" ]; then
            echo "$_ai_file" >> "$filtered_files"
            ((_ai_count++)) || true
        fi
    done

    # .github/instructions/ directory (Copilot path-specific)
    if [ -d ".github/instructions" ]; then
        while IFS= read -r _f; do
            echo "$_f" >> "$filtered_files"
            ((_ai_count++)) || true
        done < <(find ".github/instructions" -name '*.instructions.md' -type f 2>/dev/null)
    fi

    # Deduplicate (some AI files may already be git-tracked)
    if [ "$_ai_count" -gt 0 ]; then
        _tmp=$(mktemp)
        sort -u "$filtered_files" > "$_tmp"
        mv "$_tmp" "$filtered_files"
        log_info "AI artifacts: $_ai_count files from AI coding tools included"
        cli_verbose "   AI artifacts: $_ai_count files included"
    fi
fi
```

### Config Toggle

```bash
# In global config (~/.config/checkpoint/config.sh):
AI_ARTIFACT_BACKUP=true    # Set to false to disable AI tool backup

# In per-project config (.checkpoint):
AI_ARTIFACT_BACKUP=false   # Disable for this project only
```

### Dashboard Display (for Swift SettingsView)

```swift
// In SettingsView, Advanced section:
Toggle("Back up AI tool files", isOn: $settings.aiArtifactBackup)
    .help("Include .claude/, .cursor/, .aider, .windsurf/ directories in backups")
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.cursorrules` (single file) | `.cursor/rules/*.mdc` (directory) | 2025 | Multiple organized rule files |
| `.windsurfrules` (single file) | `.windsurf/rules/*.md` (directory) | 2025 (Wave 8) | Multi-file rules with activation modes |
| `.clinerules` (single file) | `.clinerules/` (directory) | 2025 | Versioned, multi-file rules |
| No project instructions | `.github/copilot-instructions.md` | 2025 | Copilot now supports project-level rules |
| Aider tags cache v3 | Aider tags cache v4 | 2025 | Different cache directory name |

**New tools to watch:**
- **Cline** (.clinerules/, memory bank) — Growing rapidly as open-source VS Code agent
- **Continue.dev** (.continuerc.*, .continue/) — Privacy-focused, multi-model
- **GitHub Copilot** (.github/copilot-instructions.md) — Now supports project-level customization
- **Amazon Q Developer** — No project-level files yet, but growing market share

**Key trend:** Every AI coding tool is converging on the same pattern: a project-root directory with markdown rule files. The naming varies but the concept is identical.
</sota_updates>

<open_questions>
## Open Questions

1. **Should we back up ~/.claude/ global config?**
   - What we know: Global config (~/.claude/settings.json, skills/, commands/) is highly valuable but lives outside the project
   - What's unclear: Whether this belongs in project backup or a separate global backup
   - Recommendation: Phase 19 focuses on project-level only. Global backup is a separate feature.

2. **New AI tools appearing frequently**
   - What we know: New tools (Devin, Amazon Q, Tabnine) may create project files
   - What's unclear: Their directory patterns aren't standardized yet
   - Recommendation: Make the AI tool list configurable via `AI_ARTIFACT_EXTRA_DIRS` and `AI_ARTIFACT_EXTRA_FILES` in config

3. **Should AI artifacts have different retention than regular files?**
   - What we know: AI session data (chat history) may be more valuable long-term than code snapshots
   - What's unclear: Whether users want different retention policies
   - Recommendation: Use same retention as regular files for v3.0. Consider separate retention in future.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Claude Code .claude/ directory — direct filesystem inspection of actual project
- Claude Code docs: https://code.claude.com/docs/en/memory, https://code.claude.com/docs/en/settings
- Aider docs: https://aider.chat/docs/faq.html, https://aider.chat/docs/config/aider_conf.html
- Cursor docs: https://cursor.directory/, Cursor rules configuration guides
- Windsurf docs: https://docs.windsurf.com/windsurf/cascade/memories
- Cline docs: https://docs.cline.bot/cline-cli/configuration, https://cline.bot/blog/clinerules-version-controlled-shareable-and-ai-editable-instructions
- Continue docs: https://docs.continue.dev/customize/deep-dives/configuration
- GitHub Copilot docs: https://docs.github.com/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot

### Secondary (MEDIUM confidence)
- rsync --files-from behavior — verified with local testing and man page
- Tool directory structures — cross-referenced across multiple sources

### Tertiary (LOW confidence - needs validation)
- Amazon Q Developer project files — not enough info yet
- Exact size ranges for cache directories — varies by project
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: rsync --files-from extension, bash file detection
- Ecosystem: 7 AI coding tools inventoried (Claude Code, Cursor, Aider, Windsurf, Cline, Continue, Copilot)
- Patterns: Append-to-file-list, config toggle, cache exclusion
- Pitfalls: Cache bloat, macOS find, trailing slash, race conditions

**Confidence breakdown:**
- AI tool directories: HIGH - verified against official docs and actual filesystems
- rsync integration: HIGH - verified with existing backup-now.sh code and testing
- Pitfalls: HIGH - documented in rsync man pages and tool docs
- Code examples: HIGH - built on existing Checkpoint patterns

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days — AI tool directory structures are stable, but new tools appear frequently)
</metadata>

---

*Phase: 19-ai-tool-artifact-backup*
*Research completed: 2026-02-16*
*Ready for planning: yes*
