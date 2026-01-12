#!/usr/bin/env bash
# Checkpoint - Manual Backup Trigger
# Force an immediate backup with progress reporting

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Resolve symlinks to get actual script location
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
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
    echo "📦 First time backup - creating configuration..."
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

    echo "   ✅ Configuration created: .backup-config.sh"
    echo "   ✅ Backup directory: backups/"
    echo ""

    # Now load the config
    if ! load_backup_config "$PROJECT_DIR"; then
        log_error "Error: Failed to load auto-created configuration"
        exit 1
    fi
fi

# Register project if not already (for existing configs)
if type is_registered &>/dev/null && ! is_registered "$PROJECT_DIR"; then
    register_project "$PROJECT_DIR" "${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
fi

# Initialize state directories
init_state_dirs

# Ensure STATE_DIR is set for error logging
STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"

# ==============================================================================
# RESOLVE BACKUP DESTINATIONS (Cloud folder routing)
# ==============================================================================

# Resolve cloud folder destination (if enabled)
resolve_backup_destinations

# Create backup directories in resolved destinations
if ! ensure_backup_dirs; then
    log_error "Failed to create backup directories"
    exit 2
fi

# Log destination info
if [[ -n "${CLOUD_BACKUP_DIR:-}" ]]; then
    log_verbose "   Backup destination: $PRIMARY_BACKUP_DIR (cloud)"
    if [[ -n "${SECONDARY_BACKUP_DIR:-}" ]]; then
        log_verbose "   Also backing up to: $SECONDARY_BACKUP_DIR (local)"
    fi
else
    log_verbose "   Backup destination: $PRIMARY_BACKUP_DIR (local)"
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

# Display backup destination
if [[ -n "${CLOUD_BACKUP_DIR:-}" ]]; then
    log_info "📂 Backing up to: ${COLOR_CYAN}$PRIMARY_BACKUP_DIR${COLOR_RESET} (cloud)"
    if [[ -n "${SECONDARY_BACKUP_DIR:-}" ]]; then
        log_info "   Also backing up locally: ${COLOR_CYAN}$SECONDARY_BACKUP_DIR${COLOR_RESET}"
    fi
else
    log_info "📂 Backing up to: ${COLOR_CYAN}$PRIMARY_BACKUP_DIR${COLOR_RESET}"
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

# Initialize JSON state tracking
init_backup_state

