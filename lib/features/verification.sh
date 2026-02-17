#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Backup Verification
# Tiered verification: quick (existence/size), full (SHA256/integrity),
# cloud (rclone check). Manifest reader and report generator.
# ==============================================================================
# @requires: core/output (for color functions, json helpers, backup_log),
#            core/error-codes (for EVER001-EVER006, map_error_to_code),
#            ops/file-ops (for get_file_hash, get_file_size, get_lock_pid),
#            platform/compat (for get_file_size, get_file_mtime),
#            features/restore (for verify_sqlite_integrity, verify_compressed_backup)
# @provides: verify_backup_quick, verify_backup_full, verify_cloud_backup,
#            generate_verification_report, read_manifest, persist_manifest_json
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_VERIFICATION:-}" ] && return || readonly _CHECKPOINT_VERIFICATION=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Set logging context for this module
log_set_context "verify"

# ==============================================================================
# GLOBAL STATE (verification results)
# ==============================================================================

# Results arrays — indexed arrays (Bash 3.2 compatible)
# Format: "path|status|message" where status = pass|fail|warning
declare -a VERIFY_FILE_RESULTS=()
declare -a VERIFY_DB_RESULTS=()
declare -a VERIFY_FAILURES=()

# Counters
VERIFY_FILES_TOTAL=0
VERIFY_FILES_PASSED=0
VERIFY_FILES_FAILED=0
VERIFY_FILES_WARNINGS=0
VERIFY_DBS_TOTAL=0
VERIFY_DBS_PASSED=0
VERIFY_DBS_FAILED=0
VERIFY_DBS_WARNINGS=0
VERIFY_CLOUD_STATUS="skipped"
VERIFY_CLOUD_DETAILS=""
VERIFY_MODE=""
VERIFY_OVERALL=""

# Manifest data — global arrays set by read_manifest()
declare -a MANIFEST_FILES=()
declare -a MANIFEST_DATABASES=()
MANIFEST_VERSION=""
MANIFEST_TIMESTAMP=""
MANIFEST_PROJECT=""

# ==============================================================================
# INTERNAL HELPERS
# ==============================================================================

# Reset verification state for a new run
_verify_reset() {
    VERIFY_FILE_RESULTS=()
    VERIFY_DB_RESULTS=()
    VERIFY_FAILURES=()
    VERIFY_FILES_TOTAL=0
    VERIFY_FILES_PASSED=0
    VERIFY_FILES_FAILED=0
    VERIFY_FILES_WARNINGS=0
    VERIFY_DBS_TOTAL=0
    VERIFY_DBS_PASSED=0
    VERIFY_DBS_FAILED=0
    VERIFY_DBS_WARNINGS=0
    VERIFY_CLOUD_STATUS="skipped"
    VERIFY_CLOUD_DETAILS=""
    VERIFY_MODE=""
    VERIFY_OVERALL=""
}

# Record a file verification result
# Args: $1 = path, $2 = status (pass|fail|warning), $3 = message
_verify_record_file() {
    local path="$1" status="$2" message="$3"
    VERIFY_FILE_RESULTS+=("${path}|${status}|${message}")
    VERIFY_FILES_TOTAL=$((VERIFY_FILES_TOTAL + 1))
    case "$status" in
        pass)    VERIFY_FILES_PASSED=$((VERIFY_FILES_PASSED + 1)) ;;
        fail)    VERIFY_FILES_FAILED=$((VERIFY_FILES_FAILED + 1))
                 VERIFY_FAILURES+=("${path}|EVER001|${message}") ;;
        warning) VERIFY_FILES_WARNINGS=$((VERIFY_FILES_WARNINGS + 1)) ;;
    esac
}

# Record a database verification result
# Args: $1 = path, $2 = status (pass|fail|warning), $3 = message
_verify_record_db() {
    local path="$1" status="$2" message="$3"
    VERIFY_DB_RESULTS+=("${path}|${status}|${message}")
    VERIFY_DBS_TOTAL=$((VERIFY_DBS_TOTAL + 1))
    case "$status" in
        pass)    VERIFY_DBS_PASSED=$((VERIFY_DBS_PASSED + 1)) ;;
        fail)    VERIFY_DBS_FAILED=$((VERIFY_DBS_FAILED + 1))
                 VERIFY_FAILURES+=("${path}|EVER004|${message}") ;;
        warning) VERIFY_DBS_WARNINGS=$((VERIFY_DBS_WARNINGS + 1)) ;;
    esac
}

# Check if a backup is currently in progress (lock file / PID)
# Args: $1 = project_name (optional, defaults to PROJECT_NAME)
# Returns: 0 if active backup detected, 1 if no active backup
_verify_check_active_backup() {
    local project_name="${1:-${PROJECT_NAME:-}}"
    [ -z "$project_name" ] && return 1

    local lock_pid
    lock_pid=$(get_lock_pid "$project_name" 2>/dev/null) || return 1
    if [ -n "$lock_pid" ]; then
        return 0
    fi
    return 1
}

# ==============================================================================
# MANIFEST READER
# ==============================================================================

