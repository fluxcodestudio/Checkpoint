#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Global Status Aggregation Library
# ==============================================================================
# Aggregates backup health across ALL registered projects
# ==============================================================================

# Prevent multiple sourcing
[[ -n "${GLOBAL_STATUS_LOADED:-}" ]] && return 0
readonly GLOBAL_STATUS_LOADED=1

# Find library directory
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    GLOBAL_STATUS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    GLOBAL_STATUS_LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# Source dependencies
if [[ -f "$GLOBAL_STATUS_LIB_DIR/projects-registry.sh" ]]; then
    source "$GLOBAL_STATUS_LIB_DIR/projects-registry.sh"
else
    echo "Error: projects-registry.sh not found in $GLOBAL_STATUS_LIB_DIR" >&2
    return 1 2>/dev/null || exit 1
fi

# ==============================================================================
# HEALTH THRESHOLDS
# ==============================================================================

# Hours without backup before warning/error
: "${HEALTH_WARNING_HOURS:=24}"
: "${HEALTH_ERROR_HOURS:=72}"

# ==============================================================================
# PROJECT HEALTH CHECK
# ==============================================================================

# Get backup age in seconds for a project
# Args: $1 = project path
# Returns: age in seconds, or -1 if never backed up
get_project_backup_age() {
    local project_path="$1"
    local config_file="$project_path/.backup-config.sh"
    local backup_dir

    # Get backup directory from config
    if [[ -f "$config_file" ]]; then
        backup_dir=$(
            source "$config_file" 2>/dev/null
            echo "${BACKUP_DIR:-$project_path/backups}"
        )
    else
        backup_dir="$project_path/backups"
    fi

    if [[ ! -d "$backup_dir" ]]; then
        echo "-1"
        return
    fi

    # Find most recent backup file
    local last_file
    last_file=$(find "$backup_dir" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" \) -print0 2>/dev/null |
                xargs -0 ls -t 2>/dev/null | head -1)

    if [[ -z "$last_file" ]]; then
        echo "-1"
        return
    fi

    # Get file modification time
    local file_time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        file_time=$(stat -f %m "$last_file" 2>/dev/null)
    else
        file_time=$(stat -c %Y "$last_file" 2>/dev/null)
    fi

    if [[ -z "$file_time" ]]; then
        echo "-1"
        return
    fi

    # Calculate age
    local now=$(date +%s)
    echo $((now - file_time))
}

# Check for errors in project's backup log
# Args: $1 = project path
# Returns: 0 if errors found, 1 if no errors
has_project_errors() {
    local project_path="$1"
    local config_file="$project_path/.backup-config.sh"
    local backup_dir

    if [[ -f "$config_file" ]]; then
        backup_dir=$(
            source "$config_file" 2>/dev/null
            echo "${BACKUP_DIR:-$project_path/backups}"
        )
    else
        backup_dir="$project_path/backups"
    fi

    local log_file="$backup_dir/backup.log"

    if [[ -f "$log_file" ]]; then
        # Check last 20 lines for errors
        if tail -20 "$log_file" 2>/dev/null | grep -qi "error\|fail"; then
            return 0  # Has errors
        fi
    fi

    return 1  # No errors
}

# Get health status for a single project
# Args: $1 = project path
# Returns: "healthy" | "warning" | "error"
get_project_health() {
    local project_path="$1"

    # Check for errors first
    if has_project_errors "$project_path"; then
        echo "error"
        return
    fi

    # Check backup age
    local age=$(get_project_backup_age "$project_path")

    if [[ "$age" == "-1" ]]; then
        echo "warning"  # Never backed up
        return
    fi

    local warning_threshold=$((HEALTH_WARNING_HOURS * 3600))
    local error_threshold=$((HEALTH_ERROR_HOURS * 3600))

    if [[ $age -gt $error_threshold ]]; then
        echo "error"
    elif [[ $age -gt $warning_threshold ]]; then
        echo "warning"
    else
        echo "healthy"
    fi
}

