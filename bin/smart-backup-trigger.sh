#!/bin/bash
# ClaudeCode Project Backups - Smart Backup Trigger
# Runs on every user prompt via Claude Code UserPromptSubmit hook
# Triggers backup on first prompt of new session, then coordinates with daemon

set -euo pipefail

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

# Find config file
CONFIG_FILE=""
if [ -f "$PWD/.backup-config.sh" ]; then
    CONFIG_FILE="$PWD/.backup-config.sh"
elif [ -f "$(dirname "$0")/../templates/backup-config.sh" ]; then
    CONFIG_FILE="$(dirname "$0")/../templates/backup-config.sh"
else
    # Silently exit if no config (not all projects have backups)
    exit 0
fi

source "$CONFIG_FILE"

# ==============================================================================
# SESSION DETECTION
# ==============================================================================

mkdir -p "$(dirname "$SESSION_FILE")"
mkdir -p "$(dirname "$BACKUP_TIME_STATE")"

# Check if correct drive is connected (if verification enabled)
if [ "$DRIVE_VERIFICATION_ENABLED" = true ]; then
    if [ ! -f "$DRIVE_MARKER_FILE" ]; then
        exit 0  # Drive not connected, skip
    fi
fi

# Detect new session using time-based approach
LAST_PROMPT_TIME=$(cat "$SESSION_FILE" 2>/dev/null || echo "0")
NOW_FOR_SESSION=$(date +%s)
SESSION_IDLE_TIME=$((NOW_FOR_SESSION - LAST_PROMPT_TIME))

# Update session timestamp
echo "$NOW_FOR_SESSION" > "$SESSION_FILE"

# Determine if this is a new session
IS_NEW_SESSION=false
if [ $SESSION_IDLE_TIME -gt $SESSION_IDLE_THRESHOLD ]; then
    IS_NEW_SESSION=true
fi

# ==============================================================================
# BACKUP TRIGGER LOGIC
# ==============================================================================

# Get last backup time
LAST_BACKUP=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
NOW=$(date +%s)
DIFF=$((NOW - LAST_BACKUP))

# Trigger backup if:
# 1. New session (after idle period)
# 2. OR backup interval elapsed
SHOULD_BACKUP=false

if [ "$IS_NEW_SESSION" = true ]; then
    SHOULD_BACKUP=true
elif [ $DIFF -gt $BACKUP_INTERVAL ]; then
    SHOULD_BACKUP=true
fi

# Run backup in background
if [ "$SHOULD_BACKUP" = true ]; then
    DAEMON_SCRIPT="$(dirname "$0")/backup-daemon.sh"
    if [ -f "$DAEMON_SCRIPT" ]; then
        "$DAEMON_SCRIPT" > /dev/null 2>&1 &
        echo "$NOW" > "$BACKUP_TIME_STATE"
    fi
fi

exit 0
