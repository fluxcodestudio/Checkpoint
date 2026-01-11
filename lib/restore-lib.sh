#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Point-in-Time Restore Library
# ==============================================================================
# Version: 1.0.0
# Description: Point-in-time restore functions for sub-minute recovery
#
# Usage:
#   source "$(dirname "$0")/../lib/restore-lib.sh"
#   versions=$(list_file_versions "src/main.js")
#   snapshot=$(list_files_at_time "2 hours ago")
#   closest=$(find_closest_version "src/main.js" "yesterday 3pm")
# ==============================================================================

# ==============================================================================
# TIME PARSING FUNCTIONS
# ==============================================================================

# Parse various time formats to epoch seconds
# Args: $1 = time string
# Accepts: epoch, "YYYY-MM-DD HH:MM:SS", relative ("2 hours ago", "yesterday 3pm")
# Returns: epoch seconds
parse_time_to_epoch() {
    local input="$1"

    # Already epoch seconds
    if [[ "$input" =~ ^[0-9]+$ ]] && [[ ${#input} -ge 10 ]]; then
        echo "$input"
        return 0
    fi

    # ISO format: YYYY-MM-DD HH:MM:SS or YYYY-MM-DD
    if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                date -j -f "%Y-%m-%d" "$input" "+%s" 2>/dev/null
            else
                date -j -f "%Y-%m-%d %H:%M:%S" "$input" "+%s" 2>/dev/null
            fi
        else
            date -d "$input" "+%s" 2>/dev/null
        fi
        return $?
    fi

    # Relative time parsing
    local now=$(date +%s)

    case "$input" in
        "now")
            echo "$now"
            ;;
        "yesterday")
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -v-1d +%s
            else
                date -d "yesterday" +%s
            fi
            ;;
        "yesterday "*)
            # "yesterday 3pm" style
            local time_part="${input#yesterday }"
            if [[ "$OSTYPE" == "darwin"* ]]; then
                local yesterday=$(date -v-1d +"%Y-%m-%d")
                date -j -f "%Y-%m-%d %I%p" "$yesterday $time_part" "+%s" 2>/dev/null || \
                date -j -f "%Y-%m-%d %H:%M" "$yesterday $time_part" "+%s" 2>/dev/null
            else
                date -d "yesterday $time_part" +%s 2>/dev/null
            fi
            ;;
        *" ago")
            # "X units ago" style
            local amount unit
            read amount unit <<< "${input% ago}"

            case "$unit" in
                second|seconds)
                    echo $((now - amount))
                    ;;
                minute|minutes|min|mins)
                    echo $((now - amount * 60))
                    ;;
                hour|hours|hr|hrs)
                    echo $((now - amount * 3600))
                    ;;
                day|days)
                    echo $((now - amount * 86400))
                    ;;
                week|weeks)
                    echo $((now - amount * 604800))
                    ;;
                *)
                    echo ""
                    return 1
                    ;;
            esac
            ;;
        "last week")
            echo $((now - 604800))
            ;;
        "last month")
            echo $((now - 2592000))
            ;;
        *)
            # Try GNU date parsing
            if [[ "$OSTYPE" != "darwin"* ]]; then
                date -d "$input" +%s 2>/dev/null
            else
                echo ""
                return 1
            fi
            ;;
    esac
}

# ==============================================================================
# FILE VERSION LISTING
# ==============================================================================

