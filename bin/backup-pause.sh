#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Pause/Resume Backups
# ==============================================================================
# Temporarily disable/enable automatic backups
# Usage: backup-pause [--resume|--status]
# ==============================================================================

set -euo pipefail

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Platform-agnostic daemon lifecycle management
source "$SCRIPT_DIR/../lib/platform/daemon-manager.sh"

# State directory
STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"
PAUSE_FILE="$STATE_DIR/.backup-paused"

# Create state directory if needed
mkdir -p "$STATE_DIR"

# ==============================================================================
# FUNCTIONS
# ==============================================================================

pause_backups() {
    if [[ -f "$PAUSE_FILE" ]]; then
        echo "⚠️  Backups are already paused"
        show_status
        exit 0
    fi

    # Create pause file with timestamp
    echo "$(date +%s)" > "$PAUSE_FILE"
    echo "paused_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "$PAUSE_FILE"

    # Stop all backup daemons via daemon-manager.sh abstraction
    local daemon_list found_daemons=false
    daemon_list="$(list_daemons "checkpoint" 2>/dev/null)" || true
    local legacy_list
    legacy_list="$(list_daemons "claudecode" 2>/dev/null)" || true
    if [ -n "$legacy_list" ]; then
        if [ -n "$daemon_list" ]; then
            daemon_list="$(printf '%s\n%s' "$daemon_list" "$legacy_list")"
        else
            daemon_list="$legacy_list"
        fi
    fi

    if [ -n "$daemon_list" ]; then
        # Extract service names and stop each daemon
        echo "$daemon_list" | while IFS= read -r line; do
            [ -z "$line" ] && continue
            local svc_name=""
            # launchd format: com.checkpoint.NAME or com.claudecode.backup.NAME
            svc_name="$(echo "$line" | grep -o 'com\.checkpoint\.[^ ]*' | sed 's/^com\.checkpoint\.//' || true)"
            if [ -z "$svc_name" ]; then
                svc_name="$(echo "$line" | grep -o 'com\.claudecode\.backup\.[^ ]*' | sed 's/^com\.claudecode\.backup\.//' || true)"
            fi
            # systemd format: checkpoint-NAME.service
            if [ -z "$svc_name" ]; then
                svc_name="$(echo "$line" | grep -o 'checkpoint-[^ .]*' | sed 's/^checkpoint-//' || true)"
            fi
            # cron format: # checkpoint:NAME
            if [ -z "$svc_name" ]; then
                svc_name="$(echo "$line" | grep -o 'checkpoint:[^ ]*' | sed 's/^checkpoint://' || true)"
            fi
            if [ -n "$svc_name" ]; then
                stop_daemon "$svc_name" 2>/dev/null || true
            fi
        done
        echo "✅ Automatic backups paused"
    else
        echo "✅ Backups paused"
    fi

    echo ""
    echo "Backups will not run automatically until resumed."
    echo "To resume: backup-pause --resume"
}

resume_backups() {
    if [[ ! -f "$PAUSE_FILE" ]]; then
        echo "ℹ️  Backups are not paused"
        exit 0
    fi

    # Remove pause file
    rm -f "$PAUSE_FILE"

    # Restart all backup daemons via daemon-manager.sh abstraction
    local daemon_list found_daemons=false
    daemon_list="$(list_daemons "checkpoint" 2>/dev/null)" || true
    local legacy_list
    legacy_list="$(list_daemons "claudecode" 2>/dev/null)" || true
    if [ -n "$legacy_list" ]; then
        if [ -n "$daemon_list" ]; then
            daemon_list="$(printf '%s\n%s' "$daemon_list" "$legacy_list")"
        else
            daemon_list="$legacy_list"
        fi
    fi

    if [ -n "$daemon_list" ]; then
        # Extract service names and start each daemon
        echo "$daemon_list" | while IFS= read -r line; do
            [ -z "$line" ] && continue
            local svc_name=""
            # launchd format: com.checkpoint.NAME or com.claudecode.backup.NAME
            svc_name="$(echo "$line" | grep -o 'com\.checkpoint\.[^ ]*' | sed 's/^com\.checkpoint\.//' || true)"
            if [ -z "$svc_name" ]; then
                svc_name="$(echo "$line" | grep -o 'com\.claudecode\.backup\.[^ ]*' | sed 's/^com\.claudecode\.backup\.//' || true)"
            fi
            # systemd format: checkpoint-NAME.service
            if [ -z "$svc_name" ]; then
                svc_name="$(echo "$line" | grep -o 'checkpoint-[^ .]*' | sed 's/^checkpoint-//' || true)"
            fi
            # cron format: # checkpoint:NAME
            if [ -z "$svc_name" ]; then
                svc_name="$(echo "$line" | grep -o 'checkpoint:[^ ]*' | sed 's/^checkpoint://' || true)"
            fi
            if [ -n "$svc_name" ]; then
                start_daemon "$svc_name" 2>/dev/null || true
            fi
        done
        echo "✅ Automatic backups resumed"
    else
        echo "✅ Backups resumed"
    fi

    echo ""
    echo "Backups will now run automatically on schedule."
}

show_status() {
    if [[ -f "$PAUSE_FILE" ]]; then
        paused_at=$(grep "paused_at=" "$PAUSE_FILE" | cut -d'=' -f2)
        echo "Status: ⏸️  PAUSED"
        echo "Paused at: $paused_at"
        echo ""
        echo "To resume: backup-pause --resume"
    else
        echo "Status: ✅ ACTIVE"
        echo ""
        echo "Backups are running normally."
        echo "To pause: backup-pause"
    fi
}

# ==============================================================================
# COMMAND LINE PARSING
# ==============================================================================

ACTION="pause"

while [[ $# -gt 0 ]]; do
    case $1 in
        --resume|-r)
            ACTION="resume"
            shift
            ;;
        --status|-s)
            ACTION="status"
            shift
            ;;
        --help|-h)
            cat <<EOF
Checkpoint - Pause/Resume Backups

USAGE:
    backup-pause           Pause automatic backups
    backup-pause --resume  Resume automatic backups
    backup-pause --status  Show current status

DESCRIPTION:
    Temporarily disable or re-enable automatic backups.

    When paused:
    - Hourly backups will not run
    - Manual backups (backup-now) still work
    - Backup daemon is stopped (if installed)

    When resumed:
    - Hourly backups restart
    - Backup daemon is restarted

OPTIONS:
    --resume, -r    Resume automatic backups
    --status, -s    Show pause status
    --help, -h      Show this help message

EXAMPLES:
    backup-pause            # Pause backups
    backup-pause --resume   # Resume backups
    backup-pause --status   # Check if paused

NOTES:
    - Manual backups (backup-now) work even when paused
    - Pause state persists across reboots
    - Resume restores the previous schedule

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ==============================================================================
# EXECUTE ACTION
# ==============================================================================

case "$ACTION" in
    pause)
        pause_backups
        ;;
    resume)
        resume_backups
        ;;
    status)
        show_status
        ;;
esac
