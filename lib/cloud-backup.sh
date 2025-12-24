#!/bin/bash
# Cloud Backup Library
# Handles cloud storage uploads via rclone

# ==============================================================================
# RCLONE DETECTION & INSTALLATION
# ==============================================================================

check_rclone_installed() {
    command -v rclone &>/dev/null
}

install_rclone() {
    echo "Installing rclone..."

    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS
        if command -v brew &>/dev/null; then
            brew install rclone
        else
            curl https://rclone.org/install.sh | bash
        fi
    else
        # Linux
        curl https://rclone.org/install.sh | bash
    fi

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

list_rclone_remotes() {
    rclone listremotes 2>/dev/null | sed 's/:$//'
}

setup_rclone_remote() {
    local provider="$1"

    echo ""
    echo "Setting up rclone for $provider..."
    echo "This will open a browser window for authentication."
    echo ""

    rclone config
}

test_rclone_connection() {
    local remote_name="$1"

    if [[ -z "$remote_name" ]]; then
        echo "✗ No remote name specified"
        return 1
    fi

    # Test by listing root directory
    if rclone lsd "$remote_name:" &>/dev/null; then
        echo "✓ Connection to $remote_name successful"
        return 0
    else
        echo "✗ Failed to connect to $remote_name"
        return 1
    fi
}

get_remote_type() {
    local remote_name="$1"
    rclone listremotes --long 2>/dev/null | grep "^$remote_name:" | awk '{print $2}'
}

# ==============================================================================
# CLOUD UPLOAD FUNCTIONS
# ==============================================================================

cloud_upload_databases() {
    local local_dir="$1"
    local cloud_remote="$2"
    local cloud_path="$3"

    if [[ ! -d "$local_dir/databases" ]]; then
        return 0
    fi

    echo "Uploading database backups..."
    rclone copy "$local_dir/databases/" "$cloud_remote:$cloud_path/databases/" \
        --include "*.db.gz" \
        --transfers 4 \
        --checkers 8 \
        --log-file "${LOG_FILE:-/dev/null}" \
        --log-level INFO
}

cloud_upload_critical() {
    local local_dir="$1"
    local cloud_remote="$2"
    local cloud_path="$3"

    if [[ ! -d "$local_dir/files" ]]; then
        return 0
    fi

    echo "Uploading critical files..."
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

cloud_upload_files() {
    local local_dir="$1"
    local cloud_remote="$2"
    local cloud_path="$3"

    if [[ ! -d "$local_dir/files" ]]; then
        return 0
    fi

    echo "Uploading all project files..."
    rclone copy "$local_dir/files/" "$cloud_remote:$cloud_path/files/" \
        --exclude "node_modules/**" \
        --exclude ".git/**" \
        --exclude "*.log" \
        --transfers 4 \
        --checkers 8 \
        --log-file "${LOG_FILE:-/dev/null}" \
        --log-level INFO
}

cloud_upload() {
    local local_dir="${LOCAL_BACKUP_DIR:-$BACKUP_DIR}"
    local cloud_remote="${CLOUD_REMOTE_NAME}"
    local cloud_path="${CLOUD_BACKUP_PATH}"

    # Validate configuration
    if [[ -z "$cloud_remote" ]] || [[ -z "$cloud_path" ]]; then
        echo "✗ Cloud configuration missing"
        return 1
    fi

    # Check rclone installed
    if ! check_rclone_installed; then
        echo "✗ rclone not installed"
        return 1
    fi

    # Test connection
    if ! test_rclone_connection "$cloud_remote" 2>&1 | grep -q "successful"; then
        echo "✗ Cannot connect to cloud storage"
        return 1
    fi

    # Upload based on configuration
    local upload_failed=0

    if [[ "${CLOUD_SYNC_DATABASES:-true}" == "true" ]]; then
        cloud_upload_databases "$local_dir" "$cloud_remote" "$cloud_path" || upload_failed=1
    fi

    if [[ "${CLOUD_SYNC_CRITICAL:-true}" == "true" ]]; then
        cloud_upload_critical "$local_dir" "$cloud_remote" "$cloud_path" || upload_failed=1
    fi

    if [[ "${CLOUD_SYNC_FILES:-false}" == "true" ]]; then
        cloud_upload_files "$local_dir" "$cloud_remote" "$cloud_path" || upload_failed=1
    fi

    if [[ $upload_failed -eq 0 ]]; then
        echo "✓ Cloud upload complete"
        echo "$(date +%s)" > "${STATE_DIR:-$HOME/.claudecode-backups/state}/.last-cloud-upload"
        return 0
    else
        echo "⚠ Cloud upload completed with errors"
        return 1
    fi
}

cloud_upload_background() {
    (cloud_upload > /dev/null 2>&1 &)
}

# ==============================================================================
# CLOUD STATUS
# ==============================================================================

get_cloud_status() {
    local cloud_remote="${CLOUD_REMOTE_NAME}"
    local last_upload_file="${STATE_DIR:-$HOME/.claudecode-backups/state}/.last-cloud-upload"

    if [[ ! -f "$last_upload_file" ]]; then
        echo "never"
        return
    fi

    local last_upload=$(cat "$last_upload_file")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_upload))

    if [[ $time_diff -lt 3600 ]]; then
        echo "$(( time_diff / 60 )) minutes ago"
    elif [[ $time_diff -lt 86400 ]]; then
        echo "$(( time_diff / 3600 )) hours ago"
    else
        echo "$(( time_diff / 86400 )) days ago"
    fi
}

validate_cloud_config() {
    local errors=0

    # Check if cloud enabled
    if [[ "${CLOUD_ENABLED:-false}" != "true" ]]; then
        return 0
    fi

    # Check rclone installed
    if ! check_rclone_installed; then
        echo "⚠ Cloud backup enabled but rclone not installed"
        errors=1
    fi

    # Check remote name set
    if [[ -z "${CLOUD_REMOTE_NAME:-}" ]]; then
        echo "⚠ Cloud remote name not configured"
        errors=1
    fi

    # Check remote exists
    if [[ -n "${CLOUD_REMOTE_NAME:-}" ]]; then
        if ! list_rclone_remotes | grep -q "^${CLOUD_REMOTE_NAME}$"; then
            echo "⚠ Cloud remote '$CLOUD_REMOTE_NAME' not found in rclone config"
            errors=1
        fi
    fi

    # Check backup path set
    if [[ -z "${CLOUD_BACKUP_PATH:-}" ]]; then
        echo "⚠ Cloud backup path not configured"
        errors=1
    fi

    return $errors
}
