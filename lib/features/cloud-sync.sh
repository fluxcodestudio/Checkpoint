#!/usr/bin/env bash
# Cloud Folder Sync — sync backups to a local cloud folder (Dropbox/iCloud/Google Drive)
#
# @provides: sync_to_cloud_folder
# @requires: log_info, log_warn from backup-lib.sh
# @globals:  CLOUD_FOLDER_ENABLED, CLOUD_FOLDER_PATH, PROJECT_NAME,
#            DATABASE_DIR, FILES_DIR, ARCHIVED_DIR, BACKUP_DIR
#
# Encryption support: if encryption_enabled / get_age_recipient / _cloud_compress_and_encrypt /
# _cloud_parallel_encrypt are available (from backup-now.sh), cloud copies are encrypted.
# If not available, files are synced as-is (daemon mode).

# Parallel encryption worker count (used by _cloud_parallel_encrypt if defined here)
if [[ -z "${_ENCRYPT_JOBS:-}" ]]; then
    _ENCRYPT_JOBS=$(( $(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4) / 2 ))
    [[ $_ENCRYPT_JOBS -lt 2 ]] && _ENCRYPT_JOBS=2
fi

sync_to_cloud_folder() {
    # Guard: feature disabled or not configured
    if [[ "${CLOUD_FOLDER_ENABLED:-false}" != "true" ]] || [[ -z "${CLOUD_FOLDER_PATH:-}" ]]; then
        return 0
    fi

    log_info "Starting cloud folder sync to $CLOUD_FOLDER_PATH"

    # Create cloud backup directory if needed (ignore errors if path doesn't exist)
    mkdir -p "$CLOUD_FOLDER_PATH/$PROJECT_NAME" 2>/dev/null || true

    if [[ ! -d "$CLOUD_FOLDER_PATH" ]]; then
        log_warn "Cloud folder not accessible: $CLOUD_FOLDER_PATH"
        return 1
    fi

    local _log="${_CHECKPOINT_LOG_FILE:-/dev/null}"

    # --- Sync databases ---
    if [[ -d "$DATABASE_DIR" ]] && [[ "$(ls -A "$DATABASE_DIR" 2>/dev/null)" ]]; then
        if rsync -a --delete "$DATABASE_DIR/" "$CLOUD_FOLDER_PATH/$PROJECT_NAME/databases/" 2>>"$_log"; then
            log_info "Cloud sync: databases synced"

            # Encrypt cloud database backups if encryption is available
            if type encryption_enabled &>/dev/null && encryption_enabled 2>/dev/null; then
                local _cloud_db_dir="$CLOUD_FOLDER_PATH/$PROJECT_NAME/databases"
                local _age_recipient
                _age_recipient="$(get_age_recipient)"
                if [[ -n "$_age_recipient" ]] && type _cloud_compress_and_encrypt &>/dev/null; then
                    while IFS= read -r -d '' db_file; do
                        if [[ ! -f "${db_file}.age" ]] || [[ "$db_file" -nt "${db_file}.age" ]]; then
                            _cloud_compress_and_encrypt "$db_file" "$_age_recipient" "$_log" || \
                                log_warn "Encryption failed for: $db_file"
                        else
                            rm -f "$db_file"
                        fi
                    done < <(find "$_cloud_db_dir" -name "*.db.gz" ! -name "*.age" -print0 2>/dev/null)
                    log_info "Cloud sync: databases encrypted"
                fi
            fi
        else
            log_warn "Cloud sync: database sync failed"
        fi
    fi

    # --- Sync project files ---
    if [[ -d "$FILES_DIR" ]]; then
        if rsync -a \
              --exclude='node_modules/' --exclude='.git/' --exclude='.venv/' \
              --exclude='__pycache__/' --exclude='dist/' --exclude='build/' \
              --exclude='.next/' --exclude='.cache/' --exclude='coverage/' \
              --exclude='.turbo/' --exclude='target/' --exclude='vendor/' \
              --exclude='.nuxt/' --exclude='.output/' --exclude='.svelte-kit/' \
              --exclude='*.log' --exclude='.DS_Store' \
              "$FILES_DIR/" "$CLOUD_FOLDER_PATH/$PROJECT_NAME/files/" 2>>"$_log"; then
            log_info "Cloud sync: project files synced"

            # Encrypt cloud file backups if encryption is available
            if type encryption_enabled &>/dev/null && encryption_enabled 2>/dev/null; then
                local _cloud_files_dir="$CLOUD_FOLDER_PATH/$PROJECT_NAME/files"
                local _age_recipient
                _age_recipient="$(get_age_recipient)"
                if [[ -n "$_age_recipient" ]] && type _cloud_parallel_encrypt &>/dev/null; then
                    # Remove plaintext files that already have encrypted counterparts
                    while IFS= read -r -d '' src_file; do
                        if [[ -f "${src_file}.age" ]] || [[ -f "${src_file}.gz.age" ]]; then
                            if [[ ! "$src_file" -nt "${src_file}.age" ]] 2>/dev/null || [[ ! "$src_file" -nt "${src_file}.gz.age" ]] 2>/dev/null; then
                                rm -f "$src_file"
                            fi
                        fi
                    done < <(find "$_cloud_files_dir" -type f ! -name "*.age" ! -name "*.gz.age" -print0 2>/dev/null)
                    # Encrypt remaining plaintext files (parallel if 100+)
                    local _encrypted_count
                    _encrypted_count=$(_cloud_parallel_encrypt "$_cloud_files_dir" "$_age_recipient" "$_log")
                    if [[ $_encrypted_count -gt 0 ]]; then
                        log_info "Cloud sync: $_encrypted_count files compressed and encrypted"
                    fi
                fi
            fi
        else
            log_warn "Cloud sync: file sync failed"
        fi
    fi

    # --- Sync archived versions ---
    if [[ -d "$ARCHIVED_DIR" ]] && [[ "$(ls -A "$ARCHIVED_DIR" 2>/dev/null)" ]]; then
        if rsync -a \
              "$ARCHIVED_DIR/" "$CLOUD_FOLDER_PATH/$PROJECT_NAME/archived/" 2>>"$_log"; then
            log_info "Cloud sync: archives synced"

            # Encrypt archived files if encryption is available
            if type encryption_enabled &>/dev/null && encryption_enabled 2>/dev/null; then
                local _cloud_archived_dir="$CLOUD_FOLDER_PATH/$PROJECT_NAME/archived"
                local _age_recipient
                _age_recipient="$(get_age_recipient)"
                if [[ -n "$_age_recipient" ]] && type _cloud_parallel_encrypt &>/dev/null; then
                    # Remove plaintext files that already have encrypted counterparts
                    while IFS= read -r -d '' arc_file; do
                        if [[ -f "${arc_file}.age" ]] || [[ -f "${arc_file}.gz.age" ]]; then
                            if [[ ! "$arc_file" -nt "${arc_file}.age" ]] 2>/dev/null || [[ ! "$arc_file" -nt "${arc_file}.gz.age" ]] 2>/dev/null; then
                                rm -f "$arc_file"
                            fi
                        fi
                    done < <(find "$_cloud_archived_dir" -type f ! -name "*.age" ! -name "*.gz.age" -print0 2>/dev/null)
                    # Encrypt remaining plaintext files (parallel if 100+)
                    local _archived_encrypted
                    _archived_encrypted=$(_cloud_parallel_encrypt "$_cloud_archived_dir" "$_age_recipient" "$_log")
                    if [[ $_archived_encrypted -gt 0 ]]; then
                        log_info "Cloud sync: $_archived_encrypted archived files compressed and encrypted"
                    fi
                fi
            fi
        else
            log_warn "Cloud sync: archive sync failed"
        fi
    fi

    # --- Sync state file (for cross-computer portability) ---
    local portable_state="${BACKUP_DIR:-$PROJECT_DIR/backups}/.checkpoint-state.json"
    if [[ -f "$portable_state" ]]; then
        if cp "$portable_state" "$CLOUD_FOLDER_PATH/$PROJECT_NAME/.checkpoint-state.json" 2>>"$_log"; then
            log_info "Cloud sync: state file synced"
        else
            log_warn "Cloud sync: state sync failed"
        fi
    fi

    log_info "Cloud folder sync complete: $CLOUD_FOLDER_PATH/$PROJECT_NAME"
    return 0
}
