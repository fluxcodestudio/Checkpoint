#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cloud Restore CLI
# ==============================================================================
# Browse, download, and restore files from cloud backups.
# Usage: checkpoint cloud [command] [options]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Source foundation library (loads core, ops, ui, platform, features)
source "$LIB_DIR/backup-lib.sh"

# Source encryption library
if [ -f "$LIB_DIR/features/encryption.sh" ]; then
    source "$LIB_DIR/features/encryption.sh"
fi

# Source cloud restore library
source "$LIB_DIR/features/cloud-restore.sh"

# Source projects registry
if [ -f "$LIB_DIR/projects-registry.sh" ]; then
    source "$LIB_DIR/projects-registry.sh"
fi

# Load global config (provides CLOUD_FOLDER_PATH, etc.)
GLOBAL_CONFIG_FILE="$HOME/.config/checkpoint/config.sh"
if [[ -f "$GLOBAL_CONFIG_FILE" ]]; then
    source "$GLOBAL_CONFIG_FILE"
fi

# ==============================================================================
# GLOBALS
# ==============================================================================

JSON_OUTPUT=false

# ==============================================================================
# HELP TEXT
# ==============================================================================

show_help() {
    cat <<EOF
Checkpoint - Cloud Restore

USAGE
    checkpoint cloud                             Cloud status summary
    checkpoint cloud list [PROJECT]              List available cloud backups
    checkpoint cloud browse PROJECT [BACKUP_ID]  Browse files in a backup
    checkpoint cloud download FILE [OPTIONS]     Download a single file
    checkpoint cloud download-all [OPTIONS]      Download entire backup
    checkpoint cloud sync-index                  Force refresh cloud index cache
    checkpoint cloud setup                       Interactive setup for new machine

OPTIONS
    --project NAME, -p NAME     Project name
    --backup-id ID, -b ID       Backup ID (or "latest")
    --output DIR, -o DIR        Output directory (default: ~/Downloads)
    --zip                       Create zip archive (download-all only)
    --latest                    Use most recent backup
    --json                      Output as JSON (for SwiftUI/scripts)
    --help, -h                  Show this help

EXAMPLES
    checkpoint cloud list                        List all projects on cloud
    checkpoint cloud list MyProject              List backups for MyProject
    checkpoint cloud browse MyProject            Interactive file browser
    checkpoint cloud browse MyProject --latest   Browse latest backup
    checkpoint cloud download .env -p MyProject -b latest
    checkpoint cloud download-all -p MyProject --zip

EOF
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Load project config by name (searches registry for path, then sources config)
_load_project_by_name() {
    local project_name="$1"

    # Try current directory first
    local current_project
    current_project=$(basename "$PWD")
    if [[ "$current_project" == "$project_name" ]] && [[ -f "$PWD/.backup-config.sh" ]]; then
        source "$PWD/.backup-config.sh" 2>/dev/null || true
        return 0
    fi

    # Search registry by path basename AND by name field
    local _project_path=""
    local registry_file="$HOME/.config/checkpoint/projects.json"
    if [[ -f "$registry_file" ]] && command -v python3 &>/dev/null; then
        _project_path=$(python3 -c "
import json, sys
name = sys.argv[1]
try:
    data = json.load(open(sys.argv[2]))
    for p in data.get('projects', []):
        path = p.get('path', '')
        pname = p.get('name', '')
        basename = path.rstrip('/').rsplit('/', 1)[-1] if '/' in path else path
        if basename == name or pname == name:
            print(path)
            break
except: pass
" "$project_name" "$registry_file" 2>/dev/null)
    fi

    # Fallback: grep-based search by basename
    if [[ -z "$_project_path" ]] && type list_projects &>/dev/null; then
        while IFS= read -r _line; do
            local _name
            _name=$(basename "$_line")
            if [[ "$_name" == "$project_name" ]]; then
                _project_path="$_line"
                break
            fi
        done < <(list_projects 2>/dev/null)
    fi

    if [[ -n "$_project_path" ]] && [[ -f "$_project_path/.backup-config.sh" ]]; then
        source "$_project_path/.backup-config.sh" 2>/dev/null || true
        return 0
    fi

    return 1
}

# Resolve "latest" backup ID from index
# Args: $1 = index_file
# Output: backup_id of most recent backup
_resolve_latest_backup() {
    local index_file="$1"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    index = json.load(open(sys.argv[1]))
    backups = index.get('backups', [])
    if backups:
        print(backups[0].get('backup_id', ''))
except: pass
" "$index_file"
    else
        # Grep fallback: find first backup_id value
        grep -o '"backup_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$index_file" 2>/dev/null | head -1 | sed 's/.*"backup_id"[[:space:]]*:[[:space:]]*"//;s/"//'
    fi
}

# Format bytes to human readable
_format_bytes() {
    local bytes="$1"
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes} B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$(( bytes / 1024 )) KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        local mb=$(( bytes / 1048576 ))
        local remainder=$(( (bytes % 1048576) * 10 / 1048576 ))
        echo "${mb}.${remainder} MB"
    else
        local gb=$(( bytes / 1073741824 ))
        local remainder=$(( (bytes % 1073741824) * 10 / 1073741824 ))
        echo "${gb}.${remainder} GB"
    fi
}

# Format timestamp to readable date
_format_timestamp() {
    local ts="$1"
    # Extract date parts from backup_id format: YYYYMMDD_HHMMSS
    if [[ "$ts" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}"
    else
        echo "$ts"
    fi
}

# ==============================================================================
# COMMAND: STATUS (default)
# ==============================================================================

cmd_status() {
    local transport
    transport=$(_cloud_transport)

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cloud_status_json
        return 0
    fi

    echo "Cloud Backup Status"
    echo "-------------------------------------------"

    if [[ -z "$transport" ]]; then
        echo "  Status:    Not connected"
        echo ""
        echo "  Run 'checkpoint cloud setup' to configure cloud access."
        return 0
    fi

    echo "  Status:    Connected"
    echo "  Mode:      $transport"

    case "$transport" in
        folder)
            echo "  Path:      ${CLOUD_FOLDER_PATH:-unknown}"
            ;;
        rclone)
            echo "  Remote:    ${CLOUD_RCLONE_REMOTE:-unknown}"
            echo "  Path:      ${CLOUD_RCLONE_PATH:-Backups/Checkpoint}"
            ;;
        rclone-legacy)
            echo "  Remote:    ${CLOUD_REMOTE_NAME:-unknown}"
            echo "  Path:      ${CLOUD_BACKUP_PATH:-unknown}"
            ;;
    esac

    # Show cached projects
    if [[ -d "$CLOUD_CACHE_DIR" ]]; then
        local cached
        cached=$(find "$CLOUD_CACHE_DIR" -name "cloud-index.json" 2>/dev/null | wc -l | tr -d ' ')
        echo "  Cached:    $cached project indexes"
    fi

    echo ""
    echo "  Use 'checkpoint cloud list' to see available backups."
}

