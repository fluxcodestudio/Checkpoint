#!/usr/bin/env bash
# Checkpoint - Manual Backup Trigger
# Force an immediate backup with progress reporting

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Source foundation library (loads logging.sh, config.sh, output.sh, etc.)
source "$LIB_DIR/backup-lib.sh"

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
DRY_RUN=false
WAIT_FOR_COMPLETION=false
QUIET=false
SHOW_HELP=false
PROJECT_DIR="${PWD}"

# Scan for log-level flags before main parsing (sets CHECKPOINT_LOG_LEVEL)
parse_log_flags "$@"

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
            CHECKPOINT_LOG_LEVEL="$LOG_LEVEL_DEBUG"
            shift
            ;;
        --debug)
            CHECKPOINT_LOG_LEVEL="$LOG_LEVEL_DEBUG"
            shift
            ;;
        --trace)
            CHECKPOINT_LOG_LEVEL="$LOG_LEVEL_TRACE"
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
            CHECKPOINT_LOG_LEVEL="$LOG_LEVEL_ERROR"
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
    --verbose           Show detailed progress (same as --debug)
    --debug             Enable debug logging
    --trace             Enable trace logging (very verbose)
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
    backup-now.sh --debug            # Debug logging to file

EXIT CODES:
    0 - Backup completed successfully
    1 - Pre-flight checks failed
    2 - Backup failed
    3 - Another backup is already running

EOF
    exit 0
fi

# ==============================================================================
# CLI OUTPUT FUNCTIONS (user-facing terminal output)
# ==============================================================================
# These are separate from the structured log_* functions in logging.sh.
# cli_* functions write colored text to stdout/stderr for the user.
# log_* functions write timestamped entries to the log file.

cli_info() {
    [ "$QUIET" = true ] && return
    echo "$@"
}

cli_success() {
    [ "$QUIET" = true ] && return
    echo -e "${COLOR_GREEN}$@${COLOR_RESET}"
}

cli_error() {
    echo -e "${COLOR_RED}$@${COLOR_RESET}" >&2
}

cli_warn() {
    [ "$QUIET" = true ] && return
    echo -e "${COLOR_YELLOW}$@${COLOR_RESET}"
}

cli_verbose() {
    [ "$CHECKPOINT_LOG_LEVEL" -lt "$LOG_LEVEL_DEBUG" ] 2>/dev/null && return
    echo -e "${COLOR_GRAY}$@${COLOR_RESET}"
}

# Issue #13: Get timestamp (UTC or local based on config)
get_backup_timestamp() {
    local format="${1:-%Y%m%d_%H%M%S}"
    if [ "${USE_UTC_TIMESTAMPS:-false}" = "true" ]; then
        date -u +"$format"
    else
        date +"$format"
    fi
}

# ==============================================================================
# LOAD CONFIGURATION (with auto-creation)
# ==============================================================================

# Source projects registry
if [ -f "$LIB_DIR/projects-registry.sh" ]; then
    source "$LIB_DIR/projects-registry.sh"
fi

if ! load_backup_config "$PROJECT_DIR"; then
    # Auto-create configuration for new projects
    echo "First time backup - creating configuration..."
    echo ""

    PROJECT_NAME="$(basename "$PROJECT_DIR")"
    BACKUP_DIR="$PROJECT_DIR/backups"

    # Create config file with smart defaults
    cat > "$PROJECT_DIR/.backup-config.sh" << AUTOCONFIG
#!/usr/bin/env bash
# Checkpoint Configuration (auto-generated)
# Created: $(date)

# Project
PROJECT_NAME="$PROJECT_NAME"
PROJECT_DIR="$PROJECT_DIR"
BACKUP_DIR="$BACKUP_DIR"

# Database (auto-detect on each backup)
DB_TYPE="auto"
DB_RETENTION_DAYS=30

# Files
FILE_RETENTION_DAYS=60

# Automation
BACKUP_INTERVAL=3600
SESSION_IDLE_THRESHOLD=600

# Optional Features
HOOKS_ENABLED=false

# Critical Files
BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=true
BACKUP_LOCAL_NOTES=true
BACKUP_LOCAL_DATABASES=true
AUTOCONFIG

    chmod +x "$PROJECT_DIR/.backup-config.sh"

    # Add to .gitignore if exists
    if [[ -f "$PROJECT_DIR/.gitignore" ]]; then
        if ! grep -q "^backups/$" "$PROJECT_DIR/.gitignore" 2>/dev/null; then
            echo "" >> "$PROJECT_DIR/.gitignore"
            echo "# Checkpoint backups" >> "$PROJECT_DIR/.gitignore"
            echo "backups/" >> "$PROJECT_DIR/.gitignore"
            echo ".backup-config.sh" >> "$PROJECT_DIR/.gitignore"
        fi
    fi

    # Create backup directories
    mkdir -p "$BACKUP_DIR"/{databases,files,archived}

    # Register in global registry
    if type register_project &>/dev/null; then
        register_project "$PROJECT_DIR" "$PROJECT_NAME"
    fi

    echo "   Configuration created: .backup-config.sh"
    echo "   Backup directory: backups/"
    echo ""

    # Now load the config
    if ! load_backup_config "$PROJECT_DIR"; then
        cli_error "Error: Failed to load auto-created configuration"
        log_error "Failed to load auto-created configuration for $PROJECT_DIR"
        exit 1
    fi
fi

# ALWAYS use directory name as PROJECT_NAME (prevents config mismatches)
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# Register project if not already (for existing configs)
if type is_registered &>/dev/null && ! is_registered "$PROJECT_DIR"; then
    register_project "$PROJECT_DIR" "$PROJECT_NAME"
fi

# Initialize state directories
init_state_dirs

# Ensure STATE_DIR is set for error logging
STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"

# ==============================================================================
# INITIALIZE STRUCTURED LOGGING
# ==============================================================================
# Must happen after load_backup_config so LOG_FILE is set from config

# Use resolved destinations (from resolve_backup_destinations) or fall back to legacy paths
# (moved LOG_FILE default up so _init_checkpoint_logging picks it up)
LOG_FILE="${LOG_FILE:-${BACKUP_DIR:-/tmp}/backup.log}"

_init_checkpoint_logging
log_set_context "backup-now"
log_info "Backup started for project=$PROJECT_NAME dir=$PROJECT_DIR"
log_debug "Log level: $CHECKPOINT_LOG_LEVEL, log file: ${_CHECKPOINT_LOG_FILE:-none}"

# ==============================================================================
# RESOLVE BACKUP DESTINATIONS (Cloud folder routing)
# ==============================================================================

# Resolve cloud folder destination (if enabled)
resolve_backup_destinations

