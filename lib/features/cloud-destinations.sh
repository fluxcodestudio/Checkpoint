#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cloud Folder Destination Resolution
# Three-tier fallback: cloud folder, rclone API, local backup
# ==============================================================================
# @requires: core/output (for color functions, backup_log),
#            core/config (for load_backup_config)
# @provides: _ensure_cloud_detector_loaded, check_cloud_folder_health,
#            _ensure_cloud_backup_loaded, resolve_backup_destinations,
#            ensure_backup_dirs
# ==============================================================================

# Include guard
[ -n "$_CHECKPOINT_CLOUD_DESTINATIONS" ] && return || readonly _CHECKPOINT_CLOUD_DESTINATIONS=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ==============================================================================
# CLOUD FOLDER DESTINATION RESOLUTION
# ==============================================================================

# Source cloud folder detector if not already loaded
_ensure_cloud_detector_loaded() {
    if [[ -z "${CLOUD_DETECTOR_LOADED:-}" ]]; then
        local lib_dir="${LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
        if [[ -f "$lib_dir/cloud-folder-detector.sh" ]]; then
            source "$lib_dir/cloud-folder-detector.sh"
            export CLOUD_DETECTOR_LOADED=1
        fi
    fi
}

# Check if cloud folder is available and writable
# Returns: 0 if healthy, 1 if unavailable
check_cloud_folder_health() {
    local cloud_dir="${CLOUD_BACKUP_DIR:-}"

    # No cloud folder configured
    if [[ -z "$cloud_dir" ]]; then
        return 1
    fi

    # Directory doesn't exist
    if [[ ! -d "$cloud_dir" ]]; then
        return 1
    fi

    # Test write access with temp file
    local test_file="$cloud_dir/.checkpoint-health-check"
    if ! touch "$test_file" 2>/dev/null; then
        return 1
    fi
    rm -f "$test_file" 2>/dev/null

    return 0
}

# Ensure cloud-backup.sh is loaded for rclone functions
_ensure_cloud_backup_loaded() {
    if ! declare -f check_rclone_installed &>/dev/null; then
        local lib_dir
        lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "$lib_dir/cloud-backup.sh" ]]; then
            source "$lib_dir/cloud-backup.sh"
        fi
    fi
}

