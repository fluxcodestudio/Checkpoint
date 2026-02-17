#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Configuration Management
# ==============================================================================
# @requires: none
# @provides: load_backup_config, check_drive, is_quiet_hours, should_notify,
#            config_key_to_var, config_var_to_key, config_get_schema,
#            config_validate_value, get_config_path, config_get_value,
#            config_get_all_values, config_set_value, config_create_from_template,
#            config_validate_file, config_profile_save, config_profile_load,
#            config_profile_list, config_audit_change
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_CONFIG:-}" ] && return || readonly _CHECKPOINT_CONFIG=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ==============================================================================
# CONFIGURATION LOADING
# ==============================================================================

# Load backup configuration from project directory
# Args: $1 = project directory (optional, defaults to PWD)
# Sets: All configuration variables from .backup-config.sh
load_backup_config() {
    local project_dir="${1:-$PWD}"
    local config_file="$project_dir/.backup-config.sh"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    source "$config_file"

    # Apply global defaults from ~/.config/checkpoint/config.sh
    apply_global_defaults

    return 0
}

# Apply global configuration defaults
# Sources ~/.config/checkpoint/config.sh and uses DEFAULT_* values as
# fallbacks for any per-project variable not already set.
apply_global_defaults() {
    local global_config="$HOME/.config/checkpoint/config.sh"
    if [ -f "$global_config" ]; then
        # Source into a subshell-safe temporary namespace
        # We only want DEFAULT_* and global preference variables
        local _saved_IFS="$IFS"
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            key="$(echo "$key" | tr -d '[:space:]')"
            # Strip surrounding quotes from value
            value="${value#\"}" ; value="${value%\"}"
            value="${value#\'}" ; value="${value%\'}"
            case "$key" in
                DEFAULT_BACKUP_INTERVAL)      : "${BACKUP_INTERVAL:=$value}" ;;
                DEFAULT_BACKUP_SCHEDULE)      : "${BACKUP_SCHEDULE:=$value}" ;;
                DEFAULT_SESSION_IDLE_THRESHOLD): "${SESSION_IDLE_THRESHOLD:=$value}" ;;
                DEFAULT_DB_RETENTION_DAYS)    : "${DB_RETENTION_DAYS:=$value}" ;;
                DEFAULT_FILE_RETENTION_DAYS)  : "${FILE_RETENTION_DAYS:=$value}" ;;
                DEFAULT_BACKUP_ENV_FILES)     : "${BACKUP_ENV_FILES:=$value}" ;;
                DEFAULT_BACKUP_CREDENTIALS)   : "${BACKUP_CREDENTIALS:=$value}" ;;
                DEFAULT_BACKUP_IDE_SETTINGS)  : "${BACKUP_IDE_SETTINGS:=$value}" ;;
                DEFAULT_BACKUP_AI_ARTIFACTS) : "${BACKUP_AI_ARTIFACTS:=$value}" ;;
                DEFAULT_STORAGE_WARNING_PERCENT) : "${STORAGE_WARNING_PERCENT:=$value}" ;;
                DEFAULT_STORAGE_CRITICAL_PERCENT) : "${STORAGE_CRITICAL_PERCENT:=$value}" ;;
                DEFAULT_STORAGE_CHECK_ENABLED) : "${STORAGE_CHECK_ENABLED:=$value}" ;;
                DEFAULT_STORAGE_CLEANUP_SUGGEST) : "${STORAGE_CLEANUP_SUGGEST:=$value}" ;;
                DEFAULT_ENCRYPTION_ENABLED) : "${ENCRYPTION_ENABLED:=$value}" ;;
                DEFAULT_ENCRYPTION_KEY_PATH) : "${ENCRYPTION_KEY_PATH:=$value}" ;;
                # Direct global config variables (not DEFAULT_ prefixed)
                CLOUD_FOLDER_ENABLED)     : "${CLOUD_FOLDER_ENABLED:=$value}" ;;
                CLOUD_FOLDER_PATH)        : "${CLOUD_FOLDER_PATH:=$value}" ;;
                CLOUD_RCLONE_ENABLED)     : "${CLOUD_RCLONE_ENABLED:=$value}" ;;
                CLOUD_RCLONE_REMOTE)      : "${CLOUD_RCLONE_REMOTE:=$value}" ;;
                CLOUD_RCLONE_PATH)        : "${CLOUD_RCLONE_PATH:=$value}" ;;
                ENCRYPTION_ENABLED)       : "${ENCRYPTION_ENABLED:=$value}" ;;
                ENCRYPTION_KEY_PATH)      : "${ENCRYPTION_KEY_PATH:=$value}" ;;
                BACKUP_REMOTE_DATABASES)  : "${BACKUP_REMOTE_DATABASES:=$value}" ;;
                AUTO_START_LOCAL_DB)      : "${AUTO_START_LOCAL_DB:=$value}" ;;
                STOP_DB_AFTER_BACKUP)     : "${STOP_DB_AFTER_BACKUP:=$value}" ;;
                BACKUP_DOCKER_DATABASES)  : "${BACKUP_DOCKER_DATABASES:=$value}" ;;
                AUTO_START_DOCKER)        : "${AUTO_START_DOCKER:=$value}" ;;
                STOP_DOCKER_AFTER_BACKUP) : "${STOP_DOCKER_AFTER_BACKUP:=$value}" ;;
                CLAUDE_CODE_INTEGRATION)  : "${CLAUDE_CODE_INTEGRATION:=$value}" ;;
                GIT_HOOKS_ENABLED)        : "${GIT_HOOKS_ENABLED:=$value}" ;;
                SHELL_INTEGRATION_ENABLED): "${SHELL_INTEGRATION_ENABLED:=$value}" ;;
                AUTO_UPDATE_CHECK)        : "${AUTO_UPDATE_CHECK:=$value}" ;;
                DESKTOP_NOTIFICATIONS)
                    if [ "$value" = "true" ]; then
                        : "${NOTIFICATIONS_ENABLED:=true}"
                    else
                        : "${NOTIFICATIONS_ENABLED:=false}"
                    fi
                    ;;
                NOTIFY_ON_FAILURE_ONLY)
                    if [ "$value" = "true" ]; then
                        : "${NOTIFY_ON_SUCCESS:=false}"
                        : "${NOTIFY_ON_ERROR:=true}"
                    fi
                    ;;
                COMPRESSION_LEVEL)            : "${COMPRESSION_LEVEL:=$value}" ;;
                DEBUG_MODE)
                    if [ "$value" = "true" ] && [ "${CHECKPOINT_LOG_LEVEL:-2}" -lt 3 ]; then
                        CHECKPOINT_LOG_LEVEL=3
                    fi
                    ;;
            esac
        done < "$global_config"
        IFS="$_saved_IFS"
    fi

    # Final fallbacks for variables that may still be unset
    : "${BACKUP_INTERVAL:=3600}"
    : "${BACKUP_SCHEDULE:=}"
    : "${SESSION_IDLE_THRESHOLD:=600}"
    : "${DB_RETENTION_DAYS:=30}"
    : "${FILE_RETENTION_DAYS:=60}"
    : "${BACKUP_ENV_FILES:=true}"
    : "${BACKUP_CREDENTIALS:=true}"
    : "${BACKUP_IDE_SETTINGS:=true}"
    : "${BACKUP_AI_ARTIFACTS:=true}"
    : "${AI_ARTIFACT_EXTRA_DIRS:=}"
    : "${AI_ARTIFACT_EXTRA_FILES:=}"
    : "${COMPRESSION_LEVEL:=6}"
    : "${NOTIFICATIONS_ENABLED:=true}"

    # Cloud folder sync defaults
    : "${CLOUD_FOLDER_ENABLED:=false}"
    : "${CLOUD_FOLDER_PATH:=}"
    : "${CLOUD_RCLONE_ENABLED:=false}"
    : "${CLOUD_RCLONE_REMOTE:=}"
    : "${CLOUD_RCLONE_PATH:=Backups/Checkpoint}"

    # Encryption defaults
    : "${ENCRYPTION_ENABLED:=false}"
    : "${ENCRYPTION_KEY_PATH:=$HOME/.config/checkpoint/age-key.txt}"

    # Database defaults
    : "${BACKUP_REMOTE_DATABASES:=true}"
    : "${AUTO_START_LOCAL_DB:=true}"
    : "${STOP_DB_AFTER_BACKUP:=true}"
    : "${BACKUP_DOCKER_DATABASES:=true}"
    : "${AUTO_START_DOCKER:=true}"
    : "${STOP_DOCKER_AFTER_BACKUP:=true}"

    # Integration defaults
    : "${CLAUDE_CODE_INTEGRATION:=true}"
    : "${GIT_HOOKS_ENABLED:=false}"
    : "${SHELL_INTEGRATION_ENABLED:=false}"
    : "${AUTO_UPDATE_CHECK:=true}"
}

