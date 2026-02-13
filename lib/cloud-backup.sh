#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cloud Backup Library
# ==============================================================================
# Version: 2.3.0
# Description: Cloud storage integration via rclone for off-site backup
#              protection. Supports Dropbox, Google Drive, OneDrive, and iCloud.
#
# Usage:
#   source "$PROJECT_ROOT/lib/cloud-backup.sh"
#   validate_cloud_config
#   cloud_upload
#
# Features:
#   - Automatic cloud uploads via rclone
#   - Support for 40+ cloud providers
#   - Background uploads (non-blocking)
#   - Smart upload strategy (databases + critical files only)
#   - Free tier optimization
# ==============================================================================

# ==============================================================================
# RCLONE DETECTION & INSTALLATION
# ==============================================================================

# Check if rclone is installed
# Returns: 0 if installed, 1 if not found
check_rclone_installed() {
    command -v rclone &>/dev/null
}

# Install rclone via Homebrew (macOS) or curl script (Linux)
# Returns: 0 on success, 1 on failure
install_rclone() {
    echo "Installing rclone..."

    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS - try Homebrew first, fall back to secure download
        if command -v brew &>/dev/null; then
            brew install rclone
        else
            source "${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/security/secure-download.sh"
            secure_install_rclone
        fi
    else
        # Linux - use secure download with SHA256 verification
        source "${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/security/secure-download.sh"
        secure_install_rclone
    fi

    # Verify installation succeeded
    if check_rclone_installed; then
        echo "✓ rclone installed successfully"
        return 0
    else
        echo "✗ Failed to install rclone"
        return 1
    fi
}

# ==============================================================================
# RCLONE CONFIGURATION
# ==============================================================================

# List all configured rclone remotes (without trailing colons)
# Returns: List of remote names, one per line
list_rclone_remotes() {
    rclone listremotes 2>/dev/null | sed 's/:$//'
}

# Launch interactive rclone configuration wizard
# Args:
#   $1 - Provider name (dropbox, gdrive, onedrive, icloud)
# Note: Opens browser for OAuth authentication
setup_rclone_remote() {
    local provider="$1"

    echo ""
    echo "Setting up rclone for $provider..."
    echo "This will open a browser window for authentication."
    echo ""

    # Launch interactive rclone config
    rclone config
}

# Test connection to cloud remote by listing root directory
# Args:
#   $1 - Remote name (e.g., "mydropbox")
# Returns: 0 if connection succeeds, 1 if fails
test_rclone_connection() {
    local remote_name="$1"

    if [[ -z "$remote_name" ]]; then
        echo "✗ No remote name specified"
        return 1
    fi

    # Test by listing root directory (lsd = list directories)
    if rclone lsd "$remote_name:" &>/dev/null; then
        echo "✓ Connection to $remote_name successful"
        return 0
    else
        echo "✗ Failed to connect to $remote_name"
        return 1
    fi
}

# Get the type of an rclone remote (dropbox, drive, onedrive, etc.)
# Args:
#   $1 - Remote name
# Returns: Remote type string (e.g., "dropbox", "drive")
get_remote_type() {
    local remote_name="$1"
    # rclone listremotes --long shows: "remotename: type"
    rclone listremotes --long 2>/dev/null | grep "^$remote_name:" | awk '{print $2}'
}

# ==============================================================================
# CLOUD UPLOAD FUNCTIONS
# ==============================================================================

# Upload compressed database backups to cloud storage
# Args:
#   $1 - Local backup directory
#   $2 - Cloud remote name
#   $3 - Cloud destination path
# Returns: 0 on success, non-zero on failure
cloud_upload_databases() {
    local local_dir="$1"
    local cloud_remote="$2"
    local cloud_path="$3"

    # Skip if no databases directory exists
    if [[ ! -d "$local_dir/databases" ]]; then
        return 0
    fi

    echo "Uploading database backups..."
    # Copy only compressed database files
    # --transfers 4: Upload 4 files in parallel
    # --checkers 8: Use 8 threads for checking
    rclone copy "$local_dir/databases/" "$cloud_remote:$cloud_path/databases/" \
        --include "*.db.gz" \
        --transfers 4 \
        --checkers 8 \
        --log-file "${LOG_FILE:-/dev/null}" \
        --log-level INFO
}

