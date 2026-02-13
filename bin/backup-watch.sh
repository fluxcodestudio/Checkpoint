#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Watcher Management Commands
# ==============================================================================
# Start, stop, and manage the file watcher for automatic backups.
# Usage: backup-watch [start|stop|status|restart]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

PROJECT_DIR="${PROJECT_DIR:-$PWD}"
CONFIG_FILE=""

if [ -f "$PROJECT_DIR/.backup-config.sh" ]; then
    CONFIG_FILE="$PROJECT_DIR/.backup-config.sh"
elif [ -f "$PWD/.backup-config.sh" ]; then
    CONFIG_FILE="$PWD/.backup-config.sh"
    PROJECT_DIR="$PWD"
fi

# Load config if available
if [ -n "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Load cross-platform file watcher abstraction
source "$LIB_DIR/platform/file-watcher.sh"

# ==============================================================================
# DEFAULTS
# ==============================================================================

STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
PROJECT_STATE_DIR="$STATE_DIR/$PROJECT_NAME"
WATCHER_PID_FILE="$PROJECT_STATE_DIR/.watcher.pid"
TIMER_PID_FILE="$PROJECT_STATE_DIR/.watcher-timer.pid"
WATCHER_LOG="$PROJECT_STATE_DIR/watcher.log"
LAST_TRIGGER_FILE="$PROJECT_STATE_DIR/.watcher-last-trigger"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-60}"
WATCHER_ENABLED="${WATCHER_ENABLED:-false}"

# Ensure state directory exists
mkdir -p "$PROJECT_STATE_DIR"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

is_watcher_running() {
    if [ ! -f "$WATCHER_PID_FILE" ]; then
        return 1
    fi

    local pid
    pid=$(cat "$WATCHER_PID_FILE" 2>/dev/null) || return 1

    if [ -z "$pid" ]; then
        return 1
    fi

    if kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q "backup-watcher"; then
        return 0
    else
        # Stale PID file
        rm -f "$WATCHER_PID_FILE"
        return 1
    fi
}

get_watcher_pid() {
    if [ -f "$WATCHER_PID_FILE" ]; then
        cat "$WATCHER_PID_FILE" 2>/dev/null || echo ""
    fi
}

format_time_ago() {
    local timestamp="$1"
    local now
    now=$(date +%s)
    local diff=$((now - timestamp))

    if [ $diff -lt 60 ]; then
        echo "${diff}s ago"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60))m ago"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# ==============================================================================
# COMMANDS
# ==============================================================================

cmd_start() {
    # Check if already running
    if is_watcher_running; then
        local pid
        pid=$(get_watcher_pid)
        echo "Watcher already running for $PROJECT_NAME (PID: $pid)"
        exit 0
    fi

    # Check watcher backend availability
    local backend
    backend="$(check_watcher_available)"
    if [ "$backend" = "poll" ]; then
        echo "Warning: No native file watcher found. Using poll fallback (less efficient)."
        echo ""
        case "$(uname -s)" in
            Darwin) echo "  Recommended: brew install fswatch" ;;
            Linux)  echo "  Recommended: sudo apt install inotify-tools" ;;
        esac
        echo ""
    fi

    # Check config exists
    if [ -z "$CONFIG_FILE" ]; then
        echo "Error: No .backup-config.sh found in $PROJECT_DIR"
        echo ""
        echo "Run install.sh first to set up backups."
        exit 1
    fi

    # Warn if WATCHER_ENABLED is not true
    if [ "$WATCHER_ENABLED" != "true" ]; then
        echo "Warning: WATCHER_ENABLED is not set to true in .backup-config.sh"
        echo "         Add 'WATCHER_ENABLED=true' to enable file watching."
        echo ""
    fi

    # Start watcher in background
    local watcher_script="$SCRIPT_DIR/backup-watcher.sh"

    if [ ! -f "$watcher_script" ]; then
        echo "Error: backup-watcher.sh not found at $watcher_script"
        exit 1
    fi

    # Export PROJECT_DIR for the watcher
    export PROJECT_DIR

    # Run watcher in background, redirect output to log
    nohup "$watcher_script" >> "$WATCHER_LOG" 2>&1 &
    local pid=$!

    # Save PID
    echo "$pid" > "$WATCHER_PID_FILE"

    # Wait briefly to check if it started successfully
    sleep 0.5

    if kill -0 "$pid" 2>/dev/null; then
        echo "Watcher started for $PROJECT_NAME (PID: $pid, backend: $backend)"
        echo "  Debounce: ${DEBOUNCE_SECONDS}s"
        echo "  Log: $WATCHER_LOG"
    else
        rm -f "$WATCHER_PID_FILE"
        echo "Error: Watcher failed to start. Check $WATCHER_LOG"
        exit 1
    fi
}

