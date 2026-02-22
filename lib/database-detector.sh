#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Universal Database Detector
# ==============================================================================
# Version: 2.3.0
# Description: Auto-detect databases (local and remote) across all types
#              - SQLite, PostgreSQL, MySQL, MongoDB
#              - Detects from files, environment variables, running processes
#              - Distinguishes local vs remote databases
#
# Usage:
#   source lib/database-detector.sh
#   detect_databases
#   backup_detected_databases
# ==============================================================================

# Set logging context for this module
log_set_context "db-detect"

# ==============================================================================
# ENV FILE DISCOVERY
# ==============================================================================

# Find all .env files in a project directory (recursive, up to 3 levels deep).
# Searches project root and common framework subdirectory patterns.
# $1 = project directory
# Output: newline-separated list of .env file paths
_discover_env_files() {
    local project_dir="${1:-.}"
    local found_files=()

    # Explicit root-level env files (highest priority)
    local root_names=(".env" ".env.local" ".env.development" ".env.production" ".env.staging")
    for name in "${root_names[@]}"; do
        [[ -f "$project_dir/$name" ]] && found_files+=("$project_dir/$name")
    done

    # Recursive search for .env files up to 3 levels deep
    # Excludes node_modules, .git, vendor/*, backups, dist, build
    while IFS= read -r -d '' env_file; do
        # Skip if already in root list
        local already_found=false
        for f in "${found_files[@]}"; do
            [[ "$f" == "$env_file" ]] && { already_found=true; break; }
        done
        $already_found && continue
        found_files+=("$env_file")
    done < <(find "$project_dir" -maxdepth 3 -type f \( -name ".env" -o -name ".env.local" -o -name ".env.development" -o -name ".env.production" -o -name ".env.staging" \) \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -not -path "*/vendor/*" \
        -not -path "*/backups/*" \
        -not -path "*/dist/*" \
        -not -path "*/build/*" \
        -print0 2>/dev/null)

    # Also check common framework config files (non-.env)
    # WordPress: wp-config.php
    while IFS= read -r -d '' wp_config; do
        found_files+=("$wp_config")
    done < <(find "$project_dir" -maxdepth 2 -type f -name "wp-config.php" \
        -not -path "*/node_modules/*" -not -path "*/.git/*" -print0 2>/dev/null)

    # Rails: config/database.yml
    while IFS= read -r -d '' rails_config; do
        found_files+=("$rails_config")
    done < <(find "$project_dir" -maxdepth 3 -type f -path "*/config/database.yml" \
        -not -path "*/node_modules/*" -not -path "*/.git/*" -print0 2>/dev/null)

    # Spring Boot: application.properties / application.yml
    while IFS= read -r -d '' spring_config; do
        found_files+=("$spring_config")
    done < <(find "$project_dir" -maxdepth 4 -type f \( -name "application.properties" -o -name "application.yml" \) \
        -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/build/*" -print0 2>/dev/null)

    printf '%s\n' "${found_files[@]}"
}

# Parse a generic config file for a key=value pattern.
# Handles shell-style (KEY=value), PHP define('KEY','value'), YAML (key: value).
# $1 = file path, $2 = key name (regex-safe)
# Output: value (stripped of quotes) or empty
_extract_config_value() {
    local file="$1" key="$2"
    local value=""

    if [[ "$file" == *.php ]]; then
        # PHP: define('KEY', 'value') or define("KEY", "value")
        value=$(grep -E "define\s*\(\s*['\"]${key}['\"]" "$file" 2>/dev/null | head -1 | sed -E "s/.*define\s*\(\s*['\"]${key}['\"]\s*,\s*['\"]([^'\"]*)['\"].*/\1/")
    elif [[ "$file" == *.yml || "$file" == *.yaml ]]; then
        # YAML: key: value
        value=$(grep -E "^\s*${key}\s*:" "$file" 2>/dev/null | head -1 | sed -E "s/.*:\s*['\"]?([^'\"#]*)['\"]?.*/\1/" | xargs)
    elif [[ "$file" == *.properties ]]; then
        # Java properties: key=value
        value=$(grep -E "^${key}\s*=" "$file" 2>/dev/null | head -1 | sed -E "s/^${key}\s*=\s*//" | xargs)
    else
        # Shell-style: KEY=value or KEY="value"
        value=$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | sed -E "s/^${key}=//" | sed "s/^['\"]//;s/['\"]$//")
    fi

    echo "$value"
}

# ==============================================================================
# VALUE SANITIZATION
# ==============================================================================

# Strip inline comments and quotes from .env values.
# "mysql # comment" → "mysql", "'value'" → "value"
_sanitize_env_value() {
    local val="$1"
    # Remove surrounding quotes first
    val="${val//\"/}"; val="${val//\'/}"
    # Strip inline comments (space + #)
    val="${val%% \#*}"
    # Trim trailing whitespace
    val="${val%"${val##*[![:space:]]}"}"
    echo "$val"
}

# Check if a value looks like an unresolved variable interpolation.
# Returns 0 if it contains ${...} or $VAR patterns, 1 if clean.
_has_interpolation() {
    [[ "$1" == *'${'* ]] || [[ "$1" =~ \$[A-Z_] ]]
}

# Check if a database name is a placeholder/null value.
# Returns 0 if it's a placeholder, 1 if it's a real name.
_is_placeholder_db() {
    local name="$1"
    [[ -z "$name" ]] || [[ "$name" == "null" ]] || [[ "$name" == "NULL" ]] || \
    [[ "$name" == "none" ]] || [[ "$name" == "undefined" ]] || [[ "$name" == "false" ]]
}

# Normalize host to canonical form for deduplication.
# Maps localhost variants to "localhost".
_normalize_host() {
    local host="$1"
    case "$host" in
        localhost|127.0.0.1|::1|0.0.0.0) echo "localhost" ;;
        *) echo "$host" ;;
    esac
}

# Deduplicate database entries by type+host+port+database (normalized).
# Input: newline-separated database info strings on stdin
# Output: deduplicated entries
_dedup_databases() {
    local -A seen=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        IFS='|' read -r type host port database rest <<< "$line"
        local norm_host
        norm_host=$(_normalize_host "$host")
        local key="${type}|${norm_host}|${port}|${database}"
        if [[ -z "${seen[$key]:-}" ]]; then
            seen[$key]=1
            echo "$line"
        fi
    done
}

# ==============================================================================
# CREDENTIAL STORE INTEGRATION (opt-in)
# ==============================================================================

# Look up a database credential from the credential store.
# Only active when CHECKPOINT_USE_CREDENTIAL_STORE="true" in config.
# Args: $1=db_type (postgres/mysql/mongodb), $2=database_name
# Output: password to stdout (empty if not found or not enabled)
# Returns: 0 if found, 1 if not found or not enabled
_get_db_credential() {
    local db_type="$1"
    local database_name="$2"

    # Only check credential store if explicitly enabled
    if [[ "${CHECKPOINT_USE_CREDENTIAL_STORE:-false}" != "true" ]]; then
        return 1
    fi

    # Source credential provider if not already loaded
    if [[ -z "${_CHECKPOINT_CREDENTIAL_PROVIDER:-}" ]]; then
        local cred_provider="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/security/credential-provider.sh"
        if [[ -f "$cred_provider" ]]; then
            source "$cred_provider"
        else
            return 1
        fi
    fi

    # Try to get credential from store
    local stored_password
    stored_password="$(credential_get "checkpoint-db" "${db_type}-${database_name}" 2>/dev/null)" || true

    if [[ -n "$stored_password" ]]; then
        echo "$stored_password"
        return 0
    fi

    return 1
}

# ==============================================================================
# DETECTION: SQLITE
# ==============================================================================

