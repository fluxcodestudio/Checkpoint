# Phase 19: AI Tool Artifact Backup - Research

**Researched:** 2026-02-16 (updated with deep dive)
**Domain:** AI coding tool directory structures, rsync gitignore override patterns, backup-now.sh integration
**Confidence:** HIGH

<research_summary>
## Summary

Researched the complete directory structures of **14 AI coding tools** to determine which project-level files to back up. Each tool creates configuration and session data that is typically gitignored but highly valuable for disaster recovery.

Key findings:
1. **14 tools inventoried** — Claude Code, Cursor, Aider, Windsurf, Cline (with Memory Bank), Continue.dev, GitHub Copilot, OpenAI Codex CLI, Augment Code, Tabnine, Amazon Q Developer, Sourcegraph Cody, JetBrains AI Assistant, Qodo
2. **Exact insertion point found** — After line 813 in backup-now.sh, inside the existing "critical files" block (lines 757-813), which already handles `.env`, credentials, IDE settings, etc. This is the perfect pattern to follow.
3. **All paths are relative** — `$filtered_files` uses paths relative to `$PROJECT_DIR`, matching `find` output with `sed 's|^\./||'`
4. **macOS `find -printf` doesn't exist** — Must use `find ... 2>/dev/null` (outputs relative paths since we're already cd'd to project dir)
5. **Cross-tool metadata files** — `AGENTS.md`, `CLAUDE.md`, `QODO.md` are emerging as shared standards

**Primary recommendation:** Add a new config flag `BACKUP_AI_ARTIFACTS=true` alongside the existing `BACKUP_ENV_FILES`, `BACKUP_CREDENTIALS`, `BACKUP_IDE_SETTINGS` pattern. Insert detection code after line 813 in backup-now.sh. Append AI tool paths to `$changed_files` before the filtering step at line 837.
</research_summary>

<standard_stack>
## AI Tool Directory Inventory

### Tier 1: Major AI Coding Tools (High Priority)

#### Claude Code
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.claude/settings.local.json` | Config | HIGH | Project permissions, 150+ auto-approved commands |
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
**Note:** `.claude/` is already included in cloud backup rsync (line 1441) but NOT in the main project file list

#### Cursor
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.cursor/rules/*.mdc` | Config | HIGH | AI rules in Markdown Cursor format, <50 lines each |
| `.cursorrules` | Config | MEDIUM | Legacy rules (deprecated, still supported) |
| `.cursorignore` | Config | HIGH | Security exclusion patterns |
| `.cursorindexingignore` | Config | MEDIUM | Indexing exclusion patterns |

**Backup pattern:** `.cursor/rules/` directory + root-level dotfiles
**Exclude:** `.cursor/` indexing cache (everything NOT in rules/)

#### Aider
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.aider.chat.history.md` | History | HIGH | Full conversation history, can be multi-MB |
| `.aider.input.history` | History | MEDIUM | Command recall history |
| `.aider.conf.yml` | Config | HIGH | Project-specific settings |
| `.aider.model.settings.yml` | Config | HIGH | Model configuration |
| `.aiderignore` | Config | HIGH | Exclusion patterns |
| `.aider.tags.cache.v*` | Cache | NONE | 50-200MB SQLite, regenerates |

**Backup pattern:** Named files only (NOT `.aider*` glob)
**Exclude:** `.aider.tags.cache.v3/`, `.aider.tags.cache.v4/` (large, regenerates)

#### Windsurf
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.windsurf/rules/*.md` | Config | HIGH | Cascade AI rules (6K char limit/file) |
| `.windsurfrules` | Config | MEDIUM | Legacy rules (deprecated) |
| `.codeiumignore` | Config | MEDIUM | Indexing exclusion patterns |

**Backup pattern:** `.windsurf/rules/` directory + `.windsurfrules` + `.codeiumignore`
**Exclude:** `.windsurf/` cache (indexing data, 1-100MB)

