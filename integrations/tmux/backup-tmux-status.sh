#!/bin/bash
# Checkpoint Project Backups - Tmux Status Bar Script
# Displays GLOBAL backup status in tmux status line
# Version: 2.0.0
#
# Now shows aggregated health across ALL registered projects

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Find integration directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../../bin" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../lib" && pwd)"

# Status file location (written by daemon)
STATUS_FILE="${CHECKPOINT_STATUS_FILE:-$HOME/.config/checkpoint/status.json}"

# Fallback: Load integration core for per-project status (backward compatibility)
BACKUP_INTEGRATION_QUIET_LOAD=true
if [[ -f "$INTEGRATION_DIR/lib/integration-core.sh" ]]; then
    source "$INTEGRATION_DIR/lib/integration-core.sh" 2>/dev/null
fi

# ==============================================================================
# FORMAT SELECTION
# ==============================================================================

# Get format from argument, tmux option, or environment
# @backup-status-format can be set in .tmux.conf
FORMAT="${1:-${TMUX_BACKUP_FORMAT:-emoji}}"

# Check for tmux option override
if command -v tmux &>/dev/null && [[ -n "$TMUX" ]]; then
    TMUX_FORMAT=$(tmux show-option -gqv @backup-status-format 2>/dev/null)
    [[ -n "$TMUX_FORMAT" ]] && FORMAT="$TMUX_FORMAT"
fi

# ==============================================================================
# GLOBAL STATUS FUNCTIONS
# ==============================================================================

# Try to read from daemon status file first (faster)
read_status_file() {
    if [[ -f "$STATUS_FILE" ]]; then
        # Check if file is recent (less than 5 minutes old)
        local file_time now age
        if [[ "$OSTYPE" == "darwin"* ]]; then
            file_time=$(stat -f %m "$STATUS_FILE" 2>/dev/null)
        else
            file_time=$(stat -c %Y "$STATUS_FILE" 2>/dev/null)
        fi

        now=$(date +%s)
        age=$((now - file_time))

        # Use file if less than 5 minutes old
        if [[ $age -lt 300 ]]; then
            return 0
        fi
    fi
    return 1
}

# Get health from status file
get_health_from_file() {
    if command -v python3 &>/dev/null; then
        python3 -c "import json; print(json.load(open('$STATUS_FILE'))['health'])" 2>/dev/null
    else
        grep -o '"health": "[^"]*"' "$STATUS_FILE" | cut -d'"' -f4
    fi
}

# Get summary from status file
get_summary_from_file() {
    if command -v python3 &>/dev/null; then
        python3 -c "import json; print(json.load(open('$STATUS_FILE'))['summary'])" 2>/dev/null
    else
        grep -o '"summary": "[^"]*"' "$STATUS_FILE" | cut -d'"' -f4
    fi
}

# Get global status directly (fallback when daemon not running)
get_global_status_direct() {
    if [[ -f "$LIB_DIR/global-status.sh" ]]; then
        source "$LIB_DIR/global-status.sh" 2>/dev/null
        return 0
    fi
    return 1
}

# ==============================================================================
# OUTPUT FUNCTIONS
# ==============================================================================

# Output emoji based on health
health_to_emoji() {
    local health="$1"
    case "$health" in
        healthy) echo "✅" ;;
        warning) echo "⚠" ;;
        error) echo "❌" ;;
        *) echo "❓" ;;
    esac
}

# Get global emoji status
get_global_emoji() {
    local health

    if read_status_file; then
        health=$(get_health_from_file)
    elif get_global_status_direct; then
        health=$(get_global_health)
    else
        echo "❌"
        return
    fi

    health_to_emoji "$health"
}

# Get global compact status
get_global_compact() {
    if read_status_file; then
        get_summary_from_file
    elif get_global_status_direct; then
        get_global_summary
    else
        echo "❌ n/a"
    fi
}

# ==============================================================================
# BACKWARD COMPATIBILITY
# ==============================================================================

# For users who want per-project status instead of global
# Set @backup-status-mode to "project" in .tmux.conf
get_status_mode() {
    if command -v tmux &>/dev/null && [[ -n "$TMUX" ]]; then
        local mode=$(tmux show-option -gqv @backup-status-mode 2>/dev/null)
        echo "${mode:-global}"
    else
        echo "global"
    fi
}

# ==============================================================================
# GET STATUS
# ==============================================================================

STATUS_MODE=$(get_status_mode)

if [[ "$STATUS_MODE" == "project" ]]; then
    # Per-project mode (backward compatible)
    case "$FORMAT" in
        emoji|icon-only)
            integration_get_status_emoji 2>/dev/null || echo "❌"
            ;;
        compact)
            status=$(integration_get_status_compact 2>/dev/null)
            if [[ $? -eq 0 && -n "$status" ]]; then
                emoji="${status%% *}"
                time=$(integration_time_since_backup 2>/dev/null | sed 's/ ago//')
                echo "$emoji $time"
            else
                echo "❌ n/a"
            fi
            ;;
        verbose)
            integration_get_status_compact 2>/dev/null || echo "❌ Status unavailable"
            ;;
        time)
            integration_time_since_backup 2>/dev/null | sed 's/ ago//' || echo "n/a"
            ;;
        *)
            integration_get_status_emoji 2>/dev/null || echo "❌"
            ;;
    esac
else
    # Global mode (default - new behavior)
    case "$FORMAT" in
        emoji|icon-only)
            get_global_emoji
            ;;
        compact)
            get_global_compact
            ;;
        verbose)
            # In status bar, verbose still needs to be compact
            get_global_compact
            ;;
        time)
            # Not applicable for global - show compact instead
            get_global_compact
            ;;
        *)
            get_global_emoji
            ;;
    esac
fi
