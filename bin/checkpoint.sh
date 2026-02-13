#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Command Center
# ==============================================================================
# Interactive command center for managing global and per-project settings
# Usage: checkpoint [--status|--global|--project|--update]
# ==============================================================================

set -euo pipefail

# Find Checkpoint installation
if command -v backup-status &>/dev/null; then
    # Global installation
    CHECKPOINT_LIB="/usr/local/lib/checkpoint"
    [[ ! -d "$CHECKPOINT_LIB" ]] && CHECKPOINT_LIB="$HOME/.local/lib/checkpoint"
    INSTALL_MODE="Global"
else
    # Per-project installation
    CHECKPOINT_LIB="$(cd "$(dirname "$0")/.." && pwd)"
    INSTALL_MODE="Per-Project"
fi

# Cross-platform helpers (stat, notifications)
source "$CHECKPOINT_LIB/lib/platform/compat.sh"

# Global config location
GLOBAL_CONFIG_DIR="$HOME/.config/checkpoint"
GLOBAL_CONFIG_FILE="$GLOBAL_CONFIG_DIR/config.sh"

# Initialize global config if needed
init_global_config() {
    if [[ ! -f "$GLOBAL_CONFIG_FILE" ]]; then
        mkdir -p "$GLOBAL_CONFIG_DIR"
        if [[ -f "$CHECKPOINT_LIB/templates/global-config-template.sh" ]]; then
            cp "$CHECKPOINT_LIB/templates/global-config-template.sh" "$GLOBAL_CONFIG_FILE"
        fi
    fi
}

# Load global config
load_global_config() {
    init_global_config
    if [[ -f "$GLOBAL_CONFIG_FILE" ]]; then
        source "$GLOBAL_CONFIG_FILE"
    fi
}

# Load project config
# Security note: Config files are shell scripts and can execute arbitrary code.
# This is by design (like .bashrc). Only use in trusted project directories.
load_project_config() {
    local config_file="$PWD/.backup-config.sh"
    if [[ -f "$config_file" ]]; then
        # Security: Check file ownership matches current user
        local file_owner
        file_owner=$(get_file_owner_uid "$config_file")
        local current_user
        current_user=$(id -u)
        if [[ "$file_owner" != "$current_user" ]]; then
            echo "⚠️  Warning: Config file not owned by you. Skipping for security." >&2
            return 1
        fi
        source "$config_file"
        return 0
    fi
    return 1
}

# Get version
get_version() {
    if [[ -f "$CHECKPOINT_LIB/VERSION" ]]; then
        cat "$CHECKPOINT_LIB/VERSION"
    else
        echo "2.2.0"
    fi
}

