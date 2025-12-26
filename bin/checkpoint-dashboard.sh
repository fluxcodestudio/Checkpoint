#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Interactive TUI Dashboard
# ==============================================================================
# Full-featured control panel for managing Checkpoint
# Usage: checkpoint-dashboard
# ==============================================================================

# Require Bash 4+ for associative arrays
if ((BASH_VERSINFO[0] < 4)); then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  Checkpoint Dashboard requires Bash 4.0 or newer"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Your bash: $BASH_VERSION (too old)"
    echo ""

    # Try to find newer bash
    if [[ -x "/opt/homebrew/bin/bash" ]]; then
        echo "Found Homebrew Bash 5+ at /opt/homebrew/bin/bash"
        echo "Relaunching with newer bash..."
        echo ""
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif [[ -x "/usr/local/bin/bash" ]]; then
        echo "Found newer bash at /usr/local/bin/bash"
        echo "Relaunching with newer bash..."
        echo ""
        exec /usr/local/bin/bash "$0" "$@"
    else
        echo "Install Homebrew Bash 5+:"
        echo "  brew install bash"
        echo ""
        echo "Falling back to simple menu mode..."
        echo ""

        # Call simple menu fallback
        if [[ -x "$HOME/.local/bin/checkpoint" ]]; then
            exec "$HOME/.local/bin/checkpoint" --status
        fi
        exit 1
    fi
fi

set -euo pipefail

# Find Checkpoint installation
if command -v backup-status &>/dev/null; then
    CHECKPOINT_LIB="/usr/local/lib/checkpoint"
    [[ ! -d "$CHECKPOINT_LIB" ]] && CHECKPOINT_LIB="$HOME/.local/lib/checkpoint"
else
    CHECKPOINT_LIB="$(cd "$(dirname "$0")/.." && pwd)"
fi

# Load libraries
source "$CHECKPOINT_LIB/lib/dashboard-ui.sh"
source "$CHECKPOINT_LIB/lib/dashboard-status.sh"

# Global config
GLOBAL_CONFIG_DIR="$HOME/.config/checkpoint"
GLOBAL_CONFIG_FILE="$GLOBAL_CONFIG_DIR/config.sh"

# Status cache
declare -A STATUS_CACHE

# ==============================================================================
# STATUS MANAGEMENT
# ==============================================================================

# Refresh status cache
refresh_status() {
    # Load project config if exists
    if [[ -f "$PWD/.backup-config.sh" ]]; then
        source "$PWD/.backup-config.sh" 2>/dev/null
    fi

    # Load global config
    if [[ -f "$GLOBAL_CONFIG_FILE" ]]; then
        source "$GLOBAL_CONFIG_FILE" 2>/dev/null
    fi

    # Collect all status data
    while IFS='=' read -r key value; do
        STATUS_CACHE["$key"]="$value"
    done < <(get_all_status)
}

# Get status value
get_status() {
    local key="$1"
    echo "${STATUS_CACHE[$key]:-Unknown}"
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

show_main_menu() {
    while true; do
        refresh_status

        local project_name=$(get_status "PROJECT_NAME")
        local config_status=$(get_status "CONFIG_STATUS")
        local is_configured=false
        [[ "$config_status" == "✓ Configured" ]] && is_configured=true

        # Build description with status header
        local desc="
Project: $project_name          $config_status
Last Backup: $(get_status "LAST_BACKUP")          $(get_status "BACKUP_STATUS")
Next Backup: $(get_status "NEXT_BACKUP")          $(get_status "CLOUD_STATUS")
Storage: $(get_status "STORAGE")

What would you like to do?"

        # Add update notification if available
        if [[ "$(get_status "HAS_UPDATE")" == "true" ]]; then
            desc="
$SYMBOL_UPDATE UPDATE AVAILABLE: v$(get_status "CURRENT_VERSION") → v$(get_status "LATEST_VERSION")
New version ready to install!
$desc"
        fi

        # Build menu options
        local options=()
        options+=("1" "⚡ Quick Actions - Backup, restore, pause/resume")
        options+=("2" "⚙  Settings - Global & project configuration")
        options+=("3" "📦 Backup Management - History, cleanup, restore points")

        if $is_configured; then
            options+=("4" "☁  Cloud Sync - Configure & manage cloud backups")
        fi

        options+=("5" "🔧 All Commands - Complete command reference")
        options+=("6" "🔄 Updates & Maintenance - Check updates, system health")
        options+=("0" "Exit")

        # Show menu
        local choice
        choice=$(show_menu "Checkpoint v$(get_status "CURRENT_VERSION") - Control Panel" "$desc" "${options[@]}")
        local result=$?

        # Handle cancellation
        if [[ $result -ne 0 || "$choice" == "0" ]]; then
            clear_screen
            echo "Goodbye!"
            exit 0
        fi

        # Handle selection
        case "$choice" in
            1) show_quick_actions_menu ;;
            2) show_settings_menu ;;
            3) show_backup_management_menu ;;
            4) $is_configured && show_cloud_sync_menu ;;
            5) show_all_commands_menu ;;
            6) show_updates_menu ;;
        esac
    done
}