# ==============================================================================
# COMMAND: LIST
# ==============================================================================

cmd_list() {
    local project_name="${1:-}"

    if [[ -z "$project_name" ]]; then
        # List all projects that have cloud backups
        _list_all_projects
        return $?
    fi

    # Load project config
    _load_project_by_name "$project_name" 2>/dev/null || true

    # Fetch index
    local index_file
    index_file=$(cloud_fetch_index "$project_name") || {
        echo "No cloud backups found for $project_name" >&2
        return 1
    }

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cloud_index_to_json "$index_file"
        return 0
    fi

    # Display backup list
    echo "Cloud Backups: $project_name"
    echo "-------------------------------------------"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    index = json.load(open(sys.argv[1]))
    backups = index.get('backups', [])
    enc = index.get('encryption_enabled', False)
    if enc:
        print('  Encryption: Enabled')
    print(f'  Total backups: {len(backups)}')
    print()
    for i, b in enumerate(backups):
        bid = b.get('backup_id', '?')
        fc = b.get('files_count', 0)
        dc = b.get('databases_count', 0)
        size = b.get('total_size_bytes', 0)
        # Format size
        if size < 1024: sz = f'{size} B'
        elif size < 1048576: sz = f'{size//1024} KB'
        elif size < 1073741824: sz = f'{size//1048576:.1f} MB'
        else: sz = f'{size/1073741824:.1f} GB'
        # Format timestamp from backup_id
        if len(bid) >= 15:
            ts = f'{bid[:4]}-{bid[4:6]}-{bid[6:8]} {bid[9:11]}:{bid[11:13]}'
        else:
            ts = bid
        marker = ' (latest)' if i == 0 else ''
        print(f'  {i+1}) {ts}  ({fc} files, {dc} databases, {sz}){marker}')
except Exception as e:
    print(f'  Error reading index: {e}', file=sys.stderr)
" "$index_file"
    else
        echo "  (Install python3 for formatted output)"
        cat "$index_file"
    fi
}