# Resolve backup destinations based on cloud folder configuration
# Sets PRIMARY_* and optionally SECONDARY_* destination variables
# Returns: 0 on success, 1 on failure
resolve_backup_destinations() {
    # Ensure cloud detector and rclone functions are loaded
    _ensure_cloud_detector_loaded
    _ensure_cloud_backup_loaded

    # Read cloud config with defaults
    local cloud_enabled="${CLOUD_FOLDER_ENABLED:-false}"
    local cloud_path="${CLOUD_FOLDER_PATH:-}"
    local project_folder="${CLOUD_PROJECT_FOLDER:-${PROJECT_NAME:-Checkpoint}}"
    local also_local="${CLOUD_FOLDER_ALSO_LOCAL:-false}"

    # Default to local backup directory
    local local_backup_dir="${BACKUP_DIR:-$PROJECT_DIR/backups}"

    if [[ "$cloud_enabled" != "true" ]]; then
        # Cloud disabled - use local backup directory
        PRIMARY_BACKUP_DIR="$local_backup_dir"
        SECONDARY_BACKUP_DIR=""

        # Set primary subdirectories
        PRIMARY_FILES_DIR="$PRIMARY_BACKUP_DIR/files"
        PRIMARY_ARCHIVED_DIR="$PRIMARY_BACKUP_DIR/archived"
        PRIMARY_DATABASE_DIR="$PRIMARY_BACKUP_DIR/databases"

        # Clear secondary
        SECONDARY_FILES_DIR=""
        SECONDARY_ARCHIVED_DIR=""
        SECONDARY_DATABASE_DIR=""

        export PRIMARY_BACKUP_DIR PRIMARY_FILES_DIR PRIMARY_ARCHIVED_DIR PRIMARY_DATABASE_DIR
        export SECONDARY_BACKUP_DIR SECONDARY_FILES_DIR SECONDARY_ARCHIVED_DIR SECONDARY_DATABASE_DIR

        return 0
    fi

    # Cloud enabled - resolve cloud folder path
    local cloud_root=""

    if [[ -n "$cloud_path" ]]; then
        # User specified a cloud folder path - validate it
        if [[ -d "$cloud_path" && -w "$cloud_path" ]]; then
            cloud_root="$cloud_path"
        else
            # Specified path invalid - log warning and fall back to auto-detect
            backup_log "Cloud folder path not valid or writable: $cloud_path - attempting auto-detect" "WARN"
            cloud_path=""
        fi
    fi

    if [[ -z "$cloud_root" ]]; then
        # Auto-detect cloud folder
        if command -v get_first_cloud_folder &>/dev/null; then
            cloud_root=$(get_first_cloud_folder 2>/dev/null)
        fi

        if [[ -z "$cloud_root" ]]; then
            # No cloud folder available - fall back to local
            backup_log "No cloud folder detected - falling back to local backup" "WARN"

            PRIMARY_BACKUP_DIR="$local_backup_dir"
            SECONDARY_BACKUP_DIR=""

            PRIMARY_FILES_DIR="$PRIMARY_BACKUP_DIR/files"
            PRIMARY_ARCHIVED_DIR="$PRIMARY_BACKUP_DIR/archived"
            PRIMARY_DATABASE_DIR="$PRIMARY_BACKUP_DIR/databases"

            SECONDARY_FILES_DIR=""
            SECONDARY_ARCHIVED_DIR=""
            SECONDARY_DATABASE_DIR=""

            export PRIMARY_BACKUP_DIR PRIMARY_FILES_DIR PRIMARY_ARCHIVED_DIR PRIMARY_DATABASE_DIR
            export SECONDARY_BACKUP_DIR SECONDARY_FILES_DIR SECONDARY_ARCHIVED_DIR SECONDARY_DATABASE_DIR

            return 0
        fi
    fi

    # Build cloud backup directory path
    CLOUD_BACKUP_DIR="$cloud_root/Backups/Checkpoint/$project_folder"
    export CLOUD_BACKUP_DIR

    # Three-tier fallback: cloud folder → rclone API → local
    # TIER 1: Cloud folder available and healthy - use it as primary
    if check_cloud_folder_health; then
        # Set primary to cloud
        PRIMARY_BACKUP_DIR="$CLOUD_BACKUP_DIR"
        PRIMARY_FILES_DIR="$PRIMARY_BACKUP_DIR/files"
        PRIMARY_ARCHIVED_DIR="$PRIMARY_BACKUP_DIR/archived"
        PRIMARY_DATABASE_DIR="$PRIMARY_BACKUP_DIR/databases"

        # Set secondary to local if also_local is true
        if [[ "$also_local" == "true" ]]; then
            SECONDARY_BACKUP_DIR="$local_backup_dir"
            SECONDARY_FILES_DIR="$SECONDARY_BACKUP_DIR/files"
            SECONDARY_ARCHIVED_DIR="$SECONDARY_BACKUP_DIR/archived"
            SECONDARY_DATABASE_DIR="$SECONDARY_BACKUP_DIR/databases"
        else
            SECONDARY_BACKUP_DIR=""
            SECONDARY_FILES_DIR=""
            SECONDARY_ARCHIVED_DIR=""
            SECONDARY_DATABASE_DIR=""
        fi

    # TIER 2: Cloud folder unavailable but rclone configured - try direct API
    elif [[ "${CLOUD_ENABLED:-false}" == "true" ]] && check_rclone_installed 2>/dev/null; then
        backup_log "Cloud folder unavailable, attempting rclone API fallback" "WARN"

        # Use local as primary, rclone will sync asynchronously
        PRIMARY_BACKUP_DIR="$local_backup_dir"
        PRIMARY_FILES_DIR="$PRIMARY_BACKUP_DIR/files"
        PRIMARY_ARCHIVED_DIR="$PRIMARY_BACKUP_DIR/archived"
        PRIMARY_DATABASE_DIR="$PRIMARY_BACKUP_DIR/databases"

        # Mark for rclone sync after backup completes
        export RCLONE_SYNC_PENDING=true

        SECONDARY_BACKUP_DIR=""
        SECONDARY_FILES_DIR=""
        SECONDARY_ARCHIVED_DIR=""
        SECONDARY_DATABASE_DIR=""

        export PRIMARY_BACKUP_DIR PRIMARY_FILES_DIR PRIMARY_ARCHIVED_DIR PRIMARY_DATABASE_DIR
        export SECONDARY_BACKUP_DIR SECONDARY_FILES_DIR SECONDARY_ARCHIVED_DIR SECONDARY_DATABASE_DIR
        return 0

    # TIER 3: Neither available - local only
    else
        backup_log "Cloud folder unavailable, using local backup only" "WARN"

        PRIMARY_BACKUP_DIR="$local_backup_dir"
        PRIMARY_FILES_DIR="$PRIMARY_BACKUP_DIR/files"
        PRIMARY_ARCHIVED_DIR="$PRIMARY_BACKUP_DIR/archived"
        PRIMARY_DATABASE_DIR="$PRIMARY_BACKUP_DIR/databases"

        SECONDARY_BACKUP_DIR=""
        SECONDARY_FILES_DIR=""
        SECONDARY_ARCHIVED_DIR=""
        SECONDARY_DATABASE_DIR=""

        export PRIMARY_BACKUP_DIR PRIMARY_FILES_DIR PRIMARY_ARCHIVED_DIR PRIMARY_DATABASE_DIR
        export SECONDARY_BACKUP_DIR SECONDARY_FILES_DIR SECONDARY_ARCHIVED_DIR SECONDARY_DATABASE_DIR
        return 0
    fi

    export CLOUD_BACKUP_DIR
    export PRIMARY_BACKUP_DIR PRIMARY_FILES_DIR PRIMARY_ARCHIVED_DIR PRIMARY_DATABASE_DIR
    export SECONDARY_BACKUP_DIR SECONDARY_FILES_DIR SECONDARY_ARCHIVED_DIR SECONDARY_DATABASE_DIR

    return 0
}

