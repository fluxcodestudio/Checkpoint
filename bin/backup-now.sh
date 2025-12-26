#!/usr/bin/env bash
# Checkpoint - Manual Backup Trigger
# Force an immediate backup with progress reporting

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Source foundation library
if [ -f "$LIB_DIR/backup-lib.sh" ]; then
    source "$LIB_DIR/backup-lib.sh"
else
    echo "Error: Foundation library not found: $LIB_DIR/backup-lib.sh" >&2
    exit 1
fi

# Source database detector
if [ -f "$LIB_DIR/database-detector.sh" ]; then
    source "$LIB_DIR/database-detector.sh"
fi

# Source dependency manager
if [ -f "$LIB_DIR/dependency-manager.sh" ]; then
    source "$LIB_DIR/dependency-manager.sh"
fi

# ==============================================================================
# COMMAND LINE OPTIONS
# ==============================================================================

FORCE_BACKUP=false
DATABASE_ONLY=false
FILES_ONLY=false
VERBOSE=false
DRY_RUN=false
WAIT_FOR_COMPLETION=false
QUIET=false
SHOW_HELP=false
PROJECT_DIR="${PWD}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BACKUP=true
            shift
            ;;
        --database-only)
            DATABASE_ONLY=true
            shift
            ;;
        --files-only)
            FILES_ONLY=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        *)
            # Assume it's a project directory
            if [ -d "$1" ]; then
                PROJECT_DIR="$1"
            else
                echo "Unknown option or invalid directory: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# ==============================================================================
# HELP TEXT
# ==============================================================================

if [ "$SHOW_HELP" = true ]; then
    cat <<EOF
Checkpoint - Manual Backup Trigger

USAGE:
    backup-now.sh [OPTIONS] [PROJECT_DIR]