# ==============================================================================
# QUICK ACTIONS MENU
# ==============================================================================

show_quick_actions_menu() {
    while true; do
        local options=()
        options+=("1" "⚡ Backup Now - Run immediate backup")
        options+=("2" "🔄 Restore Files - Browse and restore from backups")
        options+=("3" "📊 View Status - Detailed backup health")
        options+=("4" "⏸  Pause/Resume - Temporarily pause automatic backups")
        options+=("5" "🧹 Quick Cleanup - Free up space")
        options+=("0" "← Back to Main Menu")

        local choice
        choice=$(show_menu "Quick Actions" "Select an action:" "${options[@]}")
        local result=$?

        if [[ $result -ne 0 || "$choice" == "0" ]]; then
            return
        fi

        case "$choice" in
            1) action_backup_now ;;
            2) action_restore_files ;;
            3) action_view_status ;;
            4) action_pause_resume ;;
            5) action_quick_cleanup ;;
        esac
    done
}

# Action: Backup Now
action_backup_now() {
    if ! confirm_action "run backup now"; then
        return
    fi

    show_infobox "Backup" "Running backup..."

    # Run backup command
    if command -v backup-now &>/dev/null; then
        backup-now
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-now.sh" ]]; then
        "$CHECKPOINT_LIB/bin/backup-now.sh"
    fi

    show_success "Backup completed successfully!"
}

# Action: Restore Files
action_restore_files() {
    if command -v backup-restore &>/dev/null; then
        backup-restore
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-restore.sh" ]]; then
        "$CHECKPOINT_LIB/bin/backup-restore.sh"
    fi
    wait_keypress
}

# Action: View Status
action_view_status() {
    if command -v backup-status &>/dev/null; then
        clear_screen
        backup-status
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-status.sh" ]]; then
        clear_screen
        "$CHECKPOINT_LIB/bin/backup-status.sh"
    fi
    wait_keypress
}

# Action: Pause/Resume
action_pause_resume() {
    local pause_file="$HOME/.checkpoint-paused"

    if [[ -f "$pause_file" ]]; then
        # Currently paused, resume
        if confirm_action "resume automatic backups"; then
            if command -v backup-pause &>/dev/null; then
                backup-pause --resume
            elif [[ -x "$CHECKPOINT_LIB/bin/backup-pause.sh" ]]; then
                "$CHECKPOINT_LIB/bin/backup-pause.sh" --resume
            fi
            show_success "Automatic backups resumed!"
        fi
    else
        # Currently active, pause
        if confirm_action "pause automatic backups"; then
            if command -v backup-pause &>/dev/null; then
                backup-pause
            elif [[ -x "$CHECKPOINT_LIB/bin/backup-pause.sh" ]]; then
                "$CHECKPOINT_LIB/bin/backup-pause.sh"
            fi
            show_success "Automatic backups paused!"
        fi
    fi
}

