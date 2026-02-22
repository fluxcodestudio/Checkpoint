#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Restore Operations
# Safety backups, integrity verification, and database/file restore
# ==============================================================================
# @requires: core/output (for color functions, backup_log),
#            ui/time-size-utils (for format_bytes)
# @provides: create_safety_backup, verify_sqlite_integrity,
#            verify_compressed_backup, restore_database_from_backup,
#            restore_file_from_backup,
#            _get_backup_db_type, _get_backup_db_name, _read_project_env
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_RESTORE:-}" ] && return || readonly _CHECKPOINT_RESTORE=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Source encryption library if available (for decrypting .age backups)
if [ -f "$_CHECKPOINT_LIB_DIR/features/encryption.sh" ]; then
    source "$_CHECKPOINT_LIB_DIR/features/encryption.sh"
fi

# Set logging context for this module
log_set_context "restore"

# ==============================================================================
# BACKUP TYPE DETECTION
# ==============================================================================

# Detect database type from backup filename
# mysql_dbname_... → "mysql", postgres_dbname_... → "postgres",
# docker_mysql_... → "mysql", docker_postgres_... → "postgres",
# mongodb_... → "mongodb", docker_mongo_... → "mongodb",
# anything.db.gz → "sqlite"
_get_backup_db_type() {
    local filename
    filename=$(basename "$1")
    # Strip .age suffix for detection
    filename="${filename%.age}"

    case "$filename" in
        mysql_*|docker_mysql_*)     echo "mysql" ;;
        postgres_*|docker_postgres_*) echo "postgres" ;;
        mongodb_*|docker_mongo_*)   echo "mongodb" ;;
        *)
            if [[ "$filename" == *.db.gz ]]; then
                echo "sqlite"
            elif [[ "$filename" == *.sql.gz ]]; then
                # sql.gz without known prefix — guess from content later
                echo "sql_unknown"
            else
                echo "unknown"
            fi
            ;;
    esac
}

# Extract database name from backup filename
# mysql_bemusic_20260222_010100_1234.sql.gz → "bemusic"
# docker_postgres_appdb_20260222_010100_1234.sql.gz → "appdb"
# mongodb_mydb_20260222_010100_1234.tar.gz → "mydb"
_get_backup_db_name() {
    local filename
    filename=$(basename "$1")
    # Strip .age suffix
    filename="${filename%.age}"

    local db_type
    db_type=$(_get_backup_db_type "$1")

    case "$db_type" in
        mysql|postgres|mongodb)
            # Strip prefix: mysql_, postgres_, mongodb_
            local without_prefix="${filename#mysql_}"
            without_prefix="${without_prefix#postgres_}"
            without_prefix="${without_prefix#mongodb_}"
            without_prefix="${without_prefix#docker_mysql_}"
            without_prefix="${without_prefix#docker_postgres_}"
            without_prefix="${without_prefix#docker_mongo_}"
            # Re-check if docker prefix still present (filename started with docker_)
            if [[ "$filename" == docker_* ]]; then
                without_prefix="${filename#docker_mysql_}"
                without_prefix="${without_prefix#docker_postgres_}"
                without_prefix="${without_prefix#docker_mongo_}"
            fi
            # DB name is everything before _YYYYMMDD_ timestamp pattern
            echo "$without_prefix" | sed -E 's/_[0-9]{8}_[0-9]{6}_[0-9]+\.(sql|tar)\.gz$//'
            ;;
        sqlite)
            # somename_20260222_010100_1234.db.gz → somename
            echo "$filename" | sed -E 's/_[0-9]{8}_[0-9]{6}_[0-9]+\.db\.gz$//'
            ;;
        *)
            echo "$filename"
            ;;
    esac
}

# Format a human-readable type label for display
_get_backup_type_label() {
    local db_type
    db_type=$(_get_backup_db_type "$1")
    case "$db_type" in
        mysql)    echo "MySQL" ;;
        postgres) echo "PostgreSQL" ;;
        mongodb)  echo "MongoDB" ;;
        sqlite)   echo "SQLite" ;;
        *)        echo "Database" ;;
    esac
}

