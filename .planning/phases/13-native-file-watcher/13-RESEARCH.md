# Phase 13: Native File Watcher Daemon - Research

**Researched:** 2026-02-13
**Domain:** Cross-platform file watching (fswatch/inotifywait) with debounced backup triggering
**Confidence:** HIGH

<research_summary>
## Summary

Researched the file watching ecosystem for replacing Claude Code hooks with native, editor-agnostic file monitoring. The project already has a working fswatch implementation (`bin/backup-watcher.sh`) with debounce logic; Phase 13 extends this to Linux and removes the Claude Code dependency.

The standard approach uses **fswatch on macOS** (FSEvents backend, excellent scalability) and **inotifywait on Linux** (kernel inotify, universally available), unified behind a platform-abstraction wrapper. Both tools support recursive watching, exclude patterns, and integrate well with bash. The existing debounce pattern (kill-and-restart sleep) is the canonical approach used by tools like debounce.sh, nodemon, and watchexec.

Key finding: The existing implementation in `backup-watcher.sh` is already 90% correct for file watching. However, **`smart-backup-trigger.sh` contains session detection and interval logic that the watcher must absorb** before it can be removed. The trigger tracks idle time (600s threshold) and enforces backup intervals (3600s) -- the watcher is purely event-driven and has neither.

The main work is: (1) abstract the fswatch call behind a platform wrapper, (2) add inotifywait backend for Linux, (3) add poll fallback, (4) absorb session/interval/drive logic from smart-backup-trigger.sh into watcher, (5) remove hooks and trigger script, (6) update install/uninstall scripts to remove hook setup.

**Primary recommendation:** Create `lib/platform/file-watcher.sh` as a unified wrapper with fswatch/inotifywait/poll backends. Enhance `backup-watcher.sh` with session detection and interval pre-checking from smart-backup-trigger.sh. Then remove `.claude/hooks/backup-on-*.sh`, `bin/smart-backup-trigger.sh`, and `templates/claude-settings.json`. Update `bin/install.sh` and `bin/uninstall.sh` to remove all hook setup/teardown code.
</research_summary>

<standard_stack>
## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| fswatch | 1.18.3 | File watching (macOS) | Cross-platform, FSEvents backend on macOS (no fd limits, scales to 500GB+), built-in latency/batching |
| inotify-tools | 4.25.9.0 | File watching (Linux) | In every Linux package manager, zero-overhead kernel inotify, universally available including Alpine Docker |
| bash 3.2+ | 3.2+ | Script runtime | macOS ships bash 3.2; all patterns must be compatible |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| launchd | (system) | macOS daemon management | Already used via plist templates for hourly daemon |
| nohup | (system) | Background process | Already used in backup-watch.sh for starting watcher |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| fswatch + inotifywait | fswatch everywhere | fswatch can use inotify backend on Linux, but inotifywait is lighter (~50KB vs ~2MB), more universally available, and native |
| fswatch + inotifywait | watchman (Facebook) | Watchman has excellent debounce (20ms settle) but is overkill -- client-server architecture, heavy binary, not in standard Linux repos |
| fswatch + inotifywait | entr | entr cannot watch for new files, no daemon mode, designed for dev feedback loops not backup daemons |
| Custom debounce | watchexec | Rust binary, would add non-bash dependency; existing kill+sleep pattern works fine |

### Installation
```bash
# macOS
brew install fswatch

# Ubuntu/Debian
sudo apt install inotify-tools

# CentOS/RHEL
sudo yum install inotify-tools

# Alpine (Docker)
apk add inotify-tools

# Fedora
sudo dnf install inotify-tools
```
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Architecture: Platform Wrapper

```
bin/backup-watcher.sh          # Orchestrator (existing, modify)
    │
    ├── lib/platform/file-watcher.sh   # NEW: Platform abstraction
    │       │
    │       ├── fswatch backend    (macOS primary, Linux fallback)
    │       ├── inotifywait backend (Linux primary)
    │       └── poll backend       (universal fallback)
    │
    ├── Debounce logic             (existing reset_timer, keep as-is)
    │
    └── bin/backup-daemon.sh       # Actual backup execution (existing)
```

### Pattern 1: Unified Watcher Interface
**What:** A wrapper function that normalizes output across backends -- each emits "something changed" signals that the existing debounce timer consumes.
**When to use:** Always -- this is the core abstraction.
**Example:**
```bash
# lib/platform/file-watcher.sh

detect_watcher() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS: prefer fswatch (FSEvents backend)
        if command -v fswatch &>/dev/null; then
            echo "fswatch"
            return
        fi
    else
        # Linux: prefer inotifywait (native inotify)
        if command -v inotifywait &>/dev/null; then
            echo "inotifywait"
            return
        fi
        # Linux fallback: fswatch with inotify backend
        if command -v fswatch &>/dev/null; then
            echo "fswatch"
            return
        fi
    fi
    echo "poll"
}

start_watcher() {
    local dir="$1"
    shift
    local excludes=("$@")
    local backend
    backend=$(detect_watcher)

    case "$backend" in
        fswatch)    _watcher_fswatch "$dir" "${excludes[@]}" ;;
        inotifywait) _watcher_inotifywait "$dir" "${excludes[@]}" ;;
        poll)       _watcher_poll "$dir" "${excludes[@]}" ;;
    esac
}
```