cmd_stop() {
    if ! is_watcher_running; then
        echo "Watcher not running for $PROJECT_NAME"
        exit 0
    fi

    local pid
    pid=$(get_watcher_pid)

    # Send SIGTERM (watcher has trap for cleanup)
    if kill "$pid" 2>/dev/null; then
        # Wait for process to exit
        local count=0
        while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
            sleep 0.5
            count=$((count + 1))
        done

        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi

    # Clean up PID files
    rm -f "$WATCHER_PID_FILE"
    rm -f "$TIMER_PID_FILE"

    echo "Watcher stopped for $PROJECT_NAME"
}

cmd_status() {
    echo "Watcher Status - $PROJECT_NAME"
    echo ""

    if is_watcher_running; then
        local pid
        pid=$(get_watcher_pid)
        echo "  Status:   Running (PID: $pid)"
    else
        echo "  Status:   Stopped"
    fi

    echo "  Debounce: ${DEBOUNCE_SECONDS}s"

    # Show detected backend
    local backend
    backend="$(detect_watcher)"
    if [ "$backend" = "poll" ]; then
        echo "  Backend: poll (degraded — install native watcher for better performance)"
    else
        echo "  Backend: $backend (native)"
    fi

    # Show last trigger time
    if [ -f "$LAST_TRIGGER_FILE" ]; then
        local last_trigger
        last_trigger=$(cat "$LAST_TRIGGER_FILE" 2>/dev/null) || last_trigger=0
        if [ "$last_trigger" -gt 0 ]; then
            local ago
            ago=$(format_time_ago "$last_trigger")
            echo "  Last trigger: $ago"
        fi
    else
        echo "  Last trigger: Never"
    fi

    # Show WATCHER_ENABLED status
    if [ "$WATCHER_ENABLED" = "true" ]; then
        echo "  Config: WATCHER_ENABLED=true"
    else
        echo "  Config: WATCHER_ENABLED=false (not enabled in config)"
    fi

    # Show log file location
    if [ -f "$WATCHER_LOG" ]; then
        local log_lines
        log_lines=$(wc -l < "$WATCHER_LOG" | tr -d ' ')
        echo "  Log: $WATCHER_LOG ($log_lines lines)"
    else
        echo "  Log: $WATCHER_LOG (not created yet)"
    fi
}

cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

show_usage() {
    cat <<EOF
Checkpoint - Watcher Management

USAGE:
    backup-watch <command>

COMMANDS:
    start       Start file watcher for current project
    stop        Stop file watcher for current project
    status      Show watcher status
    restart     Stop then start watcher

DESCRIPTION:
    Manages the file watcher that triggers automatic backups after
    a period of file inactivity (default: 60 seconds).

    Uses native file system events for efficient monitoring:
    fswatch (macOS), inotifywait (Linux), or poll fallback.
    When files change, it starts a debounce timer. If no more
    changes occur within the debounce period, it triggers a
    backup via backup-daemon.sh.

CONFIGURATION:
    Add these to .backup-config.sh:

    WATCHER_ENABLED=true          # Enable file watching
    DEBOUNCE_SECONDS=60           # Seconds to wait after last change
    POLL_INTERVAL=30              # Seconds between polls (fallback only)

EXAMPLES:
    backup-watch start            # Start watching current project
    backup-watch stop             # Stop watching
    backup-watch status           # Check if watcher is running
    backup-watch restart          # Restart watcher

REQUIREMENTS:
    macOS:  fswatch (brew install fswatch)
    Linux:  inotify-tools (apt install inotify-tools)
    Other:  Falls back to polling if neither available

EOF
}

# ==============================================================================
# MAIN
# ==============================================================================

# Parse command
COMMAND="${1:-}"

case "$COMMAND" in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    status)
        cmd_status
        ;;
    restart)
        cmd_restart
        ;;
    --help|-h|help)
        show_usage
        ;;
    "")
        show_usage
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo ""
        echo "Use 'backup-watch --help' for usage information."
        exit 1
        ;;
esac
