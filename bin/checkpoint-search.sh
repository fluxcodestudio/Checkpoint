#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Search & Browse CLI
# Search file paths/content across backups, browse snapshots interactively
# Usage: checkpoint-search.sh [MODE] [OPTIONS] [PATTERN]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Source foundation library (loads core, ops, ui, platform, features)
source "$LIB_DIR/backup-lib.sh"

# Source retention policy (for extract_timestamp)
source "$LIB_DIR/retention-policy.sh"

# Source diff library (for discover_snapshots)
source "$LIB_DIR/features/backup-diff.sh"

# Source discovery library
source "$LIB_DIR/features/backup-discovery.sh"

# ==============================================================================
# COLORS
# ==============================================================================

if [[ -t 1 ]]; then
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_DIM='\033[2m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_DIM='' C_BOLD='' C_RESET=''
fi

# ==============================================================================
# HELP TEXT
# ==============================================================================

show_help() {
    cat <<EOF
Checkpoint - Search & Browse

USAGE
    checkpoint search <pattern>              Search file paths in backups
    checkpoint search --content <pattern>    Search file contents in backups
    checkpoint browse                        Interactively browse snapshots

SEARCH OPTIONS
    --content           Search file contents instead of paths
    --decrypt           Decrypt .age files before content search
    --since YYYYMMDD    Only show results from this date onward
    --last N            Only show results from last N snapshots
    --limit N           Max results (default: 50, 0 for unlimited)
    --json              Output as JSON array
    --plain             One path per line, no color (for piping)

BROWSE OPTIONS
    --json              Output snapshots as JSON (non-interactive)

GENERAL OPTIONS
    --help, -h          Show this help

EXAMPLES
    checkpoint search "app.js"               Find all backed-up files matching app.js
    checkpoint search --content "TODO"        Find files containing "TODO"
    checkpoint search --since 20260101 "*.sh" Search only in backups since Jan 2026
    checkpoint search --json "config"         JSON output for scripting
    checkpoint browse                         Interactive snapshot explorer

EXIT CODES
    0   Success
    1   Error (missing config, backup dir, etc.)
    2   No results found
EOF
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

MODE="search"        # search, browse
SEARCH_CONTENT=false
SEARCH_DECRYPT=false
SEARCH_SINCE=""
SEARCH_LAST=""
SEARCH_LIMIT=50
JSON_OUTPUT=false
PLAIN_OUTPUT=false
SEARCH_PATTERN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        search)
            MODE="search"
            shift
            ;;
        browse)
            MODE="browse"
            shift
            ;;
        --content)
            SEARCH_CONTENT=true
            shift
            ;;
        --decrypt)
            SEARCH_DECRYPT=true
            shift
            ;;
        --since)
            SEARCH_SINCE="${2:-}"
            if [[ -z "$SEARCH_SINCE" ]]; then
                echo "Error: --since requires a date argument (YYYYMMDD)" >&2
                exit 1
            fi
            shift 2
            ;;
        --last)
            SEARCH_LAST="${2:-}"
            if [[ -z "$SEARCH_LAST" ]]; then
                echo "Error: --last requires a number" >&2
                exit 1
            fi
            shift 2
            ;;
        --limit)
            SEARCH_LIMIT="${2:-}"
            if [[ -z "$SEARCH_LIMIT" ]]; then
                echo "Error: --limit requires a number" >&2
                exit 1
            fi
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --plain)
            PLAIN_OUTPUT=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
        *)
            # Positional argument = search pattern
            SEARCH_PATTERN="$1"
            shift
            ;;
    esac
done

# ==============================================================================
# SETUP: Load config and resolve backup destinations
# ==============================================================================

PROJECT_DIR="$PWD"

if ! load_backup_config "$PROJECT_DIR"; then
    echo "No backup configuration found. Run 'checkpoint --project' to set up." >&2
    exit 1
fi

# Resolve backup destinations (sets PRIMARY_FILES_DIR, PRIMARY_ARCHIVED_DIR, etc.)
resolve_backup_destinations

FILES_DIR="${PRIMARY_FILES_DIR:-${BACKUP_DIR:-$PROJECT_DIR/backups}/files}"
ARCHIVED_DIR="${PRIMARY_ARCHIVED_DIR:-${BACKUP_DIR:-$PROJECT_DIR/backups}/archived}"

