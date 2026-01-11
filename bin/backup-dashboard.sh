#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - All-Projects Dashboard
# ==============================================================================
# Interactive dashboard showing backup status across all registered projects
# ==============================================================================

set -euo pipefail

# Find library directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Source dependencies
source "$LIB_DIR/projects-registry.sh"
source "$LIB_DIR/global-status.sh"
source "$LIB_DIR/dashboard-ui.sh"
source "$LIB_DIR/retention-policy.sh"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Get storage usage for a project
get_project_storage() {
    local project_path="$1"
    local config_file="$project_path/.backup-config.sh"
    local backup_dir

    backup_dir=$(
        source "$config_file" 2>/dev/null
        echo "${BACKUP_DIR:-$project_path/backups}"
    )

    if [[ ! -d "$backup_dir" ]]; then
        echo "0B"
        return
    fi

    du -sh "$backup_dir" 2>/dev/null | awk '{print $1}' || echo "?"
}

# Format last backup for display (more detailed)
get_project_last_backup_detail() {
    local project_path="$1"
    local age=$(get_project_backup_age "$project_path")

    if [[ "$age" == "-1" ]]; then
        echo "Never"
        return
    fi

    # Get actual timestamp
    local config_file="$project_path/.backup-config.sh"
    local backup_dir
    backup_dir=$(
        source "$config_file" 2>/dev/null
        echo "${BACKUP_DIR:-$project_path/backups}"
    )

    local last_file
    last_file=$(find "$backup_dir" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" \) -print0 2>/dev/null |
                xargs -0 ls -t 2>/dev/null | head -1)

    if [[ -n "$last_file" ]]; then
        local timestamp
        if [[ "$OSTYPE" == "darwin"* ]]; then
            timestamp=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$last_file" 2>/dev/null)
        else
            timestamp=$(stat -c "%y" "$last_file" 2>/dev/null | cut -d'.' -f1)
        fi
        echo "$(format_age "$age") ($timestamp)"
    else
        echo "$(format_age "$age")"
    fi
}

# Get retention tier counts for a project
get_project_retention_summary() {
    local project_path="$1"
    local config_file="$project_path/.backup-config.sh"
    local backup_dir

    backup_dir=$(
        source "$config_file" 2>/dev/null
        echo "${BACKUP_DIR:-$project_path/backups}"
    )

    if [[ ! -d "$backup_dir" ]]; then
        echo "No snapshots"
        return
    fi

    local stats=$(get_retention_stats "$backup_dir")
    local hourly=$(echo "$stats" | grep -o 'hourly:[0-9]*' | cut -d: -f2)
    local daily=$(echo "$stats" | grep -o 'daily:[0-9]*' | cut -d: -f2)
    local weekly=$(echo "$stats" | grep -o 'weekly:[0-9]*' | cut -d: -f2)
    local monthly=$(echo "$stats" | grep -o 'monthly:[0-9]*' | cut -d: -f2)

    echo "${hourly:-0} hourly, ${daily:-0} daily, ${weekly:-0} weekly, ${monthly:-0} monthly"
}

# ==============================================================================
# DISPLAY FUNCTIONS
# ==============================================================================