# ==============================================================================
# BACKUP EXCLUDE PATTERNS
# ==============================================================================

# Get standard backup exclude patterns for rsync
# Returns: newline-separated list of --exclude arguments
# Used by: backup-now.sh (fallback mode), backup-diff.sh
get_backup_excludes() {
    local excludes=(
        'backups/'
        '.git/'
        'node_modules/'
        '.venv/'
        '__pycache__/'
        'dist/'
        'build/'
        '.next/'
        '.DS_Store'
        '.cache/'
        'coverage/'
        '.nyc_output/'
        '.turbo/'
        '.gradle/'
        '.maven/'
        'target/'
        'vendor/'
        '.parcel-cache/'
        '.sass-cache/'
        'logs/'
        '.nuxt/'
        '.output/'
        '.svelte-kit/'
        '.vercel/'
        '.netlify/'
        'htmlcov/'
        '*.pyc'
        '.pytest_cache/'
        '.mypy_cache/'
        '.ruff_cache/'
        '*.egg-info/'
        '.eggs/'
        'bower_components/'
        '.pnpm/'
    )
    local e
    for e in "${excludes[@]}"; do
        echo "--exclude=$e"
    done
}

# Get standard backup exclude patterns for find commands
# Returns: find-compatible ! -path arguments (one per line)
# Used by: backup-now.sh (non-git fallback), change-detection.sh
get_find_excludes() {
    local excludes=(
        'backups'
        '.git'
        'node_modules'
        '.venv'
        '__pycache__'
        'dist'
        'build'
        '.next'
        '.cache'
        'coverage'
        '.nyc_output'
        '.turbo'
        '.gradle'
        '.maven'
        'target'
        'vendor'
        '.parcel-cache'
        '.sass-cache'
        'logs'
        '.nuxt'
        '.output'
        '.svelte-kit'
        '.vercel'
        '.netlify'
        'htmlcov'
        '.pytest_cache'
        '.mypy_cache'
        '.ruff_cache'
        '.eggs'
        'bower_components'
        '.pnpm'
    )
    local e
    for e in "${excludes[@]}"; do
        echo "! -path '*/${e}/*'"
    done
    # File-level excludes (not directories)
    echo "! -path '*/.DS_Store'"
    echo "! -name '*.pyc'"
}

