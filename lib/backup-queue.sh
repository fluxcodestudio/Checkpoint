#!/usr/bin/env bash
# Checkpoint - Backup Queue Library
# Queues failed cloud syncs for retry when connectivity restores

set -euo pipefail

# Queue directory location
BACKUP_QUEUE_DIR="${BACKUP_QUEUE_DIR:-$HOME/.claudecode-backups/queue}"

# Initialize queue directory
init_backup_queue() {
    mkdir -p "$BACKUP_QUEUE_DIR"
}

# Add backup to sync queue
# Args: $1 = project_name, $2 = backup_dir, $3 = sync_type (rclone|cloud_folder)
enqueue_backup_sync() {
    local project_name="$1"
    local backup_dir="$2"
    local sync_type="${3:-rclone}"
    local timestamp=$(date +%s)
    local queue_file="$BACKUP_QUEUE_DIR/${timestamp}_${project_name}.queue"

    init_backup_queue

    # Write queue entry as simple key=value
    cat > "$queue_file" << EOF
PROJECT_NAME=$project_name
BACKUP_DIR=$backup_dir
SYNC_TYPE=$sync_type
QUEUED_AT=$timestamp
RETRY_COUNT=0
EOF

    echo "$queue_file"
}

# List pending queue entries
# Returns: paths to queue files, oldest first
list_queue_entries() {
    init_backup_queue
    find "$BACKUP_QUEUE_DIR" -name "*.queue" -type f 2>/dev/null | sort
}

# Get queue entry count
get_queue_count() {
    list_queue_entries | wc -l | tr -d ' '
}

# Read queue entry into variables
# Args: $1 = queue_file
# Sets: PROJECT_NAME, BACKUP_DIR, SYNC_TYPE, QUEUED_AT, RETRY_COUNT
read_queue_entry() {
    local queue_file="$1"
    if [[ -f "$queue_file" ]]; then
        source "$queue_file"
        return 0
    fi
    return 1
}

# Update retry count in queue entry
# Args: $1 = queue_file
increment_retry_count() {
    local queue_file="$1"
    if [[ -f "$queue_file" ]]; then
        local current_count=$(grep "^RETRY_COUNT=" "$queue_file" | cut -d= -f2)
        local new_count=$((current_count + 1))
        sed -i '' "s/^RETRY_COUNT=.*/RETRY_COUNT=$new_count/" "$queue_file"
    fi
}

# Remove queue entry (after successful sync)
# Args: $1 = queue_file
dequeue_entry() {
    local queue_file="$1"
    rm -f "$queue_file"
}

# Check if queue has entries
has_pending_queue() {
    [[ $(get_queue_count) -gt 0 ]]
}

# Process pending queue entries
# Attempts sync for each entry, removes on success, increments retry on failure
# Args: $1 = max_entries (optional, default 10)
process_backup_queue() {
    local max_entries="${1:-10}"
    local processed=0
    local succeeded=0
    local failed=0

    # Load cloud-backup for rclone functions
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$lib_dir/cloud-backup.sh" 2>/dev/null || true

    while IFS= read -r queue_file; do
        [[ -z "$queue_file" ]] && continue
        ((processed >= max_entries)) && break

        # Load entry variables
        if ! read_queue_entry "$queue_file"; then
            dequeue_entry "$queue_file"  # Corrupt entry, remove
            continue
        fi

        local sync_success=false

        # Try rclone sync
        if [[ "$SYNC_TYPE" == "rclone" ]] && [[ "${CLOUD_ENABLED:-false}" == "true" ]]; then
            # Set required vars for cloud_upload
            export LOCAL_BACKUP_DIR="$BACKUP_DIR"

            if cloud_upload 2>/dev/null; then
                sync_success=true
            fi
        fi

        if $sync_success; then
            dequeue_entry "$queue_file"
            ((succeeded++))
        else
            increment_retry_count "$queue_file"
            ((failed++))

            # Max 5 retries, then give up (but keep in queue for manual review)
            local retry_count=$(grep "^RETRY_COUNT=" "$queue_file" | cut -d= -f2)
            if [[ $retry_count -ge 5 ]]; then
                mv "$queue_file" "${queue_file}.failed"
            fi
        fi

        ((processed++))
    done < <(list_queue_entries)

    echo "Queue processed: $processed entries, $succeeded synced, $failed failed"
}