# Initialize error counter (used for legacy database backup path)
backup_errors=0

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

    # Issue #11: Always backup the backup config itself
    [ -f ".backup-config.sh" ] && echo ".backup-config.sh" >> "$changed_files"

    if [ ! -s "$changed_files" ]; then
        log_info "   ▸ Files: No changes detected"
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

        # Set defaults for file size limits
        MAX_BACKUP_FILE_SIZE="${MAX_BACKUP_FILE_SIZE:-104857600}"  # 100MB default
        BACKUP_LARGE_FILES="${BACKUP_LARGE_FILES:-false}"
        skipped_large_files=0
        skipped_symlinks=0

        while IFS= read -r file; do
            if [ -z "$file" ]; then continue; fi
            if [ ! -e "$file" ]; then continue; fi
            if [[ "$file" == backups/* ]]; then continue; fi

            # Issue #7: Skip symlinks for safety (avoid following to system files or loops)
            if [ -L "$file" ]; then
                skipped_symlinks=$((skipped_symlinks + 1))
                if [ "$VERBOSE" = true ]; then
                    log_verbose "      ⊘ Skipped symlink: $file"
                fi
                continue
            fi

            # Must be a regular file
            if [ ! -f "$file" ]; then continue; fi

            # Issue #6: Check file size limits
            if [ "$MAX_BACKUP_FILE_SIZE" -gt 0 ] && [ "$BACKUP_LARGE_FILES" != "true" ]; then
                file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                if [ "$file_size" -gt "$MAX_BACKUP_FILE_SIZE" ]; then
                    skipped_large_files=$((skipped_large_files + 1))
                    file_size_mb=$((file_size / 1048576))
                    max_size_mb=$((MAX_BACKUP_FILE_SIZE / 1048576))
                    log_warn "      ⊘ Skipped large file (${file_size_mb}MB > ${max_size_mb}MB limit): $file"
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
                        if [ "$VERBOSE" = true ]; then
                            log_verbose "      • Backed up: $file"
                        fi

                        # Dual-write to secondary if configured
                        if [[ -n "$secondary_file" ]]; then
                            mkdir -p "$secondary_dir"
                            if [[ -f "$secondary_file" ]]; then
                                mkdir -p "$secondary_archived_dir"
                                mv "$secondary_file" "$secondary_archived_file" 2>/dev/null || true
                            fi
                            cp "$current_file" "$secondary_file" 2>/dev/null || \
                                log_verbose "      ⚠ Secondary copy failed: $file"
                        fi
                    else
                        # Primary copy failed - try secondary as fallback
                        if [[ -n "$secondary_file" ]]; then
                            mkdir -p "$secondary_dir"
                            if copy_with_retry "$file" "$secondary_file" 3; then
                                log_warn "      ⚠ Primary failed, saved to secondary: $file"
                                file_count=$((file_count + 1))
                                BACKUP_STATE_SUCCEEDED_FILES=$((BACKUP_STATE_SUCCEEDED_FILES + 1))
                            else
                                # Both failed
                                error_code="${COPY_FAILURE_REASON:-copy_failed}"
                                add_file_failure "$file" "$error_code" "Copy failed to primary and secondary" "Check cloud folder accessibility" 3
                                log_error "      ✗ Failed: $file ($error_code)"
                            fi
                        else
                            # No secondary, primary failed
                            error_code="${COPY_FAILURE_REASON:-copy_failed}"
                            suggested_fix=""

                            case "$error_code" in
                                "permission_denied")
                                    suggested_fix="Run: chmod +r \"$file\" or check file permissions"
                                    ;;
                                "disk_full")
                                    suggested_fix="Free disk space or move backups to larger drive"
                                    ;;
                                *)
                                    suggested_fix="Check file accessibility and try again"
                                    ;;
                            esac

                            add_file_failure "$file" "$error_code" "Copy failed after 3 retries" "$suggested_fix" 3
                            log_error "      ✗ Failed: $file ($error_code)"
                        fi
                    fi
                fi
            else
                # Copy with retry logic (3 attempts)
                if copy_with_retry "$file" "$current_file" 3; then
                    file_count=$((file_count + 1))
                    BACKUP_STATE_SUCCEEDED_FILES=$((BACKUP_STATE_SUCCEEDED_FILES + 1))
                    if [ "$VERBOSE" = true ]; then
                        log_verbose "      • New file: $file"
                    fi

                    # Dual-write to secondary if configured
                    if [[ -n "$secondary_file" ]]; then
                        mkdir -p "$secondary_dir"
                        cp "$current_file" "$secondary_file" 2>/dev/null || \
                            log_verbose "      ⚠ Secondary copy failed: $file"
                    fi
                else
                    # Primary copy failed - try secondary as fallback
                    if [[ -n "$secondary_file" ]]; then
                        mkdir -p "$secondary_dir"
                        if copy_with_retry "$file" "$secondary_file" 3; then
                            log_warn "      ⚠ Primary failed, saved to secondary: $file"
                            file_count=$((file_count + 1))
                            BACKUP_STATE_SUCCEEDED_FILES=$((BACKUP_STATE_SUCCEEDED_FILES + 1))
                        else
                            # Both failed
                            error_code="${COPY_FAILURE_REASON:-copy_failed}"
                            add_file_failure "$file" "$error_code" "Copy failed to primary and secondary" "Check cloud folder accessibility" 3
                            log_error "      ✗ Failed: $file ($error_code)"
                        fi
                    else
                        # No secondary, primary failed
                        error_code="${COPY_FAILURE_REASON:-copy_failed}"
                        suggested_fix=""

                        case "$error_code" in
                            "permission_denied")
                                suggested_fix="Run: chmod +r \"$file\" or check file permissions"
                                ;;
                            "disk_full")
                                suggested_fix="Free disk space or move backups to larger drive"
                                ;;
                            *)
                                suggested_fix="Check file accessibility and try again"
                                ;;
                        esac

                        add_file_failure "$file" "$error_code" "Copy failed after 3 retries" "$suggested_fix" 3
                        log_error "      ✗ Failed: $file ($error_code)"
                    fi
                fi
            fi

        done < <(sort -u "$changed_files")

        rm "$changed_files"

        # ==============================================================================
        # POST-BACKUP VERIFICATION
        # ==============================================================================

        log_verbose "   Verifying backup integrity..."

        # Verify each file in manifest was actually backed up
        while IFS='|' read -r file expected_size; do
            backup_file="$FILES_DIR/$file"

            if [ ! -f "$backup_file" ]; then
                # File missing from backup
                add_file_failure "$file" "file_missing" "File missing from backup" "File was deleted during backup (ignore if intentional)" 0
                log_error "      ✗ Verification failed: $file (missing from backup)"
            else
                # Check size matches
                actual_size=$(stat -f%z "$backup_file" 2>/dev/null || echo "0")
                if [ "$actual_size" != "$expected_size" ]; then
                    # Size mismatch - file may be corrupted or modified during backup
                    add_file_failure "$file" "size_mismatch" "Size: expected $expected_size, got $actual_size" "File was modified during backup. Retry backup to capture current version" 0
                    log_error "      ✗ Verification failed: $file (size mismatch: expected $expected_size, got $actual_size)"
                fi
            fi
        done < "$manifest_file"

        # Cleanup temp files
        rm -f "$manifest_file"

        # Report results
        if [ $file_count -gt 0 ]; then
            if [ $BACKUP_STATE_FAILED_FILES -eq 0 ]; then
                # All files backed up successfully
                if [ "$is_first_backup" = true ]; then
                    log_success "   ▸ Files: ✅ Initial backup complete - $file_count files copied"
                else
                    log_success "   ▸ Files: ✅ $file_count files backed up ($archived_count archived)"
                fi
            else
                # Some files failed
                if [ "$is_first_backup" = true ]; then
                    log_error "   ▸ Files: ⚠️ Backup incomplete - $file_count succeeded, $BACKUP_STATE_FAILED_FILES failed"
                else
                    log_error "   ▸ Files: ⚠️ Backup incomplete - $file_count succeeded, $BACKUP_STATE_FAILED_FILES failed ($archived_count archived)"
                fi
            fi

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
                    log_info "   ▸ GitHub: Pushing $local_commits commit(s) to $GIT_PUSH_REMOTE/$push_branch..."

                    if git push "$GIT_PUSH_REMOTE" "$push_branch" -q 2>/dev/null; then
                        echo "$current_time" > "$GIT_PUSH_STATE"
                        log_success "   ▸ GitHub: ✅ Pushed to $GIT_PUSH_REMOTE/$push_branch"
                    else
                        log_error "   ▸ GitHub: ❌ Push failed - check authentication (run: gh auth login)"
                    fi
                else
                    # No commits to push, but update timestamp
                    echo "$current_time" > "$GIT_PUSH_STATE"
                    log_verbose "   ▸ GitHub: Already up to date"
                fi
            else
                log_error "   ▸ GitHub: ❌ No branch detected"
            fi
        else
            remaining=$((GIT_PUSH_INTERVAL - time_since_push))
            remaining_min=$((remaining / 60))
            log_verbose "   ▸ GitHub: Next push in ${remaining_min}m"
        fi
    else
        log_verbose "   ▸ GitHub: No remote '$GIT_PUSH_REMOTE' configured"
    fi
fi

# ==============================================================================
# CLEANUP
# ==============================================================================

log_info "   ▸ Cleanup: Checking retention..."

# Use single-pass cleanup (performance optimization) or legacy mode
if [ "${BACKUP_USE_LEGACY_CLEANUP:-false}" = "true" ]; then
    # Legacy cleanup: multiple find traversals
    db_removed=$(find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} 2>/dev/null | wc -l | tr -d ' ')
    find "$DATABASE_DIR" -name "*.db.gz" -type f -mtime +${DB_RETENTION_DAYS} -delete 2>/dev/null || true

    file_removed=$(find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} 2>/dev/null | wc -l | tr -d ' ')
    find "$ARCHIVED_DIR" -type f -mtime +${FILE_RETENTION_DAYS} -delete 2>/dev/null || true

    find "$ARCHIVED_DIR" -type d -empty -delete 2>/dev/null || true
else
    # Single-pass cleanup (10x faster for large backup sets)
    if [ "${BACKUP_DEBUG:-false}" = "true" ]; then
        local cleanup_start cleanup_end
        cleanup_start=$(date +%s%3N 2>/dev/null || date +%s)
    fi

    cleanup_single_pass "$BACKUP_DIR"

    db_removed=${#CLEANUP_EXPIRED_DBS[@]}
    file_removed=${#CLEANUP_EXPIRED_FILES[@]}

    if [ $db_removed -gt 0 ] || [ $file_removed -gt 0 ] || [ ${#CLEANUP_EMPTY_DIRS[@]} -gt 0 ]; then
        cleanup_execute false
    fi

    if [ "${BACKUP_DEBUG:-false}" = "true" ]; then
        cleanup_end=$(date +%s%3N 2>/dev/null || date +%s)
        log_verbose "   Cleanup completed in $((cleanup_end - cleanup_start))ms"
    fi
fi

if [ $db_removed -gt 0 ] || [ $file_removed -gt 0 ]; then
    space_freed=$((db_removed + file_removed))
    log_success "   ▸ Cleanup: ✅ $db_removed old database backups, $file_removed old files removed"
else
    log_verbose "   ▸ Cleanup: ✅ No old backups to remove"
fi

# ==============================================================================
# CLOUD SYNC QUEUE (Fallback handling)
# ==============================================================================

# Queue for cloud sync if rclone fallback was triggered
if [[ "${RCLONE_SYNC_PENDING:-false}" == "true" ]]; then
    source "$LIB_DIR/backup-queue.sh"
    enqueue_backup_sync "$PROJECT_NAME" "$PRIMARY_BACKUP_DIR" "rclone" >/dev/null
    log_info "   ▸ Queue: Backup queued for cloud sync when connectivity restores"
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

log_info ""

# Calculate final status
total_failed=$((BACKUP_STATE_FAILED_FILES + BACKUP_STATE_FAILED_DBS))

if [ $total_failed -eq 0 ]; then
    log_success "✅ TRUE SUCCESS: 100% backed up in ${backup_duration}s"
else
    # Partial success - some files backed up despite errors
    log_warn "⚠️  PARTIAL SUCCESS: $BACKUP_STATE_SUCCEEDED_FILES/$BACKUP_STATE_TOTAL_FILES files backed up, $total_failed FAILED"
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
# WRITE JSON STATE & EXIT WITH SIMPLE CODE
# ==============================================================================

# Determine exit code (0=success, 1=partial, 2=total failure)
total_succeeded=$((BACKUP_STATE_SUCCEEDED_FILES + BACKUP_STATE_SUCCEEDED_DBS))
total_failed=$((BACKUP_STATE_FAILED_FILES + BACKUP_STATE_FAILED_DBS))

if [ $total_succeeded -eq 0 ] && [ $total_failed -gt 0 ]; then
    # TOTAL FAILURE - nothing backed up
    final_exit_code=2
    log_error ""
    log_error "❌ TOTAL FAILURE: No files or databases were backed up"
elif [ $total_failed -gt 0 ]; then
    # PARTIAL SUCCESS - some failed
    final_exit_code=1
else
    # TRUE SUCCESS - 100% backed up
    final_exit_code=0
fi

# Write complete JSON state
state_file=$(write_backup_state "$final_exit_code")

log_info ""
log_info "State saved to: $state_file"

# Send notification based on JSON state
if [ -f "$state_file" ]; then
    # Read actions from JSON state
    send_notif=$(grep -o '"send_notification":[^,}]*' "$state_file" | cut -d':' -f2 | tr -d ' ')
    notif_title=$(grep -o '"title":"[^"]*"' "$state_file" | head -1 | cut -d'"' -f4)
    notif_message=$(grep -o '"message":"[^"]*"' "$state_file" | head -1 | cut -d'"' -f4)

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

log_info ""

# Exit with simple code
exit $final_exit_code