# List all versions of a file with timestamps
# Args: $1 = filepath (relative to project)
# Uses: FILES_DIR, ARCHIVED_DIR from config
# Returns: timestamp|size|source_path per line, sorted newest first
list_file_versions() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    local dirpath=$(dirname "$filepath")

    local results=()

    # Current version in files/
    if [[ -f "$FILES_DIR/$filepath" ]]; then
        local mtime=$(stat -f%m "$FILES_DIR/$filepath" 2>/dev/null || stat -c%Y "$FILES_DIR/$filepath" 2>/dev/null)
        local size=$(stat -f%z "$FILES_DIR/$filepath" 2>/dev/null || stat -c%s "$FILES_DIR/$filepath" 2>/dev/null)
        results+=("$mtime|$size|$FILES_DIR/$filepath|current")
    fi

    # Archived versions matching this file
    # Pattern: name.ext.YYYYMMDD_HHMMSS_XXXX
    if [[ -d "$ARCHIVED_DIR" ]]; then
        while IFS= read -r archived_file; do
            [[ -z "$archived_file" ]] && continue

            local archived_basename=$(basename "$archived_file")

            # Extract original filename (remove timestamp suffix)
            local orig_name
            if [[ "$archived_basename" =~ ^(.+)\.[0-9]{8}_[0-9]{6}_[0-9]+$ ]]; then
                orig_name="${BASH_REMATCH[1]}"
            else
                continue
            fi

            # Match if same original filename
            if [[ "$orig_name" == "$filename" ]]; then
                local mtime=$(stat -f%m "$archived_file" 2>/dev/null || stat -c%Y "$archived_file" 2>/dev/null)
                local size=$(stat -f%z "$archived_file" 2>/dev/null || stat -c%s "$archived_file" 2>/dev/null)
                results+=("$mtime|$size|$archived_file|archived")
            fi
        done < <(find "$ARCHIVED_DIR" -type f 2>/dev/null)
    fi

    # Sort by timestamp descending (newest first)
    printf '%s\n' "${results[@]}" | sort -rn -t'|' -k1
}

# List all files as they existed at a point in time
# Args: $1 = target_time (epoch, date string, or relative)
# Returns: filepath|timestamp|size|source_path per line
list_files_at_time() {
    local target_time="$1"
    local target_epoch=$(parse_time_to_epoch "$target_time")

    if [[ -z "$target_epoch" ]] || [[ "$target_epoch" -eq 0 ]]; then
        echo "Error: Invalid time format: $target_time" >&2
        return 1
    fi

    # Build list of all unique files
    declare -A file_versions

    # Collect current files
    if [[ -d "$FILES_DIR" ]]; then
        while IFS= read -r file; do
            local relpath="${file#$FILES_DIR/}"
            local mtime=$(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null)
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)

            # Only include if file existed at target time (mtime <= target)
            if [[ $mtime -le $target_epoch ]]; then
                # Store as: mtime|size|source_path
                if [[ -z "${file_versions[$relpath]}" ]] || \
                   [[ $mtime -gt $(echo "${file_versions[$relpath]}" | cut -d'|' -f1) ]]; then
                    file_versions[$relpath]="$mtime|$size|$file"
                fi
            fi
        done < <(find "$FILES_DIR" -type f 2>/dev/null)
    fi

    # Collect archived files and find closest version for each file
    if [[ -d "$ARCHIVED_DIR" ]]; then
        while IFS= read -r archived_file; do
            [[ -z "$archived_file" ]] && continue

            local archived_basename=$(basename "$archived_file")

            # Extract original filename
            local orig_name
            if [[ "$archived_basename" =~ ^(.+)\.[0-9]{8}_[0-9]{6}_[0-9]+$ ]]; then
                orig_name="${BASH_REMATCH[1]}"
            else
                continue
            fi

            local mtime=$(stat -f%m "$archived_file" 2>/dev/null || stat -c%Y "$archived_file" 2>/dev/null)
            local size=$(stat -f%z "$archived_file" 2>/dev/null || stat -c%s "$archived_file" 2>/dev/null)

            # Only include if file existed at target time (mtime <= target)
            if [[ $mtime -le $target_epoch ]]; then
                local existing="${file_versions[$orig_name]:-}"
                local existing_mtime=0
                [[ -n "$existing" ]] && existing_mtime=$(echo "$existing" | cut -d'|' -f1)

                # Keep version closest to (but before) target
                if [[ $mtime -gt $existing_mtime ]]; then
                    file_versions[$orig_name]="$mtime|$size|$archived_file"
                fi
            fi
        done < <(find "$ARCHIVED_DIR" -type f 2>/dev/null)
    fi

    # Output results
    for relpath in "${!file_versions[@]}"; do
        echo "$relpath|${file_versions[$relpath]}"
    done | sort
}

