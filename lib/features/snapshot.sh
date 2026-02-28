#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Database Snapshot Library
# ==============================================================================
# Version: 3.1.0
# Description: Named, per-table database snapshots with schema extraction,
#              manifest generation, and schema comparison for restore safety.
#
# Storage layout:
#   $BACKUP_DIR/snapshots/<snapshot-name>/
#     manifest.json        - Snapshot metadata (db type, tables, sizes, checksums)
#     schema.sql           - Full schema (all tables)
#     tables/
#       tablename.sql.gz   - Per-table data+schema dump (SQL types)
#       collname.bson.gz   - Per-collection dump (MongoDB)
#
# @requires: core/logging, core/output, database-detector.sh
# @provides: snapshot_create, snapshot_list, snapshot_delete,
#            snapshot_get_manifest, snapshot_compare_schema,
#            snapshot_generate_bundle
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_SNAPSHOT:-}" ] && return || readonly _CHECKPOINT_SNAPSHOT=1

# Set logging context for this module
log_set_context "snapshot"

# ==============================================================================
# CONSTANTS
# ==============================================================================

# Max snapshot name length
readonly SNAPSHOT_NAME_MAX_LENGTH=64

# Valid snapshot name pattern (alphanumeric, hyphens, underscores, dots)
readonly SNAPSHOT_NAME_PATTERN='^[a-zA-Z0-9][a-zA-Z0-9._-]*$'

# ==============================================================================
# SNAPSHOT NAME VALIDATION
# ==============================================================================

