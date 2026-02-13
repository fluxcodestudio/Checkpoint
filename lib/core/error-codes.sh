#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Error Codes and Suggested Fixes
# ==============================================================================
# @requires: none
# @provides: ERROR_CATALOG, get_error_description, get_error_suggestion,
#            format_error_with_fix, map_error_to_code
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_ERROR_CODES:-}" ] && return || readonly _CHECKPOINT_ERROR_CODES=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ==============================================================================
# ERROR CODES AND SUGGESTED FIXES
# ==============================================================================

# Error categories: PERM (permission), DISK (storage), CONF (config), NET (network), DB (database)
# Error format: E{CATEGORY}{NUMBER} - e.g., EPERM001

# Bash 3.2 compatible: indexed arrays with pipe-delimited format
# Format: "ERROR_CODE|DESCRIPTION|SUGGESTED_FIX"

ERROR_CATALOG=(
    # Permission errors
    "EPERM001|Cannot write to backup directory|Check permissions: ls -la \"\$BACKUP_DIR\" | Fix: chmod -R u+rw \"\$BACKUP_DIR\""
    "EPERM002|Cannot read source file|Check file exists and is readable: ls -la \"\$FILE\""
    "EPERM003|Permission denied during copy|Check source and destination permissions | Run: chmod u+r source && chmod u+w dest"

    # Disk errors
    "EDISK001|Backup directory full or quota exceeded|Check disk space: df -h \"\$BACKUP_DIR\" | Free space or increase quota"
    "EDISK002|External drive not mounted|Mount drive or check: ls /Volumes/ | Update BACKUP_DIR in .backup-config.sh"
    "EDISK003|Insufficient space for backup|Need more free space | Current: df -h | Delete old backups: cleanup.sh --aggressive"

    # Config errors
    "ECONF001|Invalid backup configuration|Validate config: cat .backup-config.sh | Check BACKUP_DIR and PROJECT_DIR"
    "ECONF002|Missing required configuration|Run: checkpoint.sh init | Or create .backup-config.sh manually"
    "ECONF003|Cloud folder path does not exist|Verify cloud sync app running | Check: ls \"\$CLOUD_FOLDER\" | Update path in config"

    # Database errors
    "EDB001|Database connection failed|Check database is running | Verify credentials in .env | Test: psql/mysql/sqlite3"
    "EDB002|Database dump command failed|Check dump tool installed: which pg_dump mysqldump | Check permissions"
    "EDB003|Database file locked|Close applications using the database | Wait and retry"

    # Network errors (for cloud backup)
    "ENET001|Cloud sync destination unreachable|Check internet: ping -c 1 google.com | Verify cloud folder path exists"
    "ENET002|Cloud sync service not running|Start cloud sync app (Dropbox, Google Drive) | Check: pgrep -i dropbox"

    # File errors
    "EFILE001|Source file not found|File was deleted or moved | Check: ls -la \"\$FILE\""
    "EFILE002|Size mismatch after copy|File was modified during backup | Retry backup to capture current version"
    "EFILE003|File too large for destination|Check available space | Consider excluding large files"

    # Unknown/generic
    "EUNK000|Unknown error occurred|Check backup logs for details | Run: backup-failures"
)

# Get error description by code
# Args: $1 = error code (e.g., EPERM001)
# Returns: Error description or "Unknown error: $code"
get_error_description() {
    local code="$1"
    local entry
    for entry in "${ERROR_CATALOG[@]}"; do
        if [[ "$entry" == "$code|"* ]]; then
            echo "$entry" | cut -d'|' -f2
            return 0
        fi
    done
    echo "Unknown error: $code"
}

# Get suggested fix by code
# Args: $1 = error code (e.g., EPERM001)
# Returns: Suggested fix or generic message
get_error_suggestion() {
    local code="$1"
    local entry
    for entry in "${ERROR_CATALOG[@]}"; do
        if [[ "$entry" == "$code|"* ]]; then
            # Get everything after the second pipe (field 3+)
            echo "${entry#*|}" | cut -d'|' -f2-
            return 0
        fi
    done
    echo "Check backup logs for details | Run: backup-failures"
}

# Format error with suggestion for display
# Args: $1 = error code, $2 = context (optional)
# Returns: Formatted multi-line error message
format_error_with_fix() {
    local code="$1"
    local context="${2:-}"
    local desc
    local fix

    desc=$(get_error_description "$code")
    fix=$(get_error_suggestion "$code")

    echo "Error $code: $desc"
    [[ -n "$context" ]] && echo "  Context: $context"
    echo "  Fix: $fix"
}

# Map common error conditions to error codes
# Args: $1 = error type (existing codes like "disk_full", "permission_denied")
# Returns: Standardized error code
map_error_to_code() {
    local error_type="$1"
    case "$error_type" in
        disk_full|EDISK001)          echo "EDISK001" ;;
        drive_disconnected|EDISK002) echo "EDISK002" ;;
        permission_denied|EPERM001)  echo "EPERM001" ;;
        file_not_readable|EPERM002)  echo "EPERM002" ;;
        permission|EPERM003)         echo "EPERM003" ;;
        config_invalid|ECONF001)     echo "ECONF001" ;;
        config_missing|ECONF002)     echo "ECONF002" ;;
        cloud_missing|ECONF003)      echo "ECONF003" ;;
        db_connection|EDB001)        echo "EDB001" ;;
        db_dump_failed|EDB002)       echo "EDB002" ;;
        db_locked|EDB003)            echo "EDB003" ;;
        network|ENET001)             echo "ENET001" ;;
        cloud_not_running|ENET002)   echo "ENET002" ;;
        file_missing|EFILE001)       echo "EFILE001" ;;
        size_mismatch|EFILE002)      echo "EFILE002" ;;
        file_too_large|EFILE003)     echo "EFILE003" ;;
        *)                           echo "EUNK000" ;;
    esac
}