# Display all projects table
display_projects_table() {
    local verbose="${1:-false}"

    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo "  Checkpoint - All Projects Dashboard"
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo ""

    # Table header
    printf "  %-24s %-10s %-18s %s\n" "Project" "Status" "Last Backup" "Storage"
    echo "  ─────────────────────────────────────────────────────────────────────────"

    local total_projects=0
    local healthy_count=0
    local warning_count=0
    local error_count=0
    local total_storage=0

    while IFS= read -r project_path; do
        [[ -z "$project_path" ]] && continue
        [[ ! -d "$project_path" ]] && continue

        ((total_projects++))

        local name=$(basename "$project_path")
        local health=$(get_project_health "$project_path")
        local age=$(get_project_backup_age "$project_path")
        local age_str=$(format_age "$age")
        local storage=$(get_project_storage "$project_path")

        # Count by health
        case "$health" in
            healthy) ((healthy_count++)) ;;
            warning) ((warning_count++)) ;;
            error) ((error_count++)) ;;
        esac

        # Health status and emoji
        local status_emoji status_text
        case "$health" in
            healthy) status_emoji="✅"; status_text="OK" ;;
            warning) status_emoji="⚠️ "; status_text="STALE" ;;
            error) status_emoji="❌"; status_text="ERROR" ;;
        esac

        # Truncate project name if too long
        if [[ ${#name} -gt 22 ]]; then
            name="${name:0:20}.."
        fi

        printf "  %-24s %s %-6s %-18s %s\n" "$name" "$status_emoji" "$status_text" "$age_str" "$storage"

        # Show retention summary in verbose mode
        if [[ "$verbose" == "true" ]]; then
            local retention=$(get_project_retention_summary "$project_path")
            printf "    └─ Retention: %s\n" "$retention"
        fi

    done < <(list_projects)

    echo "  ─────────────────────────────────────────────────────────────────────────"

    # Summary line
    local needs_backup=$((warning_count + error_count))
    if [[ $needs_backup -gt 0 ]]; then
        printf "  Total: %d projects" "$total_projects"
        if [[ $needs_backup -gt 0 ]]; then
            printf "                                        %d need backup\n" "$needs_backup"
        else
            echo ""
        fi
    else
        printf "  Total: %d projects                                        All healthy ✅\n" "$total_projects"
    fi

    echo ""
}

# Display action menu (non-interactive)
display_action_menu() {
    echo "Actions:"
    echo "  [1] Backup all projects now"
    echo "  [2] Select project for details"
    echo "  [3] Cleanup old backups (preview)"
    echo "  [q] Quit"
    echo ""
}

# Interactive menu mode
run_interactive() {
    local verbose="${1:-false}"

    while true; do
        clear_screen
        display_projects_table "$verbose"

        if has_dialog; then
            # Dialog-based menu
            local choice
            choice=$(show_menu "Checkpoint Dashboard" "Select an action:" \
                "1" "Backup all projects now" \
                "2" "Select project for details" \
                "3" "Cleanup old backups (preview)" \
                "q" "Quit")

            case "$choice" in
                1) backup_all_projects ;;
                2) select_project_interactive ;;
                3) cleanup_preview_all ;;
                q|"") break ;;
            esac
        else
            # Fallback text menu
            display_action_menu
            read -p "Choose option: " choice

            case "$choice" in
                1) backup_all_projects ;;
                2) select_project_text ;;
                3) cleanup_preview_all ;;
                q|Q) break ;;
                *) echo "Invalid option" ;;
            esac
        fi
    done
}