# ==============================================================================
# UTILITY: Convert YYYYMMDD_HHMMSS timestamp to epoch
# ==============================================================================

timestamp_to_epoch() {
    local ts="$1"
    # ts format: YYYYMMDD_HHMMSS
    local ts_flat="${ts//_/}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -j -f "%Y%m%d%H%M%S" "$ts_flat" +%s 2>/dev/null || echo "0"
    else
        # Linux: parse YYYYMMDDHHMMSS
        local formatted="${ts_flat:0:4}-${ts_flat:4:2}-${ts_flat:6:2} ${ts_flat:8:2}:${ts_flat:10:2}:${ts_flat:12:2}"
        date -d "$formatted" +%s 2>/dev/null || echo "0"
    fi
}

# ==============================================================================
# UTILITY: Format timestamp for display
# ==============================================================================

format_timestamp() {
    local ts="$1"
    local year="${ts:0:4}"
    local month="${ts:4:2}"
    local day="${ts:6:2}"
    local hour="${ts:9:2}"
    local min="${ts:11:2}"
    local sec="${ts:13:2}"
    echo "${year}-${month}-${day} ${hour}:${min}:${sec}"
}

# ==============================================================================
# UTILITY: Extract timestamp from archived filename
# ==============================================================================

extract_ts_from_path() {
    local filepath="$1"
    local basename_stripped
    basename_stripped=$(basename "$filepath")
    # Strip .age suffix
    basename_stripped="${basename_stripped%.age}"
    # Extract YYYYMMDD_HHMMSS (with optional _PID suffix)
    local ts=""
    if [[ "$basename_stripped" =~ \.([0-9]{8}_[0-9]{6})(_[0-9]+)?$ ]]; then
        ts="${BASH_REMATCH[1]}"
    fi
    echo "$ts"
}

# ==============================================================================
# UTILITY: JSON-escape a string
# ==============================================================================

json_escape() {
    local str="$1"
    # Escape backslashes, then double quotes
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    echo "$str"
}

# ==============================================================================
# SEARCH: Path search
# ==============================================================================

search_backup_paths() {
    local pattern="$1"
    local archived_dir="$2"
    local since_ts="$3"   # empty string if not filtering
    local limit="$4"      # 0 for unlimited

    local since_epoch=0
    if [[ -n "$since_ts" ]]; then
        since_epoch=$(timestamp_to_epoch "${since_ts}_000000")
    fi

    local count=0
    local total_found=0

    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue

        total_found=$((total_found + 1))

        # Extract timestamp
        local ts
        ts=$(extract_ts_from_path "$filepath")
        [[ -z "$ts" ]] && continue

        # Filter by --since
        if [[ "$since_epoch" -gt 0 ]]; then
            local file_epoch
            file_epoch=$(timestamp_to_epoch "$ts")
            if [[ "$file_epoch" -lt "$since_epoch" ]]; then
                continue
            fi
        fi

        # Check limit
        if [[ "$limit" -gt 0 ]] && [[ "$count" -ge "$limit" ]]; then
            # Keep counting total but don't output
            continue
        fi

        # Get file info
        local size
        size=$(get_file_size "$filepath")
        local size_human
        size_human=$(format_bytes "$size")

        local file_epoch
        file_epoch=$(timestamp_to_epoch "$ts")
        local relative=""
        if [[ "$file_epoch" -gt 0 ]]; then
            relative=$(format_relative_time "$file_epoch")
        fi

        local encrypted="false"
        case "$filepath" in
            *.age) encrypted="true" ;;
        esac

        # Relative path from archived dir
        local relpath="${filepath#"$archived_dir"/}"

        echo "${ts}|${size_human}|${relative}|${encrypted}|${relpath}|${filepath}"
        count=$((count + 1))

    done < <(find "$archived_dir" -type f -name "*${pattern}*" 2>/dev/null | sort)

    # Return total found count via fd 3 if available, otherwise stderr hint
    if [[ "$limit" -gt 0 ]] && [[ "$total_found" -gt "$limit" ]]; then
        local remaining=$((total_found - limit))
        echo "MORE|${remaining}|${total_found}" >&2
    fi
}

