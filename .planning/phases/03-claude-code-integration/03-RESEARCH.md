# Phase 3: Claude Code Integration - Research

**Researched:** 2026-01-11
**Domain:** Claude Code hooks for automated backup triggering
**Confidence:** HIGH

<research_summary>
## Summary

Researched Claude Code's hooks mechanism for triggering automated backups. Claude Code provides 8 hook events that fire at specific points in its lifecycle. For backup automation, the key events are:

1. **Stop** - Fires when Claude finishes responding (conversation end)
2. **PostToolUse** with `Edit|Write` matcher - Fires after file modifications
3. **PostToolUse** with `Bash(git commit*)` matcher - Fires after git commits

Hooks are configured in `.claude/settings.json` (project-scoped) or `~/.claude/settings.json` (user-scoped). Each hook receives JSON via stdin with session info and can trigger shell scripts. Exit code 0 means success.

**Primary recommendation:** Use Stop hook for "conversation end" backup trigger. Use PostToolUse with Edit|Write matcher for "file changes" trigger. Use PostToolUse with Bash matcher filtered by `git commit` for commit triggers.
</research_summary>

<standard_stack>
## Standard Stack

### Core (built-in)
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Claude Code hooks | Built-in | Event triggering | Native mechanism, no dependencies |
| JSON stdin | Built-in | Event data | Standard hook input format |
| Shell scripts | Built-in | Hook commands | Executed via bash |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| jq | 1.7+ | Parse JSON stdin | Extract file paths, session info |
| bash | 4.0+ | Script execution | Hook command scripts |

