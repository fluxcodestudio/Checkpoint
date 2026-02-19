#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cloud Restore Library
# ==============================================================================
# Version: 1.0.0
# Description: Cloud manifest management, index tracking, and restore operations.
#              Enables browsing cloud backups, downloading individual files, and
#              auto-decrypting age-encrypted content.
#
# @requires: core/output (for color functions, json helpers)
#            features/encryption (for decrypt_file, encryption_enabled)
# @provides: cloud_upload_manifest, cloud_fetch_index, cloud_fetch_manifest,
#            cloud_download_file, cloud_download_all
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_CLOUD_RESTORE:-}" ] && return || readonly _CHECKPOINT_CLOUD_RESTORE=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Set logging context
if type log_set_context &>/dev/null; then
    log_set_context "cloud-restore"
fi

# Cloud cache directory
CLOUD_CACHE_DIR="${HOME}/.checkpoint/cloud-cache"

# ==============================================================================
# INTERNAL HELPERS
# ==============================================================================

# Determine cloud transport mode
# Returns: "folder" if CLOUD_FOLDER_PATH is set, "rclone" if rclone configured, "" if none
_cloud_transport() {
    if [[ "${CLOUD_FOLDER_ENABLED:-false}" == "true" ]] && [[ -n "${CLOUD_FOLDER_PATH:-}" ]] && [[ -d "${CLOUD_FOLDER_PATH}" ]]; then
        echo "folder"
    elif [[ "${CLOUD_RCLONE_ENABLED:-false}" == "true" ]] && [[ -n "${CLOUD_RCLONE_REMOTE:-}" ]] && command -v rclone &>/dev/null; then
        echo "rclone"
    elif [[ "${CLOUD_ENABLED:-false}" == "true" ]] && [[ -n "${CLOUD_REMOTE_NAME:-}" ]] && command -v rclone &>/dev/null; then
        echo "rclone-legacy"
    else
        echo ""
    fi
}

# Get cloud base path for a project
# Args: $1 = project_name
# Output: full cloud path (folder path or rclone remote:path)
_cloud_project_path() {
    local project_name="$1"
    local transport
    transport=$(_cloud_transport)

    case "$transport" in
        folder)
            echo "$CLOUD_FOLDER_PATH/$project_name"
            ;;
        rclone)
            echo "${CLOUD_RCLONE_REMOTE}:${CLOUD_RCLONE_PATH:-Backups/Checkpoint}/$project_name"
            ;;
        rclone-legacy)
            echo "${CLOUD_REMOTE_NAME}:${CLOUD_BACKUP_PATH}/$project_name"
            ;;
        *)
            return 1
            ;;
    esac
}

# Copy a file TO cloud
# Args: $1 = local_path, $2 = cloud_dest_path
_cloud_put_file() {
    local local_path="$1"
    local cloud_dest="$2"
    local transport
    transport=$(_cloud_transport)

    case "$transport" in
        folder)
            mkdir -p "$(dirname "$cloud_dest")" 2>/dev/null || true
            cp "$local_path" "$cloud_dest"
            ;;
        rclone|rclone-legacy)
            rclone copyto "$local_path" "$cloud_dest" --quiet 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"
            ;;
        *)
            return 1
            ;;
    esac
}

# Copy a file FROM cloud to local
# Args: $1 = cloud_src_path, $2 = local_dest_path
_cloud_get_file() {
    local cloud_src="$1"
    local local_dest="$2"
    local transport
    transport=$(_cloud_transport)

    mkdir -p "$(dirname "$local_dest")" 2>/dev/null || true

    case "$transport" in
        folder)
            if [[ -f "$cloud_src" ]]; then
                cp "$cloud_src" "$local_dest"
            else
                return 1
            fi
            ;;
        rclone|rclone-legacy)
            rclone copyto "$cloud_src" "$local_dest" --quiet 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"
            ;;
        *)
            return 1
            ;;
    esac
}

# Copy a directory FROM cloud to local
# Args: $1 = cloud_src_dir, $2 = local_dest_dir
_cloud_get_dir() {
    local cloud_src="$1"
    local local_dest="$2"
    local transport
    transport=$(_cloud_transport)

    mkdir -p "$local_dest" 2>/dev/null || true

    case "$transport" in
        folder)
            if [[ -d "$cloud_src" ]]; then
                rsync -a "$cloud_src/" "$local_dest/" 2>/dev/null
            else
                return 1
            fi
            ;;
        rclone|rclone-legacy)
            rclone copy "$cloud_src" "$local_dest" --transfers 4 --quiet 2>>"${_CHECKPOINT_LOG_FILE:-/dev/null}"
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if a cloud file exists
# Args: $1 = cloud_path
_cloud_file_exists() {
    local cloud_path="$1"
    local transport
    transport=$(_cloud_transport)

    case "$transport" in
        folder)
            [[ -f "$cloud_path" ]]
            ;;
        rclone|rclone-legacy)
            rclone lsf "$cloud_path" --max-depth 0 &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# CLOUD INDEX MANAGEMENT
