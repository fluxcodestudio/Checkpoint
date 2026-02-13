#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Backup Discovery & Listing
# Find and list database backups and file versions sorted by date
# ==============================================================================
# @requires: none
# @provides: list_database_backups_sorted, list_file_versions_sorted
# ==============================================================================

# Include guard
[ -n "$_CHECKPOINT_BACKUP_DISCOVERY" ] && return || readonly _CHECKPOINT_BACKUP_DISCOVERY=1

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
    find "$db_dir" -name "*.db.gz" -type f 2>/dev/null | while read -r backup; do
        local mtime=$(stat -f%m "$backup" 2>/dev/null || stat -c%Y "$backup" 2>/dev/null)
        echo "$mtime|$backup"
    done | sort -rn -t'|' | while IFS='|' read -r mtime backup; do
        [ $limit -gt 0 ] && [ $count -ge $limit ] && break

        local filename=$(basename "$backup")
        local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
        local size_human=$(format_bytes "$size")
        local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
        local relative=$(format_relative_time "$mtime")

        echo "$created|$relative|$size_human|$filename|$backup"
        ((count++))
    done
}

# List file versions for a specific file
list_file_versions_sorted() {
    local file_path="$1"
    local files_dir="$2"
    local archived_dir="$3"

    local versions=()

    # Current version
    if [ -f "$files_dir/$file_path" ]; then
        local mtime=$(stat -f%m "$files_dir/$file_path" 2>/dev/null || stat -c%Y "$files_dir/$file_path" 2>/dev/null)
        local size=$(stat -f%z "$files_dir/$file_path" 2>/dev/null || stat -c%s "$files_dir/$file_path" 2>/dev/null)
        local size_human=$(format_bytes "$size")
        local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
        local relative=$(format_relative_time "$mtime")

        echo "$mtime|CURRENT|$created|$relative|$size_human|$files_dir/$file_path"
    fi

    # Archived versions
    find "$archived_dir" -type f -name "$(basename "$file_path").*" 2>/dev/null | while read -r backup; do
        local mtime=$(stat -f%m "$backup" 2>/dev/null || stat -c%Y "$backup" 2>/dev/null)
        local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
        local size_human=$(format_bytes "$size")
        local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
        local relative=$(format_relative_time "$mtime")
        local version=$(basename "$backup" | sed "s/.*\.//")

        echo "$mtime|$version|$created|$relative|$size_human|$backup"
    done | sort -rn -t'|'
}
