#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cleanup Operations
# Expired/duplicate/orphan detection, single-pass cleanup, recommendations,
# and audit logging
# ==============================================================================
# @requires: core/output (for color functions), ops/file-ops (for get_file_hash)
# @provides: find_expired_backups, find_duplicate_backups,
#            find_orphaned_archives, calculate_total_size, delete_files_batch,
#            cleanup_single_pass, cleanup_execute,
#            generate_cleanup_recommendations, audit_restore, audit_cleanup,
#            CLEANUP_EXPIRED_DBS, CLEANUP_EXPIRED_FILES, CLEANUP_EMPTY_DIRS
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_CLEANUP:-}" ] && return || readonly _CHECKPOINT_CLEANUP=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ==============================================================================
# CLEANUP OPERATIONS
# ==============================================================================

# Find backups older than retention policy
find_expired_backups() {
    local dir="$1"
    local retention_days="$2"
    local pattern="${3:-*}"

    [ ! -d "$dir" ] && return 1

    find "$dir" -name "$pattern" -type f -mtime "+$retention_days" 2>/dev/null
}

# Find duplicate backups (same content hash)
find_duplicate_backups() {
    local dir="$1"
    local pattern="${2:-*.db.gz}"

    [ ! -d "$dir" ] && return 1

    local temp_hashes=$(mktemp)

    # Calculate hashes
    find "$dir" -name "$pattern" -type f 2>/dev/null | while read -r file; do
        local hash=$(md5 -q "$file" 2>/dev/null || md5sum "$file" 2>/dev/null | awk '{print $1}')
        echo "$hash|$file"
    done > "$temp_hashes"

    # Find duplicates
    awk -F'|' '
    {
        hashes[$1]++;
        if (hashes[$1] == 1) {
            first[$1] = $2;
        } else {
            print $2;
        }
    }
    ' "$temp_hashes"

    rm -f "$temp_hashes"
}

# Find orphaned archived files (original no longer exists)
find_orphaned_archives() {
    local archived_dir="$1"
    local files_dir="$2"
    local project_dir="$3"

    [ ! -d "$archived_dir" ] && return 1

    find "$archived_dir" -type f 2>/dev/null | while read -r archived; do
        local rel_path="${archived#$archived_dir/}"
        local base_file="${rel_path%.*}"  # Remove timestamp

        # Check if original exists
        if [ ! -f "$files_dir/$base_file" ] && [ ! -f "$project_dir/$base_file" ]; then
            echo "$archived"
        fi
    done
}

# Calculate total size of file list
calculate_total_size() {
    local total=0
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
            total=$((total + size))
        fi
    done
    echo "$total"
}

