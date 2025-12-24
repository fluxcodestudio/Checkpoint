#!/bin/bash
# Checkpoint Project Backups - Tmux Status Bar Script
# Displays backup status in tmux status line
# Version: 1.2.0

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Find integration directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load integration core
if [[ -f "$INTEGRATION_DIR/lib/integration-core.sh" ]]; then
    BACKUP_INTEGRATION_QUIET_LOAD=true
    source "$INTEGRATION_DIR/lib/integration-core.sh"
else
    echo "❌"
    exit 1
fi

# Initialize integration
integration_init &>/dev/null || {
    echo "❌"
    exit 1
}

# ==============================================================================
# FORMAT SELECTION
# ==============================================================================

# Get format from argument or environment
FORMAT="${1:-${TMUX_BACKUP_FORMAT:-emoji}}"

# ==============================================================================
# GET STATUS
# ==============================================================================

case "$FORMAT" in
    emoji)
        # Just emoji: ✅ or ⚠️ or ❌
        integration_get_status_emoji 2>/dev/null || echo "❌"
        ;;

    compact)
        # Emoji + time: ✅ 2h
        status=$(integration_get_status_compact 2>/dev/null)
        if [[ $? -eq 0 && -n "$status" ]]; then
            # Extract emoji and time
            emoji="${status%% *}"
            time=$(integration_time_since_backup 2>/dev/null | sed 's/ ago//')
            echo "$emoji $time"
        else
            echo "❌ n/a"
        fi
        ;;

    verbose)
        # Full compact status
        integration_get_status_compact 2>/dev/null || echo "❌ Status unavailable"
        ;;

    time)
        # Just time since backup
        integration_time_since_backup 2>/dev/null | sed 's/ ago//' || echo "n/a"
        ;;

    icon-only)
        # Just the emoji, no text
        integration_get_status_emoji 2>/dev/null || echo "❌"
        ;;

    *)
        # Unknown format, return emoji
        integration_get_status_emoji 2>/dev/null || echo "❌"
        ;;
esac