# Read connection info from project .env file (Laravel convention)
# Sets global variables: _RESTORE_DB_HOST, _RESTORE_DB_PORT, _RESTORE_DB_USER,
# _RESTORE_DB_PASS, _RESTORE_DB_NAME
_read_project_env() {
    local project_dir="$1"
    local db_type="$2"

    _RESTORE_DB_HOST=""
    _RESTORE_DB_PORT=""
    _RESTORE_DB_USER=""
    _RESTORE_DB_PASS=""
    _RESTORE_DB_NAME=""

    local env_file=""
    for candidate in "$project_dir/.env" "$project_dir/.env.local" "$project_dir/.env.production"; do
        if [ -f "$candidate" ]; then
            env_file="$candidate"
            break
        fi
    done

    [ -z "$env_file" ] && return 1

    # Read standard Laravel/framework DB_ variables
    _RESTORE_DB_HOST=$(grep -E '^DB_HOST=' "$env_file" 2>/dev/null | head -1 | sed 's/^DB_HOST=//' | sed "s/^['\"]//;s/['\"]$//" || true)
    _RESTORE_DB_PORT=$(grep -E '^DB_PORT=' "$env_file" 2>/dev/null | head -1 | sed 's/^DB_PORT=//' | sed "s/^['\"]//;s/['\"]$//" || true)
    _RESTORE_DB_USER=$(grep -E '^DB_USERNAME=' "$env_file" 2>/dev/null | head -1 | sed 's/^DB_USERNAME=//' | sed "s/^['\"]//;s/['\"]$//" || true)
    _RESTORE_DB_PASS=$(grep -E '^DB_PASSWORD=' "$env_file" 2>/dev/null | head -1 | sed 's/^DB_PASSWORD=//' | sed "s/^['\"]//;s/['\"]$//" || true)
    _RESTORE_DB_NAME=$(grep -E '^DB_DATABASE=' "$env_file" 2>/dev/null | head -1 | sed 's/^DB_DATABASE=//' | sed "s/^['\"]//;s/['\"]$//" || true)

    # Fall back to type-specific variables if DB_ ones are empty
    if [ -z "$_RESTORE_DB_HOST" ]; then
        case "$db_type" in
            mysql)
                _RESTORE_DB_HOST=$(grep -E '^MYSQL_HOST=' "$env_file" 2>/dev/null | head -1 | sed 's/^MYSQL_HOST=//' | sed "s/^['\"]//;s/['\"]$//" || true)
                ;;
            postgres)
                _RESTORE_DB_HOST=$(grep -E '^(POSTGRES_HOST|PG_HOST)=' "$env_file" 2>/dev/null | head -1 | sed -E 's/^(POSTGRES_HOST|PG_HOST)=//' | sed "s/^['\"]//;s/['\"]$//" || true)
                ;;
            mongodb)
                _RESTORE_DB_HOST=$(grep -E '^MONGO_HOST=' "$env_file" 2>/dev/null | head -1 | sed 's/^MONGO_HOST=//' | sed "s/^['\"]//;s/['\"]$//" || true)
                ;;
        esac
    fi

    # Set defaults
    [ -z "$_RESTORE_DB_HOST" ] && _RESTORE_DB_HOST="127.0.0.1"
    if [ -z "$_RESTORE_DB_PORT" ]; then
        case "$db_type" in
            mysql)    _RESTORE_DB_PORT="3306" ;;
            postgres) _RESTORE_DB_PORT="5432" ;;
            mongodb)  _RESTORE_DB_PORT="27017" ;;
        esac
    fi
    if [ -z "$_RESTORE_DB_USER" ]; then
        case "$db_type" in
            mysql)    _RESTORE_DB_USER="root" ;;
            postgres) _RESTORE_DB_USER="postgres" ;;
        esac
    fi

    return 0
}

# ==============================================================================
# RESTORE OPERATIONS
# ==============================================================================

# Create safety backup before restore
create_safety_backup() {
    local file_path="$1"
    local suffix="${2:-pre-restore}"

    [ ! -f "$file_path" ] && return 0

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local safety_backup="${file_path}.${suffix}-${timestamp}"

    local _cp_err
    if _cp_err=$(cp "$file_path" "$safety_backup" 2>&1); then
        echo "$safety_backup"
        return 0
    else
        log_error "Safety backup cp failed for $file_path: $_cp_err"
        return 1
    fi
}

# Verify SQLite database integrity
verify_sqlite_integrity() {
    local db_path="$1"

    [ ! -f "$db_path" ] && return 1

    # Check if it's a SQLite database
    if ! file "$db_path" 2>/dev/null | grep -q "SQLite"; then
        return 1
    fi

    # Run integrity check
    local result=$(sqlite3 "$db_path" "PRAGMA integrity_check;" 2>&1)
    [ "$result" = "ok" ]
}