# Delete files with summary
delete_files_batch() {
    local dry_run="$1"
    shift
    local files=("$@")

    [ ${#files[@]} -eq 0 ] && return 0

    local total_size=0
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
            total_size=$((total_size + size))
        fi
    done

    local size_human=$(format_bytes "$total_size")

    if [ "$dry_run" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Would delete ${#files[@]} files ($size_human)"
        return 0
    fi

    local deleted=0
    for file in "${files[@]}"; do
        if rm -f "$file" 2>/dev/null; then
            ((deleted++))
        fi
    done

    color_green "✅ Deleted $deleted files ($size_human freed)"

    # Clean up empty directories
    for file in "${files[@]}"; do
        local dir=$(dirname "$file")
        [ -d "$dir" ] && rmdir "$dir" 2>/dev/null || true
    done

    return 0
}

# ==============================================================================
# SINGLE-PASS CLEANUP (Performance Optimization)
# ==============================================================================
# Replaces multiple find traversals with single-pass scanning
# Uses BSD stat -f (macOS compatible) instead of GNU find -printf

# Global arrays to hold cleanup scan results
CLEANUP_EXPIRED_DBS=()
CLEANUP_EXPIRED_FILES=()
CLEANUP_EMPTY_DIRS=()

# Single-pass cleanup scanner - replaces multiple find operations
# Usage: cleanup_single_pass [backup_dir]
cleanup_single_pass() {
    local backup_dir="${1:-$BACKUP_DIR}"
    local db_retention="${DB_RETENTION_DAYS:-30}"
    local file_retention="${FILE_RETENTION_DAYS:-7}"
    local archived_dir="${backup_dir}/archived"
    local database_dir="${backup_dir}/databases"

    # Reset global arrays
    CLEANUP_EXPIRED_DBS=()
    CLEANUP_EXPIRED_FILES=()
    CLEANUP_EMPTY_DIRS=()

    local now
    now=$(date +%s)
    local db_cutoff=$((now - db_retention * 86400))
    local file_cutoff=$((now - file_retention * 86400))

    # Single traversal for databases
    if [ -d "$database_dir" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local file mtime
            file="${line%|*}"
            mtime="${line##*|}"
            [ -n "$mtime" ] && [ "$mtime" -lt "$db_cutoff" ] 2>/dev/null && CLEANUP_EXPIRED_DBS+=("$file")
        done < <(find "$database_dir" -name "*.db.gz" -type f -exec stat -f "%N|%m" {} \; 2>/dev/null)
    fi

    # Single traversal for archived files + empty dirs
    if [ -d "$archived_dir" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local path type_char mtime
            # Parse: path|type|mtime (e.g., "/path/file|Regular File|1234567890")
            path="${line%%|*}"
            local rest="${line#*|}"
            type_char="${rest%%|*}"
            mtime="${rest##*|}"

            if [[ "$type_char" == "Regular File" ]]; then
                [ -n "$mtime" ] && [ "$mtime" -lt "$file_cutoff" ] 2>/dev/null && CLEANUP_EXPIRED_FILES+=("$path")
            elif [[ "$type_char" == "Directory" ]]; then
                # Check if empty (skip archived_dir itself)
                if [ "$path" != "$archived_dir" ] && [ -z "$(ls -A "$path" 2>/dev/null)" ]; then
                    CLEANUP_EMPTY_DIRS+=("$path")
                fi
            fi
        done < <(find "$archived_dir" \( -type f -o -type d \) -exec stat -f "%N|%HT|%m" {} \; 2>/dev/null)
    fi

    # Report counts (only if debug enabled or verbose)
    if [ "${BACKUP_DEBUG:-false}" = "true" ]; then
        echo "Cleanup scan: ${#CLEANUP_EXPIRED_DBS[@]} expired DBs, ${#CLEANUP_EXPIRED_FILES[@]} expired files, ${#CLEANUP_EMPTY_DIRS[@]} empty dirs"
    fi
}

# Execute cleanup based on single-pass scan results
# Usage: cleanup_execute [dry_run]
cleanup_execute() {
    local dry_run="${1:-false}"
    local deleted=0

    # Delete expired database backups
    for f in "${CLEANUP_EXPIRED_DBS[@]}"; do
        [ -z "$f" ] && continue
        if [ "$dry_run" = "true" ]; then
            echo "Would delete DB: $f"
            continue
        fi
        rm -f "$f" && deleted=$((deleted + 1))
    done

    # Delete expired archived files
    for f in "${CLEANUP_EXPIRED_FILES[@]}"; do
        [ -z "$f" ] && continue
        if [ "$dry_run" = "true" ]; then
            echo "Would delete file: $f"
            continue
        fi
        rm -f "$f" && deleted=$((deleted + 1))
    done

    # Delete empty dirs deepest-first (sort by path length descending)
    if [ ${#CLEANUP_EMPTY_DIRS[@]} -gt 0 ]; then
        local sorted_dirs
        sorted_dirs=$(printf '%s\n' "${CLEANUP_EMPTY_DIRS[@]}" | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-)
        while IFS= read -r d; do
            [ -z "$d" ] && continue
            if [ "$dry_run" = "true" ]; then
                echo "Would remove dir: $d"
                continue
            fi
            rmdir "$d" 2>/dev/null && deleted=$((deleted + 1))
        done <<< "$sorted_dirs"
    fi

    if [ "$dry_run" != "true" ] && [ "${BACKUP_DEBUG:-false}" = "true" ]; then
        echo "Cleanup complete: $deleted items removed"
    fi

    return 0
}

# ==============================================================================
# CLEANUP RECOMMENDATIONS
# ==============================================================================

# Analyze backup health and generate recommendations
generate_cleanup_recommendations() {
    local database_dir="$1"
    local files_dir="$2"
    local archived_dir="$3"
    local db_retention="$4"
    local file_retention="$5"

    local recommendations=()

    # Check disk usage
    local disk_usage=$(get_backup_disk_usage)
    if [ $disk_usage -ge 90 ]; then
        recommendations+=("CRITICAL: Disk usage at ${disk_usage}% - Immediate cleanup needed")
    elif [ $disk_usage -ge 80 ]; then
        recommendations+=("WARNING: Disk usage at ${disk_usage}% - Cleanup recommended")
    fi

    # Check for expired backups
    local expired_db=$(find_expired_backups "$database_dir" "$db_retention" "*.db.gz" | wc -l | tr -d ' ')
    if [ $expired_db -gt 0 ]; then
        recommendations+=("$expired_db database backups older than ${db_retention} days")
    fi

    local expired_files=$(find_expired_backups "$archived_dir" "$file_retention" "*" | wc -l | tr -d ' ')
    if [ $expired_files -gt 0 ]; then
        recommendations+=("$expired_files archived files older than ${file_retention} days")
    fi

    # Check for duplicates
    local duplicates=$(find_duplicate_backups "$database_dir" "*.db.gz" | wc -l | tr -d ' ')
    if [ $duplicates -gt 0 ]; then
        recommendations+=("$duplicates duplicate database backups detected")
    fi

    # Check for orphaned archives
    local orphaned=$(find_orphaned_archives "$archived_dir" "$files_dir" "${PROJECT_DIR:-}" | wc -l | tr -d ' ')
    if [ $orphaned -gt 0 ]; then
        recommendations+=("$orphaned orphaned archived files (original deleted)")
    fi

    # Output recommendations
    for rec in "${recommendations[@]}"; do
        echo "$rec"
    done
}

# ==============================================================================
# AUDIT LOGGING
# ==============================================================================

# Log restore operation to audit log
audit_restore() {
    local audit_file="${BACKUP_DIR:-}/audit.log"
    local operation="$1"
    local source="$2"
    local target="$3"

    mkdir -p "$(dirname "$audit_file")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RESTORE $operation: $source -> $target" >> "$audit_file"
}

# Log cleanup operation to audit log
audit_cleanup() {
    local audit_file="${BACKUP_DIR:-}/audit.log"
    local operation="$1"
    local count="$2"
    local size="$3"

    mkdir -p "$(dirname "$audit_file")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] CLEANUP $operation: Deleted $count files ($size)" >> "$audit_file"
}