# Upload critical files (.env, credentials, keys) to cloud storage
# Args:
#   $1 - Local backup directory
#   $2 - Cloud remote name
#   $3 - Cloud destination path
# Returns: 0 on success, non-zero on failure
cloud_upload_critical() {
    local local_dir="$1"
    local cloud_remote="$2"
    local cloud_path="$3"

    # Skip if no files directory exists
    if [[ ! -d "$local_dir/files" ]]; then
        return 0
    fi

    echo "Uploading critical files..."
    # Upload only sensitive files that shouldn't be in Git
    rclone copy "$local_dir/files/" "$cloud_remote:$cloud_path/files/" \
        --include ".env*" \
        --include "credentials.*" \
        --include "*.pem" \
        --include "*.key" \
        --transfers 4 \
        --checkers 8 \
        --log-file "${LOG_FILE:-/dev/null}" \
        --log-level INFO
}

# Upload all project files to cloud storage
# Args:
#   $1 - Local backup directory
#   $2 - Cloud remote name
#   $3 - Cloud destination path
# Returns: 0 on success, non-zero on failure
# Note: Excludes large/unnecessary directories (node_modules, .git, logs)
cloud_upload_files() {
    local local_dir="$1"
    local cloud_remote="$2"
    local cloud_path="$3"

    # Skip if no files directory exists
    if [[ ! -d "$local_dir/files" ]]; then
        return 0
    fi

    echo "Uploading all project files..."
    # Upload all files except large/unnecessary directories
    rclone copy "$local_dir/files/" "$cloud_remote:$cloud_path/files/" \
        --exclude "node_modules/**" \
        --exclude ".git/**" \
        --exclude "*.log" \
        --transfers 4 \
        --checkers 8 \
        --log-file "${LOG_FILE:-/dev/null}" \
        --log-level INFO
}

# Main cloud upload function
# Uploads based on configuration environment variables:
#   - LOCAL_BACKUP_DIR or BACKUP_DIR: Local backup directory
#   - CLOUD_REMOTE_NAME: rclone remote name
#   - CLOUD_BACKUP_PATH: Cloud destination path
#   - CLOUD_SYNC_DATABASES: Upload databases (true/false)
#   - CLOUD_SYNC_CRITICAL: Upload critical files (true/false)
#   - CLOUD_SYNC_FILES: Upload all files (true/false)
# Returns: 0 on success, 1 on failure
cloud_upload() {
    local local_dir="${LOCAL_BACKUP_DIR:-$BACKUP_DIR}"
    local cloud_remote="${CLOUD_REMOTE_NAME}"
    local cloud_path="${CLOUD_BACKUP_PATH}"

    # Validate required configuration
    if [[ -z "$cloud_remote" ]] || [[ -z "$cloud_path" ]]; then
        echo "✗ Cloud configuration missing"
        return 1
    fi

    # Check rclone is installed
    if ! check_rclone_installed; then
        echo "✗ rclone not installed"
        return 1
    fi

    # Test connection before attempting upload
    if ! test_rclone_connection "$cloud_remote" 2>&1 | grep -q "successful"; then
        echo "✗ Cannot connect to cloud storage"
        return 1
    fi

    # Track if any upload failed
    local upload_failed=0

    # Upload databases if configured (recommended)
    if [[ "${CLOUD_SYNC_DATABASES:-true}" == "true" ]]; then
        cloud_upload_databases "$local_dir" "$cloud_remote" "$cloud_path" || upload_failed=1
    fi

    # Upload critical files if configured (recommended)
    if [[ "${CLOUD_SYNC_CRITICAL:-true}" == "true" ]]; then
        cloud_upload_critical "$local_dir" "$cloud_remote" "$cloud_path" || upload_failed=1
    fi

    # Upload all files if configured (optional, can be large)
    if [[ "${CLOUD_SYNC_FILES:-false}" == "true" ]]; then
        cloud_upload_files "$local_dir" "$cloud_remote" "$cloud_path" || upload_failed=1
    fi

    # Report results and update status file
    if [[ $upload_failed -eq 0 ]]; then
        echo "✓ Cloud upload complete"
        # Record successful upload time (Unix timestamp)
        echo "$(date +%s)" > "${STATE_DIR:-$HOME/.claudecode-backups/state}/.last-cloud-upload"
        return 0
    else
        echo "⚠ Cloud upload completed with errors"
        return 1
    fi
}

