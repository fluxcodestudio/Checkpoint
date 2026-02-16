# Phase 2: Activity Triggers - Research

**Researched:** 2026-01-11
**Domain:** File watching with debounced backup triggering (macOS/bash)
**Confidence:** HIGH

<research_summary>
## Summary

Researched file system monitoring and debouncing patterns for triggering backups after periods of file inactivity. The standard approach on macOS uses `fswatch` with its native FSEvents backend (installed via Homebrew), combined with bash-based debouncing logic.

Key finding: fswatch's `--one-per-batch` mode combined with a bash debounce wrapper provides exactly what's needed - wait for file changes to stop for N seconds, then trigger backup. Don't hand-roll file system event handling; fswatch abstracts platform differences and handles edge cases.

**Primary recommendation:** Use fswatch with FSEvents backend, exclude patterns via `-e` flags, pipe through simple bash debounce logic that kills/restarts a timer on each event. Trigger backup-daemon.sh after 60s of quiet.
</research_summary>

<standard_stack>
## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| fswatch | 1.18.3 | File system monitoring | Native FSEvents on macOS, cross-platform, battle-tested |
| bash | 3.2+ | Debounce logic | Already in use, no dependencies, macOS native |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| launchd | native | Daemon management | Watcher persistence across reboots |
| mktemp | native | Temp files for state | Debounce PID tracking |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| fswatch | watchman | More complex client/server, overkill for this use case |
| fswatch | chokidar | Requires Node.js, adds dependency |
| fswatch | entr | Simpler but less flexible exclude patterns |
| bash debounce | debounce.sh lib | External dependency for simple logic |

**Installation:**
```bash
brew install fswatch
```
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Project Structure
```
bin/
├── backup-watcher.sh      # Main watcher script (Phase 2)
├── backup-daemon.sh       # Existing backup execution (Phase 1)
└── smart-backup-trigger.sh # Existing Claude hook trigger

lib/
└── watcher-lib.sh         # Debounce logic, exclude patterns (optional)
```

### Pattern 1: fswatch with Batch Mode + Debounce
**What:** Use `--one-per-batch` to get single notifications, pipe through debounce
**When to use:** Default approach for this phase
**Example:**
```bash
# Source: fswatch wiki + community patterns
DEBOUNCE_SECONDS=60
DEBOUNCE_PID=""

fswatch -o -r \
  -e "node_modules" \
  -e "\.git" \
  -e "backups/" \
  "$PROJECT_DIR" | while read -r _count; do
    # Kill existing timer
    [ -n "$DEBOUNCE_PID" ] && kill "$DEBOUNCE_PID" 2>/dev/null

    # Start new timer
    (sleep $DEBOUNCE_SECONDS && ./backup-daemon.sh) &
    DEBOUNCE_PID=$!
done
```

### Pattern 2: File-based Debounce State
**What:** Use temp file to track timer PID for cross-process coordination
**When to use:** When watcher and trigger are separate processes
**Example:**
```bash
# Source: MerkleBros/debounce.sh pattern
STATE_FILE="$HOME/.claudecode-backups/state/${PROJECT_NAME}/watcher.pid"

debounce_trigger() {
    local delay="$1"
    local action="$2"

    # Kill existing timer
    if [ -f "$STATE_FILE" ]; then
        kill "$(cat "$STATE_FILE")" 2>/dev/null || true
        rm -f "$STATE_FILE"
    fi

    # Start new timer in background
    (
        sleep "$delay"
        rm -f "$STATE_FILE"
        eval "$action"
    ) &
    echo $! > "$STATE_FILE"
}
```