# ==============================================================================

# Upload manifest and update cloud index after each backup
# Args: $1 = project_name, $2 = backup_id, $3 = manifest_path
# Returns: 0 on success, 1 on failure
cloud_upload_manifest() {
    local project_name="$1"
    local backup_id="$2"
    local manifest_path="$3"

    if [[ -z "$project_name" ]] || [[ -z "$backup_id" ]] || [[ ! -f "$manifest_path" ]]; then
        if type log_warn &>/dev/null; then
            log_warn "cloud_upload_manifest: missing arguments or manifest file"
        fi
        return 1
    fi

    local cloud_base
    cloud_base=$(_cloud_project_path "$project_name") || {
        if type log_debug &>/dev/null; then
            log_debug "cloud_upload_manifest: no cloud transport configured"
        fi
        return 1
    }

    # 1. Upload manifest to .checkpoint-manifests/{backup_id}.json
    local cloud_manifest_dest="$cloud_base/.checkpoint-manifests/${backup_id}.json"
    if ! _cloud_put_file "$manifest_path" "$cloud_manifest_dest"; then
        if type log_warn &>/dev/null; then
            log_warn "cloud_upload_manifest: failed to upload manifest for $backup_id"
        fi
        return 1
    fi

    # 2. Read manifest to extract stats for the index entry
    local files_count=0 databases_count=0 total_size=0

    if command -v python3 &>/dev/null; then
        local _stats
        _stats=$(python3 -c "
import json, sys
try:
    m = json.load(open(sys.argv[1]))
    fc = len(m.get('files', []))
    dc = len(m.get('databases', []))
    ts = sum(f.get('size', 0) for f in m.get('files', [])) + sum(d.get('size', 0) for d in m.get('databases', []))
    print(f'{fc}|{dc}|{ts}')
except: print('0|0|0')
" "$manifest_path" 2>/dev/null)
        if [[ -n "$_stats" ]]; then
            IFS='|' read -r files_count databases_count total_size <<< "$_stats"
        fi
    else
        # Fallback: grep-based counting
        files_count=$(grep -c '"path"' "$manifest_path" 2>/dev/null || echo "0")
    fi

    # 3. Download existing cloud index (or create new)
    local cache_dir="$CLOUD_CACHE_DIR/$project_name"
    mkdir -p "$cache_dir" 2>/dev/null || true
    local index_file="$cache_dir/cloud-index.json"
    local cloud_index_path="$cloud_base/.checkpoint-cloud-index.json"

    _cloud_get_file "$cloud_index_path" "$index_file" 2>/dev/null || true

    # 4. Update index with this backup entry
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)
    local _enc_enabled="false"
    if type encryption_enabled &>/dev/null && encryption_enabled 2>/dev/null; then
        _enc_enabled="true"
    fi

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys, os

index_file = sys.argv[1]
project = sys.argv[2]
backup_id = sys.argv[3]
timestamp = sys.argv[4]
files_count = int(sys.argv[5])
databases_count = int(sys.argv[6])
total_size = int(sys.argv[7])
enc_enabled = sys.argv[8] == 'true'

# Load or create index
index = {'version': 1, 'project': project, 'updated': timestamp, 'encryption_enabled': enc_enabled, 'backups': []}
if os.path.exists(index_file):
    try:
        with open(index_file) as f:
            index = json.load(f)
    except: pass

# Remove existing entry for same backup_id (idempotent)
index['backups'] = [b for b in index.get('backups', []) if b.get('backup_id') != backup_id]

# Append new entry
index['backups'].append({
    'backup_id': backup_id,
    'timestamp': timestamp,
    'files_count': files_count,
    'databases_count': databases_count,
    'total_size_bytes': total_size
})

# Sort by backup_id descending (newest first)
index['backups'].sort(key=lambda b: b.get('backup_id', ''), reverse=True)

# Update metadata
index['updated'] = timestamp
index['encryption_enabled'] = enc_enabled
index['project'] = project

with open(index_file, 'w') as f:
    json.dump(index, f, indent=2)
" "$index_file" "$project_name" "$backup_id" "$timestamp" "$files_count" "$databases_count" "$total_size" "$_enc_enabled"
    else
        # Minimal fallback: create a simple index without python
        {
            printf '{\n'
            printf '  "version": 1,\n'
            printf '  "project": "%s",\n' "$project_name"
            printf '  "updated": "%s",\n' "$timestamp"
            printf '  "encryption_enabled": %s,\n' "$_enc_enabled"
            printf '  "backups": [\n'
            printf '    {\n'
            printf '      "backup_id": "%s",\n' "$backup_id"
            printf '      "timestamp": "%s",\n' "$timestamp"
            printf '      "files_count": %d,\n' "$files_count"
            printf '      "databases_count": %d,\n' "$databases_count"
            printf '      "total_size_bytes": %d\n' "$total_size"
            printf '    }\n'
            printf '  ]\n'
            printf '}\n'
        } > "$index_file"
    fi

    # 5. Upload updated index
    if ! _cloud_put_file "$index_file" "$cloud_index_path"; then
        if type log_warn &>/dev/null; then
            log_warn "cloud_upload_manifest: failed to upload cloud index"
        fi
        return 1
    fi

    if type log_info &>/dev/null; then
        log_info "Cloud manifest uploaded for backup $backup_id ($files_count files, $databases_count databases)"
    fi

    return 0
}

