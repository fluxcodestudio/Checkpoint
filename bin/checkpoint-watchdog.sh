#!/usr/bin/env bash
# Checkpoint Watchdog - Monitors daemon heartbeat and auto-restarts if crashed
# Runs as a daemon to ensure backups never stop

set -euo pipefail

# Resolve script directory for sourcing sibling modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cross-platform helpers (stat, notifications)
source "$SCRIPT_DIR/../lib/platform/compat.sh"

# Platform-agnostic daemon lifecycle management
source "$SCRIPT_DIR/../lib/platform/daemon-manager.sh"

# Configuration
HEARTBEAT_DIR="${HOME}/.checkpoint"
HEARTBEAT_FILE="${HEARTBEAT_DIR}/daemon.heartbeat"
STALE_THRESHOLD=300  # 5 minutes - daemon should update heartbeat every backup cycle
CHECK_INTERVAL=60    # Check every minute
LOG_DIR="${HOME}/.checkpoint/logs"
LOG_FILE="${LOG_DIR}/watchdog.log"
MAX_LOG_SIZE=$((1024 * 1024))  # 1MB

# Ensure directories exist
mkdir -p "$HEARTBEAT_DIR" "$LOG_DIR"

# Logging function
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$LOG_FILE"

    # Rotate log if too large
    if [ -f "$LOG_FILE" ] && [ "$(get_file_size "$LOG_FILE")" -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
    fi
}

# Find checkpoint CLI
find_checkpoint_cli() {
    local paths=(
        "$HOME/.local/bin/checkpoint"
        "/usr/local/bin/checkpoint"
        "/opt/homebrew/bin/checkpoint"
    )

    for path in "${paths[@]}"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

# Read heartbeat file and return status
read_heartbeat() {
    if [[ ! -f "$HEARTBEAT_FILE" ]]; then
        echo "missing"
        return
    fi

    local timestamp status
    timestamp=$(grep -o '"timestamp": *[0-9]*' "$HEARTBEAT_FILE" 2>/dev/null | grep -o '[0-9]*' || echo "0")
    status=$(grep -o '"status": *"[^"]*"' "$HEARTBEAT_FILE" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "unknown")

    local now age
    now=$(date +%s)
    age=$((now - timestamp))

    if [[ $age -gt $STALE_THRESHOLD ]]; then
        echo "stale:$age"
    else
        echo "$status:$age"
    fi
}

# Check if any backup daemons are running
# Returns service names (one per line) suitable for daemon-manager.sh API calls.
# Searches both new (com.checkpoint.*) and legacy (com.claudecode.backup.*) naming.
get_running_daemons() {
    local raw_list service_names=""

    # List daemons matching checkpoint naming (platform-agnostic)
    raw_list="$(list_daemons "checkpoint" 2>/dev/null)" || true

    # Also check legacy naming
    local legacy_list
    legacy_list="$(list_daemons "claudecode" 2>/dev/null)" || true
    if [ -n "$legacy_list" ]; then
        if [ -n "$raw_list" ]; then
            raw_list="$(printf '%s\n%s' "$raw_list" "$legacy_list")"
        else
            raw_list="$legacy_list"
        fi
    fi

    if [ -z "$raw_list" ]; then
        return
    fi

    # Extract service names from platform-specific output.
    # launchd: columns are PID STATUS LABEL; extract LABEL then strip prefix.
    # systemd: lines like "checkpoint-foo.service loaded active running ..."; extract unit name.
    # cron: lines contain "# checkpoint:service_name"; extract after tag.
    echo "$raw_list" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        local svc_name=""
        # Try launchd format: com.checkpoint.NAME or com.claudecode.backup.NAME
        svc_name="$(echo "$line" | grep -o 'com\.checkpoint\.[^ ]*' | sed 's/^com\.checkpoint\.//' || true)"
        if [ -z "$svc_name" ]; then
            svc_name="$(echo "$line" | grep -o 'com\.claudecode\.backup\.[^ ]*' | sed 's/^com\.claudecode\.backup\.//' || true)"
        fi
        # Try systemd format: checkpoint-NAME.service
        if [ -z "$svc_name" ]; then
            svc_name="$(echo "$line" | grep -o 'checkpoint-[^ .]*' | sed 's/^checkpoint-//' || true)"
        fi
        # Try cron format: # checkpoint:NAME
        if [ -z "$svc_name" ]; then
            svc_name="$(echo "$line" | grep -o 'checkpoint:[^ ]*' | sed 's/^checkpoint://' || true)"
        fi
        if [ -n "$svc_name" ]; then
            echo "$svc_name"
        fi
    done || true
}

# Restart a specific daemon via daemon-manager.sh abstraction
restart_backup_daemon() {
    local service_name="$1"
    log "Restarting daemon: $service_name"
    if restart_daemon "$service_name"; then
        log "Daemon restarted successfully: $service_name"
        return 0
    else
        log "Failed to restart daemon: $service_name"
        return 1
    fi
}

# Run a manual backup for a project
trigger_backup() {
    local cli
    if cli=$(find_checkpoint_cli); then
        log "Triggering manual backup via CLI"
        "$cli" backup-now 2>/dev/null || true
    fi
}

# send_notification() is provided by lib/platform/compat.sh (cross-platform)

# Write watchdog status file (for menu bar app to read)
write_status() {
    local status="$1"
    local daemon_count="$2"
    local last_check
    last_check=$(date +%s)

    cat > "${HEARTBEAT_DIR}/watchdog.status" <<EOF
{
  "status": "$status",
  "daemon_count": $daemon_count,
  "last_check": $last_check,
  "pid": $$
}
EOF
}

# Main watchdog loop
main() {
    log "Watchdog starting (PID: $$)"

    local consecutive_failures=0
    local max_failures=3

    while true; do
        local daemons
        daemons=$(get_running_daemons)
        local daemon_count
        daemon_count=$(echo "$daemons" | grep -c . || echo "0")

        if [[ $daemon_count -eq 0 ]]; then
            log "No backup daemons found"
            write_status "no_daemons" 0
            sleep "$CHECK_INTERVAL"
            continue
        fi

        local heartbeat_status
        heartbeat_status=$(read_heartbeat)
        local status_type="${heartbeat_status%%:*}"
        local status_age="${heartbeat_status#*:}"

        case "$status_type" in
            healthy|syncing)
                consecutive_failures=0
                write_status "healthy" "$daemon_count"
                ;;

            stale|missing)
                ((consecutive_failures++)) || true
                log "Heartbeat issue: $status_type (age: ${status_age}s, failures: $consecutive_failures)"

                if [[ $consecutive_failures -ge $max_failures ]]; then
                    log "Max failures reached, attempting restart"

                    # Restart all found daemons
                    while IFS= read -r label; do
                        [ -z "$label" ] && continue
                        restart_backup_daemon "$label"
                    done <<< "$daemons"

                    send_notification "Checkpoint Watchdog" "Restarted backup daemon after heartbeat timeout"
                    consecutive_failures=0
                fi

                write_status "warning" "$daemon_count"
                ;;

            error)
                log "Daemon reported error state"
                write_status "error" "$daemon_count"
                consecutive_failures=0  # Don't restart on reported errors, daemon handles it
                ;;

            *)
                log "Unknown heartbeat status: $status_type"
                write_status "unknown" "$daemon_count"
                ;;
        esac

        sleep "$CHECK_INTERVAL"
    done
}

# Handle signals gracefully
cleanup() {
    log "Watchdog stopping (received signal)"
    write_status "stopped" 0
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# Run main loop
main
