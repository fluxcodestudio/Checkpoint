#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Dashboard Status Library
# ==============================================================================
# Collects live status data for dashboard display
# ==============================================================================

# Source cross-platform daemon manager if not already loaded
if [ -z "${_DAEMON_MANAGER_LOADED:-}" ]; then
    _ds_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    if [ -f "$_ds_lib_dir/platform/daemon-manager.sh" ]; then
        source "$_ds_lib_dir/platform/daemon-manager.sh"
    fi
fi

# ==============================================================================
# STATUS DATA COLLECTION
# ==============================================================================

# Get project name
get_project_name() {
    if [[ -f "$PWD/.backup-config.sh" ]]; then
        source "$PWD/.backup-config.sh" 2>/dev/null
        echo "${PROJECT_NAME:-$(basename "$PWD")}"
    else
        basename "$PWD"
    fi
}

# Get configuration status
get_config_status() {
    if [[ -f "$PWD/.backup-config.sh" ]]; then
        echo "✓ Configured"
    else
        echo "⚠ Not Configured"
    fi
}

# Get last backup time (human readable)
get_last_backup_time() {
    local backup_dir="${BACKUP_DIR:-$PWD/backups}"

    if [[ ! -d "$backup_dir" ]]; then
        echo "Never"
        return
    fi

    # Find most recent backup file
    local last_file=$(find "$backup_dir" -type f \( -name "*.gz" -o -name "*.sql" \) 2>/dev/null | head -1)

    if [[ -z "$last_file" ]]; then
        echo "Never"
        return
    fi

    # Get file modification time
    local file_time
    file_time=$(get_file_mtime "$last_file")

    if [[ -z "$file_time" ]]; then
        echo "Unknown"
        return
    fi

    # Calculate age
    local now=$(date +%s)
    local age=$((now - file_time))

    if [[ $age -lt 60 ]]; then
        echo "Just now"
    elif [[ $age -lt 3600 ]]; then
        echo "$((age / 60)) minutes ago"
    elif [[ $age -lt 86400 ]]; then
        echo "$((age / 3600)) hours ago"
    else
        echo "$((age / 86400)) days ago"
    fi
}

# Get next backup time (countdown)
get_next_backup_time() {
    # Check if daemon is running (cross-platform via daemon-manager.sh)
    local project_name=$(get_project_name)

    if type status_daemon >/dev/null 2>&1 && status_daemon "$project_name" 2>/dev/null; then
        # Get backup interval from config
        local interval="${BACKUP_INTERVAL:-3600}"
        local minutes=$((interval / 60))

        # Try to estimate next run
        local last_time=$(get_last_backup_time)
        if [[ "$last_time" =~ ([0-9]+)\ minutes\ ago ]]; then
            local elapsed="${BASH_REMATCH[1]}"
            local remaining=$((minutes - elapsed))
            if [[ $remaining -gt 0 ]]; then
                echo "$remaining minutes"
                return
            fi
        fi

        echo "~$minutes minutes"
    else
        echo "Not scheduled"
    fi
}

# Get storage usage
get_storage_usage() {
    local backup_dir="${BACKUP_DIR:-$PWD/backups}"

    if [[ ! -d "$backup_dir" ]]; then
        echo "No backups"
        return
    fi

    # Get directory size
    local size
    if [[ "$OSTYPE" == "darwin"* ]]; then
        size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
    else
        size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
    fi

    # Get database size
    local db_size=""
    if [[ -d "$backup_dir/databases" ]]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            db_size=$(du -sh "$backup_dir/databases" 2>/dev/null | awk '{print $1}')
        else
            db_size=$(du -sh "$backup_dir/databases" 2>/dev/null | awk '{print $1}')
        fi
    fi

    if [[ -n "$db_size" ]]; then
        echo "${size} (databases: ${db_size})"
    else
        echo "$size"
    fi
}

# Get backup system status
get_backup_status() {
    # Check if backups are paused
    local pause_file="$HOME/.checkpoint-paused"
    if [[ -f "$pause_file" ]]; then
        echo "⏸ Paused"
        return
    fi

    # Check for recent backup failures
    local backup_dir="${BACKUP_DIR:-$PWD/backups}"
    if [[ -f "$backup_dir/backup.log" ]]; then
        if tail -10 "$backup_dir/backup.log" 2>/dev/null | grep -qi "error\|fail"; then
            echo "✗ Error"
            return
        fi
    fi

    # Check daemon status (cross-platform via daemon-manager.sh)
    local project_name=$(get_project_name)

    if type status_daemon >/dev/null 2>&1 && status_daemon "$project_name" 2>/dev/null; then
        echo "⚡ Active"
    elif [[ -f "$PWD/.backup-config.sh" ]]; then
        echo "○ Inactive"
    else
        echo "○ Not Setup"
    fi
}

