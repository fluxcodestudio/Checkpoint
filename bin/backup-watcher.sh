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

# Session detection (migrated from smart-backup-trigger.sh)
SESSION_FILE="$PROJECT_STATE_DIR/.current-session-time"
BACKUP_TIME_STATE="$PROJECT_STATE_DIR/.last-backup-time"
SESSION_IDLE_THRESHOLD="${SESSION_IDLE_THRESHOLD:-600}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-3600}"
DRIVE_VERIFICATION_ENABLED="${DRIVE_VERIFICATION_ENABLED:-false}"
DRIVE_MARKER_FILE="${DRIVE_MARKER_FILE:-}"

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
# SESSION DETECTION (migrated from smart-backup-trigger.sh)
# ==============================================================================

check_new_session() {
    local last_session
    last_session=$(cat "$SESSION_FILE" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    if [ $((now - last_session)) -gt "$SESSION_IDLE_THRESHOLD" ]; then
        return 0  # New session
    fi
    return 1
}

should_backup_now() {
    # Check backup interval
    local last_backup
    last_backup=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    if [ $((now - last_backup)) -lt "$BACKUP_INTERVAL" ]; then
        return 1  # Too soon
    fi
    # Check drive verification
    if [ "$DRIVE_VERIFICATION_ENABLED" = true ] && [ ! -f "${DRIVE_MARKER_FILE:-}" ]; then
        return 1  # Drive not connected
    fi
    return 0
}

update_session_time() {
    date +%s > "$SESSION_FILE"
}

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

CLEANUP_DONE=false

cleanup() {
    [ "$CLEANUP_DONE" = true ] && return
    CLEANUP_DONE=true

    log "Watcher shutting down..."

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
}

trap cleanup SIGTERM SIGINT SIGHUP EXIT

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

    # Start new timer in background (close inherited FDs to avoid blocking pipe)
    (
        exec 0<&- 1>/dev/null  # close stdin, redirect stdout
        sleep "$DEBOUNCE_SECONDS"
        rm -f "$TIMER_PID_FILE"

        # Record trigger time
        date +%s > "$LAST_TRIGGER_FILE"

        # Pre-check: skip daemon spawn if interval not elapsed or drive unavailable
        if should_backup_now; then
            log "Debounce timer expired, triggering backup..."
            if ! "$SCRIPT_DIR/backup-daemon.sh" >> "$WATCHER_LOG" 2>&1; then
                log "ERROR: backup-daemon.sh failed with exit code $?"
            fi
        else
            log "Debounce timer expired, backup skipped (interval not elapsed or drive unavailable)"
        fi
    ) &

    local new_pid=$!
    echo "$new_pid" > "$TIMER_PID_FILE"

    log "Timer reset (${DEBOUNCE_SECONDS}s), PID: $new_pid"
}

# ==============================================================================
# MAIN
# ==============================================================================

# Log rotation on startup
MAX_LOG_SIZE="${MAX_LOG_SIZE:-1048576}"  # 1MB default
if [ -f "$WATCHER_LOG" ] && [ "$(wc -c < "$WATCHER_LOG" 2>/dev/null || echo 0)" -gt "$MAX_LOG_SIZE" ]; then
    mv "$WATCHER_LOG" "${WATCHER_LOG}.old"
fi

log "═══════════════════════════════════════════════"
log "Watcher starting for: $PROJECT_NAME"
log "Project: $PROJECT_DIR"
log "Debounce: ${DEBOUNCE_SECONDS}s"
log "Session idle threshold: ${SESSION_IDLE_THRESHOLD}s"
log "Backup interval: ${BACKUP_INTERVAL}s"
log "═══════════════════════════════════════════════"

# Detect file watcher backend (warns on stderr if poll mode)
WATCHER_BACKEND="$(check_watcher_available)"
log "Watcher backend: $WATCHER_BACKEND"

if [ "$WATCHER_BACKEND" = "poll" ]; then
    log "WARNING: No native file watcher found. Using poll fallback (${POLL_INTERVAL:-30}s interval)"
    log "Install fswatch (macOS: brew install fswatch) or inotify-tools (Linux: apt install inotify-tools)"
fi

# Startup: trigger immediate backup if new session
if check_new_session; then
    log "New session detected (idle > ${SESSION_IDLE_THRESHOLD}s)"
    if should_backup_now; then
        log "Triggering startup backup..."
        "$SCRIPT_DIR/backup-daemon.sh" >> "$WATCHER_LOG" 2>&1 &
    else
        log "Startup backup skipped (interval not elapsed or drive unavailable)"
    fi
fi
update_session_time

# Start watcher and process events through debounce (process substitution
# ensures watcher runs in current process group, killed by cleanup)
log "Watcher started (backend: $WATCHER_BACKEND)"
while read -r _event; do
    # Health check: verify project directory still exists
    if [ ! -d "$PROJECT_DIR" ]; then
        log "ERROR: Project directory no longer exists: $PROJECT_DIR"
        break
    fi
    update_session_time
    log "File change detected (via $WATCHER_BACKEND)"
    reset_timer
done < <(start_watcher "$PROJECT_DIR" "${DEFAULT_EXCLUDES[@]}")
