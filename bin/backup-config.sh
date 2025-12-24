#!/bin/bash
# Checkpoint - Configuration Manager
# Interactive and command-line configuration tool
#
# Usage:
#   backup-config                          # Interactive TUI mode
#   backup-config get <key>                # Get configuration value
#   backup-config get --all                # List all settings
#   backup-config set <key> <value>        # Set configuration value
#   backup-config wizard                   # Guided setup wizard
#   backup-config validate [--strict]      # Validate configuration
#   backup-config template <type>          # Load template (minimal/standard/paranoid)
#   backup-config profile save <name>      # Save current config as profile
#   backup-config profile load <name>      # Load profile
#   backup-config profile list             # List available profiles

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIBBACKUP_PATH="$PROJECT_ROOT/lib/backup-lib.sh"

# Load backup library
if [[ -f "$LIBBACKUP_PATH" ]]; then
    source "$LIBBACKUP_PATH"
else
    echo "Error: Cannot find backup library at: $LIBBACKUP_PATH" >&2
    exit 1
fi

# ==============================================================================
# HELP TEXT
# ==============================================================================

show_help() {
    cat << 'EOF'
backup-config - Configuration Manager for Checkpoint

USAGE:
    backup-config [COMMAND] [OPTIONS]

COMMANDS:
    (none)                    Launch interactive TUI configuration editor
    get <key>                 Get configuration value
    get --all                 List all configuration values
    set <key> <value>         Set configuration value
    wizard                    Launch guided setup wizard
    validate [--strict]       Validate configuration file
    template <type>           Load configuration template
    profile save <name>       Save current config as profile
    profile load <name>       Load saved profile
    profile list              List all saved profiles
    help                      Show this help message

CONFIGURATION KEYS:
    Project:
      project.name                    - Project name for backup filenames
      project.dir                     - Project directory (usually auto-detected)

    Locations:
      locations.backup_dir            - Main backup directory
      locations.database_dir          - Database backups subdirectory
      locations.files_dir             - Current files subdirectory
      locations.archived_dir          - Archived files subdirectory

    Database:
      database.path                   - Database file path
      database.type                   - Database type (sqlite or none)

    Retention:
      retention.database.time_based   - Database retention in days
      retention.database.never_delete - Never auto-delete database backups
      retention.files.time_based      - File retention in days
      retention.files.never_delete    - Never auto-delete archived files

    Schedule:
      schedule.interval               - Backup interval in seconds
      schedule.daemon_enabled         - Enable daemon mode
      schedule.session_idle_threshold - Session idle threshold in seconds

    Drive:
      drive.verification_enabled      - Enable drive verification
      drive.marker_file               - Drive marker file path

    Features:
      features.auto_commit            - Auto-commit to git after backup
      features.git_commit_message     - Git commit message template

    Backup Targets:
      backup_targets.env_files        - Backup .env files
      backup_targets.credentials      - Backup credentials
      backup_targets.ide_settings     - Backup IDE settings
      backup_targets.local_notes      - Backup local notes
      backup_targets.local_databases  - Backup local databases

TEMPLATES:
    minimal    - Minimal config (no database, short retention)
    standard   - Standard config (recommended defaults)
    paranoid   - Paranoid config (aggressive backups, long retention)

EXAMPLES:
    # Launch interactive editor
    backup-config

    # Get a specific value
    backup-config get retention.database.time_based

    # Set database retention to 60 days
    backup-config set retention.database.time_based 60

    # Enable drive verification
    backup-config set drive.verification_enabled true

    # Run guided setup wizard
    backup-config wizard

    # Validate configuration
    backup-config validate

    # Load paranoid template
    backup-config template paranoid

    # Save current config as a profile
    backup-config profile save my-laptop

    # Load saved profile
    backup-config profile load my-laptop

    # List all profiles
    backup-config profile list

EOF
}

# ==============================================================================
# MODE: GET
# ==============================================================================

mode_get() {
    local key="${1:-}"

    if [[ "$key" == "--all" ]]; then
        config_get_all_values
        return 0
    fi

    if [[ -z "$key" ]]; then
        color_red "Error: Key required"
        echo "Usage: backup-config get <key>" >&2
        echo "       backup-config get --all" >&2
        return 1
    fi

    local value
    value="$(config_get_value "$key")"

    if [[ $? -eq 0 ]]; then
        echo "$value"
    else
        return 1
    fi
}

# ==============================================================================
# MODE: SET
# ==============================================================================

