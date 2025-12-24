#!/bin/bash
# Checkpoint - Status Formatter Library
# Consistent status output formatting for all integrations
# Version: 1.2.0

# Prevent multiple sourcing
[[ -n "${BACKUP_STATUS_FORMATTER_LOADED:-}" ]] && return 0
readonly BACKUP_STATUS_FORMATTER_LOADED=1

# ==============================================================================
# EMOJI & SYMBOLS
# ==============================================================================

# Status emojis
readonly EMOJI_SUCCESS="✅"
readonly EMOJI_WARNING="⚠️"
readonly EMOJI_ERROR="❌"
readonly EMOJI_INFO="ℹ️"
readonly EMOJI_RUNNING="🔄"
readonly EMOJI_CLOCK="⏱️"
readonly EMOJI_BACKUP="💾"
readonly EMOJI_RESTORE="♻️"
readonly EMOJI_CLEANUP="🧹"
readonly EMOJI_CONFIG="⚙️"

# Symbols (for no-emoji mode)
readonly SYMBOL_SUCCESS="[OK]"
readonly SYMBOL_WARNING="[WARN]"
readonly SYMBOL_ERROR="[ERROR]"
readonly SYMBOL_INFO="[INFO]"
readonly SYMBOL_RUNNING="[...]"

# ==============================================================================
# COLOR DEFINITIONS
# ==============================================================================

# Check if colors should be disabled
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ] || [ "${BACKUP_NO_COLOR:-false}" == "true" ]; then
    # No colors
    COLOR_RESET=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_CYAN=""
    COLOR_MAGENTA=""
    COLOR_BOLD=""
    COLOR_DIM=""
else
    # Colors enabled
    COLOR_RESET='\033[0m'
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_CYAN='\033[0;36m'
    COLOR_MAGENTA='\033[0;35m'
    COLOR_BOLD='\033[1m'
    COLOR_DIM='\033[2m'
fi

# ==============================================================================
# STATUS LEVEL FORMATTING
# ==============================================================================

# Get emoji for status level
format_status_emoji() {
    local level="$1"
    local use_symbols="${BACKUP_USE_SYMBOLS:-false}"

    if [[ "$use_symbols" == "true" ]]; then
        case "$level" in
            success|ok) echo "$SYMBOL_SUCCESS" ;;
            warning|warn) echo "$SYMBOL_WARNING" ;;
            error|fail) echo "$SYMBOL_ERROR" ;;
            info) echo "$SYMBOL_INFO" ;;
            running|progress) echo "$SYMBOL_RUNNING" ;;
            *) echo "$level" ;;
        esac
    else
        case "$level" in
            success|ok) echo "$EMOJI_SUCCESS" ;;
            warning|warn) echo "$EMOJI_WARNING" ;;
            error|fail) echo "$EMOJI_ERROR" ;;
            info) echo "$EMOJI_INFO" ;;
            running|progress) echo "$EMOJI_RUNNING" ;;
            backup) echo "$EMOJI_BACKUP" ;;
            restore) echo "$EMOJI_RESTORE" ;;
            cleanup) echo "$EMOJI_CLEANUP" ;;
            config) echo "$EMOJI_CONFIG" ;;
            *) echo "$level" ;;
        esac
    fi
}

# Get color for status level
format_status_color() {
    local level="$1"

    case "$level" in
        success|ok) echo "$COLOR_GREEN" ;;
        warning|warn) echo "$COLOR_YELLOW" ;;
        error|fail) echo "$COLOR_RED" ;;
        info) echo "$COLOR_BLUE" ;;
        running|progress) echo "$COLOR_CYAN" ;;
        *) echo "$COLOR_RESET" ;;
    esac
}

# ==============================================================================
# FORMATTED OUTPUT FUNCTIONS
# ==============================================================================

# Print formatted status line
# Usage: format_status LEVEL MESSAGE
format_status() {
    local level="$1"
    shift
    local message="$@"

    local emoji=$(format_status_emoji "$level")
    local color=$(format_status_color "$level")

    echo -e "${color}${emoji} ${message}${COLOR_RESET}"
}

# Print success message
format_success() {
    format_status "success" "$@"
}

# Print warning message
format_warning() {
    format_status "warning" "$@"
}

# Print error message
format_error() {
    format_status "error" "$@"
}

# Print info message
format_info() {
    format_status "info" "$@"
}

# Print running/progress message
format_running() {
    format_status "running" "$@"
}

# ==============================================================================
# TIME FORMATTING
# ==============================================================================

# Format seconds to human-readable time
# Usage: format_duration SECONDS
format_duration() {
    local seconds="$1"

    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ $seconds -lt 3600 ]]; then
        local minutes=$((seconds / 60))
        local secs=$((seconds % 60))
        if [[ $secs -eq 0 ]]; then
            echo "${minutes}m"
        else
            echo "${minutes}m ${secs}s"
        fi
    elif [[ $seconds -lt 86400 ]]; then
        local hours=$((seconds / 3600))
        local minutes=$(((seconds % 3600) / 60))
        if [[ $minutes -eq 0 ]]; then
            echo "${hours}h"
        else
            echo "${hours}h ${minutes}m"
        fi
    else
        local days=$((seconds / 86400))
        local hours=$(((seconds % 86400) / 3600))
        if [[ $hours -eq 0 ]]; then
            echo "${days}d"
        else
            echo "${days}d ${hours}h"
        fi
    fi
}

