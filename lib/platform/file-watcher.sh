#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cross-Platform File Watcher Abstraction
# ==============================================================================
# Provides a unified interface for file watching across platforms:
#   - fswatch (macOS primary, Linux fallback)
#   - inotifywait (Linux primary)
#   - poll fallback (universal, degraded mode)
#
# NOT loaded by backup-lib.sh module loader. Sourced directly by
# backup-watcher.sh after bootstrap.sh + config load.
#
# Bash 3.2 compatible: NO associative arrays, NO mapfile, NO coproc,
# NO |&, NO ${var,,}
# ==============================================================================

# Include guard (set -u safe)
[ -n "${_FILE_WATCHER_LOADED:-}" ] && return || readonly _FILE_WATCHER_LOADED=1

# Global: set by start_watcher for consumers to read
WATCHER_BACKEND=""

# ==============================================================================
# detect_watcher
# ==============================================================================
# Detect the best available file watcher for the current platform.
# Returns: "fswatch", "inotifywait", or "poll" on stdout.
#
# macOS (Darwin): prefer fswatch (FSEvents backend), fallback to poll
# Linux: prefer inotifywait (native inotify), then fswatch, then poll
# ==============================================================================

detect_watcher() {
    local os_name
    os_name="$(uname -s)"

    if [ "$os_name" = "Darwin" ]; then
        # macOS: prefer fswatch (FSEvents backend)
        if command -v fswatch >/dev/null 2>&1; then
            echo "fswatch"
            return
        fi
    else
        # Linux / other: prefer inotifywait (native inotify)
        if command -v inotifywait >/dev/null 2>&1; then
            echo "inotifywait"
            return
        fi
        # Linux fallback: fswatch with inotify backend
        if command -v fswatch >/dev/null 2>&1; then
            echo "fswatch"
            return
        fi
    fi

    # Universal fallback
    echo "poll"
}

# ==============================================================================
# _watcher_fswatch
# ==============================================================================
# fswatch backend. Uses batch mode (-o) for one-line-per-batch output.
#
# Args:
#   $1       - directory to watch
#   $2...$N  - exclude patterns (each becomes -e flag)
#
# Output: one line per batch containing count of changes
# ==============================================================================

_watcher_fswatch() {
    local dir="$1"
    shift

    local args
    args=(-o -r --latency 1)

    local pattern
    for pattern in "$@"; do
        args+=(-e "$pattern")
    done

    fswatch "${args[@]}" "$dir"
}

# ==============================================================================
# _build_inotify_exclude
# ==============================================================================
# Combine multiple exclude patterns into a single inotifywait-compatible regex.
# inotifywait only accepts ONE --exclude flag, so patterns must be combined
# with | alternation.
#
# Args:
#   $1...$N  - exclude patterns
#
# Output: "(pattern1|pattern2|...)" on stdout
#         Empty string if no patterns provided
# ==============================================================================

_build_inotify_exclude() {
    local result=""
    local pattern

    for pattern in "$@"; do
        if [ -n "$result" ]; then
            result="${result}|${pattern}"
        else
            result="$pattern"
        fi
    done

    if [ -n "$result" ]; then
        echo "(${result})"
    fi
}

# ==============================================================================
# _watcher_inotifywait
# ==============================================================================
# inotifywait backend. Uses monitor mode (-m) with close_write,create,delete,move.
# NOT modify -- modify fires on every write() syscall (dozens per save).
#
# Args:
#   $1       - directory to watch
#   $2...$N  - exclude patterns (combined into single --exclude regex)
#
# Output: one line per event containing file path
# ==============================================================================

_watcher_inotifywait() {
    local dir="$1"
    shift

    local args
    args=(-m -r -q --format '%w%f')
    args+=(-e close_write -e create -e delete -e move)

    # Build single exclude regex (inotifywait only accepts one --exclude)
    if [ $# -gt 0 ]; then
        local exclude_regex
        exclude_regex="$(_build_inotify_exclude "$@")"
        if [ -n "$exclude_regex" ]; then
            args+=(--exclude "$exclude_regex")
        fi
    fi

    inotifywait "${args[@]}" "$dir"
}

# ==============================================================================
# _watcher_poll
# ==============================================================================
# Poll fallback using find -newer with marker file. Degraded mode for
# environments without fswatch or inotifywait.
#
# Args:
#   $1       - directory to watch
#   $2...$N  - exclude patterns (only .git and node_modules used in find)
#
# Environment:
#   POLL_INTERVAL - seconds between polls (default: 30)
#
# Output: "CHANGED" on stdout when files modified
# ==============================================================================

_watcher_poll() {
    local dir="$1"
    shift

    local poll_interval="${POLL_INTERVAL:-30}"
    local marker="/tmp/.backup-poll-marker-$$"

    touch "$marker"

    # Clean up marker file when function returns
    trap "rm -f '$marker'" RETURN

    while true; do
        sleep "$poll_interval"

        local changed
        changed="$(find "$dir" -type f -newer "$marker" \
            -not -path '*/.git/*' \
            -not -path '*/node_modules/*' \
            -not -path '*/.DS_Store' \
            -not -path '*/__pycache__/*' \
            -not -path '*/dist/*' \
            -not -path '*/build/*' \
            2>/dev/null | head -1)"

        if [ -n "$changed" ]; then
            touch "$marker"
            echo "CHANGED"
        fi
    done
}

# ==============================================================================
# start_watcher
# ==============================================================================
# Unified entry point. Detects the best backend and starts watching.
# Streams output to stdout for pipe consumption by the debounce loop.
#
# Sets global WATCHER_BACKEND for consumers to read.
#
# Args:
#   $1       - directory to watch
#   $2...$N  - exclude patterns
#
# Output: backend-specific stream (one line per event/batch)
# ==============================================================================

start_watcher() {
    local dir="$1"
    shift

    WATCHER_BACKEND="$(detect_watcher)"

    case "$WATCHER_BACKEND" in
        fswatch)
            _watcher_fswatch "$dir" "$@"
            ;;
        inotifywait)
            _watcher_inotifywait "$dir" "$@"
            ;;
        poll)
            _watcher_poll "$dir" "$@"
            ;;
    esac
}

# ==============================================================================
# check_watcher_available
# ==============================================================================
# Returns the detected backend name on stdout. If poll mode (degraded),
# prints install suggestions to stderr.
#
# Output (stdout): "fswatch", "inotifywait", or "poll"
# Output (stderr): warning + install suggestions if poll mode
# ==============================================================================

check_watcher_available() {
    local backend
    backend="$(detect_watcher)"

    if [ "$backend" = "poll" ]; then
        echo "Warning: No native file watcher found." >&2
        echo "" >&2

        local os_name
        os_name="$(uname -s)"

        case "$os_name" in
            Darwin)
                echo "Install fswatch for efficient file watching:" >&2
                echo "  brew install fswatch" >&2
                ;;
            Linux)
                echo "Install inotify-tools for efficient file watching:" >&2
                echo "  Ubuntu/Debian: sudo apt install inotify-tools" >&2
                echo "  CentOS/RHEL:   sudo yum install inotify-tools" >&2
                echo "  Fedora:        sudo dnf install inotify-tools" >&2
                echo "  Alpine:        apk add inotify-tools" >&2
                ;;
            *)
                echo "Install fswatch for efficient file watching:" >&2
                echo "  See: https://github.com/emcrisostomo/fswatch" >&2
                ;;
        esac

        echo "" >&2
        echo "Falling back to polling (less efficient, ${POLL_INTERVAL:-30}s interval)." >&2
    fi

    echo "$backend"
}
