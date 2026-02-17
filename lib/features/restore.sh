#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Restore Operations
# Safety backups, integrity verification, and database/file restore
# ==============================================================================
# @requires: core/output (for color functions, backup_log),
#            ui/time-size-utils (for format_bytes)
# @provides: create_safety_backup, verify_sqlite_integrity,
#            verify_compressed_backup, restore_database_from_backup,
#            restore_file_from_backup
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
verify_compressed_backup() {
    local compressed_path="$1"

    [ ! -f "$compressed_path" ] && return 1

    # Test decompression
    local _gz_err
    if ! _gz_err=$(gunzip -t "$compressed_path" 2>&1); then
        log_debug "Restore gunzip -t failed for $compressed_path: $_gz_err"
        return 1
    fi

    # Decompress to temp and verify SQLite integrity
    local temp_db=$(mktemp)
    gunzip -c "$compressed_path" > "$temp_db" 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"

    local result=0
    if ! verify_sqlite_integrity "$temp_db"; then
        result=1
    fi

    rm -f "$temp_db"
    return $result
}

# Restore database from compressed backup
# Handles both unencrypted (.db.gz) and encrypted (.db.gz.age) backups
restore_database_from_backup() {
    local backup_file="$1"
    local target_db="$2"
    local dry_run="${3:-false}"

    [ ! -f "$backup_file" ] && color_red "❌ Backup file not found" && return 1

    if [ "$dry_run" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Would restore:"
        color_cyan "   From: $backup_file"
        color_cyan "   To: $target_db"
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

    # Verify backup
    color_cyan "🧪 Verifying backup integrity..."
    if ! verify_compressed_backup "$actual_backup"; then
        color_red "❌ Backup verification failed"
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"
        return 1
    fi
    color_green "✅ Backup verified"

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
    color_cyan "📦 Restoring database..."
    local _restore_err
    if _restore_err=$(gunzip -c "$actual_backup" > "$target_db" 2>&1); then
        # Clean up decrypted temp file
        [ -n "$_decrypt_tmp" ] && rm -f "$_decrypt_tmp"

        # Verify restored database
        color_cyan "🧪 Verifying restored database..."
        if verify_sqlite_integrity "$target_db"; then
            color_green "✅ Restore complete and verified"
            return 0
        else
            color_red "❌ Restored database failed verification"
            # Rollback
            if [ -n "$safety_backup" ] && [ -f "$safety_backup" ]; then
                color_yellow "⚠️  Rolling back to safety backup..."
                cp "$safety_backup" "$target_db"
            fi
            return 1
        fi
    else
        log_error "Database restore failed for $target_db: $_restore_err"
        color_red "❌ Restore failed"
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