# Validate a snapshot name
# $1 = name to validate
# Returns: 0 if valid, 1 if invalid (prints error to stderr)
snapshot_validate_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo "Snapshot name cannot be empty" >&2
        return 1
    fi

    if [[ ${#name} -gt $SNAPSHOT_NAME_MAX_LENGTH ]]; then
        echo "Snapshot name too long (max $SNAPSHOT_NAME_MAX_LENGTH characters)" >&2
        return 1
    fi

    if ! [[ "$name" =~ $SNAPSHOT_NAME_PATTERN ]]; then
        echo "Invalid snapshot name: use letters, numbers, hyphens, underscores, dots" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# TABLE LISTING
# ==============================================================================

# List tables in a SQLite database
# $1 = path to SQLite file
# Output: newline-separated table names (excludes internal tables)
_snapshot_list_tables_sqlite() {
    local db_path="$1"
    sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;" 2>/dev/null
}

# List tables in a PostgreSQL database
# $1=host $2=port $3=user $4=database $5=password
# Output: newline-separated table names
_snapshot_list_tables_postgresql() {
    local host="$1" port="$2" user="$3" database="$4" password="${5:-}"
    local -a psql_args=(-h "$host" -p "$port" -U "$user" -t -A)

    [[ -n "$password" ]] && export PGPASSWORD="$password"
    psql "${psql_args[@]}" -c "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename" "$database" 2>/dev/null
    local rc=$?
    unset PGPASSWORD 2>/dev/null || true
    return $rc
}

# List tables in a MySQL database
# $1=host $2=port $3=user $4=database $5=password
# Output: newline-separated table names
_snapshot_list_tables_mysql() {
    local host="$1" port="$2" user="$3" database="$4" password="${5:-}"
    local -a mysql_args=(-h "$host" -P "$port" -u "$user" -N)

    [[ -n "$password" ]] && export MYSQL_PWD="$password"
    mysql "${mysql_args[@]}" -e "SHOW TABLES" "$database" 2>/dev/null
    local rc=$?
    unset MYSQL_PWD 2>/dev/null || true
    return $rc
}

# List collections in a MongoDB database
# $1=host $2=port $3=database $4=user $5=password $6=full_url
# Output: newline-separated collection names
_snapshot_list_tables_mongodb() {
    local host="$1" port="$2" database="$3" user="${4:-}" password="${5:-}" full_url="${6:-}"
    local mongo_cmd="mongosh"
    command -v mongosh &>/dev/null || mongo_cmd="mongo"

    local eval_js="db.getSiblingDB('$database').getCollectionNames().forEach(function(c){print(c)})"

    if [[ -n "$full_url" ]]; then
        "$mongo_cmd" "$full_url" --quiet --eval "$eval_js" 2>/dev/null
    else
        local -a mongo_args=(--host "$host" --port "$port" --quiet)
        [[ -n "$user" ]] && mongo_args+=(--username "$user")
        [[ -n "$password" ]] && mongo_args+=(--password "$password")
        "$mongo_cmd" "${mongo_args[@]}" --eval "$eval_js" 2>/dev/null
    fi
}

# ==============================================================================
# SCHEMA EXTRACTION
# ==============================================================================

# Extract schema for a single SQLite table
# $1=db_path $2=table_name
# Output: CREATE TABLE statement to stdout
_snapshot_schema_sqlite() {
    local db_path="$1" table="$2"
    sqlite3 "$db_path" ".schema $table" 2>/dev/null
}

# Extract schema for a single PostgreSQL table
# $1=host $2=port $3=user $4=database $5=password $6=table_name
# Output: CREATE TABLE + indexes to stdout
_snapshot_schema_postgresql() {
    local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6"
    [[ -n "$password" ]] && export PGPASSWORD="$password"
    pg_dump -h "$host" -p "$port" -U "$user" --schema-only -t "$table" "$database" 2>/dev/null \
        | grep -v "^--" | grep -v "^$" | grep -v "^SET " | grep -v "^SELECT "
    local rc=${PIPESTATUS[0]}
    unset PGPASSWORD 2>/dev/null || true
    return $rc
}

# Extract schema for a single MySQL table
# $1=host $2=port $3=user $4=database $5=password $6=table_name
# Output: CREATE TABLE statement to stdout
_snapshot_schema_mysql() {
    local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6"
    [[ -n "$password" ]] && export MYSQL_PWD="$password"
    mysqldump -h "$host" -P "$port" -u "$user" --no-data "$database" "$table" 2>/dev/null \
        | grep -v "^--" | grep -v "^/\*" | grep -v "^$"
    local rc=${PIPESTATUS[0]}
    unset MYSQL_PWD 2>/dev/null || true
    return $rc
}

# Extract schema info for a MongoDB collection (indexes + validation rules)
# $1=host $2=port $3=database $4=user $5=password $6=full_url $7=collection_name
# Output: JSON index/validation info to stdout
_snapshot_schema_mongodb() {
    local host="$1" port="$2" database="$3" user="${4:-}" password="${5:-}" full_url="${6:-}" collection="$7"
    local mongo_cmd="mongosh"
    command -v mongosh &>/dev/null || mongo_cmd="mongo"

    local eval_js="var coll='$collection'; var db_name='$database'; var d=db.getSiblingDB(db_name); print('indexes:'); printjson(d[coll].getIndexes()); print('info:'); printjson(d.getCollectionInfos({name:coll}));"

    if [[ -n "$full_url" ]]; then
        "$mongo_cmd" "$full_url" --quiet --eval "$eval_js" 2>/dev/null
    else
        local -a mongo_args=(--host "$host" --port "$port" --quiet)
        [[ -n "$user" ]] && mongo_args+=(--username "$user")
        [[ -n "$password" ]] && mongo_args+=(--password "$password")
        "$mongo_cmd" "${mongo_args[@]}" --eval "$eval_js" 2>/dev/null
    fi
}

# ==============================================================================
# PER-TABLE DUMP
# ==============================================================================

# Dump a single SQLite table (data+schema) to compressed file
# $1=db_path $2=table_name $3=output_dir
# Returns: 0 on success, 1 on failure
_snapshot_dump_table_sqlite() {
    local db_path="$1" table="$2" output_dir="$3"
    local _err

    mkdir -p "$output_dir/tables"
    if _err=$(sqlite3 "$db_path" ".dump $table" 2>&1 | gzip > "$output_dir/tables/${table}.sql.gz"); then
        if gunzip -t "$output_dir/tables/${table}.sql.gz" 2>/dev/null; then
            return 0
        fi
    fi
    log_debug "SQLite table dump failed for $table: $_err"
    rm -f "$output_dir/tables/${table}.sql.gz"
    return 1
}

# Dump a single PostgreSQL table to compressed file
# $1=host $2=port $3=user $4=database $5=password $6=table_name $7=output_dir
_snapshot_dump_table_postgresql() {
    local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6" output_dir="$7"

    mkdir -p "$output_dir/tables"
    [[ -n "$password" ]] && export PGPASSWORD="$password"
    pg_dump -h "$host" -p "$port" -U "$user" -t "$table" "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$output_dir/tables/${table}.sql.gz"
    local pg_exit=${PIPESTATUS[0]}
    unset PGPASSWORD 2>/dev/null || true

    if [[ $pg_exit -eq 0 ]] && gunzip -t "$output_dir/tables/${table}.sql.gz" 2>/dev/null; then
        return 0
    fi
    log_debug "PostgreSQL table dump failed for $table (exit=$pg_exit)"
    rm -f "$output_dir/tables/${table}.sql.gz"
    return 1
}

# Dump a single MySQL table to compressed file
# $1=host $2=port $3=user $4=database $5=password $6=table_name $7=output_dir
_snapshot_dump_table_mysql() {
    local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6" output_dir="$7"

    mkdir -p "$output_dir/tables"
    [[ -n "$password" ]] && export MYSQL_PWD="$password"
    mysqldump -h "$host" -P "$port" -u "$user" "$database" "$table" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}" | gzip > "$output_dir/tables/${table}.sql.gz"
    local mysql_exit=${PIPESTATUS[0]}
    unset MYSQL_PWD 2>/dev/null || true

    if [[ $mysql_exit -eq 0 ]] && gunzip -t "$output_dir/tables/${table}.sql.gz" 2>/dev/null; then
        return 0
    fi
    log_debug "MySQL table dump failed for $table (exit=$mysql_exit)"
    rm -f "$output_dir/tables/${table}.sql.gz"
    return 1
}

# Dump a single MongoDB collection to compressed file
# $1=host $2=port $3=database $4=user $5=password $6=full_url $7=collection_name $8=output_dir
_snapshot_dump_table_mongodb() {
    local host="$1" port="$2" database="$3" user="${4:-}" password="${5:-}" full_url="${6:-}" collection="$7" output_dir="$8"

    mkdir -p "$output_dir/tables"
    local temp_dir
    temp_dir=$(mktemp -d -t "snapshot_mongo.XXXXXX") || return 1

    local -a mongo_args=()
    if [[ -n "$full_url" ]]; then
        mongo_args+=(--uri="$full_url")
    else
        mongo_args+=(--host "$host" --port "$port")
        [[ -n "$user" ]] && mongo_args+=(--username "$user")
        [[ -n "$password" ]] && mongo_args+=(--password "$password")
    fi
    mongo_args+=(--db "$database" --collection "$collection" --out "$temp_dir")

    local _err
    if _err=$(mongodump "${mongo_args[@]}" 2>&1); then
        # mongodump creates db_name/collection.bson — tar and compress it
        if tar -czf "$output_dir/tables/${collection}.bson.gz" -C "$temp_dir" . 2>/dev/null; then
            rm -rf "$temp_dir"
            return 0
        fi
    fi

    log_debug "MongoDB collection dump failed for $collection: $_err"
    rm -rf "$temp_dir"
    rm -f "$output_dir/tables/${collection}.bson.gz"
    return 1
}

# ==============================================================================
# ROW COUNT
# ==============================================================================

# Get row count for a table
# $1=db_type $2..N=connection params + table_name (last arg)
_snapshot_row_count() {
    local db_type="$1"
    shift

    case "$db_type" in
        sqlite)
            local db_path="$1" table="$2"
            sqlite3 "$db_path" "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null || echo "0"
            ;;
        postgresql)
            local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6"
            [[ -n "$password" ]] && export PGPASSWORD="$password"
            psql -h "$host" -p "$port" -U "$user" -t -A -c "SELECT COUNT(*) FROM \"$table\"" "$database" 2>/dev/null || echo "0"
            unset PGPASSWORD 2>/dev/null || true
            ;;
        mysql)
            local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6"
            [[ -n "$password" ]] && export MYSQL_PWD="$password"
            mysql -h "$host" -P "$port" -u "$user" -N -e "SELECT COUNT(*) FROM \`$table\`" "$database" 2>/dev/null || echo "0"
            unset MYSQL_PWD 2>/dev/null || true
            ;;
        mongodb)
            local host="$1" port="$2" database="$3" user="${4:-}" password="${5:-}" full_url="${6:-}" collection="$7"
            local mongo_cmd="mongosh"
            command -v mongosh &>/dev/null || mongo_cmd="mongo"
            local eval_js="db.getSiblingDB('$database').$collection.countDocuments({})"
            if [[ -n "$full_url" ]]; then
                "$mongo_cmd" "$full_url" --quiet --eval "$eval_js" 2>/dev/null || echo "0"
            else
                local -a args=(--host "$host" --port "$port" --quiet)
                [[ -n "$user" ]] && args+=(--username "$user")
                [[ -n "$password" ]] && args+=(--password "$password")
                "$mongo_cmd" "${args[@]}" --eval "$eval_js" 2>/dev/null || echo "0"
            fi
            ;;
    esac
}

