#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Backup Diff Library
# Snapshot discovery, rsync dry-run comparison, and restic-style formatting
# ==============================================================================
# @requires: core/config (for get_backup_excludes)
# @provides: discover_snapshots, compare_current_to_backup, format_diff_text,
#            format_diff_json, get_file_at_snapshot
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_BACKUP_DIFF:-}" ] && return || readonly _CHECKPOINT_BACKUP_DIFF=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Source config for get_backup_excludes
if ! declare -f get_backup_excludes >/dev/null 2>&1; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/config.sh"
fi

# ==============================================================================
# GLOBAL DIFF ARRAYS
# ==============================================================================
# These arrays are set by compare_current_to_backup() and read by format_diff_*
# Bash functions cannot return arrays, so globals are the interface.
DIFF_ADDED=()
DIFF_MODIFIED=()
DIFF_REMOVED=()

# ==============================================================================
# SNAPSHOT DISCOVERY
# ==============================================================================

# Extract unique backup timestamps from archived/ file suffixes
# Args: $1 = archived directory path
# Returns: newline-separated timestamps (YYYYMMDD_HHMMSS), most recent first
# Sets: nothing (output on stdout)
discover_snapshots() {
    local archived_dir="$1"

    if [ ! -d "$archived_dir" ]; then
        return 1
    fi

    # Find all files, extract timestamp suffixes, deduplicate, sort newest first
    # Handles both .YYYYMMDD_HHMMSS_PID and .YYYYMMDD_HHMMSS patterns
    find "$archived_dir" -type f 2>/dev/null \
        | sed -n 's/.*\.\([0-9]\{8\}_[0-9]\{6\}\)\(_[0-9]*\)\{0,1\}$/\1/p' \
        | sort -u -r
}

# ==============================================================================
# RSYNC DRY-RUN COMPARISON
# ==============================================================================