# Main command center display
show_command_center() {
    clear

    local version=$(get_version)
    local project_name=$(basename "$PWD")
    local is_configured=false

    load_global_config

    if load_project_config; then
        is_configured=true
    fi

    echo "═══════════════════════════════════════════════════════════"
    echo "  Checkpoint v$version - Command Center"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Installation Mode: $INSTALL_MODE"
    echo "Current Directory: $PWD"

    if $is_configured; then
        echo "Project Status:    ✅ Configured (${PROJECT_NAME:-$project_name})"
    else
        echo "Project Status:    ⚠️  Not Configured"
    fi

    echo ""

    # Global Settings Section
    echo "━━━ GLOBAL SETTINGS (All Projects) ━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Retention Policies:"
    echo "    Database Backups:      ${DEFAULT_DB_RETENTION_DAYS:-30} days"
    echo "    Archived Files:        ${DEFAULT_FILE_RETENTION_DAYS:-60} days"
    echo ""
    echo "  Cloud Backup Defaults:"
    echo "    Enabled:               ${DEFAULT_CLOUD_ENABLED:-false}"
    echo "    Provider:              ${DEFAULT_CLOUD_PROVIDER:-Not set}"
    echo "    Sync Databases:        ${DEFAULT_CLOUD_SYNC_DATABASES:-true}"
    echo "    Sync Critical Files:   ${DEFAULT_CLOUD_SYNC_CRITICAL:-true}"
    echo ""
    echo "  Automation:"
    echo "    Hourly Backups:        ${DEFAULT_INSTALL_HOURLY_BACKUPS:-true} (macOS)"
    echo "    Backup Interval:       $((${DEFAULT_BACKUP_INTERVAL:-3600} / 60)) minutes"
    echo ""
    echo "  Integrations:"
    echo "    Claude Code:           ${CLAUDE_CODE_INTEGRATION:-true}"
    echo "    Git Hooks:             ${GIT_HOOKS_ENABLED:-false}"
    echo "    Shell Integration:     ${SHELL_INTEGRATION_ENABLED:-false}"
    echo ""

    # Project Settings Section
    if $is_configured; then
        echo "━━━ PROJECT SETTINGS (${PROJECT_NAME:-$project_name}) ━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  Configuration:"
        echo "    Project Name:          ${PROJECT_NAME:-$project_name}"
        echo "    Backup Directory:      ${BACKUP_DIR:-./backups}"
        echo "    Database Type:         ${DB_TYPE:-none}"
        echo ""
        echo "  Retention (Project Override):"
        echo "    Database Backups:      ${DB_RETENTION_DAYS:-using global (${DEFAULT_DB_RETENTION_DAYS:-30})} days"
        echo "    Archived Files:        ${FILE_RETENTION_DAYS:-using global (${DEFAULT_FILE_RETENTION_DAYS:-60})} days"
        echo ""
        echo "  Cloud Backup:"
        echo "    Enabled:               ${CLOUD_ENABLED:-${DEFAULT_CLOUD_ENABLED:-false}}"
        if [[ "${CLOUD_ENABLED:-false}" == "true" ]]; then
            echo "    Provider:              ${CLOUD_PROVIDER:-${DEFAULT_CLOUD_PROVIDER:-Not set}}"
            echo "    Remote Name:           ${CLOUD_REMOTE_NAME:-Not configured}"
            echo "    Backup Path:           ${CLOUD_BACKUP_PATH:-Not set}"
        fi
        echo ""

        # Last backup info
        if [[ -d "${BACKUP_DIR:-./backups}" ]]; then
            local last_backup=$(find "${BACKUP_DIR:-./backups}" -type f -name "*.gz" -o -name "*.sql" 2>/dev/null | head -1)
            if [[ -n "$last_backup" ]]; then
                local backup_age=$(( ($(date +%s) - $(get_file_mtime "$last_backup")) / 60 ))
                if [[ $backup_age -lt 60 ]]; then
                    echo "  Last Backup:           $backup_age minutes ago"
                elif [[ $backup_age -lt 1440 ]]; then
                    echo "  Last Backup:           $(($backup_age / 60)) hours ago"
                else
                    echo "  Last Backup:           $(($backup_age / 1440)) days ago"
                fi
            else
                echo "  Last Backup:           No backups found"
            fi
        fi
    else
        echo "━━━ PROJECT NOT CONFIGURED ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  This project doesn't have a backup configuration yet."
        echo "  Use option [2] to configure this project."
    fi

    echo ""
    echo "━━━ ACTIONS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  [1] Edit Global Settings"
    echo "  [2] Configure This Project"
    if $is_configured; then
        echo "  [3] Edit Project Settings"
        echo "  [4] View Detailed Status"
        echo "  [5] Run Backup Now"
        echo "  [6] Configure Cloud Backup"
    fi
    echo "  [7] Check for Updates"
    echo "  [8] View All Commands"
    echo ""
    echo "  [0] Exit"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Edit global settings
edit_global_settings() {
    echo "━━━ Edit Global Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Opening global configuration file..."
    echo "File: $GLOBAL_CONFIG_FILE"
    echo ""

    # Use $EDITOR or fallback to nano/vim
    # Security: validate EDITOR doesn't contain shell metacharacters
    local editor_used=false
    local unsafe_chars=';|&$`()'
    if [[ -n "${EDITOR:-}" ]]; then
        if [[ "$EDITOR" == *[';|&$`()']*  ]]; then
            echo "Warning: EDITOR contains unsafe characters, falling back to nano/vim"
        else
            # Use array to properly handle editors with arguments (e.g., "code --wait")
            read -ra editor_cmd <<< "$EDITOR"
            "${editor_cmd[@]}" "$GLOBAL_CONFIG_FILE"
            editor_used=true
        fi
    fi
    if [[ "$editor_used" == "false" ]]; then
        if command -v nano &>/dev/null; then
            nano "$GLOBAL_CONFIG_FILE"
        elif command -v vim &>/dev/null; then
            vim "$GLOBAL_CONFIG_FILE"
        else
            echo "No editor found. Please edit manually:"
            echo "  $GLOBAL_CONFIG_FILE"
        fi
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Configure current project
configure_project() {
    echo "━━━ Configure Project ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Find configure-project.sh
    if command -v configure-project &>/dev/null; then
        configure-project "$PWD"
    elif [[ -x "$CHECKPOINT_LIB/bin/configure-project.sh" ]]; then
        "$CHECKPOINT_LIB/bin/configure-project.sh" "$PWD"
    else
        echo "❌ configure-project.sh not found"
    fi

    read -p "Press Enter to continue..."
}

# Edit project settings
edit_project_settings() {
    if [[ ! -f "$PWD/.backup-config.sh" ]]; then
        echo "❌ Project not configured. Use option [2] first."
        read -p "Press Enter to continue..."
        return
    fi

    echo "━━━ Edit Project Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Opening project configuration file..."
    echo "File: $PWD/.backup-config.sh"
    echo ""

    # Use $EDITOR or fallback
    # Security: validate EDITOR doesn't contain shell metacharacters
    local editor_used=false
    if [[ -n "${EDITOR:-}" ]]; then
        if [[ "$EDITOR" == *[';|&$`()']*  ]]; then
            echo "Warning: EDITOR contains unsafe characters, falling back to nano/vim"
        else
            read -ra editor_cmd <<< "$EDITOR"
            "${editor_cmd[@]}" "$PWD/.backup-config.sh"
            editor_used=true
        fi
    fi
    if [[ "$editor_used" == "false" ]]; then
        if command -v nano &>/dev/null; then
            nano "$PWD/.backup-config.sh"
        elif command -v vim &>/dev/null; then
            vim "$PWD/.backup-config.sh"
        else
            echo "No editor found. Please edit manually:"
            echo "  $PWD/.backup-config.sh"
        fi
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# View detailed status
view_status() {
    echo "━━━ Backup Status ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if command -v backup-status &>/dev/null; then
        backup-status
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-status.sh" ]]; then
        "$CHECKPOINT_LIB/bin/backup-status.sh"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Run backup now
run_backup() {
    echo "━━━ Running Backup ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if command -v backup-now &>/dev/null; then
        backup-now
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-now.sh" ]]; then
        "$CHECKPOINT_LIB/bin/backup-now.sh"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Configure cloud backup
configure_cloud() {
    echo "━━━ Cloud Backup Configuration ━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if command -v backup-cloud-config &>/dev/null; then
        backup-cloud-config
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-cloud-config.sh" ]]; then
        "$CHECKPOINT_LIB/bin/backup-cloud-config.sh"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Check for updates
check_updates() {
    echo "━━━ Check for Updates ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if command -v backup-update &>/dev/null; then
        backup-update --check-only
    elif [[ -x "$CHECKPOINT_LIB/bin/backup-update.sh" ]]; then
        "$CHECKPOINT_LIB/bin/backup-update.sh" --check-only
    else
        echo "Update command not found"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Show all commands
show_commands() {
    echo "━━━ Available Commands ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  backup-now              Run backup immediately"
    echo "  backup-status           View backup status"
    echo "  backup-restore          Restore from backups"
    echo "  backup-cleanup          Clean old backups"
    echo "  backup-cloud-config     Configure cloud storage"
    echo "  backup-update           Update Checkpoint"
    echo "  backup-pause            Pause/resume automatic backups"
    echo "  checkpoint              This command center"
    echo ""
    echo "Claude Code skills (if installed):"
    echo "  /checkpoint             Command center"
    echo "  /backup-now             Run backup"
    echo "  /backup-status          View status"
    echo "  /backup-update          Update system"
    echo "  /backup-pause           Pause/resume"
    echo "  /uninstall              Uninstall Checkpoint"
    echo ""
    read -p "Press Enter to continue..."
}

# Main menu loop
main_menu() {
    while true; do
        show_command_center

        read -p "Choose option: " choice

        case "$choice" in
            1) edit_global_settings ;;
            2) configure_project ;;
            3)
                if load_project_config 2>/dev/null; then
                    edit_project_settings
                else
                    echo "Project not configured. Use option [2] first."
                    read -p "Press Enter to continue..."
                fi
                ;;
            4)
                if load_project_config 2>/dev/null; then
                    view_status
                else
                    echo "Project not configured."
                    read -p "Press Enter to continue..."
                fi
                ;;
            5)
                if load_project_config 2>/dev/null; then
                    run_backup
                else
                    echo "Project not configured."
                    read -p "Press Enter to continue..."
                fi
                ;;
            6)
                if load_project_config 2>/dev/null; then
                    configure_cloud
                else
                    echo "Project not configured."
                    read -p "Press Enter to continue..."
                fi
                ;;
            7) check_updates ;;
            8) show_commands ;;
            0)
                echo ""
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid option. Try again."
                sleep 1
                ;;
        esac
    done
}