#### Cline
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.clinerules` | Config | HIGH | Single-file AI rules (older format) |
| `.clinerules/` | Config | HIGH | Multi-file rules directory (newer, version-controlled) |
| `.clineignore` | Config | MEDIUM | Exclusion patterns |
| `memory-bank/` | Memory | HIGH | 6 core markdown files (projectBrief, productContext, activeContext, systemPatterns, techContext, progress) |
| `cline_docs/` | Memory | HIGH | Alternative memory bank directory name |

**Backup pattern:** `.clinerules`, `.clinerules/`, `.clineignore`, `memory-bank/`, `cline_docs/`
**Note:** Memory Bank files are designed to be committed to git, but many users gitignore them

#### Continue.dev
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.continuerc.json` | Config | HIGH | Project-specific config |
| `.continuerc.js` | Config | HIGH | Programmatic config |
| `.continuerc.ts` | Config | HIGH | TypeScript config |
| `.continue/` | Config | MEDIUM | Local Continue directory |

**Backup pattern:** `.continuerc.*` files + `.continue/` directory

#### GitHub Copilot
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.github/copilot-instructions.md` | Config | HIGH | Repo-wide AI instructions |
| `.github/instructions/*.instructions.md` | Config | HIGH | Path-specific instructions |

**Backup pattern:** Specific files in `.github/`
**Note:** `.github/` is often already committed to git

### Tier 2: Newer/Emerging AI Tools (Medium Priority)

#### OpenAI Codex CLI
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.codex/config.toml` | Config | HIGH | Project-scoped config overrides |
| `.codex/skills/` | Config | HIGH | Project-specific skills (SKILL.md + scripts) |

**Backup pattern:** `.codex/` directory

#### Augment Code
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.augment/rules/*.md` | Config | HIGH | Workspace rules (Always/Manual/Auto types) |
| `.augment/guidelines.md` | Config | MEDIUM | Legacy format |

**Backup pattern:** `.augment/` directory

#### Amazon Q Developer
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.amazonq/rules/*.md` | Config | HIGH | Project rules and coding standards |

**Backup pattern:** `.amazonq/` directory

#### JetBrains AI Assistant
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.aiassistant/rules/*.md` | Config | HIGH | Project rules (Always/Manual types) |
| `.aiignore` | Config | MEDIUM | Exclusion patterns |

**Backup pattern:** `.aiassistant/` directory + `.aiignore`

#### Tabnine
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.tabnine` | Config | MEDIUM | Project configuration (JSON) |
| `.tabnine_commands` | Config | MEDIUM | Shared custom commands |

**Backup pattern:** `.tabnine`, `.tabnine_commands`

#### Qodo (formerly CodiumAI)
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.pr_agent.toml` | Config | HIGH | PR automation config |

**Backup pattern:** `.pr_agent.toml`

#### Sourcegraph Cody
| Path | Type | Backup Value | Notes |
|------|------|-------------|-------|
| `.vscode/cody.json` | Config | MEDIUM | Custom commands (VS Code only) |

**Backup pattern:** `.vscode/cody.json` (likely already backed up via IDE settings)

### Tier 3: Cross-Tool Metadata Files

| Path | Supported By | Backup Value | Notes |
|------|-------------|-------------|-------|
| `AGENTS.md` | Augment, Qodo, Cursor, JetBrains, most tools | HIGH | Open standard for AI agent instructions |
| `CLAUDE.md` | Claude Code, Augment, Qodo | HIGH | Claude-specific instructions |
| `QODO.md` | Qodo | MEDIUM | Qodo-specific metadata |
| `CONVENTIONS.md` | Aider | MEDIUM | Coding conventions (loaded via --read) |

### Tools With NO Project Files
- **Bolt.new / StackBlitz** — Cloud-only, generates standard framework code
- **Devin** — Cloud-based, no local project files

</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Exact Integration Point in backup-now.sh

**File:** `bin/backup-now.sh`
**Insert after:** Line 813 (after `.backup-config.sh` is added to `$changed_files`)
**Insert before:** Line 815 (the `if [ ! -s "$changed_files" ]` empty check)

The existing flow (lines 757-813) adds "critical files" to `$changed_files` based on config flags:
```
Line 758:  BACKUP_ENV_FILES=true     → .env files
Line 762:  BACKUP_CREDENTIALS=true   → *.pem, *.key, AWS config, etc.
Line 789:  BACKUP_IDE_SETTINGS=true  → .vscode/, .idea/
Line 799:  BACKUP_LOCAL_NOTES=true   → NOTES.md, *.private.md
Line 806:  BACKUP_LOCAL_DATABASES=true → *.db, *.sqlite
Line 813:  Always                    → .backup-config.sh
```

**New addition follows the same pattern:**
```
Line 814+: BACKUP_AI_ARTIFACTS=true  → AI tool directories and files
```

### Complete Flow Diagram

```
1. cd "$PROJECT_DIR" (line 684)
2. Populate $changed_files (lines 686-755)
   ├─ First backup: git ls-files (ALL tracked)
   ├─ Incremental: git diff + git status (changed only)
   └─ Non-git fallback: find with mtime
3. Add critical files to $changed_files (lines 757-813)
   ├─ .env, credentials, IDE settings, notes, databases
   └─ NEW: AI tool artifacts (insert here)
4. Filter → $filtered_files (lines 837-870)
   ├─ sort -u + remove backups/ paths
   ├─ Remove symlinks
   └─ Check file size limits
5. rsync --files-from=$filtered_files ./ $FILES_DIR/ (line 923)
```

### Pattern: Follow the Existing "Critical Files" Convention

```bash
# After line 813, following the exact same pattern as lines 757-813:

# AI tool artifacts
if [ "${BACKUP_AI_ARTIFACTS:-true}" = "true" ]; then
    _ai_count=0

    # --- Directories (find files recursively) ---
    for _ai_dir in \
        .claude .cursor/rules .windsurf/rules .clinerules \
        .continue .codex .augment .amazonq .aiassistant \
        memory-bank cline_docs
    do
        if [ -d "$_ai_dir" ]; then
            while IFS= read -r _f; do
                case "$_f" in */.DS_Store|*__pycache__*) continue ;; esac
                echo "$_f" >> "$changed_files"
                ((_ai_count++)) || true
            done < <(find "$_ai_dir" -type f 2>/dev/null)
        fi
    done

    # --- Individual files ---
    for _ai_file in \
        CLAUDE.md AGENTS.md QODO.md CONVENTIONS.md \
        .aider.chat.history.md .aider.input.history \
        .aider.conf.yml .aider.model.settings.yml .aiderignore \
        .cursorrules .cursorignore .cursorindexingignore \
        .windsurfrules .codeiumignore \
        .clineignore \
        .continuerc.json .continuerc.js .continuerc.ts \
        .github/copilot-instructions.md \
        .aiignore .pr_agent.toml \
        .tabnine .tabnine_commands
    do
        [ -f "$_ai_file" ] && echo "$_ai_file" >> "$changed_files" && ((_ai_count++)) || true
    done

    # --- Copilot path-specific instructions ---
    if [ -d ".github/instructions" ]; then
        while IFS= read -r _f; do
            echo "$_f" >> "$changed_files"
            ((_ai_count++)) || true
        done < <(find ".github/instructions" -name '*.instructions.md' -type f 2>/dev/null)
    fi

    # --- User-defined extra dirs/files ---
    if [ -n "${AI_ARTIFACT_EXTRA_DIRS:-}" ]; then
        IFS=',' read -ra _extra_dirs <<< "$AI_ARTIFACT_EXTRA_DIRS"
        for _ed in "${_extra_dirs[@]}"; do
            _ed=$(echo "$_ed" | tr -d '[:space:]')
            if [ -d "$_ed" ]; then
                while IFS= read -r _f; do
                    echo "$_f" >> "$changed_files"
                    ((_ai_count++)) || true
                done < <(find "$_ed" -type f 2>/dev/null)
            fi
        done
    fi

    [ "$_ai_count" -gt 0 ] && {
        log_info "AI artifacts: added $_ai_count files from AI coding tools"
        cli_verbose "   AI tool files: $_ai_count files included"
    }
