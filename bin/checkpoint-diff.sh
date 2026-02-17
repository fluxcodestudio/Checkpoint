#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Diff & History CLI
# Compare working directory with backup, browse file version history
# Usage: checkpoint-diff.sh [MODE] [OPTIONS] [FILE]
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

# Source diff library
source "$LIB_DIR/features/backup-diff.sh"

# ==============================================================================
# COLORS
# ==============================================================================

if [[ -t 1 ]]; then
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_BOLD='' C_RESET=''
fi

# ==============================================================================
# HELP TEXT
# ==============================================================================

show_help() {
    cat <<EOF
Checkpoint - Diff & History

USAGE
    checkpoint diff                          Show changes since last backup
    checkpoint diff <file>                   Show content diff for specific file
    checkpoint diff --list-snapshots         List available backup snapshots
    checkpoint diff --json                   JSON output for scripting
    checkpoint history <file>                Show all versions of a file
    checkpoint history <file> --diff N       Diff version N against current
    checkpoint history <file> --interactive  Interactive fzf version picker

OPTIONS
    --json              Output in JSON format
    --snapshot TS       Compare against snapshot at timestamp (YYYYMMDD_HHMMSS)
    --list-snapshots    List available backup snapshots
    --interactive, -i   Interactive fzf version picker (history mode)
    --help, -h          Show this help

EXAMPLES
    checkpoint diff                          Show changes since last backup
    checkpoint diff src/app.js               Show content diff for specific file
    checkpoint diff --json                   JSON output for scripting
    checkpoint diff --list-snapshots         List available snapshots
    checkpoint history src/app.js            Show all versions of a file
    checkpoint history src/app.js -i         Interactive version browser (fzf)

EXIT CODES
    0   Success (or no changes found)
    1   Error (missing config, backup dir, etc.)
EOF
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

MODE="diff"          # diff, history, list-snapshots
JSON_OUTPUT=false
INTERACTIVE=false
SNAPSHOT_TS=""
TARGET_FILE=""
HISTORY_DIFF_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        history)
            MODE="history"
            shift
            ;;
        --list-snapshots)
            MODE="list-snapshots"
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --snapshot)
            SNAPSHOT_TS="${2:-}"
            if [[ -z "$SNAPSHOT_TS" ]]; then
                echo "Error: --snapshot requires a timestamp argument" >&2
                exit 1
            fi
            shift 2
            ;;
        --diff)
            HISTORY_DIFF_VERSION="${2:-}"
            if [[ -z "$HISTORY_DIFF_VERSION" ]]; then
                echo "Error: --diff requires a version number" >&2
                exit 1
            fi
            shift 2
            ;;
        --interactive|-i)
            INTERACTIVE=true
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
            # Positional argument = file path
            TARGET_FILE="$1"
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
# MODE: list-snapshots
# ==============================================================================