# ==============================================================================
# DRIVE VERIFICATION
# ==============================================================================

# Check if external drive is mounted (if verification enabled)
# Returns: 0 if check passes, 1 if drive not connected
check_drive() {
    if [ "${DRIVE_VERIFICATION_ENABLED:-false}" = false ]; then
        return 0  # Skip check if disabled
    fi

    if [ -z "${DRIVE_MARKER_FILE:-}" ]; then
        return 1
    fi

    if [ ! -f "$DRIVE_MARKER_FILE" ]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# LOGGING DEFAULTS
# ==============================================================================

# Log level: 0=ERROR, 1=WARN, 2=INFO, 3=DEBUG, 4=TRACE
# Can be overridden in .backup-config.sh or via --debug/--trace/--quiet flags
: "${CHECKPOINT_LOG_LEVEL:=2}"             # Default: INFO
: "${CHECKPOINT_LOG_MAX_SIZE:=10485760}"   # Default: 10MB (10 * 1024 * 1024)

# ==============================================================================
# ALERT CONFIGURATION
# ==============================================================================

# Health thresholds (hours without backup)
# Can be overridden in .backup-config.sh
: "${ALERT_WARNING_HOURS:=24}"
: "${ALERT_ERROR_HOURS:=72}"

# Notification preferences
# Can be overridden in .backup-config.sh
: "${NOTIFY_ON_SUCCESS:=false}"         # Only notify success after recovery
: "${NOTIFY_ON_WARNING:=true}"          # Notify on stale backups
: "${NOTIFY_ON_ERROR:=true}"            # Notify on failures
: "${NOTIFY_ESCALATION_HOURS:=3}"       # Hours between repeated alerts
: "${NOTIFY_SOUND:=default}"            # default, Basso, Glass, Hero, Pop, or none

# Storage monitoring thresholds
: "${STORAGE_WARNING_PERCENT:=80}"     # Warn when disk usage exceeds this %
: "${STORAGE_CRITICAL_PERCENT:=90}"    # Block backup when disk usage exceeds this %
: "${STORAGE_CHECK_ENABLED:=true}"     # Enable/disable pre-backup disk checks
: "${STORAGE_CLEANUP_SUGGEST:=true}"   # Show cleanup suggestions when space is low

# Encryption at rest — defaults now in apply_global_defaults() to allow global config override

# Per-project notification override
# Set in project's .backup-config.sh
: "${PROJECT_NOTIFY_ENABLED:=true}"     # Enable/disable for this project

# ==============================================================================
# QUIET HOURS
# ==============================================================================

# Quiet hours suppress non-critical notifications
# Format: START_HOUR-END_HOUR in 24h format (e.g., "22-07" = 10pm to 7am)
: "${QUIET_HOURS:=}"                    # Empty = no quiet hours
: "${QUIET_HOURS_BLOCK_ERRORS:=false}"  # Still notify critical errors during quiet hours

# Check if currently in quiet hours
# Returns: 0 if in quiet hours, 1 if not
is_quiet_hours() {
    local quiet_hours="${QUIET_HOURS:-}"

    # No quiet hours configured
    [[ -z "$quiet_hours" ]] && return 1

    # Parse start and end hours
    local start_hour="${quiet_hours%%-*}"
    local end_hour="${quiet_hours##*-}"

    # Validate format
    if ! [[ "$start_hour" =~ ^[0-9]+$ ]] || ! [[ "$end_hour" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    local current_hour
    current_hour=$(date +%H)
    current_hour=${current_hour#0}  # Remove leading zero

    # Handle overnight quiet hours (e.g., 22-07)
    if [[ $start_hour -gt $end_hour ]]; then
        # Quiet if after start OR before end
        if [[ $current_hour -ge $start_hour ]] || [[ $current_hour -lt $end_hour ]]; then
            return 0
        fi
    else
        # Normal range (e.g., 09-17)
        if [[ $current_hour -ge $start_hour ]] && [[ $current_hour -lt $end_hour ]]; then
            return 0
        fi
    fi

    return 1
}

# Check if notification should be sent (considering quiet hours and preferences)
# Args: $1 = urgency level (critical, high, medium, low)
should_notify() {
    local urgency="${1:-medium}"

    # Check if notifications enabled for this project
    if [[ "${PROJECT_NOTIFY_ENABLED:-true}" != "true" ]]; then
        return 1
    fi

    # Always notify critical if configured to bypass quiet hours
    if [[ "$urgency" == "critical" ]] && [[ "${QUIET_HOURS_BLOCK_ERRORS:-false}" != "true" ]]; then
        return 0
    fi

    # Check quiet hours
    if is_quiet_hours; then
        return 1  # Suppress notification
    fi

    return 0
}

# ==============================================================================
# CONFIGURATION MANAGEMENT
# ==============================================================================

# Configuration schema - defines all valid configuration keys with types and defaults
# Format: key="type|default|description"
# NOTE: Associative arrays require bash 4.0+, commented out for macOS bash 3.2 compatibility
# TODO: Implement bash 3.2-compatible config schema for backup-config command
# declare -A BACKUP_CONFIG_SCHEMA=(
#     # Project settings
#     ["project.name"]="string|MyProject|Project name for backup filenames"
#     ["project.dir"]="path||Project directory (auto-detected if empty)"
#
#     # Backup locations
#     ["locations.backup_dir"]="path|backups|Main backup directory (relative to project)"
#     ["locations.database_dir"]="path|\${BACKUP_DIR}/databases|Database backups subdirectory"
#     ["locations.files_dir"]="path|\${BACKUP_DIR}/files|Current file backups subdirectory"
#     ["locations.archived_dir"]="path|\${BACKUP_DIR}/archived|Archived file versions subdirectory"
#
#     # Database configuration
#     ["database.path"]="path||Database file path (empty if no database)"
#     ["database.type"]="enum:sqlite,none|sqlite|Database type"
#
#     # Retention policies
#     ["retention.database.time_based"]="integer|30|Database backup retention in days"
#     ["retention.database.never_delete"]="boolean|false|Never auto-delete database backups"
#     ["retention.files.time_based"]="integer|60|Archived file retention in days"
#     ["retention.files.never_delete"]="boolean|false|Never auto-delete archived files"
#
#     # Schedule settings
#     ["schedule.interval"]="integer|3600|Backup interval in seconds"
#     ["schedule.daemon_enabled"]="boolean|true|Enable daemon mode"
#     ["schedule.session_idle_threshold"]="integer|600|Session idle threshold in seconds"
#
#     # Drive verification
#     ["drive.verification_enabled"]="boolean|false|Enable drive verification"
#     ["drive.marker_file"]="path||Drive marker file path"
#
#     # Optional features
#     ["features.auto_commit"]="boolean|false|Auto-commit to git after backup"
#     ["features.git_commit_message"]="string|Auto-backup: \$(date '+%Y-%m-%d %H:%M')|Git commit message template"
#
#     # Critical files to backup
#     ["backup_targets.env_files"]="boolean|true|Backup .env files"
#     ["backup_targets.credentials"]="boolean|true|Backup credentials (*.pem, *.key, etc.)"
#     ["backup_targets.ide_settings"]="boolean|true|Backup IDE settings (.vscode/, .idea/)"
#     ["backup_targets.local_notes"]="boolean|true|Backup local notes (NOTES.md, *.private.md)"
#     ["backup_targets.local_databases"]="boolean|true|Backup local databases (*.db, *.sqlite)"
#
#     # Logging
#     ["logging.log_file"]="path|\${BACKUP_DIR}/backup.log|Main backup log file"
#     ["logging.fallback_log"]="path|\${HOME}/.claudecode-backups/logs/backup-fallback.log|Fallback log (if drive disconnected)"
#
#     # State files
#     ["state.state_dir"]="path|\${HOME}/.claudecode-backups/state|State directory"
#     ["state.backup_time_state"]="path|\${STATE_DIR}/.last-backup-time|Last backup timestamp file"
#     ["state.session_file"]="path|\${STATE_DIR}/.current-session-time|Current session tracking file"
#     ["state.db_state_file"]="path|\${BACKUP_DIR}/.backup-state|Database state tracking file"
# )

# Convert dot notation key to shell variable name
config_key_to_var() {
    local key="$1"
    case "$key" in
        "project.name") echo "PROJECT_NAME" ;;
        "project.dir") echo "PROJECT_DIR" ;;
        "locations.backup_dir") echo "BACKUP_DIR" ;;
        "locations.database_dir") echo "DATABASE_DIR" ;;
        "locations.files_dir") echo "FILES_DIR" ;;
        "locations.archived_dir") echo "ARCHIVED_DIR" ;;
        "database.path") echo "DB_PATH" ;;
        "database.type") echo "DB_TYPE" ;;
        "retention.database.time_based") echo "DB_RETENTION_DAYS" ;;
        "retention.database.never_delete") echo "DB_NEVER_DELETE" ;;
        "retention.files.time_based") echo "FILE_RETENTION_DAYS" ;;
        "retention.files.never_delete") echo "FILE_NEVER_DELETE" ;;
        "schedule.interval") echo "BACKUP_INTERVAL" ;;
        "schedule.cron") echo "BACKUP_SCHEDULE" ;;
        "schedule.daemon_enabled") echo "DAEMON_ENABLED" ;;
        "schedule.session_idle_threshold") echo "SESSION_IDLE_THRESHOLD" ;;
        "drive.verification_enabled") echo "DRIVE_VERIFICATION_ENABLED" ;;
        "drive.marker_file") echo "DRIVE_MARKER_FILE" ;;
        "features.auto_commit") echo "AUTO_COMMIT_ENABLED" ;;
        "features.git_commit_message") echo "GIT_COMMIT_MESSAGE" ;;
        "backup_targets.env_files") echo "BACKUP_ENV_FILES" ;;
        "backup_targets.credentials") echo "BACKUP_CREDENTIALS" ;;
        "backup_targets.ide_settings") echo "BACKUP_IDE_SETTINGS" ;;
        "backup_targets.local_notes") echo "BACKUP_LOCAL_NOTES" ;;
        "backup_targets.local_databases") echo "BACKUP_LOCAL_DATABASES" ;;
        "backup_targets.ai_artifacts") echo "BACKUP_AI_ARTIFACTS" ;;
        "storage.warning_percent") echo "STORAGE_WARNING_PERCENT" ;;
        "storage.critical_percent") echo "STORAGE_CRITICAL_PERCENT" ;;
        "storage.check_enabled") echo "STORAGE_CHECK_ENABLED" ;;
        "storage.cleanup_suggest") echo "STORAGE_CLEANUP_SUGGEST" ;;
        "encryption.enabled") echo "ENCRYPTION_ENABLED" ;;
        "encryption.key_path") echo "ENCRYPTION_KEY_PATH" ;;
        "logging.log_file") echo "LOG_FILE" ;;
        "logging.fallback_log") echo "FALLBACK_LOG" ;;
        "state.state_dir") echo "STATE_DIR" ;;
        "state.backup_time_state") echo "BACKUP_TIME_STATE" ;;
        "state.session_file") echo "SESSION_FILE" ;;
        "state.db_state_file") echo "DB_STATE_FILE" ;;
        *) echo "" ;;
    esac
}