# Find the version of a file closest to a target time
# Args: $1 = filepath (relative), $2 = target_time
# Returns: path to the backup file that was current at target_time
find_closest_version() {
    local filepath="$1"
    local target_time="$2"
    local target_epoch=$(parse_time_to_epoch "$target_time")

    if [[ -z "$target_epoch" ]] || [[ "$target_epoch" -eq 0 ]]; then
        echo "Error: Invalid time format: $target_time" >&2
        return 1
    fi

    local closest_path=""
    local closest_mtime=0
    local closest_diff=999999999

    # Check all versions
    while IFS='|' read -r mtime size path type; do
        [[ -z "$mtime" ]] && continue

        # Only consider versions before or at target time
        if [[ $mtime -le $target_epoch ]]; then
            local diff=$((target_epoch - mtime))
            if [[ $diff -lt $closest_diff ]]; then
                closest_diff=$diff
                closest_mtime=$mtime
                closest_path="$path"
            fi
        fi
    done < <(list_file_versions "$filepath")

    if [[ -n "$closest_path" ]]; then
        echo "$closest_path"
        return 0
    else
        echo "Error: No version found for $filepath at $target_time" >&2
        return 1
    fi
}

# ==============================================================================
# TIMELINE FORMATTING
# ==============================================================================

# Format file versions into timeline display
# Args: $1 = filepath, $2 = show_all (true/false)
# Returns: Formatted timeline string for display
format_file_timeline() {
    local filepath="$1"
    local show_all="${2:-false}"

    local versions=()
    local prev_date=""
    local count=0
    local max_count=20

    [[ "$show_all" == "true" ]] && max_count=999

    echo ""
    echo "  File Timeline: $filepath"
    echo ""

    while IFS='|' read -r mtime size path type; do
        [[ -z "$mtime" ]] && continue
        ((count++))

        [[ $count -gt $max_count ]] && continue

        # Format date header
        local date_str
        local time_str
        local today=$(date +%Y-%m-%d)
        local yesterday
        if [[ "$OSTYPE" == "darwin"* ]]; then
            yesterday=$(date -v-1d +%Y-%m-%d)
        else
            yesterday=$(date -d "yesterday" +%Y-%m-%d)
        fi

        local file_date=$(date -r "$mtime" +%Y-%m-%d 2>/dev/null)

        if [[ "$file_date" == "$today" ]]; then
            date_str="Today"
        elif [[ "$file_date" == "$yesterday" ]]; then
            date_str="Yesterday"
        else
            date_str=$(date -r "$mtime" +"%b %d" 2>/dev/null)
        fi

        # Print date header if changed
        if [[ "$date_str" != "$prev_date" ]]; then
            [[ -n "$prev_date" ]] && echo ""
            echo "  $date_str"
            prev_date="$date_str"
        fi

        time_str=$(date -r "$mtime" +"%H:%M:%S" 2>/dev/null)
        local size_human=$(format_file_size "$size")

        local marker=""
        [[ "$type" == "current" ]] && marker="[current]"

        printf "    %-2d. %s  %-10s  %8s\n" "$count" "$time_str" "$marker" "$size_human"
    done < <(list_file_versions "$filepath")

    local total_count=$count
    if [[ $total_count -gt $max_count ]] && [[ "$show_all" != "true" ]]; then
        echo ""
        echo "  [Showing $max_count of $total_count versions - use --all for full history]"
    fi
}

# Format file size for display
format_file_size() {
    local bytes="$1"

    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes} B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}") KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}") GB"
    fi
}

# Calculate size delta between two versions
# Args: $1 = current_size, $2 = previous_size
# Returns: "+N bytes" or "-N bytes" or "(no change)"
format_size_delta() {
    local current="$1"
    local previous="$2"

    if [[ -z "$previous" ]] || [[ "$previous" == "0" ]]; then
        echo ""
        return
    fi

    local delta=$((current - previous))

    if [[ $delta -eq 0 ]]; then
        echo "(no change)"
    elif [[ $delta -gt 0 ]]; then
        echo "(+$(format_file_size $delta))"
    else
        echo "($(format_file_size ${delta#-}))"
    fi
}