# Action: Quick Cleanup
action_quick_cleanup() {
    if ! confirm_action "clean up old backups"; then
        return
    fi

    show_infobox "Cleanup" "Analyzing backups..."

    if command -v backup-cleanup &>/dev/null; then
        backup-cleanup --execute
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-cleanup.sh" ]]; then
        "$CHECKPOINT_LIB/bin/backup-cleanup.sh" --execute
    fi

    show_success "Cleanup completed!"
}

# ==============================================================================
# SETTINGS MENU
# ==============================================================================

show_settings_menu() {
    while true; do
        local options=()
        options+=("1" "🌍 Edit Global Settings - Defaults for all projects")
        options+=("2" "🔗 Integrations - Claude Code, Git hooks, Shell")
        options+=("3" "🔔 Notifications - Desktop alerts, failure notifications")
        options+=("" "")
        options+=("4" "📁 Configure This Project - Setup current project")
        options+=("5" "✏  Edit Project Config - Override global defaults")
        options+=("6" "🗑  Reset to Defaults - Remove project overrides")
        options+=("0" "← Back to Main Menu")

        local choice
        choice=$(show_menu "Settings" "Manage global and project settings:" "${options[@]}")
        local result=$?

        if [[ $result -ne 0 || "$choice" == "0" ]]; then
            return
        fi

        case "$choice" in
            1) action_edit_global_settings ;;
            2) action_manage_integrations ;;
            3) action_manage_notifications ;;
            4) action_configure_project ;;
            5) action_edit_project_config ;;
            6) action_reset_to_defaults ;;
        esac
    done
}

# Action: Edit Global Settings
action_edit_global_settings() {
    if [[ ! -f "$GLOBAL_CONFIG_FILE" ]]; then
        # Initialize global config
        mkdir -p "$GLOBAL_CONFIG_DIR"
        if [[ -f "$CHECKPOINT_LIB/templates/global-config-template.sh" ]]; then
            cp "$CHECKPOINT_LIB/templates/global-config-template.sh" "$GLOBAL_CONFIG_FILE"
        fi
    fi

    # Open in editor
    ${EDITOR:-nano} "$GLOBAL_CONFIG_FILE"

    show_success "Global settings updated!"
}

# Action: Manage Integrations
action_manage_integrations() {
    show_msgbox "Integrations" "Integration management coming soon!\n\nThis will allow you to enable/disable:\n- Claude Code hooks\n- Git pre-commit hooks\n- Shell prompt integration\n- Tmux status bar"
}

# Action: Manage Notifications
action_manage_notifications() {
    show_msgbox "Notifications" "Notification settings coming soon!\n\nThis will configure:\n- Desktop notifications (macOS)\n- Email alerts\n- Failure-only mode\n- Quiet hours"
}

# Action: Configure Project
action_configure_project() {
    if command -v configure-project &>/dev/null; then
        clear_screen
        configure-project "$PWD"
    elif [[ -x "$CHECKPOINT_LIB/bin/configure-project.sh" ]]; then
        clear_screen
        "$CHECKPOINT_LIB/bin/configure-project.sh" "$PWD"
    fi
    wait_keypress
}

# Action: Edit Project Config
action_edit_project_config() {
    if [[ ! -f "$PWD/.backup-config.sh" ]]; then
        show_error "Project not configured. Use 'Configure This Project' first."
        return
    fi

    ${EDITOR:-nano} "$PWD/.backup-config.sh"
    show_success "Project settings updated!"
}

# Action: Reset to Defaults
action_reset_to_defaults() {
    if [[ ! -f "$PWD/.backup-config.sh" ]]; then
        show_error "Project not configured."
        return
    fi

    if ! confirm_action "reset this project to global defaults (this cannot be undone)"; then
        return
    fi

    rm -f "$PWD/.backup-config.sh"
    show_success "Project reset to defaults. Re-configure to set up again."
}

# ==============================================================================
# BACKUP MANAGEMENT MENU
# ==============================================================================