# Convert shell variable name to dot notation key
config_var_to_key() {
    local var="$1"
    case "$var" in
        "PROJECT_NAME") echo "project.name" ;;
        "PROJECT_DIR") echo "project.dir" ;;
        "BACKUP_DIR") echo "locations.backup_dir" ;;
        "DATABASE_DIR") echo "locations.database_dir" ;;
        "FILES_DIR") echo "locations.files_dir" ;;
        "ARCHIVED_DIR") echo "locations.archived_dir" ;;
        "DB_PATH") echo "database.path" ;;
        "DB_TYPE") echo "database.type" ;;
        "DB_RETENTION_DAYS") echo "retention.database.time_based" ;;
        "DB_NEVER_DELETE") echo "retention.database.never_delete" ;;
        "FILE_RETENTION_DAYS") echo "retention.files.time_based" ;;
        "FILE_NEVER_DELETE") echo "retention.files.never_delete" ;;
        "BACKUP_INTERVAL") echo "schedule.interval" ;;
        "BACKUP_SCHEDULE") echo "schedule.cron" ;;
        "DAEMON_ENABLED") echo "schedule.daemon_enabled" ;;
        "SESSION_IDLE_THRESHOLD") echo "schedule.session_idle_threshold" ;;
        "DRIVE_VERIFICATION_ENABLED") echo "drive.verification_enabled" ;;
        "DRIVE_MARKER_FILE") echo "drive.marker_file" ;;
        "AUTO_COMMIT_ENABLED") echo "features.auto_commit" ;;
        "GIT_COMMIT_MESSAGE") echo "features.git_commit_message" ;;
        "BACKUP_ENV_FILES") echo "backup_targets.env_files" ;;
        "BACKUP_CREDENTIALS") echo "backup_targets.credentials" ;;
        "BACKUP_IDE_SETTINGS") echo "backup_targets.ide_settings" ;;
        "BACKUP_LOCAL_NOTES") echo "backup_targets.local_notes" ;;
        "BACKUP_LOCAL_DATABASES") echo "backup_targets.local_databases" ;;
        "BACKUP_AI_ARTIFACTS") echo "backup_targets.ai_artifacts" ;;
        "STORAGE_WARNING_PERCENT") echo "storage.warning_percent" ;;
        "STORAGE_CRITICAL_PERCENT") echo "storage.critical_percent" ;;
        "STORAGE_CHECK_ENABLED") echo "storage.check_enabled" ;;
        "STORAGE_CLEANUP_SUGGEST") echo "storage.cleanup_suggest" ;;
        "ENCRYPTION_ENABLED") echo "encryption.enabled" ;;
        "ENCRYPTION_KEY_PATH") echo "encryption.key_path" ;;
        "LOG_FILE") echo "logging.log_file" ;;
        "FALLBACK_LOG") echo "logging.fallback_log" ;;
        "STATE_DIR") echo "state.state_dir" ;;
        "BACKUP_TIME_STATE") echo "state.backup_time_state" ;;
        "SESSION_FILE") echo "state.session_file" ;;
        "DB_STATE_FILE") echo "state.db_state_file" ;;
        *) echo "" ;;
    esac
}