mode_set() {
    local key="${1:-}"
    local value="${2:-}"

    if [[ -z "$key" || -z "$value" ]]; then
        color_red "Error: Key and value required"
        echo "Usage: backup-config set <key> <value>" >&2
        return 1
    fi

    # Show current value
    local old_value
    old_value="$(config_get_value "$key" 2>/dev/null || echo "(not set)")"

    echo "Setting: $key"
    echo "  Old value: $old_value"
    echo "  New value: $value"
    echo ""

    # Set the value
    if config_set_value "$key" "$value"; then
        color_green "✅ Configuration updated"

        # Show impact preview for certain keys
        case "$key" in
            retention.database.time_based|retention.files.time_based)
                echo ""
                color_yellow "Impact: Backups older than $value days will be deleted on next cleanup"
                ;;
            schedule.interval)
                local hours=$((value / 3600))
                local mins=$(((value % 3600) / 60))
                echo ""
                if [[ $hours -gt 0 ]]; then
                    color_cyan "Backups will run every ${hours}h ${mins}m"
                else
                    color_cyan "Backups will run every ${mins}m"
                fi
                ;;
            drive.verification_enabled)
                if [[ "$value" == "true" ]]; then
                    echo ""
                    color_yellow "Drive verification enabled - backups will fail if drive is not connected"
                    color_cyan "Set drive.marker_file to specify marker file path"
                fi
                ;;
        esac

        return 0
    else
        color_red "❌ Failed to update configuration"
        return 1
    fi
}

# ==============================================================================
# MODE: VALIDATE
# ==============================================================================

mode_validate() {
    local strict="${1:-false}"

    if [[ "$strict" == "--strict" ]]; then
        strict="true"
    fi

    echo "Validating configuration..."
    echo ""

    if config_validate_file "$(get_config_path)" "$strict"; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# MODE: TEMPLATE
# ==============================================================================

mode_template() {
    local template="${1:-}"

    if [[ -z "$template" ]]; then
        color_red "Error: Template type required"
        echo "Usage: backup-config template <type>" >&2
        echo "Available templates: minimal, standard, paranoid" >&2
        return 1
    fi

    if [[ "$template" != "minimal" && "$template" != "standard" && "$template" != "paranoid" ]]; then
        color_red "Error: Unknown template: $template"
        echo "Available templates: minimal, standard, paranoid" >&2
        return 1
    fi

    local config_file
    config_file="$(get_config_path)"

    # Backup existing config
    if [[ -f "$config_file" ]]; then
        local backup_file="${config_file}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$config_file" "$backup_file"
        color_cyan "Backed up existing config to: $(basename "$backup_file")"
    fi

    # Create from template
    if config_create_from_template "$config_file" "$template"; then
        color_green "✅ Loaded $template template"

        # Show template details
        echo ""
        case "$template" in
            "minimal")
                echo "Minimal Configuration:"
                echo "  - No database backups"
                echo "  - 7-day retention"
                echo "  - No drive verification"
                echo "  - Minimal file backups"
                ;;
            "standard")
                echo "Standard Configuration:"
                echo "  - SQLite database support"
                echo "  - 30-day database retention"
                echo "  - 60-day file retention"
                echo "  - Hourly backups"
                ;;
            "paranoid")
                echo "Paranoid Configuration:"
                echo "  - Aggressive backups (every 30 minutes)"
                echo "  - 180-day retention (6 months)"
                echo "  - Drive verification enabled"
                echo "  - Auto-commit to git enabled"
                ;;
        esac

        return 0
    else
        color_red "❌ Failed to load template"
        return 1
    fi
}

# ==============================================================================
# MODE: PROFILE
# ==============================================================================

mode_profile() {
    local action="${1:-}"
    local profile_name="${2:-}"

    case "$action" in
        "save")
            if [[ -z "$profile_name" ]]; then
                color_red "Error: Profile name required"
                echo "Usage: backup-config profile save <name>" >&2
                return 1
            fi
            config_profile_save "$profile_name"
            ;;

        "load")
            if [[ -z "$profile_name" ]]; then
                color_red "Error: Profile name required"
                echo "Usage: backup-config profile load <name>" >&2
                return 1
            fi
            config_profile_load "$profile_name"
            ;;

        "list")
            echo "Available profiles:"
            config_profile_list
            ;;

        *)
            color_red "Error: Unknown profile action: $action"
            echo "Usage: backup-config profile save|load|list [name]" >&2
            return 1
            ;;
    esac
}

# ==============================================================================
# MODE: WIZARD
# ==============================================================================