# Find all SQLite database files in project
# Returns: Array of absolute paths to .db, .sqlite, .sqlite3 files
detect_sqlite() {
    local project_dir="${1:-.}"
    local databases=()

    # Find common SQLite file extensions
    while IFS= read -r -d '' db_file; do
        # Verify it's actually a SQLite file (check header)
        if file "$db_file" 2>/dev/null | grep -qi "sqlite"; then
            databases+=("$db_file")
        fi
    done < <(find "$project_dir" -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/backups/*" -print0 2>/dev/null)

    # Output results (one per line)
    printf '%s\n' "${databases[@]}"
}

# ==============================================================================
# DETECTION: POSTGRESQL
# ==============================================================================

# Detect PostgreSQL databases from environment variables and config files
# Returns: Connection details in format "type|host|port|database|user|is_local|password|full_url"
detect_postgresql() {
    local project_dir="${1:-.}"
    local databases=()

    # Discover all env/config files recursively
    local env_files
    mapfile -t env_files < <(_discover_env_files "$project_dir")

    for env_file in "${env_files[@]}"; do
        [[ -f "$env_file" ]] || continue

        # --- URL-based detection ---
        if [[ "$env_file" == *.php || "$env_file" == *.yml || "$env_file" == *.yaml || "$env_file" == *.properties ]]; then
            # Framework config files: extract known keys
            local url=""
            # Spring Boot
            url=$(_extract_config_value "$env_file" "spring.datasource.url")
            [[ -z "$url" ]] && url=$(_extract_config_value "$env_file" "url")  # Rails database.yml

            if [[ "$url" =~ postgres(ql)?://([^:@]+)(:([^@]+))?@([^:/]+)(:([0-9]+))?/([^?]+) ]]; then
                local user="${BASH_REMATCH[2]}" password="${BASH_REMATCH[4]:-}"
                local host="${BASH_REMATCH[5]}" port="${BASH_REMATCH[7]:-5432}" database="${BASH_REMATCH[8]}"
                local is_local="false"
                [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                local safe_url="${url//|/%7C}" safe_password="${password//|/%7C}"
                databases+=("postgresql|$host|$port|$database|$user|$is_local|$safe_password|$safe_url")
            fi

            # WordPress wp-config.php
            if [[ "$env_file" == *wp-config.php ]]; then
                local wp_host wp_db wp_user wp_pass
                wp_host=$(_extract_config_value "$env_file" "DB_HOST")
                wp_db=$(_extract_config_value "$env_file" "DB_NAME")
                wp_user=$(_extract_config_value "$env_file" "DB_USER")
                wp_pass=$(_extract_config_value "$env_file" "DB_PASSWORD")
                # WordPress is almost always MySQL, skip for PostgreSQL
            fi

            # Rails config/database.yml — check adapter
            if [[ "$env_file" == *database.yml ]]; then
                local adapter
                adapter=$(_extract_config_value "$env_file" "adapter")
                if [[ "$adapter" == *postgres* ]]; then
                    local r_host r_port r_db r_user r_pass
                    r_host=$(_extract_config_value "$env_file" "host")
                    r_port=$(_extract_config_value "$env_file" "port")
                    r_db=$(_extract_config_value "$env_file" "database")
                    r_user=$(_extract_config_value "$env_file" "username")
                    r_pass=$(_extract_config_value "$env_file" "password")
                    if [[ -n "$r_db" ]]; then
                        local is_local="false"
                        [[ "${r_host:-localhost}" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                        databases+=("postgresql|${r_host:-localhost}|${r_port:-5432}|$r_db|${r_user:-postgres}|$is_local|${r_pass:-}|")
                    fi
                fi
            fi

            continue
        fi

        # --- .env file parsing ---
        local _PG_HOST="" _PG_PORT="" _PG_DB="" _PG_USER="" _PG_PASS=""
        local _DB_CONNECTION="" _DB_HOST="" _DB_PORT="" _DB_DATABASE="" _DB_USER="" _DB_PASS=""

        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Strip inline comments from value portion (KEY=value # comment → KEY=value)
            if [[ "$line" == *"="* ]]; then
                local _key="${line%%=*}" _val="${line#*=}"
                _val=$(_sanitize_env_value "$_val")
                line="${_key}=${_val}"
            fi

            # URL-based: DATABASE_URL, POSTGRES_URL, etc.
            if [[ "$line" =~ ^[A-Z_]*DATABASE_URL= ]] || [[ "$line" =~ ^POSTGRES.*URL= ]]; then
                local url="${line#*=}"
                url="${url//\"/}"; url="${url//\'/}"

                # Skip URLs with unresolved variable interpolation
                _has_interpolation "$url" && continue

                if [[ "$url" =~ postgres(ql)?(\+[a-z0-9]+)?://([^:@]+)(:([^@]+))?@([^:/]+)(:([0-9]+))?/([^?]+) ]]; then
                    local user="${BASH_REMATCH[3]}" password="${BASH_REMATCH[5]:-}"
                    local host="${BASH_REMATCH[6]}" port="${BASH_REMATCH[8]:-5432}" database="${BASH_REMATCH[9]}"
                    _is_placeholder_db "$database" && continue
                    local is_local="false"
                    [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                    local safe_url="${url//|/%7C}" safe_password="${password//|/%7C}"
                    databases+=("postgresql|$host|$port|$database|$user|$is_local|$safe_password|$safe_url")
                fi
            fi

            # Individual vars: POSTGRES_*, PG_*, DB_* (Laravel/generic)
            case "$line" in
                POSTGRES_HOST=*|PG_HOST=*)       _PG_HOST="${line#*=}" ;;
                POSTGRES_PORT=*|PG_PORT=*)       _PG_PORT="${line#*=}" ;;
                POSTGRES_DB=*|POSTGRES_DATABASE=*|PG_DATABASE=*) _PG_DB="${line#*=}" ;;
                POSTGRES_USER=*|PG_USER=*)       _PG_USER="${line#*=}" ;;
                POSTGRES_PASSWORD=*|PG_PASSWORD=*) _PG_PASS="${line#*=}" ;;
            esac

            # DB_* vars (Laravel, generic frameworks) — only if DB_CONNECTION=pgsql/postgres
            case "$line" in
                DB_CONNECTION=*) _DB_CONNECTION="${line#*=}" ;;
                DB_HOST=*)       _DB_HOST="${line#*=}" ;;
                DB_PORT=*)       _DB_PORT="${line#*=}" ;;
                DB_DATABASE=*)   _DB_DATABASE="${line#*=}" ;;
                DB_USERNAME=*|DB_USER=*) _DB_USER="${line#*=}" ;;
                DB_PASSWORD=*)   _DB_PASS="${line#*=}" ;;
            esac
        done < "$env_file"

        # Strip quotes from extracted values
        _PG_HOST=$(_sanitize_env_value "${_PG_HOST}")
        _PG_PORT=$(_sanitize_env_value "${_PG_PORT}")
        _PG_DB=$(_sanitize_env_value "${_PG_DB}")
        _PG_USER=$(_sanitize_env_value "${_PG_USER}")
        _PG_PASS=$(_sanitize_env_value "${_PG_PASS}")

        # Construct from POSTGRES_*/PG_* vars
        if [[ -n "$_PG_DB" ]] && ! _is_placeholder_db "$_PG_DB" && ! _has_interpolation "$_PG_DB"; then
            local host="${_PG_HOST:-localhost}" port="${_PG_PORT:-5432}"
            local user="${_PG_USER:-postgres}" password="${_PG_PASS:-}"
            local is_local="false"
            [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
            databases+=("postgresql|$host|$port|$_PG_DB|$user|$is_local|$password|")
        fi

        # Construct from DB_* vars if connection type is PostgreSQL
        _DB_CONNECTION=$(_sanitize_env_value "${_DB_CONNECTION}")
        if [[ "${_DB_CONNECTION:-}" == "pgsql" || "${_DB_CONNECTION:-}" == "postgres" || "${_DB_CONNECTION:-}" == "postgresql" ]]; then
            _DB_HOST=$(_sanitize_env_value "${_DB_HOST}")
            _DB_PORT=$(_sanitize_env_value "${_DB_PORT}")
            _DB_DATABASE=$(_sanitize_env_value "${_DB_DATABASE}")
            _DB_USER=$(_sanitize_env_value "${_DB_USER}")
            _DB_PASS=$(_sanitize_env_value "${_DB_PASS}")
            if [[ -n "${_DB_DATABASE:-}" ]] && ! _is_placeholder_db "$_DB_DATABASE" && ! _has_interpolation "$_DB_DATABASE"; then
                local host="${_DB_HOST:-localhost}" port="${_DB_PORT:-5432}"
                local user="${_DB_USER:-postgres}" password="${_DB_PASS:-}"
                local is_local="false"
                [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                databases+=("postgresql|$host|$port|$_DB_DATABASE|$user|$is_local|$password|")
            fi
        fi

        # Reset DB_* vars for next file
        unset _DB_CONNECTION _DB_HOST _DB_PORT _DB_DATABASE _DB_USER _DB_PASS
    done

    # Output results (one per line, deduplicated by type+host+port+database)
    printf '%s\n' "${databases[@]}" | _dedup_databases
}

# ==============================================================================
# DETECTION: MYSQL
# ==============================================================================

# Detect MySQL/MariaDB databases from environment variables and config files
# Returns: Connection details in format "type|host|port|database|user|is_local|password|full_url"
detect_mysql() {
    local project_dir="${1:-.}"
    local databases=()

    # Discover all env/config files recursively
    local env_files
    mapfile -t env_files < <(_discover_env_files "$project_dir")

    for env_file in "${env_files[@]}"; do
        [[ -f "$env_file" ]] || continue

        # --- Framework config files ---
        if [[ "$env_file" == *.php || "$env_file" == *.yml || "$env_file" == *.yaml || "$env_file" == *.properties ]]; then

            # WordPress wp-config.php
            if [[ "$env_file" == *wp-config.php ]]; then
                local wp_host wp_db wp_user wp_pass
                wp_host=$(_extract_config_value "$env_file" "DB_HOST")
                wp_db=$(_extract_config_value "$env_file" "DB_NAME")
                wp_user=$(_extract_config_value "$env_file" "DB_USER")
                wp_pass=$(_extract_config_value "$env_file" "DB_PASSWORD")
                if [[ -n "$wp_db" ]]; then
                    # WordPress host can include :port
                    local host="${wp_host%%:*}" port="${wp_host##*:}"
                    [[ "$host" == "$port" ]] && port="3306"
                    local is_local="false"
                    [[ "${host:-localhost}" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                    databases+=("mysql|${host:-localhost}|${port:-3306}|$wp_db|${wp_user:-root}|$is_local|${wp_pass:-}|")
                fi
            fi

            # Spring Boot application.properties / application.yml
            local url=""
            url=$(_extract_config_value "$env_file" "spring.datasource.url")
            if [[ "$url" =~ mysql://([^:@/]+)(:([0-9]+))?/([^?]+) ]] || [[ "$url" =~ jdbc:mysql://([^:@/]+)(:([0-9]+))?/([^?]+) ]]; then
                local host="${BASH_REMATCH[1]}" port="${BASH_REMATCH[3]:-3306}" database="${BASH_REMATCH[4]}"
                local s_user s_pass
                s_user=$(_extract_config_value "$env_file" "spring.datasource.username")
                s_pass=$(_extract_config_value "$env_file" "spring.datasource.password")
                local is_local="false"
                [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                databases+=("mysql|$host|$port|$database|${s_user:-root}|$is_local|${s_pass:-}|")
            fi

            # Rails config/database.yml — check adapter
            if [[ "$env_file" == *database.yml ]]; then
                local adapter
                adapter=$(_extract_config_value "$env_file" "adapter")
                if [[ "$adapter" == *mysql* ]]; then
                    local r_host r_port r_db r_user r_pass
                    r_host=$(_extract_config_value "$env_file" "host")
                    r_port=$(_extract_config_value "$env_file" "port")
                    r_db=$(_extract_config_value "$env_file" "database")
                    r_user=$(_extract_config_value "$env_file" "username")
                    r_pass=$(_extract_config_value "$env_file" "password")
                    if [[ -n "$r_db" ]]; then
                        local is_local="false"
                        [[ "${r_host:-localhost}" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                        databases+=("mysql|${r_host:-localhost}|${r_port:-3306}|$r_db|${r_user:-root}|$is_local|${r_pass:-}|")
                    fi
                fi
            fi

            continue
        fi

        # --- .env file parsing ---
        local _MY_HOST="" _MY_PORT="" _MY_DB="" _MY_USER="" _MY_PASS=""
        local _DB_CONNECTION="" _DB_HOST="" _DB_PORT="" _DB_DATABASE="" _DB_USER="" _DB_PASS=""

        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Strip inline comments from value
            if [[ "$line" == *"="* ]]; then
                local _key="${line%%=*}" _val="${line#*=}"
                _val=$(_sanitize_env_value "$_val")
                line="${_key}=${_val}"
            fi

            # URL-based: DATABASE_URL, MYSQL_URL, etc.
            if [[ "$line" =~ ^[A-Z_]*DATABASE_URL= ]] || [[ "$line" =~ ^MYSQL.*URL= ]]; then
                local url="${line#*=}"
                url="${url//\"/}"; url="${url//\'/}"
                _has_interpolation "$url" && continue

                # Support mysql://, mysql2://, mariadb://
                if [[ "$url" =~ (mysql|mysql2|mariadb)://([^:@]+)(:([^@]+))?@([^:/]+)(:([0-9]+))?/([^?]+) ]]; then
                    local user="${BASH_REMATCH[2]}" password="${BASH_REMATCH[4]:-}"
                    local host="${BASH_REMATCH[5]}" port="${BASH_REMATCH[7]:-3306}" database="${BASH_REMATCH[8]}"
                    _is_placeholder_db "$database" && continue
                    local is_local="false"
                    [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                    local safe_url="${url//|/%7C}" safe_password="${password//|/%7C}"
                    databases+=("mysql|$host|$port|$database|$user|$is_local|$safe_password|$safe_url")
                fi
            fi

            # MYSQL_* individual vars
            case "$line" in
                MYSQL_HOST=*)     _MY_HOST="${line#*=}" ;;
                MYSQL_PORT=*)     _MY_PORT="${line#*=}" ;;
                MYSQL_DATABASE=*) _MY_DB="${line#*=}" ;;
                MYSQL_USER=*)     _MY_USER="${line#*=}" ;;
                MYSQL_PASSWORD=*) _MY_PASS="${line#*=}" ;;
            esac

            # DB_* vars (Laravel, generic frameworks)
            case "$line" in
                DB_CONNECTION=*) _DB_CONNECTION="${line#*=}" ;;
                DB_HOST=*)       _DB_HOST="${line#*=}" ;;
                DB_PORT=*)       _DB_PORT="${line#*=}" ;;
                DB_DATABASE=*)   _DB_DATABASE="${line#*=}" ;;
                DB_USERNAME=*|DB_USER=*) _DB_USER="${line#*=}" ;;
                DB_PASSWORD=*)   _DB_PASS="${line#*=}" ;;
            esac
        done < "$env_file"

        # Sanitize extracted values
        _MY_HOST=$(_sanitize_env_value "${_MY_HOST}")
        _MY_PORT=$(_sanitize_env_value "${_MY_PORT}")
        _MY_DB=$(_sanitize_env_value "${_MY_DB}")
        _MY_USER=$(_sanitize_env_value "${_MY_USER}")
        _MY_PASS=$(_sanitize_env_value "${_MY_PASS}")

        # Construct from MYSQL_* vars
        if [[ -n "$_MY_DB" ]] && ! _is_placeholder_db "$_MY_DB" && ! _has_interpolation "$_MY_DB"; then
            local host="${_MY_HOST:-localhost}" port="${_MY_PORT:-3306}"
            local user="${_MY_USER:-root}" password="${_MY_PASS:-}"
            local is_local="false"
            [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
            databases+=("mysql|$host|$port|$_MY_DB|$user|$is_local|$password|")
        fi

        # Construct from DB_* vars if connection type is MySQL/MariaDB
        _DB_CONNECTION=$(_sanitize_env_value "${_DB_CONNECTION}")
        if [[ "${_DB_CONNECTION:-}" == "mysql" || "${_DB_CONNECTION:-}" == "mariadb" ]]; then
            _DB_DATABASE=$(_sanitize_env_value "${_DB_DATABASE}")
            _DB_HOST=$(_sanitize_env_value "${_DB_HOST}")
            _DB_PORT=$(_sanitize_env_value "${_DB_PORT}")
            _DB_USER=$(_sanitize_env_value "${_DB_USER}")
            _DB_PASS=$(_sanitize_env_value "${_DB_PASS}")
            if [[ -n "${_DB_DATABASE:-}" ]] && ! _is_placeholder_db "$_DB_DATABASE" && ! _has_interpolation "$_DB_DATABASE"; then
                local host="${_DB_HOST:-localhost}" port="${_DB_PORT:-3306}"
                local user="${_DB_USER:-root}" password="${_DB_PASS:-}"
                local is_local="false"
                [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                databases+=("mysql|$host|$port|$_DB_DATABASE|$user|$is_local|$password|")
            fi
        fi

        # Reset for next file
        unset _DB_CONNECTION _DB_HOST _DB_PORT _DB_DATABASE _DB_USER _DB_PASS
    done

    # Output results (one per line, deduplicated by type+host+port+database)
    printf '%s\n' "${databases[@]}" | _dedup_databases
}

# ==============================================================================
# DETECTION: MONGODB
# ==============================================================================

# Detect MongoDB databases from environment variables and config files
# Returns: Connection details in format "type|host|port|database|user|is_local|password|full_url"
detect_mongodb() {
    local project_dir="${1:-.}"
    local databases=()

    # Discover all env/config files recursively
    local env_files
    mapfile -t env_files < <(_discover_env_files "$project_dir")

    for env_file in "${env_files[@]}"; do
        [[ -f "$env_file" ]] || continue

        # Skip non-env framework configs for MongoDB (handled via URLs in .env)
        [[ "$env_file" == *.php || "$env_file" == *.properties ]] && continue

        # --- .env file parsing ---
        local _MONGO_HOST="" _MONGO_PORT="" _MONGO_DB="" _MONGO_USER="" _MONGO_PASS=""
        local _DB_CONNECTION="" _DB_HOST="" _DB_PORT="" _DB_DATABASE="" _DB_USER="" _DB_PASS=""

        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Strip inline comments from value
            if [[ "$line" == *"="* ]]; then
                local _key="${line%%=*}" _val="${line#*=}"
                _val=$(_sanitize_env_value "$_val")
                line="${_key}=${_val}"
            fi

            # URL-based: DATABASE_URL, MONGO_URL, MONGO_URI, MONGODB_URI, etc.
            if [[ "$line" =~ ^[A-Z_]*DATABASE_URL= ]] || [[ "$line" =~ ^MONGO[A-Z_]*URL= ]] || [[ "$line" =~ ^MONGO[A-Z_]*URI= ]]; then
                local url="${line#*=}"
                url="${url//\"/}"; url="${url//\'/}"
                _has_interpolation "$url" && continue
                local safe_url="${url//|/%7C}"

                # mongodb+srv (always remote)
                if [[ "$url" == mongodb+srv://* ]]; then
                    if [[ "$url" =~ mongodb\+srv://([^:@]+)(:([^@]+))?@([^:/]+)/([^?]+) ]]; then
                        local user="${BASH_REMATCH[1]}" password="${BASH_REMATCH[3]:-}"
                        local host="${BASH_REMATCH[4]}" database="${BASH_REMATCH[5]}"
                        _is_placeholder_db "$database" && continue
                        local safe_password="${password//|/%7C}"
                        databases+=("mongodb|$host|27017|$database|$user|false|$safe_password|$safe_url")
                    fi
                # Regular mongodb:// with auth (user:pass@host)
                elif [[ "$url" =~ mongodb://([^:@]+)(:([^@]+))?@([^:/]+)(:([0-9]+))?/([^?]+) ]]; then
                    local user="${BASH_REMATCH[1]}" password="${BASH_REMATCH[3]:-}"
                    local host="${BASH_REMATCH[4]}" port="${BASH_REMATCH[6]:-27017}" database="${BASH_REMATCH[7]}"
                    _is_placeholder_db "$database" && continue
                    local is_local="false"
                    [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                    local safe_password="${password//|/%7C}"
                    databases+=("mongodb|$host|$port|$database|$user|$is_local|$safe_password|$safe_url")
                # mongodb:// without auth (host:port/database)
                elif [[ "$url" =~ mongodb://([^:/]+)(:([0-9]+))?/([^?]+) ]]; then
                    local host="${BASH_REMATCH[1]}" port="${BASH_REMATCH[3]:-27017}" database="${BASH_REMATCH[4]}"
                    _is_placeholder_db "$database" && continue
                    local is_local="false"
                    [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                    databases+=("mongodb|$host|$port|$database||$is_local||$safe_url")
                fi
            fi

            # MONGO_* individual vars
            case "$line" in
                MONGO_HOST=*|MONGODB_HOST=*)       _MONGO_HOST="${line#*=}" ;;
                MONGO_PORT=*|MONGODB_PORT=*)       _MONGO_PORT="${line#*=}" ;;
                MONGO_DATABASE=*|MONGODB_DATABASE=*|MONGO_DB=*|MONGO_INITDB_DATABASE=*) _MONGO_DB="${line#*=}" ;;
                MONGO_USER=*|MONGODB_USER=*)       _MONGO_USER="${line#*=}" ;;
                MONGO_PASSWORD=*|MONGODB_PASSWORD=*) _MONGO_PASS="${line#*=}" ;;
            esac

            # DB_* vars (generic) — only if DB_CONNECTION=mongodb
            case "$line" in
                DB_CONNECTION=*) _DB_CONNECTION="${line#*=}" ;;
                DB_HOST=*)       _DB_HOST="${line#*=}" ;;
                DB_PORT=*)       _DB_PORT="${line#*=}" ;;
                DB_DATABASE=*)   _DB_DATABASE="${line#*=}" ;;
                DB_USERNAME=*|DB_USER=*) _DB_USER="${line#*=}" ;;
                DB_PASSWORD=*)   _DB_PASS="${line#*=}" ;;
            esac
        done < "$env_file"

        # Sanitize extracted values
        _MONGO_HOST=$(_sanitize_env_value "${_MONGO_HOST}")
        _MONGO_PORT=$(_sanitize_env_value "${_MONGO_PORT}")
        _MONGO_DB=$(_sanitize_env_value "${_MONGO_DB}")
        _MONGO_USER=$(_sanitize_env_value "${_MONGO_USER}")
        _MONGO_PASS=$(_sanitize_env_value "${_MONGO_PASS}")

        # Construct from MONGO_* vars
        if [[ -n "$_MONGO_DB" ]] && ! _is_placeholder_db "$_MONGO_DB" && ! _has_interpolation "$_MONGO_DB"; then
            local host="${_MONGO_HOST:-localhost}" port="${_MONGO_PORT:-27017}"
            local user="${_MONGO_USER:-}" password="${_MONGO_PASS:-}"
            local is_local="false"
            [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
            databases+=("mongodb|$host|$port|$_MONGO_DB|$user|$is_local|$password|")
        fi

        # Construct from DB_* vars if connection type is MongoDB
        _DB_CONNECTION=$(_sanitize_env_value "${_DB_CONNECTION}")
        if [[ "${_DB_CONNECTION:-}" == "mongodb" ]]; then
            _DB_DATABASE=$(_sanitize_env_value "${_DB_DATABASE}")
            _DB_HOST=$(_sanitize_env_value "${_DB_HOST}")
            _DB_PORT=$(_sanitize_env_value "${_DB_PORT}")
            _DB_USER=$(_sanitize_env_value "${_DB_USER}")
            _DB_PASS=$(_sanitize_env_value "${_DB_PASS}")
            if [[ -n "${_DB_DATABASE:-}" ]] && ! _is_placeholder_db "$_DB_DATABASE" && ! _has_interpolation "$_DB_DATABASE"; then
                local host="${_DB_HOST:-localhost}" port="${_DB_PORT:-27017}"
                local user="${_DB_USER:-}" password="${_DB_PASS:-}"
                local is_local="false"
                [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]] && is_local="true"
                databases+=("mongodb|$host|$port|$_DB_DATABASE|$user|$is_local|$password|")
            fi
        fi

        # Reset for next file
        unset _DB_CONNECTION _DB_HOST _DB_PORT _DB_DATABASE _DB_USER _DB_PASS
    done

    # Output results (one per line, deduplicated by type+host+port+database)
    printf '%s\n' "${databases[@]}" | _dedup_databases
}

# ==============================================================================
# DETECTION: DOCKER DATABASES
# ==============================================================================

# File-based flag to track if we started Docker (persists across multiple backups)
# Security: Use user-specific cache directory instead of world-writable /tmp
CHECKPOINT_CACHE_DIR="${HOME}/.cache/checkpoint"
mkdir -p "$CHECKPOINT_CACHE_DIR" 2>/dev/null || true
CHECKPOINT_DOCKER_FLAG="${CHECKPOINT_CACHE_DIR}/.started-docker"

# Check if we started Docker (for cleanup decision)
did_we_start_docker() {
    # Security: Ensure it's a regular file, not a symlink
    [[ -f "$CHECKPOINT_DOCKER_FLAG" ]] && [[ ! -L "$CHECKPOINT_DOCKER_FLAG" ]]
}

# Detect databases running in Docker containers
# Returns: Connection details in format "docker|container_name|db_type|database|user|password"
detect_docker_databases() {
    local project_dir="${1:-.}"
    local databases=()

    # Check for docker-compose files (root + up to 2 levels deep)
    local compose_file=""
    for f in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
        if [[ -f "$project_dir/$f" ]]; then
            compose_file="$project_dir/$f"
            break
        fi
    done

    # If not found at root, search subdirectories
    if [[ -z "$compose_file" ]]; then
        while IFS= read -r -d '' cf; do
            compose_file="$cf"
            break
        done < <(find "$project_dir" -maxdepth 2 -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) \
            -not -path "*/node_modules/*" -not -path "*/.git/*" -print0 2>/dev/null)
    fi

    [[ -z "$compose_file" ]] && return

    # Parse docker-compose for database services using grep/sed (shell-agnostic)
    local in_service=""
    local db_type=""
    local db_name=""
    local db_user=""
    local db_pass=""
    local container_name=""

    while IFS= read -r line; do
        # Detect service definition (2 spaces + name + colon, no more indentation)
        # Use sed to extract service name
        if echo "$line" | grep -qE '^  [a-zA-Z0-9_-]+:$'; then
            # Save previous service if it was a database
            if [[ -n "$in_service" && -n "$db_type" && -n "$db_name" ]]; then
                local cont="${container_name:-$in_service}"
                databases+=("docker|$cont|$db_type|$db_name|${db_user:-postgres}|${db_pass:-}")
            fi
            # Start new service - extract name with sed
            in_service=$(echo "$line" | sed 's/^  \([a-zA-Z0-9_-]*\):$/\1/')
            db_type=""
            db_name=""
            db_user=""
            db_pass=""
            container_name=""
        fi

        # Detect database type from image
        if echo "$line" | grep -q "image:.*postgres"; then
            db_type="postgresql"
        elif echo "$line" | grep -qE "image:.*(mysql|mariadb)"; then
            db_type="mysql"
        elif echo "$line" | grep -q "image:.*mongo"; then
            db_type="mongodb"
        fi

        # Detect container name
        if echo "$line" | grep -q "container_name:"; then
            container_name=$(echo "$line" | sed 's/.*container_name:[[:space:]]*//' | tr -d ' ')
        fi

        # Detect PostgreSQL env vars
        if echo "$line" | grep -q "POSTGRES_DB:"; then
            db_name=$(echo "$line" | sed 's/.*POSTGRES_DB:[[:space:]]*//' | tr -d ' ')
        fi
        if echo "$line" | grep -q "POSTGRES_USER:"; then
            db_user=$(echo "$line" | sed 's/.*POSTGRES_USER:[[:space:]]*//' | tr -d ' ')
        fi
        if echo "$line" | grep -q "POSTGRES_PASSWORD:"; then
            db_pass=$(echo "$line" | sed 's/.*POSTGRES_PASSWORD:[[:space:]]*//' | tr -d ' ')
        fi

        # Detect MySQL env vars
        if echo "$line" | grep -q "MYSQL_DATABASE:"; then
            db_name=$(echo "$line" | sed 's/.*MYSQL_DATABASE:[[:space:]]*//' | tr -d ' ')
        fi
        if echo "$line" | grep -q "MYSQL_USER:"; then
            db_user=$(echo "$line" | sed 's/.*MYSQL_USER:[[:space:]]*//' | tr -d ' ')
        fi
        if echo "$line" | grep -q "MYSQL_PASSWORD:"; then
            db_pass=$(echo "$line" | sed 's/.*MYSQL_PASSWORD:[[:space:]]*//' | tr -d ' ')
        fi
        if echo "$line" | grep -q "MYSQL_ROOT_PASSWORD:"; then
            [[ -z "$db_pass" ]] && db_pass=$(echo "$line" | sed 's/.*MYSQL_ROOT_PASSWORD:[[:space:]]*//' | tr -d ' ')
            [[ -z "$db_user" ]] && db_user="root"
        fi

        # Detect MongoDB env vars
        if echo "$line" | grep -q "MONGO_INITDB_DATABASE:"; then
            db_name=$(echo "$line" | sed 's/.*MONGO_INITDB_DATABASE:[[:space:]]*//' | tr -d ' ')
        fi

    done < "$compose_file"

    # Don't forget the last service
    if [[ -n "$in_service" && -n "$db_type" && -n "$db_name" ]]; then
        local cont="${container_name:-$in_service}"
        databases+=("docker|$cont|$db_type|$db_name|${db_user:-postgres}|${db_pass:-}")
    fi

    # Output results
    printf '%s\n' "${databases[@]}"
}

# Check if Docker is running (with timeout to prevent hanging)
is_docker_running() {
    # Use timeout if available (prevents hanging when Docker is starting)
    if command -v timeout &>/dev/null; then
        timeout 5 docker info &>/dev/null
    elif command -v gtimeout &>/dev/null; then
        gtimeout 5 docker info &>/dev/null
    else
        # Fallback: run in background with manual timeout
        docker info &>/dev/null &
        local pid=$!
        local count=0
        while kill -0 $pid 2>/dev/null && [[ $count -lt 5 ]]; do
            sleep 1
            count=$((count + 1))
        done
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null || true
            return 1
        fi
        wait $pid 2>/dev/null
    fi
}

# Start Docker Desktop (macOS)
# Creates a flag file to track that we started Docker (persists across backup runs)
start_docker() {
    if is_docker_running; then
        return 0
    fi

    echo "  🐳 Starting Docker Desktop..."
    if ! _err=$(open -a Docker 2>&1); then
        log_debug "Failed to start Docker Desktop: $_err"
        return 1
    fi

    # Wait for Docker to be ready (up to 60 seconds)
    local wait_count=0
    while ! is_docker_running && [[ $wait_count -lt 60 ]]; do
        sleep 2
        wait_count=$((wait_count + 2))
        if [[ $((wait_count % 10)) -eq 0 ]]; then
            echo "  ⏳ Waiting for Docker... (${wait_count}s)"
        fi
    done

    if is_docker_running; then
        echo "  ✓ Docker started"
        # Create flag file to indicate we started Docker
        # This persists across multiple backup runs so we can stop it after ALL backups complete
        # Security: Only create if not a symlink (prevent symlink attacks)
        if [[ -L "$CHECKPOINT_DOCKER_FLAG" ]]; then
            rm -f "$CHECKPOINT_DOCKER_FLAG"
        fi
        touch "$CHECKPOINT_DOCKER_FLAG"
        return 0
    else
        echo "  ⚠ Docker failed to start in time"
        return 1
    fi
}

# Stop Docker Desktop (only if we started it)
# Uses file-based flag to track state across multiple backup runs
stop_docker() {
    # Only stop if we started it (flag file exists)
    if ! did_we_start_docker; then
        return 0
    fi

    if [[ "${STOP_DOCKER_AFTER_BACKUP:-true}" != "true" ]]; then
        # User wants Docker to stay running, but clean up flag file
        rm -f "$CHECKPOINT_DOCKER_FLAG"
        return 0
    fi

    echo "  🐳 Stopping Docker (we started it)..."
    osascript -e 'quit app "Docker"' &>/dev/null || true

    # Remove flag file after stopping
    rm -f "$CHECKPOINT_DOCKER_FLAG"
}

# ==============================================================================
# UNIFIED DETECTION
# ==============================================================================

# Detect all databases in project (local and remote)
# Returns: Array of database info strings
#   SQLite: "sqlite|<path>"
#   Others: "type|host|port|database|user|is_local"
detect_databases() {
    local project_dir="${1:-.}"

    echo "🔍 Scanning for databases..."

    # SQLite files
    local sqlite_dbs
    sqlite_dbs=$(detect_sqlite "$project_dir")
    if [[ -n "$sqlite_dbs" ]]; then
        while IFS= read -r db_path; do
            echo "sqlite|$db_path"
        done <<< "$sqlite_dbs"
    fi

    # PostgreSQL
    local postgres_dbs
    postgres_dbs=$(detect_postgresql "$project_dir")
    if [[ -n "$postgres_dbs" ]]; then
        echo "$postgres_dbs"
    fi

    # MySQL
    local mysql_dbs
    mysql_dbs=$(detect_mysql "$project_dir")
    if [[ -n "$mysql_dbs" ]]; then
        echo "$mysql_dbs"
    fi

    # MongoDB
    local mongo_dbs
    mongo_dbs=$(detect_mongodb "$project_dir")
    if [[ -n "$mongo_dbs" ]]; then
        echo "$mongo_dbs"
    fi

    # Docker databases
    if [[ "${BACKUP_DOCKER_DATABASES:-true}" == "true" ]]; then
        local docker_dbs
        docker_dbs=$(detect_docker_databases "$project_dir")
        if [[ -n "$docker_dbs" ]]; then
            echo "$docker_dbs"
        fi
    fi
}

# ==============================================================================
# BACKUP FUNCTIONS
# ==============================================================================

# Backup a single database based on type
# Args:
#   $1 - Database info string (from detect_databases)
#   $2 - Backup directory
# Returns: 0 on success, 1 on failure
backup_single_database() {
    local db_info="$1"
    local backup_dir="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    IFS='|' read -r db_type rest <<< "$db_info"

    case "$db_type" in
        sqlite)
            # SQLite: Safe backup with verification
            local db_path="$rest"
            local db_name=$(basename "$db_path")
            local backup_file="$backup_dir/databases/${db_name%.db}_${timestamp}_$$.db.gz"

            mkdir -p "$backup_dir/databases"

            # Use sqlite3 .backup for safe copy (handles locks properly)
            local temp_db
            temp_db=$(mktemp -t "sqlite_backup.XXXXXX.db") || {
                echo "❌ SQLite: $db_name (temp file failed)"
                return 1
            }

            local _db_err
            if _db_err=$(sqlite3 "$db_path" ".backup '$temp_db'" 2>&1); then
                if _db_err=$(gzip -c "$temp_db" > "$backup_file" 2>&1); then
                    # Verify backup integrity
                    if _db_err=$(gunzip -t "$backup_file" 2>&1); then
                        log_info "SQLite backup succeeded: $db_name"
                        echo "✅ SQLite: $db_name"
                        rm -f "$temp_db"
                    else
                        log_debug "gunzip verification failed for $db_name: $_db_err"
                        echo "❌ SQLite: $db_name (verification failed)"
                        rm -f "$temp_db" "$backup_file"
                        return 1
                    fi
                else
                    log_debug "gzip compression failed for $db_name: $_db_err"
                    echo "❌ SQLite: $db_name (compression failed)"
                    rm -f "$temp_db"
                    return 1
                fi
            else
                log_debug "sqlite3 backup failed for $db_name: $_db_err"
                echo "❌ SQLite: $db_name (backup command failed)"
                rm -f "$temp_db"
                return 1
            fi
            ;;

        postgresql)
            # PostgreSQL: Use pg_dump with verification
            IFS='|' read -r host port database user is_local password full_url <<< "$rest"

            # Try credential store if password is empty
            if [[ -z "$password" ]]; then
                local cred_password
                cred_password="$(_get_db_credential "postgres" "$database")" && password="$cred_password"
            fi

            # Check if remote databases should be backed up
            if [[ "$is_local" != "true" ]]; then
                if [[ "${BACKUP_REMOTE_DATABASES:-false}" != "true" ]]; then
                    echo "⊘ PostgreSQL: $database (remote - skipped, set BACKUP_REMOTE_DATABASES=true to enable)"
                    return 0
                fi
            fi

            if ! command -v pg_dump &>/dev/null; then
                echo "⚠ PostgreSQL: pg_dump not found - skipping $database"
                return 1
            fi

            local backup_file="$backup_dir/databases/postgres_${database}_${timestamp}_$$.sql.gz"
            mkdir -p "$backup_dir/databases"

            # Capture exit code properly
            local pg_exit_code

            if [[ "$is_local" == "true" ]]; then
                # Local: use host/port/user (relies on .pgpass or peer auth)
                local we_started_postgres=false

                # First attempt - try direct dump
                pg_dump -h "$host" -p "$port" -U "$user" "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                pg_exit_code=${PIPESTATUS[0]}

                # If failed, try to start PostgreSQL temporarily
                if [[ $pg_exit_code -ne 0 ]] && [[ "${AUTO_START_LOCAL_DB:-true}" == "true" ]]; then
                    echo "  ⚠ PostgreSQL not running, attempting to start..."

                    # Detect PostgreSQL installation and try to start
                    if command -v brew &>/dev/null && brew services list 2>/dev/null | grep -q "postgresql"; then
                        # Homebrew PostgreSQL
                        local pg_service=$(brew services list 2>/dev/null | grep -E "^postgresql" | head -1 | awk '{print $1}')
                        if [[ -n "$pg_service" ]]; then
                            echo "  🔄 Starting PostgreSQL via Homebrew..."
                            if ! _svc_err=$(brew services start "$pg_service" 2>&1); then
                                log_debug "brew services start $pg_service: $_svc_err"
                            fi
                            sleep 3  # Give it time to start
                            we_started_postgres=true
                        fi
                    elif [[ -d "/Applications/Postgres.app" ]]; then
                        # Postgres.app
                        echo "  🔄 Starting Postgres.app..."
                        open -a "Postgres" --hide
                        sleep 5  # Postgres.app takes a moment
                        we_started_postgres=true
                    elif command -v pg_ctl &>/dev/null; then
                        # Manual install with pg_ctl
                        local pgdata="${PGDATA:-/usr/local/var/postgres}"
                        if [[ -d "$pgdata" ]]; then
                            echo "  🔄 Starting PostgreSQL via pg_ctl..."
                            if ! _svc_err=$(pg_ctl -D "$pgdata" start 2>&1); then
                                log_debug "pg_ctl start: $_svc_err"
                            fi
                            sleep 3
                            we_started_postgres=true
                        fi
                    fi

                    # Retry dump if we started PostgreSQL
                    if [[ "$we_started_postgres" == "true" ]]; then
                        # Wait for PostgreSQL to be ready (up to 10 seconds)
                        local wait_count=0
                        while ! pg_isready -h "$host" -p "$port" &>/dev/null && [[ $wait_count -lt 10 ]]; do
                            sleep 1
                            wait_count=$((wait_count + 1))
                        done

                        if pg_isready -h "$host" -p "$port" &>/dev/null; then
                            echo "  ✓ PostgreSQL started, dumping..."
                            pg_dump -h "$host" -p "$port" -U "$user" "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                            pg_exit_code=${PIPESTATUS[0]}
                        else
                            echo "  ⚠ PostgreSQL failed to start in time"
                        fi

                        # Stop PostgreSQL if we started it (to restore original state)
                        if [[ "${STOP_DB_AFTER_BACKUP:-true}" == "true" ]]; then
                            echo "  🔄 Stopping PostgreSQL (restoring original state)..."
                            if command -v brew &>/dev/null && brew services list 2>/dev/null | grep -q "postgresql"; then
                                local pg_service=$(brew services list 2>/dev/null | grep -E "^postgresql" | head -1 | awk '{print $1}')
                                if ! _svc_err=$(brew services stop "$pg_service" 2>&1); then
                                    log_debug "brew services stop $pg_service: $_svc_err"
                                fi
                            elif [[ -d "/Applications/Postgres.app" ]]; then
                                osascript -e 'quit app "Postgres"' &>/dev/null
                            elif command -v pg_ctl &>/dev/null; then
                                local pgdata="${PGDATA:-/usr/local/var/postgres}"
                                if ! _svc_err=$(pg_ctl -D "$pgdata" stop 2>&1); then
                                    log_debug "pg_ctl stop: $_svc_err"
                                fi
                            fi
                        fi
                    fi
                fi
            else
                # Remote: use full connection URL with SSL
                # Decode any URL-encoded pipes back
                local conn_url="${full_url//%7C/|}"

                # Add sslmode=require if not already present (required by Neon, Supabase, etc.)
                if [[ "$conn_url" != *"sslmode="* ]]; then
                    if [[ "$conn_url" == *"?"* ]]; then
                        conn_url="${conn_url}&sslmode=require"
                    else
                        conn_url="${conn_url}?sslmode=require"
                    fi
                fi

                # Use timeout for remote connections (30 seconds)
                echo "  ☁️  Connecting to remote: $host..."
                if command -v timeout &>/dev/null; then
                    timeout 120 pg_dump "$conn_url" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                    pg_exit_code=${PIPESTATUS[0]}
                elif command -v gtimeout &>/dev/null; then
                    gtimeout 120 pg_dump "$conn_url" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                    pg_exit_code=${PIPESTATUS[0]}
                else
                    # No timeout available, run directly
                    pg_dump "$conn_url" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                    pg_exit_code=${PIPESTATUS[0]}
                fi
            fi

            if [[ $pg_exit_code -eq 0 ]]; then
                # Verify backup
                if _db_err=$(gunzip -t "$backup_file" 2>&1) && [[ -s "$backup_file" ]]; then
                    if [[ "$is_local" == "true" ]]; then
                        log_info "PostgreSQL backup succeeded: $database"
                        echo "✅ PostgreSQL: $database"
                    else
                        log_info "PostgreSQL backup succeeded: $database (remote)"
                        echo "✅ PostgreSQL: $database (remote)"
                    fi
                else
                    log_debug "PostgreSQL backup verification failed for $database: $_db_err"
                    echo "❌ PostgreSQL: $database (verification failed)"
                    rm -f "$backup_file"
                    return 1
                fi
            else
                rm -f "$backup_file"
                if [[ $pg_exit_code -eq 124 ]]; then
                    log_warn "PostgreSQL dump timed out: $database"
                    echo "❌ PostgreSQL: $database (timeout - remote server too slow)"
                    return 1
                elif [[ "$is_local" == "true" ]]; then
                    # Check if this is a "database doesn't exist on this machine" scenario
                    # This happens when working on a different computer than where the DB was created
                    if pg_isready -h "$host" -p "$port" &>/dev/null; then
                        # Server is running but database doesn't exist
                        echo "⊘ PostgreSQL: $database (not on this machine - using cloud backup)"
                        return 0  # Not a failure, just skip
                    elif [[ "$we_started_postgres" == "true" ]]; then
                        # We started it but DB doesn't exist
                        echo "⊘ PostgreSQL: $database (not on this machine - using cloud backup)"
                        return 0
                    else
                        # Server not running and couldn't start
                        echo "⊘ PostgreSQL: $database (server not available - using cloud backup)"
                        return 0
                    fi
                else
                    echo "❌ PostgreSQL: $database (pg_dump failed with code $pg_exit_code)"
                    return 1
                fi
            fi
            ;;

        mysql)
            # MySQL: Use mysqldump with verification
            IFS='|' read -r host port database user is_local password full_url <<< "$rest"

            # Try credential store if password is empty
            if [[ -z "$password" ]]; then
                local cred_password
                cred_password="$(_get_db_credential "mysql" "$database")" && password="$cred_password"
            fi

            # Check if remote databases should be backed up
            if [[ "$is_local" != "true" ]]; then
                if [[ "${BACKUP_REMOTE_DATABASES:-false}" != "true" ]]; then
                    echo "⊘ MySQL: $database (remote - skipped, set BACKUP_REMOTE_DATABASES=true to enable)"
                    return 0
                fi
            fi

            if ! command -v mysqldump &>/dev/null; then
                echo "⚠ MySQL: mysqldump not found - skipping $database"
                return 1
            fi

            local backup_file="$backup_dir/databases/mysql_${database}_${timestamp}_$$.sql.gz"
            mkdir -p "$backup_dir/databases"

            # Capture exit code properly
            local mysql_exit_code

            if [[ "$is_local" == "true" ]]; then
                # Local: no password needed if using socket auth
                local we_started_mysql=false

                # First attempt - try direct dump
                mysqldump -h "$host" -P "$port" -u "$user" "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                mysql_exit_code=${PIPESTATUS[0]}

                # If failed, try to start MySQL temporarily
                if [[ $mysql_exit_code -ne 0 ]] && [[ "${AUTO_START_LOCAL_DB:-true}" == "true" ]]; then
                    echo "  ⚠ MySQL not running, attempting to start..."

                    # Detect MySQL installation and try to start
                    if command -v brew &>/dev/null && brew services list 2>/dev/null | grep -q "mysql"; then
                        # Homebrew MySQL
                        local mysql_service=$(brew services list 2>/dev/null | grep -E "^mysql" | head -1 | awk '{print $1}')
                        if [[ -n "$mysql_service" ]]; then
                            echo "  🔄 Starting MySQL via Homebrew..."
                            if ! _svc_err=$(brew services start "$mysql_service" 2>&1); then
                                log_debug "brew services start $mysql_service: $_svc_err"
                            fi
                            sleep 3
                            we_started_mysql=true
                        fi
                    elif [[ -f "/usr/local/mysql/support-files/mysql.server" ]]; then
                        # Official MySQL package
                        echo "  🔄 Starting MySQL via mysql.server..."
                        if ! _svc_err=$(sudo /usr/local/mysql/support-files/mysql.server start 2>&1); then
                            log_debug "mysql.server start: $_svc_err"
                        fi
                        sleep 3
                        we_started_mysql=true
                    fi

                    # Retry dump if we started MySQL
                    if [[ "$we_started_mysql" == "true" ]]; then
                        # Wait for MySQL to be ready (up to 10 seconds)
                        local wait_count=0
                        while ! mysqladmin ping -h "$host" -P "$port" &>/dev/null && [[ $wait_count -lt 10 ]]; do
                            sleep 1
                            wait_count=$((wait_count + 1))
                        done

                        if mysqladmin ping -h "$host" -P "$port" &>/dev/null; then
                            echo "  ✓ MySQL started, dumping..."
                            mysqldump -h "$host" -P "$port" -u "$user" "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                            mysql_exit_code=${PIPESTATUS[0]}
                        else
                            echo "  ⚠ MySQL failed to start in time"
                        fi

                        # Stop MySQL if we started it
                        if [[ "${STOP_DB_AFTER_BACKUP:-true}" == "true" ]]; then
                            echo "  🔄 Stopping MySQL (restoring original state)..."
                            if command -v brew &>/dev/null && brew services list 2>/dev/null | grep -q "mysql"; then
                                local mysql_service=$(brew services list 2>/dev/null | grep -E "^mysql" | head -1 | awk '{print $1}')
                                if ! _svc_err=$(brew services stop "$mysql_service" 2>&1); then
                                    log_debug "brew services stop $mysql_service: $_svc_err"
                                fi
                            elif [[ -f "/usr/local/mysql/support-files/mysql.server" ]]; then
                                if ! _svc_err=$(sudo /usr/local/mysql/support-files/mysql.server stop 2>&1); then
                                    log_debug "mysql.server stop: $_svc_err"
                                fi
                            fi
                        fi
                    fi
                fi
            else
                # Remote: use password and SSL
                # Decode any URL-encoded pipes back
                local safe_password="${password//%7C/|}"

                echo "  ☁️  Connecting to remote: $host..."
                # Security: Use MYSQL_PWD env var instead of command-line password (not visible in ps)
                if command -v timeout &>/dev/null; then
                    MYSQL_PWD="$safe_password" timeout 120 mysqldump -h "$host" -P "$port" -u "$user" --ssl-mode=REQUIRED "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                    mysql_exit_code=${PIPESTATUS[0]}
                elif command -v gtimeout &>/dev/null; then
                    MYSQL_PWD="$safe_password" gtimeout 120 mysqldump -h "$host" -P "$port" -u "$user" --ssl-mode=REQUIRED "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                    mysql_exit_code=${PIPESTATUS[0]}
                else
                    MYSQL_PWD="$safe_password" mysqldump -h "$host" -P "$port" -u "$user" --ssl-mode=REQUIRED "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                    mysql_exit_code=${PIPESTATUS[0]}
                fi
            fi

            if [[ $mysql_exit_code -eq 0 ]]; then
                # Verify backup
                if _db_err=$(gunzip -t "$backup_file" 2>&1) && [[ -s "$backup_file" ]]; then
                    if [[ "$is_local" == "true" ]]; then
                        log_info "MySQL backup succeeded: $database"
                        echo "✅ MySQL: $database"
                    else
                        log_info "MySQL backup succeeded: $database (remote)"
                        echo "✅ MySQL: $database (remote)"
                    fi
                else
                    log_debug "MySQL backup verification failed for $database: $_db_err"
                    echo "❌ MySQL: $database (verification failed)"
                    rm -f "$backup_file"
                    return 1
                fi
            else
                rm -f "$backup_file"
                if [[ $mysql_exit_code -eq 124 ]]; then
                    log_warn "MySQL dump timed out: $database"
                    echo "❌ MySQL: $database (timeout - remote server too slow)"
                    return 1
                elif [[ "$is_local" == "true" ]]; then
                    # Check if this is a "database doesn't exist on this machine" scenario
                    if mysqladmin ping -h "$host" -P "$port" &>/dev/null 2>&1; then
                        echo "⊘ MySQL: $database (not on this machine - using cloud backup)"
                        return 0
                    elif [[ "$we_started_mysql" == "true" ]]; then
                        echo "⊘ MySQL: $database (not on this machine - using cloud backup)"
                        return 0
                    else
                        echo "⊘ MySQL: $database (server not available - using cloud backup)"
                        return 0
                    fi
                else
                    echo "❌ MySQL: $database (mysqldump failed with code $mysql_exit_code)"
                    return 1
                fi
            fi
            ;;

        mongodb)
            # MongoDB: Use mongodump with verification
            IFS='|' read -r host port database user is_local password full_url <<< "$rest"

            # Try credential store if password is empty
            if [[ -z "$password" ]]; then
                local cred_password
                cred_password="$(_get_db_credential "mongodb" "$database")" && password="$cred_password"
            fi

            # Check if remote databases should be backed up
            if [[ "$is_local" != "true" ]]; then
                if [[ "${BACKUP_REMOTE_DATABASES:-false}" != "true" ]]; then
                    echo "⊘ MongoDB: $database (remote - skipped, set BACKUP_REMOTE_DATABASES=true to enable)"
                    return 0
                fi
            fi

            if ! command -v mongodump &>/dev/null; then
                echo "⚠ MongoDB: mongodump not found - skipping $database"
                return 1
            fi

            local backup_file="$backup_dir/databases/mongodb_${database}_${timestamp}_$$.tar.gz"
            mkdir -p "$backup_dir/databases"
            local temp_dir
            temp_dir=$(mktemp -d) || {
                echo "❌ MongoDB: $database (temp dir failed)"
                return 1
            }

            # Capture exit code
            local mongo_exit_code

            if [[ "$is_local" == "true" ]]; then
                # Local: simple connection
                _db_err=$(mongodump --host "$host" --port "$port" --db "$database" --out "$temp_dir" 2>&1)
                mongo_exit_code=$?
                if [[ $mongo_exit_code -ne 0 ]]; then
                    log_debug "mongodump local failed for $database: $_db_err"
                fi
            else
                # Remote: use full connection URI with SSL
                # Decode any URL-encoded pipes back
                local conn_url="${full_url//%7C/|}"

                echo "  ☁️  Connecting to remote: $host..."
                if command -v timeout &>/dev/null; then
                    _db_err=$(timeout 120 mongodump --uri="$conn_url" --out "$temp_dir" 2>&1)
                    mongo_exit_code=$?
                elif command -v gtimeout &>/dev/null; then
                    _db_err=$(gtimeout 120 mongodump --uri="$conn_url" --out "$temp_dir" 2>&1)
                    mongo_exit_code=$?
                else
                    _db_err=$(mongodump --uri="$conn_url" --out "$temp_dir" 2>&1)
                    mongo_exit_code=$?
                fi
                if [[ $mongo_exit_code -ne 0 ]]; then
                    log_debug "mongodump remote failed for $database: $_db_err"
                fi
            fi

            if [[ $mongo_exit_code -eq 0 ]]; then
                if _db_err=$(tar -czf "$backup_file" -C "$temp_dir" . 2>&1); then
                    # Verify backup
                    if _db_err=$(tar -tzf "$backup_file" 2>&1) && [[ -s "$backup_file" ]]; then
                        if [[ "$is_local" == "true" ]]; then
                            log_info "MongoDB backup succeeded: $database"
                            echo "✅ MongoDB: $database"
                        else
                            log_info "MongoDB backup succeeded: $database (remote)"
                            echo "✅ MongoDB: $database (remote)"
                        fi
                        rm -rf "$temp_dir"
                    else
                        log_debug "MongoDB backup verification failed for $database: $_db_err"
                        echo "❌ MongoDB: $database (verification failed)"
                        rm -rf "$temp_dir" "$backup_file"
                        return 1
                    fi
                else
                    log_debug "MongoDB tar compression failed for $database: $_db_err"
                    echo "❌ MongoDB: $database (compression failed)"
                    rm -rf "$temp_dir"
                    return 1
                fi
            else
                rm -rf "$temp_dir"
                if [[ $mongo_exit_code -eq 124 ]]; then
                    log_warn "MongoDB dump timed out: $database"
                    echo "❌ MongoDB: $database (timeout - remote server too slow)"
                else
                    log_warn "mongodump failed for $database with code $mongo_exit_code"
                    echo "❌ MongoDB: $database (mongodump failed with code $mongo_exit_code)"
                fi
                return 1
            fi
            ;;

        docker)
            # Docker database: Use docker exec to dump from container
            IFS='|' read -r container_name db_type database user password <<< "$rest"

            # Check if Docker backup is enabled
            if [[ "${BACKUP_DOCKER_DATABASES:-true}" != "true" ]]; then
                echo "⊘ Docker/$db_type: $database (disabled)"
                return 0
            fi

            # Check if Docker is available
            if ! command -v docker &>/dev/null; then
                echo "⚠ Docker: docker command not found - skipping $database"
                return 1
            fi

            # Start Docker if needed
            if ! is_docker_running; then
                if [[ "${AUTO_START_DOCKER:-true}" == "true" ]]; then
                    start_docker || {
                        echo "⊘ Docker/$db_type: $database (Docker not available)"
                        return 0
                    }
                else
                    echo "⊘ Docker/$db_type: $database (Docker not running)"
                    return 0
                fi
            fi

            # Check if container is running
            if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
                # Try to start the container
                echo "  🐳 Starting container: $container_name..."
                if ! _docker_err=$(docker start "$container_name" 2>&1); then
                    log_debug "docker start $container_name: $_docker_err"
                fi
                sleep 3

                if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
                    echo "⊘ Docker/$db_type: $database (container $container_name not available)"
                    return 0
                fi
            fi

            local backup_file=""
            local docker_exit_code=0

            case "$db_type" in
                postgresql)
                    backup_file="$backup_dir/databases/docker_postgres_${database}_${timestamp}_$$.sql.gz"
                    mkdir -p "$backup_dir/databases"

                    echo "  🐳 Dumping from container: $container_name..."
                    docker exec "$container_name" pg_dump -U "$user" "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                    docker_exit_code=${PIPESTATUS[0]}
                    ;;

                mysql)
                    backup_file="$backup_dir/databases/docker_mysql_${database}_${timestamp}_$$.sql.gz"
                    mkdir -p "$backup_dir/databases"

                    echo "  🐳 Dumping from container: $container_name..."
                    # Security: Use environment variable for password instead of command line
                    if [[ -n "$password" ]]; then
                        docker exec -e MYSQL_PWD="$password" "$container_name" mysqldump -u "$user" "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                    else
                        docker exec "$container_name" mysqldump -u "$user" "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$backup_file"
                    fi
                    docker_exit_code=${PIPESTATUS[0]}
                    ;;

                mongodb)
                    backup_file="$backup_dir/databases/docker_mongo_${database}_${timestamp}_$$.tar.gz"
                    mkdir -p "$backup_dir/databases"
                    local temp_dir
                    temp_dir=$(mktemp -d)

                    echo "  🐳 Dumping from container: $container_name..."
                    docker exec "$container_name" mongodump --db "$database" --archive 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" > "$temp_dir/dump.archive"
                    docker_exit_code=$?

                    if [[ $docker_exit_code -eq 0 ]]; then
                        tar -czf "$backup_file" -C "$temp_dir" . 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"
                        docker_exit_code=$?
                    fi
                    rm -rf "$temp_dir"
                    ;;

                *)
                    echo "⚠ Docker: Unknown database type $db_type"
                    return 1
                    ;;
            esac

            if [[ $docker_exit_code -eq 0 ]]; then
                # Verify backup
                if _db_err=$(gunzip -t "$backup_file" 2>&1) || _db_err=$(tar -tzf "$backup_file" 2>&1); then
                    if [[ -s "$backup_file" ]]; then
                        log_info "Docker/$db_type backup succeeded: $database (from $container_name)"
                        echo "✅ Docker/$db_type: $database (from $container_name)"
                    else
                        log_debug "Docker/$db_type backup empty for $database"
                        echo "❌ Docker/$db_type: $database (empty backup)"
                        rm -f "$backup_file"
                        return 1
                    fi
                else
                    log_debug "Docker/$db_type verification failed for $database: $_db_err"
                    echo "❌ Docker/$db_type: $database (verification failed)"
                    rm -f "$backup_file"
                    return 1
                fi
            else
                log_warn "Docker/$db_type dump failed for $database from $container_name"
                echo "❌ Docker/$db_type: $database (dump failed)"
                rm -f "$backup_file"
                return 1
            fi
            ;;
    esac

    return 0
}