### Project Configuration
| File | Location | Purpose |
|------|----------|---------|
| settings.json | .claude/settings.json | Project-scoped hooks |
| settings.local.json | .claude/settings.local.json | Local overrides (gitignored) |
| Hook scripts | .claude/hooks/*.sh | Executable hook handlers |

**No additional installation required.** Claude Code hooks are built-in.
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Project Structure
```
.claude/
├── settings.json           # Project hooks config (committed)
├── settings.local.json     # Local overrides (gitignored)
└── hooks/
    ├── backup-on-stop.sh       # Stop event handler
    ├── backup-on-edit.sh       # PostToolUse Edit/Write handler
    └── backup-on-commit.sh     # PostToolUse git commit handler
```

### Pattern 1: Stop Hook for Conversation End
**What:** Trigger backup when Claude finishes responding
**When to use:** "Conversation end" backup trigger
**Example:**
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/backup-on-stop.sh"
          }
        ]
      }
    ]
  }
}
```

Hook script receives JSON stdin:
```json
{
  "session_id": "eb5b0174-...",
  "transcript_path": "/Users/.../.jsonl",
  "cwd": "/path/to/project",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
```

### Pattern 2: PostToolUse for File Changes
**What:** Trigger backup after Claude edits/writes files
**When to use:** "File changes" backup trigger
**Example:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/backup-on-edit.sh"
          }
        ]
      }
    ]
  }
}
```

Hook script receives JSON stdin including:
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/modified/file.ts",
    "old_string": "...",
    "new_string": "..."
  },
  "cwd": "/path/to/project"
}
```

### Pattern 3: PostToolUse for Git Commits
**What:** Trigger backup after Claude makes a git commit
**When to use:** "Commit" backup trigger
**Example:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash(git commit*)",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/backup-on-commit.sh"
          }
        ]
      }
    ]
  }
}
```

### Anti-Patterns to Avoid
- **Triggering backup on every tool call:** Use specific matchers (Edit|Write, not *)
- **Blocking hooks for backup:** Use exit 0, don't block Claude's flow
- **Long-running hooks without timeout:** Set timeout to avoid blocking
- **Relying on PreToolUse for backup:** PostToolUse ensures operation completed
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Event detection | Custom file watcher in Claude | Claude Code hooks | Hooks are native, reliable, and event-driven |
| Session tracking | Parse transcript manually | session_id from stdin | Claude provides this automatically |
| File path extraction | Regex on tool output | jq on tool_input JSON | Structured data, reliable parsing |
| Debouncing in hooks | Complex timer logic | Call existing debounce script | Reuse Phase 2 debounce pattern |

**Key insight:** Claude Code hooks provide the event triggers. Our existing backup infrastructure (backup-daemon.sh, smart-backup-trigger.sh) handles the actual backup. Hooks just call the existing scripts.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Hook Timeout
**What goes wrong:** Hook takes >60s, gets killed
**Why it happens:** Default timeout is 60 seconds
**How to avoid:** Trigger backup-daemon.sh in background (non-blocking)
**Warning signs:** Hooks silently failing, backups not happening

### Pitfall 2: Blocking Claude with Exit Code 2
**What goes wrong:** Exit code 2 blocks tool execution
**Why it happens:** Exit 2 means "blocking error" in Claude Code
**How to avoid:** Always exit 0 for backup hooks (non-blocking)
**Warning signs:** Claude stops working, error messages

### Pitfall 3: Missing Project Detection
**What goes wrong:** Hook runs but can't find .backup-config.sh
**Why it happens:** Hook's cwd might not be project root
**How to avoid:** Use $cwd from JSON stdin, or resolve from script location
**Warning signs:** "Config not found" errors in hook logs

### Pitfall 4: Duplicate Backups
**What goes wrong:** Multiple hooks trigger multiple simultaneous backups
**Why it happens:** Stop + PostToolUse both fire, no coordination
**How to avoid:** Use file locking (already in backup-daemon.sh)
**Warning signs:** Multiple backup processes running
</common_pitfalls>

<code_examples>
## Code Examples

### Hook Script Template
```bash
#!/usr/bin/env bash
# Source: Claude Code hooks guide
set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract working directory
CWD=$(echo "$INPUT" | jq -r '.cwd')

# Change to project directory
cd "$CWD"

# Source project config if it exists
if [ -f .backup-config.sh ]; then
    source .backup-config.sh
fi

# Trigger backup (non-blocking, in background)
./bin/smart-backup-trigger.sh &

# Exit success (don't block Claude)
exit 0
```

### Extract File Path from Edit/Write
```bash
#!/usr/bin/env bash
# PostToolUse hook for Edit|Write
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

echo "File modified: $FILE_PATH via $TOOL_NAME" >> ~/.claudecode-backups/logs/edit-events.log
```

### Detect Git Commit
```bash
#!/usr/bin/env bash
# PostToolUse hook for Bash(git commit*)
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

if echo "$COMMAND" | grep -q "^git commit"; then
    echo "Commit detected: $COMMAND" >> ~/.claudecode-backups/logs/commit-events.log
fi
```

### settings.json Complete Example
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/backup-on-stop.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/backup-on-edit.sh",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "Bash(git commit*)",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/backup-on-commit.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual backup | Hooks automation | 2025 | Automatic triggers on Claude events |
| File watcher only | Hooks + watcher | 2025 | Hooks for Claude events, watcher for manual edits |
| Global config only | Project .claude/settings.json | 2025 | Per-project hook configuration |

**New capabilities:**
- **SubagentStop hook:** Fires when subagent tasks complete (useful for multi-agent workflows)
- **PreCompact hook:** Fires before context compaction (opportunity to save state)
- **Matcher argument patterns:** `Bash(git commit*)` matches specific commands
- **Hook JSON output:** Return `{"continue": true}` for sophisticated control

**Current limitations:**
- No native PreCommit/PostCommit hooks (use Bash matcher workaround)
- 60s default timeout (can be configured per hook)
- Hooks run with user permissions (security consideration)
</sota_updates>

<open_questions>
## Open Questions

1. **SessionStart vs Stop for backup?**
   - What we know: SessionStart fires on startup/resume, Stop fires on response end
   - What's unclear: Best event for "start of session" backup vs "end of conversation"
   - Recommendation: Use Stop for end-of-work backup (most meaningful point)

2. **Hook deduplication behavior?**
   - What we know: Claude deduplicates identical hook commands
   - What's unclear: Exact deduplication logic when same script called from multiple matchers
   - Recommendation: Use different scripts for different triggers to ensure all fire
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - Official documentation
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide) - Getting started guide
- [Anthropic Claude Blog: How to Configure Hooks](https://claude.com/blog/how-to-configure-hooks) - Official blog post

### Secondary (MEDIUM confidence)
- [GitButler Claude Code Hooks](https://docs.gitbutler.com/features/ai-integration/claude-code-hooks) - Integration example
- [Steve Kinney: Claude Code Hook Examples](https://stevekinney.com/courses/ai-development/claude-code-hook-examples) - Practical examples
- [SmartScope: Claude Code Hooks Complete Guide](https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/) - Comprehensive guide

### Tertiary (verified with official docs)
- GitHub issue #4834 - PreCommit/PostCommit feature request (confirms current workarounds)
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Claude Code hooks mechanism
- Ecosystem: JSON stdin, jq parsing, bash scripts
- Patterns: Stop, PostToolUse, matcher syntax
- Pitfalls: Timeouts, exit codes, project detection

**Confidence breakdown:**
- Standard stack: HIGH - verified with official docs
- Architecture: HIGH - from official examples and community patterns
- Pitfalls: HIGH - documented in official docs
- Code examples: HIGH - adapted from official sources

**Research date:** 2026-01-11
**Valid until:** 2026-02-11 (30 days - hooks API is stable)
</metadata>

---

*Phase: 03-claude-code-integration*
*Research completed: 2026-01-11*
*Ready for planning: yes*
