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

# Hours without backup before warning/error (global defaults)
# These can be overridden per-project via ALERT_WARNING_HOURS/ALERT_ERROR_HOURS
# in project's .backup-config.sh
: "${HEALTH_WARNING_HOURS:=24}"
: "${HEALTH_ERROR_HOURS:=72}"

# ==============================================================================
# PROJECT HEALTH CHECK
# ==============================================================================

# Get backup age in seconds for a project
# Uses BOTH the registry timestamp (updated every successful cycle) AND
# the newest backup file on disk, returning whichever is more recent.
# This prevents false staleness alerts when a backup cycle runs but
# produces no new files (no changes detected in the project).
# Args: $1 = project path
# Returns: age in seconds, or -1 if never backed up
get_project_backup_age() {
    local project_path="$1"
    local now
    now=$(date +%s)
    local best_time=0

    # Source 1: Registry last_backup timestamp (updated every successful cycle)
    if command -v python3 &>/dev/null && [[ -f "${REGISTRY_FILE:-$HOME/.config/checkpoint/projects.json}" ]]; then
        local registry_time
        registry_time=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for p in data.get('projects', []):
        if p['path'] == sys.argv[2]:
            print(p.get('last_backup', 0))
            sys.exit(0)
    print(0)
except: print(0)
" "${REGISTRY_FILE:-$HOME/.config/checkpoint/projects.json}" "$project_path" 2>/dev/null)
        registry_time="${registry_time//[^0-9]/}"  # Strip non-numeric chars
        if [[ -n "$registry_time" ]] && [[ "$registry_time" -gt "$best_time" ]]; then
            best_time=$registry_time
        fi
    fi

    # Source 2: Newest backup file on disk
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

    if [[ -d "$backup_dir" ]]; then
        local last_file
        last_file=$(find "$backup_dir" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" \) -print0 2>/dev/null |
                    xargs -0 ls -t 2>/dev/null | head -1)
        if [[ -n "$last_file" ]]; then
            local file_time
            file_time=$(get_file_mtime "$last_file")
            file_time="${file_time//[^0-9]/}"  # Strip non-numeric chars
            if [[ -n "$file_time" ]] && [[ "$file_time" -gt "$best_time" ]]; then
                best_time=$file_time
            fi
        fi
    fi

    if [[ "$best_time" -eq 0 ]]; then
        echo "-1"
    else
        echo $((now - best_time))
    fi
}

# Check for critical errors in project's backup log
# Only flags true errors: backup script crashes or explicit FATAL/CRITICAL markers.
# Ignores sub-component warnings (e.g. optional DB dump failures when Docker is off)
# since the file backup itself may have succeeded.
# Args: $1 = project path
# Returns: 0 if critical errors found, 1 if no critical errors
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
        # Only check checkpoint's own log lines (prefixed with timestamp brackets)
        # for critical failures. Ignore interleaved stderr from sub-processes
        # like pg_dump which write "error:" lines when Docker is off.
        local last_checkpoint_line
        last_checkpoint_line=$(grep '^\[' "$log_file" 2>/dev/null | tail -1)
        if [[ -n "$last_checkpoint_line" ]]; then
            if echo "$last_checkpoint_line" | grep -qi "FATAL\|CRITICAL\|backup failed\|exit code"; then
                return 0  # Has critical errors
            fi
        fi
    fi

    return 1  # No critical errors
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

    # Load project-specific thresholds if available
    local config_file="$project_path/.backup-config.sh"
    local warning_hours=${HEALTH_WARNING_HOURS:-24}
    local error_hours=${HEALTH_ERROR_HOURS:-72}

    if [[ -f "$config_file" ]]; then
        local project_warning project_error
        project_warning=$(source "$config_file" 2>/dev/null; echo "${ALERT_WARNING_HOURS:-}")
        project_error=$(source "$config_file" 2>/dev/null; echo "${ALERT_ERROR_HOURS:-}")
        [[ -n "$project_warning" ]] && warning_hours="$project_warning"
        [[ -n "$project_error" ]] && error_hours="$project_error"
    fi

    local warning_threshold=$((warning_hours * 3600))
    local error_threshold=$((error_hours * 3600))

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
# PROJECT ERROR EXTRACTION
# ==============================================================================

# Get backup directory for a project
# Args: $1 = project path
# Returns: backup directory path
get_project_backup_dir() {
    local project_path="$1"
    local config_file="$project_path/.backup-config.sh"

    if [[ -f "$config_file" ]]; then
        (
            source "$config_file" 2>/dev/null
            echo "${BACKUP_DIR:-$project_path/backups}"
        )
    else
        echo "$project_path/backups"
    fi
}

# Get recent errors for a project from backup state
# Args: $1 = project path, $2 = max errors (default 5)
# Returns: One error per line in format: error_code:file_path
get_project_errors() {
    local project_path="$1"
    local max_errors="${2:-5}"
    local project_name
    project_name=$(basename "$project_path")
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    local state_file="$state_dir/$project_name/last-backup.json"

    if [[ ! -f "$state_file" ]]; then
        return
    fi

    # Extract failures from JSON (grep-based, no jq dependency)
    # Failure format: {"type":"file","path":"...","error_code":"...","error_message":"...","suggested_fix":"..."}
    local in_failures=false
    local count=0
    local current_code=""
    local current_path=""

    while IFS= read -r line; do
        # Detect start of failures array
        if [[ "$line" =~ \"failures\"[[:space:]]*:[[:space:]]*\[ ]]; then
            in_failures=true
            continue
        fi

        if [[ "$in_failures" == "true" ]]; then
            # End of failures array
            if [[ "$line" =~ ^[[:space:]]*\] ]]; then
                break
            fi

            # Extract error_code from line
            if [[ "$line" =~ \"error_code\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                current_code="${BASH_REMATCH[1]}"
            fi

            # Extract path from line
            if [[ "$line" =~ \"path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                current_path="${BASH_REMATCH[1]}"
            fi

            # If we have both, output and reset
            if [[ -n "$current_code" && -n "$current_path" ]]; then
                echo "$current_code:$current_path"
                current_code=""
                current_path=""
                ((count++))
                [[ $count -ge $max_errors ]] && break
            fi
        fi
    done < "$state_file"
}

# ==============================================================================
# EXPORT FUNCTIONS
# ==============================================================================

export -f get_project_backup_dir
export -f get_project_errors
export -f get_project_backup_age
export -f has_project_errors
export -f get_project_health
export -f get_global_health
export -f get_global_summary
export -f format_age
export -f get_all_projects_status
export -f get_all_projects_status_json
