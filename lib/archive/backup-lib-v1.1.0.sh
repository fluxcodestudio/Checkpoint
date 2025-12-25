#!/usr/bin/env bash
# ==============================================================================
# ClaudeCode Project Backups - Core Library v1.1.0
# ==============================================================================
# Complete reference implementation with YAML support
#
# This is the production-ready version. To use:
#   1. Backup current lib/backup-lib.sh
#   2. Copy this file to lib/backup-lib.sh
#   3. Test with: ./lib/test-library.sh
#   4. Verify with: source lib/backup-lib.sh && backup_lib_selftest
#
# ==============================================================================

set -euo pipefail

readonly BACKUP_LIB_VERSION="1.1.0"
readonly BACKUP_LIB_COMPAT="1.0.0"

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================

declare -A CONFIG_VALUES
declare -A CONFIG_DEFAULTS
declare -A CONFIG_METADATA

BACKUP_CONFIG_YAML=""
BACKUP_CONFIG_BASH=""
BACKUP_CONFIG_LOADED=false
BACKUP_PROJECT_ROOT=""

BACKUP_LOG_LEVEL="${BACKUP_LOG_LEVEL:-INFO}"
BACKUP_LOG_COLORS="${BACKUP_LOG_COLORS:-true}"

readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_GRAY='\033[0;90m'

# ==============================================================================
# LOGGING
# ==============================================================================

log_level_value() {
    case "$1" in
        DEBUG) echo 0 ;; INFO) echo 1 ;; WARN) echo 2 ;; ERROR) echo 3 ;; *) echo 1 ;;
    esac
}

log() {
    local level="$1"; shift
    local message="$*"
    local current_level=$(log_level_value "$BACKUP_LOG_LEVEL")
    local msg_level=$(log_level_value "$level")
    [ "$msg_level" -lt "$current_level" ] && return 0

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color="" prefix=""

    case "$level" in
        DEBUG) color="$COLOR_GRAY"; prefix="[DEBUG]" ;;
        INFO) color="$COLOR_BLUE"; prefix="[INFO] " ;;
        WARN) color="$COLOR_YELLOW"; prefix="[WARN] " ;;
        ERROR) color="$COLOR_RED"; prefix="[ERROR]" ;;
    esac

    if [ "$BACKUP_LOG_COLORS" = "true" ]; then
        echo -e "${color}${timestamp} ${prefix} ${message}${COLOR_RESET}" >&2
    else
        echo "${timestamp} ${prefix} ${message}" >&2
    fi
}

log_debug() { log DEBUG "$@"; }
log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_success() {
    [ "$BACKUP_LOG_COLORS" = "true" ] && echo -e "${COLOR_GREEN}✓ $*${COLOR_RESET}" >&2 || echo "✓ $*" >&2
}
log_fatal() { log_error "$@"; exit 1; }

# ==============================================================================
# CONFIGURATION SCHEMA
# ==============================================================================

