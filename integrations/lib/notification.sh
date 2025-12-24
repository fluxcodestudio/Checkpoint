#!/bin/bash
# Checkpoint Project Backups - Notification Library
# Cross-platform desktop notifications
# Version: 1.2.0

# Prevent multiple sourcing
[[ -n "${BACKUP_NOTIFICATION_LOADED:-}" ]] && return 0
readonly BACKUP_NOTIFICATION_LOADED=1

# ==============================================================================
# NOTIFICATION BACKEND DETECTION
# ==============================================================================

# Detect available notification system
detect_notification_backend() {
    # macOS
    if command -v osascript &>/dev/null && [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
        return 0
    fi

    # Linux: notify-send (most common)
    if command -v notify-send &>/dev/null; then
        echo "notify-send"
        return 0
    fi

    # Linux: kdialog (KDE)
    if command -v kdialog &>/dev/null; then
        echo "kdialog"
        return 0
    fi

    # Linux: zenity (GNOME)
    if command -v zenity &>/dev/null; then
        echo "zenity"
        return 0
    fi

    # Windows Subsystem for Linux
    if command -v powershell.exe &>/dev/null; then
        echo "wsl"
        return 0
    fi

    # Fallback: terminal bell
    echo "terminal"
    return 0
}

# Cache backend detection
NOTIFICATION_BACKEND="${NOTIFICATION_BACKEND:-$(detect_notification_backend)}"

# ==============================================================================
# NOTIFICATION FUNCTIONS BY BACKEND
# ==============================================================================

# macOS notification via osascript
notify_macos() {
    local title="$1"
    local message="$2"
    local subtitle="${3:-}"

    if [[ -n "$subtitle" ]]; then
        osascript -e "display notification \"$message\" with title \"$title\" subtitle \"$subtitle\"" 2>/dev/null
    else
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null
    fi
}

# Linux notification via notify-send
notify_notify_send() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"  # low, normal, critical
    local icon="${4:-}"

    local args=()
    args+=("-u" "$urgency")
    [[ -n "$icon" ]] && args+=("-i" "$icon")
    args+=("$title" "$message")

    notify-send "${args[@]}" 2>/dev/null
}

# KDE notification via kdialog
notify_kdialog() {
    local title="$1"
    local message="$2"

    kdialog --passivepopup "$message" 5 --title "$title" 2>/dev/null
}

# GNOME notification via zenity
notify_zenity() {
    local title="$1"
    local message="$2"
    local type="${3:-info}"  # info, warning, error

    zenity --notification --text="$title: $message" 2>/dev/null
}

# WSL notification via PowerShell
notify_wsl() {
    local title="$1"
    local message="$2"

    powershell.exe -Command "
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        \$template = @\"
        <toast>
            <visual>
                <binding template='ToastText02'>
                    <text id='1'>$title</text>
                    <text id='2'>$message</text>
                </binding>
            </visual>
        </toast>
\"@
        \$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        \$xml.LoadXml(\$template)
        \$toast = New-Object Windows.UI.Notifications.ToastNotification \$xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Checkpoint Backups').Show(\$toast)
    " 2>/dev/null
}

# Terminal fallback (bell + echo)
notify_terminal() {
    local title="$1"
    local message="$2"

    echo -e "\a"  # Bell
    echo "[$title] $message"
}

# ==============================================================================
# UNIFIED NOTIFICATION INTERFACE
# ==============================================================================

