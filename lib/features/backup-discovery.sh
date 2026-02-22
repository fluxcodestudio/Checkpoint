#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Backup Discovery & Listing
# Find and list database backups and file versions sorted by date
# ==============================================================================
# @requires: none
# @provides: list_database_backups_sorted, list_file_versions_sorted
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_BACKUP_DISCOVERY:-}" ] && return || readonly _CHECKPOINT_BACKUP_DISCOVERY=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ==============================================================================
# BACKUP DISCOVERY & LISTING
# ==============================================================================

# List database backups sorted by date
list_database_backups_sorted() {
    local db_dir="$1"
    local limit="${2:-0}"  # 0 = no limit

    [ ! -d "$db_dir" ] && return 1

    local count=0
    find "$db_dir" \( -name "*.db.gz" -o -name "*.db.gz.age" \
        -o -name "*.sql.gz" -o -name "*.sql.gz.age" \
        -o -name "*.tar.gz" -o -name "*.tar.gz.age" \) -type f 2>/dev/null | while read -r backup; do
        local mtime=$(get_file_mtime "$backup")
        echo "$mtime|$backup"
    done | sort -rn -t'|' | while IFS='|' read -r mtime backup; do
        [ $limit -gt 0 ] && [ $count -ge $limit ] && break

        local filename=$(basename "$backup")
        local size=$(get_file_size "$backup")
        local size_human=$(format_bytes "$size")
        local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
        local relative=$(format_relative_time "$mtime")

        echo "$created|$relative|$size_human|$filename|$backup"
        count=$((count + 1))
    done
}

# List file versions for a specific file
list_file_versions_sorted() {
    local file_path="$1"
    local files_dir="$2"
    local archived_dir="$3"

    local versions=()

    # Current version (check both unencrypted and encrypted)
    local current_path=""
    if [ -f "$files_dir/$file_path" ]; then
        current_path="$files_dir/$file_path"
    elif [ -f "$files_dir/${file_path}.age" ]; then
        current_path="$files_dir/${file_path}.age"
    fi
    if [ -n "$current_path" ]; then
        local mtime=$(get_file_mtime "$current_path")
        local size=$(get_file_size "$current_path")
        local size_human=$(format_bytes "$size")
        local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
        local relative=$(format_relative_time "$mtime")

        echo "$mtime|CURRENT|$created|$relative|$size_human|$current_path"
    fi

    # Archived versions (match both encrypted and unencrypted)
    find "$archived_dir" -type f -name "$(basename "$file_path").*" 2>/dev/null | while read -r backup; do
        local mtime=$(get_file_mtime "$backup")
        local size=$(get_file_size "$backup")
        local size_human=$(format_bytes "$size")
        local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
        local relative=$(format_relative_time "$mtime")
        # Strip .age suffix before extracting version/timestamp
        local base_name
        base_name=$(basename "$backup")
        base_name="${base_name%.age}"
        local version=$(echo "$base_name" | sed "s/.*\.//")

        echo "$mtime|$version|$created|$relative|$size_human|$backup"
    done | sort -rn -t'|'
}
