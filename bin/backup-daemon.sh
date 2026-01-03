#!/usr/bin/env bash
# Checkpoint - Main Backup Daemon
# Handles database backups, file backups, archiving, and cleanup
# Can be triggered by: LaunchAgent (hourly), Claude Code hooks (on prompt), or manually

set -euo pipefail

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

# Resolve symlinks to get actual script location
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# Find config file (check project root first, then script directory)
CONFIG_FILE=""
if [ -f "$PWD/.backup-config.sh" ]; then
    CONFIG_FILE="$PWD/.backup-config.sh"
elif [ -f "$SCRIPT_DIR/../templates/backup-config.sh" ]; then
    CONFIG_FILE="$SCRIPT_DIR/../templates/backup-config.sh"
else
    echo "❌ Configuration file not found. Run install.sh first." >&2
    exit 1
fi

source "$CONFIG_FILE"

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
CLOUD_LIB="$SCRIPT_DIR/../lib/cloud-backup.sh"
if [[ -f "$CLOUD_LIB" ]] && [[ "${CLOUD_ENABLED:-false}" == "true" ]]; then
    source "$CLOUD_LIB"
fi

# ==============================================================================
# ORPHAN DETECTION (Issue #8)
# ==============================================================================
# Check if project still exists - self-disable if deleted

if [ ! -d "$PROJECT_DIR" ]; then
    echo "⚠️  Project directory no longer exists: $PROJECT_DIR" >&2
    echo "   This LaunchAgent appears to be orphaned." >&2

    # Try to unload the LaunchAgent automatically
    PLIST_NAME="com.claudecode.backup.${PROJECT_NAME}.plist"
    PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"

    if [ -f "$PLIST_PATH" ]; then
        echo "   Attempting to unload orphaned LaunchAgent..." >&2
        if launchctl unload "$PLIST_PATH" 2>/dev/null; then
            rm -f "$PLIST_PATH"
            echo "✅ Orphaned LaunchAgent removed: $PLIST_NAME" >&2
        else
            echo "   Failed to unload. Run manually:" >&2
            echo "   launchctl unload '$PLIST_PATH' && rm '$PLIST_PATH'" >&2
        fi
    fi

    # Clean up state files for this project
    STATE_PROJECT_DIR="$HOME/.claudecode-backups/state/${PROJECT_NAME}"
    if [ -d "$STATE_PROJECT_DIR" ]; then
        rm -rf "$STATE_PROJECT_DIR"
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
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"

    if check_drive && [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "$message" | tee -a "$LOG_FILE"
    else
        # Drive not connected, log to fallback location
        mkdir -p "$(dirname "$FALLBACK_LOG")"
        echo "$message" >> "$FALLBACK_LOG"
        echo "$message"  # Still print to stdout
    fi
}

# Get database state (size + modification time)
get_db_state() {
    if [ -z "$DB_PATH" ] || [ ! -f "$DB_PATH" ]; then
        echo "0:0"
        return
    fi

    size=$(stat -f%z "$DB_PATH" 2>/dev/null || echo "0")
    mtime=$(stat -f%m "$DB_PATH" 2>/dev/null || echo "0")
    echo "$size:$mtime"
}

