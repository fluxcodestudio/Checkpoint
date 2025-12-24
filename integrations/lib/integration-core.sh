#!/bin/bash
# Checkpoint - Integration Core Library
# Shared utilities for all integrations
# Version: 1.2.0

# Prevent multiple sourcing
[[ -n "${BACKUP_INTEGRATION_CORE_LOADED:-}" ]] && return 0
readonly BACKUP_INTEGRATION_CORE_LOADED=1

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Default configuration (can be overridden)
: "${BACKUP_BIN_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../bin" && pwd)}"
: "${BACKUP_INTEGRATION_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${BACKUP_DEBOUNCE_INTERVAL:=300}"  # 5 minutes default
: "${BACKUP_QUIET_MODE:=false}"
: "${BACKUP_AUTO_TRIGGER:=true}"

# State directory for tracking
BACKUP_STATE_DIR="${HOME}/.claudecode-backups/integrations"
mkdir -p "$BACKUP_STATE_DIR"

# Debounce tracking file
BACKUP_LAST_TRIGGER_FILE="$BACKUP_STATE_DIR/.last-trigger"

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Check if backup bin directory exists and is accessible
integration_check_bin_dir() {
    if [[ ! -d "$BACKUP_BIN_DIR" ]]; then
        echo "Error: Backup bin directory not found: $BACKUP_BIN_DIR" >&2
        return 1
    fi

    if [[ ! -x "$BACKUP_BIN_DIR/backup-status.sh" ]]; then
        echo "Error: backup-status.sh not found or not executable" >&2
        return 1
    fi

    return 0
}

# Get current timestamp
integration_timestamp() {
    date +%s
}

# Get time since last trigger in seconds
integration_time_since_trigger() {
    if [[ -f "$BACKUP_LAST_TRIGGER_FILE" ]]; then
        local last_trigger=$(cat "$BACKUP_LAST_TRIGGER_FILE")
        local now=$(integration_timestamp)
        echo $((now - last_trigger))
    else
        echo 999999  # Very large number to force trigger on first run
    fi
}

# Update last trigger timestamp
integration_update_trigger_time() {
    integration_timestamp > "$BACKUP_LAST_TRIGGER_FILE"
}

# ==============================================================================
# DEBOUNCE MECHANISM
# ==============================================================================

# Check if enough time has passed since last trigger
# Returns 0 if should trigger, 1 if should skip
integration_should_trigger() {
    local interval="${1:-$BACKUP_DEBOUNCE_INTERVAL}"
    local elapsed=$(integration_time_since_trigger)

    if [[ $elapsed -gt $interval ]]; then
        return 0  # Should trigger
    else
        return 1  # Should skip (too soon)
    fi
}

# Generic debounce wrapper
# Usage: integration_debounce INTERVAL COMMAND [ARGS...]
integration_debounce() {
    local interval="$1"
    shift

    if integration_should_trigger "$interval"; then
        integration_update_trigger_time
        "$@"
        return $?
    else
        return 2  # Skipped due to debounce
    fi
}

# ==============================================================================
# BACKUP OPERATIONS
# ==============================================================================

# Trigger backup (respects debounce)
# Usage: integration_trigger_backup [--force] [--quiet] [OPTIONS...]
integration_trigger_backup() {
    local force=false
    local quiet="${BACKUP_QUIET_MODE}"
    local args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                args+=("--force")
                shift
                ;;
            --quiet|-q)
                quiet=true
                args+=("--quiet")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Check if bin directory exists
    integration_check_bin_dir || return 1

    # Force mode bypasses debounce
    if [[ "$force" == "true" ]]; then
        integration_update_trigger_time
        "$BACKUP_BIN_DIR/backup-now.sh" "${args[@]}"
        return $?
    fi

    # Check debounce
    if ! integration_should_trigger; then
        [[ "$quiet" == "false" ]] && echo "⏭️  Backup skipped (triggered recently)" >&2
        return 2  # Skipped
    fi

    # Trigger backup
    integration_update_trigger_time
    "$BACKUP_BIN_DIR/backup-now.sh" "${args[@]}"
    return $?
}

# ==============================================================================
# STATUS OPERATIONS
# ==============================================================================

# Get backup status
# Usage: integration_get_status [--compact|--json|--timeline]
integration_get_status() {
    integration_check_bin_dir || return 1
    "$BACKUP_BIN_DIR/backup-status.sh" "$@"
}

# Get compact status (one line)
integration_get_status_compact() {
    integration_check_bin_dir || return 1
    "$BACKUP_BIN_DIR/backup-status.sh" --compact 2>/dev/null
}