init_config_schema() {
    # locations.*
    CONFIG_DEFAULTS["locations.backup_dir"]="backups/"
    CONFIG_DEFAULTS["locations.database_dir"]="backups/databases"
    CONFIG_DEFAULTS["locations.files_dir"]="backups/files"
    CONFIG_DEFAULTS["locations.archived_dir"]="backups/archived"
    CONFIG_DEFAULTS["locations.drive_marker"]=""
    CONFIG_METADATA["locations.backup_dir"]="path:Main backup directory"
    CONFIG_METADATA["locations.database_dir"]="path:Database backups subdirectory"
    CONFIG_METADATA["locations.files_dir"]="path:File backups subdirectory"
    CONFIG_METADATA["locations.archived_dir"]="path:Archived files subdirectory"
    CONFIG_METADATA["locations.drive_marker"]="path:Drive verification marker file"

    # schedule.*
    CONFIG_DEFAULTS["schedule.interval"]=3600
    CONFIG_DEFAULTS["schedule.daemon_enabled"]=true
    CONFIG_DEFAULTS["schedule.hooks_enabled"]=true
    CONFIG_DEFAULTS["schedule.session_idle_threshold"]=600
    CONFIG_METADATA["schedule.interval"]="number:Backup interval in seconds"
    CONFIG_METADATA["schedule.daemon_enabled"]="boolean:Enable daemon backups"
    CONFIG_METADATA["schedule.hooks_enabled"]="boolean:Enable Claude Code hooks"
    CONFIG_METADATA["schedule.session_idle_threshold"]="number:Session idle time in seconds"

    # retention.database.*
    CONFIG_DEFAULTS["retention.database.time_based"]=30
    CONFIG_DEFAULTS["retention.database.count_based"]=""
    CONFIG_DEFAULTS["retention.database.size_based"]=""
    CONFIG_DEFAULTS["retention.database.never_delete"]=false
    CONFIG_METADATA["retention.database.time_based"]="number:Delete database backups older than N days"
    CONFIG_METADATA["retention.database.count_based"]="number:Keep only N most recent database backups"
    CONFIG_METADATA["retention.database.size_based"]="number:Delete when total size exceeds N MB"
    CONFIG_METADATA["retention.database.never_delete"]="boolean:Never delete database backups"

    # retention.files.*
    CONFIG_DEFAULTS["retention.files.time_based"]=60
    CONFIG_DEFAULTS["retention.files.count_based"]=""
    CONFIG_DEFAULTS["retention.files.size_based"]=""
    CONFIG_DEFAULTS["retention.files.never_delete"]=false
    CONFIG_METADATA["retention.files.time_based"]="number:Delete archived files older than N days"
    CONFIG_METADATA["retention.files.count_based"]="number:Keep only N most recent file versions"
    CONFIG_METADATA["retention.files.size_based"]="number:Delete when total size exceeds N MB"
    CONFIG_METADATA["retention.files.never_delete"]="boolean:Never delete archived files"

    # database.*
    CONFIG_DEFAULTS["database.path"]=""
    CONFIG_DEFAULTS["database.type"]="none"
    CONFIG_METADATA["database.path"]="path:Path to database file"
    CONFIG_METADATA["database.type"]="enum(none,sqlite):Database type"

    # patterns.include.*
    CONFIG_DEFAULTS["patterns.include.env_files"]=true
    CONFIG_DEFAULTS["patterns.include.credentials"]=true
    CONFIG_DEFAULTS["patterns.include.ide_settings"]=true
    CONFIG_DEFAULTS["patterns.include.local_notes"]=true
    CONFIG_DEFAULTS["patterns.include.local_databases"]=true
    CONFIG_METADATA["patterns.include.env_files"]="boolean:Backup .env files"
    CONFIG_METADATA["patterns.include.credentials"]="boolean:Backup credentials"
    CONFIG_METADATA["patterns.include.ide_settings"]="boolean:Backup IDE settings"
    CONFIG_METADATA["patterns.include.local_notes"]="boolean:Backup local notes"
    CONFIG_METADATA["patterns.include.local_databases"]="boolean:Backup local databases"

    # patterns.exclude
    CONFIG_DEFAULTS["patterns.exclude"]=""
    CONFIG_METADATA["patterns.exclude"]="array:Exclude patterns"

    # git.*
    CONFIG_DEFAULTS["git.auto_commit"]=false
    CONFIG_DEFAULTS["git.commit_message"]='Auto-backup: $(date "+%Y-%m-%d %H:%M")'
    CONFIG_METADATA["git.auto_commit"]="boolean:Auto-commit after backup"
    CONFIG_METADATA["git.commit_message"]="string:Git commit message template"

    # advanced.*
    CONFIG_DEFAULTS["advanced.parallel_compression"]=true
    CONFIG_DEFAULTS["advanced.compression_level"]=6
    CONFIG_DEFAULTS["advanced.symlink_handling"]="follow"
    CONFIG_DEFAULTS["advanced.permissions_preserve"]=true
    CONFIG_METADATA["advanced.parallel_compression"]="boolean:Use parallel compression"
    CONFIG_METADATA["advanced.compression_level"]="number:Compression level (1-9)"
    CONFIG_METADATA["advanced.symlink_handling"]="enum(follow,preserve,skip):How to handle symlinks"
    CONFIG_METADATA["advanced.permissions_preserve"]="boolean:Preserve file permissions"
}

# ==============================================================================
# YAML PARSER
# ==============================================================================