# Ensure backup directories exist in both primary and secondary destinations
# Creates: files/, archived/, databases/ subdirectories
# Returns: 0 on success, 1 if primary creation fails
ensure_backup_dirs() {
    local create_errors=0

    # Create primary directories (required)
    if [[ -n "${PRIMARY_BACKUP_DIR:-}" ]]; then
        mkdir -p "$PRIMARY_FILES_DIR" 2>/dev/null || create_errors=$((create_errors + 1))
        mkdir -p "$PRIMARY_ARCHIVED_DIR" 2>/dev/null || create_errors=$((create_errors + 1))
        mkdir -p "$PRIMARY_DATABASE_DIR" 2>/dev/null || create_errors=$((create_errors + 1))

        if [[ $create_errors -gt 0 ]]; then
            backup_log "Failed to create primary backup directories in $PRIMARY_BACKUP_DIR" "ERROR"
            return 1
        fi
    fi

    # Create secondary directories (optional, warn on failure)
    if [[ -n "${SECONDARY_BACKUP_DIR:-}" ]]; then
        mkdir -p "$SECONDARY_FILES_DIR" 2>/dev/null || \
            backup_log "Failed to create secondary files directory: $SECONDARY_FILES_DIR" "WARN"
        mkdir -p "$SECONDARY_ARCHIVED_DIR" 2>/dev/null || \
            backup_log "Failed to create secondary archived directory: $SECONDARY_ARCHIVED_DIR" "WARN"
        mkdir -p "$SECONDARY_DATABASE_DIR" 2>/dev/null || \
            backup_log "Failed to create secondary database directory: $SECONDARY_DATABASE_DIR" "WARN"
    fi

    return 0
}