### Pattern 2: fswatch Batch Mode (Existing, Keep)
**What:** Use `-o` (one-per-batch) to get a single "N files changed" signal per batch. Combined with `--latency` for OS-level coalescing.
**When to use:** macOS primary path.
**Example:**
```bash
_watcher_fswatch() {
    local dir="$1"
    shift
    local excludes=("$@")

    local args=(-o -r --latency 1)
    for pattern in "${excludes[@]}"; do
        args+=(-e "$pattern")
    done

    fswatch "${args[@]}" "$dir"
    # Output: one line per batch containing count of changes
}
```

### Pattern 3: inotifywait Continuous Mode
**What:** Use `-m` (monitor mode) with `close_write,create,delete,move` events. Output one line per event; debounce handles coalescing.
**When to use:** Linux primary path.
**Example:**
```bash
_watcher_inotifywait() {
    local dir="$1"
    shift
    local excludes=("$@")

    # Build single exclude regex (inotifywait only accepts one --exclude)
    local exclude_regex=""
    for pattern in "${excludes[@]}"; do
        if [ -n "$exclude_regex" ]; then
            exclude_regex="${exclude_regex}|${pattern}"
        else
            exclude_regex="$pattern"
        fi
    done

    local args=(-m -r -q --format '%w%f')
    args+=(-e close_write -e create -e delete -e move)
    if [ -n "$exclude_regex" ]; then
        args+=(--exclude "($exclude_regex)")
    fi

    inotifywait "${args[@]}" "$dir"
    # Output: one line per event containing file path
}
```

### Pattern 4: Poll Fallback
**What:** `find -newer` loop as degraded mode when no native watcher is available.
**When to use:** Environments without fswatch or inotifywait (minimal containers, exotic platforms).
**Example:**
```bash
_watcher_poll() {
    local dir="$1"
    shift
    local excludes=("$@")
    local poll_interval="${POLL_INTERVAL:-30}"
    local marker="/tmp/.backup-poll-marker-$$"

    touch "$marker"

    while true; do
        sleep "$poll_interval"
        local changed
        changed=$(find "$dir" -type f -newer "$marker" \
            -not -path '*/.git/*' \
            -not -path '*/node_modules/*' \
            2>/dev/null | head -1)
        if [ -n "$changed" ]; then
            touch "$marker"
            echo "CHANGED"  # trigger debounce
        fi
    done
}
```

### Pattern 5: Trailing-Edge Debounce (Existing, Keep)
**What:** Kill previous sleep, start new sleep. Backup fires only after quiet period expires.
**When to use:** Always -- this is the existing `reset_timer()` in backup-watcher.sh.
**Key insight:** This is the canonical pattern used by debounce.sh, nodemon, and watchexec. The existing implementation is correct.

### Pattern 6: Session-Aware Watcher (NEW -- from smart-backup-trigger.sh migration)
**What:** The watcher must absorb session detection from smart-backup-trigger.sh. On startup, check if a new session started (idle > 10min) and trigger immediate backup. During watching, update session timestamp on each file change.
**When to use:** Always -- ensures backup on first activity after idle period, not just on file changes.
**Critical insight:** smart-backup-trigger.sh tracked three things the watcher currently doesn't:
1. **Session idle detection** (SESSION_IDLE_THRESHOLD=600s) via `.current-session-time`
2. **Backup interval pre-check** (BACKUP_INTERVAL=3600s) via `.last-backup-time`
3. **Drive verification** (DRIVE_VERIFICATION_ENABLED) via marker file
**Example:**
```bash
# Add to backup-watcher.sh startup
check_new_session() {
    local last_session
    last_session=$(cat "$SESSION_FILE" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    if [ $((now - last_session)) -gt "${SESSION_IDLE_THRESHOLD:-600}" ]; then
        echo "$now" > "$SESSION_FILE"
        return 0  # New session
    fi
    return 1
}

should_backup_now() {
    # Check interval
    local last_backup
    last_backup=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    if [ $((now - last_backup)) -lt "${BACKUP_INTERVAL:-3600}" ]; then
        return 1  # Too soon
    fi
    # Check drive
    if [ "${DRIVE_VERIFICATION_ENABLED:-false}" = true ] && [ ! -f "${DRIVE_MARKER_FILE:-}" ]; then
        return 1  # Drive not connected
    fi
    return 0
}

# On startup: immediate backup if new session
if check_new_session && should_backup_now; then
    log "New session detected, triggering startup backup..."
    "$SCRIPT_DIR/backup-daemon.sh" >> "$WATCHER_LOG" 2>&1 &
fi

# In debounce timer: update session timestamp on each file change
on_file_change() {
    echo "$(date +%s)" > "$SESSION_FILE"
    reset_timer
}
```