# ==============================================================================
# MANIFEST GENERATION
# ==============================================================================

# Generate manifest.json for a completed snapshot
# $1=snapshot_dir $2=db_type $3=db_name $4=host $5=port $6=is_local
#    $7=snapshot_name $8=table_entries_json $9=table_count $10=total_rows
#    $11=total_bytes $12=duration $13=status
_snapshot_write_manifest() {
    local snapshot_dir="$1" db_type="$2" db_name="$3" host="$4" port="$5"
    local is_local="$6" snapshot_name="$7" table_entries="$8" table_count="$9"
    local total_rows="${10}" total_bytes="${11}" duration="${12}" status="${13}"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local snapshot_id
    snapshot_id=$(date +%Y%m%d_%H%M%S)_$$

    # Escape strings for JSON
    local safe_name
    safe_name=$(printf '%s' "$snapshot_name" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local safe_db_name
    safe_db_name=$(printf '%s' "$db_name" | sed 's/\\/\\\\/g; s/"/\\"/g')

    cat > "$snapshot_dir/manifest.json" <<MANIFEST_EOF
{
  "version": "1.0.0",
  "snapshot_name": "$safe_name",
  "snapshot_id": "$snapshot_id",
  "timestamp": "$timestamp",
  "db_type": "$db_type",
  "db_name": "$safe_db_name",
  "host": "$host",
  "port": $port,
  "is_local": $is_local,
  "table_count": $table_count,
  "total_rows": $total_rows,
  "total_data_bytes": $total_bytes,
  "duration_seconds": $duration,
  "status": "$status",
  "checkpoint_version": "${CHECKPOINT_VERSION:-3.1.0}",
  "tables": [
$table_entries
  ]
}
MANIFEST_EOF
}

# Build a single table entry for manifest JSON
# $1=name $2=row_count $3=schema_file $4=data_file $5=data_size_bytes $6=is_last
_snapshot_table_entry_json() {
    local name="$1" row_count="$2" schema_file="$3" data_file="$4" size="$5" is_last="${6:-false}"
    local safe_name
    safe_name=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local trailing=","
    [[ "$is_last" == "true" ]] && trailing=""

    printf '    {"name":"%s","row_count":%s,"schema_file":"%s","data_file":"%s","data_size_bytes":%s}%s' \
        "$safe_name" "$row_count" "$schema_file" "$data_file" "$size" "$trailing"
}

# ==============================================================================
# MAIN SNAPSHOT FUNCTION
# ==============================================================================

# Create a named snapshot of a detected database
# $1 = database info string (from detect_databases)
# $2 = backup directory
# $3 = snapshot name
# Returns: 0 on success, 1 on failure
# Output: status messages to stdout
snapshot_create() {
    local db_info="$1"
    local backup_dir="$2"
    local snapshot_name="$3"

    # Validate name
    if ! snapshot_validate_name "$snapshot_name"; then
        return 1
    fi

    local start_time=$SECONDS

    IFS='|' read -r db_type rest <<< "$db_info"

    local snapshot_dir=""
    local db_name="" host="" port="" user="" password="" is_local="" full_url=""

    case "$db_type" in
        sqlite)
            local db_path="$rest"
            db_name=$(basename "$db_path" | sed 's/\.[^.]*$//')
            host="local"
            port=0
            is_local="true"
            snapshot_dir="$backup_dir/snapshots/$snapshot_name"
            ;;
        postgresql|mysql|mongodb)
            IFS='|' read -r host port db_name user is_local password full_url <<< "$rest"
            snapshot_dir="$backup_dir/snapshots/$snapshot_name"
            ;;
        docker)
            IFS='|' read -r container_name docker_db_type db_name user password <<< "$rest"
            echo "⚠ Docker snapshot not yet supported (use full backup instead)"
            return 1
            ;;
        *)
            echo "❌ Unknown database type: $db_type" >&2
            return 1
            ;;
    esac

    # Check if snapshot already exists
    if [[ -d "$snapshot_dir" ]]; then
        echo "❌ Snapshot '$snapshot_name' already exists" >&2
        echo "   Use a different name or delete the existing snapshot first" >&2
        return 1
    fi

    # Create snapshot directory structure
    mkdir -p "$snapshot_dir/tables"

    echo "📸 Creating snapshot '$snapshot_name' for $db_type database '$db_name'..."

    # List tables
    local tables=()
    local table_list=""

    case "$db_type" in
        sqlite)
            table_list=$(_snapshot_list_tables_sqlite "$db_path") || {
                echo "❌ Failed to list SQLite tables"
                rm -rf "$snapshot_dir"
                return 1
            }
            ;;
        postgresql)
            table_list=$(_snapshot_list_tables_postgresql "$host" "$port" "$user" "$db_name" "$password") || {
                echo "❌ Failed to list PostgreSQL tables"
                rm -rf "$snapshot_dir"
                return 1
            }
            ;;
        mysql)
            table_list=$(_snapshot_list_tables_mysql "$host" "$port" "$user" "$db_name" "$password") || {
                echo "❌ Failed to list MySQL tables"
                rm -rf "$snapshot_dir"
                return 1
            }
            ;;
        mongodb)
            table_list=$(_snapshot_list_tables_mongodb "$host" "$port" "$db_name" "$user" "$password" "$full_url") || {
                echo "❌ Failed to list MongoDB collections"
                rm -rf "$snapshot_dir"
                return 1
            }
            ;;
    esac

    # Parse table list into array
    while IFS= read -r t; do
        [[ -n "$t" ]] && tables+=("$t")
    done <<< "$table_list"

    if [[ ${#tables[@]} -eq 0 ]]; then
        echo "⚠ No tables found in database '$db_name'"
        rm -rf "$snapshot_dir"
        return 1
    fi

    echo "   Found ${#tables[@]} tables"

    # Extract full schema
    echo -n "   Extracting schema... "
    local schema_content=""
    for table in "${tables[@]}"; do
        case "$db_type" in
            sqlite)     schema_content+=$(_snapshot_schema_sqlite "$db_path" "$table")$'\n\n' ;;
            postgresql) schema_content+=$(_snapshot_schema_postgresql "$host" "$port" "$user" "$db_name" "$password" "$table")$'\n\n' ;;
            mysql)      schema_content+=$(_snapshot_schema_mysql "$host" "$port" "$user" "$db_name" "$password" "$table")$'\n\n' ;;
            mongodb)    schema_content+=$(_snapshot_schema_mongodb "$host" "$port" "$db_name" "$user" "$password" "$full_url" "$table")$'\n\n' ;;
        esac
    done
    printf '%s' "$schema_content" > "$snapshot_dir/schema.sql"
    echo "done"

    # Dump each table
    local table_entries=""
    local total_rows=0
    local total_bytes=0
    local failed_tables=0
    local table_count=${#tables[@]}
    local idx=0

    for table in "${tables[@]}"; do
        idx=$((idx + 1))
        echo -n "   [$idx/$table_count] $table... "

        local dump_ok=false
        case "$db_type" in
            sqlite)
                _snapshot_dump_table_sqlite "$db_path" "$table" "$snapshot_dir" && dump_ok=true
                ;;
            postgresql)
                _snapshot_dump_table_postgresql "$host" "$port" "$user" "$db_name" "$password" "$table" "$snapshot_dir" && dump_ok=true
                ;;
            mysql)
                _snapshot_dump_table_mysql "$host" "$port" "$user" "$db_name" "$password" "$table" "$snapshot_dir" && dump_ok=true
                ;;
            mongodb)
                _snapshot_dump_table_mongodb "$host" "$port" "$db_name" "$user" "$password" "$full_url" "$table" "$snapshot_dir" && dump_ok=true
                ;;
        esac

        if [[ "$dump_ok" == "true" ]]; then
            # Get row count
            local rows=0
            case "$db_type" in
                sqlite)     rows=$(_snapshot_row_count sqlite "$db_path" "$table") ;;
                postgresql) rows=$(_snapshot_row_count postgresql "$host" "$port" "$user" "$db_name" "$password" "$table") ;;
                mysql)      rows=$(_snapshot_row_count mysql "$host" "$port" "$user" "$db_name" "$password" "$table") ;;
                mongodb)    rows=$(_snapshot_row_count mongodb "$host" "$port" "$db_name" "$user" "$password" "$full_url" "$table") ;;
            esac
            rows="${rows//[^0-9]/}"  # Strip non-numeric
            rows="${rows:-0}"

            # Get file size
            local data_ext="sql.gz"
            [[ "$db_type" == "mongodb" ]] && data_ext="bson.gz"
            local data_file="tables/${table}.${data_ext}"
            local file_size=0
            if [[ -f "$snapshot_dir/$data_file" ]]; then
                file_size=$(wc -c < "$snapshot_dir/$data_file" 2>/dev/null || echo 0)
                file_size="${file_size//[[:space:]]/}"
            fi

            total_rows=$((total_rows + rows))
            total_bytes=$((total_bytes + file_size))

            # Build manifest entry
            local is_last="false"
            [[ $idx -eq $table_count ]] && is_last="true"
            local entry
            entry=$(_snapshot_table_entry_json "$table" "$rows" "schema.sql" "$data_file" "$file_size" "$is_last")
            if [[ -n "$table_entries" ]]; then
                table_entries+=$'\n'
            fi
            table_entries+="$entry"

            echo "$rows rows ($file_size bytes)"
        else
            failed_tables=$((failed_tables + 1))
            echo "FAILED"
        fi
    done

    # Determine status
    local status="complete"
    if [[ $failed_tables -gt 0 ]]; then
        if [[ $failed_tables -eq $table_count ]]; then
            status="failed"
        else
            status="partial"
        fi
    fi

    # Calculate duration
    local duration=$(( SECONDS - start_time ))

    # Write manifest
    _snapshot_write_manifest "$snapshot_dir" "$db_type" "$db_name" "$host" "${port:-0}" \
        "$is_local" "$snapshot_name" "$table_entries" "$table_count" "$total_rows" \
        "$total_bytes" "$duration" "$status"

    echo ""
    if [[ "$status" == "complete" ]]; then
        echo "✅ Snapshot '$snapshot_name' created: $table_count tables, $total_rows rows (${duration}s)"
    elif [[ "$status" == "partial" ]]; then
        echo "⚠ Snapshot '$snapshot_name' partial: $((table_count - failed_tables))/$table_count tables succeeded (${duration}s)"
    else
        echo "❌ Snapshot '$snapshot_name' failed: all $table_count tables failed"
        rm -rf "$snapshot_dir"
        return 1
    fi

    return 0
}

