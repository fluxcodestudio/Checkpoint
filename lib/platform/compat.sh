#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cross-Platform Compatibility Helpers
# ==============================================================================
# Portable wrappers for stat(1) and desktop notifications.
# Dispatches to the correct flags based on `uname -s` (Darwin vs Linux/other).
#
# Standalone module — no dependency on backup-lib.sh.
# Also auto-loaded by backup-lib.sh so every bin/ script gets these for free.
#
# Bash 3.2 compatible: NO associative arrays, NO [[ ]], NO ${var,,},
# NO |&, NO coproc
# ==============================================================================

# Include guard (set -u safe)
[ -n "${_COMPAT_LOADED:-}" ] && return || readonly _COMPAT_LOADED=1

# Cache uname result to avoid repeated subprocess calls
_COMPAT_OS="$(uname -s)"

# ==============================================================================
# get_file_size
# ==============================================================================
# Returns file size in bytes.
#
# Args:
#   $1 - path to file
#
# Output (stdout): integer byte count, or 0 on error
# ==============================================================================

get_file_size() {
    local file="$1"

    case "$_COMPAT_OS" in
        Darwin)
            stat -f%z "$file" 2>/dev/null || echo 0
            ;;
        *)
            stat -c%s "$file" 2>/dev/null || echo 0
            ;;
    esac
}

# ==============================================================================
# get_file_mtime
# ==============================================================================
# Returns file modification time as epoch seconds.
#
# Args:
#   $1 - path to file
#
# Output (stdout): integer epoch seconds, or 0 on error
# ==============================================================================

get_file_mtime() {
    local file="$1"

    case "$_COMPAT_OS" in
        Darwin)
            stat -f%m "$file" 2>/dev/null || echo 0
            ;;
        *)
            stat -c%Y "$file" 2>/dev/null || echo 0
            ;;
    esac
}

# ==============================================================================
# get_file_owner_uid
# ==============================================================================
# Returns the UID of the file owner.
#
# Args:
#   $1 - path to file
#
# Output (stdout): integer UID, or -1 on error
# ==============================================================================

get_file_owner_uid() {
    local file="$1"

    case "$_COMPAT_OS" in
        Darwin)
            stat -f "%u" "$file" 2>/dev/null || echo -1
            ;;
        *)
            stat -c "%u" "$file" 2>/dev/null || echo -1
            ;;
    esac
}

# ==============================================================================
# send_notification
# ==============================================================================
# Cross-platform desktop notification.
#
# Args:
#   $1 - notification title
#   $2 - notification message
#
# Darwin:  osascript (Notification Center)
# Linux:   notify-send (freedesktop.org)
# Other:   silent (no notification system available)
# ==============================================================================

send_notification() {
    local title="$1"
    local message="$2"

    case "$_COMPAT_OS" in
        Darwin)
            osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
            ;;
        Linux)
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "$title" "$message" 2>/dev/null || true
            fi
            ;;
        *)
            # No notification system available — silent fallback
            :
            ;;
    esac
}
