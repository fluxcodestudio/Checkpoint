#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Time & Size Utilities
# Human-readable formatting for time durations, byte sizes, and date parsing
# ==============================================================================
# @requires: none
# @provides: format_time_ago, format_duration, time_until_next_backup,
#            format_bytes, get_dir_size_bytes, parse_date_string,
#            format_relative_time
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_TIME_SIZE_UTILS:-}" ] && return || readonly _CHECKPOINT_TIME_SIZE_UTILS=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ==============================================================================
# TIME UTILITIES
# ==============================================================================

# Format seconds into human-readable time ago
# Args: $1 = timestamp (Unix epoch)
# Output: "2h ago", "45m ago", "3d ago", etc.
format_time_ago() {
    local timestamp="$1"
    local now=$(date +%s)
    local diff=$((now - timestamp))

    if [ $diff -lt 0 ]; then
        echo "in the future"
    elif [ $diff -lt 60 ]; then
        echo "${diff}s ago"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60))m ago"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# Format seconds into human-readable duration
# Args: $1 = seconds
# Output: "2h 15m", "45m", "3d 4h", etc.
format_duration() {
    local seconds="$1"

    if [ $seconds -lt 60 ]; then
        echo "${seconds}s"
    elif [ $seconds -lt 3600 ]; then
        echo "$((seconds / 60))m"
    elif [ $seconds -lt 86400 ]; then
        local hours=$((seconds / 3600))
        local mins=$(((seconds % 3600) / 60))
        if [ $mins -gt 0 ]; then
            echo "${hours}h ${mins}m"
        else
            echo "${hours}h"
        fi
    else
        local days=$((seconds / 86400))
        local hours=$(((seconds % 86400) / 3600))
        if [ $hours -gt 0 ]; then
            echo "${days}d ${hours}h"
        else
            echo "${days}d"
        fi
    fi
}

# Calculate time until next scheduled backup
# Returns: Seconds until next backup (can be negative if overdue)
time_until_next_backup() {
    local backup_interval="${BACKUP_INTERVAL:-3600}"
    local last_backup=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
    local now=$(date +%s)
    local next_backup=$((last_backup + backup_interval))
    local diff=$((next_backup - now))

    echo "$diff"
}

# ==============================================================================
# SIZE UTILITIES
# ==============================================================================

# Format bytes into human-readable size
# Args: $1 = bytes
# Output: "1.2 GB", "45 MB", etc.
format_bytes() {
    local bytes="$1"

    if [ $bytes -lt 1024 ]; then
        echo "${bytes} B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}") KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}") GB"
    fi
}

# Get total size of directory in bytes
# Args: $1 = directory path
# Output: size in bytes
get_dir_size_bytes() {
    local dir="$1"

    if [ ! -d "$dir" ]; then
        echo "0"
        return
    fi

    # macOS uses -f%z, Linux uses --format=%s
    if [[ "$OSTYPE" == "darwin"* ]]; then
        find "$dir" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END {print s+0}'
    else
        find "$dir" -type f -exec stat --format=%s {} + 2>/dev/null | awk '{s+=$1} END {print s+0}'
    fi
}

# ==============================================================================
# DATE/TIME PARSING
# ==============================================================================

# Parse human-readable date strings
# Examples: "2 days ago", "yesterday", "2025-12-24 10:00"
parse_date_string() {
    local input="$1"

    case "$input" in
        "now"|"today")
            date +%s
            ;;
        "yesterday")
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -v-1d +%s
            else
                date -d "yesterday" +%s
            fi
            ;;
        *"days ago"|*"day ago")
            local days=$(echo "$input" | grep -oE '[0-9]+')
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -v-${days}d +%s
            else
                date -d "$days days ago" +%s
            fi
            ;;
        *"hours ago"|*"hour ago")
            local hours=$(echo "$input" | grep -oE '[0-9]+')
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -v-${hours}H +%s
            else
                date -d "$hours hours ago" +%s
            fi
            ;;
        *"weeks ago"|*"week ago")
            local weeks=$(echo "$input" | grep -oE '[0-9]+')
            local days=$((weeks * 7))
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -v-${days}d +%s
            else
                date -d "$days days ago" +%s
            fi
            ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*)
            # ISO format
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -j -f "%Y-%m-%d %H:%M" "$input" +%s 2>/dev/null || \
                date -j -f "%Y-%m-%d" "$input" +%s 2>/dev/null
            else
                date -d "$input" +%s
            fi
            ;;
        *)
            # Try direct parsing
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -j -f "%Y-%m-%d %H:%M:%S" "$input" +%s 2>/dev/null
            else
                date -d "$input" +%s 2>/dev/null
            fi
            ;;
    esac
}

# Format relative time (X hours ago, X days ago)
format_relative_time() {
    local timestamp="$1"
    local now=$(date +%s)
    local diff=$((now - timestamp))

    if [ $diff -lt 60 ]; then
        echo "just now"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60)) minutes ago"
    elif [ $diff -lt 7200 ]; then
        echo "1 hour ago"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600)) hours ago"
    elif [ $diff -lt 172800 ]; then
        echo "yesterday"
    elif [ $diff -lt 604800 ]; then
        echo "$((diff / 86400)) days ago"
    else
        echo "$((diff / 604800)) weeks ago"
    fi
}
