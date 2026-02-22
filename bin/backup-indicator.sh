#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Backup Status Indicator
# ==============================================================================
# CLI command for global backup status with multiple output formats
# Designed for status bars, scripts, and monitoring tools
# ==============================================================================

set -euo pipefail

# Find script directory and load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Source global status library
source "$LIB_DIR/global-status.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

STATUS_FILE="${CHECKPOINT_STATUS_FILE:-$HOME/.config/checkpoint/status.json}"
STATUS_DIR="$(dirname "$STATUS_FILE")"
DAEMON_INTERVAL="${CHECKPOINT_DAEMON_INTERVAL:-60}"
DAEMON_PID_FILE="$STATUS_DIR/indicator.pid"

# ==============================================================================
# OUTPUT FORMATS
# ==============================================================================

# Just emoji: ✅ or ⚠ or ❌
output_emoji() {
    local health=$(get_global_health)
    case "$health" in
        healthy) echo "✅" ;;
        warning) echo "⚠" ;;
        error) echo "❌" ;;
    esac
}

# Compact: "✅ 5 OK" or "⚠ 2/5"
output_compact() {
    get_global_summary
}

# Verbose: Full multi-line status per project
output_verbose() {
    echo "Checkpoint Backup Status"
    echo "========================"
    echo ""
    echo "Global: $(get_global_summary)"
    echo ""

    local count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ((count++))
        echo "  $line"
    done < <(get_all_projects_status)

    if [[ $count -eq 0 ]]; then
        echo "  No projects registered"
        echo ""
        echo "Register a project with: checkpoint.sh register /path/to/project"
    fi
}

# JSON output for external tools
output_json() {
    local health=$(get_global_health)
    local summary=$(get_global_summary)
    local updated=$(date +%s)

    cat <<EOF
{
  "health": "$health",
  "summary": "$summary",
  "updated": $updated,
  "projects": $(get_all_projects_status_json)
}
EOF
}

# ==============================================================================
# DAEMON MODE
# ==============================================================================

# Write status to file
write_status_file() {
    mkdir -p "$STATUS_DIR"
    output_json > "$STATUS_FILE.tmp"
    mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}

# Run as daemon, updating status file periodically
run_daemon() {
    mkdir -p "$STATUS_DIR"

    # Check if already running
    if [[ -f "$DAEMON_PID_FILE" ]]; then
        local pid=$(cat "$DAEMON_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Daemon already running (PID: $pid)" >&2
            exit 1
        fi
    fi

    # Write PID file
    echo $$ > "$DAEMON_PID_FILE"

    echo "Starting backup indicator daemon (interval: ${DAEMON_INTERVAL}s)"
    echo "Status file: $STATUS_FILE"
    echo "PID: $$"

    # Trap signals for cleanup
    trap 'rm -f "$DAEMON_PID_FILE"; exit 0' SIGTERM SIGINT

    # Main loop
    while true; do
        write_status_file
        sleep "$DAEMON_INTERVAL"
    done
}

# Stop daemon
stop_daemon() {
    if [[ -f "$DAEMON_PID_FILE" ]]; then
        local pid=$(cat "$DAEMON_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping daemon (PID: $pid)"
            kill "$pid"
            rm -f "$DAEMON_PID_FILE"
            return 0
        else
            echo "Daemon not running (stale PID file)"
            rm -f "$DAEMON_PID_FILE"
            return 1
        fi
    else
        echo "Daemon not running"
        return 1
    fi
}

# Check daemon status
daemon_status() {
    if [[ -f "$DAEMON_PID_FILE" ]]; then
        local pid=$(cat "$DAEMON_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Daemon running (PID: $pid)"

            # Show status file info if exists
            if [[ -f "$STATUS_FILE" ]]; then
                local updated
                if command -v python3 &>/dev/null; then
                    updated=$(python3 -c "import json; print(json.load(open('$STATUS_FILE'))['updated'])" 2>/dev/null)
                else
                    updated=$(grep -o '"updated": [0-9]*' "$STATUS_FILE" | grep -o '[0-9]*' || true)
                fi

                if [[ -n "$updated" ]]; then
                    local now=$(date +%s)
                    local age=$((now - updated))
                    echo "Last update: ${age}s ago"
                fi
            fi
            return 0
        fi
    fi
    echo "Daemon not running"
    return 1
}

# ==============================================================================
# EXIT CODE MAPPING
# ==============================================================================

# Set exit code based on health
# 0 = healthy, 1 = warning, 2 = error
get_exit_code() {
    local health=$(get_global_health)
    case "$health" in
        healthy) return 0 ;;
        warning) return 1 ;;
        error) return 2 ;;
    esac
}

# ==============================================================================
# USAGE
# ==============================================================================

usage() {
    cat <<EOF
Usage: backup-indicator.sh [OPTIONS]

Display global backup status across all registered Checkpoint projects.

Output Formats:
  --emoji, -e       Just emoji (✅/⚠/❌) for minimal UIs
  --compact, -c     Compact format: "✅ 5 OK" or "⚠ 2/5"
  --verbose, -v     Full multi-line status per project
  --json, -j        JSON output for external tools

Daemon Mode:
  --daemon, -d      Run as background daemon, updating status file
  --stop            Stop the daemon
  --status          Check if daemon is running

Options:
  --help, -h        Show this help message

Exit Codes:
  0 = All projects healthy
  1 = One or more projects have warnings
  2 = One or more projects have errors

Environment Variables:
  CHECKPOINT_STATUS_FILE    Status file location (default: ~/.config/checkpoint/status.json)
  CHECKPOINT_DAEMON_INTERVAL  Update interval in seconds (default: 60)

Examples:
  backup-indicator.sh --emoji        # For tmux/status bar
  backup-indicator.sh --json         # For scripting
  backup-indicator.sh --daemon &     # Start background updates
  backup-indicator.sh --verbose      # Full status report
EOF
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    local format="emoji"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --emoji|-e)
                format="emoji"
                shift
                ;;
            --compact|-c)
                format="compact"
                shift
                ;;
            --verbose|-v)
                format="verbose"
                shift
                ;;
            --json|-j)
                format="json"
                shift
                ;;
            --daemon|-d)
                run_daemon
                exit 0
                ;;
            --stop)
                stop_daemon
                exit $?
                ;;
            --status)
                daemon_status
                exit $?
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done

    # Output in requested format
    case "$format" in
        emoji) output_emoji ;;
        compact) output_compact ;;
        verbose) output_verbose ;;
        json) output_json ;;
    esac

    # Set exit code based on health
    get_exit_code
}

main "$@"