# ==============================================================================
# CLOUD INDEX / MANIFEST FETCHING
# ==============================================================================

# Fetch cloud index for a project
# Args: $1 = project_name
# Output: path to cached index file
# Returns: 0 on success, 1 on failure
cloud_fetch_index() {
    local project_name="$1"

    if [[ -z "$project_name" ]]; then
        echo "Error: project name required" >&2
        return 1
    fi

    local cache_dir="$CLOUD_CACHE_DIR/$project_name"
    mkdir -p "$cache_dir" 2>/dev/null || true
    local index_file="$cache_dir/cloud-index.json"

    local cloud_base
    cloud_base=$(_cloud_project_path "$project_name") || {
        echo "Error: no cloud transport configured" >&2
        return 1
    }

    local cloud_index_path="$cloud_base/.checkpoint-cloud-index.json"

    if ! _cloud_get_file "$cloud_index_path" "$index_file"; then
        echo "Error: could not fetch cloud index for $project_name" >&2
        return 1
    fi

    echo "$index_file"
    return 0
}

# Fetch specific backup manifest from cloud
# Args: $1 = project_name, $2 = backup_id
# Output: path to cached manifest file
# Returns: 0 on success, 1 on failure
cloud_fetch_manifest() {
    local project_name="$1"
    local backup_id="$2"

    if [[ -z "$project_name" ]] || [[ -z "$backup_id" ]]; then
        echo "Error: project name and backup ID required" >&2
        return 1
    fi

    local cache_dir="$CLOUD_CACHE_DIR/$project_name/manifests"
    mkdir -p "$cache_dir" 2>/dev/null || true
    local manifest_file="$cache_dir/${backup_id}.json"

    # Manifests are immutable — use cache if available
    if [[ -f "$manifest_file" ]] && [[ -s "$manifest_file" ]]; then
        echo "$manifest_file"
        return 0
    fi

    local cloud_base
    cloud_base=$(_cloud_project_path "$project_name") || {
        echo "Error: no cloud transport configured" >&2
        return 1
    }

    local cloud_manifest_path="$cloud_base/.checkpoint-manifests/${backup_id}.json"

    if ! _cloud_get_file "$cloud_manifest_path" "$manifest_file"; then
        echo "Error: could not fetch manifest for backup $backup_id" >&2
        return 1
    fi

    echo "$manifest_file"
    return 0
}

# ==============================================================================
# DOWNLOAD OPERATIONS
# ==============================================================================