# List all projects on cloud
_list_all_projects() {
    local transport
    transport=$(_cloud_transport)

    if [[ -z "$transport" ]]; then
        echo "No cloud transport configured. Run 'checkpoint cloud setup'." >&2
        return 1
    fi

    echo "Cloud Projects"
    echo "-------------------------------------------"

    # List project directories from cloud
    case "$transport" in
        folder)
            local _count=0
            for dir in "$CLOUD_FOLDER_PATH"/*/; do
                [[ -d "$dir" ]] || continue
                local _name
                _name=$(basename "$dir")
                [[ "$_name" == "*" ]] && continue
                _count=$((_count + 1))
                local _has_index=""
                if [[ -f "$dir/.checkpoint-cloud-index.json" ]]; then
                    _has_index=" (indexed)"
                fi
                echo "  $_count) $_name$_has_index"
            done
            if [[ $_count -eq 0 ]]; then
                echo "  No projects found on cloud."
            fi
            ;;
        rclone|rclone-legacy)
            local remote_path
            if [[ "$transport" == "rclone" ]]; then
                remote_path="${CLOUD_RCLONE_REMOTE}:${CLOUD_RCLONE_PATH:-Backups/Checkpoint}"
            else
                remote_path="${CLOUD_REMOTE_NAME}:${CLOUD_BACKUP_PATH}"
            fi
            local dirs
            dirs=$(rclone lsd "$remote_path" 2>/dev/null) || {
                echo "  Could not list cloud projects." >&2
                return 1
            }
            local _count=0
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local _name
                _name=$(echo "$line" | awk '{print $NF}')
                [[ -z "$_name" ]] && continue
                _count=$((_count + 1))
                echo "  $_count) $_name"
            done <<< "$dirs"
            if [[ $_count -eq 0 ]]; then
                echo "  No projects found on cloud."
            fi
            ;;
    esac
}

# ==============================================================================
# COMMAND: BROWSE
# ==============================================================================

cmd_browse() {
    local project_name="${1:-}"
    local backup_id="${2:-}"
    local use_latest=false

    if [[ -z "$project_name" ]]; then
        echo "Usage: checkpoint cloud browse PROJECT [BACKUP_ID]" >&2
        echo "       checkpoint cloud browse PROJECT --latest" >&2
        return 1
    fi

    # Load project config
    _load_project_by_name "$project_name" 2>/dev/null || true

    # Fetch index
    local index_file
    index_file=$(cloud_fetch_index "$project_name") || {
        echo "No cloud backups found for $project_name" >&2
        return 1
    }

    # Resolve backup ID
    if [[ -z "$backup_id" ]] || [[ "$backup_id" == "latest" ]] || [[ "$use_latest" == "true" ]]; then
        if [[ -z "$backup_id" ]] && [[ "$use_latest" != "true" ]]; then
            # Interactive backup selection
            backup_id=$(_select_backup_interactive "$index_file" "$project_name")
            if [[ -z "$backup_id" ]]; then
                return 1
            fi
        else
            backup_id=$(_resolve_latest_backup "$index_file")
            if [[ -z "$backup_id" ]]; then
                echo "No backups found for $project_name" >&2
                return 1
            fi
        fi
    fi

    # Fetch manifest
    local manifest_file
    manifest_file=$(cloud_fetch_manifest "$project_name" "$backup_id") || {
        echo "Could not fetch manifest for backup $backup_id" >&2
        return 1
    }

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cloud_manifest_to_json "$manifest_file"
        return 0
    fi

    # Interactive file browser
    if command -v fzf &>/dev/null && [[ -t 0 ]]; then
        _browse_fzf "$manifest_file" "$project_name" "$backup_id"
    else
        _browse_interactive "$manifest_file" "$project_name" "$backup_id"
    fi
}

# Select backup interactively
_select_backup_interactive() {
    local index_file="$1"
    local project_name="$2"

    if command -v fzf &>/dev/null && [[ -t 0 ]]; then
        # fzf mode
        local selection
        selection=$(python3 -c "
import json, sys
index = json.load(open(sys.argv[1]))
for b in index.get('backups', []):
    bid = b.get('backup_id', '')
    fc = b.get('files_count', 0)
    dc = b.get('databases_count', 0)
    size = b.get('total_size_bytes', 0)
    if size < 1048576: sz = f'{size//1024} KB'
    elif size < 1073741824: sz = f'{size//1048576:.1f} MB'
    else: sz = f'{size/1073741824:.1f} GB'
    if len(bid) >= 15:
        ts = f'{bid[:4]}-{bid[4:6]}-{bid[6:8]} {bid[9:11]}:{bid[11:13]}'
    else:
        ts = bid
    print(f'{bid}\t{ts}  ({fc} files, {dc} databases, {sz})')
" "$index_file" 2>/dev/null | fzf --delimiter='\t' --with-nth=2 --header="Select backup for $project_name" --height=15 --reverse)
        echo "${selection%%	*}"
    else
        # Numbered list
        echo "" >&2
        echo "Available backups for $project_name:" >&2

        local backup_ids=()
        if command -v python3 &>/dev/null; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local _bid="${line%%|*}"
                local _display="${line#*|}"
                backup_ids+=("$_bid")
                echo "  ${#backup_ids[@]}) $_display" >&2
            done < <(python3 -c "
import json, sys
index = json.load(open(sys.argv[1]))
for b in index.get('backups', []):
    bid = b.get('backup_id', '')
    fc = b.get('files_count', 0)
    dc = b.get('databases_count', 0)
    size = b.get('total_size_bytes', 0)
    if size < 1048576: sz = f'{size//1024} KB'
    elif size < 1073741824: sz = f'{size//1048576:.1f} MB'
    else: sz = f'{size/1073741824:.1f} GB'
    if len(bid) >= 15:
        ts = f'{bid[:4]}-{bid[4:6]}-{bid[6:8]} {bid[9:11]}:{bid[11:13]}'
    else:
        ts = bid
    print(f'{bid}|{ts}  ({fc} files, {dc} databases, {sz})')
" "$index_file" 2>/dev/null)
        fi

        if [[ ${#backup_ids[@]} -eq 0 ]]; then
            echo "  No backups found." >&2
            return
        fi

        echo "" >&2
        read -p "Select backup [1]: " choice <&2
        choice="${choice:-1}"

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#backup_ids[@]} ]]; then
            echo "${backup_ids[$((choice - 1))]}"
        else
            echo "Invalid selection" >&2
            return
        fi
    fi
}

# Browse files using fzf
_browse_fzf() {
    local manifest_file="$1"
    local project_name="$2"
    local backup_id="$3"

    local selection
    selection=$(python3 -c "
import json, sys
m = json.load(open(sys.argv[1]))
for f in m.get('files', []):
    path = f.get('path', '')
    size = f.get('size', 0)
    if size < 1024: sz = f'{size} B'
    elif size < 1048576: sz = f'{size//1024} KB'
    else: sz = f'{size//1048576:.1f} MB'
    print(f'{path}\t{sz}')
for d in m.get('databases', []):
    path = d.get('path', '')
    size = d.get('size', 0)
    if size < 1024: sz = f'{size} B'
    elif size < 1048576: sz = f'{size//1024} KB'
    else: sz = f'{size//1048576:.1f} MB'
    tables = d.get('tables', '')
    extra = f' ({tables} tables)' if tables else ''
    print(f'{path}\t{sz}{extra}')
" "$manifest_file" 2>/dev/null | fzf --delimiter='\t' --with-nth=1,2 --header="Browse $project_name @ $backup_id  |  Enter=download" --height=20 --reverse --multi)

    if [[ -z "$selection" ]]; then
        return 0
    fi

    # Download each selected file
    while IFS= read -r line; do
        local rel_path="${line%%	*}"
        [[ -z "$rel_path" ]] && continue
        echo "Downloading: $rel_path"
        local result
        result=$(cloud_download_file "$project_name" "$backup_id" "$rel_path")
        if [[ $? -eq 0 ]]; then
            echo "  Saved: $result"
        else
            echo "  Failed to download $rel_path" >&2
        fi
    done <<< "$selection"
}

# Browse files with numbered list (no fzf)
_browse_interactive() {
    local manifest_file="$1"
    local project_name="$2"
    local backup_id="$3"

    local formatted_id
    formatted_id=$(_format_timestamp "$backup_id")

    echo ""
    echo "Backup: $project_name @ $formatted_id"
    echo "-------------------------------------------"

    local file_paths=()
    local file_display=()

    if command -v python3 &>/dev/null; then
        while IFS='|' read -r path display; do
            [[ -z "$path" ]] && continue
            file_paths+=("$path")
            file_display+=("$display")
        done < <(python3 -c "
import json, sys
m = json.load(open(sys.argv[1]))
print('|FILES:', file=sys.stderr)
for f in m.get('files', []):
    path = f.get('path', '')
    size = f.get('size', 0)
    if size < 1024: sz = f'{size} B'
    elif size < 1048576: sz = f'{size//1024} KB'
    else: sz = f'{size//1048576:.1f} MB'
    print(f'{path}|{path:<40s} {sz:>10s}')
for d in m.get('databases', []):
    path = d.get('path', '')
    size = d.get('size', 0)
    if size < 1024: sz = f'{size} B'
    elif size < 1048576: sz = f'{size//1024} KB'
    else: sz = f'{size//1048576:.1f} MB'
    tables = d.get('tables', '')
    extra = f' ({tables} tables)' if tables else ''
    print(f'{path}|{path:<40s} {sz:>10s}{extra}')
" "$manifest_file" 2>/dev/null)
    fi

    if [[ ${#file_paths[@]} -eq 0 ]]; then
        echo "  No files found in manifest."
        return 0
    fi

    echo ""
    echo "Files:"
    for i in "${!file_paths[@]}"; do
        printf "  %3d) %s\n" "$((i + 1))" "${file_display[$i]}"
    done

    echo ""
    echo "Select file(s) to download [all/1-3/1,3/q]: "
    read -r selection

    case "$selection" in
        q|Q|"")
            return 0
            ;;
        all|a|A)
            echo ""
            echo "Downloading all files..."
            local result
            result=$(cloud_download_all "$project_name" "$backup_id")
            echo "Done: $result"
            ;;
        *)
            # Parse selection: supports "1", "1,3", "1-5"
            local indices=()
            IFS=',' read -ra parts <<< "$selection"
            for part in "${parts[@]}"; do
                part=$(echo "$part" | tr -d ' ')
                if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    for (( j=${BASH_REMATCH[1]}; j<=${BASH_REMATCH[2]}; j++ )); do
                        indices+=("$j")
                    done
                elif [[ "$part" =~ ^[0-9]+$ ]]; then
                    indices+=("$part")
                fi
            done

            for idx in "${indices[@]}"; do
                local arr_idx=$((idx - 1))
                if [[ $arr_idx -ge 0 ]] && [[ $arr_idx -lt ${#file_paths[@]} ]]; then
                    local rel_path="${file_paths[$arr_idx]}"
                    echo "Downloading: $rel_path"
                    local result
                    result=$(cloud_download_file "$project_name" "$backup_id" "$rel_path")
                    if [[ $? -eq 0 ]]; then
                        echo "  Saved: $result"
                    else
                        echo "  Failed to download $rel_path" >&2
                    fi
                fi
            done
            ;;
    esac
}

# ==============================================================================
# COMMAND: DOWNLOAD
# ==============================================================================

cmd_download() {
    local file_path="$1"
    local project_name="${OPT_PROJECT:-}"
    local backup_id="${OPT_BACKUP_ID:-latest}"
    local output_dir="${OPT_OUTPUT:-$HOME/Downloads}"

    if [[ -z "$file_path" ]]; then
        echo "Usage: checkpoint cloud download FILE --project NAME [--backup-id ID]" >&2
        return 1
    fi

    if [[ -z "$project_name" ]]; then
        # Try current directory project name
        project_name="${PROJECT_NAME:-$(basename "$PWD")}"
    fi

    # Load project config
    _load_project_by_name "$project_name" 2>/dev/null || true

    # Resolve latest backup ID
    if [[ "$backup_id" == "latest" ]]; then
        local index_file
        index_file=$(cloud_fetch_index "$project_name") || {
            echo "Could not fetch cloud index for $project_name" >&2
            return 1
        }
        backup_id=$(_resolve_latest_backup "$index_file")
        if [[ -z "$backup_id" ]]; then
            echo "No backups found for $project_name" >&2
            return 1
        fi
    fi

    echo "Downloading: $file_path"
    echo "  Project:   $project_name"
    echo "  Backup:    $backup_id"
    echo "  Output:    $output_dir"
    echo ""

    local result
    result=$(cloud_download_file "$project_name" "$backup_id" "$file_path" "$output_dir")
    local rc=$?

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        if [[ $rc -eq 0 ]]; then
            printf '{"success": true, "file": "%s", "path": "%s"}\n' "$file_path" "$result"
        else
            printf '{"success": false, "file": "%s", "error": "download failed"}\n' "$file_path"
        fi
    else
        if [[ $rc -eq 0 ]]; then
            echo "Downloaded: $result"
        else
            echo "Failed to download $file_path" >&2
            return 1
        fi
    fi
}

# ==============================================================================
# COMMAND: DOWNLOAD-ALL
# ==============================================================================

cmd_download_all() {
    local project_name="${OPT_PROJECT:-}"
    local backup_id="${OPT_BACKUP_ID:-latest}"
    local output_dir="${OPT_OUTPUT:-$HOME/Downloads}"
    local as_zip="${OPT_ZIP:-}"

    if [[ -z "$project_name" ]]; then
        project_name="${PROJECT_NAME:-$(basename "$PWD")}"
    fi

    # Load project config
    _load_project_by_name "$project_name" 2>/dev/null || true

    # Resolve latest backup ID
    if [[ "$backup_id" == "latest" ]]; then
        local index_file
        index_file=$(cloud_fetch_index "$project_name") || {
            echo "Could not fetch cloud index for $project_name" >&2
            return 1
        }
        backup_id=$(_resolve_latest_backup "$index_file")
        if [[ -z "$backup_id" ]]; then
            echo "No backups found for $project_name" >&2
            return 1
        fi
    fi

    echo "Downloading entire backup..."
    echo "  Project:   $project_name"
    echo "  Backup:    $backup_id"
    echo "  Output:    $output_dir"
    if [[ "$as_zip" == "zip" ]]; then
        echo "  Format:    ZIP archive"
    fi
    echo ""

    local result
    result=$(cloud_download_all "$project_name" "$backup_id" "$output_dir" "$as_zip")
    local rc=$?

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        if [[ $rc -eq 0 ]]; then
            printf '{"success": true, "path": "%s"}\n' "$result"
        else
            printf '{"success": false, "error": "download failed"}\n'
        fi
    else
        if [[ $rc -eq 0 ]]; then
            echo ""
            echo "Done: $result"
        else
            echo "Download failed" >&2
            return 1
        fi
    fi
}

# ==============================================================================
# COMMAND: SYNC-INDEX
# ==============================================================================

cmd_sync_index() {
    echo "Refreshing cloud index cache..."

    # Clear cache
    rm -rf "$CLOUD_CACHE_DIR" 2>/dev/null || true
    mkdir -p "$CLOUD_CACHE_DIR"

    # Re-fetch for known projects
    local _count=0
    if type list_projects &>/dev/null; then
        while IFS= read -r _project_path; do
            [[ -z "$_project_path" ]] && continue
            local _name
            _name=$(basename "$_project_path")

            # Load project config to get cloud settings
            if [[ -f "$_project_path/.backup-config.sh" ]]; then
                (
                    source "$_project_path/.backup-config.sh" 2>/dev/null || true
                    if cloud_fetch_index "$_name" &>/dev/null; then
                        echo "  Synced: $_name"
                    fi
                )
                _count=$((_count + 1))
            fi
        done < <(list_projects 2>/dev/null)
    fi

    echo ""
    echo "Done. Refreshed $_count project indexes."
}

# ==============================================================================
# COMMAND: SETUP
# ==============================================================================

cmd_setup() {
    echo "Checkpoint Cloud Setup"
    echo "============================================="
    echo ""

    # Step 1: Check age
    echo "Step 1: Encryption Key"
    echo "---------------------------------------------"
    if command -v age &>/dev/null; then
        echo "  age is installed."
    else
        echo "  age is NOT installed."
        echo ""
        echo "  Install with: brew install age"
        echo ""
        read -p "  Continue without encryption? [y/N]: " _continue
        if [[ "$_continue" != "y" ]] && [[ "$_continue" != "Y" ]]; then
            echo "Install age first, then re-run setup."
            return 1
        fi
    fi

    local key_path="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"
    if [[ -f "$key_path" ]]; then
        echo "  Encryption key found: $key_path"
    else
        echo ""
        echo "  No encryption key found."
        read -p "  Do you have an existing age key? [y/N]: " _has_key
        if [[ "$_has_key" == "y" ]] || [[ "$_has_key" == "Y" ]]; then
            read -p "  Enter path to your age key file: " _key_path
            if [[ -f "$_key_path" ]]; then
                mkdir -p "$(dirname "$key_path")" 2>/dev/null || true
                cp "$_key_path" "$key_path"
                chmod 600 "$key_path"
                echo "  Key imported to $key_path"
            else
                echo "  File not found: $_key_path" >&2
                return 1
            fi
        else
            echo "  Generating new encryption key..."
            if type generate_encryption_key &>/dev/null; then
                generate_encryption_key
            else
                echo "  Run: checkpoint encrypt setup"
            fi
        fi
    fi

    echo ""

    # Step 2: Cloud access
    echo "Step 2: Cloud Access"
    echo "---------------------------------------------"
    local transport
    transport=$(_cloud_transport)

    if [[ -n "$transport" ]]; then
        echo "  Cloud already configured: $transport"
    else
        echo "  No cloud access configured."
        echo ""
        echo "  Options:"
        echo "    1) Cloud folder (Dropbox/iCloud/Google Drive)"
        echo "    2) rclone remote (S3, B2, any provider)"
        echo "    0) Skip for now"
        echo ""
        read -p "  Choose [0]: " _cloud_choice
        case "$_cloud_choice" in
            1)
                read -p "  Enter cloud folder path: " _cloud_path
                if [[ -d "$_cloud_path" ]]; then
                    echo ""
                    echo "  Add to your global config (~/.config/checkpoint/config.sh):"
                    echo "    CLOUD_FOLDER_ENABLED=true"
                    echo "    CLOUD_FOLDER_PATH=\"$_cloud_path\""
                else
                    echo "  Path not found: $_cloud_path" >&2
                fi
                ;;
            2)
                echo "  Running rclone config..."
                if command -v rclone &>/dev/null; then
                    rclone config
                else
                    echo "  rclone not installed. Install with: brew install rclone"
                fi
                ;;
        esac
    fi

    echo ""

    # Step 3: Test connection
    echo "Step 3: Test Connection"
    echo "---------------------------------------------"
    transport=$(_cloud_transport)
    if [[ -n "$transport" ]]; then
        echo "  Testing cloud access..."
        # Try to list projects
        _list_all_projects 2>/dev/null || echo "  Could not list projects (this is OK for a fresh setup)"
    else
        echo "  Skipped (no cloud configured)"
    fi

    echo ""
    echo "Setup complete!"
}

# ==============================================================================
# ARGUMENT PARSING & DISPATCH
# ==============================================================================

# Parse global options
OPT_PROJECT=""
OPT_BACKUP_ID=""
OPT_OUTPUT=""
OPT_ZIP=""
COMMAND=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --project|-p)
            OPT_PROJECT="$2"
            shift 2
            ;;
        --backup-id|-b)
            OPT_BACKUP_ID="$2"
            shift 2
            ;;
        --output|-o)
            OPT_OUTPUT="$2"
            shift 2
            ;;
        --zip)
            OPT_ZIP="zip"
            shift
            ;;
        --latest)
            OPT_BACKUP_ID="latest"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Extract command from positional args
COMMAND="${POSITIONAL_ARGS[0]:-status}"

case "$COMMAND" in
    status)
        cmd_status
        ;;
    list)
        cmd_list "${POSITIONAL_ARGS[1]:-}"
        ;;
    browse)
        cmd_browse "${POSITIONAL_ARGS[1]:-}" "${POSITIONAL_ARGS[2]:-${OPT_BACKUP_ID:-}}"
        ;;
    download)
        cmd_download "${POSITIONAL_ARGS[1]:-}"
        ;;
    download-all)
        cmd_download_all
        ;;
    sync-index)
        cmd_sync_index
        ;;
    setup)
        cmd_setup
        ;;
    --help|-h)
        show_help
        ;;
    *)
        echo "Unknown cloud command: $COMMAND" >&2
        echo "Use 'checkpoint cloud --help' for usage information" >&2
        exit 1
        ;;
esac