show_backup_management_menu() {
    while true; do
        local options=()
        options+=("1" "📜 View Backup History - List all backups")
        options+=("2" "🔍 Browse Restore Points - Interactive file browser")
        options+=("3" "🧹 Cleanup Old Backups - Manage retention")
        options+=("4" "✓  Verify Backups - Check integrity")
        options+=("0" "← Back to Main Menu")

        local choice
        choice=$(show_menu "Backup Management" "Manage your backups:" "${options[@]}")
        local result=$?

        if [[ $result -ne 0 || "$choice" == "0" ]]; then
            return
        fi

        case "$choice" in
            1) action_view_history ;;
            2) action_browse_restore_points ;;
            3) action_cleanup_backups ;;
            4) action_verify_backups ;;
        esac
    done
}

# Action: View History
action_view_history() {
    local backup_dir="${BACKUP_DIR:-$PWD/backups}"

    if [[ ! -d "$backup_dir" ]]; then
        show_error "No backup directory found."
        return
    fi

    clear_screen
    echo "Backup History"
    echo "=============="
    echo ""

    echo "Databases:"
    if [[ -d "$backup_dir/databases" ]]; then
        ls -lh "$backup_dir/databases" 2>/dev/null | tail -n +2
    else
        echo "  No database backups"
    fi

    echo ""
    echo "Archived Files:"
    if [[ -d "$backup_dir/archived" ]]; then
        ls -lh "$backup_dir/archived" 2>/dev/null | tail -n +2 | head -20
    else
        echo "  No archived files"
    fi

    wait_keypress
}

# Action: Browse Restore Points
action_browse_restore_points() {
    action_restore_files
}

# Action: Cleanup Backups
action_cleanup_backups() {
    action_quick_cleanup
}

# Action: Verify Backups
action_verify_backups() {
    show_msgbox "Verify Backups" "Backup verification coming soon!\n\nThis will:\n- Check file integrity\n- Verify database dumps\n- Test cloud sync status\n- Report any issues"
}

# ==============================================================================
# CLOUD SYNC MENU
# ==============================================================================

show_cloud_sync_menu() {
    while true; do
        local options=()
        options+=("1" "⚙  Configure Provider - Setup cloud storage")
        options+=("2" "⬆  Sync Now - Upload backups immediately")
        options+=("3" "📊 Sync Status - View upload history")
        options+=("4" "🔌 Test Connection - Verify provider access")
        options+=("0" "← Back to Main Menu")

        local choice
        choice=$(show_menu "Cloud Sync" "Manage cloud backups:" "${options[@]}")
        local result=$?

        if [[ $result -ne 0 || "$choice" == "0" ]]; then
            return
        fi

        case "$choice" in
            1) action_configure_cloud ;;
            2) action_sync_now ;;
            3) action_sync_status ;;
            4) action_test_connection ;;
        esac
    done
}

# Action: Configure Cloud
action_configure_cloud() {
    if command -v backup-cloud-config &>/dev/null; then
        clear_screen
        backup-cloud-config
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-cloud-config.sh" ]]; then
        clear_screen
        "$CHECKPOINT_LIB/bin/backup-cloud-config.sh"
    fi
    wait_keypress
}

# Action: Sync Now
action_sync_now() {
    show_msgbox "Sync Now" "Cloud sync coming soon!\n\nThis will upload:\n- Latest database backups\n- Critical files\n- Changed files (if enabled)"
}

# Action: Sync Status
action_sync_status() {
    show_msgbox "Sync Status" "Last sync: $(get_status "LAST_BACKUP")\nStatus: $(get_status "CLOUD_STATUS")"
}

# Action: Test Connection
action_test_connection() {
    show_msgbox "Test Connection" "Connection test coming soon!"
}

# ==============================================================================
# ALL COMMANDS MENU
# ==============================================================================