parse_yaml() {
    local yaml_file="$1" prefix="${2:-}"
    [ ! -f "$yaml_file" ] && log_error "YAML file not found: $yaml_file" && return 1

    local indent_stack=() key_stack=() in_array=false array_key="" array_values=()

    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        local leading_spaces="${line%%[! ]*}"
        local indent=${#leading_spaces}
        local content="${line#"$leading_spaces"}"

        if [[ "$content" =~ ^-[[:space:]]+ ]]; then
            local value="${content#- }"; value="${value#\"}"; value="${value%\"}"
            case "$value" in
                true|yes|on) value="true" ;; false|no|off) value="false" ;; null|~) value="" ;;
            esac
            [ -n "$array_key" ] && array_values+=("$value")
            continue
        fi

        if [[ "$content" =~ ^([a-zA-Z0-9_-]+):[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"

            if [ "$in_array" = true ] && [ -n "$array_key" ]; then
                local joined=$(IFS=:; echo "${array_values[*]}")
                CONFIG_VALUES["$array_key"]="$joined"
                array_values=(); in_array=false
            fi

            while [ "${#indent_stack[@]}" -gt 0 ] && [ "$indent" -le "${indent_stack[-1]}" ]; do
                unset 'indent_stack[-1]' 'key_stack[-1]'
            done

            local full_key="$prefix"
            [ "${#key_stack[@]}" -gt 0 ] && full_key="${full_key}$(IFS=.; echo "${key_stack[*]}")."
            full_key="${full_key}${key}"

            value="${value#\"}"; value="${value%\"}"

            if [ -z "$value" ]; then
                indent_stack+=("$indent"); key_stack+=("$key")
            else
                case "$value" in
                    true|yes|on) value="true" ;; false|no|off) value="false" ;; null|~) value="" ;;
                esac
                CONFIG_VALUES["$full_key"]="$value"
                log_debug "Parsed: $full_key = $value"
            fi
        elif [[ "$content" =~ ^([a-zA-Z0-9_-]+):$ ]]; then
            local key="${BASH_REMATCH[1]}"
            in_array=false; array_key=""

            while [ "${#indent_stack[@]}" -gt 0 ] && [ "$indent" -le "${indent_stack[-1]}" ]; do
                unset 'indent_stack[-1]' 'key_stack[-1]'
            done

            indent_stack+=("$indent"); key_stack+=("$key")

            local full_key="$prefix"
            [ "${#key_stack[@]}" -gt 0 ] && full_key="${full_key}$(IFS=.; echo "${key_stack[*]}")"
            array_key="$full_key"; in_array=true
        fi
    done < "$yaml_file"

    if [ "$in_array" = true ] && [ -n "$array_key" ] && [ "${#array_values[@]}" -gt 0 ]; then
        local joined=$(IFS=:; echo "${array_values[*]}")
        CONFIG_VALUES["$array_key"]="$joined"
    fi
    return 0
}

# ==============================================================================
# CONFIGURATION LOADER
# ==============================================================================

config_find_files() {
    local search_dir="${1:-$PWD}"
    BACKUP_PROJECT_ROOT="$search_dir"

    [ -f "$search_dir/.backup-config.yaml" ] && BACKUP_CONFIG_YAML="$search_dir/.backup-config.yaml" && log_debug "Found YAML config: $BACKUP_CONFIG_YAML"
    [ -f "$search_dir/.backup-config.sh" ] && BACKUP_CONFIG_BASH="$search_dir/.backup-config.sh" && log_debug "Found bash config: $BACKUP_CONFIG_BASH"

    if [ -z "$BACKUP_CONFIG_YAML" ] && [ -z "$BACKUP_CONFIG_BASH" ]; then
        log_error "No configuration file found in $search_dir"
        log_error "Expected: .backup-config.yaml or .backup-config.sh"
        return 1
    fi
    return 0
}

config_load() {
    local search_dir="${1:-$PWD}"
    [ "$BACKUP_CONFIG_LOADED" = true ] && log_debug "Configuration already loaded" && return 0

    log_info "Loading configuration..."
    init_config_schema
    config_find_files "$search_dir" || return 1

    if [ -n "$BACKUP_CONFIG_YAML" ]; then
        log_info "Loading YAML config: $BACKUP_CONFIG_YAML"
        parse_yaml "$BACKUP_CONFIG_YAML" && BACKUP_CONFIG_LOADED=true && log_success "YAML configuration loaded" || { log_error "Failed to parse YAML configuration"; return 1; }
    elif [ -n "$BACKUP_CONFIG_BASH" ]; then
        log_info "Loading legacy bash config: $BACKUP_CONFIG_BASH"
        config_load_bash "$BACKUP_CONFIG_BASH" && BACKUP_CONFIG_LOADED=true && log_success "Legacy configuration loaded" && log_warn "Consider migrating to YAML format" || { log_error "Failed to load bash configuration"; return 1; }
    fi

    config_validate || { log_error "Configuration validation failed"; return 1; }
    return 0
}

