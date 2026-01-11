#!/usr/bin/env bash
# Backup Pause Skill - Pause/resume automatic backups
set -euo pipefail

# Determine project
PROJECT_DIR="${PWD}"
PROJECT_NAME=$(basename "$PROJECT_DIR")

# State file location
STATE_DIR="$HOME/.claudecode-backups/state/${PROJECT_NAME}"
PAUSE_FILE="$STATE_DIR/.backup-paused"

mkdir -p "$STATE_DIR"

# Parse arguments
ACTION="${1:-toggle}"
DURATION="${2:-}"

show_status() {
    if [[ -f "$PAUSE_FILE" ]]; then
        local pause_time=$(cat "$PAUSE_FILE")
        local pause_until=""

        if [[ "$pause_time" =~ ^[0-9]+$ ]]; then
            local now=$(date +%s)
            if [[ $pause_time -gt $now ]]; then
                local remaining=$(( (pause_time - now) / 60 ))
                pause_until=" (${remaining} minutes remaining)"
            else
                # Pause expired, remove file
                rm -f "$PAUSE_FILE"
                echo "Backups: ACTIVE (pause expired)"
                return
            fi
        fi

        echo "Backups: PAUSED${pause_until}"
    else
        echo "Backups: ACTIVE"
    fi
}

pause_backups() {
    local duration_mins="$1"

    if [[ -n "$duration_mins" ]] && [[ "$duration_mins" =~ ^[0-9]+$ ]]; then
        # Timed pause
        local pause_until=$(( $(date +%s) + (duration_mins * 60) ))
        echo "$pause_until" > "$PAUSE_FILE"
        echo "Backups paused for ${duration_mins} minutes"
        echo "Will auto-resume at: $(date -r "$pause_until" '+%H:%M')"
    else
        # Indefinite pause
        echo "indefinite" > "$PAUSE_FILE"
        echo "Backups paused indefinitely"
        echo "Run '/backup-resume' to resume"
    fi
}

resume_backups() {
    if [[ -f "$PAUSE_FILE" ]]; then
        rm -f "$PAUSE_FILE"
        echo "Backups resumed"
    else
        echo "Backups were not paused"
    fi
}

toggle_backups() {
    if [[ -f "$PAUSE_FILE" ]]; then
        resume_backups
    else
        pause_backups "$DURATION"
    fi
}

echo "═══════════════════════════════════════════════"
echo "Checkpoint - Backup Pause Control"
echo "═══════════════════════════════════════════════"
echo ""
echo "Project: $PROJECT_NAME"
echo ""

case "$ACTION" in
    status)
        show_status
        ;;
    pause)
        pause_backups "$DURATION"
        ;;
    resume)
        resume_backups
        ;;
    toggle|"")
        toggle_backups
        ;;
    *)
        # Check if action is a number (duration)
        if [[ "$ACTION" =~ ^[0-9]+$ ]]; then
            pause_backups "$ACTION"
        else
            echo "Unknown action: $ACTION"
            echo "Valid actions: pause, resume, status, toggle, or a number (minutes)"
            exit 1
        fi
        ;;
esac

echo ""
show_status
