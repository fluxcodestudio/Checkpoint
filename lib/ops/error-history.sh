#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Error History
# ==============================================================================
# Append-only error history per project (capped at 100 entries)
# Location: ~/.claudecode-backups/state/{name}/error-history.log
# Format: TIMESTAMP|BACKUP_ID|ERROR_COUNT|TOTAL_FILES|ERRORS_SUMMARY
# ==============================================================================

# Append an error history entry after a backup with failures
# Args: $1 = project name, $2 = backup ID, $3 = error count,
#        $4 = total files, $5 = errors summary (one-line)
append_error_history() {
    local project_name="$1"
    local backup_id="$2"
    local error_count="$3"
    local total_files="$4"
    local errors_summary="$5"

    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}/${project_name}"
    local history_file="$state_dir/error-history.log"

    mkdir -p "$state_dir"

    local timestamp
    timestamp="$(date +%Y-%m-%dT%H:%M:%S)"

    # Sanitize summary (remove pipes and newlines)
    errors_summary="${errors_summary//$'\n'/ }"
    errors_summary="${errors_summary//|/;}"

    echo "${timestamp}|${backup_id}|${error_count}|${total_files}|${errors_summary}" >> "$history_file"

    # Cap at 100 lines (keep newest)
    if [[ -f "$history_file" ]]; then
        local line_count
        line_count=$(wc -l < "$history_file" | tr -d ' ')
        if [[ "$line_count" -gt 100 ]]; then
            tail -100 "$history_file" > "${history_file}.tmp"
            mv "${history_file}.tmp" "$history_file"
        fi
    fi
}

# Read recent error history entries
# Args: $1 = project name, $2 = count (default 10)
# Output: lines in TIMESTAMP|BACKUP_ID|ERROR_COUNT|TOTAL_FILES|ERRORS_SUMMARY format
read_error_history() {
    local project_name="$1"
    local count="${2:-10}"

    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}/${project_name}"
    local history_file="$state_dir/error-history.log"

    if [[ -f "$history_file" ]]; then
        tail -"$count" "$history_file"
    fi
}