### Anti-Patterns to Avoid
- **Watching .git/ directory:** Generates 10-30 events per commit, 50-200+ per pull. Always exclude entirely.
- **Using `modify` event with inotifywait:** Fires on every `write()` syscall (dozens per save). Use `close_write` instead -- fires once when file is fully written.
- **Building custom file change detection:** The existing `has_changes` / `get_changed_files_fast` in backup-lib.sh handles this for the backup phase. The watcher only needs "something changed" signal.
- **Watching build output directories:** Creates infinite feedback loops if watcher triggers builds. Always exclude dist/, build/, .next/, etc.
- **Using associative arrays:** Bash 3.2 (macOS default) doesn't support `declare -A`. Use regular arrays or files.
- **Removing smart-backup-trigger.sh without migrating its logic:** The trigger has session detection and interval enforcement that the watcher lacks. Must migrate BEFORE removing.
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File system event notification | Custom kqueue/inotify bindings | fswatch / inotifywait | These are battle-tested wrappers around OS APIs with proper error handling, overflow protection, and recursive support |
| OS-level event coalescing | Custom batch window | fswatch `--latency` flag | Built-in, configurable, handles edge cases around batch boundaries |
| Trailing-edge debounce | Complex timer management | Kill-and-restart sleep pattern | The `kill $old_pid; (sleep N && action) &` pattern is the canonical approach. The existing `reset_timer()` already implements this correctly |
| Cross-platform detection | Manual `/proc` or `sw_vers` checks | `uname -s` + `command -v` | Simple, POSIX-standard, already used elsewhere in codebase |
| Exclude pattern normalization | Custom regex translator | Platform-native exclude syntax | fswatch uses `-e` (repeatable), inotifywait uses single `--exclude` with `\|` alternation. Keep them separate. |
| Process management | Custom PID tracking | Existing PID file pattern | backup-watch.sh already has robust PID tracking with stale detection |

**Key insight:** The existing codebase already solves most of the hard problems. The debounce logic in `reset_timer()` is correct. The exclude pattern list in `DEFAULT_EXCLUDES` is comprehensive. The PID management in `backup-watch.sh` handles edge cases. Phase 13 is primarily about adding a platform abstraction layer and the inotifywait backend -- not rewriting what works.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: inotifywait Single --exclude Limitation
**What goes wrong:** Passing multiple `--exclude` flags to inotifywait -- only the last one takes effect.
**Why it happens:** inotifywait only accepts one `--exclude` argument (unlike fswatch which accepts many `-e` flags).
**How to avoid:** Combine all patterns into a single regex with `|` alternation: `--exclude '(\.git/|node_modules/|dist/)'`
**Warning signs:** Seeing events from directories you thought were excluded.

### Pitfall 2: inotifywait `modify` Event Storm
**What goes wrong:** Hundreds of events for a single file save, triggering debounce resets continuously.
**Why it happens:** `modify` fires on every `write()` syscall. An editor saving a 1MB file may issue 100+ writes.
**How to avoid:** Use `close_write` event instead -- fires once when the file is fully written and closed.
**Warning signs:** Debounce timer never expires because events keep coming.

### Pitfall 3: .git Directory Event Noise
**What goes wrong:** Every `git commit`, `git pull`, `git checkout` generates 10-200+ filesystem events inside `.git/`.
**Why it happens:** Git modifies index, objects, refs, logs, HEAD, FETCH_HEAD, COMMIT_EDITMSG, etc.
**How to avoid:** Always exclude `\.git/` from watching. For a backup system, .git is fully regenerable from the remote.
**Warning signs:** Backup triggers after every git operation even when no source files changed.

### Pitfall 4: inotify Watch Limit on Linux
**What goes wrong:** `inotifywait: Failed to watch /path: The upper limit on inotify watches reached!`
**Why it happens:** Default `max_user_watches` is 8,192 on older kernels. A single `node_modules/` can have 10,000+ subdirectories, each needing a watch.
**How to avoid:** (1) Exclude `node_modules/` and other heavy dirs BEFORE starting watches. (2) Document how to increase limit: `echo 524288 | sudo tee /proc/sys/fs/inotify/max_user_watches`. (3) On kernel 5.11+, default is dynamically scaled up to 1,048,576.
**Warning signs:** Watcher crashes on startup for large projects.

### Pitfall 5: Recursive Watch Startup Race (inotifywait)
**What goes wrong:** Files changed during inotifywait startup (while watches are being established) are missed.
**Why it happens:** Recursive mode establishes one watch per subdirectory sequentially. On large trees (700K dirs), startup takes ~35 seconds. Events during this window are lost.
**How to avoid:** (1) Run an initial backup immediately when watcher starts (before or during watch establishment). (2) For the backup use case, this is acceptable -- the hourly daemon catches anything missed. (3) Exclude heavy directories to speed up startup.
**Warning signs:** Sporadic missed file changes on large projects, especially right after watcher restart.

