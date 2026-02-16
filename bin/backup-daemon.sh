#!/usr/bin/env bash
# Checkpoint - Main Backup Daemon
# Handles database backups, file backups, archiving, and cleanup
# Can be triggered by: daemon scheduler (hourly), Claude Code hooks (on prompt), or manually

set -euo pipefail

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Find config file (check project root first, then script directory)
CONFIG_FILE=""
if [ -f "$PWD/.backup-config.sh" ]; then
    CONFIG_FILE="$PWD/.backup-config.sh"
elif [ -f "$SCRIPT_DIR/../templates/backup-config.sh" ]; then
    CONFIG_FILE="$SCRIPT_DIR/../templates/backup-config.sh"
else
    echo "Configuration file not found. Run install.sh first." >&2
    exit 1
fi

source "$CONFIG_FILE"

# Apply global defaults from ~/.config/checkpoint/config.sh
# (provides fallbacks for any variable not set in per-project config)
if type apply_global_defaults &>/dev/null; then
    apply_global_defaults
elif [ -f "$LIB_DIR/core/config.sh" ]; then
    source "$LIB_DIR/core/config.sh"
    apply_global_defaults
fi

# Apply defaults for optional variables (Bash 3.2 compatible)
# Backup directories
DATABASE_DIR="${DATABASE_DIR:-$BACKUP_DIR/databases}"
FILES_DIR="${FILES_DIR:-$BACKUP_DIR/files}"
ARCHIVED_DIR="${ARCHIVED_DIR:-$BACKUP_DIR/archived}"

# Drive verification
DRIVE_VERIFICATION_ENABLED="${DRIVE_VERIFICATION_ENABLED:-false}"
DRIVE_MARKER_FILE="${DRIVE_MARKER_FILE:-$PROJECT_DIR/.backup-drive-marker}"

# Logging
LOG_FILE="${LOG_FILE:-$BACKUP_DIR/backup.log}"
FALLBACK_LOG="${FALLBACK_LOG:-$HOME/.claudecode-backups/logs/backup-fallback.log}"

# State management
STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"
BACKUP_TIME_STATE="${BACKUP_TIME_STATE:-$STATE_DIR/${PROJECT_NAME}/.last-backup-time}"
SESSION_FILE="${SESSION_FILE:-$STATE_DIR/${PROJECT_NAME}/.current-session-time}"
DB_STATE_FILE="${DB_STATE_FILE:-$BACKUP_DIR/.backup-state}"

# Git options
AUTO_COMMIT_ENABLED="${AUTO_COMMIT_ENABLED:-false}"
GIT_AUTO_PUSH_ENABLED="${GIT_AUTO_PUSH_ENABLED:-false}"
GIT_PUSH_INTERVAL="${GIT_PUSH_INTERVAL:-7200}"
GIT_PUSH_BRANCH="${GIT_PUSH_BRANCH:-}"
GIT_PUSH_REMOTE="${GIT_PUSH_REMOTE:-origin}"
GIT_PUSH_STATE="${GIT_PUSH_STATE:-$STATE_DIR/${PROJECT_NAME}/.last-git-push}"

# File size limits
MAX_BACKUP_FILE_SIZE="${MAX_BACKUP_FILE_SIZE:-104857600}"
BACKUP_LARGE_FILES="${BACKUP_LARGE_FILES:-false}"

# Timestamps
USE_UTC_TIMESTAMPS="${USE_UTC_TIMESTAMPS:-false}"

# Load cloud backup library if cloud enabled
if [[ -f "$LIB_DIR/cloud-backup.sh" ]] && [[ "${CLOUD_ENABLED:-false}" == "true" ]]; then
    source "$LIB_DIR/cloud-backup.sh"
fi

# Core backup library (provides has_changes, get_changed_files_fast)
if [ -f "$LIB_DIR/backup-lib.sh" ]; then
    source "$LIB_DIR/backup-lib.sh"
fi

# Retention policy library (for tiered cleanup)
if [ -f "$LIB_DIR/retention-policy.sh" ]; then
    source "$LIB_DIR/retention-policy.sh"
fi

# Scheduling library (for cron-style schedules)
source "$LIB_DIR/features/scheduling.sh" 2>/dev/null || true

