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

# Detect PostgreSQL databases from environment variables and running processes
# Returns: Connection details in format "type|host|port|database|user|is_local|password|full_url"
detect_postgresql() {
    local project_dir="${1:-.}"
    local databases=()

    # Check environment files for DATABASE_URL, POSTGRES_URL, etc.
    local env_files=("$project_dir/.env" "$project_dir/.env.local" "$project_dir/.env.development")

    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            # Parse PostgreSQL connection strings
            while IFS= read -r line; do
                if [[ "$line" =~ ^[A-Z_]*DATABASE_URL= ]] || [[ "$line" =~ ^POSTGRES.*URL= ]]; then
                    local url="${line#*=}"
                    # Remove quotes
                    url="${url//\"/}"
                    url="${url//\'/}"

                    # Parse postgres://user:pass@host:port/database
                    if [[ "$url" =~ postgres(ql)?://([^:@]+)(:([^@]+))?@([^:/]+)(:([0-9]+))?/([^?]+) ]]; then
                        local user="${BASH_REMATCH[2]}"
                        local password="${BASH_REMATCH[4]:-}"
                        local host="${BASH_REMATCH[5]}"
                        local port="${BASH_REMATCH[7]:-5432}"
                        local database="${BASH_REMATCH[8]}"

                        # Determine if local
                        local is_local="false"
                        if [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]]; then
                            is_local="true"
                        fi

                        # Store full URL for remote backup (URL-encode pipe chars if present)
                        local safe_url="${url//|/%7C}"
                        local safe_password="${password//|/%7C}"

                        databases+=("postgresql|$host|$port|$database|$user|$is_local|$safe_password|$safe_url")
                    fi
                fi
            done < "$env_file"
        fi
    done

    # Note: We do NOT auto-detect PostgreSQL just because it's running
    # Only detect if explicitly configured in .env files (above)
    # This prevents backing up system/user databases for projects without databases

    # Output results (one per line)
    printf '%s\n' "${databases[@]}" | sort -u
}

# ==============================================================================
# DETECTION: MYSQL
# ==============================================================================

# Detect MySQL/MariaDB databases from environment variables and running processes
# Returns: Connection details in format "type|host|port|database|user|is_local|password|full_url"
detect_mysql() {
    local project_dir="${1:-.}"
    local databases=()

    # Check environment files
    local env_files=("$project_dir/.env" "$project_dir/.env.local" "$project_dir/.env.development")

    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            # Parse MySQL connection strings
            while IFS= read -r line; do
                if [[ "$line" =~ ^[A-Z_]*DATABASE_URL= ]] || [[ "$line" =~ ^MYSQL.*URL= ]]; then
                    local url="${line#*=}"
                    url="${url//\"/}"
                    url="${url//\'/}"

                    # Parse mysql://user:pass@host:port/database
                    if [[ "$url" =~ mysql://([^:@]+)(:([^@]+))?@([^:/]+)(:([0-9]+))?/([^?]+) ]]; then
                        local user="${BASH_REMATCH[1]}"
                        local password="${BASH_REMATCH[3]:-}"
                        local host="${BASH_REMATCH[4]}"
                        local port="${BASH_REMATCH[6]:-3306}"
                        local database="${BASH_REMATCH[7]}"

                        # Determine if local
                        local is_local="false"
                        if [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]]; then
                            is_local="true"
                        fi

                        # Store full URL for remote backup (URL-encode pipe chars if present)
                        local safe_url="${url//|/%7C}"
                        local safe_password="${password//|/%7C}"

                        databases+=("mysql|$host|$port|$database|$user|$is_local|$safe_password|$safe_url")
                    fi
                fi

                # Also check for individual MySQL env vars
                if [[ "$line" =~ ^MYSQL_HOST= ]]; then
                    MYSQL_HOST="${line#*=}"
                fi
                if [[ "$line" =~ ^MYSQL_PORT= ]]; then
                    MYSQL_PORT="${line#*=}"
                fi
                if [[ "$line" =~ ^MYSQL_DATABASE= ]]; then
                    MYSQL_DATABASE="${line#*=}"
                fi
                if [[ "$line" =~ ^MYSQL_USER= ]]; then
                    MYSQL_USER="${line#*=}"
                fi
                if [[ "$line" =~ ^MYSQL_PASSWORD= ]]; then
                    MYSQL_PASSWORD="${line#*=}"
                fi
            done < "$env_file"

            # If individual vars found, construct connection
            if [[ -n "${MYSQL_DATABASE:-}" ]]; then
                local host="${MYSQL_HOST:-localhost}"
                local port="${MYSQL_PORT:-3306}"
                local user="${MYSQL_USER:-root}"
                local password="${MYSQL_PASSWORD:-}"
                local is_local="false"
                if [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]]; then
                    is_local="true"
                fi
                databases+=("mysql|$host|$port|$MYSQL_DATABASE|$user|$is_local|$password|")
            fi
        fi
    done

    # Note: We do NOT auto-detect MySQL just because it's running
    # Only detect if explicitly configured in .env files (above)
    # This prevents backing up system 'mysql' database for projects without databases

    # Output results (one per line)
    printf '%s\n' "${databases[@]}" | sort -u
}

# ==============================================================================
# DETECTION: MONGODB
# ==============================================================================

# Detect MongoDB databases from environment variables and running processes
# Returns: Connection details in format "type|host|port|database|user|is_local|password|full_url"
detect_mongodb() {
    local project_dir="${1:-.}"
    local databases=()

    # Check environment files
    local env_files=("$project_dir/.env" "$project_dir/.env.local" "$project_dir/.env.development")

    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            # Parse MongoDB connection strings
            while IFS= read -r line; do
                if [[ "$line" =~ ^[A-Z_]*DATABASE_URL= ]] || [[ "$line" =~ ^MONGO.*URL= ]]; then
                    local url="${line#*=}"
                    url="${url//\"/}"
                    url="${url//\'/}"

                    # Store full URL for remote backup (URL-encode pipe chars if present)
                    local safe_url="${url//|/%7C}"

                    # Parse mongodb://user:pass@host:port/database or mongodb+srv://...
                    # Check for mongodb+srv (always remote)
                    if [[ "$url" == mongodb+srv://* ]]; then
                        # Extract from mongodb+srv://user:pass@host/database
                        if [[ "$url" =~ mongodb\+srv://([^:@]+)(:([^@]+))?@([^:/]+)/([^?]+) ]]; then
                            local user="${BASH_REMATCH[1]}"
                            local password="${BASH_REMATCH[3]:-}"
                            local host="${BASH_REMATCH[4]}"
                            local port="27017"
                            local database="${BASH_REMATCH[5]}"
                            local safe_password="${password//|/%7C}"
                            databases+=("mongodb|$host|$port|$database|$user|false|$safe_password|$safe_url")
                        fi
                    # Regular mongodb://
                    elif [[ "$url" =~ mongodb://([^:@]+)(:([^@]+))?@([^:/]+)(:([0-9]+))?/([^?]+) ]]; then
                        local user="${BASH_REMATCH[1]}"
                        local password="${BASH_REMATCH[3]:-}"
                        local host="${BASH_REMATCH[4]}"
                        local port="${BASH_REMATCH[6]:-27017}"
                        local database="${BASH_REMATCH[7]}"

                        # Determine if local
                        local is_local="false"
                        if [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]]; then
                            is_local="true"
                        fi

                        local safe_password="${password//|/%7C}"
                        databases+=("mongodb|$host|$port|$database|$user|$is_local|$safe_password|$safe_url")
                    fi
                fi
            done < "$env_file"
        fi
    done

    # Note: We do NOT auto-detect MongoDB just because it's running
    # Only detect if explicitly configured in .env files (above)
    # This prevents backing up system 'admin' database for projects without databases

    # Output results (one per line)
    printf '%s\n' "${databases[@]}" | sort -u
}

# ==============================================================================
# DETECTION: DOCKER DATABASES
# ==============================================================================

# File-based flag to track if we started Docker (persists across multiple backups)
CHECKPOINT_DOCKER_FLAG="/tmp/.checkpoint-started-docker"

# Check if we started Docker (for cleanup decision)
did_we_start_docker() {
    [[ -f "$CHECKPOINT_DOCKER_FLAG" ]]
}

# Detect databases running in Docker containers
# Returns: Connection details in format "docker|container_name|db_type|database|user|password"
detect_docker_databases() {
    local project_dir="${1:-.}"
    local databases=()

    # Check for docker-compose files
    local compose_file=""
    for f in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
        if [[ -f "$project_dir/$f" ]]; then
            compose_file="$project_dir/$f"
            break
        fi
    done

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
    open -a Docker 2>/dev/null || return 1

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

            if sqlite3 "$db_path" ".backup '$temp_db'" 2>/dev/null; then
                if gzip -c "$temp_db" > "$backup_file" 2>/dev/null; then
                    # Verify backup integrity
                    if gunzip -t "$backup_file" 2>/dev/null; then
                        echo "✅ SQLite: $db_name"
                        rm -f "$temp_db"
                    else
                        echo "❌ SQLite: $db_name (verification failed)"
                        rm -f "$temp_db" "$backup_file"
                        return 1
                    fi
                else
                    echo "❌ SQLite: $db_name (compression failed)"
                    rm -f "$temp_db"
                    return 1
                fi
            else
                echo "❌ SQLite: $db_name (backup command failed)"
                rm -f "$temp_db"
                return 1
            fi
            ;;

        postgresql)
            # PostgreSQL: Use pg_dump with verification
            IFS='|' read -r host port database user is_local password full_url <<< "$rest"

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
                pg_dump -h "$host" -p "$port" -U "$user" "$database" 2>/dev/null | gzip > "$backup_file"
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
                            brew services start "$pg_service" &>/dev/null
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
                            pg_ctl -D "$pgdata" start &>/dev/null
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
                            pg_dump -h "$host" -p "$port" -U "$user" "$database" 2>/dev/null | gzip > "$backup_file"
                            pg_exit_code=${PIPESTATUS[0]}
                        else
                            echo "  ⚠ PostgreSQL failed to start in time"
                        fi

                        # Stop PostgreSQL if we started it (to restore original state)
                        if [[ "${STOP_DB_AFTER_BACKUP:-true}" == "true" ]]; then
                            echo "  🔄 Stopping PostgreSQL (restoring original state)..."
                            if command -v brew &>/dev/null && brew services list 2>/dev/null | grep -q "postgresql"; then
                                local pg_service=$(brew services list 2>/dev/null | grep -E "^postgresql" | head -1 | awk '{print $1}')
                                brew services stop "$pg_service" &>/dev/null
                            elif [[ -d "/Applications/Postgres.app" ]]; then
                                osascript -e 'quit app "Postgres"' &>/dev/null
                            elif command -v pg_ctl &>/dev/null; then
                                local pgdata="${PGDATA:-/usr/local/var/postgres}"
                                pg_ctl -D "$pgdata" stop &>/dev/null
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
                    timeout 120 pg_dump "$conn_url" 2>/dev/null | gzip > "$backup_file"
                    pg_exit_code=${PIPESTATUS[0]}
                elif command -v gtimeout &>/dev/null; then
                    gtimeout 120 pg_dump "$conn_url" 2>/dev/null | gzip > "$backup_file"
                    pg_exit_code=${PIPESTATUS[0]}
                else
                    # No timeout available, run directly
                    pg_dump "$conn_url" 2>/dev/null | gzip > "$backup_file"
                    pg_exit_code=${PIPESTATUS[0]}
                fi
            fi

            if [[ $pg_exit_code -eq 0 ]]; then
                # Verify backup
                if gunzip -t "$backup_file" 2>/dev/null && [[ -s "$backup_file" ]]; then
                    if [[ "$is_local" == "true" ]]; then
                        echo "✅ PostgreSQL: $database"
                    else
                        echo "✅ PostgreSQL: $database (remote)"
                    fi
                else
                    echo "❌ PostgreSQL: $database (verification failed)"
                    rm -f "$backup_file"
                    return 1
                fi
            else
                rm -f "$backup_file"
                if [[ $pg_exit_code -eq 124 ]]; then
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
                mysqldump -h "$host" -P "$port" -u "$user" "$database" 2>/dev/null | gzip > "$backup_file"
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
                            brew services start "$mysql_service" &>/dev/null
                            sleep 3
                            we_started_mysql=true
                        fi
                    elif [[ -f "/usr/local/mysql/support-files/mysql.server" ]]; then
                        # Official MySQL package
                        echo "  🔄 Starting MySQL via mysql.server..."
                        sudo /usr/local/mysql/support-files/mysql.server start &>/dev/null
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
                            mysqldump -h "$host" -P "$port" -u "$user" "$database" 2>/dev/null | gzip > "$backup_file"
                            mysql_exit_code=${PIPESTATUS[0]}
                        else
                            echo "  ⚠ MySQL failed to start in time"
                        fi

                        # Stop MySQL if we started it
                        if [[ "${STOP_DB_AFTER_BACKUP:-true}" == "true" ]]; then
                            echo "  🔄 Stopping MySQL (restoring original state)..."
                            if command -v brew &>/dev/null && brew services list 2>/dev/null | grep -q "mysql"; then
                                local mysql_service=$(brew services list 2>/dev/null | grep -E "^mysql" | head -1 | awk '{print $1}')
                                brew services stop "$mysql_service" &>/dev/null
                            elif [[ -f "/usr/local/mysql/support-files/mysql.server" ]]; then
                                sudo /usr/local/mysql/support-files/mysql.server stop &>/dev/null
                            fi
                        fi
                    fi
                fi
            else
                # Remote: use password and SSL
                # Decode any URL-encoded pipes back
                local safe_password="${password//%7C/|}"

                echo "  ☁️  Connecting to remote: $host..."
                if command -v timeout &>/dev/null; then
                    timeout 120 mysqldump -h "$host" -P "$port" -u "$user" -p"$safe_password" --ssl-mode=REQUIRED "$database" 2>/dev/null | gzip > "$backup_file"
                    mysql_exit_code=${PIPESTATUS[0]}
                elif command -v gtimeout &>/dev/null; then
                    gtimeout 120 mysqldump -h "$host" -P "$port" -u "$user" -p"$safe_password" --ssl-mode=REQUIRED "$database" 2>/dev/null | gzip > "$backup_file"
                    mysql_exit_code=${PIPESTATUS[0]}
                else
                    mysqldump -h "$host" -P "$port" -u "$user" -p"$safe_password" --ssl-mode=REQUIRED "$database" 2>/dev/null | gzip > "$backup_file"
                    mysql_exit_code=${PIPESTATUS[0]}
                fi
            fi

            if [[ $mysql_exit_code -eq 0 ]]; then
                # Verify backup
                if gunzip -t "$backup_file" 2>/dev/null && [[ -s "$backup_file" ]]; then
                    if [[ "$is_local" == "true" ]]; then
                        echo "✅ MySQL: $database"
                    else
                        echo "✅ MySQL: $database (remote)"
                    fi
                else
                    echo "❌ MySQL: $database (verification failed)"
                    rm -f "$backup_file"
                    return 1
                fi
            else
                rm -f "$backup_file"
                if [[ $mysql_exit_code -eq 124 ]]; then
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
                mongodump --host "$host" --port "$port" --db "$database" --out "$temp_dir" &>/dev/null
                mongo_exit_code=$?
            else
                # Remote: use full connection URI with SSL
                # Decode any URL-encoded pipes back
                local conn_url="${full_url//%7C/|}"

                echo "  ☁️  Connecting to remote: $host..."
                if command -v timeout &>/dev/null; then
                    timeout 120 mongodump --uri="$conn_url" --out "$temp_dir" &>/dev/null
                    mongo_exit_code=$?
                elif command -v gtimeout &>/dev/null; then
                    gtimeout 120 mongodump --uri="$conn_url" --out "$temp_dir" &>/dev/null
                    mongo_exit_code=$?
                else
                    mongodump --uri="$conn_url" --out "$temp_dir" &>/dev/null
                    mongo_exit_code=$?
                fi
            fi

            if [[ $mongo_exit_code -eq 0 ]]; then
                if tar -czf "$backup_file" -C "$temp_dir" . 2>/dev/null; then
                    # Verify backup
                    if tar -tzf "$backup_file" &>/dev/null && [[ -s "$backup_file" ]]; then
                        if [[ "$is_local" == "true" ]]; then
                            echo "✅ MongoDB: $database"
                        else
                            echo "✅ MongoDB: $database (remote)"
                        fi
                        rm -rf "$temp_dir"
                    else
                        echo "❌ MongoDB: $database (verification failed)"
                        rm -rf "$temp_dir" "$backup_file"
                        return 1
                    fi
                else
                    echo "❌ MongoDB: $database (compression failed)"
                    rm -rf "$temp_dir"
                    return 1
                fi
            else
                rm -rf "$temp_dir"
                if [[ $mongo_exit_code -eq 124 ]]; then
                    echo "❌ MongoDB: $database (timeout - remote server too slow)"
                else
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
                docker start "$container_name" &>/dev/null
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
                    docker exec "$container_name" pg_dump -U "$user" "$database" 2>/dev/null | gzip > "$backup_file"
                    docker_exit_code=${PIPESTATUS[0]}
                    ;;

                mysql)
                    backup_file="$backup_dir/databases/docker_mysql_${database}_${timestamp}_$$.sql.gz"
                    mkdir -p "$backup_dir/databases"

                    echo "  🐳 Dumping from container: $container_name..."
                    if [[ -n "$password" ]]; then
                        docker exec "$container_name" mysqldump -u "$user" -p"$password" "$database" 2>/dev/null | gzip > "$backup_file"
                    else
                        docker exec "$container_name" mysqldump -u "$user" "$database" 2>/dev/null | gzip > "$backup_file"
                    fi
                    docker_exit_code=${PIPESTATUS[0]}
                    ;;

                mongodb)
                    backup_file="$backup_dir/databases/docker_mongo_${database}_${timestamp}_$$.tar.gz"
                    mkdir -p "$backup_dir/databases"
                    local temp_dir
                    temp_dir=$(mktemp -d)

                    echo "  🐳 Dumping from container: $container_name..."
                    docker exec "$container_name" mongodump --db "$database" --archive 2>/dev/null > "$temp_dir/dump.archive"
                    docker_exit_code=$?

                    if [[ $docker_exit_code -eq 0 ]]; then
                        tar -czf "$backup_file" -C "$temp_dir" . 2>/dev/null
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
                if gunzip -t "$backup_file" 2>/dev/null || tar -tzf "$backup_file" &>/dev/null; then
                    if [[ -s "$backup_file" ]]; then
                        echo "✅ Docker/$db_type: $database (from $container_name)"
                    else
                        echo "❌ Docker/$db_type: $database (empty backup)"
                        rm -f "$backup_file"
                        return 1
                    fi
                else
                    echo "❌ Docker/$db_type: $database (verification failed)"
                    rm -f "$backup_file"
                    return 1
                fi
            else
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