# Verify compressed database backup
# For SQLite: decompress and run integrity check
# For SQL/tar dumps: just verify the archive is valid
verify_compressed_backup() {
    local compressed_path="$1"

    [ ! -f "$compressed_path" ] && return 1

    local db_type
    db_type=$(_get_backup_db_type "$compressed_path")

    if [[ "$db_type" == "mongodb" ]]; then
        # MongoDB backups are .tar.gz — verify tar integrity
        local _tar_err
        if ! _tar_err=$(tar tzf "$compressed_path" >/dev/null 2>&1); then
            log_debug "Restore tar test failed for $compressed_path: $_tar_err"
            return 1
        fi
        return 0
    fi

    # Test gzip integrity for .gz files
    local _gz_err
    if ! _gz_err=$(gunzip -t "$compressed_path" 2>&1); then
        log_debug "Restore gunzip -t failed for $compressed_path: $_gz_err"
        return 1
    fi

    # For SQLite, also verify database integrity
    if [[ "$db_type" == "sqlite" ]]; then
        local temp_db=$(mktemp)
        gunzip -c "$compressed_path" > "$temp_db" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"

        local result=0
        if ! verify_sqlite_integrity "$temp_db"; then
            result=1
        fi

        rm -f "$temp_db"
        return $result
    fi

    # For MySQL/PostgreSQL SQL dumps, gzip integrity is sufficient
    return 0
}

