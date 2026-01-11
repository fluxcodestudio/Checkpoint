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