fi
```

### Config Variables to Add

**In `lib/core/config.sh` (alongside existing BACKUP_* flags):**
```bash
: "${BACKUP_AI_ARTIFACTS:=true}"        # Back up AI tool config/history
: "${AI_ARTIFACT_EXTRA_DIRS:=}"         # Comma-separated extra directories
: "${AI_ARTIFACT_EXTRA_FILES:=}"        # Comma-separated extra files
```

**In `templates/global-config-template.sh`:**
```bash
# Back up AI coding tool artifacts (.claude/, .cursor/, .aider, etc.)
DEFAULT_BACKUP_AI_ARTIFACTS=true
```

**In `templates/backup-config.sh`:**
```bash
# AI Tool Artifacts — include .claude/, .cursor/, .aider, .windsurf/ etc.
BACKUP_AI_ARTIFACTS=true
# Extra directories to include (comma-separated, relative to project root)
AI_ARTIFACT_EXTRA_DIRS=""
# Extra files to include (comma-separated, relative to project root)
AI_ARTIFACT_EXTRA_FILES=""
```

### Anti-Patterns to Avoid
- **Globbing `.*/` directories:** Would catch .git/, .venv/, .node_modules/, etc.
- **Using rsync --include/--exclude with --files-from:** They don't interact — include/exclude cannot ADD files to a --files-from list
- **Separate rsync pass:** Breaks atomic backup, complicates dual-write, doubles error handling
- **Parsing .gitignore:** Unnecessary — rsync doesn't read .gitignore. Just add files to the list.
- **Using `find -printf`:** Not available on macOS BSD `find`. Use plain `find` output (already relative since we cd'd to project dir)
- **Adding to $filtered_files:** Wrong variable — add to `$changed_files` so they go through the same filtering pipeline (dedup, symlink check, size check)
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| .gitignore parsing | Custom parser for .gitignore | Skip entirely — rsync ignores .gitignore | rsync uses its own filter system, not git's |
| Recursive file listing | Custom walk function | `find "$dir" -type f 2>/dev/null` | Already in project dir, outputs relative paths |
| Deduplication | Custom dedup logic | Existing `sort -u` on line 840 | Filtering step already deduplicates |
| Tool detection | Complex heuristic | Simple `[ -d ".claude" ]` checks | Each tool has a known, stable directory name |
| Config variable | New config system | Follow existing `BACKUP_*` pattern | `BACKUP_ENV_FILES`, `BACKUP_CREDENTIALS`, etc. already exist |

**Key insight:** This feature slots perfectly into the existing "critical files" architecture (lines 757-813). No new patterns needed — just a new config flag and a list of paths.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Backing Up Cache Directories
**What goes wrong:** `.aider.tags.cache.v4/` contains a SQLite database that can be 50-200MB and regenerates automatically. `.windsurf/` cache can be 100MB+. `.cursor/` indexing cache is large.
**Why it happens:** Matching too broadly (`.aider*`, all of `.windsurf/`, all of `.cursor/`).
**How to avoid:** Target specific subdirectories: `.cursor/rules/` not `.cursor/`, `.windsurf/rules/` not `.windsurf/`. Use named files for Aider, not glob.
**Warning signs:** Backup size suddenly jumps 100MB+ for a small project.

### Pitfall 2: find -printf Not Available on macOS
**What goes wrong:** GNU `find -printf '%P\n'` doesn't exist on macOS BSD `find`.
**Why it happens:** macOS uses BSD userland, not GNU.
**How to avoid:** Don't use `-printf`. Since we've already `cd`'d to `$PROJECT_DIR` (line 684), `find .claude -type f` outputs `./claude/settings.local.json` which works fine, or use `find .claude -type f 2>/dev/null` which outputs `.claude/settings.local.json` (relative to cwd). The existing non-git fallback on line 730 uses `sed 's|^\./||'` if needed.
**Warning signs:** `find: -printf: unknown primary or operator`

### Pitfall 3: Adding to Wrong Variable
**What goes wrong:** Adding paths to `$filtered_files` instead of `$changed_files` means they skip the dedup/filter pipeline.
**Why it happens:** `$filtered_files` is the final file list, but it's created from `$changed_files` via sort -u and filtering.
**How to avoid:** Add to `$changed_files` (same as other critical files on lines 757-813). The filtering step at lines 837-870 handles dedup, symlink removal, and size checks.
**Warning signs:** Duplicate entries in backup, symlinks being followed.

### Pitfall 4: Trailing Slash Semantics in --files-from
**What goes wrong:** Adding `.claude/` (directory path) to --files-from doesn't work as expected.
**Why it happens:** rsync `--files-from` expects individual file paths, not directory names.
**How to avoid:** List individual files via `find`, not directory names. The `find "$dir" -type f` pattern outputs individual file paths.
**Warning signs:** 0 files transferred for AI tools.

### Pitfall 5: Cline Memory Bank Has Two Directory Names
**What goes wrong:** Missing `cline_docs/` backup because only checking `memory-bank/`.
**Why it happens:** Cline community uses two naming conventions: `memory-bank/` (official) and `cline_docs/` (alternative).
**How to avoid:** Check both directory names.
**Warning signs:** Cline users report missing memory bank backups.

### Pitfall 6: Race Condition with Active Sessions
**What goes wrong:** Files being written while backup runs.
**Why it happens:** These files update during active AI sessions.
**How to avoid:** rsync handles this gracefully (exit code 23/24 = partial transfer, non-fatal). Already handled in backup-now.sh.
**Warning signs:** None — existing error handling covers this.
</common_pitfalls>

<code_examples>
## Code Examples

### Complete Implementation for backup-now.sh

```bash
# Source: Custom implementation following existing "critical files" pattern
# Insert after line 813 in backup-now.sh (after .backup-config.sh)
# Add to $changed_files (NOT $filtered_files) to go through filtering pipeline