### Pattern 3: LaunchAgent for Persistence
**What:** Run watcher as a LaunchAgent so it survives terminal close
**When to use:** Production deployment
**Example:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claudecode.backup-watcher.${PROJECT_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/backup-watcher.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>${PROJECT_DIR}</string>
</dict>
</plist>
```

### Anti-Patterns to Avoid
- **Polling with find/stat:** CPU-intensive, doesn't scale, misses rapid changes
- **fswatch without excludes:** Will watch node_modules, .git, causing noise
- **Triggering backup on every event:** No debouncing leads to duplicate backups
- **Foreground watcher:** Dies when terminal closes, unreliable
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File system events | Polling with find/stat | fswatch | FSEvents is kernel-level, efficient, catches all events |
| Exclude patterns | grep filters on paths | fswatch `-e` | Built-in regex, applied before events emitted |
| Recursive watching | Manual directory traversal | fswatch `-r` | Handles new directories automatically |
| Daemon persistence | Manual backgrounding | LaunchAgent | Survives reboot, proper process management |
| Cross-platform events | Separate inotify/FSEvents code | fswatch | Abstracts platform differences |

**Key insight:** File system event handling has decades of platform-specific edge cases (symlinks, renames, atomic writes, permissions). fswatch wraps the native APIs correctly. Hand-rolling leads to missed events and race conditions.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Watching Too Much
**What goes wrong:** Watcher triggers on node_modules changes, build artifacts
**Why it happens:** Default fswatch watches everything recursively
**How to avoid:** Always use `-e` to exclude heavy directories:
```bash
fswatch -e "node_modules" -e "\.git" -e "backups/" -e "\.cache"
```
**Warning signs:** Constant backup triggers during `npm install` or `git operations`

### Pitfall 2: Debounce Timer Not Killed
**What goes wrong:** Multiple backup-daemon.sh instances run simultaneously
**Why it happens:** New events don't cancel pending timer
**How to avoid:** Track PID, kill before starting new timer, use file lock in daemon
**Warning signs:** Log shows overlapping backup cycles, lock contention

### Pitfall 3: Watcher Dies Silently
**What goes wrong:** File changes stop triggering backups
**Why it happens:** Process killed, terminal closed, error not caught
**How to avoid:**
- Use LaunchAgent with `KeepAlive`
- Log errors to persistent location
- Health check in status command
**Warning signs:** No backup for hours despite active development

### Pitfall 4: Race with Manual/Hook Triggers
**What goes wrong:** Watcher and Claude hook both trigger backup at same time
**Why it happens:** File change (watcher) + conversation end (hook) = double trigger
**How to avoid:** Existing backup-daemon.sh has file locking - coordinate via same lock
**Warning signs:** Log shows "Another backup is currently running" frequently

### Pitfall 5: Hanging on fswatch Pipe
**What goes wrong:** Script blocks forever, can't cleanly stop watcher
**Why it happens:** `while read` blocks, no signal handling
**How to avoid:**
- Trap SIGTERM/SIGINT to kill fswatch
- Store fswatch PID for clean shutdown
**Warning signs:** `kill` on watcher script doesn't stop fswatch process
</common_pitfalls>

<code_examples>
## Code Examples

Verified patterns from official sources and project conventions:

### Complete Watcher Script Structure
```bash
#!/usr/bin/env bash
# Source: fswatch wiki + project conventions
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$PWD}"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-60}"
STATE_DIR="$HOME/.claudecode-backups/state/$(basename "$PROJECT_DIR")"
TIMER_PID_FILE="$STATE_DIR/.watcher-timer.pid"

mkdir -p "$STATE_DIR"

# Cleanup on exit
cleanup() {
    [ -f "$TIMER_PID_FILE" ] && kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null
    rm -f "$TIMER_PID_FILE"
    exit 0
}
trap cleanup SIGTERM SIGINT EXIT

# Kill existing timer and start new one
reset_timer() {
    if [ -f "$TIMER_PID_FILE" ]; then
        kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null || true
        rm -f "$TIMER_PID_FILE"
    fi

    (
        sleep "$DEBOUNCE_SECONDS"
        rm -f "$TIMER_PID_FILE"
        ./bin/backup-daemon.sh
    ) &
    echo $! > "$TIMER_PID_FILE"
}

# Main watch loop
fswatch -o -r \
    -e "node_modules" \
    -e "\.git" \
    -e "backups/" \
    -e "\.cache" \
    -e "__pycache__" \
    -e "\.pyc$" \
    "$PROJECT_DIR" | while read -r _; do
    reset_timer