# ==============================================================================
# SEARCH: Content search
# ==============================================================================

search_backup_content() {
    local pattern="$1"
    local archived_dir="$2"
    local decrypt_flag="$3"
    local since_ts="$4"
    local limit="$5"

    local since_epoch=0
    if [[ -n "$since_ts" ]]; then
        since_epoch=$(timestamp_to_epoch "${since_ts}_000000")
    fi

    local count=0
    local total_found=0
    local encrypted_skipped=0

    # Find matching files using grep -rl (skip .age by default)
    local grep_cmd="grep"
    if command -v rg >/dev/null 2>&1; then
        grep_cmd="rg"
    fi

    local tmp_results
    tmp_results=$(mktemp)

    if [[ "$grep_cmd" == "rg" ]]; then
        rg -l --no-messages --glob '!*.age' "$pattern" "$archived_dir" > "$tmp_results" 2>/dev/null || true
    else
        grep -rl --exclude='*.age' "$pattern" "$archived_dir" > "$tmp_results" 2>/dev/null || true
    fi

    # Count encrypted files that were skipped
    encrypted_skipped=$(find "$archived_dir" -type f -name "*.age" 2>/dev/null | wc -l | tr -d ' ')

    # If --decrypt, also search .age files
    if [[ "$decrypt_flag" == "true" ]]; then
        # Source encryption module
        if [[ -f "$LIB_DIR/features/encryption.sh" ]]; then
            source "$LIB_DIR/features/encryption.sh"
            local age_file
            while IFS= read -r age_file; do
                [[ -z "$age_file" ]] && continue
                local tmp_decrypted
                tmp_decrypted=$(mktemp)
                if decrypt_file "$age_file" "$tmp_decrypted" 2>/dev/null; then
                    if grep -q "$pattern" "$tmp_decrypted" 2>/dev/null; then
                        echo "$age_file" >> "$tmp_results"
                    fi
                fi
                rm -f "$tmp_decrypted"
            done < <(find "$archived_dir" -type f -name "*.age" 2>/dev/null)
            encrypted_skipped=0
        else
            echo "Warning: encryption module not found, cannot decrypt .age files" >&2
        fi
    fi

    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        total_found=$((total_found + 1))

        local ts
        ts=$(extract_ts_from_path "$filepath")
        [[ -z "$ts" ]] && continue

        # Filter by --since
        if [[ "$since_epoch" -gt 0 ]]; then
            local file_epoch
            file_epoch=$(timestamp_to_epoch "$ts")
            if [[ "$file_epoch" -lt "$since_epoch" ]]; then
                continue
            fi
        fi

        # Check limit
        if [[ "$limit" -gt 0 ]] && [[ "$count" -ge "$limit" ]]; then
            continue
        fi

        local size
        size=$(get_file_size "$filepath")
        local size_human
        size_human=$(format_bytes "$size")

        local file_epoch
        file_epoch=$(timestamp_to_epoch "$ts")
        local relative=""
        if [[ "$file_epoch" -gt 0 ]]; then
            relative=$(format_relative_time "$file_epoch")
        fi

        local encrypted="false"
        case "$filepath" in
            *.age) encrypted="true" ;;
        esac

        local relpath="${filepath#"$archived_dir"/}"

        echo "${ts}|${size_human}|${relative}|${encrypted}|${relpath}|${filepath}"
        count=$((count + 1))

    done < "$tmp_results"

    rm -f "$tmp_results"

    if [[ "$encrypted_skipped" -gt 0 ]] && [[ "$decrypt_flag" != "true" ]]; then
        echo "ENCRYPTED_SKIPPED|${encrypted_skipped}" >&2
    fi

    if [[ "$limit" -gt 0 ]] && [[ "$total_found" -gt "$limit" ]]; then
        local remaining=$((total_found - limit))
        echo "MORE|${remaining}|${total_found}" >&2
    fi
}

# ==============================================================================
# OUTPUT: Format search results
# ==============================================================================