# Run cloud upload in background (non-blocking)
# Usage: cloud_upload_background
# Note: Output is discarded, runs in subshell
cloud_upload_background() {
    (cloud_upload > /dev/null 2>&1 &)
}

# ==============================================================================
# CLOUD STATUS
# ==============================================================================

# Get time since last successful cloud upload
# Returns: Human-readable time string ("never", "5 minutes ago", etc.)
# Uses: STATE_DIR/.last-cloud-upload file (Unix timestamp)
get_cloud_status() {
    local cloud_remote="${CLOUD_REMOTE_NAME}"
    local last_upload_file="${STATE_DIR:-$HOME/.claudecode-backups/state}/.last-cloud-upload"

    # Return "never" if no upload has occurred
    if [[ ! -f "$last_upload_file" ]]; then
        echo "never"
        return
    fi

    # Calculate time difference
    local last_upload=$(cat "$last_upload_file")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_upload))

    # Format as human-readable time
    if [[ $time_diff -lt 3600 ]]; then
        # Less than 1 hour: show minutes
        echo "$(( time_diff / 60 )) minutes ago"
    elif [[ $time_diff -lt 86400 ]]; then
        # Less than 1 day: show hours
        echo "$(( time_diff / 3600 )) hours ago"
    else
        # 1+ days: show days
        echo "$(( time_diff / 86400 )) days ago"
    fi
}

# Validate cloud backup configuration
# Checks:
#   - CLOUD_ENABLED setting
#   - rclone installation
#   - Remote name configured
#   - Remote exists in rclone config
#   - Backup path configured
# Returns: 0 if valid (or cloud disabled), error count otherwise
validate_cloud_config() {
    local errors=0

    # Skip validation if cloud backup is disabled
    if [[ "${CLOUD_ENABLED:-false}" != "true" ]]; then
        return 0
    fi

    # Check rclone installed
    if ! check_rclone_installed; then
        echo "⚠ Cloud backup enabled but rclone not installed"
        errors=1
    fi

    # Check remote name is set
    if [[ -z "${CLOUD_REMOTE_NAME:-}" ]]; then
        echo "⚠ Cloud remote name not configured"
        errors=1
    fi

    # Check remote exists in rclone config
    if [[ -n "${CLOUD_REMOTE_NAME:-}" ]]; then
        if ! list_rclone_remotes | grep -q "^${CLOUD_REMOTE_NAME}$"; then
            echo "⚠ Cloud remote '$CLOUD_REMOTE_NAME' not found in rclone config"
            errors=1
        fi
    fi

    # Check backup path is set
    if [[ -z "${CLOUD_BACKUP_PATH:-}" ]]; then
        echo "⚠ Cloud backup path not configured"
        errors=1
    fi

    return $errors
}

# ==============================================================================
# CLOUD BACKUP ROTATION (v2.3.0)
# ==============================================================================

# Default retention settings
CLOUD_RETENTION_DAYS="${CLOUD_RETENTION_DAYS:-30}"
CLOUD_MIN_BACKUP_COUNT="${CLOUD_MIN_BACKUP_COUNT:-5}"

