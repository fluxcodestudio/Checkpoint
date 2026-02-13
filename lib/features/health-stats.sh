#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Health Checks & Statistics
# Component health verification, backup statistics, and retention analysis
# ==============================================================================
# @requires: core/config (for BACKUP_DIR, check_drive)
# @provides: check_daemon_status, check_hooks_status, check_config_status,
#            count_database_backups, count_current_files, count_archived_files,
#            get_total_backup_size, get_last_backup_time,
#            count_backups_to_prune, days_until_prune
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_HEALTH_STATS:-}" ] && return || readonly _CHECKPOINT_HEALTH_STATS=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Source cross-platform daemon manager if not already loaded
if [ -z "${_DAEMON_MANAGER_LOADED:-}" ]; then
    _hs_dm_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/platform/daemon-manager.sh"
    if [ -f "$_hs_dm_path" ]; then
        source "$_hs_dm_path"
    fi
fi

# ==============================================================================
# COMPONENT HEALTH CHECKS
# ==============================================================================

# Check if daemon is running (cross-platform via daemon-manager.sh)
# Returns: 0 if running, 1 if not
check_daemon_status() {
    # Check for global daemon first (new architecture)
    if type status_daemon >/dev/null 2>&1; then
        if status_daemon "global-daemon" 2>/dev/null; then
            return 0
        fi

        # Fallback: check for per-project daemons
        local project_name="${PROJECT_NAME:-}"
        if [ -n "$project_name" ] && status_daemon "$project_name" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Check if hooks are installed
# Args: $1 = project directory
# Returns: 0 if installed, 1 if not
check_hooks_status() {
    local project_dir="$1"

    if [ -f "$project_dir/.claude/hooks/backup-trigger.sh" ]; then
        return 0
    fi
    return 1
}

# Check configuration validity
# Returns: 0 if valid, 1 if invalid
check_config_status() {
    # Check required variables are set
    [ -z "${PROJECT_NAME:-}" ] && return 1
    [ -z "${PROJECT_DIR:-}" ] && return 1
    [ -z "${BACKUP_DIR:-}" ] && return 1

    # Check backup interval is reasonable
    local interval="${BACKUP_INTERVAL:-0}"
    [ $interval -lt 60 ] && return 1

    return 0
}

# ==============================================================================
# STATISTICS GATHERING
# ==============================================================================

# Count database backups
# Output: number of database backup files
count_database_backups() {
    local db_dir="${DATABASE_DIR:-}"
    [ -z "$db_dir" ] || [ ! -d "$db_dir" ] && echo "0" && return

    find "$db_dir" -name "*.db.gz" -type f 2>/dev/null | wc -l | tr -d ' '
}

# Count current files
# Output: number of current backed-up files
count_current_files() {
    local files_dir="${FILES_DIR:-}"
    [ -z "$files_dir" ] || [ ! -d "$files_dir" ] && echo "0" && return

    find "$files_dir" -type f 2>/dev/null | wc -l | tr -d ' '
}

# Count archived files
# Output: number of archived file versions
count_archived_files() {
    local archived_dir="${ARCHIVED_DIR:-}"
    [ -z "$archived_dir" ] || [ ! -d "$archived_dir" ] && echo "0" && return

    find "$archived_dir" -type f 2>/dev/null | wc -l | tr -d ' '
}

# Get total backup size in bytes
# Output: total size in bytes
get_total_backup_size() {
    local backup_dir="${BACKUP_DIR:-}"
    [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ] && echo "0" && return

    get_dir_size_bytes "$backup_dir"
}

# Get last backup timestamp
# Output: Unix timestamp or 0 if never
get_last_backup_time() {
    local state_file="${BACKUP_TIME_STATE:-}"
    [ -z "$state_file" ] || [ ! -f "$state_file" ] && echo "0" && return

    cat "$state_file" 2>/dev/null || echo "0"
}

# ==============================================================================
# RETENTION POLICY ANALYSIS
# ==============================================================================

# Count backups that will be pruned soon
# Args: $1 = directory, $2 = retention days, $3 = warning days (default 7)
# Output: number of backups that will be deleted within warning period
count_backups_to_prune() {
    local dir="$1"
    local retention_days="$2"
    local warning_days="${3:-7}"

    [ ! -d "$dir" ] && echo "0" && return

    local warning_threshold=$((retention_days - warning_days))
    [ $warning_threshold -lt 0 ] && warning_threshold=0

    find "$dir" -type f -mtime +${warning_threshold} 2>/dev/null | wc -l | tr -d ' '
}

# Calculate days until oldest backup is pruned
# Args: $1 = directory, $2 = retention days
# Output: days until next prune, or -1 if none
days_until_prune() {
    local dir="$1"
    local retention_days="$2"

    [ ! -d "$dir" ] && echo "-1" && return

    local oldest_mtime=""
    local f
    while IFS= read -r -d '' f; do
        local mt
        mt=$(get_file_mtime "$f")
        if [ -z "$oldest_mtime" ] || [ "$mt" -lt "$oldest_mtime" ]; then
            oldest_mtime="$mt"
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null)
    [ -z "$oldest_mtime" ] && echo "-1" && return

    local now=$(date +%s)
    local age_seconds=$((now - oldest_mtime))
    local age_days=$((age_seconds / 86400))
    local days_remaining=$((retention_days - age_days))

    echo "$days_remaining"
}