### Pitfall 6: fswatch Exclude Doesn't Prevent Kernel Scanning
**What goes wrong:** Performance expectations not met -- fswatch still processes events from excluded directories internally.
**Why it happens:** On macOS, FSEvents delivers ALL events to userspace. fswatch's `--exclude` filters the output, not the kernel delivery (Issue #151). The events are still received; they're just not printed.
**How to avoid:** This is fine for a backup system -- the filtering prevents unnecessary backup triggers. The CPU overhead of receiving-and-discarding events is negligible. Don't expect excludes to reduce kernel-level I/O.
**Warning signs:** None for typical projects. Only relevant for extremely high-event-rate scenarios (rare).

### Pitfall 7: Bash 3.2 Incompatibility
**What goes wrong:** Script fails on macOS with syntax errors.
**Why it happens:** macOS ships bash 3.2. Features added in bash 4+ (associative arrays, `mapfile`, `coproc`, `|&`, `${var,,}`) don't work.
**How to avoid:** Test all code with bash 3.2. Avoid: `declare -A`, `mapfile`, `readarray`, `${var,,}`, `${var^^}`, `[[ x =~ regex ]]` with stored regex variables, `|&` pipe shorthand.
**Warning signs:** Works on Linux (bash 5+) but fails on macOS.
</common_pitfalls>

<code_examples>
## Code Examples

### Existing Debounce (Keep As-Is)
```bash
# Source: bin/backup-watcher.sh:133-163 (existing, verified working)
reset_timer() {
    # Kill existing timer if running
    if [ -f "$TIMER_PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$TIMER_PID_FILE" 2>/dev/null) || true
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            kill "$old_pid" 2>/dev/null || true
            wait "$old_pid" 2>/dev/null || true
        fi
        rm -f "$TIMER_PID_FILE"
    fi

    # Start new timer in background
    (
        sleep "$DEBOUNCE_SECONDS"
        rm -f "$TIMER_PID_FILE"
        date +%s > "$LAST_TRIGGER_FILE"
        log "Debounce timer expired, triggering backup..."
        "$SCRIPT_DIR/backup-daemon.sh" >> "$WATCHER_LOG" 2>&1 &
    ) &

    local new_pid=$!
    echo "$new_pid" > "$TIMER_PID_FILE"
}
```

### Platform Wrapper (New)
```bash
# Source: Pattern derived from cross-platform research
# File: lib/platform/file-watcher.sh

#!/usr/bin/env bash
# Cross-platform file watcher abstraction
# Outputs one line per change batch for debounce consumption

detect_watcher() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if command -v fswatch &>/dev/null; then echo "fswatch"; return; fi
    else
        if command -v inotifywait &>/dev/null; then echo "inotifywait"; return; fi
        if command -v fswatch &>/dev/null; then echo "fswatch"; return; fi
    fi
    echo "poll"
}

_build_inotify_exclude() {
    local result=""
    for pattern in "$@"; do
        if [ -n "$result" ]; then
            result="${result}|${pattern}"
        else
            result="$pattern"
        fi
    done
    echo "($result)"
}

start_watcher() {
    local dir="$1"
    shift
    local excludes=("$@")
    local backend
    backend=$(detect_watcher)

    case "$backend" in
        fswatch)
            local args=(-o -r --latency 1)
            for pattern in "${excludes[@]}"; do
                args+=(-e "$pattern")
            done
            fswatch "${args[@]}" "$dir"
            ;;
        inotifywait)
            local exclude_regex
            exclude_regex=$(_build_inotify_exclude "${excludes[@]}")
            inotifywait -m -r -q --format '%w%f' \
                -e close_write -e create -e delete -e move \
                --exclude "$exclude_regex" \
                "$dir"
            ;;
        poll)
            local poll_interval="${POLL_INTERVAL:-30}"
            local marker="/tmp/.backup-poll-marker-$$"
            touch "$marker"
            trap "rm -f '$marker'" RETURN
            while true; do
                sleep "$poll_interval"
                if find "$dir" -type f -newer "$marker" \
                    -not -path '*/.git/*' -not -path '*/node_modules/*' \
                    2>/dev/null | head -1 | grep -q .; then
                    touch "$marker"
                    echo "CHANGED"
                fi
            done
            ;;
    esac
}
```