output_search_results() {
    local results="$1"
    local stderr_info="$2"

    if [[ -z "$results" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"results":[],"count":0}'
        elif [[ "$PLAIN_OUTPUT" != "true" ]]; then
            echo "No results found."
        fi
        return 2
    fi

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        printf '{"results":['
        local first=true
        while IFS='|' read -r ts size_human relative encrypted relpath fullpath; do
            [[ -z "$ts" ]] && continue
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi
            local escaped_relpath
            escaped_relpath=$(json_escape "$relpath")
            local escaped_fullpath
            escaped_fullpath=$(json_escape "$fullpath")
            local formatted_ts
            formatted_ts=$(format_timestamp "$ts")
            printf '{"path":"%s","timestamp":"%s","date":"%s","size":"%s","encrypted":%s}' \
                "$escaped_relpath" "$ts" "$formatted_ts" "$size_human" "$encrypted"
        done <<< "$results"
        local count
        count=$(echo "$results" | grep -c . || true)
        printf '],"count":%d}\n' "$count"
        return 0
    fi

    if [[ "$PLAIN_OUTPUT" == "true" ]]; then
        while IFS='|' read -r ts size_human relative encrypted relpath fullpath; do
            [[ -z "$ts" ]] && continue
            echo "$relpath"
        done <<< "$results"
        return 0
    fi

    # Default: colored table output
    echo -e "${C_BOLD}Search Results${C_RESET}"
    echo ""
    printf "  ${C_BOLD}%-50s  %-20s  %-16s  %-8s  %s${C_RESET}\n" "PATH" "TIMESTAMP" "AGE" "SIZE" "ENC"
    echo "  $(printf '%0.s-' $(seq 1 50))  $(printf '%0.s-' $(seq 1 20))  $(printf '%0.s-' $(seq 1 16))  $(printf '%0.s-' $(seq 1 8))  ---"

    while IFS='|' read -r ts size_human relative encrypted relpath fullpath; do
        [[ -z "$ts" ]] && continue
        local formatted_ts
        formatted_ts=$(format_timestamp "$ts")
        local enc_label=""
        if [[ "$encrypted" == "true" ]]; then
            enc_label="${C_YELLOW}yes${C_RESET}"
        else
            enc_label="${C_DIM}no${C_RESET}"
        fi
        # Truncate long paths
        local display_path="$relpath"
        if [[ ${#display_path} -gt 48 ]]; then
            display_path="...${display_path: -45}"
        fi
        printf "  %-50s  %s  ${C_DIM}%-16s${C_RESET}  %-8s  %b\n" \
            "$display_path" "$formatted_ts" "$relative" "$size_human" "$enc_label"
    done <<< "$results"

    echo ""

    # Show hints from stderr info
    if echo "$stderr_info" | grep -q "^MORE|"; then
        local remaining
        remaining=$(echo "$stderr_info" | grep "^MORE|" | head -1 | cut -d'|' -f2)
        local total
        total=$(echo "$stderr_info" | grep "^MORE|" | head -1 | cut -d'|' -f3)
        echo -e "  ${C_DIM}Showing ${SEARCH_LIMIT} of ${total} results. Use --limit 0 for all.${C_RESET}"
    fi

    if echo "$stderr_info" | grep -q "^ENCRYPTED_SKIPPED|"; then
        local skipped
        skipped=$(echo "$stderr_info" | grep "^ENCRYPTED_SKIPPED|" | head -1 | cut -d'|' -f2)
        echo -e "  ${C_YELLOW}${skipped} encrypted .age file(s) skipped. Use --decrypt to include.${C_RESET}"
    fi

    return 0
}

# ==============================================================================
# MODE: search
# ==============================================================================

if [[ "$MODE" == "search" ]]; then
    if [[ -z "$SEARCH_PATTERN" ]]; then
        echo "Error: search mode requires a pattern argument" >&2
        echo "Usage: checkpoint search <pattern>" >&2
        echo "Use --help for more information" >&2
        exit 1
    fi

    if [[ ! -d "$ARCHIVED_DIR" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"results":[],"count":0,"error":"No archived backups found"}'
        else
            echo "No archived backups found at: $ARCHIVED_DIR" >&2
        fi
        exit 1
    fi

    # Filter by --last N snapshots (convert to --since)
    if [[ -n "$SEARCH_LAST" ]]; then
        snapshots=$(discover_snapshots "$ARCHIVED_DIR" 2>/dev/null || true)
        if [[ -n "$snapshots" ]]; then
            # Get the Nth most recent snapshot timestamp
            local_since=$(echo "$snapshots" | head -n "$SEARCH_LAST" | tail -1)
            if [[ -n "$local_since" ]]; then
                # Extract just the date portion (YYYYMMDD)
                SEARCH_SINCE="${local_since:0:8}"
            fi
        fi
    fi

    # Capture stderr for hints (MORE, ENCRYPTED_SKIPPED)
    stderr_tmp=$(mktemp)

    if [[ "$SEARCH_CONTENT" == "true" ]]; then
        results=$(search_backup_content "$SEARCH_PATTERN" "$ARCHIVED_DIR" "$SEARCH_DECRYPT" "$SEARCH_SINCE" "$SEARCH_LIMIT" 2>"$stderr_tmp")
    else
        results=$(search_backup_paths "$SEARCH_PATTERN" "$ARCHIVED_DIR" "$SEARCH_SINCE" "$SEARCH_LIMIT" 2>"$stderr_tmp")
    fi

    stderr_info=$(cat "$stderr_tmp")
    rm -f "$stderr_tmp"

    # If fzf available AND TTY AND not --json/--plain, pipe through fzf
    if [[ -n "$results" ]] && [[ -t 1 ]] && [[ "$JSON_OUTPUT" != "true" ]] && [[ "$PLAIN_OUTPUT" != "true" ]] && command -v fzf >/dev/null 2>&1; then
        # Build fzf input: display path + timestamp + size, full path in last field
        selection=$(echo "$results" | while IFS='|' read -r ts size_human relative encrypted relpath fullpath; do
            [[ -z "$ts" ]] && continue
            local formatted_ts
            formatted_ts=$(format_timestamp "$ts")
            local enc=""
            if [[ "$encrypted" == "true" ]]; then
                enc=" [encrypted]"
            fi
            printf "%s  %s  %s  %s%s\t%s\n" "$relpath" "$formatted_ts" "$relative" "$size_human" "$enc" "$fullpath"
        done | fzf --prompt "Search results > " \
                   --header "ENTER: select | ESC: quit" \
                   --delimiter '\t' \
                   --with-nth 1 \
                   --preview 'file={2}; if echo "$file" | grep -q "\.age$"; then echo "Encrypted file - use --decrypt to view"; else cat "$file" 2>/dev/null || echo "Cannot preview file"; fi' \
                   --preview-window right:50% 2>/dev/null) || true

        if [[ -n "$selection" ]]; then
            # Extract the full path (after tab)
            selected_path=$(echo "$selection" | cut -f2)
            echo "$selected_path"
        fi
        exit 0
    fi

    output_search_results "$results" "$stderr_info"
    exit $?
fi

# ==============================================================================
# BROWSE: List files at a specific snapshot timestamp
# ==============================================================================

list_files_at_snapshot() {
    local archived_dir="$1"
    local timestamp="$2"

    find "$archived_dir" -type f -name "*${timestamp}*" 2>/dev/null | sort | while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue

        local basename_file
        basename_file=$(basename "$filepath")

        # Strip .age suffix to get base
        local stripped="$basename_file"
        local encrypted="no"
        case "$stripped" in
            *.age)
                stripped="${stripped%.age}"
                encrypted="yes"
                ;;
        esac

        # Strip timestamp + optional PID suffix to get original filename
        # Pattern: original_name.YYYYMMDD_HHMMSS or original_name.YYYYMMDD_HHMMSS_PID
        local original_name
        original_name=$(echo "$stripped" | sed 's/\.[0-9]\{8\}_[0-9]\{6\}\(_[0-9]*\)\{0,1\}$//')

        # Reconstruct relative path: directory within archived + original filename
        local rel_dir="${filepath#"$archived_dir"/}"
        rel_dir=$(dirname "$rel_dir")
        local original_relpath
        if [[ "$rel_dir" == "." ]]; then
            original_relpath="$original_name"
        else
            original_relpath="${rel_dir}/${original_name}"
        fi

        local size
        size=$(get_file_size "$filepath")
        local size_human
        size_human=$(format_bytes "$size")

        echo "${original_relpath}|${size_human}|${encrypted}|${filepath}"
    done
}

# ==============================================================================
# MODE: browse
# ==============================================================================

if [[ "$MODE" == "browse" ]]; then
    if [[ ! -d "$ARCHIVED_DIR" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"snapshots":[],"count":0}'
        else
            echo "No archived backups found at: $ARCHIVED_DIR" >&2
        fi
        exit 1
    fi

    snapshots=$(discover_snapshots "$ARCHIVED_DIR" 2>/dev/null || true)

    if [[ -z "$snapshots" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"snapshots":[],"count":0}'
        else
            echo "No snapshots found."
        fi
        exit 0
    fi

    # --json mode: output all snapshots with file counts
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        printf '{"snapshots":['
        first=true
        while IFS= read -r ts; do
            [[ -z "$ts" ]] && continue

            formatted_ts=$(format_timestamp "$ts")

            file_count=$(find "$ARCHIVED_DIR" -type f -name "*${ts}*" 2>/dev/null | wc -l | tr -d ' ')

            epoch=$(timestamp_to_epoch "$ts")
            relative=""
            if [[ "$epoch" -gt 0 ]]; then
                relative=$(format_relative_time "$epoch")
            fi

            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi

            escaped_relative=$(json_escape "$relative")
            printf '{"timestamp":"%s","date":"%s","relative":"%s","file_count":%d}' \
                "$ts" "$formatted_ts" "$escaped_relative" "$file_count"
        done <<< "$snapshots"

        snap_count=$(echo "$snapshots" | grep -c . || true)
        printf '],"count":%d}\n' "$snap_count"
        exit 0
    fi

    # Interactive browse: fzf or select fallback

    if command -v fzf >/dev/null 2>&1 && [[ -t 1 ]]; then
        # ============================================================
        # FZF MODE: Two-level drill-down
        # ============================================================

        # Level 1: Select snapshot
        fzf_snapshot_input=""
        while IFS= read -r ts; do
            [[ -z "$ts" ]] && continue
            formatted_ts=$(format_timestamp "$ts")
            epoch=$(timestamp_to_epoch "$ts")
            relative=""
            if [[ "$epoch" -gt 0 ]]; then
                relative=$(format_relative_time "$epoch")
            fi
            file_count=$(find "$ARCHIVED_DIR" -type f -name "*${ts}*" 2>/dev/null | wc -l | tr -d ' ')
            fzf_snapshot_input="${fzf_snapshot_input}${formatted_ts}  (${relative})  [${file_count} files]\t${ts}
"
        done <<< "$snapshots"

        selected_snapshot=$(printf '%s' "$fzf_snapshot_input" | fzf \
            --prompt "Select snapshot > " \
            --header "ENTER: browse files | ESC: quit" \
            --delimiter '\t' \
            --with-nth 1 \
            --preview "find \"$ARCHIVED_DIR\" -type f -name \"*{2}*\" 2>/dev/null | wc -l | xargs printf '%s files in this snapshot\n'" \
            --preview-window right:30% 2>/dev/null) || true

        if [[ -z "$selected_snapshot" ]]; then
            exit 0
        fi

        # Extract raw timestamp (after tab)
        chosen_ts=$(echo "$selected_snapshot" | cut -f2)

        # Level 2: Browse files in selected snapshot
        file_list=$(list_files_at_snapshot "$ARCHIVED_DIR" "$chosen_ts")

        if [[ -z "$file_list" ]]; then
            echo "No files found at snapshot $chosen_ts."
            exit 0
        fi

        selected_file=$(echo "$file_list" | fzf \
            --prompt "Files > " \
            --header "ENTER: view | ESC: back" \
            --delimiter '|' \
            --with-nth '1,2,3' \
            --preview 'file=$(echo {} | cut -d"|" -f4); if echo "$file" | grep -q "\.age$"; then echo "Encrypted file - use --decrypt to view"; else cat "$file" 2>/dev/null || echo "Cannot preview file"; fi' \
            --preview-window right:50% 2>/dev/null) || true

        if [[ -n "$selected_file" ]]; then
            # Output the full path
            echo "$selected_file" | cut -d'|' -f4
        fi
        exit 0

    else
        # ============================================================
        # SELECT FALLBACK: bash select menu
        # ============================================================

        echo -e "${C_BOLD}Browse Snapshots${C_RESET}"
        echo ""

        # Build snapshot list
        snap_options=()
        snap_timestamps=()
        display_count=0
        total_snaps=0

        while IFS= read -r ts; do
            [[ -z "$ts" ]] && continue
            total_snaps=$((total_snaps + 1))

            if [[ "$display_count" -ge 50 ]]; then
                continue
            fi

            formatted_ts=$(format_timestamp "$ts")
            epoch=$(timestamp_to_epoch "$ts")
            relative=""
            if [[ "$epoch" -gt 0 ]]; then
                relative=$(format_relative_time "$epoch")
            fi
            file_count=$(find "$ARCHIVED_DIR" -type f -name "*${ts}*" 2>/dev/null | wc -l | tr -d ' ')

            snap_options[${#snap_options[@]}]="${formatted_ts}  (${relative})  [${file_count} files]"
            snap_timestamps[${#snap_timestamps[@]}]="$ts"
            display_count=$((display_count + 1))
        done <<< "$snapshots"

        if [[ "$total_snaps" -gt 50 ]]; then
            echo -e "  ${C_DIM}Showing 50 of ${total_snaps} snapshots.${C_RESET}"
            echo ""
        fi

        PS3="Select snapshot (or 'q' to quit): "
        select opt in "${snap_options[@]}"; do
            if [[ "$REPLY" == "q" ]] || [[ "$REPLY" == "Q" ]]; then
                exit 0
            fi
            if [[ -n "$opt" ]]; then
                # Find index
                idx=0
                while [[ "$idx" -lt "${#snap_options[@]}" ]]; do
                    if [[ "${snap_options[$idx]}" == "$opt" ]]; then
                        break
                    fi
                    idx=$((idx + 1))
                done

                chosen_ts="${snap_timestamps[$idx]}"
                echo ""
                echo -e "${C_BOLD}Files at snapshot: $(format_timestamp "$chosen_ts")${C_RESET}"
                echo ""

                # List files
                file_list=$(list_files_at_snapshot "$ARCHIVED_DIR" "$chosen_ts")

                if [[ -z "$file_list" ]]; then
                    echo "No files found at this snapshot."
                    break
                fi

                file_options=()
                file_paths=()
                fcount=0

                while IFS='|' read -r original_relpath size_human encrypted fullpath; do
                    [[ -z "$original_relpath" ]] && continue
                    if [[ "$fcount" -ge 50 ]]; then
                        continue
                    fi
                    enc_label=""
                    if [[ "$encrypted" == "yes" ]]; then
                        enc_label=" [encrypted]"
                    fi
                    file_options[${#file_options[@]}]="${original_relpath}  (${size_human})${enc_label}"
                    file_paths[${#file_paths[@]}]="$fullpath"
                    fcount=$((fcount + 1))
                done <<< "$file_list"

                total_files=$(echo "$file_list" | grep -c . || true)
                if [[ "$total_files" -gt 50 ]]; then
                    echo -e "  ${C_DIM}Showing 50 of ${total_files} files.${C_RESET}"
                    echo ""
                fi

                PS3="Select file (or 'q' to quit): "
                select fopt in "${file_options[@]}"; do
                    if [[ "$REPLY" == "q" ]] || [[ "$REPLY" == "Q" ]]; then
                        break 2
                    fi
                    if [[ -n "$fopt" ]]; then
                        fidx=0
                        while [[ "$fidx" -lt "${#file_options[@]}" ]]; do
                            if [[ "${file_options[$fidx]}" == "$fopt" ]]; then
                                break
                            fi
                            fidx=$((fidx + 1))
                        done
                        echo "${file_paths[$fidx]}"
                        exit 0
                    else
                        echo "Invalid selection. Try again." >&2
                    fi
                done
                break
            else
                echo "Invalid selection. Try again." >&2
            fi
        done
        exit 0
    fi
fi

# If we get here, no valid mode was handled
echo "Error: unknown mode '$MODE'" >&2
echo "Use --help for usage information" >&2
exit 1