# Get schema details for a key
config_get_schema() {
    local key="$1"
    local field="${2:-all}"  # all, type, default, description

    local schema="${BACKUP_CONFIG_SCHEMA[$key]}"
    [[ -z "$schema" ]] && return 1

    local type="${schema%%|*}"
    local rest="${schema#*|}"
    local default="${rest%%|*}"
    local description="${rest#*|}"

    case "$field" in
        "type") echo "$type" ;;
        "default") echo "$default" ;;
        "description") echo "$description" ;;
        "all") echo "$type|$default|$description" ;;
        *) echo "$schema" ;;
    esac
}

# Validate a configuration value against schema
config_validate_value() {
    local key="$1"
    local value="$2"

    local type
    type="$(config_get_schema "$key" "type")"
    [[ -z "$type" ]] && color_red "Error: Unknown configuration key: $key" && return 1

    case "$type" in
        "string")
            [[ -z "$value" ]] && color_red "Error: Value cannot be empty for $key" && return 1
            ;;
        "integer")
            [[ ! "$value" =~ ^[0-9]+$ ]] && color_red "Error: Value must be a positive integer for $key (got: $value)" && return 1
            ;;
        "boolean")
            [[ "$value" != "true" && "$value" != "false" ]] && color_red "Error: Value must be 'true' or 'false' for $key (got: $value)" && return 1
            ;;
        "path")
            if [[ -n "$value" ]]; then
                [[ "$value" =~ ^[[:space:]] || "$value" =~ [[:space:]]$ ]] && color_red "Error: Path cannot have leading/trailing spaces for $key" && return 1
            fi
            ;;
        enum:*)
            local allowed="${type#enum:}"
            local valid=false
            IFS=',' read -ra ALLOWED <<< "$allowed"
            for item in "${ALLOWED[@]}"; do
                [[ "$value" == "$item" ]] && valid=true && break
            done
            [[ "$valid" != "true" ]] && color_red "Error: Value must be one of [$allowed] for $key (got: $value)" && return 1
            ;;
        *)
            color_red "Error: Unknown type '$type' in schema for $key"
            return 1
            ;;
    esac
    return 0
}