# Download a single file from cloud backup, auto-decrypt if needed
# Args: $1 = project_name, $2 = backup_id, $3 = rel_path, $4 = output_dir (default: ~/Downloads)
# Returns: 0 on success, 1 on failure
cloud_download_file() {
    local project_name="$1"
    local backup_id="$2"
    local rel_path="$3"
    local output_dir="${4:-$HOME/Downloads}"

    if [[ -z "$project_name" ]] || [[ -z "$backup_id" ]] || [[ -z "$rel_path" ]]; then
        echo "Error: project name, backup ID, and file path required" >&2
        return 1
    fi

    local cloud_base
    cloud_base=$(_cloud_project_path "$project_name") || {
        echo "Error: no cloud transport configured" >&2
        return 1
    }

    # Create secure temp directory with cleanup trap
    local SECURE_TMP
    SECURE_TMP=$(mktemp -d)
    trap "rm -rf '$SECURE_TMP'" EXIT INT TERM

    mkdir -p "$output_dir" 2>/dev/null || true

    local cloud_file_path="$cloud_base/files/$rel_path"
    local downloaded=false
    local is_encrypted=false
    local is_compressed=false
    local tmp_file="$SECURE_TMP/$(basename "$rel_path")"

    # Try .gz.age variant first (compressed + encrypted)
    local cloud_gz_age_path="${cloud_file_path}.gz.age"
    if _cloud_file_exists "$cloud_gz_age_path" 2>/dev/null; then
        local tmp_gz_age_file="${tmp_file}.gz.age"
        if _cloud_get_file "$cloud_gz_age_path" "$tmp_gz_age_file"; then
            downloaded=true
            is_encrypted=true
            is_compressed=true
        fi
    fi

    # Try .age variant (encrypted only)
    if [[ "$downloaded" != "true" ]]; then
        local cloud_age_path="${cloud_file_path}.age"
        if _cloud_file_exists "$cloud_age_path" 2>/dev/null; then
            local tmp_age_file="${tmp_file}.age"
            if _cloud_get_file "$cloud_age_path" "$tmp_age_file"; then
                downloaded=true
                is_encrypted=true
            fi
        fi
    fi

    # Fall back to unencrypted version
    if [[ "$downloaded" != "true" ]]; then
        if _cloud_get_file "$cloud_file_path" "$tmp_file"; then
            downloaded=true
        fi
    fi

    if [[ "$downloaded" != "true" ]]; then
        echo "Error: could not download $rel_path from backup $backup_id" >&2
        rm -rf "$SECURE_TMP"
        trap - EXIT INT TERM
        return 1
    fi

    # Decrypt if needed
    if [[ "$is_encrypted" == "true" ]]; then
        if type decrypt_file &>/dev/null; then
            if [[ "$is_compressed" == "true" ]]; then
                local tmp_gz_age_file="${tmp_file}.gz.age"
                local tmp_gz_file="${tmp_file}.gz"
                if ! decrypt_file "$tmp_gz_age_file" "$tmp_gz_file"; then
                    echo "Error: decryption failed for $rel_path" >&2
                    rm -rf "$SECURE_TMP"
                    trap - EXIT INT TERM
                    return 1
                fi
                rm -f "$tmp_gz_age_file"
            else
                local tmp_age_file="${tmp_file}.age"
                if ! decrypt_file "$tmp_age_file" "$tmp_file"; then
                    echo "Error: decryption failed for $rel_path" >&2
                    rm -rf "$SECURE_TMP"
                    trap - EXIT INT TERM
                    return 1
                fi
                rm -f "$tmp_age_file"
            fi
        else
            echo "Error: encryption library not loaded, cannot decrypt" >&2
            rm -rf "$SECURE_TMP"
            trap - EXIT INT TERM
            return 1
        fi
    fi

    # Decompress if needed
    if [[ "$is_compressed" == "true" ]]; then
        local tmp_gz_file="${tmp_file}.gz"
        if ! gunzip -f "$tmp_gz_file" 2>/dev/null; then
            echo "Error: decompression failed for $rel_path" >&2
            rm -rf "$SECURE_TMP"
            trap - EXIT INT TERM
            return 1
        fi
    fi

    # Move to output directory
    local final_name
    final_name=$(basename "$rel_path")
    local final_path="$output_dir/$final_name"

    # Avoid overwriting: add suffix if file exists
    if [[ -f "$final_path" ]]; then
        local base="${final_name%.*}"
        local ext="${final_name##*.}"
        if [[ "$base" == "$ext" ]]; then
            final_path="$output_dir/${final_name}-${backup_id}"
        else
            final_path="$output_dir/${base}-${backup_id}.${ext}"
        fi
    fi

    mv "$tmp_file" "$final_path"

    # Cleanup
    rm -rf "$SECURE_TMP"
    trap - EXIT INT TERM

    echo "$final_path"
    return 0
}