config_load_bash() {
    local bash_file="$1"
    [ ! -f "$bash_file" ] && log_error "Bash config not found: $bash_file" && return 1

    local vars=$(bash -c "source '$bash_file' && set" | grep -E '^(PROJECT_|BACKUP_|DB_|FILE_|SESSION_|DRIVE_|AUTO_|GIT_)')

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local var_name="${line%%=*}" var_value="${line#*=}"
        var_value="${var_value#\'}"; var_value="${var_value%\'}"; var_value="${var_value#\"}"; var_value="${var_value%\"}"

        case "$var_name" in
            PROJECT_DIR) BACKUP_PROJECT_ROOT="$var_value" ;;
            PROJECT_NAME) CONFIG_VALUES["project.name"]="$var_value" ;;
            BACKUP_DIR) CONFIG_VALUES["locations.backup_dir"]="$var_value" ;;
            DATABASE_DIR) CONFIG_VALUES["locations.database_dir"]="$var_value" ;;
            FILES_DIR) CONFIG_VALUES["locations.files_dir"]="$var_value" ;;
            ARCHIVED_DIR) CONFIG_VALUES["locations.archived_dir"]="$var_value" ;;
            DRIVE_MARKER_FILE) CONFIG_VALUES["locations.drive_marker"]="$var_value" ;;
            DB_PATH) CONFIG_VALUES["database.path"]="$var_value" ;;
            DB_TYPE) CONFIG_VALUES["database.type"]="$var_value" ;;
            DB_RETENTION_DAYS) CONFIG_VALUES["retention.database.time_based"]="$var_value" ;;
            FILE_RETENTION_DAYS) CONFIG_VALUES["retention.files.time_based"]="$var_value" ;;
            BACKUP_INTERVAL) CONFIG_VALUES["schedule.interval"]="$var_value" ;;
            SESSION_IDLE_THRESHOLD) CONFIG_VALUES["schedule.session_idle_threshold"]="$var_value" ;;
            AUTO_COMMIT_ENABLED) CONFIG_VALUES["git.auto_commit"]="$var_value" ;;
            GIT_COMMIT_MESSAGE) CONFIG_VALUES["git.commit_message"]="$var_value" ;;
            BACKUP_ENV_FILES) CONFIG_VALUES["patterns.include.env_files"]="$var_value" ;;
            BACKUP_CREDENTIALS) CONFIG_VALUES["patterns.include.credentials"]="$var_value" ;;
            BACKUP_IDE_SETTINGS) CONFIG_VALUES["patterns.include.ide_settings"]="$var_value" ;;
            BACKUP_LOCAL_NOTES) CONFIG_VALUES["patterns.include.local_notes"]="$var_value" ;;
            BACKUP_LOCAL_DATABASES) CONFIG_VALUES["patterns.include.local_databases"]="$var_value" ;;
        esac
    done <<< "$vars"

    log_debug "Mapped ${#CONFIG_VALUES[@]} config values from bash"
    return 0
}

# ==============================================================================
# GETTERS/SETTERS
# ==============================================================================

config_get() {
    local key="$1" default="${2:-}"
    [ "$BACKUP_CONFIG_LOADED" != true ] && log_error "Configuration not loaded. Call config_load first." && return 1

    [ -n "${CONFIG_VALUES[$key]+x}" ] && echo "${CONFIG_VALUES[$key]}" && return 0
    [ -n "$default" ] && echo "$default" && return 0
    [ -n "${CONFIG_DEFAULTS[$key]+x}" ] && echo "${CONFIG_DEFAULTS[$key]}" && return 0
    log_debug "Config key not found: $key" && return 1
}

config_set() {
    local key="$1" value="$2"
    [ "$BACKUP_CONFIG_LOADED" != true ] && log_error "Configuration not loaded. Call config_load first." && return 1

    if [ -n "${CONFIG_VALIDATORS[$key]+x}" ]; then
        ${CONFIG_VALIDATORS[$key]} "$value" || { log_error "Validation failed for $key: $value"; return 1; }
    fi

    CONFIG_VALUES["$key"]="$value"
    log_debug "Set config: $key = $value"
    return 0
}