# Rotate (delete) old cloud backups based on retention policy
# Args:
#   $1 - dry_run: "true" to preview without deleting
# Returns: Number of files deleted (or would delete in dry-run)
cloud_rotate_backups() {
    local dry_run="${1:-false}"
    local deleted_count=0

    # Skip if cloud not enabled
    if [[ "${CLOUD_ENABLED:-false}" != "true" ]]; then
        echo "Cloud backup not enabled"
        return 0
    fi

    # Validate rclone is available
    if ! check_rclone_installed; then
        echo "rclone not installed"
        return 1
    fi

    local cloud_remote="${CLOUD_REMOTE_NAME}"
    local cloud_path="${CLOUD_BACKUP_PATH}"

    if [[ -z "$cloud_remote" ]] || [[ -z "$cloud_path" ]]; then
        echo "Cloud remote or path not configured"
        return 1
    fi

    local full_path="${cloud_remote}:${cloud_path}"

    echo "Scanning cloud backups for rotation..."
    echo "Retention: $CLOUD_RETENTION_DAYS days"
    echo "Minimum backups to keep: $CLOUD_MIN_BACKUP_COUNT"
    echo ""

    # Get list of all backup files with modification times
    local backup_list
    backup_list=$(rclone lsl "$full_path" 2>/dev/null | sort -k2,3 -r) || {
        echo "Failed to list cloud backups"
        return 1
    }

    if [[ -z "$backup_list" ]]; then
        echo "No cloud backups found"
        return 0
    fi

    # Count total backups
    local total_count
    total_count=$(echo "$backup_list" | wc -l | tr -d ' ')
    echo "Found $total_count cloud backup files"

    # Calculate cutoff date (Unix timestamp)
    local cutoff_date
    cutoff_date=$(date -v-${CLOUD_RETENTION_DAYS}d +%s 2>/dev/null || \
                  date -d "-${CLOUD_RETENTION_DAYS} days" +%s 2>/dev/null)

    # Track files to delete
    local files_to_delete=()
    local kept_count=0

    while IFS= read -r line; do
        # Parse rclone lsl output: size date time filename
        local file_date file_time filename
        file_date=$(echo "$line" | awk '{print $2}')
        file_time=$(echo "$line" | awk '{print $3}')
        filename=$(echo "$line" | awk '{print $4}')

        if [[ -z "$filename" ]]; then
            continue
        fi

        # Parse file date to Unix timestamp
        local file_timestamp
        file_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$file_date $file_time" +%s 2>/dev/null || \
                        date -d "$file_date $file_time" +%s 2>/dev/null || echo "0")

        if [[ "$file_timestamp" -eq 0 ]]; then
            # Can't parse date, keep the file
            kept_count=$((kept_count + 1))
            continue
        fi

        # Check if file is older than retention period
        if [[ "$file_timestamp" -lt "$cutoff_date" ]]; then
            # Check if we still need to keep minimum backups
            if [[ $kept_count -ge $CLOUD_MIN_BACKUP_COUNT ]]; then
                files_to_delete+=("$filename")
            else
                kept_count=$((kept_count + 1))
            fi
        else
            kept_count=$((kept_count + 1))
        fi
    done <<< "$backup_list"

    # Delete old files
    local delete_count=${#files_to_delete[@]}
    if [[ $delete_count -eq 0 ]]; then
        echo "No old backups to delete"
        return 0
    fi

    echo ""
    echo "Files to delete: $delete_count"

    for filename in "${files_to_delete[@]}"; do
        if [[ "$dry_run" == "true" ]]; then
            echo "  [DRY RUN] Would delete: $filename"
        else
            echo "  Deleting: $filename"
            if rclone deletefile "${full_path}/${filename}" 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
            else
                echo "    Failed to delete: $filename"
            fi
        fi
    done

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        echo "Would delete $delete_count files"
    else
        echo "Deleted $deleted_count files"
    fi

    return 0
}

# Get cloud backup statistics
# Returns: JSON-formatted statistics
cloud_get_stats() {
    if [[ "${CLOUD_ENABLED:-false}" != "true" ]]; then
        echo '{"enabled": false}'
        return 0
    fi

    local cloud_remote="${CLOUD_REMOTE_NAME}"
    local cloud_path="${CLOUD_BACKUP_PATH}"
    local full_path="${cloud_remote}:${cloud_path}"

    # Get size and count
    local size_output
    size_output=$(rclone size "$full_path" 2>/dev/null) || {
        echo '{"enabled": true, "error": "Failed to get stats"}'
        return 1
    }

    local total_size=$(echo "$size_output" | grep "Total size:" | awk '{print $3, $4}')
    local total_count=$(echo "$size_output" | grep "Total objects:" | awk '{print $3}')

    echo "{\"enabled\": true, \"size\": \"$total_size\", \"count\": $total_count, \"retention_days\": $CLOUD_RETENTION_DAYS}"
}