# Download all files from a cloud backup
# Args: $1 = project_name, $2 = backup_id, $3 = output_dir (default: ~/Downloads), $4 = "zip" for zip output
# Returns: 0 on success, 1 on failure
cloud_download_all() {
    local project_name="$1"
    local backup_id="$2"
    local output_dir="${3:-$HOME/Downloads}"
    local as_zip="${4:-}"

    if [[ -z "$project_name" ]] || [[ -z "$backup_id" ]]; then
        echo "Error: project name and backup ID required" >&2
        return 1
    fi

    local cloud_base
    cloud_base=$(_cloud_project_path "$project_name") || {
        echo "Error: no cloud transport configured" >&2
        return 1
    }

    # Create secure temp directory with cleanup trap
    local SECURE_TMP
    SECURE_TMP=$(mktemp -d)
    trap "rm -rf '$SECURE_TMP'" EXIT INT TERM

    mkdir -p "$output_dir" 2>/dev/null || true

    local staging_dir="$SECURE_TMP/${project_name}-${backup_id}"
    mkdir -p "$staging_dir"

    # Download entire project directory to temp
    echo "Downloading backup $backup_id..."
    if ! _cloud_get_dir "$cloud_base" "$staging_dir"; then
        echo "Error: could not download backup $backup_id" >&2
        rm -rf "$SECURE_TMP"
        trap - EXIT INT TERM
        return 1
    fi

    # Decrypt all .age files
    if type decrypt_file &>/dev/null; then
        local _decrypt_count=0
        while IFS= read -r -d '' age_file; do
            local decrypted_path="${age_file%.age}"
            if decrypt_file "$age_file" "$decrypted_path" 2>/dev/null; then
                rm -f "$age_file"
                _decrypt_count=$((_decrypt_count + 1))
            fi
        done < <(find "$staging_dir" -name "*.age" -type f -print0 2>/dev/null)
        if [[ $_decrypt_count -gt 0 ]]; then
            echo "Decrypted $_decrypt_count files"
        fi
    fi

    # Decompress all .gz files (compressed files from .gz.age and database backups)
    local _gunzip_count=0
    while IFS= read -r -d '' gz_file; do
        if gunzip -f "$gz_file" 2>/dev/null; then
            _gunzip_count=$((_gunzip_count + 1))
        fi
    done < <(find "$staging_dir" -name "*.gz" -type f -print0 2>/dev/null)
    if [[ $_gunzip_count -gt 0 ]]; then
        echo "Decompressed $_gunzip_count files"
    fi

    # Remove internal checkpoint files from download
    rm -f "$staging_dir/.checkpoint-cloud-index.json"
    rm -rf "$staging_dir/.checkpoint-manifests"
    rm -f "$staging_dir/.checkpoint-state.json"
    rm -f "$staging_dir/.checkpoint-manifest.json"

    local final_path
    if [[ "$as_zip" == "zip" ]]; then
        # Create zip archive
        final_path="$output_dir/${project_name}-${backup_id}.zip"
        if [[ -f "$final_path" ]]; then
            final_path="$output_dir/${project_name}-${backup_id}-$(date +%s).zip"
        fi
        (cd "$SECURE_TMP" && zip -r "$final_path" "$(basename "$staging_dir")" -x '*.DS_Store' 2>/dev/null)
        echo "Created: $final_path"
    else
        # Move tree to output directory
        final_path="$output_dir/${project_name}-${backup_id}"
        if [[ -d "$final_path" ]]; then
            final_path="$output_dir/${project_name}-${backup_id}-$(date +%s)"
        fi
        mv "$staging_dir" "$final_path"
        echo "Restored to: $final_path"
    fi

    # Cleanup
    rm -rf "$SECURE_TMP"
    trap - EXIT INT TERM

    echo "$final_path"
    return 0
}

# ==============================================================================
# JSON OUTPUT HELPERS (for --json flag)
# ==============================================================================

# Output cloud index as JSON to stdout
# Args: $1 = index_file_path
cloud_index_to_json() {
    local index_file="$1"
    if [[ -f "$index_file" ]]; then
        cat "$index_file"
    else
        echo '{"error": "no index available"}'
    fi
}

# Output manifest as JSON to stdout
# Args: $1 = manifest_file_path
cloud_manifest_to_json() {
    local manifest_file="$1"
    if [[ -f "$manifest_file" ]]; then
        cat "$manifest_file"
    else
        echo '{"error": "no manifest available"}'
    fi
}

# Get cloud status summary as JSON
cloud_status_json() {
    local transport
    transport=$(_cloud_transport)

    local connected="false"
    local mode="none"
    local project_count=0

    if [[ -n "$transport" ]]; then
        connected="true"
        mode="$transport"
        # Count cached project indexes
        if [[ -d "$CLOUD_CACHE_DIR" ]]; then
            project_count=$(find "$CLOUD_CACHE_DIR" -name "cloud-index.json" 2>/dev/null | wc -l | tr -d ' ')
        fi
    fi

    printf '{"connected": %s, "mode": "%s", "cached_projects": %d}\n' "$connected" "$mode" "$project_count"
}
