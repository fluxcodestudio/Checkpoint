#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - File Watcher with Debounced Backup Triggering
# ==============================================================================
# Watches project files for changes and triggers backup after inactivity period.
# Uses platform-specific file watcher: fswatch (macOS), inotifywait (Linux),
# or poll fallback. Backend selected automatically via lib/platform/file-watcher.sh.
#
# Usage: Called by backup-watch.sh (not directly)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Find config file (check project root first, then environment)
CONFIG_FILE=""
PROJECT_DIR="${PROJECT_DIR:-$PWD}"

if [ -f "$PROJECT_DIR/.backup-config.sh" ]; then
    CONFIG_FILE="$PROJECT_DIR/.backup-config.sh"
elif [ -f "$PWD/.backup-config.sh" ]; then
    CONFIG_FILE="$PWD/.backup-config.sh"
    PROJECT_DIR="$PWD"
else
    echo "Error: No .backup-config.sh found in project directory" >&2
    exit 1
fi

source "$CONFIG_FILE"

# Load cross-platform file watcher abstraction
source "$LIB_DIR/platform/file-watcher.sh"

# ==============================================================================
# DEFAULTS
# ==============================================================================

# Debounce configuration
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-60}"

# State management
STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
PROJECT_STATE_DIR="$STATE_DIR/$PROJECT_NAME"
TIMER_PID_FILE="$PROJECT_STATE_DIR/.watcher-timer.pid"
WATCHER_LOG="$PROJECT_STATE_DIR/watcher.log"
LAST_TRIGGER_FILE="$PROJECT_STATE_DIR/.watcher-last-trigger"

# Ensure state directory exists
mkdir -p "$PROJECT_STATE_DIR"

# ==============================================================================
# EXCLUDE PATTERNS
# ==============================================================================

# Default excludes for common non-source directories
DEFAULT_EXCLUDES=(
    # Version control (MUST exclude -- extreme event noise)
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
    # IDE / Editor temporaries
    "\.idea"
    "\.swp$"
    "\.swo$"
    "4913"
    "\.\#"
    # OS metadata
    "\.DS_Store"
    # Infrastructure / project-specific
    "backups/"
    "\.cache"
    "\.planning/"
    "\.claudecode-backups"
    "\.terraform"
    # Compiled artifacts
    "\.pyc$"
)

# Append custom excludes from config if defined
if [ -n "${WATCHER_EXCLUDES:-}" ]; then
    for pattern in "${WATCHER_EXCLUDES[@]}"; do
        DEFAULT_EXCLUDES+=("$pattern")
    done
fi

# ==============================================================================
# LOGGING
# ==============================================================================

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$WATCHER_LOG"
}

# ==============================================================================
# CLEANUP
# ==============================================================================

WATCHER_PID=""

cleanup() {
    log "Watcher shutting down..."

    # Kill watcher process if running
    if [ -n "$WATCHER_PID" ] && kill -0 "$WATCHER_PID" 2>/dev/null; then
        kill "$WATCHER_PID" 2>/dev/null || true
        wait "$WATCHER_PID" 2>/dev/null || true
    fi

    # Kill pending timer if exists
    if [ -f "$TIMER_PID_FILE" ]; then
        local timer_pid
        timer_pid=$(cat "$TIMER_PID_FILE" 2>/dev/null) || true
        if [ -n "$timer_pid" ] && kill -0 "$timer_pid" 2>/dev/null; then
            kill "$timer_pid" 2>/dev/null || true
        fi
        rm -f "$TIMER_PID_FILE"
    fi

    log "Watcher stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

# ==============================================================================
# DEBOUNCE LOGIC
# ==============================================================================

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

        # Record trigger time
        date +%s > "$LAST_TRIGGER_FILE"

        log "Debounce timer expired, triggering backup..."

        # Run backup daemon in background (it has its own locking)
        "$SCRIPT_DIR/backup-daemon.sh" >> "$WATCHER_LOG" 2>&1 &
    ) &

    local new_pid=$!
    echo "$new_pid" > "$TIMER_PID_FILE"

    log "Timer reset (${DEBOUNCE_SECONDS}s), PID: $new_pid"
}

# ==============================================================================
# MAIN
# ==============================================================================

log "═══════════════════════════════════════════════"
log "Watcher starting for: $PROJECT_NAME"
log "Project: $PROJECT_DIR"
log "Debounce: ${DEBOUNCE_SECONDS}s"
log "═══════════════════════════════════════════════"

# Detect file watcher backend (warns on stderr if poll mode)
WATCHER_BACKEND="$(check_watcher_available)"
log "Watcher backend: $WATCHER_BACKEND"

if [ "$WATCHER_BACKEND" = "poll" ]; then
    log "WARNING: No native file watcher found. Using poll fallback (${POLL_INTERVAL:-30}s interval)"
    log "Install fswatch (macOS: brew install fswatch) or inotify-tools (Linux: apt install inotify-tools)"
fi

# Start watcher and process events through debounce
start_watcher "$PROJECT_DIR" "${DEFAULT_EXCLUDES[@]}" | while read -r _event; do
    log "File change detected (via $WATCHER_BACKEND)"
    reset_timer
done &

WATCHER_PID=$!
log "Watcher started (PID: $WATCHER_PID, backend: $WATCHER_BACKEND)"

# Wait for watcher to exit (cleanup will handle signals)
wait "$WATCHER_PID"