# ==============================================================================
# Include AI coding tool artifacts (even if gitignored)
# ==============================================================================
if [ "${BACKUP_AI_ARTIFACTS:-true}" = "true" ]; then
    _ai_count=0

    # Directories: find individual files recursively
    for _ai_dir in \
        .claude .cursor/rules .windsurf/rules .clinerules \
        .continue .codex .augment .amazonq .aiassistant \
        memory-bank cline_docs
    do
        if [ -d "$_ai_dir" ]; then
            while IFS= read -r _f; do
                case "$_f" in */.DS_Store) continue ;; esac
                echo "$_f" >> "$changed_files"
                ((_ai_count++)) || true
            done < <(find "$_ai_dir" -type f 2>/dev/null)
        fi
    done

    # Individual files (config, history, ignore patterns)
    for _ai_file in \
        CLAUDE.md AGENTS.md QODO.md CONVENTIONS.md \
        .aider.chat.history.md .aider.input.history \
        .aider.conf.yml .aider.model.settings.yml .aiderignore \
        .cursorrules .cursorignore .cursorindexingignore \
        .windsurfrules .codeiumignore \
        .clineignore \
        .continuerc.json .continuerc.js .continuerc.ts \
        .github/copilot-instructions.md \
        .aiignore .pr_agent.toml \
        .tabnine .tabnine_commands
    do
        [ -f "$_ai_file" ] && {
            echo "$_ai_file" >> "$changed_files"
            ((_ai_count++)) || true
        }
    done

    # Copilot path-specific instructions
    if [ -d ".github/instructions" ]; then
        while IFS= read -r _f; do
            echo "$_f" >> "$changed_files"
            ((_ai_count++)) || true
        done < <(find ".github/instructions" -name '*.instructions.md' -type f 2>/dev/null)
    fi

    # User-defined extra directories
    if [ -n "${AI_ARTIFACT_EXTRA_DIRS:-}" ]; then
        IFS=',' read -ra _extra_dirs <<< "$AI_ARTIFACT_EXTRA_DIRS"
        for _ed in "${_extra_dirs[@]}"; do
            _ed=$(echo "$_ed" | tr -d '[:space:]')
            [ -d "$_ed" ] && while IFS= read -r _f; do
                echo "$_f" >> "$changed_files"
                ((_ai_count++)) || true
            done < <(find "$_ed" -type f 2>/dev/null)
        done
    fi

    # User-defined extra files
    if [ -n "${AI_ARTIFACT_EXTRA_FILES:-}" ]; then
        IFS=',' read -ra _extra_files <<< "$AI_ARTIFACT_EXTRA_FILES"
        for _ef in "${_extra_files[@]}"; do
            _ef=$(echo "$_ef" | tr -d '[:space:]')
            [ -f "$_ef" ] && {
                echo "$_ef" >> "$changed_files"
                ((_ai_count++)) || true
            }
        done
    fi

    [ "$_ai_count" -gt 0 ] && {
        log_info "AI artifacts: added $_ai_count files from AI coding tools"
        cli_verbose "   AI tool files: $_ai_count files included"
    }