# ==============================================================================
# SNAPSHOT LISTING
# ==============================================================================

# List all snapshots for a project
# $1 = backup directory
# Output: one line per snapshot: name|db_type|db_name|table_count|timestamp|status|size
snapshot_list() {
    local backup_dir="$1"
    local snapshots_dir="$backup_dir/snapshots"

    if [[ ! -d "$snapshots_dir" ]]; then
        return 0
    fi

    for snap_dir in "$snapshots_dir"/*/; do
        [[ -d "$snap_dir" ]] || continue
        local manifest="$snap_dir/manifest.json"
        [[ -f "$manifest" ]] || continue

        local name
        name=$(basename "$snap_dir")

        # Parse manifest with grep/sed (no jq dependency)
        local db_type db_name table_count timestamp status
        db_type=$(grep '"db_type"' "$manifest" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
        db_name=$(grep '"db_name"' "$manifest" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
        table_count=$(grep '"table_count"' "$manifest" | head -1 | sed 's/.*: *\([0-9]*\).*/\1/')
        timestamp=$(grep '"timestamp"' "$manifest" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
        status=$(grep '"status"' "$manifest" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

        # Calculate directory size
        local dir_size
        dir_size=$(du -sh "$snap_dir" 2>/dev/null | cut -f1 || echo "?")

        printf '%s|%s|%s|%s|%s|%s|%s\n' "$name" "$db_type" "$db_name" "${table_count:-0}" "${timestamp:-unknown}" "${status:-unknown}" "$dir_size"
    done
}

# ==============================================================================
# SNAPSHOT DELETION
# ==============================================================================

# Delete a named snapshot
# $1 = backup directory
# $2 = snapshot name
# Returns: 0 on success, 1 if not found
snapshot_delete() {
    local backup_dir="$1"
    local snapshot_name="$2"
    local snapshot_dir="$backup_dir/snapshots/$snapshot_name"

    if [[ ! -d "$snapshot_dir" ]]; then
        echo "❌ Snapshot '$snapshot_name' not found" >&2
        return 1
    fi

    rm -rf "$snapshot_dir"
    echo "🗑 Snapshot '$snapshot_name' deleted"
    return 0
}

# ==============================================================================
# SNAPSHOT MANIFEST READING
# ==============================================================================

# Read manifest.json and output key fields
# $1 = snapshot directory path
# Output: key=value pairs
snapshot_get_manifest() {
    local snapshot_dir="$1"
    local manifest="$snapshot_dir/manifest.json"

    if [[ ! -f "$manifest" ]]; then
        echo "❌ No manifest found in $snapshot_dir" >&2
        return 1
    fi

    cat "$manifest"
}

# Get list of table names from a snapshot manifest
# $1 = snapshot directory path
# Output: newline-separated table names
snapshot_get_tables() {
    local snapshot_dir="$1"
    local manifest="$snapshot_dir/manifest.json"

    [[ -f "$manifest" ]] || return 1
    grep '"name"' "$manifest" | sed 's/.*"name" *: *"\([^"]*\)".*/\1/'
}

# ==============================================================================
# SCHEMA COMPARISON
# ==============================================================================

# Compare snapshot schema against live database schema
# $1 = snapshot directory
# $2 = db_info string (from detect_databases)
# Returns: 0 if schemas match, 1 if different, 2 on error
# Output: diff summary to stdout
snapshot_compare_schema() {
    local snapshot_dir="$1"
    local db_info="$2"

    local snapshot_schema="$snapshot_dir/schema.sql"
    if [[ ! -f "$snapshot_schema" ]]; then
        echo "❌ No schema file found in snapshot" >&2
        return 2
    fi

    IFS='|' read -r db_type rest <<< "$db_info"

    # Get live schema
    local live_schema
    live_schema=$(mktemp -t "snapshot_live_schema.XXXXXX.sql") || return 2
    trap "rm -f '$live_schema'" RETURN

    local tables=()
    case "$db_type" in
        sqlite)
            local db_path="$rest"
            local table_list
            table_list=$(_snapshot_list_tables_sqlite "$db_path") || return 2
            while IFS= read -r t; do
                [[ -n "$t" ]] && tables+=("$t")
            done <<< "$table_list"
            for t in "${tables[@]}"; do
                _snapshot_schema_sqlite "$db_path" "$t" >> "$live_schema"
                echo "" >> "$live_schema"
            done
            ;;
        postgresql)
            IFS='|' read -r host port db_name user is_local password full_url <<< "$rest"
            local table_list
            table_list=$(_snapshot_list_tables_postgresql "$host" "$port" "$user" "$db_name" "$password") || return 2
            while IFS= read -r t; do
                [[ -n "$t" ]] && tables+=("$t")
            done <<< "$table_list"
            for t in "${tables[@]}"; do
                _snapshot_schema_postgresql "$host" "$port" "$user" "$db_name" "$password" "$t" >> "$live_schema"
                echo "" >> "$live_schema"
            done
            ;;
        mysql)
            IFS='|' read -r host port db_name user is_local password full_url <<< "$rest"
            local table_list
            table_list=$(_snapshot_list_tables_mysql "$host" "$port" "$user" "$db_name" "$password") || return 2
            while IFS= read -r t; do
                [[ -n "$t" ]] && tables+=("$t")
            done <<< "$table_list"
            for t in "${tables[@]}"; do
                _snapshot_schema_mysql "$host" "$port" "$user" "$db_name" "$password" "$t" >> "$live_schema"
                echo "" >> "$live_schema"
            done
            ;;
        mongodb)
            # MongoDB is schemaless — always "compatible"
            echo "MongoDB is schemaless — schema comparison not applicable"
            echo "COMPATIBLE"
            return 0
            ;;
    esac

    # Compare
    if diff -q "$snapshot_schema" "$live_schema" &>/dev/null; then
        echo "MATCH"
        return 0
    else
        echo "CHANGED"
        echo ""
        echo "Schema differences:"
        diff --unified=3 "$snapshot_schema" "$live_schema" 2>/dev/null || true
        return 1
    fi
}