# Get configuration file path for current project
# Returns: Path to .backup-config.sh in project root
get_config_path() {
    local project_dir="${PROJECT_ROOT:-$PWD}"
    echo "$project_dir/.backup-config.sh"
}

# Get a configuration value by key
config_get_value() {
    local key="$1"
    local config_file="${2:-$(get_config_path)}"

    [[ ! -f "$config_file" ]] && color_red "Error: Config file not found: $config_file" && return 1

    local var_name
    var_name="$(config_key_to_var "$key")"
    [[ -z "$var_name" ]] && color_red "Error: Unknown configuration key: $key" && return 1

    (
        source "$config_file" 2>/dev/null
        echo "${!var_name}"
    )
}

# Get all configuration values
config_get_all_values() {
    local config_file="${1:-$(get_config_path)}"

    [[ ! -f "$config_file" ]] && color_red "Error: Config file not found: $config_file" && return 1

    (
        source "$config_file" 2>/dev/null
        for key in "${!BACKUP_CONFIG_SCHEMA[@]}"; do
            local var_name
            var_name="$(config_key_to_var "$key")"
            local value="${!var_name}"
            [[ -n "$value" ]] && echo "$key=$value"
        done
    ) | sort
}

# Set a configuration value
config_set_value() {
    local key="$1"
    local value="$2"
    local config_file="${3:-$(get_config_path)}"

    # Validate key exists
    # NOTE: -v operator requires bash 4.3+, commented out for macOS bash 3.2 compatibility
    # [[ ! -v BACKUP_CONFIG_SCHEMA["$key"] ]] && color_red "Error: Unknown configuration key: $key" && return 1

    # Validate value
    config_validate_value "$key" "$value" || return 1

    # Create config from template if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        local project_root
        project_root="$(dirname "$config_file")"
        config_create_from_template "$config_file" "standard"
    fi

    # Get variable name
    local var_name
    var_name="$(config_key_to_var "$key")"

    # Update value in config file using sed
    if grep -q "^${var_name}=" "$config_file"; then
        # Value needs quoting if it contains spaces or special chars
        if [[ "$value" =~ [[:space:]] ]] || [[ "$value" == *'$'* ]]; then
            sed -i.bak "s|^${var_name}=.*|${var_name}=\"${value}\"|" "$config_file"
        else
            sed -i.bak "s|^${var_name}=.*|${var_name}=${value}|" "$config_file"
        fi
        rm -f "${config_file}.bak"
    else
        echo "${var_name}=${value}" >> "$config_file"
    fi

    # Log change to audit
    config_audit_change "$key" "$value"
}