# Create backup directories in resolved destinations
if ! ensure_backup_dirs; then
    cli_error "Failed to create backup directories"
    log_error "Failed to create backup directories"
    exit 2
fi

# Log destination info
if [[ -n "${CLOUD_BACKUP_DIR:-}" ]]; then
    cli_verbose "   Backup destination: $PRIMARY_BACKUP_DIR (cloud)"
    log_debug "Backup destination: $PRIMARY_BACKUP_DIR (cloud)"
    if [[ -n "${SECONDARY_BACKUP_DIR:-}" ]]; then
        cli_verbose "   Also backing up to: $SECONDARY_BACKUP_DIR (local)"
        log_debug "Secondary destination: $SECONDARY_BACKUP_DIR (local)"
    fi
else
    cli_verbose "   Backup destination: $PRIMARY_BACKUP_DIR (local)"
    log_debug "Backup destination: $PRIMARY_BACKUP_DIR (local)"
fi

# Set defaults for optional config variables (compatibility with older configs)
DRIVE_VERIFICATION_ENABLED="${DRIVE_VERIFICATION_ENABLED:-false}"
DRIVE_MARKER_FILE="${DRIVE_MARKER_FILE:-}"
BACKUP_LOCAL_NOTES="${BACKUP_LOCAL_NOTES:-true}"
BACKUP_LOCAL_DATABASES="${BACKUP_LOCAL_DATABASES:-true}"
AUTO_COMMIT_ENABLED="${AUTO_COMMIT_ENABLED:-false}"
GIT_COMMIT_MESSAGE="${GIT_COMMIT_MESSAGE:-Auto-backup: $(date '+%Y-%m-%d %H:%M')}"
USE_UTC_TIMESTAMPS="${USE_UTC_TIMESTAMPS:-false}"
DB_PATH="${DB_PATH:-}"
DB_TYPE="${DB_TYPE:-none}"
DB_STATE_FILE="${DB_STATE_FILE:-$BACKUP_DIR/.backup-state}"
BACKUP_TIME_STATE="${BACKUP_TIME_STATE:-$STATE_DIR/${PROJECT_NAME}/.last-backup-time}"
BACKUP_USE_HASH_COMPARE="${BACKUP_USE_HASH_COMPARE:-true}"

# Use resolved destinations (from resolve_backup_destinations) or fall back to legacy paths
DATABASE_DIR="${PRIMARY_DATABASE_DIR:-${DATABASE_DIR:-$BACKUP_DIR/databases}}"
FILES_DIR="${PRIMARY_FILES_DIR:-${FILES_DIR:-$BACKUP_DIR/files}}"
ARCHIVED_DIR="${PRIMARY_ARCHIVED_DIR:-${ARCHIVED_DIR:-$BACKUP_DIR/archived}}"
LOG_FILE="${LOG_FILE:-$BACKUP_DIR/backup.log}"

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

cli_info "Triggering backup for ${COLOR_CYAN}$PROJECT_NAME${COLOR_RESET}..."
cli_info ""

preflight_errors=0

cli_info "Pre-flight checks..."

# Check drive connection
if [ "$DRIVE_VERIFICATION_ENABLED" = "true" ]; then
    if check_drive; then
        cli_verbose "   Drive connected"
        log_debug "Drive verification passed"
    else
        cli_error "   Drive not connected: $DRIVE_MARKER_FILE"
        log_error "Drive not connected: $DRIVE_MARKER_FILE"
        preflight_errors=$((preflight_errors + 1))
    fi
fi

# Check configuration
if check_config_status; then
    cli_verbose "   Configuration valid"
    log_debug "Configuration validation passed"
else
    cli_error "   Configuration invalid"
    log_error "Configuration validation failed"
    preflight_errors=$((preflight_errors + 1))
fi

# Check for running backup
lock_pid=$(get_lock_pid "$PROJECT_NAME" || echo "")
if [ -n "$lock_pid" ]; then
    cli_error "   Another backup is running (PID: $lock_pid)"
    cli_error ""
    cli_error "Wait for it to complete or kill process: kill $lock_pid"
    log_error "Another backup already running, PID=$lock_pid"
    exit 3
else
    cli_verbose "   No other backup running"
fi

# Check if backup interval reached (unless forced)
if [ "$FORCE_BACKUP" = false ]; then
    time_until_next=$(time_until_next_backup)
    if [ $time_until_next -gt 0 ]; then
        cli_warn "   Backup interval not reached (${time_until_next}s remaining)"
        cli_warn "     Use --force to override"
        log_info "Backup interval not reached, ${time_until_next}s remaining"
        exit 1
    else
        cli_verbose "   Backup interval reached"
    fi
else
    cli_verbose "   Force mode enabled"
    log_debug "Force mode enabled"
fi

if [ $preflight_errors -gt 0 ]; then
    cli_error ""
    cli_error "Pre-flight checks failed ($preflight_errors errors)"
    log_error "Pre-flight checks failed with $preflight_errors errors"

    # Determine specific error code and message
    if [ "$DRIVE_VERIFICATION_ENABLED" = "true" ] && ! check_drive; then
        error_code=$(map_error_to_code "drive_disconnected")
        notify_backup_failure "$preflight_errors" "0" "0" "$error_code"
        echo "Error: Drive not connected: $DRIVE_MARKER_FILE" > "$STATE_DIR/.last-backup-failures"
    else
        error_code=$(map_error_to_code "config_invalid")
        notify_backup_failure "$preflight_errors" "0" "0" "$error_code"
        echo "Pre-flight checks failed" > "$STATE_DIR/.last-backup-failures"
    fi

    exit 1
fi

cli_info ""

# Display backup destination
if [[ -n "${CLOUD_BACKUP_DIR:-}" ]]; then
    cli_info "Backing up to: ${COLOR_CYAN}$PRIMARY_BACKUP_DIR${COLOR_RESET} (cloud)"
    if [[ -n "${SECONDARY_BACKUP_DIR:-}" ]]; then
        cli_info "   Also backing up locally: ${COLOR_CYAN}$SECONDARY_BACKUP_DIR${COLOR_RESET}"
    fi
else
    cli_info "Backing up to: ${COLOR_CYAN}$PRIMARY_BACKUP_DIR${COLOR_RESET}"
fi
cli_info ""

# ==============================================================================
# DRY RUN MODE
# ==============================================================================