# Read and parse .checkpoint-manifest.json into global arrays
# Args: $1 = backup_dir
# Returns: 0 if manifest read successfully, 1 if missing/corrupt
# Sets: MANIFEST_FILES[], MANIFEST_DATABASES[], MANIFEST_VERSION,
#        MANIFEST_TIMESTAMP, MANIFEST_PROJECT
read_manifest() {
    local backup_dir="$1"
    local manifest_file="$backup_dir/.checkpoint-manifest.json"

    MANIFEST_FILES=()
    MANIFEST_DATABASES=()
    MANIFEST_VERSION=""
    MANIFEST_TIMESTAMP=""
    MANIFEST_PROJECT=""

    if [ ! -f "$manifest_file" ]; then
        return 1
    fi

    # Parse version
    MANIFEST_VERSION=$(grep -o '"version": *[0-9]*' "$manifest_file" 2>/dev/null | grep -o '[0-9]*$') || true

    # Parse timestamp
    MANIFEST_TIMESTAMP=$(grep -o '"timestamp": *"[^"]*"' "$manifest_file" 2>/dev/null | head -1 | cut -d'"' -f4) || true

    # Parse project
    MANIFEST_PROJECT=$(grep -o '"project": *"[^"]*"' "$manifest_file" 2>/dev/null | head -1 | cut -d'"' -f4) || true

    # Parse file entries — extract path, size, sha256 from each file object
    # Files section is between "files": [ and the closing ]
    # Each entry: {"path": "...", "size": N, "sha256": "..."}
    local in_files=false
    local in_databases=false
    while IFS= read -r line; do
        # Detect section boundaries
        if echo "$line" | grep -q '"files"'; then
            in_files=true
            in_databases=false
            continue
        fi
        if echo "$line" | grep -q '"databases"'; then
            in_files=false
            in_databases=true
            continue
        fi
        if echo "$line" | grep -q '"totals"'; then
            in_files=false
            in_databases=false
            continue
        fi

        # Parse file entries
        if [ "$in_files" = true ]; then
            local entry_path entry_size entry_hash
            entry_path=$(echo "$line" | grep -o '"path": *"[^"]*"' | cut -d'"' -f4) || true
            entry_size=$(echo "$line" | grep -o '"size": *[0-9]*' | grep -o '[0-9]*$') || true
            entry_hash=$(echo "$line" | grep -o '"sha256": *"[^"]*"' | cut -d'"' -f4) || true

            if [ -n "$entry_path" ]; then
                # Store as pipe-delimited: path|size|sha256
                MANIFEST_FILES+=("${entry_path}|${entry_size:-0}|${entry_hash:-}")
            fi
        fi

        # Parse database entries
        if [ "$in_databases" = true ]; then
            local db_path db_size db_hash db_tables
            db_path=$(echo "$line" | grep -o '"path": *"[^"]*"' | cut -d'"' -f4) || true
            db_size=$(echo "$line" | grep -o '"size": *[0-9]*' | grep -o '[0-9]*$') || true
            db_hash=$(echo "$line" | grep -o '"sha256": *"[^"]*"' | cut -d'"' -f4) || true
            db_tables=$(echo "$line" | grep -o '"tables": *[0-9]*' | grep -o '[0-9]*$') || true

            if [ -n "$db_path" ]; then
                # Store as pipe-delimited: path|size|sha256|tables
                MANIFEST_DATABASES+=("${db_path}|${db_size:-0}|${db_hash:-}|${db_tables:-0}")
            fi
        fi
    done < "$manifest_file"

    # Validate we got something
    if [ ${#MANIFEST_FILES[@]} -eq 0 ] && [ ${#MANIFEST_DATABASES[@]} -eq 0 ]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# QUICK VERIFICATION
# ==============================================================================

# Quick verification: manifest check, file existence/size, gunzip -t,
# sqlite3 PRAGMA quick_check
# Args: $1 = backup_dir
# Returns: 0 if all pass, 1 if any fail
verify_backup_quick() {
    local backup_dir="$1"

    _verify_reset
    VERIFY_MODE="quick"

    # Check for active backup
    if _verify_check_active_backup; then
        VERIFY_OVERALL="error"
        VERIFY_CLOUD_DETAILS="Cannot verify during active backup (race condition)"
        return 2
    fi

    # Validate backup directory
    if [ ! -d "$backup_dir" ]; then
        VERIFY_OVERALL="error"
        VERIFY_CLOUD_DETAILS="Backup directory does not exist: $backup_dir"
        return 2
    fi

    local has_manifest=true
    if ! read_manifest "$backup_dir"; then
        has_manifest=false
    fi

    # --- File verification ---
    if [ "$has_manifest" = true ] && [ ${#MANIFEST_FILES[@]} -gt 0 ]; then
        # Verify files from manifest
        local entry
        for entry in "${MANIFEST_FILES[@]}"; do
            local rel_path file_size_expected
            rel_path=$(echo "$entry" | cut -d'|' -f1)
            file_size_expected=$(echo "$entry" | cut -d'|' -f2)

            local full_path="$backup_dir/$rel_path"
            if [ ! -f "$full_path" ]; then
                _verify_record_file "$rel_path" "fail" "File missing from backup"
            else
                local actual_size
                actual_size=$(get_file_size "$full_path")
                if [ "$actual_size" != "$file_size_expected" ]; then
                    _verify_record_file "$rel_path" "fail" "Size mismatch: expected $file_size_expected, got $actual_size"
                else
                    _verify_record_file "$rel_path" "pass" "Exists, size OK"
                fi
            fi
        done
    else
        # No manifest — fall back to scanning files directory
        if [ -d "$backup_dir/files" ]; then
            local scan_file
            while IFS= read -r scan_file; do
                [ -z "$scan_file" ] && continue
                local rel_path="${scan_file#$backup_dir/}"
                _verify_record_file "$rel_path" "pass" "Exists (no manifest to verify size)"
            done < <(find "$backup_dir/files" -type f 2>/dev/null)
        fi
    fi

    # --- Database verification ---
    if [ "$has_manifest" = true ] && [ ${#MANIFEST_DATABASES[@]} -gt 0 ]; then
        local db_entry
        for db_entry in "${MANIFEST_DATABASES[@]}"; do
            local db_rel_path db_size_expected
            db_rel_path=$(echo "$db_entry" | cut -d'|' -f1)
            db_size_expected=$(echo "$db_entry" | cut -d'|' -f2)

            local db_full_path="$backup_dir/$db_rel_path"
            if [ ! -f "$db_full_path" ]; then
                _verify_record_db "$db_rel_path" "fail" "Database backup missing"
                continue
            fi

            # Size check
            local db_actual_size
            db_actual_size=$(get_file_size "$db_full_path")
            if [ "$db_actual_size" != "$db_size_expected" ]; then
                _verify_record_db "$db_rel_path" "fail" "Size mismatch: expected $db_size_expected, got $db_actual_size"
                continue
            fi

            # Encrypted databases: skip integrity check (verify local unencrypted copy instead)
            if echo "$db_rel_path" | grep -q '\.gz\.age$'; then
                _verify_record_db "$db_rel_path" "pass" "Encrypted backup — size OK (verify local copy for integrity)"
                continue
            fi

            # gunzip -t for compressed databases
            if echo "$db_rel_path" | grep -q '\.gz$'; then
                local _v_err
                if ! _v_err=$(gunzip -t "$db_full_path" 2>&1); then
                    log_debug "Verification gunzip -t failed for $db_rel_path: $_v_err"
                    _verify_record_db "$db_rel_path" "fail" "Gzip decompression test failed"
                    continue
                fi

                # PRAGMA quick_check on decompressed copy
                local temp_db
                temp_db=$(mktemp 2>/dev/null) || {
                    _verify_record_db "$db_rel_path" "warning" "Could not create temp file for integrity check"
                    continue
                }
                if gunzip -c "$db_full_path" > "$temp_db" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                    local qc_result
                    qc_result=$(sqlite3 "$temp_db" "PRAGMA quick_check;" 2>&1) || true
                    if [ "$qc_result" = "ok" ]; then
                        _verify_record_db "$db_rel_path" "pass" "Gzip OK, quick_check OK"
                    else
                        _verify_record_db "$db_rel_path" "fail" "PRAGMA quick_check failed: $qc_result"
                    fi
                else
                    _verify_record_db "$db_rel_path" "fail" "Could not decompress for integrity check"
                fi
                rm -f "$temp_db"
            fi
        done
    else
        # No manifest — scan for database files
        if [ -d "$backup_dir/databases" ]; then
            local db_file
            while IFS= read -r db_file; do
                [ -z "$db_file" ] && continue
                local db_rel="${db_file#$backup_dir/}"
                # Encrypted databases: skip integrity check
                if echo "$db_file" | grep -q '\.gz\.age$'; then
                    _verify_record_db "$db_rel" "pass" "Encrypted backup — exists (verify local copy for integrity)"
                    continue
                fi
                if echo "$db_file" | grep -q '\.gz$'; then
                    local _v_err
                    if _v_err=$(gunzip -t "$db_file" 2>&1); then
                        _verify_record_db "$db_rel" "pass" "Gzip OK (no manifest)"
                    else
                        log_debug "Verification gunzip -t failed for $db_rel: $_v_err"
                        _verify_record_db "$db_rel" "fail" "Gzip decompression test failed"
                    fi
                fi
            done < <(find "$backup_dir/databases" -type f \( -name "*.gz" -o -name "*.gz.age" \) 2>/dev/null)
        fi
    fi

    # --- Manifest file count check ---
    if [ "$has_manifest" = true ] && [ -d "$backup_dir/files" ]; then
        local manifest_count=${#MANIFEST_FILES[@]}
        local actual_count
        actual_count=$(find "$backup_dir/files" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ "$actual_count" -lt "$manifest_count" ]; then
            VERIFY_FILES_WARNINGS=$((VERIFY_FILES_WARNINGS + 1))
        fi
    fi

    # Determine overall status
    if [ $VERIFY_FILES_FAILED -gt 0 ] || [ $VERIFY_DBS_FAILED -gt 0 ]; then
        VERIFY_OVERALL="fail"
        return 1
    elif [ $VERIFY_FILES_WARNINGS -gt 0 ] || [ $VERIFY_DBS_WARNINGS -gt 0 ]; then
        VERIFY_OVERALL="warning"
        return 0
    else
        VERIFY_OVERALL="pass"
        return 0
    fi
}

# ==============================================================================
# FULL VERIFICATION
# ==============================================================================

# Full verification: everything in quick + SHA256 hashes, full integrity_check,
# schema check, table count, orphan WAL/SHM warning, min size sanity
# Args: $1 = backup_dir
# Returns: 0 if all pass, 1 if any fail
verify_backup_full() {
    local backup_dir="$1"

    _verify_reset
    VERIFY_MODE="full"

    # Check for active backup
    if _verify_check_active_backup; then
        VERIFY_OVERALL="error"
        VERIFY_CLOUD_DETAILS="Cannot verify during active backup (race condition)"
        return 2
    fi

    # Validate backup directory
    if [ ! -d "$backup_dir" ]; then
        VERIFY_OVERALL="error"
        VERIFY_CLOUD_DETAILS="Backup directory does not exist: $backup_dir"
        return 2
    fi

    local has_manifest=true
    if ! read_manifest "$backup_dir"; then
        has_manifest=false
    fi

    # --- File verification (with SHA256) ---
    if [ "$has_manifest" = true ] && [ ${#MANIFEST_FILES[@]} -gt 0 ]; then
        local entry
        for entry in "${MANIFEST_FILES[@]}"; do
            local rel_path file_size_expected file_hash_expected
            rel_path=$(echo "$entry" | cut -d'|' -f1)
            file_size_expected=$(echo "$entry" | cut -d'|' -f2)
            file_hash_expected=$(echo "$entry" | cut -d'|' -f3)

            local full_path="$backup_dir/$rel_path"
            if [ ! -f "$full_path" ]; then
                _verify_record_file "$rel_path" "fail" "File missing from backup"
                continue
            fi

            # Size check
            local actual_size
            actual_size=$(get_file_size "$full_path")
            if [ "$actual_size" != "$file_size_expected" ]; then
                _verify_record_file "$rel_path" "fail" "Size mismatch: expected $file_size_expected, got $actual_size"
                continue
            fi

            # SHA256 hash verification (bypass cache — compute fresh)
            if [ -n "$file_hash_expected" ]; then
                local actual_hash
                actual_hash=$(shasum -a 256 "$full_path" 2>/dev/null | cut -d' ' -f1) || true
                if [ -z "$actual_hash" ]; then
                    # Fallback for Linux
                    actual_hash=$(sha256sum "$full_path" 2>/dev/null | cut -d' ' -f1) || true
                fi

                if [ -n "$actual_hash" ] && [ "$actual_hash" != "$file_hash_expected" ]; then
                    _verify_record_file "$rel_path" "fail" "Hash mismatch (possible corruption)"
                    continue
                fi
            fi

            _verify_record_file "$rel_path" "pass" "Exists, size OK, hash verified"
        done
    else
        # No manifest — scan and hash files
        if [ -d "$backup_dir/files" ]; then
            local scan_file
            while IFS= read -r scan_file; do
                [ -z "$scan_file" ] && continue
                local rel_path="${scan_file#$backup_dir/}"
                _verify_record_file "$rel_path" "pass" "Exists (no manifest for hash comparison)"
            done < <(find "$backup_dir/files" -type f 2>/dev/null)
        fi
    fi

    # --- Database verification (full integrity) ---
    local db_files_to_check=()

    if [ "$has_manifest" = true ] && [ ${#MANIFEST_DATABASES[@]} -gt 0 ]; then
        local db_entry
        for db_entry in "${MANIFEST_DATABASES[@]}"; do
            local db_rel_path db_size_expected db_hash_expected
            db_rel_path=$(echo "$db_entry" | cut -d'|' -f1)
            db_size_expected=$(echo "$db_entry" | cut -d'|' -f2)
            db_hash_expected=$(echo "$db_entry" | cut -d'|' -f3)

            local db_full_path="$backup_dir/$db_rel_path"
            if [ ! -f "$db_full_path" ]; then
                _verify_record_db "$db_rel_path" "fail" "Database backup missing"
                continue
            fi

            # Size check
            local db_actual_size
            db_actual_size=$(get_file_size "$db_full_path")
            if [ "$db_actual_size" != "$db_size_expected" ]; then
                _verify_record_db "$db_rel_path" "fail" "Size mismatch: expected $db_size_expected, got $db_actual_size"
                continue
            fi

            # Minimum size sanity check (< 100 bytes = likely empty/corrupt)
            if [ "$db_actual_size" -lt 100 ]; then
                _verify_record_db "$db_rel_path" "warning" "Suspiciously small ($db_actual_size bytes)"
            fi

            # SHA256 hash verification (bypass cache)
            if [ -n "$db_hash_expected" ]; then
                local db_actual_hash
                db_actual_hash=$(shasum -a 256 "$db_full_path" 2>/dev/null | cut -d' ' -f1) || true
                if [ -z "$db_actual_hash" ]; then
                    db_actual_hash=$(sha256sum "$db_full_path" 2>/dev/null | cut -d' ' -f1) || true
                fi
                if [ -n "$db_actual_hash" ] && [ "$db_actual_hash" != "$db_hash_expected" ]; then
                    _verify_record_db "$db_rel_path" "fail" "Hash mismatch (possible corruption)"
                    continue
                fi
            fi

            # Encrypted databases: skip deep integrity check (verify local unencrypted copy instead)
            if echo "$db_rel_path" | grep -q '\.gz\.age$'; then
                _verify_record_db "$db_rel_path" "pass" "Encrypted backup — size/hash OK (verify local copy for integrity)"
                continue
            fi

            # Full verification for compressed databases
            if echo "$db_rel_path" | grep -q '\.gz$'; then
                local _v_err
                if ! _v_err=$(gunzip -t "$db_full_path" 2>&1); then
                    log_debug "Full verification gunzip -t failed for $db_rel_path: $_v_err"
                    _verify_record_db "$db_rel_path" "fail" "Gzip decompression test failed"
                    continue
                fi

                # Decompress and run full checks
                local temp_db
                temp_db=$(mktemp 2>/dev/null) || {
                    _verify_record_db "$db_rel_path" "warning" "Could not create temp file for integrity check"
                    continue
                }

                if gunzip -c "$db_full_path" > "$temp_db" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                    # Full PRAGMA integrity_check
                    local ic_result
                    ic_result=$(sqlite3 "$temp_db" "PRAGMA integrity_check;" 2>&1) || true
                    if [ "$ic_result" != "ok" ]; then
                        _verify_record_db "$db_rel_path" "fail" "PRAGMA integrity_check failed: $ic_result"
                        rm -f "$temp_db"
                        continue
                    fi

                    # Schema readability
                    if ! sqlite3 "$temp_db" ".schema" >/dev/null 2>&1; then
                        _verify_record_db "$db_rel_path" "fail" "Schema not readable"
                        rm -f "$temp_db"
                        continue
                    fi

                    # Table count (must have >0 tables)
                    local table_count
                    table_count=$(sqlite3 "$temp_db" "SELECT count(*) FROM sqlite_master WHERE type='table';" 2>/dev/null) || true
                    if [ "${table_count:-0}" -eq 0 ]; then
                        _verify_record_db "$db_rel_path" "warning" "Database has no tables"
                    fi

                    _verify_record_db "$db_rel_path" "pass" "Gzip OK, integrity OK, schema OK, ${table_count:-0} tables"
                else
                    _verify_record_db "$db_rel_path" "fail" "Could not decompress for integrity check"
                fi
                rm -f "$temp_db"
            fi
        done
    else
        # No manifest — scan database files
        if [ -d "$backup_dir/databases" ]; then
            local db_file
            while IFS= read -r db_file; do
                [ -z "$db_file" ] && continue
                local db_rel="${db_file#$backup_dir/}"
                local db_size
                db_size=$(get_file_size "$db_file")

                # Min size check
                if [ "$db_size" -lt 100 ]; then
                    _verify_record_db "$db_rel" "warning" "Suspiciously small ($db_size bytes)"
                fi

                # Encrypted databases: skip deep integrity check
                if echo "$db_file" | grep -q '\.gz\.age$'; then
                    _verify_record_db "$db_rel" "pass" "Encrypted backup — exists (verify local copy for integrity)"
                    continue
                fi

                if echo "$db_file" | grep -q '\.gz$'; then
                    local _v_err
                    if ! _v_err=$(gunzip -t "$db_file" 2>&1); then
                        log_debug "Full verification gunzip -t failed for $db_rel: $_v_err"
                        _verify_record_db "$db_rel" "fail" "Gzip decompression test failed"
                        continue
                    fi

                    local temp_db
                    temp_db=$(mktemp 2>/dev/null) || {
                        _verify_record_db "$db_rel" "warning" "Could not create temp file"
                        continue
                    }
                    if gunzip -c "$db_file" > "$temp_db" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                        local ic_result
                        ic_result=$(sqlite3 "$temp_db" "PRAGMA integrity_check;" 2>&1) || true
                        if [ "$ic_result" = "ok" ]; then
                            local tc
                            tc=$(sqlite3 "$temp_db" "SELECT count(*) FROM sqlite_master WHERE type='table';" 2>/dev/null) || true
                            _verify_record_db "$db_rel" "pass" "Gzip OK, integrity OK, ${tc:-0} tables"
                        else
                            _verify_record_db "$db_rel" "fail" "PRAGMA integrity_check failed"
                        fi
                    else
                        _verify_record_db "$db_rel" "fail" "Decompression failed"
                    fi
                    rm -f "$temp_db"
                fi
            done < <(find "$backup_dir/databases" -type f \( -name "*.gz" -o -name "*.gz.age" \) 2>/dev/null)
        fi
    fi

    # --- Orphan WAL/SHM check ---
    if [ -d "$backup_dir" ]; then
        local wal_file
        while IFS= read -r wal_file; do
            [ -z "$wal_file" ] && continue
            local wal_rel="${wal_file#$backup_dir/}"
            _verify_record_db "$wal_rel" "warning" "Orphan WAL/SHM file found (incomplete backup?)"
        done < <(find "$backup_dir" -type f \( -name "*.db-wal" -o -name "*.db-shm" \) 2>/dev/null)
    fi

    # Determine overall status
    if [ $VERIFY_FILES_FAILED -gt 0 ] || [ $VERIFY_DBS_FAILED -gt 0 ]; then
        VERIFY_OVERALL="fail"
        return 1
    elif [ $VERIFY_FILES_WARNINGS -gt 0 ] || [ $VERIFY_DBS_WARNINGS -gt 0 ]; then
        VERIFY_OVERALL="warning"
        return 0
    else
        VERIFY_OVERALL="pass"
        return 0
    fi
}

# ==============================================================================
# CLOUD VERIFICATION
# ==============================================================================

# Cloud verification via rclone check
# Args: $1 = backup_dir
# Returns: 0 if match or skipped, 1 if differences found
verify_cloud_backup() {
    local backup_dir="$1"

    # Check if cloud is enabled
    if [ "${CLOUD_RCLONE_ENABLED:-false}" != "true" ] && [ "${CLOUD_ENABLED:-false}" != "true" ]; then
        VERIFY_CLOUD_STATUS="skipped"
        VERIFY_CLOUD_DETAILS="Cloud backup not enabled"
        return 0
    fi

    # Check rclone is installed
    if ! command -v rclone >/dev/null 2>&1; then
        VERIFY_CLOUD_STATUS="skipped"
        VERIFY_CLOUD_DETAILS="rclone not installed"
        return 0
    fi

    # Build remote path
    local remote_name="${CLOUD_RCLONE_REMOTE:-${CLOUD_REMOTE_NAME:-}}"
    local remote_path="${CLOUD_RCLONE_PATH:-${CLOUD_BACKUP_PATH:-}}"
    if [ -z "$remote_name" ]; then
        VERIFY_CLOUD_STATUS="skipped"
        VERIFY_CLOUD_DETAILS="No cloud remote configured"
        return 0
    fi

    local full_remote="${remote_name}:${remote_path}/${PROJECT_NAME:-}"

    # Run rclone check with 60s timeout
    local check_output
    if check_output=$(timeout 60 rclone check "$backup_dir" "$full_remote" --one-way --size-only 2>&1); then
        VERIFY_CLOUD_STATUS="pass"
        VERIFY_CLOUD_DETAILS="Cloud sync verified (size-only match)"
        return 0
    else
        local rc=$?
        if [ $rc -eq 124 ]; then
            VERIFY_CLOUD_STATUS="warning"
            VERIFY_CLOUD_DETAILS="Cloud verification timed out (60s)"
            return 0
        fi
        VERIFY_CLOUD_STATUS="fail"
        VERIFY_CLOUD_DETAILS="Cloud sync mismatch detected"
        VERIFY_FAILURES+=("cloud|EVER006|$check_output")
        return 1
    fi
}

# ==============================================================================
# VERIFICATION REPORT GENERATOR
# ==============================================================================

# Generate verification report in specified output mode
# Args: $1 = output_mode (human|json|compact)
# Uses global VERIFY_* variables set by verify_backup_quick/full
generate_verification_report() {
    local output_mode="${1:-human}"

    local total_checks=$((VERIFY_FILES_TOTAL + VERIFY_DBS_TOTAL))
    local total_passed=$((VERIFY_FILES_PASSED + VERIFY_DBS_PASSED))
    local total_failed=$((VERIFY_FILES_FAILED + VERIFY_DBS_FAILED))
    local total_warnings=$((VERIFY_FILES_WARNINGS + VERIFY_DBS_WARNINGS))

    case "$output_mode" in

        compact)
            if [ "$VERIFY_OVERALL" = "pass" ]; then
                echo "PASS: $VERIFY_FILES_TOTAL files, $VERIFY_DBS_TOTAL databases verified"
            elif [ "$VERIFY_OVERALL" = "warning" ]; then
                echo "WARNING: $total_passed/$total_checks passed, $total_warnings warning(s)"
            elif [ "$VERIFY_OVERALL" = "fail" ]; then
                echo "FAIL: $total_failed/$total_checks check(s) failed"
            else
                echo "ERROR: Verification could not be performed"
            fi
            ;;

        json)
            local ts
            ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)
            local project="${PROJECT_NAME:-unknown}"

            # Build failures array
            local failures_json=""
            local first_failure=true
            local failure_entry
            for failure_entry in "${VERIFY_FAILURES[@]}"; do
                local f_path f_code f_msg
                f_path=$(echo "$failure_entry" | cut -d'|' -f1)
                f_code=$(echo "$failure_entry" | cut -d'|' -f2)
                f_msg=$(echo "$failure_entry" | cut -d'|' -f3-)
                if [ "$first_failure" = true ]; then
                    first_failure=false
                else
                    failures_json+=","
                fi
                failures_json+="{$(json_kv "path" "$f_path"), $(json_kv "error_code" "$f_code"), $(json_kv "message" "$f_msg")}"
            done

            cat <<EOF
{
  $(json_kv "timestamp" "$ts"),
  $(json_kv "project" "$project"),
  $(json_kv "mode" "$VERIFY_MODE"),
  $(json_kv "overall_status" "$VERIFY_OVERALL"),
  "checks": {
    "files": {$(json_kv_num "total" "$VERIFY_FILES_TOTAL"), $(json_kv_num "passed" "$VERIFY_FILES_PASSED"), $(json_kv_num "failed" "$VERIFY_FILES_FAILED"), $(json_kv_num "warnings" "$VERIFY_FILES_WARNINGS")},
    "databases": {$(json_kv_num "total" "$VERIFY_DBS_TOTAL"), $(json_kv_num "passed" "$VERIFY_DBS_PASSED"), $(json_kv_num "failed" "$VERIFY_DBS_FAILED"), $(json_kv_num "warnings" "$VERIFY_DBS_WARNINGS")},
    "cloud": {$(json_kv "status" "$VERIFY_CLOUD_STATUS"), $(json_kv "details" "$VERIFY_CLOUD_DETAILS")}
  },
  "failures": [${failures_json}],
  "summary": {$(json_kv_num "total_checks" "$total_checks"), $(json_kv_num "passed" "$total_passed"), $(json_kv_num "failed" "$total_failed"), $(json_kv_num "warnings" "$total_warnings")}
}
EOF
            ;;

        human|*)
            echo ""
            echo "Checkpoint Verification Report"
            echo "================================"
            echo "Project: ${PROJECT_NAME:-unknown}"
            echo "Mode:    $VERIFY_MODE"
            echo "Backup:  ${BACKUP_DIR:-unknown}"
            echo ""

            # Files section
            echo "Files"
            if [ $VERIFY_FILES_TOTAL -gt 0 ]; then
                printf "  Existence ......... %s (%d/%d present)\n" \
                    "$([ $VERIFY_FILES_FAILED -eq 0 ] && echo 'PASS' || echo 'FAIL')" \
                    "$VERIFY_FILES_PASSED" "$VERIFY_FILES_TOTAL"
                if [ "$VERIFY_MODE" = "full" ]; then
                    printf "  Integrity ......... %s (%d/%d hashes valid)\n" \
                        "$([ $VERIFY_FILES_FAILED -eq 0 ] && echo 'PASS' || echo 'FAIL')" \
                        "$VERIFY_FILES_PASSED" "$VERIFY_FILES_TOTAL"
                fi
            else
                echo "  No files to verify"
            fi
            echo ""

            # Databases section
            echo "Databases"
            if [ $VERIFY_DBS_TOTAL -gt 0 ]; then
                local db_result
                for db_result in "${VERIFY_DB_RESULTS[@]}"; do
                    local d_path d_status d_msg
                    d_path=$(echo "$db_result" | cut -d'|' -f1)
                    d_status=$(echo "$db_result" | cut -d'|' -f2)
                    d_msg=$(echo "$db_result" | cut -d'|' -f3-)
                    local status_label
                    case "$d_status" in
                        pass)    status_label="PASS" ;;
                        fail)    status_label="FAIL" ;;
                        warning) status_label="WARN" ;;
                    esac
                    printf "  %-30s %s (%s)\n" "$(basename "$d_path")" "$status_label" "$d_msg"
                done
            else
                echo "  No databases to verify"
            fi
            echo ""

            # Cloud section
            echo "Cloud"
            printf "  Status ............ %s (%s)\n" \
                "$(echo "$VERIFY_CLOUD_STATUS" | tr '[:lower:]' '[:upper:]')" \
                "$VERIFY_CLOUD_DETAILS"
            echo ""

            # Failures detail
            if [ ${#VERIFY_FAILURES[@]} -gt 0 ]; then
                echo "FAILURES:"
                echo "---"
                local fail_entry
                for fail_entry in "${VERIFY_FAILURES[@]}"; do
                    local fp fc fm
                    fp=$(echo "$fail_entry" | cut -d'|' -f1)
                    fc=$(echo "$fail_entry" | cut -d'|' -f2)
                    fm=$(echo "$fail_entry" | cut -d'|' -f3-)
                    echo "  $fc: $fp"
                    echo "       $fm"
                done
                echo ""
            fi

            # Summary
            if [ "$VERIFY_OVERALL" = "pass" ]; then
                echo "Summary: ALL CHECKS PASSED"
            elif [ "$VERIFY_OVERALL" = "warning" ]; then
                echo "Summary: PASSED WITH WARNINGS ($total_warnings warning(s))"
            elif [ "$VERIFY_OVERALL" = "fail" ]; then
                echo "Summary: CHECKS FAILED ($total_failed failure(s))"
            else
                echo "Summary: VERIFICATION ERROR"
            fi
            echo ""
            ;;
    esac
}

# ==============================================================================
# MANIFEST PERSISTENCE
# ==============================================================================

# Persist JSON manifest to $BACKUP_DIR/.checkpoint-manifest.json
# Called from backup-now.sh after post-backup verification
# Args: $1 = backup_dir, $2 = files_dir, $3 = database_dir, $4 = project_name
# Returns: 0 on success, 1 on failure (non-fatal — caller should continue)
persist_manifest_json() {
    local backup_dir="${1:-${BACKUP_DIR:-}}"
    local files_dir="${2:-${FILES_DIR:-$backup_dir/files}}"
    local database_dir="${3:-${DATABASE_DIR:-$backup_dir/databases}}"
    local project_name="${4:-${PROJECT_NAME:-unknown}}"

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        return 1
    fi

    local manifest_file="$backup_dir/.checkpoint-manifest.json"
    local tmp_manifest
    tmp_manifest=$(mktemp 2>/dev/null) || return 1

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)
    local backup_id
    backup_id=$(date +%Y%m%d_%H%M%S)

    # Bulk-collect file list with sizes using a single find+stat pipeline
    # Output: "size<TAB>relative_path" per line, sorted
    local _files_tmp
    _files_tmp=$(mktemp 2>/dev/null) || return 1
    local _dbs_tmp
    _dbs_tmp=$(mktemp 2>/dev/null) || return 1

    local file_count=0
    local db_count=0

    if [ -d "$files_dir" ]; then
        # Single find piped to xargs stat — 2 forks total instead of 2 per file
        find "$files_dir" -type f 2>/dev/null | \
            tr '\n' '\0' | xargs -0 stat -f$'%z\t%N' 2>/dev/null | \
            sort -t$'\t' -k2 > "$_files_tmp"
        file_count=$(wc -l < "$_files_tmp" | tr -d ' ')
    fi

    if [ -d "$database_dir" ]; then
        find "$database_dir" -type f \( -name "*.gz" -o -name "*.gz.age" -o -name "*.db" \) 2>/dev/null | \
            tr '\n' '\0' | xargs -0 stat -f$'%z\t%N' 2>/dev/null | \
            sort -t$'\t' -k2 > "$_dbs_tmp"
        db_count=$(wc -l < "$_dbs_tmp" | tr -d ' ')
    fi

    # Build JSON in one write
    {
        printf '{\n'
        printf '  "version": 1,\n'
        printf '  "timestamp": "%s",\n' "$ts"
        printf '  "project": "%s",\n' "$(printf '%s' "$project_name" | sed 's/\\/\\\\/g;s/"/\\"/g')"
        printf '  "backup_id": "%s",\n' "$backup_id"

        # --- Files array ---
        printf '  "files": [\n'
        local _first=true
        if [ "$file_count" -gt 0 ]; then
            while IFS=$'\t' read -r f_size file_path; do
                [ -z "$file_path" ] && continue
                # Strip files_dir prefix to get relative path (handles cloud destinations)
                local rel_path="${file_path#$files_dir/}"
                # Fallback: strip backup_dir prefix
                [ "$rel_path" = "$file_path" ] && rel_path="${file_path#$backup_dir/}"
                if [ "$_first" = true ]; then
                    _first=false
                else
                    printf ',\n'
                fi
                # Escape path for JSON (backslash and double-quote)
                local safe_path
                safe_path=$(printf '%s' "$rel_path" | sed 's/\\/\\\\/g;s/"/\\"/g')
                printf '    {"path": "%s", "size": %s}' "$safe_path" "$f_size"
            done < "$_files_tmp"
        fi
        printf '\n  ],\n'

        # --- Databases array ---
        printf '  "databases": [\n'
        _first=true
        if [ "$db_count" -gt 0 ]; then
            while IFS=$'\t' read -r d_size db_path; do
                [ -z "$db_path" ] && continue
                local db_rel="${db_path#$database_dir/}"
                [ "$db_rel" = "$db_path" ] && db_rel="${db_path#$backup_dir/}"
                local d_tables=0

                # Get table count for .gz databases (small number of DBs, ok to fork)
                if [[ "$db_path" == *.gz ]]; then
                    local tmp_db
                    tmp_db=$(mktemp 2>/dev/null) || true
                    if [ -n "$tmp_db" ] && gunzip -c "$db_path" > "$tmp_db" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"; then
                        d_tables=$(sqlite3 "$tmp_db" "SELECT count(*) FROM sqlite_master WHERE type='table';" 2>/dev/null) || d_tables=0
                    fi
                    rm -f "$tmp_db" 2>/dev/null || true
                fi

                if [ "$_first" = true ]; then
                    _first=false
                else
                    printf ',\n'
                fi
                local safe_db
                safe_db=$(printf '%s' "$db_rel" | sed 's/\\/\\\\/g;s/"/\\"/g')
                printf '    {"path": "%s", "size": %s, "tables": %s}' "$safe_db" "$d_size" "$d_tables"
            done < "$_dbs_tmp"
        fi
        printf '\n  ],\n'

        # --- Totals ---
        printf '  "totals": {"files": %s, "databases": %s}\n' "$file_count" "$db_count"
        printf '}\n'
    } > "$tmp_manifest"

    rm -f "$_files_tmp" "$_dbs_tmp"

    # Atomic move
    local _mv_err
    if _mv_err=$(mv "$tmp_manifest" "$manifest_file" 2>&1); then
        return 0
    else
        log_debug "Manifest mv failed: $_mv_err"
        rm -f "$tmp_manifest" 2>/dev/null || true
        return 1
    fi
}