# Compare current project directory against its last backup snapshot
# Args: $1 = project directory, $2 = files (backup) directory
# Returns: 0 on success, 1 on error
# Sets: DIFF_ADDED, DIFF_MODIFIED, DIFF_REMOVED (global arrays)
compare_current_to_backup() {
    local project_dir="$1"
    local files_dir="$2"

    # Reset global arrays
    DIFF_ADDED=()
    DIFF_MODIFIED=()
    DIFF_REMOVED=()

    if [ ! -d "$project_dir" ]; then
        return 1
    fi
    if [ ! -d "$files_dir" ]; then
        return 1
    fi

    # Build exclude arguments from centralized config
    local exclude_args=()
    local line
    while IFS= read -r line; do
        exclude_args[${#exclude_args[@]}]="$line"
    done < <(get_backup_excludes)

    # Run rsync dry-run to discover differences
    local rsync_output
    rsync_output=$(mktemp)

    rsync --archive --no-links --dry-run --delete \
        --itemize-changes --out-format="%i %n" \
        "${exclude_args[@]}" \
        "$project_dir/" "$files_dir/" > "$rsync_output" 2>/dev/null || true

    # Parse rsync itemize-changes output
    local indicator filepath
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue

        indicator="${line%% *}"
        filepath="${line#* }"

        # Skip directory entries (contain 'd' in position 2)
        case "$indicator" in
            ??d*) continue ;;
        esac

        # Classify changes by rsync itemize indicator
        case "$indicator" in
            '>f+++++++++'|'>f++++++++++')
                # New file (all attributes are new)
                DIFF_ADDED[${#DIFF_ADDED[@]}]="$filepath"
                ;;
            '>f'*)
                # Modified file (some attributes changed)
                DIFF_MODIFIED[${#DIFF_MODIFIED[@]}]="$filepath"
                ;;
            '*deleting')
                # File exists in backup but not in source
                DIFF_REMOVED[${#DIFF_REMOVED[@]}]="$filepath"
                ;;
        esac
    done < "$rsync_output"

    rm -f "$rsync_output"
    return 0
}

# ==============================================================================
# OUTPUT FORMATTING
# ==============================================================================

# Print restic-style diff output from DIFF_* arrays
# Args: none (reads DIFF_ADDED, DIFF_MODIFIED, DIFF_REMOVED globals)
# Returns: 0
# Sets: nothing (output on stdout)
format_diff_text() {
    local added_count=${#DIFF_ADDED[@]}
    local removed_count=${#DIFF_REMOVED[@]}
    local modified_count=${#DIFF_MODIFIED[@]}
    local total=$((added_count + removed_count + modified_count))

    if [ "$total" -eq 0 ]; then
        echo "No changes detected."
        return 0
    fi

    # Print added files
    local i=0
    while [ "$i" -lt "$added_count" ]; do
        echo "+  ${DIFF_ADDED[$i]}"
        i=$((i + 1))
    done

    # Print removed files
    i=0
    while [ "$i" -lt "$removed_count" ]; do
        echo "-  ${DIFF_REMOVED[$i]}"
        i=$((i + 1))
    done

    # Print modified files
    i=0
    while [ "$i" -lt "$modified_count" ]; do
        echo "M  ${DIFF_MODIFIED[$i]}"
        i=$((i + 1))
    done

    echo ""
    echo "Files: $added_count new, $removed_count removed, $modified_count modified"

    return 0
}

# Print JSON diff output from DIFF_* arrays
# Args: none (reads DIFF_ADDED, DIFF_MODIFIED, DIFF_REMOVED globals)
# Returns: 0
# Sets: nothing (output on stdout)
format_diff_json() {
    local added_count=${#DIFF_ADDED[@]}
    local removed_count=${#DIFF_REMOVED[@]}
    local modified_count=${#DIFF_MODIFIED[@]}

    # Helper: build a JSON array string from a bash array
    # Uses printf to construct properly escaped JSON
    _json_array() {
        local count="$1"
        shift
        local arr=("$@")

        if [ "$count" -eq 0 ]; then
            printf '[]'
            return
        fi

        printf '['
        local i=0
        while [ "$i" -lt "$count" ]; do
            [ "$i" -gt 0 ] && printf ','
            # Escape backslashes and double quotes for JSON
            local escaped="${arr[$i]//\\/\\\\}"
            escaped="${escaped//\"/\\\"}"
            printf '"%s"' "$escaped"
            i=$((i + 1))
        done
        printf ']'
    }

    printf '{'
    printf '"added":'
    _json_array "$added_count" "${DIFF_ADDED[@]+"${DIFF_ADDED[@]}"}"
    printf ','
    printf '"removed":'
    _json_array "$removed_count" "${DIFF_REMOVED[@]+"${DIFF_REMOVED[@]}"}"
    printf ','
    printf '"modified":'
    _json_array "$modified_count" "${DIFF_MODIFIED[@]+"${DIFF_MODIFIED[@]}"}"
    printf ','
    printf '"summary":{"added":%d,"removed":%d,"modified":%d}' \
        "$added_count" "$removed_count" "$modified_count"
    printf '}\n'

    return 0
}

# ==============================================================================
# FILE VERSION LOOKUP
# ==============================================================================

# Reconstruct which version of a file existed at a given snapshot time
# Finds the archived version closest to but not after the target timestamp.
# Args: $1 = file path (relative), $2 = target timestamp (YYYYMMDD_HHMMSS),
#       $3 = files directory, $4 = archived directory
# Returns: path to the version file on stdout, or returns 1 if not found
# Sets: nothing
get_file_at_snapshot() {
    local file_path="$1"
    local target_timestamp="$2"
    local files_dir="$3"
    local archived_dir="$4"

    if [ ! -d "$archived_dir" ]; then
        return 1
    fi

    local filename
    filename=$(basename "$file_path")
    local file_dir
    file_dir=$(dirname "$file_path")

    # Look for archived versions in the corresponding subdirectory
    local search_dir="$archived_dir"
    if [ "$file_dir" != "." ]; then
        search_dir="$archived_dir/$file_dir"
    fi

    if [ ! -d "$search_dir" ]; then
        # No archived versions in expected dir - check files_dir as current
        if [ -f "$files_dir/$file_path" ]; then
            echo "$files_dir/$file_path"
            return 0
        fi
        return 1
    fi

    # Find all archived versions of this file, extract timestamps, sort ascending
    local best_match=""
    local best_ts=""

    local candidate
    while IFS= read -r candidate; do
        [ -z "$candidate" ] && continue
        local cname
        cname=$(basename "$candidate")

        # Extract timestamp from archived filename
        local cts=""
        if [[ "$cname" =~ \.([0-9]{8}_[0-9]{6})_[0-9]+$ ]]; then
            cts="${BASH_REMATCH[1]}"
        elif [[ "$cname" =~ \.([0-9]{8}_[0-9]{6})$ ]]; then
            cts="${BASH_REMATCH[1]}"
        fi

        [ -z "$cts" ] && continue

        # Only consider versions at or before the target timestamp
        if [ "$cts" \> "$target_timestamp" ]; then
            continue
        fi

        # Keep the closest (most recent) version not after target
        if [ -z "$best_ts" ] || [ "$cts" \> "$best_ts" ]; then
            best_ts="$cts"
            best_match="$candidate"
        fi
    done < <(find "$search_dir" -type f -name "${filename}.*" 2>/dev/null)

    if [ -n "$best_match" ]; then
        echo "$best_match"
        return 0
    fi

    # No archived version found before target - check if current version exists
    # (it may have existed unchanged since before the target time)
    if [ -f "$files_dir/$file_path" ]; then
        echo "$files_dir/$file_path"
        return 0
    fi

    return 1
}