# Send notification using detected backend
# Usage: notify TITLE MESSAGE [LEVEL]
notify() {
    local title="$1"
    local message="$2"
    local level="${3:-info}"  # info, success, warning, error

    # Check if notifications are disabled
    if [[ "${BACKUP_NOTIFICATIONS_ENABLED:-true}" != "true" ]]; then
        return 0
    fi

    # Map level to urgency/icon
    local urgency="normal"
    local icon=""

    case "$level" in
        success)
            urgency="normal"
            icon="emblem-default"  # Green checkmark
            ;;
        warning)
            urgency="normal"
            icon="dialog-warning"
            ;;
        error)
            urgency="critical"
            icon="dialog-error"
            ;;
        info|*)
            urgency="low"
            icon="dialog-information"
            ;;
    esac

    # Send notification based on backend
    case "$NOTIFICATION_BACKEND" in
        macos)
            notify_macos "$title" "$message"
            ;;
        notify-send)
            notify_notify_send "$title" "$message" "$urgency" "$icon"
            ;;
        kdialog)
            notify_kdialog "$title" "$message"
            ;;
        zenity)
            notify_zenity "$title" "$message" "$level"
            ;;
        wsl)
            notify_wsl "$title" "$message"
            ;;
        terminal|*)
            notify_terminal "$title" "$message"
            ;;
    esac
}

# ==============================================================================
# CONVENIENCE WRAPPERS
# ==============================================================================

# Success notification (green checkmark)
notify_success() {
    local message="$1"
    local title="${2:-Checkpoint Backups}"
    notify "$title" "$message" "success"
}

# Error notification (red X)
notify_error() {
    local message="$1"
    local title="${2:-Checkpoint Backups}"
    notify "$title" "$message" "error"
}

# Warning notification (yellow warning)
notify_warning() {
    local message="$1"
    local title="${2:-Checkpoint Backups}"
    notify "$title" "$message" "warning"
}

# Info notification (blue i)
notify_info() {
    local message="$1"
    local title="${2:-Checkpoint Backups}"
    notify "$title" "$message" "info"
}

# ==============================================================================
# BACKUP-SPECIFIC NOTIFICATIONS
# ==============================================================================

# Backup started notification
notify_backup_started() {
    local project_name="${1:-Project}"
    notify_info "Backup started for $project_name"
}

# Backup completed notification
notify_backup_completed() {
    local project_name="${1:-Project}"
    local duration="${2:-}"

    if [[ -n "$duration" ]]; then
        notify_success "Backup completed for $project_name in $duration"
    else
        notify_success "Backup completed for $project_name"
    fi
}

# Backup failed notification
notify_backup_failed() {
    local project_name="${1:-Project}"
    local error="${2:-Unknown error}"
    notify_error "Backup failed for $project_name: $error"
}

# Backup warning notification
notify_backup_warning() {
    local project_name="${1:-Project}"
    local warning="${2:-}"
    notify_warning "Backup warning for $project_name: $warning"
}

# Multiple backups completed
notify_backups_completed() {
    local count="$1"
    local duration="${2:-}"

    if [[ -n "$duration" ]]; then
        notify_success "Completed $count backups in $duration"
    else
        notify_success "Completed $count backups"
    fi
}

# ==============================================================================
# NOTIFICATION TESTING
# ==============================================================================

# Test notification system
test_notifications() {
    echo "Testing notification backend: $NOTIFICATION_BACKEND"
    echo ""

    echo "Sending test notifications..."
    notify_info "This is an info notification"
    sleep 1
    notify_success "This is a success notification"
    sleep 1
    notify_warning "This is a warning notification"
    sleep 1
    notify_error "This is an error notification"

    echo ""
    echo "Check your system for 4 notifications"
    echo "If you didn't see them, notifications may be disabled or unsupported"
    echo ""
    echo "Detected backend: $NOTIFICATION_BACKEND"
}

# ==============================================================================
# EXPORT FUNCTIONS
# ==============================================================================

export -f notify
export -f notify_success
export -f notify_error
export -f notify_warning
export -f notify_info
export -f notify_backup_started
export -f notify_backup_completed
export -f notify_backup_failed
export -f notify_backup_warning
export -f notify_backups_completed
export -f test_notifications

# ==============================================================================
# LIBRARY LOADED
# ==============================================================================

# Silent load
: # No output by default