OPTIONS:
    --force             Force backup even if interval not reached
    --database-only     Only backup database
    --files-only        Only backup files
    --verbose           Show detailed progress
    --dry-run           Preview what would be backed up
    --wait              Wait for completion (don't background)
    --quiet             Suppress non-error output
    --help, -h          Show this help message

EXAMPLES:
    backup-now.sh                    # Standard backup
    backup-now.sh --force            # Force immediate backup
    backup-now.sh --database-only    # Only backup database
    backup-now.sh --verbose          # Show detailed progress
    backup-now.sh --dry-run          # Preview changes

EXIT CODES:
    0 - Backup completed successfully
    1 - Pre-flight checks failed
    2 - Backup failed
    3 - Another backup is already running

EOF
    exit 0
fi

# ==============================================================================
# OUTPUT FUNCTIONS
# ==============================================================================

log_info() {
    [ "$QUIET" = true ] && return
    echo "$@"
}

log_success() {
    [ "$QUIET" = true ] && return
    echo -e "${COLOR_GREEN}$@${COLOR_RESET}"
}

log_error() {
    echo -e "${COLOR_RED}$@${COLOR_RESET}" >&2
}

log_warn() {
    [ "$QUIET" = true ] && return
    echo -e "${COLOR_YELLOW}$@${COLOR_RESET}"
}

log_verbose() {
    [ "$VERBOSE" = false ] && return
    echo -e "${COLOR_GRAY}$@${COLOR_RESET}"
}

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

if ! load_backup_config "$PROJECT_DIR"; then
    log_error "Error: No backup configuration found in: $PROJECT_DIR"
    log_error "Run install.sh first or specify project directory"
    exit 1
fi

# Initialize state directories
init_state_dirs

# Ensure STATE_DIR is set for error logging
STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

log_info "🚀 Triggering backup for ${COLOR_CYAN}$PROJECT_NAME${COLOR_RESET}..."
log_info ""

preflight_errors=0

log_info "✅ Pre-flight checks..."

# Check drive connection
if [ "$DRIVE_VERIFICATION_ENABLED" = "true" ]; then
    if check_drive; then
        log_verbose "   ✓ Drive connected"
    else
        log_error "   ✗ Drive not connected: $DRIVE_MARKER_FILE"
        preflight_errors=$((preflight_errors + 1))
    fi
fi

# Check configuration
if check_config_status; then
    log_verbose "   ✓ Configuration valid"
else
    log_error "   ✗ Configuration invalid"
    preflight_errors=$((preflight_errors + 1))
fi

# Check for running backup
lock_pid=$(get_lock_pid "$PROJECT_NAME" || echo "")
if [ -n "$lock_pid" ]; then
    log_error "   ✗ Another backup is running (PID: $lock_pid)"
    log_error ""
    log_error "Wait for it to complete or kill process: kill $lock_pid"
    exit 3
else
    log_verbose "   ✓ No other backup running"
fi

# Check if backup interval reached (unless forced)
if [ "$FORCE_BACKUP" = false ]; then
    time_until_next=$(time_until_next_backup)
    if [ $time_until_next -gt 0 ]; then
        log_warn "   ⚠ Backup interval not reached (${time_until_next}s remaining)"
        log_warn "     Use --force to override"
        exit 1
    else
        log_verbose "   ✓ Backup interval reached"
    fi
else
    log_verbose "   ✓ Force mode enabled"
fi

if [ $preflight_errors -gt 0 ]; then
    log_error ""
    log_error "Pre-flight checks failed ($preflight_errors errors)"

    # Determine specific error message
    if [ "$DRIVE_VERIFICATION_ENABLED" = "true" ] && ! check_drive; then
        notify_backup_failure "$preflight_errors" "0" "0"  # No files attempted yet
        echo "Error: Drive not connected: $DRIVE_MARKER_FILE" > "$STATE_DIR/.last-backup-failures"
    else
        notify_backup_failure "$preflight_errors" "0" "0"  # No files attempted yet
        echo "Pre-flight checks failed" > "$STATE_DIR/.last-backup-failures"
    fi

    exit 1
fi

log_info ""

# ==============================================================================
# DRY RUN MODE
# ==============================================================================

if [ "$DRY_RUN" = true ]; then
    log_info "🔍 Dry run mode - previewing changes..."
    log_info ""

    # Database changes
    if [ "$FILES_ONLY" = false ]; then
        if [ -n "$DB_PATH" ] && [ -f "$DB_PATH" ]; then
            current_state=$(stat -f%z "$DB_PATH" 2>/dev/null || echo "0")
            last_state=$(cat "$DB_STATE_FILE" 2>/dev/null || echo "")

            if [ "$current_state" != "$last_state" ] || [ "$FORCE_BACKUP" = true ]; then
                db_size=$(format_bytes $current_state)
                log_info "📦 Database: Would backup (${db_size})"
                log_verbose "   Path: $DB_PATH"
            else
                log_info "📦 Database: No changes detected"
            fi
        else
            log_info "📦 Database: Not configured"
        fi
        log_info ""
    fi

    # File changes
    if [ "$DATABASE_ONLY" = false ]; then
        cd "$PROJECT_DIR" || exit 1

        changed_files=$(mktemp)

        # Get changed files (same logic as daemon)
        git diff --name-only >> "$changed_files" 2>/dev/null || true
        git diff --cached --name-only >> "$changed_files" 2>/dev/null || true
        git ls-files --others --exclude-standard >> "$changed_files" 2>/dev/null || true

        # FALLBACK: If no git repo, use mtime check for dry-run
        if [ ! -s "$changed_files" ]; then
            find . -type f -mmin -$(( BACKUP_INTERVAL / 60 )) \
                ! -path "*/backups/*" \
                ! -path "*/.git/*" \
                ! -path "*/node_modules/*" \
                ! -path "*/.venv/*" \
                ! -path "*/__pycache__/*" \
                ! -path "*/dist/*" \
                ! -path "*/build/*" \
                ! -path "*/.next/*" \
                ! -path "*/.DS_Store" \
                2>/dev/null | sed 's|^\./||' >> "$changed_files"
        fi

        if [ "$BACKUP_ENV_FILES" = true ]; then
            find . -maxdepth 3 -type f \( -name ".env" -o -name ".env.*" \) 2>/dev/null | sed 's|^\./||' >> "$changed_files"
        fi

        if [ "$BACKUP_CREDENTIALS" = true ]; then
            find . -maxdepth 3 -type f \( \
                -name "*.pem" -o -name "*.key" -o \
                -name "credentials.json" -o -name "secrets.*" -o \
                -name "*.p12" -o -name "*.pfx" \
            \) 2>/dev/null | sed 's|^\./||' >> "$changed_files"

            # Cloud provider configs
            [ -f ".aws/credentials" ] && echo ".aws/credentials" >> "$changed_files"
            [ -f ".aws/config" ] && echo ".aws/config" >> "$changed_files"
            find . -maxdepth 2 -type f -path "*/.gcp/*.json" 2>/dev/null | sed 's|^\./||' >> "$changed_files"

            # Terraform secrets
            find . -maxdepth 3 -type f -name "terraform.tfvars" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
            find . -maxdepth 3 -type f -name "*.tfvars" 2>/dev/null | sed 's|^\./||' >> "$changed_files"

            # Firebase configs
            find . -maxdepth 2 -type f -path "*/.firebase/*.json" 2>/dev/null | sed 's|^\./||' >> "$changed_files"

            # Local config overrides
            find . -maxdepth 3 -type f -name "*.local.*" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
            find . -maxdepth 3 -type f -name "local.settings.json" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
            find . -maxdepth 3 -type f -name "appsettings.*.json" 2>/dev/null | sed 's|^\./||' >> "$changed_files"

            # Docker overrides
            [ -f "docker-compose.override.yml" ] && echo "docker-compose.override.yml" >> "$changed_files"
        fi

        if [ "$BACKUP_IDE_SETTINGS" = true ]; then
            [ -f ".vscode/settings.json" ] && echo ".vscode/settings.json" >> "$changed_files"
            [ -f ".vscode/launch.json" ] && echo ".vscode/launch.json" >> "$changed_files"
            [ -f ".vscode/extensions.json" ] && echo ".vscode/extensions.json" >> "$changed_files"
            [ -f ".idea/workspace.xml" ] && echo ".idea/workspace.xml" >> "$changed_files"
            if [ -d ".idea/codeStyles" ]; then
                find .idea/codeStyles -type f 2>/dev/null | sed 's|^\./||' >> "$changed_files"
            fi
        fi

        if [ "$BACKUP_LOCAL_NOTES" = true ]; then
            find . -maxdepth 2 -type f \( \
                -name "NOTES.md" -o -name "NOTES.txt" -o \
                -name "TODO.local.md" -o -name "*.private.md" \
            \) 2>/dev/null | sed 's|^\./||' >> "$changed_files"
        fi

        if [ "$BACKUP_LOCAL_DATABASES" = true ]; then
            main_db_name=$(basename "$DB_PATH" 2>/dev/null || echo "")
            find . -maxdepth 3 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sql" \) \
                ! -name "$main_db_name" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
        fi

        if [ ! -s "$changed_files" ]; then
            log_info "📁 Files: No changes detected"
        else
            file_count=$(sort -u "$changed_files" | wc -l | tr -d ' ')
            log_info "📁 Files: Would backup $file_count files"
            log_info ""

            if [ "$VERBOSE" = true ]; then
                log_verbose "   Changed files:"
                sort -u "$changed_files" | head -20 | while read -r file; do
                    log_verbose "   • $file"
                done
                if [ $file_count -gt 20 ]; then
                    log_verbose "   ... and $((file_count - 20)) more"
                fi
            fi
        fi

        rm "$changed_files"
    fi

    log_info ""
    log_info "Dry run complete. Use 'backup-now.sh --force' to execute."
    exit 0
fi

# ==============================================================================
# BACKUP EXECUTION
# ==============================================================================

# Acquire lock
if ! acquire_backup_lock "$PROJECT_NAME"; then
    log_error "Failed to acquire backup lock"
    exit 3
fi

# Ensure lock is released on exit
trap 'release_backup_lock' EXIT

# Initialize backup directories
if ! init_backup_dirs; then
    log_error "Failed to initialize backup directories"
    exit 2
fi

# Track backup start time
backup_start=$(date +%s)
backup_errors=0
db_count=0  # Track successful database backups

log_info "📦 Backup in progress..."
log_info ""

# ==============================================================================
# DATABASE BACKUP (Universal Auto-Detection)
# ==============================================================================

if [ "$FILES_ONLY" = false ]; then
    log_info "   ▸ Databases: Auto-detecting..."

    # Use universal database detector
    if command -v backup_detected_databases &>/dev/null; then
        if backup_detected_databases "$PROJECT_DIR" "$BACKUP_DIR"; then
            log_success "   ▸ Databases: ✅ Backup complete"
        else
            log_info "   ▸ Databases: Some backups failed (see above)"
            backup_errors=$((backup_errors + 1))
        fi
    else
        # Fallback to legacy SQLite-only backup if detector not available
        if [ -n "${DB_PATH:-}" ] && [ -f "$DB_PATH" ]; then
            log_info "   ▸ Database: Backing up (legacy SQLite)..."

            timestamp=$(date '+%m.%d.%y - %H:%M')
            backup_file="$DATABASE_DIR/${PROJECT_NAME} - ${timestamp}.db.gz"

            if [ "${DB_TYPE:-sqlite}" = "sqlite" ]; then
                if sqlite3 "$DB_PATH" ".backup /tmp/${PROJECT_NAME}_temp.db" && \
                   gzip -c "/tmp/${PROJECT_NAME}_temp.db" > "$backup_file" && \
                   rm "/tmp/${PROJECT_NAME}_temp.db"; then

                    backup_size=$(stat -f%z "$backup_file")
                    backup_size_human=$(format_bytes $backup_size)
                    log_success "   ▸ Database: ✅ Done ($backup_size_human compressed)"
                else
                    log_error "   ▸ Database: ❌ Failed"
                    backup_errors=$((backup_errors + 1))
                fi
            else
                log_error "   ▸ Database: ❌ Unsupported type: ${DB_TYPE}"
                backup_errors=$((backup_errors + 1))
            fi
        else
            log_verbose "   ▸ Database: No databases detected"
        fi
    fi
fi

# ==============================================================================
# FILE BACKUP
# ==============================================================================

if [ "$DATABASE_ONLY" = false ]; then
    log_info "   ▸ Files: Scanning for changes..."

    cd "$PROJECT_DIR" || exit 2

    changed_files=$(mktemp)

    # Detect if this is the first backup
    is_first_backup=false
    if [ ! -d "$FILES_DIR" ] || [ -z "$(ls -A "$FILES_DIR" 2>/dev/null)" ]; then
        is_first_backup=true
        log_info "   ▸ Files: First backup detected - will backup all tracked files"
    fi

    # Get changed files
    if [ "$is_first_backup" = true ]; then
        # FIRST BACKUP: Include ALL tracked git files
        git ls-files >> "$changed_files" 2>/dev/null || true
        git ls-files --others --exclude-standard >> "$changed_files" 2>/dev/null || true

        # FALLBACK: If no git repo, use find to get all files
        if [ ! -s "$changed_files" ]; then
            log_verbose "   No git repository detected - using file system scan"
            find . -type f \
                ! -path "*/backups/*" \
                ! -path "*/.git/*" \
                ! -path "*/node_modules/*" \
                ! -path "*/.venv/*" \
                ! -path "*/__pycache__/*" \
                ! -path "*/dist/*" \
                ! -path "*/build/*" \
                ! -path "*/.next/*" \
                ! -path "*/.DS_Store" \
                2>/dev/null | sed 's|^\./||' >> "$changed_files"
        fi
    else
        # INCREMENTAL: Only changed files
        git diff --name-only >> "$changed_files" 2>/dev/null || true
        git diff --cached --name-only >> "$changed_files" 2>/dev/null || true
        git ls-files --others --exclude-standard >> "$changed_files" 2>/dev/null || true

        # FALLBACK: If no git repo, backup modified files (by mtime)
        if [ ! -s "$changed_files" ]; then
            log_verbose "   No git repository detected - using mtime check"
            # Find files modified in last hour (BACKUP_INTERVAL)
            find . -type f -mmin -$(( BACKUP_INTERVAL / 60 )) \
                ! -path "*/backups/*" \
                ! -path "*/.git/*" \
                ! -path "*/node_modules/*" \
                ! -path "*/.venv/*" \
                ! -path "*/__pycache__/*" \
                ! -path "*/dist/*" \
                ! -path "*/build/*" \
                ! -path "*/.next/*" \
                ! -path "*/.DS_Store" \
                2>/dev/null | sed 's|^\./||' >> "$changed_files"
        fi
    fi

    if [ "$BACKUP_ENV_FILES" = true ]; then
        find . -maxdepth 3 -type f \( -name ".env" -o -name ".env.*" \) 2>/dev/null | sed 's|^\./||' >> "$changed_files"
    fi

    if [ "$BACKUP_CREDENTIALS" = true ]; then
        find . -maxdepth 3 -type f \( \
            -name "*.pem" -o -name "*.key" -o \
            -name "credentials.json" -o -name "secrets.*" -o \
            -name "*.p12" -o -name "*.pfx" \
        \) 2>/dev/null | sed 's|^\./||' >> "$changed_files"

        # Cloud provider configs
        [ -f ".aws/credentials" ] && echo ".aws/credentials" >> "$changed_files"
        [ -f ".aws/config" ] && echo ".aws/config" >> "$changed_files"
        find . -maxdepth 2 -type f -path "*/.gcp/*.json" 2>/dev/null | sed 's|^\./||' >> "$changed_files"

        # Terraform secrets
        find . -maxdepth 3 -type f -name "terraform.tfvars" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
        find . -maxdepth 3 -type f -name "*.tfvars" 2>/dev/null | sed 's|^\./||' >> "$changed_files"

        # Firebase configs
        find . -maxdepth 2 -type f -path "*/.firebase/*.json" 2>/dev/null | sed 's|^\./||' >> "$changed_files"

        # Local config overrides
        find . -maxdepth 3 -type f -name "*.local.*" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
        find . -maxdepth 3 -type f -name "local.settings.json" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
        find . -maxdepth 3 -type f -name "appsettings.*.json" 2>/dev/null | sed 's|^\./||' >> "$changed_files"

        # Docker overrides
        [ -f "docker-compose.override.yml" ] && echo "docker-compose.override.yml" >> "$changed_files"
    fi

    if [ "$BACKUP_IDE_SETTINGS" = true ]; then
        [ -f ".vscode/settings.json" ] && echo ".vscode/settings.json" >> "$changed_files"
        [ -f ".vscode/launch.json" ] && echo ".vscode/launch.json" >> "$changed_files"
        [ -f ".vscode/extensions.json" ] && echo ".vscode/extensions.json" >> "$changed_files"
        [ -f ".idea/workspace.xml" ] && echo ".idea/workspace.xml" >> "$changed_files"
        if [ -d ".idea/codeStyles" ]; then
            find .idea/codeStyles -type f 2>/dev/null | sed 's|^\./||' >> "$changed_files"
        fi
    fi

    if [ "$BACKUP_LOCAL_NOTES" = true ]; then
        find . -maxdepth 2 -type f \( \
            -name "NOTES.md" -o -name "NOTES.txt" -o \
            -name "TODO.local.md" -o -name "*.private.md" \
        \) 2>/dev/null | sed 's|^\./||' >> "$changed_files"
    fi

    if [ "$BACKUP_LOCAL_DATABASES" = true ]; then
        main_db_name=$(basename "$DB_PATH" 2>/dev/null || echo "")
        find . -maxdepth 3 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sql" \) \
            ! -name "$main_db_name" 2>/dev/null | sed 's|^\./||' >> "$changed_files"
    fi

    if [ ! -s "$changed_files" ]; then
        log_info "   ▸ Files: No changes detected"
    else
        file_count=0
        archived_count=0
        failed_count=0
        timestamp=$(date +%Y%m%d_%H%M%S)

        # Create manifest for verification
        manifest_file=$(mktemp)
        failed_files=$(mktemp)

        total_files=$(sort -u "$changed_files" | wc -l | tr -d ' ')

        # Build manifest: capture file metadata at backup START
        log_verbose "   Creating backup manifest..."
        while IFS= read -r file; do
            # Skip backups directory and non-existent files
            if [[ "$file" == backups/* ]] || [ ! -f "$file" ]; then
                continue
            fi
            file_size=$(stat -f%z "$file" 2>/dev/null || echo "0")
            echo "$file|$file_size" >> "$manifest_file"
        done < <(sort -u "$changed_files")

        if [ "$is_first_backup" = true ]; then
            log_info "   ▸ Files: Initial backup - copying $total_files files..."
        else
            log_info "   ▸ Files: $total_files modified files found"
            log_info "   ▸ Files: Backing up changes..."
        fi

        while IFS= read -r file; do
            if [ -z "$file" ]; then continue; fi
            if [ ! -f "$file" ]; then continue; fi
            if [[ "$file" == backups/* ]]; then continue; fi

            current_file="$FILES_DIR/$file"
            current_dir=$(dirname "$current_file")
            archived_file="$ARCHIVED_DIR/${file}.${timestamp}"
            archived_dir=$(dirname "$archived_file")

            mkdir -p "$current_dir"

            # Check if file changed
            if [ -f "$current_file" ]; then
                if ! cmp -s "$file" "$current_file"; then
                    mkdir -p "$archived_dir"
                    mv "$current_file" "$archived_file"
                    archived_count=$((archived_count + 1))

                    # Copy with retry logic (3 attempts)
                    if copy_with_retry "$file" "$current_file" 3; then
                        file_count=$((file_count + 1))
                        if [ "$VERBOSE" = true ]; then
                            log_verbose "      • Backed up: $file"
                        fi
                    else
                        # Copy failed after retries - track it with specific error type
                        failed_count=$((failed_count + 1))
                        error_type="${COPY_FAILURE_REASON:-copy_failed}"
                        track_file_failure "$file" "$error_type" "$failed_files"
                        log_error "      ✗ Failed: $file ($error_type)"
                    fi
                fi
            else
                # Copy with retry logic (3 attempts)
                if copy_with_retry "$file" "$current_file" 3; then
                    file_count=$((file_count + 1))
                    if [ "$VERBOSE" = true ]; then
                        log_verbose "      • New file: $file"
                    fi
                else
                    # Copy failed after retries - track it with specific error type
                    failed_count=$((failed_count + 1))
                    error_type="${COPY_FAILURE_REASON:-copy_failed}"
                    track_file_failure "$file" "$error_type" "$failed_files"
                    log_error "      ✗ Failed: $file ($error_type)"
                fi
            fi

        done < <(sort -u "$changed_files")

        rm "$changed_files"

        # ==============================================================================
        # POST-BACKUP VERIFICATION
        # ==============================================================================

        log_verbose "   Verifying backup integrity..."

        # Verify each file in manifest was actually backed up
        verification_failed=0
        while IFS='|' read -r file expected_size; do
            backup_file="$FILES_DIR/$file"

            if [ ! -f "$backup_file" ]; then
                # File missing from backup
                verification_failed=$((verification_failed + 1))
                track_file_failure "$file" "file_missing" "$failed_files"
                log_error "      ✗ Verification failed: $file (missing from backup)"
            else
                # Check size matches
                actual_size=$(stat -f%z "$backup_file" 2>/dev/null || echo "0")
                if [ "$actual_size" != "$expected_size" ]; then
                    # Size mismatch - file may be corrupted or modified during backup
                    verification_failed=$((verification_failed + 1))
                    track_file_failure "$file" "size_mismatch" "$failed_files"
                    log_error "      ✗ Verification failed: $file (size mismatch: expected $expected_size, got $actual_size)"
                fi
            fi
        done < "$manifest_file"

        # Update failed count with verification failures
        failed_count=$((failed_count + verification_failed))

        # Cleanup temp files
        rm -f "$manifest_file"

        # Report results
        if [ $file_count -gt 0 ]; then
            if [ $failed_count -eq 0 ]; then
                # All files backed up successfully
                if [ "$is_first_backup" = true ]; then
                    log_success "   ▸ Files: ✅ Initial backup complete - $file_count files copied"
                else
                    log_success "   ▸ Files: ✅ $file_count files backed up ($archived_count archived)"
                fi
            else
                # Some files failed
                if [ "$is_first_backup" = true ]; then
                    log_error "   ▸ Files: ⚠️ Backup incomplete - $file_count succeeded, $failed_count failed"
                else
                    log_error "   ▸ Files: ⚠️ Backup incomplete - $file_count succeeded, $failed_count failed ($archived_count archived)"
                fi

                # Increment backup errors
                backup_errors=$((backup_errors + failed_count))

                # Log failed files for troubleshooting
                log_error "   ▸ Failed files saved to: $STATE_DIR/.last-backup-failures"
                mkdir -p "$(dirname "$STATE_DIR/.last-backup-failures")" 2>/dev/null || true
                cp "$failed_files" "$STATE_DIR/.last-backup-failures" 2>/dev/null || true
            fi

            # Cleanup failed files temp
            rm -f "$failed_files"

            # Auto-commit to git (if enabled)
            if [ "$AUTO_COMMIT_ENABLED" = true ]; then
                if git add -A && git commit -m "$GIT_COMMIT_MESSAGE" -q 2>/dev/null; then
                    log_success "   ▸ Git: ✅ Changes committed"
                fi
            fi
        else
            log_info "   ▸ Files: No changes to backup"
        fi
    fi
fi

# ==============================================================================
# CLEANUP
# ==============================================================================

log_info "   ▸ Cleanup: Checking retention..."

# Remove old backups
db_removed=$(find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} 2>/dev/null | wc -l | tr -d ' ')
find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} -delete 2>/dev/null || true

file_removed=$(find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} 2>/dev/null | wc -l | tr -d ' ')
find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} -delete 2>/dev/null || true

find "$ARCHIVED_DIR" -type d -empty -delete 2>/dev/null || true

if [ $db_removed -gt 0 ] || [ $file_removed -gt 0 ]; then
    space_freed=$((db_removed + file_removed))
    log_success "   ▸ Cleanup: ✅ $db_removed old database backups, $file_removed old files removed"
else
    log_verbose "   ▸ Cleanup: ✅ No old backups to remove"
fi

# ==============================================================================
# UPDATE STATE
# ==============================================================================

backup_end=$(date +%s)
backup_duration=$((backup_end - backup_start))

echo "$backup_end" > "$BACKUP_TIME_STATE"

# ==============================================================================
# SUMMARY
# ==============================================================================

log_info ""

if [ $backup_errors -eq 0 ]; then
    log_success "✅ TRUE SUCCESS: 100% backed up in ${backup_duration}s"
else
    # Partial success - some files backed up despite errors
    log_warn "⚠️  PARTIAL SUCCESS: $file_count files backed up, $backup_errors FAILED"
    log_warn "    Run 'backup-failures' for LLM-ready prompt to fix issues"
fi

log_info ""
log_info "📊 Summary:"

# Get updated statistics
db_count=$(count_database_backups)
current_files=$(count_current_files)
archived_files=$(count_archived_files)

log_info "   Database: $db_count snapshots"
log_info "   Files: $current_files backed up, $archived_files archived"

if [ $db_removed -gt 0 ] || [ $file_removed -gt 0 ]; then
    log_info "   Cleanup: $db_removed DB backups, $file_removed files removed"
fi

log_info ""
log_info "View status: ${COLOR_CYAN}backup-status.sh${COLOR_RESET}"

if [ -f "$LOG_FILE" ]; then
    log_info "View logs: ${COLOR_CYAN}tail -f $LOG_FILE${COLOR_RESET}"
fi

log_info ""

# ==============================================================================
# NOTIFICATIONS & EXIT CODES
# ==============================================================================

# Calculate totals for notification
total_files_attempted=$((file_count + failed_count))
total_backed_up=$((file_count + db_count))

if [ $backup_errors -gt 0 ]; then
    if [ $total_backed_up -eq 0 ]; then
        # TOTAL FAILURE - zero files/databases backed up
        log_error ""
        log_error "❌ TOTAL FAILURE: No files or databases were backed up"
        notify_backup_failure "$backup_errors" "$total_files_attempted" "0"
        exit 2
    else
        # PARTIAL SUCCESS - some files backed up despite errors
        # Make a fuss: Notify user with file counts + LLM prompt
        # Even 1 file failure = NOT TRUE SUCCESS
        notify_backup_failure "$backup_errors" "$total_files_attempted" "$file_count"

        # Exit 0 to allow daemon to continue (not a fatal error)
        # But notification will alert user to fix incomplete backup
        exit 0
    fi
else
    # TRUE SUCCESS - 100% backed up and verified
    # Only now can we call it "success"
    notify_backup_success
    exit 0
fi