fi
```

### Config Variables (lib/core/config.sh)

```bash
# AI Tool Artifacts (alongside existing BACKUP_* flags)
: "${BACKUP_AI_ARTIFACTS:=true}"
: "${AI_ARTIFACT_EXTRA_DIRS:=}"
: "${AI_ARTIFACT_EXTRA_FILES:=}"
```

### Global Config Defaults (apply_global_defaults function)

```bash
DEFAULT_BACKUP_AI_ARTIFACTS)  : "${BACKUP_AI_ARTIFACTS:=$value}" ;;
```

### Dashboard Settings (Swift SettingsView)

```swift
// In "What to Backup" section, alongside existing toggles:
Toggle("AI tool files (.claude, .cursor, .aider, etc.)",
       isOn: $settings.backupAiArtifacts)
```

### checkpoint.sh Status Display

```bash
# In the info/status output, show detected AI tools:
_detected_tools=""
[ -d ".claude" ] && _detected_tools="${_detected_tools}Claude Code, "
[ -d ".cursor" ] && _detected_tools="${_detected_tools}Cursor, "
[ -f ".aider.conf.yml" ] && _detected_tools="${_detected_tools}Aider, "
[ -d ".windsurf" ] && _detected_tools="${_detected_tools}Windsurf, "
[ -f ".clinerules" ] || [ -d ".clinerules" ] && _detected_tools="${_detected_tools}Cline, "
[ -n "$_detected_tools" ] && echo "AI tools detected: ${_detected_tools%, }"
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
| No cross-tool standard | `AGENTS.md` emerging | 2025-2026 | Open standard for AI agent instructions |
| No Codex CLI | `.codex/config.toml` + `.codex/skills/` | 2025 | OpenAI's CLI creates project files |
| No Amazon Q rules | `.amazonq/rules/*.md` | 2025 | AWS tool now has project rules |
| No JetBrains AI rules | `.aiassistant/rules/*.md` | 2025 | JetBrains adopted rule file pattern |