# ==============================================================================
# DOWNLOAD BUNDLE GENERATION
# ==============================================================================

# Generate a self-contained download bundle for schema-mismatch restores
# $1 = snapshot directory
# $2 = db_info string (live database)
# $3 = output directory (default: ~/Downloads)
# Returns: 0 on success, sets BUNDLE_PATH variable
snapshot_generate_bundle() {
    local snapshot_dir="$1"
    local db_info="$2"
    local output_dir="${3:-$HOME/Downloads}"

    local snapshot_name
    snapshot_name=$(basename "$snapshot_dir")

    local bundle_dir="$output_dir/${snapshot_name}-snapshot-bundle"
    mkdir -p "$bundle_dir"

    # Copy snapshot data
    cp -r "$snapshot_dir/tables" "$bundle_dir/"
    cp "$snapshot_dir/schema.sql" "$bundle_dir/schema-snapshot.sql"
    cp "$snapshot_dir/manifest.json" "$bundle_dir/"

    # Get live schema
    IFS='|' read -r db_type rest <<< "$db_info"
    local live_schema="$bundle_dir/schema-current.sql"

    case "$db_type" in
        sqlite)
            local db_path="$rest"
            local table_list
            table_list=$(_snapshot_list_tables_sqlite "$db_path")
            while IFS= read -r t; do
                [[ -n "$t" ]] && _snapshot_schema_sqlite "$db_path" "$t" >> "$live_schema"
                echo "" >> "$live_schema"
            done <<< "$table_list"
            ;;
        postgresql)
            IFS='|' read -r host port db_name user is_local password full_url <<< "$rest"
            local table_list
            table_list=$(_snapshot_list_tables_postgresql "$host" "$port" "$user" "$db_name" "$password")
            while IFS= read -r t; do
                [[ -n "$t" ]] && _snapshot_schema_postgresql "$host" "$port" "$user" "$db_name" "$password" "$t" >> "$live_schema"
                echo "" >> "$live_schema"
            done <<< "$table_list"
            ;;
        mysql)
            IFS='|' read -r host port db_name user is_local password full_url <<< "$rest"
            local table_list
            table_list=$(_snapshot_list_tables_mysql "$host" "$port" "$user" "$db_name" "$password")
            while IFS= read -r t; do
                [[ -n "$t" ]] && _snapshot_schema_mysql "$host" "$port" "$user" "$db_name" "$password" "$t" >> "$live_schema"
                echo "" >> "$live_schema"
            done <<< "$table_list"
            ;;
        mongodb)
            echo "# MongoDB — schemaless" > "$live_schema"
            ;;
    esac

    # Generate schema diff
    diff --unified=3 "$bundle_dir/schema-snapshot.sql" "$live_schema" > "$bundle_dir/schema.diff" 2>/dev/null || true

    # Generate LLM prompt
    local db_name_display
    db_name_display=$(grep '"db_name"' "$snapshot_dir/manifest.json" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

    cat > "$bundle_dir/llm-prompt.md" <<LLM_EOF
# Database Schema Migration Help

I have a database snapshot that I want to restore, but the schema has changed since the snapshot was taken.

## Database
- **Type:** $db_type
- **Name:** $db_name_display

## Schema at snapshot time
See: schema-snapshot.sql

## Current schema
See: schema-current.sql

## Schema diff
See: schema.diff

## What I need
Please generate SQL statements to restore the data from the snapshot into the current schema.
Handle any column additions, removals, or type changes. For new columns that don't exist
in the snapshot data, use sensible defaults (NULL if nullable, empty string, 0, etc.).

## Table dump files
The \`tables/\` directory contains per-table SQL dumps (gzipped). Decompress with:
\`\`\`
gunzip tables/tablename.sql.gz
\`\`\`

Then adapt the INSERT statements to match the current schema.
LLM_EOF

    # Generate README
    cat > "$bundle_dir/README.txt" <<README_EOF
Checkpoint Snapshot Bundle: $snapshot_name
==========================================

This bundle was generated because the database schema has changed since
the snapshot was taken. Direct restore may fail or cause data loss.

Files:
  manifest.json          Snapshot metadata
  schema-snapshot.sql    Schema at snapshot time
  schema-current.sql     Current live schema
  schema.diff            Differences between schemas
  llm-prompt.md          Ready-to-paste prompt for AI-assisted migration
  tables/                Per-table SQL/BSON dumps (gzipped)

Options:
  1. Paste llm-prompt.md + schema files into Claude/ChatGPT for help
  2. Manually edit the SQL dumps to match your current schema
  3. Roll back your schema to match the snapshot, then restore directly

Generated by Checkpoint v${CHECKPOINT_VERSION:-3.1.0}
README_EOF

    BUNDLE_PATH="$bundle_dir"
    echo "📦 Bundle saved to: $bundle_dir"
    return 0
}

# ==============================================================================
# PER-TABLE RESTORE
# ==============================================================================

# Restore a single SQLite table from snapshot dump
# $1=db_path $2=table_name $3=snapshot_dir
_snapshot_restore_table_sqlite() {
    local db_path="$1" table="$2" snapshot_dir="$3"
    local dump_file="$snapshot_dir/tables/${table}.sql.gz"

    if [[ ! -f "$dump_file" ]]; then
        echo "  Dump file not found for table '$table'" >&2
        return 1
    fi

    # Delete existing data, then replay the dump
    sqlite3 "$db_path" "DELETE FROM \"$table\";" 2>/dev/null || true
    local _err
    if _err=$(gunzip -c "$dump_file" | sqlite3 "$db_path" 2>&1); then
        return 0
    fi
    log_debug "SQLite restore failed for $table: $_err"
    return 1
}

# Restore a single PostgreSQL table from snapshot dump
# $1=host $2=port $3=user $4=database $5=password $6=table_name $7=snapshot_dir
_snapshot_restore_table_postgresql() {
    local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6" snapshot_dir="$7"
    local dump_file="$snapshot_dir/tables/${table}.sql.gz"

    if [[ ! -f "$dump_file" ]]; then
        echo "  Dump file not found for table '$table'" >&2
        return 1
    fi

    [[ -n "$password" ]] && export PGPASSWORD="$password"

    # Truncate then restore
    psql -h "$host" -p "$port" -U "$user" -c "TRUNCATE TABLE \"$table\" CASCADE;" "$database" 2>/dev/null || true
    gunzip -c "$dump_file" | psql -h "$host" -p "$port" -U "$user" -q "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"
    local rc=${PIPESTATUS[1]}
    unset PGPASSWORD 2>/dev/null || true
    return $rc
}

# Restore a single MySQL table from snapshot dump
# $1=host $2=port $3=user $4=database $5=password $6=table_name $7=snapshot_dir
_snapshot_restore_table_mysql() {
    local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6" snapshot_dir="$7"
    local dump_file="$snapshot_dir/tables/${table}.sql.gz"

    if [[ ! -f "$dump_file" ]]; then
        echo "  Dump file not found for table '$table'" >&2
        return 1
    fi

    [[ -n "$password" ]] && export MYSQL_PWD="$password"

    # Truncate then restore (mysqldump output includes DROP TABLE + CREATE TABLE)
    gunzip -c "$dump_file" | mysql -h "$host" -P "$port" -u "$user" "$database" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"
    local rc=${PIPESTATUS[1]}
    unset MYSQL_PWD 2>/dev/null || true
    return $rc
}

# Restore a single MongoDB collection from snapshot dump
# $1=host $2=port $3=database $4=user $5=password $6=full_url $7=collection_name $8=snapshot_dir
_snapshot_restore_table_mongodb() {
    local host="$1" port="$2" database="$3" user="${4:-}" password="${5:-}" full_url="${6:-}" collection="$7" snapshot_dir="$8"
    local dump_file="$snapshot_dir/tables/${collection}.bson.gz"

    if [[ ! -f "$dump_file" ]]; then
        echo "  Dump file not found for collection '$collection'" >&2
        return 1
    fi

    # Extract to temp dir
    local temp_dir
    temp_dir=$(mktemp -d -t "snapshot_mongorestore.XXXXXX") || return 1

    if ! tar -xzf "$dump_file" -C "$temp_dir" 2>/dev/null; then
        rm -rf "$temp_dir"
        return 1
    fi

    local -a mongo_args=()
    if [[ -n "$full_url" ]]; then
        mongo_args+=(--uri="$full_url")
    else
        mongo_args+=(--host "$host" --port "$port")
        [[ -n "$user" ]] && mongo_args+=(--username "$user")
        [[ -n "$password" ]] && mongo_args+=(--password "$password")
    fi
    mongo_args+=(--db "$database" --collection "$collection" --drop)

    # Find the bson file in extracted dump
    local bson_file
    bson_file=$(find "$temp_dir" -name "${collection}.bson" -type f 2>/dev/null | head -1)
    if [[ -z "$bson_file" ]]; then
        # Try any .bson file
        bson_file=$(find "$temp_dir" -name "*.bson" -type f 2>/dev/null | head -1)
    fi

    if [[ -z "$bson_file" ]]; then
        log_debug "No .bson file found in dump for collection $collection"
        rm -rf "$temp_dir"
        return 1
    fi

    local _err
    _err=$(mongorestore "${mongo_args[@]}" "$bson_file" 2>&1)
    local rc=$?

    rm -rf "$temp_dir"
    [[ $rc -ne 0 ]] && log_debug "MongoDB restore failed for $collection: $_err"
    return $rc
}

# Create a safety backup of a single table before restore
# $1=db_type $2..N=connection params + table_name (last arg) + backup_dir (second to last)
_snapshot_safety_backup_table() {
    local db_type="$1"
    shift

    case "$db_type" in
        sqlite)
            local db_path="$1" table="$2" safety_dir="$3"
            mkdir -p "$safety_dir"
            sqlite3 "$db_path" ".dump $table" 2>/dev/null | gzip > "$safety_dir/${table}.sql.gz"
            ;;
        postgresql)
            local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6" safety_dir="$7"
            mkdir -p "$safety_dir"
            [[ -n "$password" ]] && export PGPASSWORD="$password"
            pg_dump -h "$host" -p "$port" -U "$user" -t "$table" "$database" 2>/dev/null | gzip > "$safety_dir/${table}.sql.gz"
            unset PGPASSWORD 2>/dev/null || true
            ;;
        mysql)
            local host="$1" port="$2" user="$3" database="$4" password="${5:-}" table="$6" safety_dir="$7"
            mkdir -p "$safety_dir"
            [[ -n "$password" ]] && export MYSQL_PWD="$password"
            mysqldump -h "$host" -P "$port" -u "$user" "$database" "$table" 2>/dev/null | gzip > "$safety_dir/${table}.sql.gz"
            unset MYSQL_PWD 2>/dev/null || true
            ;;
        mongodb)
            local host="$1" port="$2" database="$3" user="${4:-}" password="${5:-}" full_url="${6:-}" collection="$7" safety_dir="$8"
            mkdir -p "$safety_dir"
            local temp_dir
            temp_dir=$(mktemp -d -t "snapshot_safety.XXXXXX") || return 1
            local -a args=()
            if [[ -n "$full_url" ]]; then
                args+=(--uri="$full_url")
            else
                args+=(--host "$host" --port "$port")
                [[ -n "$user" ]] && args+=(--username "$user")
                [[ -n "$password" ]] && args+=(--password "$password")
            fi
            args+=(--db "$database" --collection "$collection" --out "$temp_dir")
            mongodump "${args[@]}" 2>/dev/null
            tar -czf "$safety_dir/${collection}.bson.gz" -C "$temp_dir" . 2>/dev/null
            rm -rf "$temp_dir"
            ;;
    esac
}

# ==============================================================================
# MAIN RESTORE FUNCTION
# ==============================================================================

# Restore tables from a named snapshot
# $1 = snapshot directory
# $2 = db_info string (from detect_databases)
# $3 = comma-separated table names (empty = all tables)
# Returns: 0 on success, 1 on failure
# Output: progress to stdout
snapshot_restore() {
    local snapshot_dir="$1"
    local db_info="$2"
    local selected_tables="${3:-}"

    local snapshot_name
    snapshot_name=$(basename "$snapshot_dir")

    IFS='|' read -r db_type rest <<< "$db_info"

    local db_path="" host="" port="" db_name="" user="" password="" is_local="" full_url=""

    case "$db_type" in
        sqlite)
            db_path="$rest"
            db_name=$(basename "$db_path" | sed 's/\.[^.]*$//')
            host="local"
            port=0
            ;;
        postgresql|mysql)
            IFS='|' read -r host port db_name user is_local password full_url <<< "$rest"
            ;;
        mongodb)
            IFS='|' read -r host port db_name user password full_url <<< "$rest"
            ;;
        *)
            echo "❌ Unsupported database type for restore: $db_type" >&2
            return 1
            ;;
    esac

    # Get tables from snapshot manifest
    local all_tables=()
    while IFS= read -r t; do
        [[ -n "$t" ]] && all_tables+=("$t")
    done < <(snapshot_get_tables "$snapshot_dir")

    if [[ ${#all_tables[@]} -eq 0 ]]; then
        echo "❌ No tables found in snapshot manifest" >&2
        return 1
    fi

    # Filter to selected tables if specified
    local restore_tables=()
    if [[ -n "$selected_tables" ]]; then
        IFS=',' read -ra requested <<< "$selected_tables"
        for req in "${requested[@]}"; do
            req=$(echo "$req" | tr -d '[:space:]')
            local found=false
            for t in "${all_tables[@]}"; do
                if [[ "$t" == "$req" ]]; then
                    restore_tables+=("$t")
                    found=true
                    break
                fi
            done
            if [[ "$found" != "true" ]]; then
                echo "⚠ Table '$req' not found in snapshot (skipping)" >&2
            fi
        done
    else
        restore_tables=("${all_tables[@]}")
    fi

    if [[ ${#restore_tables[@]} -eq 0 ]]; then
        echo "❌ No valid tables to restore" >&2
        return 1
    fi

    local table_count=${#restore_tables[@]}
    local start_time=$SECONDS

    echo "🔄 Restoring $table_count table(s) from snapshot '$snapshot_name'..."
    echo ""

    # Safety backup directory
    local safety_dir="$snapshot_dir/pre-restore-$(date +%Y%m%d-%H%M%S)"

    # Disable foreign key constraints
    echo -n "   Disabling foreign key constraints... "
    case "$db_type" in
        sqlite)
            sqlite3 "$db_path" "PRAGMA foreign_keys=OFF;" 2>/dev/null
            ;;
        postgresql)
            [[ -n "$password" ]] && export PGPASSWORD="$password"
            psql -h "$host" -p "$port" -U "$user" -c "SET session_replication_role = 'replica';" "$db_name" 2>/dev/null
            ;;
        mysql)
            [[ -n "$password" ]] && export MYSQL_PWD="$password"
            mysql -h "$host" -P "$port" -u "$user" -e "SET GLOBAL FOREIGN_KEY_CHECKS=0;" "$db_name" 2>/dev/null
            ;;
        mongodb)
            # MongoDB has no FK constraints
            ;;
    esac
    echo "done"

    # Restore each table
    local idx=0
    local failed=0
    local restored=0

    for table in "${restore_tables[@]}"; do
        idx=$((idx + 1))
        echo -n "   [$idx/$table_count] $table — "

        # Safety backup
        echo -n "backup... "
        case "$db_type" in
            sqlite)
                _snapshot_safety_backup_table sqlite "$db_path" "$table" "$safety_dir"
                ;;
            postgresql)
                _snapshot_safety_backup_table postgresql "$host" "$port" "$user" "$db_name" "$password" "$table" "$safety_dir"
                ;;
            mysql)
                _snapshot_safety_backup_table mysql "$host" "$port" "$user" "$db_name" "$password" "$table" "$safety_dir"
                ;;
            mongodb)
                _snapshot_safety_backup_table mongodb "$host" "$port" "$db_name" "$user" "$password" "$full_url" "$table" "$safety_dir"
                ;;
        esac

        # Restore
        echo -n "restore... "
        local restore_ok=false
        case "$db_type" in
            sqlite)
                _snapshot_restore_table_sqlite "$db_path" "$table" "$snapshot_dir" && restore_ok=true
                ;;
            postgresql)
                _snapshot_restore_table_postgresql "$host" "$port" "$user" "$db_name" "$password" "$table" "$snapshot_dir" && restore_ok=true
                ;;
            mysql)
                _snapshot_restore_table_mysql "$host" "$port" "$user" "$db_name" "$password" "$table" "$snapshot_dir" && restore_ok=true
                ;;
            mongodb)
                _snapshot_restore_table_mongodb "$host" "$port" "$db_name" "$user" "$password" "$full_url" "$table" "$snapshot_dir" && restore_ok=true
                ;;
        esac

        if [[ "$restore_ok" == "true" ]]; then
            restored=$((restored + 1))
            echo "✓"
        else
            failed=$((failed + 1))
            echo "FAILED"
        fi
    done

    # Re-enable foreign key constraints
    echo -n "   Re-enabling foreign key constraints... "
    case "$db_type" in
        sqlite)
            sqlite3 "$db_path" "PRAGMA foreign_keys=ON;" 2>/dev/null
            ;;
        postgresql)
            [[ -n "$password" ]] && export PGPASSWORD="$password"
            psql -h "$host" -p "$port" -U "$user" -c "SET session_replication_role = 'origin';" "$db_name" 2>/dev/null
            unset PGPASSWORD 2>/dev/null || true
            ;;
        mysql)
            [[ -n "$password" ]] && export MYSQL_PWD="$password"
            mysql -h "$host" -P "$port" -u "$user" -e "SET GLOBAL FOREIGN_KEY_CHECKS=1;" "$db_name" 2>/dev/null
            unset MYSQL_PWD 2>/dev/null || true
            ;;
        mongodb)
            # No-op
            ;;
    esac
    echo "done"

    local duration=$(( SECONDS - start_time ))
    echo ""

    if [[ $failed -eq 0 ]]; then
        echo "✅ Restored $restored/$table_count tables from '$snapshot_name' (${duration}s)"
        echo "   Safety backup: $safety_dir"
        return 0
    elif [[ $failed -eq $table_count ]]; then
        echo "❌ All $table_count tables failed to restore"
        echo "   Safety backup preserved: $safety_dir"
        return 1
    else
        echo "⚠ Restored $restored/$table_count tables ($failed failed) (${duration}s)"
        echo "   Safety backup: $safety_dir"
        return 1
    fi
}