# Select project (interactive with dialog)
select_project_interactive() {
    local menu_args=()
    local idx=1

    while IFS= read -r project_path; do
        [[ -z "$project_path" ]] && continue
        [[ ! -d "$project_path" ]] && continue

        local name=$(basename "$project_path")
        local health=$(get_project_health "$project_path")
        local emoji
        case "$health" in
            healthy) emoji="✅" ;;
            warning) emoji="⚠️" ;;
            error) emoji="❌" ;;
        esac

        menu_args+=("$project_path" "$emoji $name")
        ((idx++))
    done < <(list_projects)

    if [[ ${#menu_args[@]} -eq 0 ]]; then
        show_msgbox "No Projects" "No projects registered. Use checkpoint init in a project directory."
        return
    fi

    local selected
    selected=$(show_menu "Select Project" "Choose a project to view details:" "${menu_args[@]}")

    if [[ -n "$selected" ]]; then
        display_project_detail "$selected"
        wait_keypress
    fi
}

# Select project (text fallback)
select_project_text() {
    echo ""
    echo "Registered projects:"

    local projects=()
    local idx=1

    while IFS= read -r project_path; do
        [[ -z "$project_path" ]] && continue
        [[ ! -d "$project_path" ]] && continue

        projects+=("$project_path")
        local name=$(basename "$project_path")
        echo "  [$idx] $name"
        ((idx++))
    done < <(list_projects)

    if [[ ${#projects[@]} -eq 0 ]]; then
        echo "No projects registered."
        return
    fi

    echo ""
    read -p "Select project number (or q to cancel): " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#projects[@]} ]]; then
        local selected="${projects[$((choice-1))]}"
        display_project_detail "$selected"
        echo ""
        read -p "Press Enter to continue..."
    fi
}

# Backup all projects
backup_all_projects() {
    echo ""
    echo "Backing up all projects..."
    echo ""

    local success=0
    local failed=0

    while IFS= read -r project_path; do
        [[ -z "$project_path" ]] && continue
        [[ ! -d "$project_path" ]] && continue

        local name=$(basename "$project_path")
        printf "  Backing up %-30s " "$name..."

        if [[ -x "$SCRIPT_DIR/backup-now.sh" ]]; then
            if (cd "$project_path" && "$SCRIPT_DIR/backup-now.sh" >/dev/null 2>&1); then
                echo "✅"
                ((success++))
            else
                echo "❌"
                ((failed++))
            fi
        else
            echo "⚠️  backup-now.sh not found"
            ((failed++))
        fi
    done < <(list_projects)

    echo ""
    echo "Complete: $success succeeded, $failed failed"
    echo ""
    read -p "Press Enter to continue..."
}

# Cleanup preview for all projects
cleanup_preview_all() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo "  Cleanup Preview - All Projects"
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo ""

    local total_savings=0

    while IFS= read -r project_path; do
        [[ -z "$project_path" ]] && continue
        [[ ! -d "$project_path" ]] && continue

        local name=$(basename "$project_path")
        local config_file="$project_path/.backup-config.sh"
        local backup_dir

        backup_dir=$(
            source "$config_file" 2>/dev/null
            echo "${BACKUP_DIR:-$project_path/backups}"
        )

        if [[ -d "$backup_dir" ]]; then
            local savings=$(calculate_tiered_savings "$backup_dir" "*")
            if [[ $savings -gt 0 ]]; then
                local human_savings
                if [[ $savings -gt 1073741824 ]]; then
                    human_savings="$(echo "scale=1; $savings / 1073741824" | bc)G"
                elif [[ $savings -gt 1048576 ]]; then
                    human_savings="$(echo "scale=1; $savings / 1048576" | bc)M"
                elif [[ $savings -gt 1024 ]]; then
                    human_savings="$(echo "scale=1; $savings / 1024" | bc)K"
                else
                    human_savings="${savings}B"
                fi
                printf "  %-30s %s can be freed\n" "$name" "$human_savings"
                total_savings=$((total_savings + savings))
            fi
        fi
    done < <(list_projects)

    echo ""
    if [[ $total_savings -gt 0 ]]; then
        local total_human
        if [[ $total_savings -gt 1073741824 ]]; then
            total_human="$(echo "scale=1; $total_savings / 1073741824" | bc)G"
        elif [[ $total_savings -gt 1048576 ]]; then
            total_human="$(echo "scale=1; $total_savings / 1048576" | bc)M"
        else
            total_human="$(echo "scale=1; $total_savings / 1024" | bc)K"
        fi
        echo "  Total space that can be freed: $total_human"
        echo ""
        echo "  Run 'checkpoint cleanup' in each project to apply retention policy."
    else
        echo "  No expired backups found. All storage is within retention policy."
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# ==============================================================================
# DETAILED PROJECT VIEW
# ==============================================================================

display_project_detail() {
    local project_path="$1"
    local name=$(basename "$project_path")
    local config_file="$project_path/.backup-config.sh"

    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo "  Project: $name"
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo ""

    # Health status
    local health=$(get_project_health "$project_path")
    local health_emoji health_text
    case "$health" in
        healthy) health_emoji="✅"; health_text="Healthy" ;;
        warning) health_emoji="⚠️ "; health_text="Needs Backup" ;;
        error) health_emoji="❌"; health_text="Error" ;;
    esac

    printf "  Status:        %s %s\n" "$health_emoji" "$health_text"

    # Last backup
    local last_backup=$(get_project_last_backup_detail "$project_path")
    printf "  Last Backup:   %s\n" "$last_backup"

    # Next backup estimate
    local age=$(get_project_backup_age "$project_path")
    if [[ "$age" != "-1" ]]; then
        local remaining=$((3600 - (age % 3600)))
        printf "  Next Backup:   ~%d minutes (activity trigger active)\n" "$((remaining / 60))"
    else
        printf "  Next Backup:   Waiting for first backup\n"
    fi

    echo ""

    # Storage breakdown
    local backup_dir
    backup_dir=$(
        source "$config_file" 2>/dev/null
        echo "${BACKUP_DIR:-$project_path/backups}"
    )

    echo "  Storage Breakdown:"

    if [[ -d "$backup_dir" ]]; then
        local total_storage=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')

        # Files directory
        if [[ -d "$backup_dir/files" ]]; then
            local files_storage=$(du -sh "$backup_dir/files" 2>/dev/null | awk '{print $1}')
            printf "    Current files:     %s (mirror in files/)\n" "${files_storage:-0B}"
        fi

        # Archive directory
        if [[ -d "$backup_dir/archive" ]]; then
            local archive_storage=$(du -sh "$backup_dir/archive" 2>/dev/null | awk '{print $1}')
            local archive_count=$(find "$backup_dir/archive" -type f 2>/dev/null | wc -l | tr -d ' ')
            printf "    Archived versions: %s (%d file versions)\n" "${archive_storage:-0B}" "$archive_count"
        fi

        # Database dumps
        if [[ -d "$backup_dir/databases" ]]; then
            local db_storage=$(du -sh "$backup_dir/databases" 2>/dev/null | awk '{print $1}')
            local db_count=$(find "$backup_dir/databases" -type f 2>/dev/null | wc -l | tr -d ' ')
            printf "    Database dumps:    %s (%d dumps)\n" "${db_storage:-0B}" "$db_count"
        fi

        echo "    ───────────────────────────────────"
        printf "    Total:             %s\n" "${total_storage:-0B}"
    else
        echo "    No backups yet"
    fi

    echo ""

    # Retention status
    echo "  Retention Status (Time Machine style):"
    if [[ -d "$backup_dir" ]]; then
        local stats=$(get_retention_stats "$backup_dir")
        local hourly=$(echo "$stats" | grep -o 'hourly:[0-9]*' | cut -d: -f2)
        local daily=$(echo "$stats" | grep -o 'daily:[0-9]*' | cut -d: -f2)
        local weekly=$(echo "$stats" | grep -o 'weekly:[0-9]*' | cut -d: -f2)
        local monthly=$(echo "$stats" | grep -o 'monthly:[0-9]*' | cut -d: -f2)

        printf "    Hourly (24h):   %d snapshots (keeping all)\n" "${hourly:-0}"
        printf "    Daily (7d):     %d representatives\n" "${daily:-0}"
        printf "    Weekly (4w):    %d representatives\n" "${weekly:-0}"
        printf "    Monthly (12m):  %d representatives\n" "${monthly:-0}"
    else
        echo "    No retention data available"
    fi

    echo ""

    # Recent activity (from backup.log)
    echo "  Recent Activity:"
    if [[ -f "$backup_dir/backup.log" ]]; then
        tail -5 "$backup_dir/backup.log" 2>/dev/null | while read -r line; do
            printf "    • %s\n" "$line"
        done
    else
        echo "    No activity log found"
    fi

    echo ""

    # Actions
    echo "  Actions:"
    echo "    [b] Backup now"
    echo "    [r] Restore wizard"
    echo "    [c] Configure"
    echo "    [l] Cleanup preview"
    echo "    [q] Back to dashboard"
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

All-projects backup dashboard showing status across all registered projects.

OPTIONS:
    --interactive, -i    Run in interactive menu mode
    --verbose, -v        Show detailed retention info
    --project NAME       Show detailed view for specific project
    -h, --help           Show this help message

EXAMPLES:
    $(basename "$0")                  # Show all projects table
    $(basename "$0") --interactive    # Interactive menu mode
    $(basename "$0") --project myapp  # Detailed view for 'myapp'
    $(basename "$0") -v               # Verbose table with retention info

EOF
}

main() {
    local interactive=false
    local verbose=false
    local project_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interactive|-i)
                interactive=true
                shift
                ;;
            --verbose|-v)
                verbose=true
                shift
                ;;
            --project)
                project_name="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage
                exit 1
                ;;
        esac
    done

    # Project detail mode
    if [[ -n "$project_name" ]]; then
        # Find project by name
        local found=""
        while IFS= read -r project_path; do
            [[ -z "$project_path" ]] && continue
            local name=$(basename "$project_path")
            if [[ "$name" == "$project_name" ]]; then
                found="$project_path"
                break
            fi
        done < <(list_projects)

        if [[ -z "$found" ]]; then
            echo "Error: Project '$project_name' not found in registry" >&2
            exit 1
        fi

        display_project_detail "$found"
        exit 0
    fi

    # Interactive mode
    if [[ "$interactive" == "true" ]]; then
        run_interactive "$verbose"
        exit 0
    fi

    # Default: show table
    display_projects_table "$verbose"
}

main "$@"