# Format time ago (e.g., "2h ago")
# Usage: format_time_ago SECONDS
format_time_ago() {
    local seconds="$1"
    local duration=$(format_duration "$seconds")
    echo "$duration ago"
}

# Format timestamp to human-readable date
# Usage: format_timestamp UNIX_TIMESTAMP
format_timestamp() {
    local timestamp="$1"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS date
        date -r "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null
    else
        # Linux date
        date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null
    fi
}

# ==============================================================================
# SIZE FORMATTING
# ==============================================================================

# Format bytes to human-readable size
# Usage: format_size BYTES
format_size() {
    local bytes="$1"

    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# ==============================================================================
# TABLE FORMATTING
# ==============================================================================

# Print table header
# Usage: format_table_header COLUMN1 COLUMN2 ...
format_table_header() {
    local columns=("$@")

    echo -e "${COLOR_BOLD}${columns[*]}${COLOR_RESET}"
    echo -e "${COLOR_DIM}$(printf '%*s' "${#columns[*]}" '' | tr ' ' '-')${COLOR_RESET}"
}

# Print table row
# Usage: format_table_row VALUE1 VALUE2 ...
format_table_row() {
    echo "$@"
}

# ==============================================================================
# COMPACT STATUS FORMATTING
# ==============================================================================

# Format compact status (one line)
# Usage: format_compact_status LEVEL COUNT TIME
format_compact_status() {
    local level="$1"
    local count="$2"
    local time_ago="$3"

    local emoji=$(format_status_emoji "$level")

    case "$level" in
        success|ok)
            echo "$emoji All backups current ($count projects, $time_ago)"
            ;;
        warning|warn)
            echo "$emoji Backups need attention ($count projects, $time_ago)"
            ;;
        error|fail)
            echo "$emoji Backup errors ($count projects, $time_ago)"
            ;;
        *)
            echo "$emoji Status: $level ($count projects, $time_ago)"
            ;;
    esac
}

# ==============================================================================
# PROGRESS BAR
# ==============================================================================

# Draw progress bar
# Usage: format_progress_bar CURRENT TOTAL [WIDTH]
format_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"

    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    local bar="["
    for ((i=0; i<filled; i++)); do bar+="="; done
    for ((i=0; i<empty; i++)); do bar+=" "; done
    bar+="]"

    echo -e "${COLOR_CYAN}${bar}${COLOR_RESET} ${percentage}% ($current/$total)"
}

# ==============================================================================
# SPINNER
# ==============================================================================

# Spinner frames
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
SPINNER_INDEX=0

# Show next spinner frame
# Usage: format_spinner MESSAGE
format_spinner() {
    local message="${1:-Processing}"

    local frame="${SPINNER_FRAMES[$SPINNER_INDEX]}"
    SPINNER_INDEX=$(((SPINNER_INDEX + 1) % ${#SPINNER_FRAMES[@]}))

    echo -ne "\r${COLOR_CYAN}${frame}${COLOR_RESET} ${message}..."
}

# Clear spinner line
format_spinner_clear() {
    echo -ne "\r\033[K"  # Clear line
}

# ==============================================================================
# BOX FORMATTING
# ==============================================================================

# Print box around text
# Usage: format_box TITLE [LINE1] [LINE2] ...
format_box() {
    local title="$1"
    shift
    local lines=("$@")

    local max_length=${#title}
    for line in "${lines[@]}"; do
        [[ ${#line} -gt $max_length ]] && max_length=${#line}
    done

    local width=$((max_length + 4))
    local border=$(printf '═%.0s' $(seq 1 $width))

    echo -e "${COLOR_BLUE}╔${border}╗${COLOR_RESET}"
    echo -e "${COLOR_BLUE}║${COLOR_RESET} ${COLOR_BOLD}${title}${COLOR_RESET} $(printf ' %.0s' $(seq 1 $((width - ${#title} - 2))))${COLOR_BLUE}║${COLOR_RESET}"

    if [[ ${#lines[@]} -gt 0 ]]; then
        echo -e "${COLOR_BLUE}╠${border}╣${COLOR_RESET}"
        for line in "${lines[@]}"; do
            printf "${COLOR_BLUE}║${COLOR_RESET} %-${max_length}s ${COLOR_BLUE}║${COLOR_RESET}\n" "$line"
        done
    fi

    echo -e "${COLOR_BLUE}╚${border}╝${COLOR_RESET}"
}

# ==============================================================================
# EXPORT FUNCTIONS
# ==============================================================================

export -f format_status_emoji
export -f format_status_color
export -f format_status
export -f format_success
export -f format_warning
export -f format_error
export -f format_info
export -f format_running
export -f format_duration
export -f format_time_ago
export -f format_timestamp
export -f format_size
export -f format_table_header
export -f format_table_row
export -f format_compact_status
export -f format_progress_bar
export -f format_spinner
export -f format_spinner_clear
export -f format_box

# ==============================================================================
# LIBRARY LOADED
# ==============================================================================

# Silent load
: # No output by default