if [[ "$MODE" == "list-snapshots" ]]; then
    if [[ ! -d "$ARCHIVED_DIR" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"snapshots":[],"count":0}'
        else
            echo "No archived backups found."
        fi
        exit 0
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

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # Build JSON array of snapshots
        printf '{"snapshots":['
        first=true
        while IFS= read -r ts; do
            [[ -z "$ts" ]] && continue
            # Format timestamp as date
            local_year="${ts:0:4}"
            local_month="${ts:4:2}"
            local_day="${ts:6:2}"
            local_hour="${ts:9:2}"
            local_min="${ts:11:2}"
            local_sec="${ts:13:2}"
            formatted="${local_year}-${local_month}-${local_day} ${local_hour}:${local_min}:${local_sec}"

            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi
            printf '{"timestamp":"%s","date":"%s"}' "$ts" "$formatted"
        done <<< "$snapshots"
        count=$(echo "$snapshots" | grep -c . || true)
        printf '],"count":%d}\n' "$count"
    else
        echo -e "${C_BOLD}Available Snapshots${C_RESET}"
        echo ""
        count=0
        while IFS= read -r ts; do
            [[ -z "$ts" ]] && continue
            count=$((count + 1))
            local_year="${ts:0:4}"
            local_month="${ts:4:2}"
            local_day="${ts:6:2}"
            local_hour="${ts:9:2}"
            local_min="${ts:11:2}"
            local_sec="${ts:13:2}"
            formatted="${local_year}-${local_month}-${local_day} ${local_hour}:${local_min}:${local_sec}"

            # Calculate relative time
            if epoch=$(date -j -f "%Y%m%d%H%M%S" "${ts//_/}" +%s 2>/dev/null); then
                relative=$(format_relative_time "$epoch")
            else
                relative=""
            fi

            printf "  %s  %s" "$formatted" "$ts"
            [[ -n "$relative" ]] && printf "  (%s)" "$relative"
            echo ""
        done <<< "$snapshots"
        echo ""
        echo "$count snapshot(s) found."
    fi
    exit 0
fi

# ==============================================================================
# MODE: history <file>
# ==============================================================================

if [[ "$MODE" == "history" ]]; then
    if [[ -z "$TARGET_FILE" ]]; then
        echo "Error: history mode requires a file argument" >&2
        echo "Usage: checkpoint history <file>" >&2
        exit 1
    fi

    if [[ ! -d "$FILES_DIR" ]]; then
        echo "No backup found. Run a backup first." >&2
        exit 1
    fi

    # Collect versions
    versions=$(list_file_versions_sorted "$TARGET_FILE" "$FILES_DIR" "$ARCHIVED_DIR" 2>/dev/null || true)

    if [[ -z "$versions" ]]; then
        echo "File '$TARGET_FILE' not found in backup. It may not have been backed up yet." >&2
        exit 1
    fi

    # Interactive fzf mode (early return)
    if [[ "$INTERACTIVE" == "true" ]]; then
        if ! command -v fzf &>/dev/null; then
            echo "fzf not installed — showing table output instead. Install fzf for interactive browsing." >&2
            # Fall through to normal output below
        elif [[ ! -t 1 ]]; then
            echo "Interactive mode requires a terminal. Falling back to table output." >&2
            # Fall through to normal output below
        else
            # Build tab-delimited list for fzf
            fzf_input=""
            num=1
            while IFS='|' read -r mtime version created relative size_human path; do
                [[ -z "$mtime" ]] && continue
                fzf_input+=$(printf '%d\t%s\t%s\t%s\t%s\t%s\n' "$num" "$version" "$created" "$relative" "$size_human" "$path")
                fzf_input+=$'\n'
                num=$((num + 1))
            done <<< "$versions"

            # Remove trailing newline
            fzf_input="${fzf_input%$'\n'}"

            selected=$(echo "$fzf_input" | fzf \
                --prompt "Version > " \
                --header "ENTER: view diff vs current | CTRL-C: cancel" \
                --header-first \
                --delimiter '\t' \
                --with-nth 1,2,3,4,5 \
                --ansi \
                --preview "diff --color=always \"$PROJECT_DIR/$TARGET_FILE\" {6} 2>/dev/null || cat {6}" \
                --preview-window "right:60%:wrap" \
            ) || true

            if [[ -n "$selected" ]]; then
                selected_path=$(echo "$selected" | cut -f6)
                selected_version=$(echo "$selected" | cut -f2)
                echo ""
                echo -e "${C_BOLD}Diff: current vs ${C_CYAN}${selected_version}${C_RESET}"
                echo ""
                diff -u --label "current" --label "version ${selected_version}" \
                    "$PROJECT_DIR/$TARGET_FILE" "$selected_path" || true
            fi
            exit 0
        fi
    fi

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        printf '{"file":"%s","versions":[' "$TARGET_FILE"
        first=true
        num=1
        while IFS='|' read -r mtime version created relative size_human path; do
            [[ -z "$mtime" ]] && continue
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi
            printf '{"version":%d,"label":"%s","date":"%s","relative":"%s","size":"%s","path":"%s"}' \
                "$num" "$version" "$created" "$relative" "$size_human" "$path"
            num=$((num + 1))
        done <<< "$versions"
        printf ']}\n'
    else
        echo -e "${C_BOLD}File History: ${C_CYAN}${TARGET_FILE}${C_RESET}"
        echo ""
        printf "  ${C_BOLD}%-4s  %-16s  %-20s  %-18s  %s${C_RESET}\n" "#" "Version" "Date" "Age" "Size"
        echo "  ---- ----------------  --------------------  ------------------  --------"
        num=1
        while IFS='|' read -r mtime version created relative size_human path; do
            [[ -z "$mtime" ]] && continue
            if [[ "$version" == "CURRENT" ]]; then
                printf "  ${C_GREEN}%-4d  %-16s  %-20s  %-18s  %s${C_RESET}\n" \
                    "$num" "$version" "$created" "$relative" "$size_human"
            else
                printf "  %-4d  %-16s  %-20s  %-18s  %s\n" \
                    "$num" "$version" "$created" "$relative" "$size_human"
            fi
            num=$((num + 1))
        done <<< "$versions"
        echo ""
    fi
    exit 0
fi

# ==============================================================================
# MODE: diff <file> (single file content diff)
# ==============================================================================

if [[ -n "$TARGET_FILE" ]]; then
    if [[ ! -d "$FILES_DIR" ]]; then
        echo "No backup found. Run a backup first." >&2
        exit 1
    fi

    backup_file="$FILES_DIR/$TARGET_FILE"

    # If --snapshot specified, get that version instead
    if [[ -n "$SNAPSHOT_TS" ]]; then
        snapshot_file=$(get_file_at_snapshot "$TARGET_FILE" "$SNAPSHOT_TS" "$FILES_DIR" "$ARCHIVED_DIR" 2>/dev/null || true)
        if [[ -z "$snapshot_file" ]] || [[ ! -f "$snapshot_file" ]]; then
            echo "File '$TARGET_FILE' not found at snapshot $SNAPSHOT_TS." >&2
            exit 1
        fi
        backup_file="$snapshot_file"
    fi

    if [[ ! -f "$backup_file" ]]; then
        echo "File '$TARGET_FILE' not found in backup. It may not have been backed up yet." >&2
        exit 1
    fi

    current_file="$PROJECT_DIR/$TARGET_FILE"
    if [[ ! -f "$current_file" ]]; then
        echo "File '$TARGET_FILE' not found in working directory (may have been deleted)." >&2
        # Show the backed-up content as removed
        diff -u --label "backup" --label "working (deleted)" "$backup_file" /dev/null 2>/dev/null || true
        exit 0
    fi

    # Run content diff
    diff -u --label "backup" --label "working" "$backup_file" "$current_file" || true
    exit 0
fi

# ==============================================================================
# MODE: diff (default - full project comparison)
# ==============================================================================

if [[ ! -d "$FILES_DIR" ]]; then
    echo "No backup found. Run a backup first." >&2
    exit 1
fi

# Run rsync dry-run comparison
compare_current_to_backup "$PROJECT_DIR" "$FILES_DIR"

total=$((${#DIFF_ADDED[@]} + ${#DIFF_REMOVED[@]} + ${#DIFF_MODIFIED[@]}))

if [[ "$JSON_OUTPUT" == "true" ]]; then
    format_diff_json
else
    if [[ "$total" -eq 0 ]]; then
        echo "No changes since last backup."
    else
        format_diff_text
    fi
fi

exit 0
