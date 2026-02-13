#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - File Watcher with Debounced Backup Triggering
# ==============================================================================
# Watches project files for changes and triggers backup after inactivity period.
# Uses fswatch with FSEvents backend (macOS) for efficient file monitoring.
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
    "node_modules"
    "\.git"
    "backups/"
    "\.cache"
    "__pycache__"
    "\.pyc$"
    "\.swp$"
    "\.DS_Store"
    "dist/"
    "build/"
    "\.next/"
    "coverage/"
    "\.planning/"
    "\.claudecode-backups"
)

# Build fswatch exclude arguments
FSWATCH_EXCLUDES=()
for pattern in "${DEFAULT_EXCLUDES[@]}"; do
    FSWATCH_EXCLUDES+=(-e "$pattern")
done

# Add custom excludes from config if defined
if [ -n "${WATCHER_EXCLUDES:-}" ]; then
    for pattern in "${WATCHER_EXCLUDES[@]}"; do
        FSWATCH_EXCLUDES+=(-e "$pattern")
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

FSWATCH_PID=""

cleanup() {
    log "Watcher shutting down..."

    # Kill fswatch process if running
    if [ -n "$FSWATCH_PID" ] && kill -0 "$FSWATCH_PID" 2>/dev/null; then
        kill "$FSWATCH_PID" 2>/dev/null || true
        wait "$FSWATCH_PID" 2>/dev/null || true
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

# Check fswatch is installed
if ! command -v fswatch &>/dev/null; then
    log "ERROR: fswatch not installed. Run: brew install fswatch"
    echo "Error: fswatch not installed. Run: brew install fswatch" >&2
    exit 1
fi

# Start fswatch in one-per-batch mode and process events
# -o: one event per batch (coalesce multiple rapid changes)
# -r: recursive
# --batch-marker: mark end of batch (not needed with -o)
fswatch -o -r "${FSWATCH_EXCLUDES[@]}" "$PROJECT_DIR" | while read -r _count; do
    log "File change detected"
    reset_timer
done &

FSWATCH_PID=$!
log "fswatch started (PID: $FSWATCH_PID)"

# Wait for fswatch to exit (cleanup will handle signals)
wait "$FSWATCH_PID"