# Backup all detected databases
# Args:
#   $1 - Project directory (default: current directory)
#   $2 - Backup directory (default: ./backups)
# Returns: Number of failed backups
backup_detected_databases() {
    local project_dir="${1:-.}"
    local backup_dir="${2:-./backups}"
    local failed_count=0

    # Detect all databases
    local databases
    databases=$(detect_databases "$project_dir")

    if [[ -z "$databases" ]]; then
        echo "ℹ No databases detected"
        return 0
    fi

    echo ""
    echo "📦 Backing up databases..."

    # Backup each database
    while IFS= read -r db_info; do
        if ! backup_single_database "$db_info" "$backup_dir"; then
            failed_count=$((failed_count + 1))
        fi
    done <<< "$databases"

    # NOTE: Docker cleanup is handled by calling stop_docker() AFTER all project backups complete
    # This function does NOT stop Docker - the main backup script should call stop_docker() at the end

    return $failed_count
}

# Display detected databases in human-readable format
# Args:
#   $1 - Project directory (default: current directory)
show_detected_databases() {
    local project_dir="${1:-.}"

    local databases
    databases=$(detect_databases "$project_dir")

    if [[ -z "$databases" ]]; then
        echo "No databases detected"
        return
    fi

    echo ""
    echo "Detected databases:"
    echo ""

    while IFS= read -r db_info; do
        IFS='|' read -r db_type rest <<< "$db_info"

        case "$db_type" in
            sqlite)
                local db_path="$rest"
                local db_name=$(basename "$db_path")
                echo "  • SQLite: $db_name"
                echo "    Path: $db_path"
                echo "    Type: Local file"
                ;;
            postgresql)
                IFS='|' read -r host port database user is_local password full_url <<< "$rest"
                echo "  • PostgreSQL: $database"
                echo "    Host: $host:$port"
                if [[ "$is_local" == "true" ]]; then
                    echo "    Type: Local server ✅"
                else
                    if [[ "${BACKUP_REMOTE_DATABASES:-false}" == "true" ]]; then
                        echo "    Type: Remote server ✅ (backup enabled)"
                    else
                        echo "    Type: Remote server ⊘ (set BACKUP_REMOTE_DATABASES=true to enable)"
                    fi
                fi
                ;;
            mysql)
                IFS='|' read -r host port database user is_local password full_url <<< "$rest"
                echo "  • MySQL: $database"
                echo "    Host: $host:$port"
                if [[ "$is_local" == "true" ]]; then
                    echo "    Type: Local server ✅"
                else
                    if [[ "${BACKUP_REMOTE_DATABASES:-false}" == "true" ]]; then
                        echo "    Type: Remote server ✅ (backup enabled)"
                    else
                        echo "    Type: Remote server ⊘ (set BACKUP_REMOTE_DATABASES=true to enable)"
                    fi
                fi
                ;;
            mongodb)
                IFS='|' read -r host port database user is_local password full_url <<< "$rest"
                echo "  • MongoDB: $database"
                echo "    Host: $host:$port"
                if [[ "$is_local" == "true" ]]; then
                    echo "    Type: Local server ✅"
                else
                    if [[ "${BACKUP_REMOTE_DATABASES:-false}" == "true" ]]; then
                        echo "    Type: Remote server ✅ (backup enabled)"
                    else
                        echo "    Type: Remote server ⊘ (set BACKUP_REMOTE_DATABASES=true to enable)"
                    fi
                fi
                ;;
        esac
        echo ""
    done
}