if [ "$DRY_RUN" = true ]; then
    cli_info "Dry run mode - previewing changes..."
    cli_info ""
    log_info "Dry run mode"

    # Database changes
    if [ "$FILES_ONLY" = false ]; then
        if [ -n "$DB_PATH" ] && [ -f "$DB_PATH" ]; then
            current_state=$(get_file_size "$DB_PATH")
            last_state=$(cat "$DB_STATE_FILE" 2>/dev/null || echo "")

            if [ "$current_state" != "$last_state" ] || [ "$FORCE_BACKUP" = true ]; then
                db_size=$(format_bytes $current_state)
                cli_info "Database: Would backup (${db_size})"
                cli_verbose "   Path: $DB_PATH"
            else
                cli_info "Database: No changes detected"
            fi
        else
            cli_info "Database: Not configured"
        fi
        cli_info ""
    fi

    # File changes
    if [ "$DATABASE_ONLY" = false ]; then
        cd "$PROJECT_DIR" || exit 1

        changed_files=$(mktemp)

        # Get changed files (same logic as daemon)
        git diff --name-only >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
        git diff --cached --name-only >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
        git ls-files --others --exclude-standard >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true

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
            cli_info "Files: No changes detected"
        else
            file_count=$(sort -u "$changed_files" | wc -l | tr -d ' ')
            cli_info "Files: Would backup $file_count files"
            cli_info ""

            if [ "$CHECKPOINT_LOG_LEVEL" -ge "$LOG_LEVEL_DEBUG" ] 2>/dev/null; then
                cli_verbose "   Changed files:"
                sort -u "$changed_files" | head -20 | while read -r file; do
                    cli_verbose "   $file"
                done
                if [ $file_count -gt 20 ]; then
                    cli_verbose "   ... and $((file_count - 20)) more"
                fi
            fi
        fi

        rm "$changed_files"
    fi

    cli_info ""
    cli_info "Dry run complete. Use 'backup-now.sh --force' to execute."
    log_info "Dry run complete"
    exit 0
fi

# ==============================================================================
# BACKUP EXECUTION
# ==============================================================================

# Acquire lock
if ! acquire_backup_lock "$PROJECT_NAME"; then
    cli_error "Failed to acquire backup lock"
    log_error "Failed to acquire backup lock for $PROJECT_NAME"
    exit 3
fi

# Ensure lock is released on exit
trap 'release_backup_lock' EXIT

# Initialize backup directories
if ! init_backup_dirs; then
    cli_error "Failed to initialize backup directories"
    log_error "Failed to initialize backup directories"
    exit 2
fi

# Track backup start time
backup_start=$(date +%s)

# Initialize JSON state tracking
init_backup_state

# Initialize error counter (used for legacy database backup path)
backup_errors=0

cli_info "Backup in progress..."
cli_info ""
log_info "Backup execution starting"

# ==============================================================================
# DATABASE BACKUP (Universal Auto-Detection)
# ==============================================================================

if [ "$FILES_ONLY" = false ]; then
    cli_info "   Databases: Auto-detecting..."

    # Use universal database detector
    if command -v backup_detected_databases &>/dev/null; then
        if backup_detected_databases "$PROJECT_DIR" "$BACKUP_DIR"; then
            cli_success "   Databases: Backup complete"
            log_info "Database backup complete"
        else
            cli_info "   Databases: Some backups failed (see above)"
            log_warn "Some database backups failed"
            backup_errors=$((backup_errors + 1))
        fi
    else
        # Fallback to legacy SQLite-only backup if detector not available
        if [ -n "${DB_PATH:-}" ] && [ -f "$DB_PATH" ]; then
            cli_info "   Database: Backing up (legacy SQLite)..."
            log_info "Legacy SQLite backup: $DB_PATH"

            timestamp=$(date '+%m.%d.%y - %H:%M')
            backup_file="$DATABASE_DIR/${PROJECT_NAME} - ${timestamp}.db.gz"

            if [ "${DB_TYPE:-sqlite}" = "sqlite" ]; then
                if sqlite3 "$DB_PATH" ".backup /tmp/${PROJECT_NAME}_temp.db" && \
                   gzip -c "/tmp/${PROJECT_NAME}_temp.db" > "$backup_file" && \
                   rm "/tmp/${PROJECT_NAME}_temp.db"; then

                    backup_size=$(get_file_size "$backup_file")
                    backup_size_human=$(format_bytes $backup_size)
                    cli_success "   Database: Done ($backup_size_human compressed)"
                    log_info "Database backup done: $backup_size_human compressed"
                else
                    cli_error "   Database: Failed"
                    log_error "Database backup failed for $DB_PATH"
                    backup_errors=$((backup_errors + 1))
                fi
            else
                cli_error "   Database: Unsupported type: ${DB_TYPE}"
                log_error "Unsupported database type: ${DB_TYPE}"
                backup_errors=$((backup_errors + 1))
            fi
        else
            cli_verbose "   Database: No databases detected"
            log_debug "No databases detected"
        fi
    fi
fi

# ==============================================================================
# FILE BACKUP
# ==============================================================================