# Create config file from template
config_create_from_template() {
    local output_file="$1"
    local template="${2:-standard}"
    local project_root
    project_root="$(dirname "$output_file")"

    # Try to find package templates directory
    local templates_dir=""
    if [[ -d "$project_root/templates" ]]; then
        templates_dir="$project_root/templates"
    elif [[ -d "$(dirname "${BASH_SOURCE[0]}")/../templates" ]]; then
        templates_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)"
    else
        color_red "Error: Cannot find templates directory"
        return 1
    fi

    # Copy base template
    cp "$templates_dir/backup-config.sh" "$output_file"

    # Apply template modifications
    case "$template" in
        "minimal")
            sed -i.bak \
                -e 's/^DB_PATH=.*/DB_PATH=""/' \
                -e 's/^DB_TYPE=.*/DB_TYPE="none"/' \
                -e 's/^DB_RETENTION_DAYS=.*/DB_RETENTION_DAYS=7/' \
                -e 's/^FILE_RETENTION_DAYS=.*/FILE_RETENTION_DAYS=7/' \
                -e 's/^DRIVE_VERIFICATION_ENABLED=.*/DRIVE_VERIFICATION_ENABLED=false/' \
                "$output_file"
            ;;
        "paranoid")
            sed -i.bak \
                -e 's/^BACKUP_INTERVAL=.*/BACKUP_INTERVAL=1800/' \
                -e 's/^DB_RETENTION_DAYS=.*/DB_RETENTION_DAYS=180/' \
                -e 's/^FILE_RETENTION_DAYS=.*/FILE_RETENTION_DAYS=180/' \
                -e 's/^DRIVE_VERIFICATION_ENABLED=.*/DRIVE_VERIFICATION_ENABLED=true/' \
                -e 's/^AUTO_COMMIT_ENABLED=.*/AUTO_COMMIT_ENABLED=true/' \
                "$output_file"
            ;;
        "standard")
            # Already correct
            ;;
    esac

    rm -f "${output_file}.bak"
}