# Get just the status emoji (✅/⚠️/❌)
integration_get_status_emoji() {
    local status=$(integration_get_status_compact)
    if [[ $? -eq 0 && -n "$status" ]]; then
        # Extract first emoji
        echo "${status%% *}"
    else
        echo "❌"
    fi
}

# Get status exit code
# 0 = healthy, 1 = warnings, 2 = errors
integration_get_status_code() {
    integration_check_bin_dir || return 1
    "$BACKUP_BIN_DIR/backup-status.sh" --compact >/dev/null 2>&1
    return $?
}

# ==============================================================================
# LOCK CHECKING
# ==============================================================================

# Check if a backup is currently running
# Returns 0 if running, 1 if not running
integration_check_lock() {
    # Lock files are in ~/.claudecode-backups/locks/
    local lock_dir="${HOME}/.claudecode-backups/locks"

    if [[ -d "$lock_dir" ]]; then
        # Check for any lock directories
        local lock_count=$(find "$lock_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        if [[ $lock_count -gt 0 ]]; then
            return 0  # Backup is running
        fi
    fi

    return 1  # No backup running
}

# Wait for backup to complete (with timeout)
# Usage: integration_wait_for_backup [TIMEOUT_SECONDS]
integration_wait_for_backup() {
    local timeout="${1:-60}"
    local waited=0

    while integration_check_lock; do
        if [[ $waited -ge $timeout ]]; then
            echo "⏱️  Timeout waiting for backup to complete" >&2
            return 1
        fi
        sleep 1
        ((waited++))
    done

    return 0
}

# ==============================================================================
# NOTIFICATION HELPERS
# ==============================================================================

# Simple notification (delegates to notification.sh if available)
integration_notify() {
    local level="$1"
    shift
    local message="$@"

    # Try to use notification.sh if available
    local notify_script="$BACKUP_INTEGRATION_DIR/lib/notification.sh"
    if [[ -f "$notify_script" ]]; then
        source "$notify_script"
        case "$level" in
            success) notify_success "$message" ;;
            error) notify_error "$message" ;;
            info) notify_info "$message" ;;
            *) echo "$message" ;;
        esac
    else
        # Fallback to echo
        echo "$message"
    fi
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Initialize integration
# Call this at the start of each integration script
integration_init() {
    # Verify backup system is accessible
    if ! integration_check_bin_dir; then
        echo "❌ Error: Backup system not found or not accessible" >&2
        echo "   Expected location: $BACKUP_BIN_DIR" >&2
        return 1
    fi

    # Create state directory if needed
    mkdir -p "$BACKUP_STATE_DIR"

    return 0
}

# ==============================================================================
# HELPER FUNCTIONS FOR INTEGRATIONS
# ==============================================================================

# Format time ago (e.g., "2h ago", "5m ago")
integration_format_time_ago() {
    local seconds="$1"

    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s ago"
    elif [[ $seconds -lt 3600 ]]; then
        echo "$((seconds / 60))m ago"
    elif [[ $seconds -lt 86400 ]]; then
        echo "$((seconds / 3600))h ago"
    else
        echo "$((seconds / 86400))d ago"
    fi
}

# Get time since last backup
integration_time_since_backup() {
    local elapsed=$(integration_time_since_trigger)
    integration_format_time_ago "$elapsed"
}

# Check if integration is enabled
# Usage: integration_is_enabled INTEGRATION_NAME
integration_is_enabled() {
    local integration_name="$1"
    local config_file="$HOME/.backup-integrations.conf"

    # If no config file, assume enabled
    [[ ! -f "$config_file" ]] && return 0

    # Check if integration is explicitly disabled
    if grep -q "^${integration_name}_enabled=false" "$config_file" 2>/dev/null; then
        return 1
    fi

    return 0
}

# ==============================================================================
# EXPORT FUNCTIONS
# ==============================================================================

# Make functions available to other scripts
export -f integration_check_bin_dir
export -f integration_timestamp
export -f integration_time_since_trigger
export -f integration_update_trigger_time
export -f integration_should_trigger
export -f integration_debounce
export -f integration_trigger_backup
export -f integration_get_status
export -f integration_get_status_compact
export -f integration_get_status_emoji
export -f integration_get_status_code
export -f integration_check_lock
export -f integration_wait_for_backup
export -f integration_notify
export -f integration_init
export -f integration_format_time_ago
export -f integration_time_since_backup
export -f integration_is_enabled

# ==============================================================================
# LIBRARY LOADED
# ==============================================================================

# Success message (can be suppressed by integration scripts)
if [[ "${BACKUP_INTEGRATION_QUIET_LOAD:-false}" != "true" ]]; then
    : # Silent by default, integrations can enable if needed
fi