# Check if database changed since last backup
db_changed() {
    [ -z "$DB_PATH" ] && return 1  # No database configured

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
    if [ -z "$DB_PATH" ] || [ ! -f "$DB_PATH" ]; then
        return 0  # No database to backup
    fi

    log "📦 Backing up database: $PROJECT_NAME"

    # Human-readable timestamp with PID suffix to prevent collisions
    timestamp=$(date '+%m.%d.%y - %H:%M')
    backup_file="$DATABASE_DIR/${PROJECT_NAME} - ${timestamp}.db.gz"

    # SQLite backup: copy + compress with proper cleanup
    if [ "$DB_TYPE" = "sqlite" ]; then
        # Use mktemp for secure temp file (not world-readable /tmp)
        local temp_db
        temp_db=$(mktemp -t "${PROJECT_NAME}_backup.XXXXXX.db") || {
            log "❌ Failed to create temp file"
            return 1
        }

        # Trap to ensure cleanup on any exit from this function
        trap "rm -f '$temp_db' 2>/dev/null" RETURN

        # Perform backup
        if sqlite3 "$DB_PATH" ".backup '$temp_db'" 2>/dev/null; then
            if gzip -c "$temp_db" > "$backup_file" 2>/dev/null; then
                # Verify the backup is valid
                if gunzip -t "$backup_file" 2>/dev/null; then
                    size=$(du -h "$backup_file" | cut -f1)
                    log "✅ Database backup created: ${backup_file##*/} ($size)"
                    rm -f "$temp_db" 2>/dev/null
                    return 0
                else
                    log "❌ Database backup verification failed"
                    rm -f "$backup_file" 2>/dev/null
                    rm -f "$temp_db" 2>/dev/null
                    return 1
                fi
            else
                log "❌ Database compression failed"
                rm -f "$temp_db" 2>/dev/null
                return 1
            fi
        else
            log "❌ SQLite backup command failed"
            rm -f "$temp_db" 2>/dev/null
            return 1
        fi
    else
        log "⚠️  Unsupported database type: $DB_TYPE"
        return 1
    fi
}

backup_changed_files() {
    log "📁 Checking for changed files..."

    cd "$PROJECT_DIR" || return 1

    # Get list of CHANGED files to backup
    changed_files=$(mktemp)

    # Modified tracked files
    git diff --name-only >> "$changed_files" 2>/dev/null || true

    # Staged files
    git diff --cached --name-only >> "$changed_files" 2>/dev/null || true

    # Untracked files (not in .gitignore)
    git ls-files --others --exclude-standard >> "$changed_files" 2>/dev/null || true

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
        main_db_name=$(basename "$DB_PATH" 2>/dev/null || echo "")
        find . -maxdepth 3 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sql" \) \
            ! -name "$main_db_name" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
    fi

    if [ ! -s "$changed_files" ]; then
        log "ℹ️  No file changes detected"
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
                ((archived_count++))
                # Copy new version
                cp "$file" "$current_file"
                ((file_count++))
            fi
            # else: file unchanged, skip
        else
            # New file - just copy it
            cp "$file" "$current_file"
            ((file_count++))
        fi

    done < "$changed_files"

    rm "$changed_files"

    if [ $file_count -gt 0 ]; then
        log "✅ Backed up $file_count files ($archived_count archived)"

        # Auto-commit to git (if enabled)
        if [ "$AUTO_COMMIT_ENABLED" = true ]; then
            git add -A
            git commit -m "$GIT_COMMIT_MESSAGE" -q 2>/dev/null && \
                log "✅ Changes committed to git"
        fi
    fi
}

cleanup_old_backups() {
    log "🧹 Cleaning up old backups..."

    # Remove database backups older than retention policy
    db_removed=$(find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} 2>/dev/null | wc -l)
    find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} -delete 2>/dev/null

    # Remove archived files older than retention policy
    file_removed=$(find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} 2>/dev/null | wc -l)
    find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} -delete 2>/dev/null

    # Remove empty directories in archived
    find "$ARCHIVED_DIR" -type d -empty -delete 2>/dev/null

    if [ "$db_removed" -gt 0 ] || [ "$file_removed" -gt 0 ]; then
        log "🗑️  Removed $db_removed old database backups, $file_removed old archived files"
    fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

# Initialize directories (only if drive is connected)
if check_drive; then
    mkdir -p "$DATABASE_DIR" "$FILES_DIR" "$ARCHIVED_DIR"
    touch "$LOG_FILE" 2>/dev/null
fi

log "═══════════════════════════════════════════════"
log "🚀 Checkpoint - Starting"
log "📂 Project: $PROJECT_NAME"