# Storage monitor (pre-backup disk space checks)
source "$LIB_DIR/features/storage-monitor.sh" 2>/dev/null || true

# ==============================================================================
# STRUCTURED LOGGING INITIALIZATION
# ==============================================================================

# Initialize structured logging (logging.sh loaded via backup-lib.sh)
_init_checkpoint_logging
log_set_context "daemon"

# Parse CLI flags for log level (--debug, --trace, --quiet)
parse_log_flags "$@"

# SIGUSR1 debug toggle: send `kill -USR1 <daemon_pid>` to toggle debug logging
trap '_toggle_debug_level' USR1

log_info "Daemon starting, PID=$$, project=$PROJECT_NAME"
log_debug "Config: LOG_FILE=$LOG_FILE, BACKUP_DIR=$BACKUP_DIR"

# Tiered cleanup interval (in daemon cycles, e.g., 6 = every 6 hours if hourly daemon)
CLEANUP_INTERVAL="${CLEANUP_INTERVAL:-6}"
CLEANUP_COUNTER=0

# Heartbeat configuration
HEARTBEAT_DIR="${HEARTBEAT_DIR:-$HOME/.checkpoint}"
HEARTBEAT_FILE="${HEARTBEAT_FILE:-$HEARTBEAT_DIR/daemon.heartbeat}"

# ==============================================================================
# ORPHAN DETECTION (Issue #8)
# ==============================================================================
# Check if project still exists - self-disable if deleted

if [ ! -d "$PROJECT_DIR" ]; then
    log_error "Project directory no longer exists: $PROJECT_DIR"
    log_warn "Daemon appears to be orphaned"
    echo "  Project directory no longer exists: $PROJECT_DIR" >&2
    echo "   This daemon appears to be orphaned." >&2

    # Source daemon-manager.sh for cross-platform removal
    if [ -f "$LIB_DIR/platform/daemon-manager.sh" ]; then
        source "$LIB_DIR/platform/daemon-manager.sh"
        echo "   Attempting to remove orphaned daemon..." >&2
        log_info "Attempting to remove orphaned daemon: $PROJECT_NAME"
        if uninstall_daemon "$PROJECT_NAME" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
            echo "   Orphaned daemon removed: $PROJECT_NAME" >&2
            log_info "Orphaned daemon removed: $PROJECT_NAME"
        else
            echo "   Failed to remove daemon. Run: uninstall.sh --cleanup-orphans" >&2
            log_error "Failed to remove orphaned daemon: $PROJECT_NAME"
        fi
    fi

    # Clean up state files for this project
    STATE_PROJECT_DIR="$HOME/.claudecode-backups/state/${PROJECT_NAME}"
    if [ -d "$STATE_PROJECT_DIR" ]; then
        rm -rf "$STATE_PROJECT_DIR"
        log_info "Cleaned up state files for: $PROJECT_NAME"
        echo "   Cleaned up state files for: $PROJECT_NAME" >&2
    fi

    # Clean up lock files
    LOCK_DIR="$HOME/.claudecode-backups/locks/${PROJECT_NAME}.lock"
    if [ -d "$LOCK_DIR" ]; then
        rm -rf "$LOCK_DIR"
    fi

    exit 0  # Exit gracefully, not an error
