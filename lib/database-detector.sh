#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Universal Database Detector
# ==============================================================================
# Version: 2.2.0
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
# Returns: Connection details in format "type|host|port|database|user|is_local"
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
                        local host="${BASH_REMATCH[5]}"
                        local port="${BASH_REMATCH[7]:-5432}"
                        local database="${BASH_REMATCH[8]}"

                        # Determine if local
                        local is_local="false"
                        if [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]]; then
                            is_local="true"
                        fi

                        databases+=("postgresql|$host|$port|$database|$user|$is_local")
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
# Returns: Connection details in format "type|host|port|database|user|is_local"
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
                        local host="${BASH_REMATCH[4]}"
                        local port="${BASH_REMATCH[6]:-3306}"
                        local database="${BASH_REMATCH[7]}"

                        # Determine if local
                        local is_local="false"
                        if [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]]; then
                            is_local="true"
                        fi

                        databases+=("mysql|$host|$port|$database|$user|$is_local")
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
            done < "$env_file"

            # If individual vars found, construct connection
            if [[ -n "${MYSQL_DATABASE:-}" ]]; then
                local host="${MYSQL_HOST:-localhost}"
                local port="${MYSQL_PORT:-3306}"
                local user="${MYSQL_USER:-root}"
                local is_local="false"
                if [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]]; then
                    is_local="true"
                fi
                databases+=("mysql|$host|$port|$MYSQL_DATABASE|$user|$is_local")
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
# Returns: Connection details in format "type|host|port|database|user|is_local"
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

                    # Parse mongodb://user:pass@host:port/database or mongodb+srv://...
                    # Check for mongodb+srv (always remote)
                    if [[ "$url" == mongodb+srv://* ]]; then
                        # Extract from mongodb+srv://user:pass@host/database
                        if [[ "$url" =~ mongodb\+srv://([^:@]+)(:([^@]+))?@([^:/]+)/([^?]+) ]]; then
                            local user="${BASH_REMATCH[1]}"
                            local host="${BASH_REMATCH[4]}"
                            local port="27017"
                            local database="${BASH_REMATCH[5]}"
                            databases+=("mongodb|$host|$port|$database|$user|false")
                        fi
                    # Regular mongodb://
                    elif [[ "$url" =~ mongodb://([^:@]+)(:([^@]+))?@([^:/]+)(:([0-9]+))?/([^?]+) ]]; then
                        local user="${BASH_REMATCH[1]}"
                        local host="${BASH_REMATCH[4]}"
                        local port="${BASH_REMATCH[6]:-27017}"
                        local database="${BASH_REMATCH[7]}"

                        # Determine if local
                        local is_local="false"
                        if [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0)$ ]]; then
                            is_local="true"
                        fi

                        databases+=("mongodb|$host|$port|$database|$user|$is_local")
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
            # SQLite: Simple file copy
            local db_path="$rest"
            local db_name=$(basename "$db_path")
            local backup_file="$backup_dir/databases/${db_name%.db}_${timestamp}.db.gz"

            mkdir -p "$backup_dir/databases"
            gzip -c "$db_path" > "$backup_file"
            echo "✅ SQLite: $db_name"
            ;;

        postgresql)
            # PostgreSQL: Use pg_dump
            IFS='|' read -r host port database user is_local <<< "$rest"

            if [[ "$is_local" != "true" ]]; then
                echo "⊘ PostgreSQL: $database (remote - skipped)"
                return 0
            fi

            if ! command -v pg_dump &>/dev/null; then
                echo "⚠ PostgreSQL: pg_dump not found - skipping $database"
                return 1
            fi

            local backup_file="$backup_dir/databases/postgres_${database}_${timestamp}.sql.gz"
            mkdir -p "$backup_dir/databases"

            if pg_dump -h "$host" -p "$port" -U "$user" "$database" 2>/dev/null | gzip > "$backup_file"; then
                echo "✅ PostgreSQL: $database"
            else
                echo "❌ PostgreSQL: $database (backup failed)"
                return 1
            fi
            ;;

        mysql)
            # MySQL: Use mysqldump
            IFS='|' read -r host port database user is_local <<< "$rest"

            if [[ "$is_local" != "true" ]]; then
                echo "⊘ MySQL: $database (remote - skipped)"
                return 0
            fi

            if ! command -v mysqldump &>/dev/null; then
                echo "⚠ MySQL: mysqldump not found - skipping $database"
                return 1
            fi

            local backup_file="$backup_dir/databases/mysql_${database}_${timestamp}.sql.gz"
            mkdir -p "$backup_dir/databases"

            if mysqldump -h "$host" -P "$port" -u "$user" "$database" 2>/dev/null | gzip > "$backup_file"; then
                echo "✅ MySQL: $database"
            else
                echo "❌ MySQL: $database (backup failed)"
                return 1
            fi
            ;;

        mongodb)
            # MongoDB: Use mongodump
            IFS='|' read -r host port database user is_local <<< "$rest"

            if [[ "$is_local" != "true" ]]; then
                echo "⊘ MongoDB: $database (remote - skipped)"
                return 0
            fi

            if ! command -v mongodump &>/dev/null; then
                echo "⚠ MongoDB: mongodump not found - skipping $database"
                return 1
            fi

            local backup_file="$backup_dir/databases/mongodb_${database}_${timestamp}.gz"
            mkdir -p "$backup_dir/databases"
            local temp_dir=$(mktemp -d)

            if mongodump --host "$host" --port "$port" --db "$database" --out "$temp_dir" &>/dev/null; then
                tar -czf "$backup_file" -C "$temp_dir" .
                rm -rf "$temp_dir"
                echo "✅ MongoDB: $database"
            else
                rm -rf "$temp_dir"
                echo "❌ MongoDB: $database (backup failed)"
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
            ((failed_count++))
        fi
    done <<< "$databases"

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
                IFS='|' read -r host port database user is_local <<< "$rest"
                echo "  • PostgreSQL: $database"
                echo "    Host: $host:$port"
                if [[ "$is_local" == "true" ]]; then
                    echo "    Type: Local server ✅"
                else
                    echo "    Type: Remote server (will skip)"
                fi
                ;;
            mysql)
                IFS='|' read -r host port database user is_local <<< "$rest"
                echo "  • MySQL: $database"
                echo "    Host: $host:$port"
                if [[ "$is_local" == "true" ]]; then
                    echo "    Type: Local server ✅"
                else
                    echo "    Type: Remote server (will skip)"
                fi
                ;;
            mongodb)
                IFS='|' read -r host port database user is_local <<< "$rest"
                echo "  • MongoDB: $database"
                echo "    Host: $host:$port"
                if [[ "$is_local" == "true" ]]; then
                    echo "    Type: Local server ✅"
                else
                    echo "    Type: Remote server (will skip)"
                fi
                ;;
        esac
        echo ""
    done
}