# Validate entire configuration file
config_validate_file() {
    local config_file="${1:-$(get_config_path)}"
    local strict="${2:-false}"

    [[ ! -f "$config_file" ]] && color_red "Error: Config file not found: $config_file" && return 1

    local errors=0

    (
        source "$config_file" 2>/dev/null

        for key in "${!BACKUP_CONFIG_SCHEMA[@]}"; do
            local var_name
            var_name="$(config_key_to_var "$key")"
            local value="${!var_name}"

            # Strict mode requires all values
            if [[ "$strict" == "true" && -z "$value" ]]; then
                color_red "Error: Required key '$key' is not set"
                ((errors++))
                continue
            fi

            # Validate non-empty values
            if [[ -n "$value" ]]; then
                if ! config_validate_value "$key" "$value" 2>/dev/null; then
                    ((errors++))
                fi
            fi
        done

        exit "$errors"
    )

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        color_green "✅ Configuration is valid"
        return 0
    else
        color_red "❌ Configuration has $exit_code errors"
        return 1
    fi
}

# Profile management - save current config as profile
config_profile_save() {
    local profile_name="$1"
    local config_file="${2:-$(get_config_path)}"

    [[ ! -f "$config_file" ]] && color_red "Error: Config file not found: $config_file" && return 1

    local profiles_dir="$HOME/.claudecode-backups/profiles"
    mkdir -p "$profiles_dir"

    local profile_file="$profiles_dir/${profile_name}.sh"
    cp "$config_file" "$profile_file"
    color_green "✅ Profile '$profile_name' saved to $profile_file"
}

# Profile management - load profile
config_profile_load() {
    local profile_name="$1"
    local config_file="${2:-$(get_config_path)}"

    local profiles_dir="$HOME/.claudecode-backups/profiles"
    local profile_file="$profiles_dir/${profile_name}.sh"

    [[ ! -f "$profile_file" ]] && color_red "Error: Profile '$profile_name' not found" && config_profile_list && return 1

    cp "$profile_file" "$config_file"
    color_green "✅ Profile '$profile_name' loaded"
}

# Profile management - list profiles
config_profile_list() {
    local profiles_dir="$HOME/.claudecode-backups/profiles"

    [[ ! -d "$profiles_dir" ]] && echo "No profiles found" && return 0

    local count=0
    for profile in "$profiles_dir"/*.sh; do
        if [[ -f "$profile" ]]; then
            local name
            name="$(basename "$profile" .sh)"
            echo "  - $name"
            ((count++))
        fi
    done

    [[ $count -eq 0 ]] && echo "No profiles found"
}

# Audit log for configuration changes
config_audit_change() {
    local key="$1"
    local value="$2"

    local audit_dir="$HOME/.claudecode-backups/audit"
    mkdir -p "$audit_dir"

    local audit_file="$audit_dir/config-changes.log"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[$timestamp] $key = $value" >> "$audit_file"
}
