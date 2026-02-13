#!/usr/bin/env bash
# Checkpoint - Smart Backup Trigger
# Runs on every user prompt via Claude Code UserPromptSubmit hook
# Triggers backup on first prompt of new session, then coordinates with daemon

set -euo pipefail

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Find config file
CONFIG_FILE=""
if [ -f "$PWD/.backup-config.sh" ]; then
    CONFIG_FILE="$PWD/.backup-config.sh"
elif [ -f "$SCRIPT_DIR/../templates/backup-config.sh" ]; then
    CONFIG_FILE="$SCRIPT_DIR/../templates/backup-config.sh"
else
    # Silently exit if no config (not all projects have backups)
    exit 0
fi

source "$CONFIG_FILE"

# ==============================================================================
# DEFENSIVE DEFAULTS (ensure script never fails)
# ==============================================================================

STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PWD")}"
SESSION_FILE="${SESSION_FILE:-$STATE_DIR/$PROJECT_NAME/.current-session-time}"
BACKUP_TIME_STATE="${BACKUP_TIME_STATE:-$STATE_DIR/$PROJECT_NAME/.last-backup-time}"
SESSION_IDLE_THRESHOLD="${SESSION_IDLE_THRESHOLD:-600}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-3600}"
DRIVE_VERIFICATION_ENABLED="${DRIVE_VERIFICATION_ENABLED:-false}"
DRIVE_MARKER_FILE="${DRIVE_MARKER_FILE:-}"

# ==============================================================================
# SESSION DETECTION
# ==============================================================================

mkdir -p "$(dirname "$SESSION_FILE")" 2>/dev/null || exit 0
mkdir -p "$(dirname "$BACKUP_TIME_STATE")" 2>/dev/null || exit 0

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
    DAEMON_SCRIPT="$SCRIPT_DIR/backup-daemon.sh"
    if [ -f "$DAEMON_SCRIPT" ]; then
        "$DAEMON_SCRIPT" > /dev/null 2>&1 &
        echo "$NOW" > "$BACKUP_TIME_STATE"
    fi
fi

exit 0
