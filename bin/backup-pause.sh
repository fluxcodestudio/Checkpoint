#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Pause/Resume Backups
# ==============================================================================
# Temporarily disable/enable automatic backups
# Usage: backup-pause [--resume|--status]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

    # Unload LaunchAgent if it exists
    PLIST_FILE="$HOME/Library/LaunchAgents/com.claudecode.backup.*.plist"
    if ls $PLIST_FILE 2>/dev/null; then
        for plist in $PLIST_FILE; do
            launchctl unload "$plist" 2>/dev/null || true
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

    # Reload LaunchAgent if it exists
    PLIST_FILE="$HOME/Library/LaunchAgents/com.claudecode.backup.*.plist"
    if ls $PLIST_FILE 2>/dev/null; then
        for plist in $PLIST_FILE; do
            launchctl load "$plist" 2>/dev/null || true
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
    - LaunchAgent is unloaded (if installed)

    When resumed:
    - Hourly backups restart
    - LaunchAgent is reloaded

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