### Modified backup-watcher.sh Main Loop (New)
```bash
# Source: Modification to bin/backup-watcher.sh:176-196
# Replace direct fswatch call with platform wrapper

# Load platform watcher
source "$LIB_DIR/platform/file-watcher.sh"

WATCHER_BACKEND=$(detect_watcher)
log "Using watcher backend: $WATCHER_BACKEND"

if [ "$WATCHER_BACKEND" = "poll" ]; then
    log "WARNING: No native file watcher found. Using poll fallback (${POLL_INTERVAL:-30}s interval)"
    log "Install fswatch (macOS: brew install fswatch) or inotify-tools (Linux: apt install inotify-tools)"
fi

# Start watcher and process events
start_watcher "$PROJECT_DIR" "${DEFAULT_EXCLUDES[@]}" | while read -r _event; do
    log "File change detected (via $WATCHER_BACKEND)"
    reset_timer
done &

WATCHER_PID=$!
log "Watcher started (PID: $WATCHER_PID, backend: $WATCHER_BACKEND)"
wait "$WATCHER_PID"
```

### inotifywait close_write Usage
```bash
# Source: inotifywait(1) man page, verified pattern
# GOOD: fires once when file save completes
inotifywait -m -r -e close_write,create,delete,move \
    --exclude '(\.git/|node_modules/|dist/|build/)' \
    --format '%w%f' \
    /path/to/project/

# BAD: fires many times per save (every write() syscall)
inotifywait -m -r -e modify /path/to/project/
```

### Installation Check with Helpful Error
```bash
# Source: New pattern for cross-platform error messages
check_watcher_available() {
    local backend
    backend=$(detect_watcher)

    if [ "$backend" = "poll" ]; then
        echo "Warning: No native file watcher found." >&2
        echo "" >&2
        case "$(uname -s)" in
            Darwin)
                echo "Install fswatch: brew install fswatch" >&2
                ;;
            Linux)
                echo "Install inotify-tools:" >&2
                echo "  Ubuntu/Debian: sudo apt install inotify-tools" >&2
                echo "  CentOS/RHEL:   sudo yum install inotify-tools" >&2
                echo "  Alpine:        apk add inotify-tools" >&2
                ;;
        esac
        echo "" >&2
        echo "Falling back to polling (less efficient)." >&2
    fi

    echo "$backend"
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Claude Code hooks only | Native file watching | Phase 13 | Editor-agnostic, works without Claude Code |
| fswatch macOS only | fswatch + inotifywait cross-platform | Phase 13 | Linux support |
| inotify-tools 3.x | inotify-tools 4.25.9 | 2024 | fanotify backend support, recursive --include fix, better crash handling |
| inotify max_user_watches=8192 | Kernel 5.11+ auto-scales to 1M | 2021 | Less frequent watch limit issues on modern kernels |
| Manual event batching | fswatch --latency built-in | Already used | No change needed |

**New tools/patterns to consider:**
- **fanotify (Linux):** Newer kernel API (inotify-tools 4.x supports it via `-F` flag). Enables filesystem-wide watching with `-S`. Not needed for per-project watching but worth knowing about.
- **watchexec:** Rust-based watcher with excellent debounce (50ms default). Not suitable as a dependency for a bash project but its debounce research (500ms -> 50ms journey) informed our timing recommendations.

**Deprecated/outdated:**
- **Claude Code hooks for backup triggering:** Being replaced by this phase. Hooks tie the system to a specific editor.
- **entr for daemon-style watching:** Cannot detect new files, no continuous monitoring mode. Only suitable for dev feedback loops on known files.
- **cannon.js / kqueue for file watching:** kqueue requires 1 fd per file, scales badly. Always use FSEvents on macOS (fswatch default).
</sota_updates>

<hook_removal_scope>
## Hook Removal Scope (Deep Dive)

Complete inventory of files affected by removing Claude Code hooks:

### Files to Delete
| File | Lines | Purpose |
|------|-------|---------|
| `.claude/hooks/backup-on-stop.sh` | 20 | Triggers on conversation end |
| `.claude/hooks/backup-on-edit.sh` | 19 | Triggers on file edit/write |
| `.claude/hooks/backup-on-commit.sh` | 16 | Triggers on git commit |
| `bin/smart-backup-trigger.sh` | 98 | Session detection + interval enforcement (logic moves to watcher) |
| `templates/claude-settings.json` | 38 | Hook configuration template for `.claude/settings.local.json` |

### Files to Modify
| File | What Changes |
|------|-------------|
| `bin/install.sh` | Remove: hook installation question (L754-760), `.claude/hooks` dir creation (L1098-1101), hook script copying (L1119-1124), HOOKS_ENABLED logic (L1227-1264), settings.json hook config (L1272-1338), old global hooks migration (L1276-1299) |
| `bin/uninstall.sh` | Remove: hook script deletion (L166-178), jq-based hook removal from settings (L180-194), `.claude/hooks` dir cleanup |
| `bin/install-global.sh` | Remove: entire "SESSION-START HOOKS" section (L392-499), hook installation within session-start (L453-496) |
| `bin/backup-watcher.sh` | Add: session detection, interval pre-check, drive verification (from smart-backup-trigger.sh) |
| `bin/backup-watch.sh` | Update: error messages for cross-platform, help text |
| `templates/backup-config.sh` | Update: document watcher as primary trigger mechanism, remove HOOKS_ENABLED references |

### Documentation to Update
| File | Section |
|------|---------|
| `.planning/codebase/ARCHITECTURE.md` | L118-120: hook entry points |
| `.planning/codebase/INTEGRATIONS.md` | L80-86: Claude Code integration |
| `README.md` | Claude Code hook section |
| `CHANGELOG.md` | Mark hooks removed |

### State Files Affected
| File | Current Owner | After Migration |
|------|--------------|-----------------|
| `.current-session-time` | smart-backup-trigger.sh | backup-watcher.sh |
| `.last-backup-time` | smart-backup-trigger.sh + backup-daemon.sh | backup-watcher.sh (pre-check) + backup-daemon.sh (write) |

### Hook Event Flow (Being Replaced)
```
BEFORE (hooks):
  Claude Code event → hook script → smart-backup-trigger.sh → backup-daemon.sh