fi

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Write heartbeat file with current status
# Args: $1=status (healthy|syncing|error|stopped), $2=error_message (optional)
write_heartbeat() {
    local status="${1:-healthy}"
    local error_msg="${2:-}"
    local timestamp
    local last_backup_time
    local last_backup_files

    timestamp=$(date +%s)
    last_backup_time=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
    last_backup_files=$(find "$FILES_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')

    mkdir -p "$HEARTBEAT_DIR"

    # Build sync progress fields if running under backup-all-projects.sh
    local sync_fields=""
    if [[ -n "${CHECKPOINT_SYNC_TOTAL:-}" ]]; then
        sync_fields=",
  \"syncing_project_index\": ${CHECKPOINT_SYNC_INDEX:-0},
  \"syncing_total_projects\": ${CHECKPOINT_SYNC_TOTAL:-0},
  \"syncing_current_project\": \"${CHECKPOINT_SYNC_PROJECT:-}\",
  \"syncing_backed_up\": ${CHECKPOINT_SYNC_BACKED_UP:-0},
  \"syncing_failed\": ${CHECKPOINT_SYNC_FAILED:-0},
  \"syncing_skipped\": ${CHECKPOINT_SYNC_SKIPPED:-0}"
    fi

    # Write JSON heartbeat file atomically (temp+rename prevents partial reads)
    local tmp_file="${HEARTBEAT_DIR}/.heartbeat.tmp.$$"
    cat > "$tmp_file" <<EOF
{
  "timestamp": $timestamp,
  "status": "$status",
  "project": "$PROJECT_NAME",
  "last_backup": $last_backup_time,
  "last_backup_files": $last_backup_files,
  "error": ${error_msg:+\"$error_msg\"}${error_msg:-null},
  "pid": $$${sync_fields}
}
EOF
    mv "$tmp_file" "$HEARTBEAT_FILE"
}

# Check if external drive is mounted (if verification enabled)
check_drive() {
    if [ "$DRIVE_VERIFICATION_ENABLED" = false ]; then
        return 0  # Skip check if disabled
    fi

    # Check if marker file exists
    if [ ! -f "$DRIVE_MARKER_FILE" ]; then
        return 1
    fi

    return 0
}

# Graceful log function (works even if drive disconnected)
# NOTE: This is the legacy CLI output function for the daemon.
# Structured logging goes to log_info/warn/error via logging.sh.
daemon_log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"

    if check_drive && [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "$message" | tee -a "$LOG_FILE"
    else
        # Drive not connected, log to fallback location
        mkdir -p "$(dirname "$FALLBACK_LOG")"
        echo "$message" >> "$FALLBACK_LOG"
        echo "$message"  # Still print to stdout
    fi

    # Also write to structured log
    log_info "$1"
}

# Get database state (size + modification time)
get_db_state() {
    if [ -z "${DB_PATH:-}" ] || [ ! -f "${DB_PATH:-}" ]; then
        echo "0:0"
        return
    fi

    size=$(get_file_size "$DB_PATH")
    mtime=$(get_file_mtime "$DB_PATH")
    echo "$size:$mtime"
}

# Check if database changed since last backup
db_changed() {
    [ -z "${DB_PATH:-}" ] && return 1  # No database configured

    current_state=$(get_db_state)

    if [ ! -f "$DB_STATE_FILE" ]; then
        echo "$current_state" > "$DB_STATE_FILE"
        return 0  # First run, consider changed
    fi

    last_state=$(cat "$DB_STATE_FILE")

    if [ "$current_state" != "$last_state" ]; then
        echo "$current_state" > "$DB_STATE_FILE"
        return 0  # Changed
    fi

    return 1  # Not changed
}

# ==============================================================================
# BACKUP FUNCTIONS
# ==============================================================================

backup_database() {
    if [ -z "${DB_PATH:-}" ] || [ ! -f "${DB_PATH:-}" ]; then
        return 0  # No database to backup
    fi

    daemon_log "Backing up database: $PROJECT_NAME"
    log_debug "Database path: $DB_PATH, type: $DB_TYPE"

    # Human-readable timestamp with PID suffix to prevent collisions
    timestamp=$(date '+%m.%d.%y - %H:%M')
    backup_file="$DATABASE_DIR/${PROJECT_NAME} - ${timestamp}.db.gz"

    # SQLite backup: copy + compress with proper cleanup
    if [ "$DB_TYPE" = "sqlite" ]; then
        # Use mktemp for secure temp file (not world-readable /tmp)
        local temp_db
        temp_db=$(mktemp -t "${PROJECT_NAME}_backup.XXXXXX.db") || {
            daemon_log "Failed to create temp file"
            log_error "Failed to create temp file for database backup"
            return 1
        }

        # Trap to ensure cleanup on any exit from this function
        trap "rm -f '$temp_db' 2>/dev/null" RETURN

        # Perform backup
        if sqlite3 "$DB_PATH" ".backup '$temp_db'" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
            if gzip -"${COMPRESSION_LEVEL:-6}" -c "$temp_db" > "$backup_file" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                # Verify the backup is valid
                if gunzip -t "$backup_file" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                    size=$(du -h "$backup_file" | cut -f1)
                    daemon_log "Database backup created: ${backup_file##*/} ($size)"
                    rm -f "$temp_db" 2>/dev/null
                    return 0
                else
                    daemon_log "Database backup verification failed"
                    log_error "Database backup verification failed: $backup_file"
                    rm -f "$backup_file" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"
                    rm -f "$temp_db" 2>/dev/null
                    return 1
                fi
            else
                daemon_log "Database compression failed"
                log_error "Database compression failed: $DB_PATH"
                rm -f "$temp_db" 2>/dev/null
                return 1
            fi
        else
            daemon_log "SQLite backup command failed"
            log_error "SQLite backup command failed: $DB_PATH"
            rm -f "$temp_db" 2>/dev/null
            return 1
        fi
    else
        daemon_log "Unsupported database type: $DB_TYPE"
        log_warn "Unsupported database type: $DB_TYPE"
        return 1
    fi
}

backup_changed_files() {
    daemon_log "Checking for changed files..."
    log_debug "Scanning for file changes in $PROJECT_DIR"

    cd "$PROJECT_DIR" || return 1

    # Get list of CHANGED files to backup
    changed_files=$(mktemp)

    # Use parallel git detection if function available (from backup-lib.sh)
    if type get_changed_files_fast &>/dev/null; then
        get_changed_files_fast "$changed_files"
    else
        # Fallback: sequential git commands
        git diff --name-only >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
        git diff --cached --name-only >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
        git ls-files --others --exclude-standard >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
    fi

    # Add critical gitignored files (if enabled)
    if [ "$BACKUP_ENV_FILES" = true ]; then
        find . -maxdepth 3 -type f \( -name ".env" -o -name ".env.*" \) 2>/dev/null | sed 's|^\./||' >> "$changed_files"
    fi

    if [ "$BACKUP_CREDENTIALS" = true ]; then
        find . -maxdepth 3 -type f \( \
            -name "*.pem" -o -name "*.key" -o \
            -name "credentials.json" -o -name "secrets.*" -o \
            -name "*.p12" -o -name "*.pfx" \
        \) 2>/dev/null | sed 's|^\./||' >> "$changed_files"
    fi

    if [ "$BACKUP_IDE_SETTINGS" = true ]; then
        [ -f ".vscode/settings.json" ] && echo ".vscode/settings.json" >> "$changed_files"
        [ -f ".vscode/launch.json" ] && echo ".vscode/launch.json" >> "$changed_files"
        [ -f ".idea/workspace.xml" ] && echo ".idea/workspace.xml" >> "$changed_files"
    fi

    if [ "$BACKUP_LOCAL_NOTES" = true ]; then
        find . -maxdepth 2 -type f \( \
            -name "NOTES.md" -o -name "NOTES.txt" -o \
            -name "TODO.local.md" -o -name "*.private.md" \
        \) 2>/dev/null | sed 's|^\./||' >> "$changed_files"
    fi

    if [ "$BACKUP_LOCAL_DATABASES" = true ]; then
        # Exclude the main DB_PATH if it's in the project
        main_db_name=$(basename "${DB_PATH:-}" 2>/dev/null || echo "")
        find . -maxdepth 3 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sql" \) \
            ! -name "$main_db_name" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
    fi

    if [ ! -s "$changed_files" ]; then
        daemon_log "No file changes detected"
        rm "$changed_files"
        return 0
    fi

    timestamp=$(date +%Y%m%d_%H%M%S)
    file_count=0
    archived_count=0

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        [ ! -f "$file" ] && continue  # Skip if not a regular file

        # Skip files inside the backups directory itself
        [[ "$file" == backups/* ]] && continue

        current_file="$FILES_DIR/$file"
        current_dir=$(dirname "$current_file")
        archived_file="$ARCHIVED_DIR/${file}.${timestamp}"
        archived_dir=$(dirname "$archived_file")

        # Create directories if needed
        mkdir -p "$current_dir"

        # Check if file changed (compare with current backup)
        if [ -f "$current_file" ]; then
            if ! cmp -s "$file" "$current_file"; then
                # File changed - archive old version
                mkdir -p "$archived_dir"
                mv "$current_file" "$archived_file"
                ((archived_count++)) || true
                # Copy new version
                cp "$file" "$current_file"
                ((file_count++)) || true
                log_trace "Updated: $file"
            fi
            # else: file unchanged, skip
        else
            # New file - just copy it
            cp "$file" "$current_file"
            ((file_count++)) || true
            log_trace "New file: $file"
        fi

    done < "$changed_files"

    rm "$changed_files"

    if [ $file_count -gt 0 ]; then
        daemon_log "Backed up $file_count files ($archived_count archived)"

        # Auto-commit to git (if enabled)
        if [ "$AUTO_COMMIT_ENABLED" = true ]; then
            if git add -A 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" && \
               git commit -m "$GIT_COMMIT_MESSAGE" -q 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                daemon_log "Changes committed to git"
            fi
        fi
    fi
}

cleanup_old_backups() {
    daemon_log "Cleaning up old backups..."
    log_debug "Starting cleanup: DB_RETENTION_DAYS=$DB_RETENTION_DAYS, FILE_RETENTION_DAYS=$FILE_RETENTION_DAYS"

    local db_removed=0
    local file_removed=0

    # Use single-pass cleanup (performance optimization) or legacy mode
    if [ "${BACKUP_USE_LEGACY_CLEANUP:-false}" = "true" ]; then
        # Legacy cleanup: multiple find traversals
        db_removed=$(find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} 2>/dev/null | wc -l)
        find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"

        file_removed=$(find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} 2>/dev/null | wc -l)
        find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"

        find "$ARCHIVED_DIR" -type d -empty -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"
    elif type cleanup_single_pass &>/dev/null; then
        # Single-pass cleanup (10x faster for large backup sets)
        cleanup_single_pass "$BACKUP_DIR"

        db_removed=${#CLEANUP_EXPIRED_DBS[@]}
        file_removed=${#CLEANUP_EXPIRED_FILES[@]}

        if [ $db_removed -gt 0 ] || [ $file_removed -gt 0 ] || [ ${#CLEANUP_EMPTY_DIRS[@]} -gt 0 ]; then
            cleanup_execute false
        fi
    else
        # Fallback if backup-lib.sh not loaded
        db_removed=$(find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} 2>/dev/null | wc -l)
        find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"

        file_removed=$(find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} 2>/dev/null | wc -l)
        find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"

        find "$ARCHIVED_DIR" -type d -empty -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"
    fi

    if [ "$db_removed" -gt 0 ] || [ "$file_removed" -gt 0 ]; then
        daemon_log "Removed $db_removed old database backups, $file_removed old archived files"
    fi
}

# Run tiered retention cleanup (silent, non-blocking)
run_tiered_cleanup() {
    local log_file="${STATE_DIR:-$HOME/.claudecode-backups/state}/cleanup.log"

    # Only run if retention-policy.sh is available
    if ! command -v find_tiered_pruning_candidates &>/dev/null; then
        return 0
    fi

    log_debug "Starting tiered cleanup for $PROJECT_NAME"

    {
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Starting tiered cleanup for $PROJECT_NAME"

        local total_pruned=0
        local total_freed=0

        # Prune archived files
        if [[ -d "$ARCHIVED_DIR" ]]; then
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                local size=$(get_file_size "$file")
                if rm -f "$file" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                    ((total_pruned++)) || true
                    total_freed=$((total_freed + size))
                fi
            done < <(find_tiered_pruning_candidates "$ARCHIVED_DIR" "*" 2>/dev/null)

            # Clean empty directories
            find "$ARCHIVED_DIR" -type d -empty -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
        fi

        # Prune database backups
        if [[ -d "$DATABASE_DIR" ]]; then
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                local size=$(get_file_size "$file")
                if rm -f "$file" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                    ((total_pruned++)) || true
                    total_freed=$((total_freed + size))
                fi
            done < <(find_tiered_pruning_candidates "$DATABASE_DIR" "*.db.gz" 2>/dev/null)
        fi

        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Cleanup complete: $total_pruned files, $total_freed bytes freed"
    } >> "$log_file" 2>&1 &
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

# Initialize directories (only if drive is connected)
if check_drive; then
    mkdir -p "$DATABASE_DIR" "$FILES_DIR" "$ARCHIVED_DIR"
    touch "$LOG_FILE" 2>/dev/null
fi

daemon_log "Checkpoint - Starting"
daemon_log "Project: $PROJECT_NAME"

# Write initial heartbeat
write_heartbeat "syncing"

# Check if external drive is connected (if verification enabled)
if ! check_drive; then
    daemon_log "External drive not connected or wrong drive"
    daemon_log "Skipping backup cycle, will retry later"
    log_warn "Drive not connected, skipping backup cycle"
    daemon_log "Fallback log: $FALLBACK_LOG"
    write_heartbeat "error" "Drive not connected"
    exit 0  # Exit gracefully
fi

log_debug "Drive verification passed"

# ==============================================================================
# BACKUP EXECUTION WITH FILE LOCKING
# ==============================================================================
# Prevents duplicate backups when daemon and hook run simultaneously
# Uses atomic mkdir for cross-platform compatibility (macOS + Linux)
# Fix: Write PID atomically to prevent race conditions

LOCK_BASE="${HOME}/.claudecode-backups/locks"
LOCK_DIR="${LOCK_BASE}/${PROJECT_NAME}.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"

# Ensure lock base directory exists
mkdir -p "$LOCK_BASE" 2>/dev/null

# Helper function to acquire lock atomically
acquire_lock() {
    # Create temp PID file first (atomic write)
    local temp_pid_file
    temp_pid_file=$(mktemp "${LOCK_BASE}/.pid.XXXXXX") || return 1
    echo $$ > "$temp_pid_file"

    # Try to create lock directory (atomic operation)
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        # Move PID file into lock directory (atomic on same filesystem)
        mv "$temp_pid_file" "$LOCK_PID_FILE" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || {
            rm -f "$temp_pid_file"
            rm -rf "$LOCK_DIR"
            return 1
        }
        return 0
    else
        rm -f "$temp_pid_file"
        return 1
    fi
}

# Try to acquire lock
if acquire_lock; then
    trap 'rm -rf "$LOCK_DIR"' EXIT
    daemon_log "Acquired backup lock (PID: $$)"
else
    # Lock exists - check if it's stale
    if [ -f "$LOCK_PID_FILE" ]; then
        LOCK_PID=$(cat "$LOCK_PID_FILE" 2>/dev/null)
        if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
            # Process is running - lock is valid
            daemon_log "Another backup is currently running (PID: $LOCK_PID), skipping to avoid duplication"
            log_debug "Lock held by PID $LOCK_PID, skipping"
            exit 0
        else
            # Process is dead - lock is stale, clean it up
            daemon_log "Removing stale lock (PID $LOCK_PID not running)"
            log_warn "Removing stale lock, PID $LOCK_PID not running"
            rm -rf "$LOCK_DIR"
            # Try to acquire lock again
            if acquire_lock; then
                trap 'rm -rf "$LOCK_DIR"' EXIT
                daemon_log "Acquired backup lock after cleanup (PID: $$)"
            else
                # Race condition - another process got the lock
                daemon_log "Another backup started simultaneously, skipping"
                log_debug "Lock race condition, skipping"
                exit 0
            fi
        fi
    else
        # Lock directory exists but no PID file - probably stale or race condition
        # Wait briefly and check again (handles the mkdir/mv race window)
        sleep 0.1
        if [ -f "$LOCK_PID_FILE" ]; then
            LOCK_PID=$(cat "$LOCK_PID_FILE" 2>/dev/null)
            if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
                daemon_log "Another backup is currently running (PID: $LOCK_PID), skipping"
                log_debug "Lock held by PID $LOCK_PID after wait, skipping"
                exit 0
            fi
        fi
        # Still no valid PID, clean up and try again
        daemon_log "Removing incomplete lock directory"
        log_warn "Removing incomplete lock directory"
        rm -rf "$LOCK_DIR"
        if acquire_lock; then
            trap 'rm -rf "$LOCK_DIR"' EXIT
            daemon_log "Acquired backup lock after cleanup (PID: $$)"
        else
            daemon_log "Another backup started simultaneously, skipping"
            log_debug "Lock race condition after cleanup, skipping"
            exit 0
        fi
    fi
fi

# Check if backup should run (schedule or interval mode)
mkdir -p "$(dirname "$BACKUP_TIME_STATE")"
LAST_BACKUP=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
NOW=$(date +%s)
DIFF=$((NOW - LAST_BACKUP))

if [[ -n "${BACKUP_SCHEDULE:-}" ]] && type cron_matches_now &>/dev/null; then
    # Schedule mode: check if current time matches cron expression
    if ! cron_matches_now "$BACKUP_SCHEDULE"; then
        daemon_log "Schedule does not match current time (schedule: $BACKUP_SCHEDULE)"
        log_debug "Cron schedule '$BACKUP_SCHEDULE' does not match current time"
        exit 0
    fi
    # Dedup: prevent double-run within same minute
    if [ $DIFF -lt 60 ]; then
        daemon_log "Backup ran ${DIFF}s ago, skipping dedup (schedule mode)"
        log_debug "Schedule dedup: ${DIFF}s < 60s"
        exit 0
    fi
    daemon_log "Schedule matches current time (schedule: $BACKUP_SCHEDULE)"
else
    # Interval mode: existing BACKUP_INTERVAL logic
    if [ $DIFF -lt $BACKUP_INTERVAL ]; then
        # Backup ran recently, skip
        daemon_log "Backup ran ${DIFF}s ago, skipping (interval: ${BACKUP_INTERVAL}s)"
        log_debug "Backup interval not reached: ${DIFF}s < ${BACKUP_INTERVAL}s"
        exit 0
    fi
fi

# Pre-backup storage check (disk space gate)
if type pre_backup_storage_check &>/dev/null; then
    _storage_rc=0
    pre_backup_storage_check "$BACKUP_DIR" || _storage_rc=$?
    if [ "$_storage_rc" -eq 2 ]; then
        daemon_log "Backup skipped: disk critically full"
        log_error "Backup skipped: disk critically full (storage check returned critical)"
        write_heartbeat "error" "Disk critically full"
        echo "$NOW" > "$BACKUP_TIME_STATE"
        exit 0
    elif [ "$_storage_rc" -eq 1 ]; then
        daemon_log "Storage warning: disk space is low, continuing backup"
        log_warn "Storage warning: disk space is low, continuing backup"
    fi
fi

# Fast early-exit: check if any changes exist before full detection
cd "$PROJECT_DIR" || exit 1
if type has_changes &>/dev/null && ! has_changes; then
    # No git/file changes - skip file backup entirely
    # Still check database (it has its own change detection)
    if db_changed; then
        backup_database
    else
        daemon_log "No changes detected (database or files)"
        log_debug "No changes detected, skipping"
        # Update timestamp to prevent immediate re-check
        echo "$NOW" > "$BACKUP_TIME_STATE"
        exit 0
    fi
fi

# Perform backup
if db_changed; then
    backup_database
else
    daemon_log "Database unchanged, skipping backup"
    log_debug "Database unchanged"
fi

backup_changed_files
cleanup_old_backups

# Increment cleanup counter and run tiered cleanup if interval reached
((CLEANUP_COUNTER++)) || true
if [[ $CLEANUP_COUNTER -ge $CLEANUP_INTERVAL ]]; then
    run_tiered_cleanup
    CLEANUP_COUNTER=0
fi

# Update coordination state
echo "$NOW" > "$BACKUP_TIME_STATE"

# Cloud Upload (if enabled)
if [[ "${CLOUD_ENABLED:-false}" == "true" ]] && [[ "${BACKUP_LOCATION:-local}" != "local" ]]; then
    daemon_log "Starting cloud upload..."
    log_info "Starting cloud upload"
    if type cloud_upload_background &>/dev/null; then
        cloud_upload_background
        daemon_log "Cloud upload running in background"
        log_info "Cloud upload running in background"
    else
        daemon_log "Cloud backup library not loaded"
        log_warn "Cloud backup library not loaded"
    fi
fi

# Summary
db_count=$(find "$DATABASE_DIR" -name "*.db.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
current_files=$(find "$FILES_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
archived_files=$(find "$ARCHIVED_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
daemon_log "Databases: $db_count snapshots"
daemon_log "Files: $current_files current, $archived_files archived versions"
daemon_log "Backup cycle complete"
daemon_log "Released backup lock"
log_info "Backup cycle complete: $db_count DB snapshots, $current_files files, $archived_files archived"

# Write final healthy heartbeat
write_heartbeat "healthy"

# Lock is automatically removed by trap on exit (even on crash/kill)
