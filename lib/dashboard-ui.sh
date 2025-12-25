#!/bin/bash
# ==============================================================================
# Checkpoint - Dashboard UI Library
# ==============================================================================
# Provides UI components for TUI dashboard using dialog/whiptail
# ==============================================================================

# Detect available dialog tool
if command -v dialog &>/dev/null; then
    DIALOG_CMD="dialog"
elif command -v whiptail &>/dev/null; then
    DIALOG_CMD="whiptail"
else
    DIALOG_CMD=""
fi

# Dialog settings
DIALOG_HEIGHT=20
DIALOG_WIDTH=70
DIALOG_MENU_HEIGHT=12

# Colors and symbols
SYMBOL_CHECK="✓"
SYMBOL_ACTIVE="⚡"
SYMBOL_CLOUD="☁"
SYMBOL_HEALTHY="📊"
SYMBOL_WARNING="⚠"
SYMBOL_ERROR="✗"
SYMBOL_INFO="ℹ"
SYMBOL_UPDATE="🔄"

# ==============================================================================
# CORE DIALOG FUNCTIONS
# ==============================================================================

# Check if dialog is available
has_dialog() {
    [[ -n "$DIALOG_CMD" ]]
}

# Show message box
# Usage: show_msgbox "Title" "Message"
show_msgbox() {
    local title="$1"
    local message="$2"

    if has_dialog; then
        $DIALOG_CMD --title "$title" --msgbox "$message" $DIALOG_HEIGHT $DIALOG_WIDTH
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " $title"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "$message"
        echo ""
        read -p "Press Enter to continue..."
    fi
}

# Show yes/no dialog
# Usage: show_yesno "Title" "Question"
# Returns: 0 for yes, 1 for no
show_yesno() {
    local title="$1"
    local question="$2"

    if has_dialog; then
        $DIALOG_CMD --title "$title" --yesno "$question" $DIALOG_HEIGHT $DIALOG_WIDTH
        return $?
    else
        echo "$question"
        read -p "(y/N): " answer
        [[ "$answer" =~ ^[Yy]$ ]]
        return $?
    fi
}

# Show menu
# Usage: show_menu "Title" "Description" "tag1" "item1" "tag2" "item2" ...
# Returns: Selected tag via stdout
show_menu() {
    local title="$1"
    local desc="$2"
    shift 2

    if has_dialog; then
        local result
        result=$($DIALOG_CMD --title "$title" \
                            --menu "$desc" \
                            $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                            "$@" \
                            2>&1 >/dev/tty)
        echo "$result"
        return $?
    else
        # Fallback to simple menu
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " $title"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "$desc"
        echo ""

        local i=1
        while [[ $# -gt 0 ]]; do
            local tag="$1"
            local item="$2"
            echo "  $i. $item"
            shift 2
            ((i++))
        done

        echo ""
        read -p "Choose option (or 0 to cancel): " choice

        # Map number to tag
        i=1
        while [[ $# -gt 0 ]]; do
            if [[ "$choice" == "$i" ]]; then
                echo "$1"
                return 0
            fi
            shift 2
            ((i++))
        done

        return 1
    fi
}

# Show input box
# Usage: show_inputbox "Title" "Label" "Default"
# Returns: User input via stdout
show_inputbox() {
    local title="$1"
    local label="$2"
    local default="$3"

    if has_dialog; then
        local result
        result=$($DIALOG_CMD --title "$title" \
                            --inputbox "$label" \
                            $DIALOG_HEIGHT $DIALOG_WIDTH \
                            "$default" \
                            2>&1 >/dev/tty)
        echo "$result"
        return $?
    else
        echo "$label"
        read -p "[${default}]: " input
        echo "${input:-$default}"
        return 0
    fi
}

# Show progress gauge
# Usage: echo "50" | show_gauge "Title" "Message"
show_gauge() {
    local title="$1"
    local message="$2"

    if has_dialog; then
        $DIALOG_CMD --title "$title" --gauge "$message" 10 $DIALOG_WIDTH 0
    else
        while read -r percent; do
            echo -ne "\r$message... ${percent}%"
        done
        echo ""
    fi
}

# Show info box (non-blocking)
# Usage: show_infobox "Title" "Message"
show_infobox() {
    local title="$1"
    local message="$2"

    if has_dialog; then
        $DIALOG_CMD --title "$title" --infobox "$message" 10 $DIALOG_WIDTH
    else
        echo "$message"
    fi
}

# ==============================================================================
# CUSTOM DASHBOARD COMPONENTS
# ==============================================================================

# Build status header
# Returns: Formatted status string
build_status_header() {
    local project_name="${PROJECT_NAME:-Unknown}"
    local config_status="${1:-Not Configured}"
    local last_backup="${2:-Never}"
    local next_backup="${3:-Unknown}"
    local storage="${4:-Unknown}"
    local status="${5:-Unknown}"

    cat << EOF
Project: $project_name                    $config_status
Last Backup: $last_backup                 $status
Next Backup: $next_backup
Storage Used: $storage
EOF
}

# Build update notification banner
# Returns: Formatted notification string
build_update_banner() {
    local current_version="$1"
    local latest_version="$2"

    cat << EOF

╔══════════════════════════════════════════════════════════════╗
║  $SYMBOL_UPDATE UPDATE AVAILABLE: v$current_version → v$latest_version                      ║
║                                                              ║
║  A new version is available! Select "Updates & Maintenance" ║
║  from the main menu to install.                             ║
╚══════════════════════════════════════════════════════════════╝
EOF
}

# Format menu item with icon
# Usage: format_menu_item "icon" "label" "description"
format_menu_item() {
    local icon="$1"
    local label="$2"
    local desc="$3"

    printf "%s %s\n%s" "$icon" "$label" "$desc"
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Clear screen (terminal only)
clear_screen() {
    if ! has_dialog; then
        clear
    fi
}

# Wait for keypress
wait_keypress() {
    if ! has_dialog; then
        read -p "Press Enter to continue..." -r
    fi
}

# Show error and wait
# Usage: show_error "Error message"
show_error() {
    local message="$1"
    show_msgbox "Error" "$SYMBOL_ERROR $message"
}

# Show success and wait
# Usage: show_success "Success message"
show_success() {
    local message="$1"
    show_msgbox "Success" "$SYMBOL_CHECK $message"
}

# Show warning and wait
# Usage: show_warning "Warning message"
show_warning() {
    local message="$1"
    show_msgbox "Warning" "$SYMBOL_WARNING $message"
}

# Confirm action
# Usage: confirm_action "Action description"
# Returns: 0 if confirmed, 1 if cancelled
confirm_action() {
    local action="$1"
    show_yesno "Confirm" "Are you sure you want to $action?"
    return $?
}