mode_wizard() {
    color_bold "═══════════════════════════════════════════════"
    color_bold "  Backup Configuration Wizard"
    color_bold "═══════════════════════════════════════════════"
    echo ""

    # Project name
    color_cyan "Project Configuration"
    echo ""
    local project_name
    project_name="$(prompt "Project name" "$(basename "$PROJECT_ROOT")")"

    # Database
    echo ""
    color_cyan "Database Configuration"
    echo ""
    echo "Do you have a database to backup?"
    echo "  1) Yes - SQLite database"
    echo "  2) No database"
    local db_choice
    db_choice="$(prompt "Select option [1-2]" "2")"

    local db_path=""
    local db_type="none"

    if [[ "$db_choice" == "1" ]]; then
        db_path="$(prompt "Database file path" "$HOME/.myapp/data/app.db")"
        db_type="sqlite"
    fi

    # Retention
    echo ""
    color_cyan "Retention Policies"
    echo ""
    local db_retention
    db_retention="$(prompt "Database backup retention (days)" "30")"

    local file_retention
    file_retention="$(prompt "Archived file retention (days)" "60")"

    # Backup frequency
    echo ""
    color_cyan "Backup Schedule"
    echo ""
    echo "How often should backups run?"
    echo "  1) Every 30 minutes (aggressive)"
    echo "  2) Every hour (recommended)"
    echo "  3) Every 2 hours"
    echo "  4) Every 4 hours"
    local interval_choice
    interval_choice="$(prompt "Select option [1-4]" "2")"

    local backup_interval=3600
    case "$interval_choice" in
        "1") backup_interval=1800 ;;
        "2") backup_interval=3600 ;;
        "3") backup_interval=7200 ;;
        "4") backup_interval=14400 ;;
    esac

    # Drive verification
    echo ""
    color_cyan "Drive Verification"
    echo ""
    local drive_verify
    if confirm "Enable external drive verification?"; then
        local drive_marker
        drive_marker="$(prompt "Drive marker file path" "$PROJECT_ROOT/.backup-drive-marker")"
        config_set_value "drive.verification_enabled" "true"
        config_set_value "drive.marker_file" "$drive_marker"
    else
        config_set_value "drive.verification_enabled" "false"
    fi

    # Critical files
    echo ""
    color_cyan "Critical Files to Backup"
    echo ""

    if confirm "Backup .env files?" "y"; then
        config_set_value "backup_targets.env_files" "true"
    else
        config_set_value "backup_targets.env_files" "false"
    fi

    if confirm "Backup credentials (*.pem, *.key, etc.)?" "y"; then
        config_set_value "backup_targets.credentials" "true"
    else
        config_set_value "backup_targets.credentials" "false"
    fi

    if confirm "Backup IDE settings?" "y"; then
        config_set_value "backup_targets.ide_settings" "true"
    else
        config_set_value "backup_targets.ide_settings" "false"
    fi

    # Apply core settings
    config_set_value "project.name" "$project_name"
    config_set_value "database.path" "$db_path"
    config_set_value "database.type" "$db_type"
    config_set_value "retention.database.time_based" "$db_retention"
    config_set_value "retention.files.time_based" "$file_retention"
    config_set_value "schedule.interval" "$backup_interval"

    # Summary
    echo ""
    color_bold "═══════════════════════════════════════════════"
    color_green "✅ Configuration Complete!"
    color_bold "═══════════════════════════════════════════════"
    echo ""
    echo "Summary:"
    echo "  Project: $project_name"
    echo "  Database: ${db_path:-None}"
    echo "  Retention: ${db_retention}d (DB), ${file_retention}d (files)"
    echo "  Backup Interval: $(format_duration "$backup_interval")"
    echo ""
    echo "Configuration saved to: $(get_config_path)"
    echo ""

    if confirm "Validate configuration now?" "y"; then
        echo ""
        mode_validate
    fi
}

# ==============================================================================
# MODE: INTERACTIVE (TUI)
# ==============================================================================

mode_interactive() {
    # Check if dialog is available
    if command -v dialog &>/dev/null; then
        mode_interactive_dialog
    else
        mode_interactive_fallback
    fi
}