**Key convergence trend:** Every AI coding tool is converging on the same pattern: a `.toolname/rules/` directory with markdown files. The naming varies but the architecture is identical. This makes detection straightforward — check for known directory names.

**New tools to monitor:**
- **Devin** — Cloud-only currently, but may add local project files
- **Amazon Q Developer** — `.amazonq/rules/` now confirmed
- **Augment Code** — `.augment/rules/` directory with 3 activation modes
- **OpenAI Codex CLI** — `.codex/` with config.toml and skills/
</sota_updates>

<open_questions>
## Open Questions

1. **Should we back up ~/.claude/ global config?**
   - What we know: Global config (~/.claude/settings.json, skills/, commands/) is highly valuable but lives outside the project
   - What's unclear: Whether this belongs in project backup or a separate global backup
   - Recommendation: Phase 19 focuses on project-level only. Global tool backup is a separate future feature.

2. **Cline Memory Bank naming inconsistency**
   - What we know: `memory-bank/` is official, `cline_docs/` is community alternative
   - What's unclear: Whether future Cline versions will standardize on one name
   - Recommendation: Check both directories. Low cost, prevents missed backups.

3. **Should AI artifacts have different retention?**
   - What we know: AI session data (chat history) may be more valuable long-term than code snapshots
   - What's unclear: Whether users want different retention policies
   - Recommendation: Use same retention as regular files for v3.0. Consider separate retention in future.

