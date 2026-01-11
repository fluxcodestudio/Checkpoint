#!/usr/bin/env bash
# Checkpoint Skill - Launch backup dashboard or execute action
set -euo pipefail

# Find the checkpoint command
CHECKPOINT_CMD=""
if command -v checkpoint &>/dev/null; then
    CHECKPOINT_CMD="checkpoint"
elif [[ -f "$HOME/.local/bin/checkpoint" ]]; then
    CHECKPOINT_CMD="$HOME/.local/bin/checkpoint"
elif [[ -f "./bin/checkpoint-dashboard.sh" ]]; then
    CHECKPOINT_CMD="./bin/checkpoint-dashboard.sh"
elif [[ -f "./bin/backup-status.sh" ]]; then
    CHECKPOINT_CMD="./bin/backup-status.sh"
fi

if [[ -z "$CHECKPOINT_CMD" ]]; then
    echo "Error: Checkpoint not installed. Run install-global.sh first."
    exit 1
fi

# Parse action argument
ACTION="${1:-dashboard}"

case "$ACTION" in
    dashboard|"")
        exec "$CHECKPOINT_CMD"
        ;;
    status)
        if [[ -f "./bin/backup-status.sh" ]]; then
            exec ./bin/backup-status.sh
        else
            exec "$CHECKPOINT_CMD" --status
        fi
        ;;
    now)
        if [[ -f "./bin/backup-now.sh" ]]; then
            exec ./bin/backup-now.sh --force
        else
            echo "Error: backup-now.sh not found"
            exit 1
        fi
        ;;
    cleanup)
        if [[ -f "./bin/backup-cleanup.sh" ]]; then
            exec ./bin/backup-cleanup.sh
        else
            echo "Error: backup-cleanup.sh not found"
            exit 1
        fi
        ;;
    restore)
        if [[ -f "./bin/backup-restore.sh" ]]; then
            exec ./bin/backup-restore.sh
        else
            echo "Error: backup-restore.sh not found"
            exit 1
        fi
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Valid actions: dashboard, status, now, cleanup, restore"
        exit 1
        ;;
esac
