#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Interactive UI Components (Formatting)
# Box drawing, prompts, and confirmation dialogs
# ==============================================================================
# @requires: core/output (for COLOR_* constants)
# @provides: BOX_TL, BOX_TR, BOX_BL, BOX_BR, BOX_H, BOX_V,
#            draw_box, draw_border, prompt, confirm
# ==============================================================================

# Include guard
[ -n "$_CHECKPOINT_FORMATTING" ] && return || readonly _CHECKPOINT_FORMATTING=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ==============================================================================
# INTERACTIVE UI COMPONENTS
# ==============================================================================

# Box drawing characters
BOX_TL='╭'
BOX_TR='╮'
BOX_BL='╰'
BOX_BR='╯'
BOX_H='─'
BOX_V='│'

# Draw box with title and content
draw_box() {
    local title="$1"
    local content="$2"
    local width="${3:-60}"

    # Calculate padding for centered title
    local title_len=${#title}
    local padding=$(( (width - title_len - 4) / 2 ))

    # Top border with title
    echo -n "$BOX_TL"
    printf "%${padding}s" | tr ' ' "$BOX_H"
    echo -n " $title "
    printf "%$((width - padding - title_len - 4))s" | tr ' ' "$BOX_H"
    echo "$BOX_TR"

    # Content lines
    if [ -n "$content" ]; then
        echo "$content" | while IFS= read -r line; do
            printf "%s %-$((width - 2))s %s\n" "$BOX_V" "$line" "$BOX_V"
        done
    else
        printf "%s %$((width - 2))s %s\n" "$BOX_V" "" "$BOX_V"
    fi

    # Bottom border
    echo -n "$BOX_BL"
    printf "%${width}s" | tr ' ' "$BOX_H"
    echo "$BOX_BR"
}

# Draw simple box border
draw_border() {
    local width="${1:-60}"
    echo -n "$BOX_TL"
    printf "%${width}s" | tr ' ' "$BOX_H"
    echo "$BOX_TR"
}

# Prompt for user input with default
prompt() {
    local message="$1"
    local default="$2"
    local result=""

    if [ -n "$default" ]; then
        read -p "$message [$default]: " result
        echo "${result:-$default}"
    else
        read -p "$message: " result
        echo "$result"
    fi
}

# Yes/No confirmation
confirm() {
    local message="$1"
    local default="${2:-n}"
    local result=""

    if [ "$default" = "y" ]; then
        read -p "$message [Y/n]: " result
        result="${result:-y}"
    else
        read -p "$message [y/N]: " result
        result="${result:-n}"
    fi

    [ "$result" = "y" ] || [ "$result" = "Y" ]
}