4. **AGENTS.md as universal instruction file**
   - What we know: Growing adoption as cross-tool standard alongside tool-specific files
   - What's unclear: Whether it will truly become universal or fragment
   - Recommendation: Back it up. It's one file, and its value only increases.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Claude Code .claude/ — direct filesystem inspection + https://code.claude.com/docs/en/memory
- Cursor .cursor/rules/ — https://cursor.directory/, https://workos.com/blog/what-are-cursor-rules
- Aider — https://aider.chat/docs/faq.html, https://aider.chat/docs/config/aider_conf.html
- Windsurf — https://docs.windsurf.com/windsurf/cascade/memories, https://docs.windsurf.com/context-awareness/windsurf-ignore
- Cline — https://docs.cline.bot/cline-cli/configuration, https://cline.bot/blog/memory-bank-how-to-make-cline-an-ai-agent-that-never-forgets
- Continue — https://docs.continue.dev/customize/deep-dives/configuration
- GitHub Copilot — https://docs.github.com/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot
- OpenAI Codex CLI — https://developers.openai.com/codex/config-basic/, https://developers.openai.com/codex/config-advanced/
- Augment Code — https://docs.augmentcode.com/setup-augment/guidelines
- Amazon Q — https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/context-project-rules.html
- JetBrains AI — https://www.jetbrains.com/help/ai-assistant/configure-project-rules.html
- Qodo — https://qodo-merge-docs.qodo.ai/usage-guide/configuration_options/
- AGENTS.md standard — https://layer5.io/blog/ai/agentsmd-one-file-to-guide-them-all

### Secondary (MEDIUM confidence)
- rsync --files-from behavior — verified with man page and existing backup-now.sh code
- backup-now.sh integration point — verified by reading lines 757-870

### Tertiary (LOW confidence - needs validation)
- Exact Cline memory bank file sizes — varies heavily by usage
- Future tool directory names (Devin, etc.) — speculative
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: rsync --files-from extension, bash file detection
- Ecosystem: 14 AI coding tools inventoried
- Patterns: Append-to-changed-files, BACKUP_AI_ARTIFACTS config flag, cache exclusion
- Pitfalls: Cache bloat, macOS find, wrong variable, trailing slash, dual naming

**Confidence breakdown:**
- AI tool directories: HIGH - verified against official docs, actual filesystems, web research
- rsync integration: HIGH - verified exact insertion point in backup-now.sh (after line 813)
- Pitfalls: HIGH - documented with specific line numbers and variable names
- Code examples: HIGH - follows existing critical files pattern exactly

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days — directory structures are stable, but new tools appear frequently)
</metadata>

---

*Phase: 19-ai-tool-artifact-backup*
*Research completed: 2026-02-16*
*Ready for planning: yes*