# Restore database from compressed backup
# Handles SQLite (.db.gz), MySQL/PostgreSQL (.sql.gz), MongoDB (.tar.gz)
# and encrypted variants (.age)
# $1 = backup file path
# $2 = target (DB_PATH for SQLite, or project dir for MySQL/PostgreSQL/MongoDB)
# $3 = dry_run (true/false)
restore_database_from_backup() {
    local backup_file="$1"
    local target_db="$2"
    local dry_run="${3:-false}"

    [ ! -f "$backup_file" ] && color_red "❌ Backup file not found" && return 1

    local db_type
    db_type=$(_get_backup_db_type "$backup_file")

    if [ "$dry_run" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Would restore:"
        color_cyan "   From: $backup_file"
        color_cyan "   Type: $(_get_backup_type_label "$backup_file")"
        if [[ "$db_type" == "sqlite" ]]; then
            color_cyan "   To: $target_db"
        else
            color_cyan "   Database: $(_get_backup_db_name "$backup_file")"
        fi
        [[ "$backup_file" == *.age ]] && color_cyan "   (encrypted — will decrypt before restore)"
        return 0
    fi

    # Handle encrypted backups: decrypt to temp file first
    local actual_backup="$backup_file"
    local _decrypt_tmp=""
    if [[ "$backup_file" == *.age ]]; then
        if ! command -v age >/dev/null 2>&1; then
            log_error "Cannot restore encrypted backup: age not installed"
            color_red "❌ Cannot restore encrypted backup: age not installed"
            return 1
        fi
        color_cyan "🔓 Decrypting backup..."
        _decrypt_tmp="${backup_file%.age}.tmp-decrypt"
        if ! decrypt_file "$backup_file" "$_decrypt_tmp"; then
            log_error "Decryption failed for: $backup_file"
            color_red "❌ Decryption failed"
            rm -f "$_decrypt_tmp"
            return 1
        fi
        actual_backup="$_decrypt_tmp"
        color_green "✅ Decrypted"
    fi

    # Verify backup archive integrity
    color_cyan "🧪 Verifying backup integrity..."
    if ! verify_compressed_backup "$actual_backup"; then
        color_red "❌ Backup verification failed"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi
    color_green "✅ Backup verified"

    # Branch by database type
    case "$db_type" in
        sqlite)
            _restore_sqlite "$actual_backup" "$target_db" "$_decrypt_tmp"
            return $?
            ;;
        mysql)
            _restore_mysql "$actual_backup" "$target_db" "$_decrypt_tmp"
            return $?
            ;;
        postgres)
            _restore_postgres "$actual_backup" "$target_db" "$_decrypt_tmp"
            return $?
            ;;
        mongodb)
            _restore_mongodb "$actual_backup" "$target_db" "$_decrypt_tmp"
            return $?
            ;;
        *)
            color_red "❌ Unknown backup type: $db_type"
            [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# SQLite restore (original logic)
# ---------------------------------------------------------------------------
_restore_sqlite() {
    local actual_backup="$1"
    local target_db="$2"
    local _decrypt_tmp="$3"

    # Create safety backup
    local safety_backup=""
    if [ -f "$target_db" ]; then
        color_cyan "💾 Creating safety backup..."
        safety_backup=$(create_safety_backup "$target_db")
        if [ $? -eq 0 ]; then
            color_green "✅ Safety backup: $(basename "$safety_backup")"
        else
            color_red "❌ Failed to create safety backup"
            [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
            return 1
        fi
    fi

    # Perform restore
    color_cyan "📦 Restoring SQLite database..."
    local _restore_err
    if _restore_err=$(gunzip -c "$actual_backup" > "$target_db" 2>&1); then
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"

        # Verify restored database
        color_cyan "🧪 Verifying restored database..."
        if verify_sqlite_integrity "$target_db"; then
            color_green "✅ Restore complete and verified"
            return 0
        else
            color_red "❌ Restored database failed verification"
            if [ -n "$safety_backup" ] && [ -f "$safety_backup" ]; then
                color_yellow "⚠️  Rolling back to safety backup..."
                cp "$safety_backup" "$target_db"
            fi
            return 1
        fi
    else
        log_error "SQLite restore failed for $target_db: $_restore_err"
        color_red "❌ Restore failed"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# MySQL restore
# ---------------------------------------------------------------------------
_restore_mysql() {
    local actual_backup="$1"
    local project_dir="$2"
    local _decrypt_tmp="$3"

    if ! command -v mysql >/dev/null 2>&1; then
        color_red "❌ mysql client not found — install it to restore MySQL backups"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi

    # Read connection info
    if ! _read_project_env "$project_dir" "mysql"; then
        color_yellow "⚠️  No .env found in $project_dir — using defaults"
    fi

    local db_name="${_RESTORE_DB_NAME:-$(_get_backup_db_name "$actual_backup")}"
    [ -z "$db_name" ] && { color_red "❌ Cannot determine database name"; [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"; return 1; }

    # Build mysql args
    local mysql_args=(-h "$_RESTORE_DB_HOST" -P "$_RESTORE_DB_PORT" -u "$_RESTORE_DB_USER")
    [ -n "$_RESTORE_DB_PASS" ] && mysql_args+=(-p"$_RESTORE_DB_PASS")

    # Safety dump of current state
    color_cyan "💾 Creating safety dump of current $db_name..."
    local safety_file="${BACKUP_DIR:-/tmp}/databases/${db_name}.pre-restore-$(date +%Y%m%d-%H%M%S).sql.gz"
    mkdir -p "$(dirname "$safety_file")"
    local _dump_err
    if _dump_err=$(mysqldump "${mysql_args[@]}" "$db_name" 2>&1 | gzip > "$safety_file"); then
        if [ -s "$safety_file" ]; then
            color_green "✅ Safety dump: $(basename "$safety_file")"
        else
            color_yellow "⚠️  Safety dump is empty (database may not exist yet)"
            rm -f "$safety_file"
        fi
    else
        color_yellow "⚠️  Safety dump failed (database may not exist yet): $_dump_err"
        rm -f "$safety_file"
    fi

    # Perform restore
    color_cyan "📦 Restoring MySQL database $db_name..."
    local _restore_err
    if _restore_err=$(gunzip -c "$actual_backup" | mysql "${mysql_args[@]}" "$db_name" 2>&1); then
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"

        # Post-restore verification
        color_cyan "🧪 Verifying restored database..."
        local table_count
        table_count=$(mysql "${mysql_args[@]}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db_name'" 2>/dev/null | tail -1)
        if [ -n "$table_count" ] && [ "$table_count" -gt 0 ] 2>/dev/null; then
            color_green "✅ Restore complete — $table_count tables in $db_name"
            return 0
        else
            color_yellow "⚠️  Restore completed but verification found $table_count tables"
            return 0
        fi
    else
        log_error "MySQL restore failed for $db_name: $_restore_err"
        color_red "❌ MySQL restore failed: $_restore_err"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# PostgreSQL restore
# ---------------------------------------------------------------------------
_restore_postgres() {
    local actual_backup="$1"
    local project_dir="$2"
    local _decrypt_tmp="$3"

    if ! command -v psql >/dev/null 2>&1; then
        color_red "❌ psql client not found — install it to restore PostgreSQL backups"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi

    # Read connection info
    if ! _read_project_env "$project_dir" "postgres"; then
        color_yellow "⚠️  No .env found in $project_dir — using defaults"
    fi

    local db_name="${_RESTORE_DB_NAME:-$(_get_backup_db_name "$actual_backup")}"
    [ -z "$db_name" ] && { color_red "❌ Cannot determine database name"; [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"; return 1; }

    # Set PGPASSWORD for non-interactive auth
    [ -n "$_RESTORE_DB_PASS" ] && export PGPASSWORD="$_RESTORE_DB_PASS"

    local psql_args=(-h "$_RESTORE_DB_HOST" -p "$_RESTORE_DB_PORT" -U "$_RESTORE_DB_USER")

    # Safety dump of current state
    color_cyan "💾 Creating safety dump of current $db_name..."
    local safety_file="${BACKUP_DIR:-/tmp}/databases/${db_name}.pre-restore-$(date +%Y%m%d-%H%M%S).sql.gz"
    mkdir -p "$(dirname "$safety_file")"
    local _dump_err
    if _dump_err=$(pg_dump "${psql_args[@]}" "$db_name" 2>&1 | gzip > "$safety_file"); then
        if [ -s "$safety_file" ]; then
            color_green "✅ Safety dump: $(basename "$safety_file")"
        else
            color_yellow "⚠️  Safety dump is empty (database may not exist yet)"
            rm -f "$safety_file"
        fi
    else
        color_yellow "⚠️  Safety dump failed (database may not exist yet): $_dump_err"
        rm -f "$safety_file"
    fi

    # Perform restore
    color_cyan "📦 Restoring PostgreSQL database $db_name..."
    local _restore_err
    if _restore_err=$(gunzip -c "$actual_backup" | psql "${psql_args[@]}" "$db_name" 2>&1); then
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        unset PGPASSWORD 2>/dev/null || true

        # Post-restore verification
        color_cyan "🧪 Verifying restored database..."
        local table_count
        table_count=$(psql "${psql_args[@]}" -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" "$db_name" 2>/dev/null | head -1)
        if [ -n "$table_count" ] && [ "$table_count" -gt 0 ] 2>/dev/null; then
            color_green "✅ Restore complete — $table_count tables in $db_name"
            return 0
        else
            color_yellow "⚠️  Restore completed but verification found $table_count tables"
            return 0
        fi
    else
        log_error "PostgreSQL restore failed for $db_name: $_restore_err"
        color_red "❌ PostgreSQL restore failed: $_restore_err"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        unset PGPASSWORD 2>/dev/null || true
        return 1
    fi
}

# ---------------------------------------------------------------------------
# MongoDB restore
# ---------------------------------------------------------------------------
_restore_mongodb() {
    local actual_backup="$1"
    local project_dir="$2"
    local _decrypt_tmp="$3"

    if ! command -v mongorestore >/dev/null 2>&1; then
        color_red "❌ mongorestore not found — install MongoDB tools to restore"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi

    # Read connection info
    if ! _read_project_env "$project_dir" "mongodb"; then
        color_yellow "⚠️  No .env found in $project_dir — using defaults"
    fi

    local db_name="${_RESTORE_DB_NAME:-$(_get_backup_db_name "$actual_backup")}"
    [ -z "$db_name" ] && { color_red "❌ Cannot determine database name"; [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"; return 1; }

    local mongo_args=(--host "$_RESTORE_DB_HOST" --port "$_RESTORE_DB_PORT")
    [ -n "$_RESTORE_DB_USER" ] && mongo_args+=(--username "$_RESTORE_DB_USER")
    [ -n "$_RESTORE_DB_PASS" ] && mongo_args+=(--password "$_RESTORE_DB_PASS")

    # Safety dump of current state
    color_cyan "💾 Creating safety dump of current $db_name..."
    local safety_dir="${BACKUP_DIR:-/tmp}/databases/${db_name}.pre-restore-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$safety_dir"
    local _dump_err
    if _dump_err=$(mongodump "${mongo_args[@]}" --db "$db_name" --out "$safety_dir" 2>&1); then
        color_green "✅ Safety dump: $(basename "$safety_dir")"
    else
        color_yellow "⚠️  Safety dump failed (database may not exist yet): $_dump_err"
        rm -rf "$safety_dir"
    fi

    # Extract tar to temp directory
    local temp_dir
    temp_dir=$(mktemp -d)
    color_cyan "📦 Extracting backup archive..."
    if ! tar xzf "$actual_backup" -C "$temp_dir" 2>&1; then
        color_red "❌ Failed to extract backup archive"
        rm -rf "$temp_dir"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi

    # Perform restore — mongorestore expects a directory with BSON files
    color_cyan "📦 Restoring MongoDB database $db_name..."
    # Find the dump directory (mongodump creates db_name/ subdirectory)
    local restore_path="$temp_dir"
    if [ -d "$temp_dir/$db_name" ]; then
        restore_path="$temp_dir/$db_name"
    else
        # Look for any subdirectory
        local subdir
        subdir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
        [ -n "$subdir" ] && restore_path="$subdir"
    fi

    local _restore_err
    if _restore_err=$(mongorestore "${mongo_args[@]}" --db "$db_name" --drop "$restore_path" 2>&1); then
        rm -rf "$temp_dir"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"

        # Post-restore verification
        color_cyan "🧪 Verifying restored database..."
        local coll_count
        if command -v mongosh >/dev/null 2>&1; then
            coll_count=$(mongosh --host "$_RESTORE_DB_HOST" --port "$_RESTORE_DB_PORT" --quiet --eval "db.getSiblingDB('$db_name').getCollectionNames().length" 2>/dev/null)
        elif command -v mongo >/dev/null 2>&1; then
            coll_count=$(mongo --host "$_RESTORE_DB_HOST" --port "$_RESTORE_DB_PORT" --quiet --eval "db.getSiblingDB('$db_name').getCollectionNames().length" 2>/dev/null)
        fi
        if [ -n "$coll_count" ] && [ "$coll_count" -gt 0 ] 2>/dev/null; then
            color_green "✅ Restore complete — $coll_count collections in $db_name"
        else
            color_yellow "⚠️  Restore completed but verification found $coll_count collections"
        fi
        return 0
    else
        log_error "MongoDB restore failed for $db_name: $_restore_err"
        color_red "❌ MongoDB restore failed: $_restore_err"
        rm -rf "$temp_dir"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi
}

# Restore file from backup
# Handles both unencrypted and encrypted (.age) file backups
restore_file_from_backup() {
    local backup_file="$1"
    local target_file="$2"
    local dry_run="${3:-false}"

    [ ! -f "$backup_file" ] && color_red "❌ Backup file not found" && return 1

    if [ "$dry_run" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Would restore:"
        color_cyan "   From: $backup_file"
        color_cyan "   To: $target_file"
        [[ "$backup_file" == *.age ]] && color_cyan "   (encrypted — will decrypt before restore)"
        return 0
    fi

    # Handle encrypted backups: decrypt to temp file first
    local actual_backup="$backup_file"
    local _decrypt_tmp=""
    if [[ "$backup_file" == *.age ]]; then
        if ! command -v age >/dev/null 2>&1; then
            log_error "Cannot restore encrypted backup: age not installed"
            color_red "❌ Cannot restore encrypted backup: age not installed"
            return 1
        fi
        color_cyan "🔓 Decrypting backup..."
        _decrypt_tmp="${backup_file%.age}.tmp-decrypt"
        if ! decrypt_file "$backup_file" "$_decrypt_tmp"; then
            log_error "Decryption failed for: $backup_file"
            color_red "❌ Decryption failed"
            rm -f "$_decrypt_tmp"
            return 1
        fi
        actual_backup="$_decrypt_tmp"
        color_green "✅ Decrypted"
    fi

    # Create safety backup
    local safety_backup=""
    if [ -f "$target_file" ]; then
        color_cyan "💾 Creating safety backup..."
        safety_backup=$(create_safety_backup "$target_file")
        [ $? -eq 0 ] && color_green "✅ Safety backup: $(basename "$safety_backup")"
    fi

    # Create target directory
    mkdir -p "$(dirname "$target_file")"

    # Perform restore
    color_cyan "📦 Restoring file..."
    local _cp_err
    if _cp_err=$(cp "$actual_backup" "$target_file" 2>&1); then
        # Clean up decrypted temp file
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        log_info "File restored: $target_file"
        color_green "✅ Restore complete"
        return 0
    else
        log_error "File restore cp failed for $target_file: $_cp_err"
        color_red "❌ Restore failed"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi
}