config_has() { [ -n "${CONFIG_VALUES[$1]+x}" ]; }

config_list_keys() {
    local prefix="${1:-}"
    [ -z "$prefix" ] && echo "${!CONFIG_VALUES[@]}" | tr ' ' '\n' | sort || echo "${!CONFIG_VALUES[@]}" | tr ' ' '\n' | grep "^${prefix}" | sort
}

# ==============================================================================
# VALIDATION
# ==============================================================================

validate_path() {
    local path="$1" must_exist="${2:-false}"
    [ -z "$path" ] && return 0
    [[ "$path" =~ [^a-zA-Z0-9/_.\-\$\{\}\ ] ]] && log_error "Invalid characters in path: $path" && return 1
    if [ "$must_exist" = true ]; then
        local expanded_path=$(eval echo "$path")
        [ ! -e "$expanded_path" ] && log_error "Path does not exist: $path" && return 1
    fi
    return 0
}

validate_number() {
    local value="$1" min="${2:-}" max="${3:-}"
    [ -z "$value" ] && return 0
    ! [[ "$value" =~ ^[0-9]+$ ]] && log_error "Not a valid number: $value" && return 1
    [ -n "$min" ] && [ "$value" -lt "$min" ] && log_error "Value $value is less than minimum $min" && return 1
    [ -n "$max" ] && [ "$value" -gt "$max" ] && log_error "Value $value is greater than maximum $max" && return 1
    return 0
}

validate_boolean() {
    local value="$1"
    [ -z "$value" ] && return 0
    case "$value" in
        true|false|yes|no|on|off|1|0) return 0 ;;
        *) log_error "Not a valid boolean: $value"; return 1 ;;
    esac
}

validate_enum() {
    local value="$1"; shift; local valid_values=("$@")
    [ -z "$value" ] && return 0
    for valid in "${valid_values[@]}"; do
        [ "$value" = "$valid" ] && return 0
    done
    log_error "Invalid value '$value'. Must be one of: ${valid_values[*]}"
    return 1
}

validate_config_value() {
    local key="$1" value="$2"
    [ -z "${CONFIG_METADATA[$key]+x}" ] && log_warn "Unknown config key: $key" && return 0

    local metadata="${CONFIG_METADATA[$key]}" type="${metadata%%:*}"

    case "$type" in
        path) validate_path "$value" false ;;
        number) validate_number "$value" ;;
        boolean) validate_boolean "$value" ;;
        enum*)
            local options="${type#enum(}"; options="${options%)}"
            IFS=',' read -ra valid_values <<< "$options"
            validate_enum "$value" "${valid_values[@]}"
            ;;
        string|array) return 0 ;;
        *) log_warn "Unknown validation type: $type"; return 0 ;;
    esac
}

config_validate() {
    log_info "Validating configuration..."
    local errors=0

    for key in "${!CONFIG_VALUES[@]}"; do
        validate_config_value "$key" "${CONFIG_VALUES[$key]}" || ((errors++))
    done

    local comp_level=$(config_get "advanced.compression_level" 6)
    validate_number "$comp_level" 1 9 || { log_error "Compression level must be 1-9, got: $comp_level"; ((errors++)); }

    local db_path=$(config_get "database.path" "") db_type=$(config_get "database.type" "none")
    [ -n "$db_path" ] && [ "$db_type" = "none" ] && log_warn "Database path set but type is 'none'"
    [ -z "$db_path" ] && [ "$db_type" != "none" ] && log_warn "Database type '$db_type' set but no path configured"

    local db_never=$(config_get "retention.database.never_delete" false)
    local files_never=$(config_get "retention.files.never_delete" false)
    [ "$db_never" = "true" ] && log_info "Database retention: Never delete (keep all backups)"
    [ "$files_never" = "true" ] && log_info "File retention: Never delete (keep all versions)"

    [ "$errors" -gt 0 ] && log_error "Configuration validation failed with $errors errors" && return 1
    log_success "Configuration validated successfully"
    return 0
}

# ==============================================================================
# SAFE FILE OPERATIONS
# ==============================================================================

