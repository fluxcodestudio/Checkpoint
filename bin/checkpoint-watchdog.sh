#!/usr/bin/env bash
# Checkpoint Watchdog - Monitors daemon heartbeat and auto-restarts if crashed
# Runs as LaunchAgent to ensure backups never stop

set -euo pipefail

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
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]]; then
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
get_running_daemons() {
    launchctl list 2>/dev/null | grep "com.claudecode.backup" | awk '{print $3}' || true
}

# Restart a specific daemon
restart_daemon() {
    local label="$1"
    local plist_path="$HOME/Library/LaunchAgents/${label}.plist"

    if [[ -f "$plist_path" ]]; then
        log "Restarting daemon: $label"
        launchctl unload "$plist_path" 2>/dev/null || true
        sleep 1
        launchctl load -w "$plist_path" 2>/dev/null || true
        return $?
    else
        log "Plist not found: $plist_path"
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

# Send notification (macOS native)
send_notification() {
    local title="$1"
    local message="$2"

    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
}

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
                        [[ -z "$label" ]] && continue
                        restart_daemon "$label"
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