# Get cloud sync status
get_cloud_status() {
    if [[ -f "$PWD/.backup-config.sh" ]]; then
        source "$PWD/.backup-config.sh" 2>/dev/null

        if [[ "${CLOUD_ENABLED:-false}" == "true" ]]; then
            # Check last cloud sync time
            local backup_dir="${BACKUP_DIR:-$PWD/backups}"
            if [[ -f "$backup_dir/.last-cloud-sync" ]]; then
                local sync_time=$(cat "$backup_dir/.last-cloud-sync")
                local now=$(date +%s)
                local age=$((now - sync_time))

                if [[ $age -lt 3600 ]]; then
                    echo "☁ Synced"
                else
                    echo "☁ Sync pending"
                fi
            else
                echo "☁ Enabled"
            fi
        else
            echo "○ Disabled"
        fi
    else
        echo "○ Disabled"
    fi
}

# Check for updates
# Returns: "current_version|latest_version|has_update"
check_for_updates() {
    local checkpoint_lib=""

    # Find Checkpoint installation
    if command -v backup-status &>/dev/null; then
        checkpoint_lib="/usr/local/lib/checkpoint"
        [[ ! -d "$checkpoint_lib" ]] && checkpoint_lib="$HOME/.local/lib/checkpoint"
    else
        checkpoint_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    fi

    # Get current version
    local current_version="unknown"
    if [[ -f "$checkpoint_lib/VERSION" ]]; then
        current_version=$(cat "$checkpoint_lib/VERSION" 2>/dev/null)
    fi

    # Get latest version from GitHub
    local latest_version
    latest_version=$(curl -sf https://api.github.com/repos/fluxcodestudio/Checkpoint/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' 2>/dev/null)

    if [[ -z "$latest_version" ]]; then
        # No release yet or network error
        echo "$current_version||false"
        return
    fi

    # Compare versions
    if [[ "$current_version" != "$latest_version" ]]; then
        echo "$current_version|$latest_version|true"
    else
        echo "$current_version|$latest_version|false"
    fi
}

# Get health status
# Returns: "healthy", "warning", "error"
get_health_status() {
    local status="healthy"

    # Check for backup failures
    local backup_dir="${BACKUP_DIR:-$PWD/backups}"
    if [[ -f "$backup_dir/backup.log" ]]; then
        if tail -10 "$backup_dir/backup.log" 2>/dev/null | grep -qi "error"; then
            status="error"
        elif tail -10 "$backup_dir/backup.log" 2>/dev/null | grep -qi "warn"; then
            status="warning"
        fi
    fi

    # Check if backup is too old
    local last_backup=$(get_last_backup_time)
    if [[ "$last_backup" == "Never" ]]; then
        status="warning"
    elif [[ "$last_backup" =~ ([0-9]+)\ days\ ago ]]; then
        local days="${BASH_REMATCH[1]}"
        if [[ $days -gt 7 ]]; then
            status="error"
        elif [[ $days -gt 2 ]]; then
            status="warning"
        fi
    fi

    echo "$status"
}

# Get all status data as key-value pairs
get_all_status() {
    echo "PROJECT_NAME=$(get_project_name)"
    echo "CONFIG_STATUS=$(get_config_status)"
    echo "LAST_BACKUP=$(get_last_backup_time)"
    echo "NEXT_BACKUP=$(get_next_backup_time)"
    echo "STORAGE=$(get_storage_usage)"
    echo "BACKUP_STATUS=$(get_backup_status)"
    echo "CLOUD_STATUS=$(get_cloud_status)"
    echo "HEALTH=$(get_health_status)"

    # Check for updates
    local update_info=$(check_for_updates)
    IFS='|' read -r current_ver latest_ver has_update <<< "$update_info"
    echo "CURRENT_VERSION=$current_ver"
    echo "LATEST_VERSION=$latest_ver"
    echo "HAS_UPDATE=$has_update"
}