# Find dashboard script
DASHBOARD_SCRIPT=""
if [[ -x "$CHECKPOINT_LIB/bin/checkpoint-dashboard.sh" ]]; then
    DASHBOARD_SCRIPT="$CHECKPOINT_LIB/bin/checkpoint-dashboard.sh"
fi

# Handle command-line arguments
case "${1:-}" in
    --status|--info)
        show_command_center
        exit 0
        ;;
    --global)
        edit_global_settings
        exit 0
        ;;
    --project)
        if load_project_config 2>/dev/null; then
            edit_project_settings
        else
            configure_project
        fi
        exit 0
        ;;
    --update)
        check_updates
        exit 0
        ;;
    --help|-h)
        echo "Checkpoint - Command Center"
        echo ""
        echo "Usage: checkpoint [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --status, --info    Show status only (no menu)"
        echo "  --global            Edit global settings"
        echo "  --project           Edit/configure project settings"
        echo "  --update            Check for updates"
        echo "  --dashboard         Launch interactive TUI dashboard"
        echo "  --help, -h          Show this help"
        echo ""
        echo "No options:           Launch interactive TUI dashboard"
        exit 0
        ;;
    --dashboard)
        # Launch TUI dashboard if available
        if [[ -n "$DASHBOARD_SCRIPT" ]]; then
            exec "$DASHBOARD_SCRIPT"
        else
            main_menu
        fi
        ;;
    "")
        # Default: Launch TUI dashboard if available, otherwise fallback to simple menu
        if [[ -n "$DASHBOARD_SCRIPT" ]]; then
            exec "$DASHBOARD_SCRIPT"
        else
            main_menu
        fi
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
