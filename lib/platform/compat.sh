#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cross-Platform Compatibility Helpers
# ==============================================================================
# Portable wrappers for stat(1), date(1), case conversion, and notifications.
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

# ==============================================================================
# date_to_epoch
# ==============================================================================
# Portable date-to-epoch conversion. Parses a date string using a given format
# and outputs epoch seconds.
#
# Args:
#   $1 - format string (strftime, e.g. "%Y%m%d%H%M%S")
#   $2 - date string to parse
#
# Output (stdout): integer epoch seconds, or empty on error
# ==============================================================================

date_to_epoch() {
    local fmt="$1"
    local datestr="$2"

    case "$_COMPAT_OS" in
        Darwin)
            date -j -f "$fmt" "$datestr" +%s 2>/dev/null
            ;;
        *)
            # Linux/GNU date: convert strftime format to date -d friendly string
            # Common case: pure numeric YYYYMMDDHHMMSS
            if [ "$fmt" = "%Y%m%d%H%M%S" ] && [ ${#datestr} -eq 14 ]; then
                local _y="${datestr:0:4}"
                local _m="${datestr:4:2}"
                local _d="${datestr:6:2}"
                local _H="${datestr:8:2}"
                local _M="${datestr:10:2}"
                local _S="${datestr:12:2}"
                date -d "${_y}-${_m}-${_d} ${_H}:${_M}:${_S}" +%s 2>/dev/null
            elif [ "$fmt" = "%Y-%m-%d" ]; then
                date -d "$datestr" +%s 2>/dev/null
            elif [ "$fmt" = "%Y%m%d" ] && [ ${#datestr} -eq 8 ]; then
                local _y="${datestr:0:4}"
                local _m="${datestr:4:2}"
                local _d="${datestr:6:2}"
                date -d "${_y}-${_m}-${_d}" +%s 2>/dev/null
            else
                # Generic fallback: try GNU date -d directly
                date -d "$datestr" +%s 2>/dev/null
            fi
            ;;
    esac
}

# ==============================================================================
# epoch_to_date
# ==============================================================================
# Portable epoch-to-formatted-date conversion.
#
# Args:
#   $1 - epoch seconds
#   $2 - output format (strftime, e.g. "%Y-%m-%d")
#
# Output (stdout): formatted date string
# ==============================================================================

epoch_to_date() {
    local epoch="$1"
    local fmt="$2"

    case "$_COMPAT_OS" in
        Darwin)
            date -r "$epoch" +"$fmt" 2>/dev/null
            ;;
        *)
            date -d "@$epoch" +"$fmt" 2>/dev/null
            ;;
    esac
}

# ==============================================================================
# date_format_iso_week
# ==============================================================================
# Portable ISO week formatting from a YYYYMMDD string.
#
# Args:
#   $1 - date string in YYYYMMDD format
#
# Output (stdout): ISO week string (YYYY-WXX)
# ==============================================================================

date_format_iso_week() {
    local datestr="$1"

    case "$_COMPAT_OS" in
        Darwin)
            date -j -f "%Y%m%d" "$datestr" "+%G-W%V" 2>/dev/null
            ;;
        *)
            local _y="${datestr:0:4}"
            local _m="${datestr:4:2}"
            local _d="${datestr:6:2}"
            date -d "${_y}-${_m}-${_d}" "+%G-W%V" 2>/dev/null
            ;;
    esac
}

# ==============================================================================
# to_upper / to_lower
# ==============================================================================
# Portable case conversion (bash 3.2 compatible — no ${var^^} or ${var,,}).
#
# Args:
#   $1 - string to convert
#
# Output (stdout): converted string
# ==============================================================================

to_upper() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

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
