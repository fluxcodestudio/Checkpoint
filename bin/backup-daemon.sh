#!/bin/bash
# Checkpoint - Main Backup Daemon
# Handles database backups, file backups, archiving, and cleanup
# Can be triggered by: LaunchAgent (hourly), Claude Code hooks (on prompt), or manually

set -euo pipefail

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

# Find config file (check project root first, then script directory)
CONFIG_FILE=""
if [ -f "$PWD/.backup-config.sh" ]; then
    CONFIG_FILE="$PWD/.backup-config.sh"
elif [ -f "$(dirname "$0")/../templates/backup-config.sh" ]; then
    CONFIG_FILE="$(dirname "$0")/../templates/backup-config.sh"
else
    echo "❌ Configuration file not found. Run install.sh first." >&2
    exit 1
fi

source "$CONFIG_FILE"

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

    # Human-readable timestamp: "ProjectName - 12.23.25 - 10:45.db.gz"
    timestamp=$(date '+%m.%d.%y - %H:%M')
    backup_file="$DATABASE_DIR/${PROJECT_NAME} - ${timestamp}.db.gz"

    # SQLite backup: copy + compress
    if [ "$DB_TYPE" = "sqlite" ]; then
        sqlite3 "$DB_PATH" ".backup /tmp/${PROJECT_NAME}_temp.db" && \
        gzip -c "/tmp/${PROJECT_NAME}_temp.db" > "$backup_file" && \
        rm "/tmp/${PROJECT_NAME}_temp.db"

        if [ $? -eq 0 ]; then
            size=$(du -h "$backup_file" | cut -f1)
            log "✅ Database backup created: ${backup_file##*/} ($size)"
            return 0
        else
            log "❌ Database backup failed"
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

LOCK_DIR="${HOME}/.claudecode-backups/locks/${PROJECT_NAME}.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"

# Try to acquire lock by creating directory (atomic operation)
if mkdir "$LOCK_DIR" 2>/dev/null; then
    # Successfully acquired lock
    echo $$ > "$LOCK_PID_FILE"
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
            if mkdir "$LOCK_DIR" 2>/dev/null; then
                echo $$ > "$LOCK_PID_FILE"
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
        # Lock directory exists but no PID file - probably stale
        log "⚠️  Removing incomplete lock directory"
        rm -rf "$LOCK_DIR"
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo $$ > "$LOCK_PID_FILE"
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