done
```

### fswatch Exclude Patterns for Common Projects
```bash
# Source: fswatch man page + community patterns
COMMON_EXCLUDES=(
    -e "node_modules"
    -e "\.git"
    -e "\.cache"
    -e "__pycache__"
    -e "\.pyc$"
    -e "\.swp$"
    -e "\.DS_Store"
    -e "backups/"
    -e "\.planning/"
    -e "dist/"
    -e "build/"
    -e "\.next/"
    -e "coverage/"
)

fswatch -o -r "${COMMON_EXCLUDES[@]}" "$PROJECT_DIR"
```

### Integration with Existing Daemon
```bash
# Source: project backup-daemon.sh pattern
# The watcher just triggers backup-daemon.sh which already handles:
# - File locking (prevents duplicate runs)
# - Interval coordination (skips if ran recently)
# - Cloud upload (if configured)
# - Logging

trigger_backup() {
    local daemon="$SCRIPT_DIR/backup-daemon.sh"
    if [ -f "$daemon" ]; then
        # Run in background, daemon handles coordination
        "$daemon" > /dev/null 2>&1 &
    fi
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| inotify everywhere | fswatch for cross-platform | 2015+ | Unified API for macOS/Linux |
| Custom polling loops | FSEvents (macOS native) | Mature | Near-zero CPU overhead |
| Node.js watchers (chokidar) | Native tools for bash projects | Ongoing | Fewer dependencies |

**New tools/patterns to consider:**
- **watchman (Facebook):** Good for large monorepos, but adds complexity for single-project use
- **entr:** Simple alternative for simpler use cases, but less flexible excludes

**Deprecated/outdated:**
- **kqueue directly:** Use fswatch which wraps it properly
- **find + polling:** Inefficient, misses events, don't use
</sota_updates>

<open_questions>
## Open Questions

Things that couldn't be fully resolved:

1. **Optimal debounce interval**
   - What we know: 60s is the target from roadmap
   - What's unclear: Should be configurable per-project? Shorter for rapid iteration?
   - Recommendation: Start with 60s, add DEBOUNCE_SECONDS config option

2. **Watcher start/stop lifecycle**
   - What we know: LaunchAgent is the right pattern for persistence
   - What's unclear: Should watcher auto-start when entering project directory? Or explicit enable?
   - Recommendation: Explicit command (`backup-watch start/stop`) initially, auto-start as Phase 3 enhancement

3. **Multiple project watchers**
   - What we know: Each project needs its own watcher process
   - What's unclear: Central daemon vs per-project LaunchAgents?
   - Recommendation: Per-project LaunchAgents match existing daemon pattern
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- [fswatch GitHub](https://github.com/emcrisostomo/fswatch) - Official repository, README, wiki
- [fswatch Wiki - How to Use](https://github.com/emcrisostomo/fswatch/wiki/How-to-Use-fswatch) - Piping patterns, batch mode
- [fswatch man page](https://www.mankier.com/1/fswatch) - CLI options reference
- Existing project code: `backup-daemon.sh`, `smart-backup-trigger.sh` - Integration patterns

### Secondary (MEDIUM confidence)
- [MerkleBros/debounce.sh](https://github.com/MerkleBros/debounce.sh) - Bash debounce pattern verified against fswatch docs
- [Debouncing shell commands](https://aweirdimagination.net/2025/07/20/debouncing-shell-commands/) - Timer approach verified
- [Bash throttle/debounce gist](https://gist.github.com/niieani/29a054eb29d5306b32ecdfa4678cbb39) - PID tracking pattern verified

### Tertiary (LOW confidence - needs validation)
- None - all patterns verified against official sources or existing project code
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: fswatch with FSEvents backend
- Ecosystem: LaunchAgent, bash debounce patterns
- Patterns: Watcher + debounce + trigger daemon
- Pitfalls: Exclude patterns, timer management, process lifecycle

**Confidence breakdown:**
- Standard stack: HIGH - fswatch is the established tool, verified with official docs
- Architecture: HIGH - Patterns from official wiki + match project conventions
- Pitfalls: HIGH - Common issues documented in GitHub issues + community
- Code examples: HIGH - Built from official patterns + existing project code

**Research date:** 2026-01-11
**Valid until:** 2026-02-11 (30 days - fswatch ecosystem stable)
</metadata>

---

*Phase: 02-activity-triggers*
*Research completed: 2026-01-11*
*Ready for planning: yes*