AFTER (watcher):
  Any editor saves → fswatch/inotifywait → backup-watcher.sh (debounce) → backup-daemon.sh
  Watcher startup  → session check → immediate backup if idle > 10min
```
</hook_removal_scope>

<exclude_improvements>
## Exclude Pattern Improvements (Deep Dive)

### Current Patterns (backup-watcher.sh:59-74)
All 14 current patterns are **valid POSIX regex for fswatch**. Substring matching is acceptable (conservative -- excludes more, not less).

### Missing Patterns to Add
| Pattern | Category | Why |
|---------|----------|-----|
| `\.venv` | Python virtualenv | Thousands of files, not user content |
| `venv/` | Python virtualenv | Alternative naming convention |
| `vendor/` | PHP/Go deps | Similar to node_modules |
| `\.idea` | JetBrains IDE | Noisy metadata |
| `\.hg` | Mercurial VCS | Less common but valid |
| `\.svn` | Subversion VCS | Legacy but valid |
| `\.swo$` | Vim undo files | Complements existing `.swp$` |
| `4913` | Vim test write | Vim writes this to test directory writability |
| `\.\#` | Emacs lock files | Emacs creates `.#filename` lock symlinks |
| `bower_components` | Legacy deps | Still used in some projects |
| `\.terraform` | Terraform cache | Heavy cached state |
| `\.parcel-cache` | Parcel bundler | Build cache |

### Updated DEFAULT_EXCLUDES Array
```bash
DEFAULT_EXCLUDES=(
    # Version control (MUST exclude -- extreme noise)
    "\.git"
    "\.hg"
    "\.svn"
    # Dependencies (MUST exclude -- massive file counts)
    "node_modules"
    "vendor/"
    "\.venv"
    "venv/"
    "__pycache__"
    "bower_components"
    # Build output (MUST exclude -- generated content)
    "dist/"
    "build/"
    "\.next/"
    "\.nuxt/"
    "\.parcel-cache"
    "coverage/"
    # IDE / Editor
    "\.idea"
    "\.swp$"
    "\.swo$"
    "4913"
    "\.\#"
    # OS metadata
    "\.DS_Store"
    # Project-specific
    "backups/"
    "\.cache"
    "\.planning/"
    "\.claudecode-backups"
    "\.terraform"
    # Compiled
    "\.pyc$"
)
```

### Configuration Template Gap
`templates/backup-config.sh` (L234-238) documents WATCHER_EXCLUDES but the comment listing default patterns is **incomplete** -- only lists 10 of 14 current patterns. Update to list all defaults.

### inotifywait Translation
All patterns combined into single `--exclude` with `|` alternation:
```bash
--exclude '(\.git|\.hg|\.svn|node_modules|vendor/|\.venv|venv/|__pycache__|bower_components|dist/|build/|\.next/|\.nuxt/|\.parcel-cache|coverage/|\.idea|\.swp$|\.swo$|4913|\.\#|\.DS_Store|backups/|\.cache|\.planning/|\.claudecode-backups|\.terraform|\.pyc$)'
```
</exclude_improvements>

<trigger_migration>
## smart-backup-trigger.sh Migration Analysis (Deep Dive)

### What the Trigger Does That the Watcher Doesn't

| Feature | smart-backup-trigger.sh | backup-watcher.sh | backup-daemon.sh |
|---------|------------------------|-------------------|------------------|
| **Session idle detection** | Reads `.current-session-time`, compares to 600s threshold | None | None |
| **Backup interval pre-check** | Reads `.last-backup-time`, compares to 3600s | None | Reads + enforces at runtime |
| **Drive verification** | Checks marker file, exits silently if missing | None | Checks, logs warning, exits |
| **Session timestamp update** | Writes current time on every prompt | None | None |

### Migration Strategy (CRITICAL)

The watcher must become **partially time-aware** in addition to event-driven:

**On startup:**
1. Check if idle > SESSION_IDLE_THRESHOLD (new session)
2. If new session AND interval allows, trigger immediate backup
3. This replaces the "first prompt after idle" trigger from hooks

**On each file change:**
1. Update `.current-session-time` (tracks user activity for session detection)
2. Reset debounce timer (existing behavior)

**Before debounce fires:**
1. Check backup interval (don't call daemon if too soon -- saves a process spawn)
2. Check drive verification (don't call daemon if drive disconnected)
3. The daemon's own interval check stays as defensive redundancy

### State File Ownership Transfer
```
BEFORE:
  .current-session-time  ← written by smart-backup-trigger.sh (every prompt)
  .last-backup-time      ← written by smart-backup-trigger.sh + backup-daemon.sh

AFTER:
  .current-session-time  ← written by backup-watcher.sh (every file change)
  .last-backup-time      ← written by backup-daemon.sh only (no pre-write needed)
```

### Key Difference: Prompt-Based vs File-Based Session Tracking
- **Before:** Session tracked by Claude Code prompts (every user message updates timestamp)
- **After:** Session tracked by file changes (any editor save updates timestamp)
- **Impact:** Minor -- file changes are a superset of Claude Code prompts for active development. The watcher captures all editor activity, not just Claude Code activity. This is actually better for editor-agnostic detection.

### The Daemon's Interval Check Stays (Defense in Depth)
`backup-daemon.sh:595-606` checks `BACKUP_INTERVAL` before executing. This MUST remain even after adding the pre-check to the watcher. Reasons:
1. Multiple triggers can fire simultaneously (watcher + hourly launchd)
2. Race conditions between debounce timer expiry and daemon startup
3. The daemon is the last line of defense against duplicate backups
</trigger_migration>

<daemon_architecture>
## Daemon Architecture (Deep Dive)

### Three-Tier Runtime Architecture
```
┌─ Hourly Daemon (LaunchAgent, StartInterval=3600) ────────┐
│  com.claudecode.backup.${PROJECT_NAME}                    │
│  Script: backup-daemon.sh                                 │
│  Writes: .checkpoint/daemon.heartbeat                     │
└───────────────────────────────────────────────────────────┘

┌─ File Watcher (LaunchAgent, KeepAlive=true) ──────────────┐
│  com.claudecode.backup-watcher.${PROJECT_NAME}            │
│  Script: backup-watcher.sh                                │
│  Calls: backup-daemon.sh on debounce                      │
│  Does NOT write heartbeat (gap for Phase 18)              │
└───────────────────────────────────────────────────────────┘

┌─ Watchdog (LaunchAgent, KeepAlive=true, GLOBAL) ──────────┐
│  com.checkpoint.watchdog                                  │
│  Script: checkpoint-watchdog.sh                           │
│  Monitors: daemon heartbeat ONLY (not watcher)            │
│  Action: Auto-restarts daemon after 3 consecutive stales  │
└───────────────────────────────────────────────────────────┘
```

### Phase 13 Impact on Daemon Architecture
- **launchd-watcher.plist:** No changes needed. Platform abstraction is inside bash, not in plist.
- **Watchdog:** No changes for Phase 13. Watchdog monitors daemon, not watcher. Phase 18 will add watcher monitoring.
- **Hourly daemon:** No changes. Continues as independent scheduled backup.
- **backup-watcher.sh:** Modified to use platform wrapper + absorb trigger logic.

### Installation Points (in install.sh)
1. Hourly daemon plist: inline generated (L1168-1203)
2. Watcher plist: template + sed substitution (L1205-1220)
3. Watchdog plist: separate `install-helper.sh` (L93-118)
</daemon_architecture>

<open_questions>
## Open Questions

1. **Should the watcher replace or coexist with Claude Code hooks?**
   - What we know: Phase 13 roadmap says "remove .claude/hooks/backup-on-*.sh"
   - What's unclear: Should hooks be kept as an optional fallback for Claude Code-specific events (conversation end)?
   - Recommendation: **Remove hooks entirely.** The watcher catches all file changes regardless of source. Session detection on startup replaces the "first prompt" trigger. The hourly daemon handles periodic cadence. Hooks add no value once native watching is active.

2. **Optimal default debounce for the watcher?**
   - What we know: Current default is 60s. Research shows 3s is typical for dev tools, but backup systems are less latency-sensitive.
   - What's unclear: Is 60s too long? Users might expect faster response.
   - Recommendation: **Keep 60s as default.** This is a backup system, not a build tool. 60s coalesces editor saves, git operations, and even npm installs into a single backup. Make it configurable via `DEBOUNCE_SECONDS` (already is).

3. **Should the watcher auto-start on install?**
   - What we know: Currently requires `backup-watch start`. The launchd plist template exists but isn't auto-configured.
   - What's unclear: Should Phase 13 also set up auto-start, or defer to Phase 18 (Daemon Lifecycle)?
   - Recommendation: **Defer auto-start to Phase 18.** Phase 13 focuses on cross-platform watching + hook removal. Phase 18 handles lifecycle (auto-start, heartbeat, health monitoring).

4. **Poll fallback interval?**
   - What we know: 30s is reasonable for degraded mode. Too frequent wastes CPU; too infrequent misses changes.
   - What's unclear: Should we even support poll mode, or just fail if no native watcher?
   - Recommendation: **Support poll as degraded fallback with warning.** Some environments (Docker, CI) may not have fswatch/inotifywait. Default 30s interval, configurable via `POLL_INTERVAL`.

5. **Session tracking: prompt-based vs file-based?** (RESOLVED)
   - What we know: Currently sessions tracked by Claude Code prompts. After migration, tracked by file changes.
   - Resolution: File changes are a superset of editor activity. This is actually better -- captures VS Code, Vim, any editor, not just Claude Code. Minor behavioral change: idle detection based on file activity, not just Claude Code prompts.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- [fswatch GitHub](https://github.com/emcrisostomo/fswatch) - v1.18.3, all flags, monitors, exclude syntax, latency/debounce
- [fswatch official documentation](https://emcrisostomo.github.io/fswatch/) - tutorials, invocation reference, monitor selection
- [inotifywait(1) man page](https://man7.org/linux/man-pages/man1/inotifywait.1.html) - event types, flags, exclude patterns
- [inotify(7) man page](https://man7.org/linux/man-pages/man7/inotify.7.html) - kernel API, limitations, queue overflow
- [inotify-tools GitHub](https://github.com/inotify-tools/inotify-tools/wiki) - v4.25.9.0, fanotify support, installation
- Existing codebase: `bin/backup-watcher.sh`, `bin/backup-watch.sh`, `.claude/hooks/backup-on-*.sh`

### Secondary (MEDIUM confidence)
- [debounce.sh (MerkleBros)](https://github.com/MerkleBros/debounce.sh) - canonical bash debounce pattern, verified against existing code
- [watchexec debounce discussion](https://github.com/watchexec/watchexec/issues/168) - debounce timing research (500ms -> 50ms journey)
- [Watchman configuration](https://facebook.github.io/watchman/docs/config) - settle period, ignore patterns
- [VS Code file watcher internals](https://github.com/microsoft/vscode/wiki/File-Watcher-Internals) - .git exclusion strategy
- [Linux kernel commit: auto-scale max_user_watches](https://github.com/torvalds/linux/commit/92890123749bafc317bbfacbe0a62ce08d78efb7)
- [fswatch Issue #151](https://github.com/emcrisostomo/fswatch/issues/151) - exclude filtering is output-level, not kernel-level

### Tertiary (LOW confidence - needs validation)
- None -- all findings cross-verified against official docs or existing codebase
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: fswatch (macOS FSEvents), inotifywait (Linux inotify)
- Ecosystem: entr, watchman, watchexec, chokidar (evaluated and rejected)
- Patterns: Trailing-edge debounce, platform wrapper, exclude patterns, poll fallback
- Pitfalls: .git noise, inotify limits, close_write vs modify, bash 3.2, startup race

**Confidence breakdown:**
- Standard stack: HIGH - fswatch/inotifywait are the established tools, verified with official docs and existing codebase
- Architecture: HIGH - wrapper pattern is straightforward; existing code already implements 90% of the logic
- Pitfalls: HIGH - documented in official docs, GitHub issues, and community experience
- Code examples: HIGH - derived from official docs and existing working code in the project

**Existing code analysis:**
- `bin/backup-watcher.sh` - Working fswatch + debounce; needs platform abstraction + session/interval logic from trigger
- `bin/backup-watch.sh` - Management CLI (start/stop/status); needs cross-platform error messages
- `bin/smart-backup-trigger.sh` - Session detection + interval enforcement; logic moves to watcher, then script deleted
- `.claude/hooks/backup-on-{edit,commit,stop}.sh` - To be deleted (replaced by native watching)
- `templates/claude-settings.json` - Hook config template; to be deleted
- `bin/install.sh` - Hook setup code in ~6 sections; all hook-related code removed
- `bin/uninstall.sh` - Hook teardown code; hook-related cleanup removed
- `bin/install-global.sh` - Session-start hooks section (L392-499); removed
- `templates/launchd-watcher.plist` - No changes needed (platform abstraction is in bash)
- `bin/checkpoint-watchdog.sh` - No changes for Phase 13 (monitors daemon, not watcher)
- `templates/backup-config.sh` - WATCHER_EXCLUDES docs incomplete; update default pattern list

**Research date:** 2026-02-13
**Updated:** 2026-02-13 (deep dive: hook removal scope, trigger migration, exclude improvements, daemon architecture)
**Valid until:** 2026-03-15 (30 days - fswatch/inotify-tools ecosystems are stable)
</metadata>

---

*Phase: 13-native-file-watcher*
*Research completed: 2026-02-13*
*Ready for planning: yes*