show_all_commands_menu() {
    while true; do
        local options=()
        options+=("1" "backup-now          - Run backup immediately")
        options+=("2" "backup-status       - View backup health")
        options+=("3" "backup-restore      - Restore from backups")
        options+=("4" "backup-cleanup      - Clean old backups")
        options+=("5" "backup-pause        - Pause/resume backups")
        options+=("6" "backup-cloud-config - Configure cloud storage")
        options+=("7" "configure-project   - Setup new project")
        options+=("8" "backup-update       - Check for updates")
        options+=("9" "checkpoint          - Open this dashboard")
        options+=("0" "← Back to Main Menu")

        local choice
        choice=$(show_menu "All Commands" "Run any command:" "${options[@]}")
        local result=$?

        if [[ $result -ne 0 || "$choice" == "0" ]]; then
            return
        fi

        # Execute corresponding command
        case "$choice" in
            1) action_backup_now ;;
            2) action_view_status ;;
            3) action_restore_files ;;
            4) action_cleanup_backups ;;
            5) action_pause_resume ;;
            6) action_configure_cloud ;;
            7) action_configure_project ;;
            8) action_check_updates ;;
            9) return ;;
        esac
    done
}

# ==============================================================================
# UPDATES MENU
# ==============================================================================

show_updates_menu() {
    while true; do
        local has_update=$(get_status "HAS_UPDATE")
        local current_ver=$(get_status "CURRENT_VERSION")
        local latest_ver=$(get_status "LATEST_VERSION")

        local options=()

        if [[ "$has_update" == "true" ]]; then
            options+=("1" "$SYMBOL_UPDATE Install Update (v$current_ver → v$latest_ver)")
        else
            options+=("1" "✓ No updates available (v$current_ver)")
        fi

        options+=("2" "🔄 Check for Updates")
        options+=("3" "📋 View Changelog")
        options+=("4" "🏥 System Health Check")
        options+=("0" "← Back to Main Menu")

        local choice
        choice=$(show_menu "Updates & Maintenance" "Keep Checkpoint up to date:" "${options[@]}")
        local result=$?

        if [[ $result -ne 0 || "$choice" == "0" ]]; then
            return
        fi

        case "$choice" in
            1)
                if [[ "$has_update" == "true" ]]; then
                    action_install_update
                fi
                ;;
            2) action_check_updates ;;
            3) action_view_changelog ;;
            4) action_health_check ;;
        esac

        # Refresh status after actions
        refresh_status
    done
}

# Action: Install Update
action_install_update() {
    if ! confirm_action "install update v$(get_status "LATEST_VERSION")"; then
        return
    fi

    show_infobox "Update" "Installing update..."

    if command -v backup-update &>/dev/null; then
        clear_screen
        backup-update
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-update.sh" ]]; then
        clear_screen
        "$CHECKPOINT_LIB/bin/backup-update.sh"
    fi

    wait_keypress
}

# Action: Check Updates
action_check_updates() {
    show_infobox "Update" "Checking for updates..."
    sleep 1
    refresh_status

    if [[ "$(get_status "HAS_UPDATE")" == "true" ]]; then
        show_msgbox "Update Available" "Version $(get_status "LATEST_VERSION") is available!\n\nCurrent: v$(get_status "CURRENT_VERSION")\nLatest: v$(get_status "LATEST_VERSION")\n\nSelect 'Install Update' to upgrade."
    else
        show_success "You're running the latest version (v$(get_status "CURRENT_VERSION"))!"
    fi
}

# Action: View Changelog
action_view_changelog() {
    local changelog="$CHECKPOINT_LIB/CHANGELOG.md"
    if [[ -f "$changelog" ]]; then
        clear_screen
        less "$changelog"
    else
        show_msgbox "Changelog" "Changelog not found."
    fi
}

# Action: Health Check
action_health_check() {
    show_msgbox "System Health" "Overall Health: $(get_status "HEALTH")\n\nBackup Status: $(get_status "BACKUP_STATUS")\nCloud Status: $(get_status "CLOUD_STATUS")\nLast Backup: $(get_status "LAST_BACKUP")\n\nStorage: $(get_status "STORAGE")"
}

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

# Check for dialog
if ! has_dialog; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Checkpoint Dashboard"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "⚠ Warning: dialog or whiptail not found"
    echo ""
    echo "For the best experience, install dialog:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  brew install dialog"
    else
        echo "  sudo apt-get install dialog  # Debian/Ubuntu"
        echo "  sudo yum install dialog      # RedHat/CentOS"
    fi
    echo ""
    echo "Falling back to simple menu mode..."
    echo ""
    read -p "Press Enter to continue..."
fi

# Run main menu
show_main_menu
