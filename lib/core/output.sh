#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Output (Color, JSON, Logging)
# ==============================================================================
# @requires: core/config (for check_drive used by backup_log)
# @provides: COLOR_* constants, color_echo, color_red, color_green,
#            color_yellow, color_blue, color_cyan, color_gray, color_bold,
#            json_escape, json_kv, json_kv_num, json_kv_bool, backup_log
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_OUTPUT:-}" ] && return || readonly _CHECKPOINT_OUTPUT=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ==============================================================================
# COLOR OUTPUT
# ==============================================================================

# ANSI color codes (check for NO_COLOR/piped output first)
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
    # Disable colors for piped output or when NO_COLOR is set
    readonly COLOR_RESET=''
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    readonly COLOR_BLUE=''
    readonly COLOR_CYAN=''
    readonly COLOR_GRAY=''
    readonly COLOR_BOLD=''
else
    readonly COLOR_RESET='\033[0m'
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_CYAN='\033[0;36m'
    readonly COLOR_GRAY='\033[0;90m'
    readonly COLOR_BOLD='\033[1m'
fi

# Color output functions
color_echo() {
    local color="$1"
    shift
    echo -e "${color}$@${COLOR_RESET}"
}

color_red() { color_echo "$COLOR_RED" "$@"; }
color_green() { color_echo "$COLOR_GREEN" "$@"; }
color_yellow() { color_echo "$COLOR_YELLOW" "$@"; }
color_blue() { color_echo "$COLOR_BLUE" "$@"; }
color_cyan() { color_echo "$COLOR_CYAN" "$@"; }
color_gray() { color_echo "$COLOR_GRAY" "$@"; }
color_bold() { color_echo "$COLOR_BOLD" "$@"; }

# ==============================================================================
# JSON OUTPUT
# ==============================================================================

# Escape string for JSON
json_escape() {
    local str="$1"
    # Escape backslashes, quotes, newlines, tabs
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g'
}

# JSON key-value pair
json_kv() {
    local key="$1"
    local value="$2"
    echo "\"$key\": \"$(json_escape "$value")\""
}

# JSON number key-value pair
json_kv_num() {
    local key="$1"
    local value="$2"
    echo "\"$key\": $value"
}

# JSON boolean key-value pair
json_kv_bool() {
    local key="$1"
    local value="$2"
    echo "\"$key\": $value"
}

# ==============================================================================
# LOGGING
# ==============================================================================

# Log message to file and stdout
# Args: $1 = message, $2 = level (optional: INFO, WARN, ERROR)
backup_log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local log_entry="$timestamp [$level] $message"

    # Print to stdout
    echo "$log_entry"

    # Write to log file if available
    local log_file="${LOG_FILE:-}"
    if [ -n "$log_file" ] && check_drive; then
        if [ -d "$(dirname "$log_file")" ]; then
            echo "$log_entry" >> "$log_file" 2>/dev/null || true
        fi
    fi

    # Write to fallback log
    local fallback_log="${FALLBACK_LOG:-}"
    if [ -n "$fallback_log" ]; then
        mkdir -p "$(dirname "$fallback_log")" 2>/dev/null || true
        echo "$log_entry" >> "$fallback_log" 2>/dev/null || true
    fi
}