atomic_write() {
    local target_file="$1" content="$2"
    local temp_file="${target_file}.tmp.$$" backup_file="${target_file}.backup"

    echo -e "$content" > "$temp_file" || { log_error "Failed to write temp file: $temp_file"; rm -f "$temp_file"; return 1; }

    if [ -f "$target_file" ]; then
        cp "$target_file" "$backup_file" || { log_error "Failed to create backup: $backup_file"; rm -f "$temp_file"; return 1; }
        log_debug "Created backup: $backup_file"
    fi

    mv "$temp_file" "$target_file" || {
        log_error "Failed to move temp file to target"
        [ -f "$backup_file" ] && cp "$backup_file" "$target_file" && log_info "Restored from backup"
        rm -f "$temp_file"; return 1
    }

    log_debug "Atomic write successful: $target_file"
    return 0
}

# ==============================================================================
# UTILITIES
# ==============================================================================

is_macos() { [[ "$OSTYPE" == "darwin"* ]]; }
is_linux() { [[ "$OSTYPE" == "linux-gnu"* ]]; }

format_bytes() {
    local bytes="$1"
    [ "$bytes" -lt 1024 ] && echo "${bytes}B" && return
    [ "$bytes" -lt 1048576 ] && echo "$((bytes / 1024))KB" && return
    [ "$bytes" -lt 1073741824 ] && echo "$((bytes / 1048576))MB" && return
    echo "$((bytes / 1073741824))GB"
}

expand_path() {
    local path="$1"
    path=$(eval echo "$path"); path="${path/#\~/$HOME}"
    [[ "$path" != /* ]] && path="$BACKUP_PROJECT_ROOT/$path"
    echo "$path"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

check_dependencies() {
    local missing=() required_commands=("git" "sqlite3" "gzip")
    for cmd in "${required_commands[@]}"; do
        command_exists "$cmd" || missing+=("$cmd")
    done
    [ "${#missing[@]}" -gt 0 ] && log_error "Missing required commands: ${missing[*]}" && return 1
    return 0
}

find_project_root() {
    local dir="${1:-$PWD}"
    while [ "$dir" != "/" ]; do
        [ -f "$dir/.backup-config.yaml" ] || [ -f "$dir/.backup-config.sh" ] || [ -d "$dir/.git" ] && echo "$dir" && return 0
        dir=$(dirname "$dir")
    done
    echo "$PWD"; return 1
}

# ==============================================================================
# SELF-TEST
# ==============================================================================

backup_lib_selftest() {
    echo "=== Backup Library Self-Test ==="
    echo "Version: $BACKUP_LIB_VERSION"
    echo ""

    local tests_passed=0 tests_failed=0

    echo -n "Test 1: Schema initialization... "
    init_config_schema
    [ "${#CONFIG_DEFAULTS[@]}" -gt 0 ] && echo "PASS (${#CONFIG_DEFAULTS[@]} defaults loaded)" && ((tests_passed++)) || { echo "FAIL"; ((tests_failed++)); }

    echo -n "Test 2: Validation functions... "
    validate_number "42" && validate_boolean "true" && validate_enum "sqlite" "none" "sqlite" "postgres" && echo "PASS" && ((tests_passed++)) || { echo "FAIL"; ((tests_failed++)); }

    echo -n "Test 3: Path expansion... "
    local expanded=$(expand_path "~/test")
    [[ "$expanded" == "$HOME/test" ]] && echo "PASS" && ((tests_passed++)) || { echo "FAIL (got: $expanded)"; ((tests_failed++)); }

    echo -n "Test 4: File size formatting... "
    local size=$(format_bytes 1536)
    [[ "$size" == "1KB" ]] && echo "PASS" && ((tests_passed++)) || { echo "FAIL (got: $size)"; ((tests_failed++)); }

    echo -n "Test 5: Platform detection... "
    is_macos || is_linux && echo "PASS ($(uname))" && ((tests_passed++)) || { echo "FAIL"; ((tests_failed++)); }

    echo ""
    echo "Results: $tests_passed passed, $tests_failed failed"

    [ "$tests_failed" -eq 0 ] && echo "All tests passed!" && return 0 || { echo "Some tests failed!"; return 1; }
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================

[ "${BACKUP_LIB_NO_AUTO_INIT:-0}" != "1" ] && log_debug "Backup library v$BACKUP_LIB_VERSION loaded"

# Export public functions
export -f config_load config_get config_set config_validate
export -f log_debug log_info log_warn log_error log_success log_fatal
export -f atomic_write expand_path format_bytes check_dependencies find_project_root