# ==============================================================================
# GLOBAL AGGREGATION
# ==============================================================================

# Get global health status (worst across all projects)
# Returns: "healthy" | "warning" | "error"
get_global_health() {
    local worst="healthy"
    local project_count=0

    while IFS= read -r project_path; do
        [[ -z "$project_path" ]] && continue
        [[ ! -d "$project_path" ]] && continue

        ((project_count++))
        local health=$(get_project_health "$project_path")

        case "$health" in
            error)
                worst="error"
                ;;
            warning)
                [[ "$worst" != "error" ]] && worst="warning"
                ;;
        esac
    done < <(list_projects)

    # If no projects registered, that's a warning
    if [[ $project_count -eq 0 ]]; then
        echo "warning"
        return
    fi

    echo "$worst"
}

# Get global summary string
# Returns: "✅ 5 projects OK" or "⚠ 2/5 need backup" or "❌ 1/5 has errors"
get_global_summary() {
    local total=0
    local healthy=0
    local warnings=0
    local errors=0

    while IFS= read -r project_path; do
        [[ -z "$project_path" ]] && continue
        [[ ! -d "$project_path" ]] && continue

        ((total++))
        local health=$(get_project_health "$project_path")

        case "$health" in
            healthy) ((healthy++)) ;;
            warning) ((warnings++)) ;;
            error) ((errors++)) ;;
        esac
    done < <(list_projects)

    if [[ $total -eq 0 ]]; then
        echo "⚠ No projects"
        return
    fi

    if [[ $errors -gt 0 ]]; then
        echo "❌ $errors/$total errors"
    elif [[ $warnings -gt 0 ]]; then
        echo "⚠ $warnings/$total need backup"
    else
        echo "✅ $total OK"
    fi
}

# Format age for display
format_age() {
    local seconds="$1"

    if [[ "$seconds" == "-1" ]]; then
        echo "Never"
        return
    fi

    if [[ $seconds -lt 60 ]]; then
        echo "Just now"
    elif [[ $seconds -lt 3600 ]]; then
        echo "$((seconds / 60))m ago"
    elif [[ $seconds -lt 86400 ]]; then
        echo "$((seconds / 3600))h ago"
    else
        echo "$((seconds / 86400))d ago"
    fi
}

# Get status for all projects (one line per project)
# Output format: NAME | HEALTH | LAST_BACKUP
get_all_projects_status() {
    while IFS= read -r project_path; do
        [[ -z "$project_path" ]] && continue
        [[ ! -d "$project_path" ]] && continue

        local name=$(basename "$project_path")
        local health=$(get_project_health "$project_path")
        local age=$(get_project_backup_age "$project_path")
        local age_str=$(format_age "$age")

        # Health emoji
        local emoji
        case "$health" in
            healthy) emoji="✅" ;;
            warning) emoji="⚠" ;;
            error) emoji="❌" ;;
        esac

        echo "$emoji $name | $age_str"
    done < <(list_projects)
}

# Get all projects status as JSON array
get_all_projects_status_json() {
    echo "["
    local first=true

    while IFS= read -r project_path; do
        [[ -z "$project_path" ]] && continue
        [[ ! -d "$project_path" ]] && continue

        local name=$(basename "$project_path")
        local health=$(get_project_health "$project_path")
        local age=$(get_project_backup_age "$project_path")
        local age_str=$(format_age "$age")

        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi

        cat <<EOF
  {
    "path": "$project_path",
    "name": "$name",
    "health": "$health",
    "lastBackupAge": $age,
    "lastBackupStr": "$age_str"
  }
EOF
    done < <(list_projects)

    echo ""
    echo "]"
}

# ==============================================================================
# EXPORT FUNCTIONS
# ==============================================================================

export -f get_project_backup_age
export -f has_project_errors
export -f get_project_health
export -f get_global_health
export -f get_global_summary
export -f format_age
export -f get_all_projects_status
export -f get_all_projects_status_json