# Interactive mode using dialog
mode_interactive_dialog() {
    local config_file
    config_file="$(get_config_path)"

    while true; do
        # Build menu from schema
        local menu_items=()
        local i=0

        # Group by category
        for category in "Project" "Locations" "Database" "Retention" "Schedule" "Drive" "Features" "Backup Targets"; do
            menu_items+=("$i" "── $category ──")
            ((i++))

            # Find keys in this category
            for key in $(echo "${!BACKUP_CONFIG_SCHEMA[@]}" | tr ' ' '\n' | grep "^${category,,}" | sort); do
                local value
                value="$(config_get_value "$key" 2>/dev/null || echo "(not set)")"

                local desc
                desc="$(config_get_schema "$key" "description")"

                menu_items+=("$key" "$desc: $value")
                ((i++))
            done
        done

        # Add actions
        menu_items+=("" "")
        menu_items+=("validate" "Validate configuration")
        menu_items+=("save" "Save changes")
        menu_items+=("quit" "Exit")

        # Show dialog
        local choice
        choice=$(dialog --clear --title "Backup Configuration" \
            --menu "Select option to edit:" 30 80 20 \
            "${menu_items[@]}" \
            2>&1 >/dev/tty)

        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            break
        fi

        # Handle selection
        case "$choice" in
            "validate")
                mode_validate
                read -p "Press Enter to continue..."
                ;;

            "save")
                dialog --msgbox "Configuration saved to:\n$(get_config_path)" 8 50
                ;;

            "quit")
                break
                ;;

            [0-9]*)
                # Category header, ignore
                ;;

            *)
                # Edit a key
                local current_value
                current_value="$(config_get_value "$choice" 2>/dev/null || echo "")"

                local new_value
                new_value=$(dialog --clear --title "Edit: $choice" \
                    --inputbox "Current value: $current_value" 10 60 "$current_value" \
                    2>&1 >/dev/tty)

                if [[ $? -eq 0 && -n "$new_value" ]]; then
                    if config_set_value "$choice" "$new_value"; then
                        dialog --msgbox "✅ Updated: $choice = $new_value" 8 50
                    else
                        dialog --msgbox "❌ Failed to update $choice" 8 50
                    fi
                fi
                ;;
        esac
    done

    clear
}

# Interactive mode fallback (without dialog)
mode_interactive_fallback() {
    color_bold "═══════════════════════════════════════════════"
    color_bold "  Interactive Configuration Editor"
    color_bold "═══════════════════════════════════════════════"
    echo ""
    color_yellow "Note: Install 'dialog' for a better TUI experience"
    echo ""

    while true; do
        echo ""
        echo "Options:"
        echo "  1) View current configuration"
        echo "  2) Edit a setting"
        echo "  3) Validate configuration"
        echo "  4) Load template"
        echo "  5) Exit"
        echo ""

        local choice
        choice="$(prompt "Select option [1-5]" "5")"

        case "$choice" in
            "1")
                echo ""
                color_cyan "Current Configuration:"
                echo ""
                config_get_all_values | while IFS='=' read -r key value; do
                    echo "  $key = $value"
                done
                ;;

            "2")
                echo ""
                local key
                key="$(prompt "Configuration key")"

                if [[ -z "$key" ]]; then
                    continue
                fi

                local current_value
                current_value="$(config_get_value "$key" 2>/dev/null || echo "(not set)")"

                echo "Current value: $current_value"

                local new_value
                new_value="$(prompt "New value")"

                if [[ -n "$new_value" ]]; then
                    mode_set "$key" "$new_value"
                fi
                ;;

            "3")
                echo ""
                mode_validate
                ;;

            "4")
                echo ""
                echo "Available templates:"
                echo "  1) minimal"
                echo "  2) standard"
                echo "  3) paranoid"

                local template_choice
                template_choice="$(prompt "Select template [1-3]" "2")"

                case "$template_choice" in
                    "1") mode_template "minimal" ;;
                    "2") mode_template "standard" ;;
                    "3") mode_template "paranoid" ;;
                esac
                ;;

            "5")
                break
                ;;
        esac
    done

    echo ""
    color_green "Configuration saved"
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    local command="${1:-}"

    case "$command" in
        "help"|"--help"|"-h")
            show_help
            ;;

        "get")
            shift
            mode_get "$@"
            ;;

        "set")
            shift
            mode_set "$@"
            ;;

        "validate")
            shift
            mode_validate "$@"
            ;;

        "template")
            shift
            mode_template "$@"
            ;;

        "profile")
            shift
            mode_profile "$@"
            ;;

        "wizard")
            mode_wizard
            ;;

        "")
            # Interactive mode
            mode_interactive
            ;;

        *)
            color_red "Error: Unknown command: $command"
            echo ""
            echo "Run 'backup-config help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