if [ "$DATABASE_ONLY" = false ]; then
    cli_info "   Files: Scanning for changes..."

    cd "$PROJECT_DIR" || exit 2

    changed_files=$(mktemp)

    # Detect if this is the first backup
    # Issue #9: Filter .DS_Store and other system files from emptiness check
    is_first_backup=false
    if [ ! -d "$FILES_DIR" ]; then
        is_first_backup=true
    else
        # Count real files (excluding .DS_Store, .localized, etc.)
        real_file_count=$(find "$FILES_DIR" -type f \
            ! -name ".DS_Store" \
            ! -name ".localized" \
            ! -name "*.swp" \
            ! -name "*~" \
            2>/dev/null | wc -l | tr -d ' ')
        if [ "$real_file_count" -eq 0 ]; then
            is_first_backup=true
        fi
    fi
    if [ "$is_first_backup" = true ]; then
        cli_info "   Files: First backup detected - will backup all tracked files"
        log_info "First backup detected for $PROJECT_NAME"
    fi

    # Get changed files
    if [ "$is_first_backup" = true ]; then
        # FIRST BACKUP: Include ALL tracked git files
        git ls-files >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
        git ls-files --others --exclude-standard >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true

        # FALLBACK: If no git repo, use find to get all files
        if [ ! -s "$changed_files" ]; then
            cli_verbose "   No git repository detected - using file system scan"
            log_debug "No git repo, falling back to filesystem scan"
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
        git diff --name-only >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
        git diff --cached --name-only >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
        git ls-files --others --exclude-standard >> "$changed_files" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true

        # FALLBACK: If no git repo, backup modified files (by mtime)
        if [ ! -s "$changed_files" ]; then
            cli_verbose "   No git repository detected - using mtime check"
            log_debug "No git repo, falling back to mtime check"
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

    # Issue #11: Always backup the backup config itself
    [ -f ".backup-config.sh" ] && echo ".backup-config.sh" >> "$changed_files"

    if [ ! -s "$changed_files" ]; then
        cli_info "   Files: No changes detected"
        log_info "No file changes detected"
    else
        file_count=0
        archived_count=0
        # Issue #5: Add PID suffix to prevent timestamp collisions
        # Issue #13: Use UTC or local time based on config
        timestamp=$(get_backup_timestamp)_$$

        # Create manifest for verification
        manifest_file=$(mktemp)

        total_files=$(sort -u "$changed_files" | wc -l | tr -d ' ')
        BACKUP_STATE_TOTAL_FILES=$total_files

        # Build manifest: capture file metadata at backup START
        cli_verbose "   Creating backup manifest..."
        log_debug "Building backup manifest for $total_files files"
        while IFS= read -r file; do
            # Skip backups directory and non-existent files
            if [[ "$file" == backups/* ]] || [ ! -f "$file" ]; then
                continue
            fi
            file_size=$(get_file_size "$file")
            echo "$file|$file_size" >> "$manifest_file"
        done < <(sort -u "$changed_files")

        if [ "$is_first_backup" = true ]; then
            cli_info "   Files: Initial backup - copying $total_files files..."
            log_info "Initial backup: $total_files files"
        else
            cli_info "   Files: $total_files modified files found"
            cli_info "   Files: Backing up changes..."
            log_info "Incremental backup: $total_files modified files"
        fi

        # Set defaults for file size limits (no limit by default - backup everything)
        MAX_BACKUP_FILE_SIZE="${MAX_BACKUP_FILE_SIZE:-0}"  # 0 = no limit
        BACKUP_LARGE_FILES="${BACKUP_LARGE_FILES:-true}"
        skipped_large_files=0
        skipped_symlinks=0

        while IFS= read -r file; do
            if [ -z "$file" ]; then continue; fi
            if [ ! -e "$file" ]; then continue; fi
            if [[ "$file" == backups/* ]]; then continue; fi

            # Issue #7: Skip symlinks for safety (avoid following to system files or loops)
            if [ -L "$file" ]; then
                skipped_symlinks=$((skipped_symlinks + 1))
                if [ "$CHECKPOINT_LOG_LEVEL" -ge "$LOG_LEVEL_DEBUG" ] 2>/dev/null; then
                    cli_verbose "      Skipped symlink: $file"
                fi
                log_trace "Skipped symlink: $file"
                continue
            fi

            # Must be a regular file
            if [ ! -f "$file" ]; then continue; fi

            # Issue #6: Check file size limits
            if [ "$MAX_BACKUP_FILE_SIZE" -gt 0 ] && [ "$BACKUP_LARGE_FILES" != "true" ]; then
                file_size=$(get_file_size "$file")
                if [ "$file_size" -gt "$MAX_BACKUP_FILE_SIZE" ]; then
                    skipped_large_files=$((skipped_large_files + 1))
                    file_size_mb=$((file_size / 1048576))
                    max_size_mb=$((MAX_BACKUP_FILE_SIZE / 1048576))
                    cli_warn "      Skipped large file (${file_size_mb}MB > ${max_size_mb}MB limit): $file"
                    log_debug "Skipped large file (${file_size_mb}MB > ${max_size_mb}MB): $file"
                    continue
                fi
            fi

            current_file="$FILES_DIR/$file"
            current_dir=$(dirname "$current_file")
            archived_file="$ARCHIVED_DIR/${file}.${timestamp}"
            archived_dir=$(dirname "$archived_file")

            # Secondary destination paths (for dual-write)
            secondary_file=""
            secondary_dir=""
            secondary_archived_file=""
            secondary_archived_dir=""
            if [[ -n "${SECONDARY_FILES_DIR:-}" ]]; then
                secondary_file="$SECONDARY_FILES_DIR/$file"
                secondary_dir=$(dirname "$secondary_file")
                secondary_archived_file="$SECONDARY_ARCHIVED_DIR/${file}.${timestamp}"
                secondary_archived_dir=$(dirname "$secondary_archived_file")
            fi

            mkdir -p "$current_dir"

            # Check if file changed
            if [ -f "$current_file" ]; then
                # Use hash comparison if enabled, fall back to cmp
                files_are_identical=false
                if [ "$BACKUP_USE_HASH_COMPARE" = "true" ]; then
                    # Try hash-based comparison first (faster for large files)
                    if files_identical_hash "$file" "$current_file" 2>/dev/null; then
                        files_are_identical=true
                    fi
                else
                    # Use byte-by-byte comparison (fallback)
                    if cmp -s "$file" "$current_file"; then
                        files_are_identical=true
                    fi
                fi

                if [ "$files_are_identical" = "false" ]; then
                    mkdir -p "$archived_dir"
                    mv "$current_file" "$archived_file"
                    archived_count=$((archived_count + 1))

                    # Copy with retry logic (3 attempts)
                    if copy_with_retry "$file" "$current_file" 3; then
                        file_count=$((file_count + 1))
                        BACKUP_STATE_SUCCEEDED_FILES=$((BACKUP_STATE_SUCCEEDED_FILES + 1))
                        if [ "$CHECKPOINT_LOG_LEVEL" -ge "$LOG_LEVEL_DEBUG" ] 2>/dev/null; then
                            cli_verbose "      Backed up: $file"
                        fi
                        log_trace "Backed up: $file"

                        # Dual-write to secondary if configured
                        if [[ -n "$secondary_file" ]]; then
                            mkdir -p "$secondary_dir"
                            if [[ -f "$secondary_file" ]]; then
                                mkdir -p "$secondary_archived_dir"
                                mv "$secondary_file" "$secondary_archived_file" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
                            fi
                            if ! cp "$current_file" "$secondary_file" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                                cli_verbose "      Secondary copy failed: $file"
                                log_debug "Secondary copy failed: $file"
                            fi
                        fi
                    else
                        # Primary copy failed - try secondary as fallback
                        if [[ -n "$secondary_file" ]]; then
                            mkdir -p "$secondary_dir"
                            if copy_with_retry "$file" "$secondary_file" 3; then
                                cli_warn "      Primary failed, saved to secondary: $file"
                                log_warn "Primary copy failed, saved to secondary: $file"
                                file_count=$((file_count + 1))
                                BACKUP_STATE_SUCCEEDED_FILES=$((BACKUP_STATE_SUCCEEDED_FILES + 1))
                            else
                                # Both failed - use standardized error codes
                                raw_code="${COPY_FAILURE_REASON:-copy_failed}"
                                error_code=$(map_error_to_code "$raw_code")
                                suggested_fix=$(get_error_suggestion "$error_code")
                                add_file_failure "$file" "$error_code" "Copy failed to primary and secondary" "$suggested_fix" 3
                                cli_error "      Failed: $file ($error_code)"
                                log_error "Copy failed (primary+secondary): $file error=$error_code"
                            fi
                        else
                            # No secondary, primary failed - use standardized error codes
                            raw_code="${COPY_FAILURE_REASON:-copy_failed}"
                            error_code=$(map_error_to_code "$raw_code")
                            suggested_fix=$(get_error_suggestion "$error_code")

                            add_file_failure "$file" "$error_code" "Copy failed after 3 retries" "$suggested_fix" 3
                            cli_error "      Failed: $file ($error_code)"
                            log_error "Copy failed after 3 retries: $file error=$error_code"
                        fi
                    fi
                fi
            else
                # Copy with retry logic (3 attempts)
                if copy_with_retry "$file" "$current_file" 3; then
                    file_count=$((file_count + 1))
                    BACKUP_STATE_SUCCEEDED_FILES=$((BACKUP_STATE_SUCCEEDED_FILES + 1))
                    if [ "$CHECKPOINT_LOG_LEVEL" -ge "$LOG_LEVEL_DEBUG" ] 2>/dev/null; then
                        cli_verbose "      New file: $file"
                    fi
                    log_trace "New file: $file"

                    # Dual-write to secondary if configured
                    if [[ -n "$secondary_file" ]]; then
                        mkdir -p "$secondary_dir"
                        if ! cp "$current_file" "$secondary_file" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                            cli_verbose "      Secondary copy failed: $file"
                            log_debug "Secondary copy failed: $file"
                        fi
                    fi
                else
                    # Primary copy failed - try secondary as fallback
                    if [[ -n "$secondary_file" ]]; then
                        mkdir -p "$secondary_dir"
                        if copy_with_retry "$file" "$secondary_file" 3; then
                            cli_warn "      Primary failed, saved to secondary: $file"
                            log_warn "Primary copy failed, saved to secondary: $file"
                            file_count=$((file_count + 1))
                            BACKUP_STATE_SUCCEEDED_FILES=$((BACKUP_STATE_SUCCEEDED_FILES + 1))
                        else
                            # Both failed - use standardized error codes
                            raw_code="${COPY_FAILURE_REASON:-copy_failed}"
                            error_code=$(map_error_to_code "$raw_code")
                            suggested_fix=$(get_error_suggestion "$error_code")
                            add_file_failure "$file" "$error_code" "Copy failed to primary and secondary" "$suggested_fix" 3
                            cli_error "      Failed: $file ($error_code)"
                            log_error "Copy failed (primary+secondary): $file error=$error_code"
                        fi
                    else
                        # No secondary, primary failed - use standardized error codes
                        raw_code="${COPY_FAILURE_REASON:-copy_failed}"
                        error_code=$(map_error_to_code "$raw_code")
                        suggested_fix=$(get_error_suggestion "$error_code")

                        add_file_failure "$file" "$error_code" "Copy failed after 3 retries" "$suggested_fix" 3
                        cli_error "      Failed: $file ($error_code)"
                        log_error "Copy failed after 3 retries: $file error=$error_code"
                    fi
                fi
            fi

        done < <(sort -u "$changed_files")

        rm "$changed_files"

        # ==============================================================================
        # POST-BACKUP VERIFICATION
        # ==============================================================================

        cli_verbose "   Verifying backup integrity..."
        log_debug "Starting post-backup verification"

        # Verify each file in manifest was actually backed up
        while IFS='|' read -r file expected_size; do
            backup_file="$FILES_DIR/$file"

            if [ ! -f "$backup_file" ]; then
                # File missing from backup - use standardized error code
                error_code=$(map_error_to_code "file_missing")
                suggested_fix=$(get_error_suggestion "$error_code")
                add_file_failure "$file" "$error_code" "File missing from backup" "$suggested_fix" 0
                cli_error "      Verification failed: $file (missing from backup)"
                log_error "Verification failed: $file missing from backup"
            else
                # Check size matches
                actual_size=$(get_file_size "$backup_file")
                if [ "$actual_size" != "$expected_size" ]; then
                    # Size mismatch - use standardized error code
                    error_code=$(map_error_to_code "size_mismatch")
                    suggested_fix=$(get_error_suggestion "$error_code")
                    add_file_failure "$file" "$error_code" "Size: expected $expected_size, got $actual_size" "$suggested_fix" 0
                    cli_error "      Verification failed: $file (size mismatch: expected $expected_size, got $actual_size)"
                    log_error "Verification failed: $file size mismatch expected=$expected_size actual=$actual_size"
                fi
            fi
        done < "$manifest_file"

        # Persist JSON manifest for later verification audits
        if type persist_manifest_json &>/dev/null; then
            cli_verbose "   Persisting verification manifest..."
            log_debug "Persisting verification manifest"
            if persist_manifest_json "$BACKUP_DIR" "$FILES_DIR" "$DATABASE_DIR" "$PROJECT_NAME"; then
                cli_verbose "   Manifest saved: $BACKUP_DIR/.checkpoint-manifest.json"
                log_debug "Manifest saved: $BACKUP_DIR/.checkpoint-manifest.json"
            else
                cli_warn "   Warning: Could not persist verification manifest (non-fatal)"
                log_warn "Could not persist verification manifest"
            fi
        fi

        # Cleanup temp files
        rm -f "$manifest_file"

        # Report results
        if [ $file_count -gt 0 ]; then
            if [ $BACKUP_STATE_FAILED_FILES -eq 0 ]; then
                # All files backed up successfully
                if [ "$is_first_backup" = true ]; then
                    cli_success "   Files: Initial backup complete - $file_count files copied"
                    log_info "Initial backup complete: $file_count files"
                else
                    cli_success "   Files: $file_count files backed up ($archived_count archived)"
                    log_info "Backup complete: $file_count files, $archived_count archived"
                fi
            else
                # Some files failed
                if [ "$is_first_backup" = true ]; then
                    cli_error "   Files: Backup incomplete - $file_count succeeded, $BACKUP_STATE_FAILED_FILES failed"
                    log_error "Backup incomplete: $file_count succeeded, $BACKUP_STATE_FAILED_FILES failed"
                else
                    cli_error "   Files: Backup incomplete - $file_count succeeded, $BACKUP_STATE_FAILED_FILES failed ($archived_count archived)"
                    log_error "Backup incomplete: $file_count succeeded, $BACKUP_STATE_FAILED_FILES failed, $archived_count archived"
                fi
            fi

            # Auto-commit to git (if enabled)
            if [ "$AUTO_COMMIT_ENABLED" = true ]; then
                if git add -A 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" && git commit -m "$GIT_COMMIT_MESSAGE" -q 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                    cli_success "   Git: Changes committed"
                    log_info "Auto-commit: changes committed"
                fi
            fi
        else
            cli_info "   Files: No changes to backup"
            log_info "No file changes to backup"
        fi
    fi
fi

# ==============================================================================
# GITHUB AUTO-PUSH
# ==============================================================================

# Set defaults for push config
GIT_AUTO_PUSH_ENABLED="${GIT_AUTO_PUSH_ENABLED:-false}"
GIT_PUSH_INTERVAL="${GIT_PUSH_INTERVAL:-7200}"
GIT_PUSH_REMOTE="${GIT_PUSH_REMOTE:-origin}"
GIT_PUSH_BRANCH="${GIT_PUSH_BRANCH:-}"
GIT_PUSH_STATE="${GIT_PUSH_STATE:-$STATE_DIR/${PROJECT_NAME}/.last-git-push}"

if [ "$GIT_AUTO_PUSH_ENABLED" = true ]; then
    # Ensure state directory exists
    mkdir -p "$(dirname "$GIT_PUSH_STATE")" 2>/dev/null || true

    # Check if we're in a git repo with a remote
    if git remote get-url "$GIT_PUSH_REMOTE" &>/dev/null; then
        # Get last push time
        last_push_time=0
        if [ -f "$GIT_PUSH_STATE" ]; then
            last_push_time=$(cat "$GIT_PUSH_STATE" 2>/dev/null || echo "0")
        fi

        current_time=$(date +%s)
        time_since_push=$((current_time - last_push_time))

        # Check if push interval has elapsed
        if [ $time_since_push -ge $GIT_PUSH_INTERVAL ]; then
            # Determine branch to push
            push_branch="$GIT_PUSH_BRANCH"
            if [ -z "$push_branch" ]; then
                push_branch=$(git branch --show-current 2>/dev/null)
            fi

            if [ -n "$push_branch" ]; then
                # Check if there are commits to push
                local_commits=$(git rev-list --count "$GIT_PUSH_REMOTE/$push_branch..HEAD" 2>/dev/null || echo "0")

                if [ "$local_commits" -gt 0 ]; then
                    cli_info "   GitHub: Pushing $local_commits commit(s) to $GIT_PUSH_REMOTE/$push_branch..."
                    log_info "Pushing $local_commits commit(s) to $GIT_PUSH_REMOTE/$push_branch"

                    if git push "$GIT_PUSH_REMOTE" "$push_branch" -q 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                        echo "$current_time" > "$GIT_PUSH_STATE"
                        cli_success "   GitHub: Pushed to $GIT_PUSH_REMOTE/$push_branch"
                        log_info "Push succeeded to $GIT_PUSH_REMOTE/$push_branch"
                    else
                        cli_error "   GitHub: Push failed - check authentication (run: gh auth login)"
                        log_error "Git push failed to $GIT_PUSH_REMOTE/$push_branch"
                    fi
                else
                    # No commits to push, but update timestamp
                    echo "$current_time" > "$GIT_PUSH_STATE"
                    cli_verbose "   GitHub: Already up to date"
                    log_debug "Git push: already up to date"
                fi
            else
                cli_error "   GitHub: No branch detected"
                log_error "Git push: no branch detected"
            fi
        else
            remaining=$((GIT_PUSH_INTERVAL - time_since_push))
            remaining_min=$((remaining / 60))
            cli_verbose "   GitHub: Next push in ${remaining_min}m"
            log_debug "Git push: next in ${remaining_min}m"
        fi
    else
        cli_verbose "   GitHub: No remote '$GIT_PUSH_REMOTE' configured"
        log_debug "Git push: no remote '$GIT_PUSH_REMOTE' configured"
    fi
fi

# ==============================================================================
# CLEANUP
# ==============================================================================

cli_info "   Cleanup: Checking retention..."
log_debug "Starting cleanup"

# Use single-pass cleanup (performance optimization) or legacy mode
if [ "${BACKUP_USE_LEGACY_CLEANUP:-false}" = "true" ]; then
    # Legacy cleanup: multiple find traversals
    db_removed=$(find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} 2>/dev/null | wc -l | tr -d ' ')
    find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true

    file_removed=$(find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} 2>/dev/null | wc -l | tr -d ' ')
    find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true

    find "$ARCHIVED_DIR" -type d -empty -delete 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" || true
else
    # Single-pass cleanup (10x faster for large backup sets)
    if [ "$CHECKPOINT_LOG_LEVEL" -ge "$LOG_LEVEL_DEBUG" ] 2>/dev/null; then
        cleanup_start=$(date +%s%3N 2>/dev/null || date +%s)
    fi

    cleanup_single_pass "$BACKUP_DIR"

    db_removed=${#CLEANUP_EXPIRED_DBS[@]}
    file_removed=${#CLEANUP_EXPIRED_FILES[@]}

    if [ $db_removed -gt 0 ] || [ $file_removed -gt 0 ] || [ ${#CLEANUP_EMPTY_DIRS[@]} -gt 0 ]; then
        cleanup_execute false
    fi

    if [ "$CHECKPOINT_LOG_LEVEL" -ge "$LOG_LEVEL_DEBUG" ] 2>/dev/null; then
        cleanup_end=$(date +%s%3N 2>/dev/null || date +%s)
        cli_verbose "   Cleanup completed in $((cleanup_end - cleanup_start))ms"
        log_debug "Cleanup completed in $((cleanup_end - cleanup_start))ms"
    fi
fi

if [ $db_removed -gt 0 ] || [ $file_removed -gt 0 ]; then
    space_freed=$((db_removed + file_removed))
    cli_success "   Cleanup: $db_removed old database backups, $file_removed old files removed"
    log_info "Cleanup: removed $db_removed DB backups, $file_removed files"
else
    cli_verbose "   Cleanup: No old backups to remove"
    log_debug "Cleanup: nothing to remove"
fi

# ==============================================================================
# CLOUD SYNC QUEUE (Fallback handling)
# ==============================================================================

# Queue for cloud sync if rclone fallback was triggered
if [[ "${RCLONE_SYNC_PENDING:-false}" == "true" ]]; then
    source "$LIB_DIR/backup-queue.sh"
    enqueue_backup_sync "$PROJECT_NAME" "$PRIMARY_BACKUP_DIR" "rclone" >/dev/null
    cli_info "   Queue: Backup queued for cloud sync when connectivity restores"
    log_info "Backup queued for cloud sync (rclone pending)"
fi

# Opportunistically process queue (non-blocking, max 3 entries)
if [ -f "$LIB_DIR/backup-queue.sh" ]; then
    source "$LIB_DIR/backup-queue.sh"
    if has_pending_queue 2>/dev/null; then
        process_backup_queue 3 &
    fi
fi

# ==============================================================================
# UPDATE STATE
# ==============================================================================

backup_end=$(date +%s)
backup_duration=$((backup_end - backup_start))

# Ensure project-specific state directory exists
mkdir -p "$(dirname "$BACKUP_TIME_STATE")" 2>/dev/null || true
echo "$backup_end" > "$BACKUP_TIME_STATE"

# ==============================================================================
# SUMMARY
# ==============================================================================

cli_info ""

# Calculate final status
total_failed=$((BACKUP_STATE_FAILED_FILES + BACKUP_STATE_FAILED_DBS))

if [ $total_failed -eq 0 ]; then
    cli_success "TRUE SUCCESS: 100% backed up in ${backup_duration}s"
    log_info "Backup complete: 100% success in ${backup_duration}s"
else
    # Partial success - some files backed up despite errors
    cli_warn "PARTIAL SUCCESS: $BACKUP_STATE_SUCCEEDED_FILES/$BACKUP_STATE_TOTAL_FILES files backed up, $total_failed FAILED"
    cli_warn "    Run 'backup-failures' for LLM-ready prompt to fix issues"
    log_warn "Backup partial: $BACKUP_STATE_SUCCEEDED_FILES/$BACKUP_STATE_TOTAL_FILES succeeded, $total_failed failed"
fi

cli_info ""
cli_info "Summary:"

# Get updated statistics
db_count=$(count_database_backups)
current_files=$(count_current_files)
archived_files=$(count_archived_files)

cli_info "   Database: $db_count snapshots"
cli_info "   Files: $current_files backed up, $archived_files archived"

if [ $db_removed -gt 0 ] || [ $file_removed -gt 0 ]; then
    cli_info "   Cleanup: $db_removed DB backups, $file_removed files removed"
fi

cli_info ""
cli_info "View status: ${COLOR_CYAN}backup-status.sh${COLOR_RESET}"

if [ -f "$LOG_FILE" ]; then
    cli_info "View logs: ${COLOR_CYAN}tail -f $LOG_FILE${COLOR_RESET}"
fi

cli_info ""

# ==============================================================================
# WRITE JSON STATE & EXIT WITH SIMPLE CODE
# ==============================================================================

# Determine exit code (0=success, 1=partial, 2=total failure)
total_succeeded=$((BACKUP_STATE_SUCCEEDED_FILES + BACKUP_STATE_SUCCEEDED_DBS))
total_failed=$((BACKUP_STATE_FAILED_FILES + BACKUP_STATE_FAILED_DBS))

if [ $total_succeeded -eq 0 ] && [ $total_failed -gt 0 ]; then
    # TOTAL FAILURE - nothing backed up
    final_exit_code=2
    cli_error ""
    cli_error "TOTAL FAILURE: No files or databases were backed up"
    log_error "Total failure: nothing backed up"
elif [ $total_failed -gt 0 ]; then
    # PARTIAL SUCCESS - some failed
    final_exit_code=1
else
    # TRUE SUCCESS - 100% backed up
    final_exit_code=0
fi

# Calculate backup size from cloud folder
BACKUP_STATE_SIZE=0
BACKUP_STATE_SIZE_HUMAN="0B"
if [[ -n "${CLOUD_FOLDER_PATH:-}" ]] && [[ -d "${CLOUD_FOLDER_PATH}/${PROJECT_NAME}" ]]; then
    size_output=$(du -sh "${CLOUD_FOLDER_PATH}/${PROJECT_NAME}" 2>/dev/null | cut -f1)
    size_bytes=$(du -s "${CLOUD_FOLDER_PATH}/${PROJECT_NAME}" 2>/dev/null | cut -f1)
    BACKUP_STATE_SIZE="${size_bytes:-0}"
    BACKUP_STATE_SIZE_HUMAN="${size_output:-0B}"
fi

# Write complete JSON state
state_file=$(write_backup_state "$final_exit_code")

cli_info ""
cli_info "State saved to: $state_file"

# Write heartbeat for helper app
HEARTBEAT_DIR="$HOME/.checkpoint"
HEARTBEAT_FILE="$HEARTBEAT_DIR/daemon.heartbeat"
mkdir -p "$HEARTBEAT_DIR"

now=$(date +%s)
if [[ $final_exit_code -eq 0 ]]; then
    hb_status="healthy"
    hb_error=""
elif [[ $final_exit_code -eq 1 ]]; then
    hb_status="error"
    hb_error="Partial backup: $BACKUP_STATE_FAILED_FILES file(s) failed"
else
    hb_status="error"
    hb_error="Backup failed completely"
fi

if [[ -n "$hb_error" ]]; then
    hb_error_json="\"$hb_error\""
else
    hb_error_json="null"
fi

cat > "$HEARTBEAT_FILE" <<EOF
{
  "timestamp": $now,
  "status": "$hb_status",
  "project": "$PROJECT_NAME",
  "last_backup": $now,
  "last_backup_files": $BACKUP_STATE_SUCCEEDED_FILES,
  "error": $hb_error_json,
  "pid": $$
}
EOF

# Update registry with last backup time (for successful or partial backups)
if [[ $final_exit_code -le 1 ]] && type update_last_backup &>/dev/null; then
    update_last_backup "$PROJECT_DIR"
fi

# Send notification based on JSON state
if [ -f "$state_file" ]; then
    # Read actions from JSON state (use || true to prevent exit on no-match)
    send_notif=$(grep -o '"send_notification":[^,}]*' "$state_file" 2>/dev/null | cut -d':' -f2 | tr -d ' ' || true)
    notif_title=$(grep -o '"title":"[^"]*"' "$state_file" 2>/dev/null | head -1 | cut -d'"' -f4 || true)
    notif_message=$(grep -o '"message":"[^"]*"' "$state_file" 2>/dev/null | head -1 | cut -d'"' -f4 || true)

    if [ "$send_notif" = "true" ]; then
        # Determine sound based on exit code
        sound="default"
        case "$final_exit_code" in
            0) sound="Glass" ;;       # Success
            1) sound="Basso" ;;       # Partial
            2) sound="Sosumi" ;;      # Total failure
        esac

        send_notification "$notif_title" "$notif_message" "$sound"
    fi
fi

cli_info ""

# ==============================================================================
# CLOUD FOLDER SYNC (Dropbox/iCloud/Google Drive)
# ==============================================================================

CLOUD_FOLDER_FAILED=false

if [[ "${CLOUD_FOLDER_ENABLED:-false}" == "true" ]] && [[ -n "${CLOUD_FOLDER_PATH:-}" ]]; then
    cli_info "Syncing to cloud folder..."
    log_info "Starting cloud folder sync to $CLOUD_FOLDER_PATH"

    # Create cloud backup directory if needed (ignore errors if path doesn't exist)
    mkdir -p "$CLOUD_FOLDER_PATH/$PROJECT_NAME" 2>/dev/null || true

    if [[ -d "$CLOUD_FOLDER_PATH" ]]; then
        # Sync databases
        if [[ -d "$DATABASE_DIR" ]] && [[ "$(ls -A "$DATABASE_DIR" 2>/dev/null)" ]]; then
            if rsync -a --delete "$DATABASE_DIR/" "$CLOUD_FOLDER_PATH/$PROJECT_NAME/databases/" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                cli_info "   Databases synced"
                log_info "Cloud sync: databases synced"
            else
                cli_warn "   Database sync failed"
                log_warn "Cloud sync: database sync failed"
            fi
        fi

        # Sync critical files (not full file backups - too large)
        if [[ -d "$FILES_DIR" ]]; then
            # Only sync config and small critical files
            if rsync -a --include='.env*' --include='*.sh' --include='.claude/' --include='.claude/**' \
                  --exclude='node_modules/' --exclude='*.log' \
                  --max-size=1M \
                  "$FILES_DIR/" "$CLOUD_FOLDER_PATH/$PROJECT_NAME/files/" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                cli_info "   Critical files synced"
                log_info "Cloud sync: critical files synced"
            else
                cli_warn "   File sync failed"
                log_warn "Cloud sync: file sync failed"
            fi
        fi

        # Sync state file (for cross-computer portability)
        portable_state="${BACKUP_DIR:-$PROJECT_DIR/backups}/.checkpoint-state.json"
        if [[ -f "$portable_state" ]]; then
            if cp "$portable_state" "$CLOUD_FOLDER_PATH/$PROJECT_NAME/.checkpoint-state.json" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                cli_info "   State file synced"
                log_info "Cloud sync: state file synced"
            else
                cli_warn "   State sync failed"
                log_warn "Cloud sync: state sync failed"
            fi
        fi

        cli_info "   Cloud folder: $CLOUD_FOLDER_PATH/$PROJECT_NAME"
    else
        cli_warn "   Cloud folder not accessible: $CLOUD_FOLDER_PATH"
        log_warn "Cloud folder not accessible: $CLOUD_FOLDER_PATH"
        CLOUD_FOLDER_FAILED=true
    fi
fi

# ==============================================================================
# CLOUD DIRECT UPLOAD (via rclone)
# ==============================================================================
# Runs if:
#   1. Explicitly enabled (CLOUD_RCLONE_ENABLED=true), OR
#   2. Cloud folder sync failed and rclone is configured as fallback
# ==============================================================================

# Determine if we should use rclone
USE_RCLONE=false
RCLONE_REASON=""

if [[ "${CLOUD_RCLONE_ENABLED:-false}" == "true" ]] && [[ -n "${CLOUD_RCLONE_REMOTE:-}" ]]; then
    USE_RCLONE=true
    RCLONE_REASON="enabled"
elif [[ "$CLOUD_FOLDER_FAILED" == "true" ]] && [[ -n "${CLOUD_RCLONE_REMOTE:-}" ]]; then
    # Fallback: cloud folder not accessible but rclone is configured
    USE_RCLONE=true
    RCLONE_REASON="fallback"
    cli_info "Cloud folder unavailable - falling back to rclone..."
    log_info "Cloud folder unavailable, falling back to rclone"
fi

if [[ "$USE_RCLONE" == "true" ]] && [[ -n "${CLOUD_RCLONE_REMOTE:-}" ]]; then
    # Check if rclone is available
    if command -v rclone &>/dev/null; then
        cli_info "Uploading to cloud via rclone..."
        log_info "Starting rclone upload"

        rclone_dest="${CLOUD_RCLONE_REMOTE}:${CLOUD_RCLONE_PATH:-Backups/Checkpoint}/$PROJECT_NAME"

        # Sync databases
        if [[ -d "$DATABASE_DIR" ]] && [[ "$(ls -A "$DATABASE_DIR" 2>/dev/null)" ]]; then
            if rclone sync "$DATABASE_DIR/" "$rclone_dest/databases/" --quiet 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                cli_info "   Databases uploaded"
                log_info "rclone: databases uploaded"
            else
                cli_warn "   Database upload failed"
                log_warn "rclone: database upload failed"
            fi
        fi

        # Sync critical files (using filter for small important files)
        if [[ -d "$FILES_DIR" ]]; then
            # Create a temp filter file for rclone
            rclone_filter=$(mktemp)
            cat > "$rclone_filter" << 'RCLONE_FILTER'
+ .env*
+ *.sh
+ .claude/**
+ .backup-config.sh
+ CLAUDE.md
+ credentials.json
+ *.pem
- node_modules/**
- *.log
- **
RCLONE_FILTER

            if rclone sync "$FILES_DIR/" "$rclone_dest/files/" \
                --filter-from "$rclone_filter" \
                --max-size 1M \
                --quiet 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                cli_info "   Critical files uploaded"
                log_info "rclone: critical files uploaded"
            else
                cli_warn "   File upload failed"
                log_warn "rclone: file upload failed"
            fi

            rm -f "$rclone_filter"
        fi

        # Upload state file (for cross-computer portability)
        portable_state="${BACKUP_DIR:-$PROJECT_DIR/backups}/.checkpoint-state.json"
        if [[ -f "$portable_state" ]]; then
            if rclone copyto "$portable_state" "$rclone_dest/.checkpoint-state.json" --quiet 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                cli_info "   State file uploaded"
                log_info "rclone: state file uploaded"
            else
                cli_warn "   State upload failed"
                log_warn "rclone: state upload failed"
            fi
        fi

        cli_info "   Cloud destination: $rclone_dest"
    else
        cli_warn "   rclone not installed - skipping cloud upload"
        log_warn "rclone not installed, skipping cloud upload"
    fi
fi

# ==============================================================================
# CLEANUP
# ==============================================================================

# Stop Docker if we started it (for single-project backups)
# In multi-project backups, this is handled by backup-all-projects.sh
if type did_we_start_docker &>/dev/null && did_we_start_docker; then
    cli_info "Stopping Docker (we started it)..."
    log_info "Stopping Docker"
    stop_docker
fi

log_info "Backup finished, exit_code=$final_exit_code"

# Exit with simple code
exit $final_exit_code