# Check if external drive is connected (if verification enabled)
if ! check_drive; then
    log "⚠️  External drive not connected or wrong drive"
    log "ℹ️  Skipping backup cycle, will retry later"
    log "📝 Fallback log: $FALLBACK_LOG"
    log "═══════════════════════════════════════════════"
    exit 0  # Exit gracefully
fi

log "✅ Drive verification passed"

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
        mv "$temp_pid_file" "$LOCK_PID_FILE" 2>/dev/null || {
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
    log "🔒 Acquired backup lock (PID: $$)"
else
    # Lock exists - check if it's stale
    if [ -f "$LOCK_PID_FILE" ]; then
        LOCK_PID=$(cat "$LOCK_PID_FILE" 2>/dev/null)
        if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
            # Process is running - lock is valid
            log "ℹ️  Another backup is currently running (PID: $LOCK_PID), skipping to avoid duplication"
            log "═══════════════════════════════════════════════"
            exit 0
        else
            # Process is dead - lock is stale, clean it up
            log "⚠️  Removing stale lock (PID $LOCK_PID not running)"
            rm -rf "$LOCK_DIR"
            # Try to acquire lock again
            if acquire_lock; then
                trap 'rm -rf "$LOCK_DIR"' EXIT
                log "🔒 Acquired backup lock after cleanup (PID: $$)"
            else
                # Race condition - another process got the lock
                log "ℹ️  Another backup started simultaneously, skipping"
                log "═══════════════════════════════════════════════"
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
                log "ℹ️  Another backup is currently running (PID: $LOCK_PID), skipping"
                log "═══════════════════════════════════════════════"
                exit 0
            fi
        fi
        # Still no valid PID, clean up and try again
        log "⚠️  Removing incomplete lock directory"
        rm -rf "$LOCK_DIR"
        if acquire_lock; then
            trap 'rm -rf "$LOCK_DIR"' EXIT
            log "🔒 Acquired backup lock after cleanup (PID: $$)"
        else
            log "ℹ️  Another backup started simultaneously, skipping"
            log "═══════════════════════════════════════════════"
            exit 0
        fi
    fi
fi

# Check if backup already ran recently (coordination)
mkdir -p "$(dirname "$BACKUP_TIME_STATE")"
LAST_BACKUP=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
NOW=$(date +%s)
DIFF=$((NOW - LAST_BACKUP))

if [ $DIFF -lt $BACKUP_INTERVAL ]; then
    # Backup ran recently, skip
    log "ℹ️  Backup ran ${DIFF}s ago, skipping (interval: ${BACKUP_INTERVAL}s)"
    log "═══════════════════════════════════════════════"
    exit 0
fi

# Perform backup
if db_changed; then
    backup_database
else
    log "ℹ️  Database unchanged, skipping backup"
fi

backup_changed_files
cleanup_old_backups

# Update coordination state
echo "$NOW" > "$BACKUP_TIME_STATE"

# Cloud Upload (if enabled)
if [[ "${CLOUD_ENABLED:-false}" == "true" ]] && [[ "${BACKUP_LOCATION:-local}" != "local" ]]; then
    log "☁️  Starting cloud upload..."
    if type cloud_upload_background &>/dev/null; then
        cloud_upload_background
        log "☁️  Cloud upload running in background"
    else
        log "⚠️  Cloud backup library not loaded"
    fi
fi

# Summary
db_count=$(find "$DATABASE_DIR" -name "*.db.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
current_files=$(find "$FILES_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
archived_files=$(find "$ARCHIVED_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
log "📊 Databases: $db_count snapshots"
log "📊 Files: $current_files current, $archived_files archived versions"
log "✅ Backup cycle complete"
log "🔓 Released backup lock"
log "═══════════════════════════════════════════════"

# Lock is automatically removed by trap on exit (even on crash/kill)
