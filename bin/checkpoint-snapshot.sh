#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Database Snapshot CLI
# Named per-table database snapshots: save, list, restore, delete
# Usage: checkpoint snapshot <command> [OPTIONS]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Source foundation library (loads core, ops, ui, platform, features incl. snapshot.sh)
source "$LIB_DIR/backup-lib.sh"

# Source database detector
source "$LIB_DIR/database-detector.sh"

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
Checkpoint - Database Snapshots

USAGE
    checkpoint snapshot save [NAME]      Create a named snapshot
    checkpoint snapshot list             List saved snapshots
    checkpoint snapshot delete <NAME>    Delete a snapshot
    checkpoint snapshot show <NAME>      Show snapshot details
    checkpoint snapshot restore <NAME>   Restore from a snapshot
    checkpoint snapshot bundle <NAME>    Generate download bundle

SAVE OPTIONS
    --name, -n NAME    Snapshot name (prompted if not provided)

LIST OPTIONS
    --json             Output as JSON array

RESTORE OPTIONS
    --tables T1,T2     Restore only specific tables (comma-separated)
    --force            Skip confirmation prompt
    --dry-run          Show what would be restored without doing it
    --bundle           Generate download bundle instead of restoring

GENERAL OPTIONS
    --help, -h         Show this help

EXAMPLES
    checkpoint snapshot save "pre-redesign"    Save current DB state
    checkpoint snapshot save                   Interactive: prompts for name
    checkpoint snapshot list                   Show all snapshots
    checkpoint snapshot restore "pre-redesign" Restore snapshot
    checkpoint snapshot delete "old-backup"    Remove a snapshot

EXIT CODES
    0   Success
    1   Error (missing config, DB not found, etc.)
EOF
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

MODE=""
SNAPSHOT_NAME=""
OPT_JSON=false
OPT_FORCE=false
OPT_DRY_RUN=false
OPT_BUNDLE=false
OPT_TABLES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        save)       MODE="save"; shift ;;
        list|ls)    MODE="list"; shift ;;
        delete|rm)  MODE="delete"; shift ;;
        show|info)  MODE="show"; shift ;;
        restore)    MODE="restore"; shift ;;
        bundle)     MODE="bundle"; shift ;;
        --name|-n)  SNAPSHOT_NAME="${2:-}"; shift 2 ;;
        --json)     OPT_JSON=true; shift ;;
        --force|-f) OPT_FORCE=true; shift ;;
        --dry-run)  OPT_DRY_RUN=true; shift ;;
        --bundle)   OPT_BUNDLE=true; shift ;;
        --tables)   OPT_TABLES="${2:-}"; shift 2 ;;
        --help|-h)  show_help; exit 0 ;;
        -*)         echo "Unknown option: $1" >&2; show_help; exit 1 ;;
        *)
            # Positional: snapshot name
            if [[ -z "$MODE" ]]; then
                MODE="$1"
            elif [[ -z "$SNAPSHOT_NAME" ]]; then
                SNAPSHOT_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$MODE" ]]; then
    show_help
    exit 0
fi

# ==============================================================================
# PROJECT SETUP
# ==============================================================================

PROJECT_DIR="$PWD"
if ! load_backup_config "$PROJECT_DIR" 2>/dev/null; then
    echo -e "${C_RED}No backup configuration found in $PROJECT_DIR${C_RESET}" >&2
    echo "Run 'checkpoint add .' to register this project first." >&2
    exit 1
fi
resolve_backup_destinations

BACKUP_DIR="${PRIMARY_BACKUP_DIR:-${BACKUP_DIR:-$PROJECT_DIR/backups}}"
SNAPSHOTS_DIR="$BACKUP_DIR/snapshots"

# ==============================================================================
# HELPER: detect database for current project
# ==============================================================================

_detect_project_database() {
    local databases
    databases=$(detect_databases "$PROJECT_DIR" 2>/dev/null)

    if [[ -z "$databases" ]]; then
        echo -e "${C_RED}No databases detected in $PROJECT_DIR${C_RESET}" >&2
        echo "Checkpoint snapshot requires a detectable database (SQLite, PostgreSQL, MySQL, or MongoDB)." >&2
        return 1
    fi

    # If multiple databases, let user choose
    local db_count
    db_count=$(echo "$databases" | wc -l | tr -d ' ')

    if [[ "$db_count" -eq 1 ]]; then
        echo "$databases"
        return 0
    fi

    # Multiple databases — present selection
    echo -e "${C_BOLD}Multiple databases detected:${C_RESET}" >&2
    local idx=0
    local db_array=()
    while IFS= read -r db_info; do
        idx=$((idx + 1))
        IFS='|' read -r db_type rest <<< "$db_info"
        case "$db_type" in
            sqlite)
                local db_name=$(basename "$rest" | sed 's/\.[^.]*$//')
                echo -e "  ${C_CYAN}$idx.${C_RESET} SQLite: $db_name" >&2
                ;;
            postgresql|mysql|mongodb)
                IFS='|' read -r host port db_name user _ _ _ <<< "$rest"
                local _db_label
                _db_label="$(printf '%s' "$db_type" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
                echo -e "  ${C_CYAN}$idx.${C_RESET} ${_db_label}: $db_name ($host:$port)" >&2
                ;;
        esac
        db_array+=("$db_info")
    done <<< "$databases"

    echo "" >&2
    local selection
    read -p "  Select database [1-$idx]: " selection
    if [[ -z "$selection" ]] || ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt "$idx" ]]; then
        echo "Invalid selection" >&2
        return 1
    fi

    echo "${db_array[$((selection - 1))]}"
}

# ==============================================================================
# COMMANDS
# ==============================================================================

case "$MODE" in
    save)
        # Prompt for name if not provided
        if [[ -z "$SNAPSHOT_NAME" ]]; then
            _default_name="snapshot-$(date +%Y-%m-%d)"
            echo -e "${C_BOLD}Create Database Snapshot${C_RESET}"
            echo ""
            read -p "  Snapshot name [${_default_name}]: " SNAPSHOT_NAME
            SNAPSHOT_NAME="${SNAPSHOT_NAME:-$_default_name}"
        fi

        # Validate name
        if ! snapshot_validate_name "$SNAPSHOT_NAME"; then
            exit 1
        fi

        # Detect database
        _db_info=$(_detect_project_database) || exit 1

        # Create snapshot
        snapshot_create "$_db_info" "$BACKUP_DIR" "$SNAPSHOT_NAME"
        exit $?
        ;;

    list)
        if [[ "$OPT_JSON" == "true" ]]; then
            # JSON output
            echo "["
            _first=true
            while IFS='|' read -r name db_type db_name table_count timestamp status size; do
                [[ -z "$name" ]] && continue
                [[ "$_first" != "true" ]] && echo ","
                printf '  {"name":"%s","db_type":"%s","db_name":"%s","table_count":%s,"timestamp":"%s","status":"%s","size":"%s"}' \
                    "$name" "$db_type" "$db_name" "$table_count" "$timestamp" "$status" "$size"
                _first=false
            done < <(snapshot_list "$BACKUP_DIR")
            echo ""
            echo "]"
        else
            # Table output
            _entries=$(snapshot_list "$BACKUP_DIR")

            if [[ -z "$_entries" ]]; then
                echo -e "${C_DIM}No snapshots found.${C_RESET}"
                echo "Create one with: checkpoint snapshot save \"my-snapshot\""
                exit 0
            fi

            echo -e "${C_BOLD}Database Snapshots${C_RESET}"
            echo ""
            printf "  ${C_BOLD}%-25s  %-12s  %-15s  %-6s  %-10s  %s${C_RESET}\n" \
                "NAME" "TYPE" "DATABASE" "TABLES" "STATUS" "SIZE"
            printf "  %-25s  %-12s  %-15s  %-6s  %-10s  %s\n" \
                "-------------------------" "------------" "---------------" "------" "----------" "--------"

            while IFS='|' read -r name db_type db_name table_count timestamp status size; do
                [[ -z "$name" ]] && continue
                _status_color="$C_GREEN"
                [[ "$status" == "partial" ]] && _status_color="$C_YELLOW"
                [[ "$status" == "failed" ]] && _status_color="$C_RED"

                printf "  %-25s  %-12s  %-15s  %-6s  ${_status_color}%-10s${C_RESET}  %s\n" \
                    "$name" "$db_type" "$db_name" "$table_count" "$status" "$size"
            done <<< "$_entries"
            echo ""
        fi
        ;;

    show)
        if [[ -z "$SNAPSHOT_NAME" ]]; then
            echo "Usage: checkpoint snapshot show <name>" >&2
            exit 1
        fi

        _snap_dir="$SNAPSHOTS_DIR/$SNAPSHOT_NAME"
        if [[ ! -d "$_snap_dir" ]]; then
            echo -e "${C_RED}Snapshot '$SNAPSHOT_NAME' not found${C_RESET}" >&2
            exit 1
        fi

        if [[ "$OPT_JSON" == "true" ]]; then
            cat "$_snap_dir/manifest.json"
        else
            echo -e "${C_BOLD}Snapshot: $SNAPSHOT_NAME${C_RESET}"
            echo ""

            # Parse manifest
            _manifest="$_snap_dir/manifest.json"
            _db_type=$(grep '"db_type"' "$_manifest" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
            _db_name=$(grep '"db_name"' "$_manifest" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
            _timestamp=$(grep '"timestamp"' "$_manifest" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
            _table_count=$(grep '"table_count"' "$_manifest" | head -1 | sed 's/.*: *\([0-9]*\).*/\1/')
            _status=$(grep '"status"' "$_manifest" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
            _total_rows=$(grep '"total_rows"' "$_manifest" | head -1 | sed 's/.*: *\([0-9]*\).*/\1/')

            echo "  Database:    $_db_type / $_db_name"
            echo "  Created:     $_timestamp"
            echo "  Tables:      $_table_count"
            echo "  Total rows:  $_total_rows"
            echo "  Status:      $_status"
            echo ""

            # List tables
            echo -e "  ${C_BOLD}Tables:${C_RESET}"
            snapshot_get_tables "$_snap_dir" | while IFS= read -r table; do
                echo "    - $table"
            done
            echo ""
        fi
        ;;

    delete)
        if [[ -z "$SNAPSHOT_NAME" ]]; then
            echo "Usage: checkpoint snapshot delete <name>" >&2
            exit 1
        fi

        if [[ "$OPT_FORCE" != "true" ]]; then
            read -p "Delete snapshot '$SNAPSHOT_NAME'? (y/N): " confirm
            if [[ "${confirm,,}" != "y" ]]; then
                echo "Cancelled."
                exit 0
            fi
        fi

        snapshot_delete "$BACKUP_DIR" "$SNAPSHOT_NAME"
        exit $?
        ;;

    restore)
        if [[ -z "$SNAPSHOT_NAME" ]]; then
            echo "Usage: checkpoint snapshot restore <name>" >&2
            exit 1
        fi

        _snap_dir="$SNAPSHOTS_DIR/$SNAPSHOT_NAME"
        if [[ ! -d "$_snap_dir" ]]; then
            echo -e "${C_RED}Snapshot '$SNAPSHOT_NAME' not found${C_RESET}" >&2
            exit 1
        fi

        # Detect current database
        _db_info=$(_detect_project_database) || exit 1

        # Compare schema
        echo -e "${C_CYAN}Comparing schemas...${C_RESET}"
        _schema_result=$(snapshot_compare_schema "$_snap_dir" "$_db_info" 2>/dev/null | head -1)

        if [[ "$_schema_result" == "MATCH" ]] || [[ "$_schema_result" == "COMPATIBLE" ]]; then
            echo -e "${C_GREEN}Schema matches — safe to restore directly${C_RESET}"
            echo ""

            if [[ "$OPT_DRY_RUN" == "true" ]]; then
                echo "[DRY RUN] Would restore snapshot '$SNAPSHOT_NAME'"
                if [[ -n "$OPT_TABLES" ]]; then
                    IFS=',' read -ra _dry_tables <<< "$OPT_TABLES"
                    for _dt in "${_dry_tables[@]}"; do
                        echo "  Would restore: $(echo "$_dt" | tr -d '[:space:]')"
                    done
                else
                    snapshot_get_tables "$_snap_dir" | while IFS= read -r t; do
                        echo "  Would restore: $t"
                    done
                fi
                exit 0
            fi

            if [[ "$OPT_BUNDLE" == "true" ]]; then
                snapshot_generate_bundle "$_snap_dir" "$_db_info"
                exit $?
            fi

            # Confirmation
            if [[ "$OPT_FORCE" != "true" ]]; then
                echo -e "${C_YELLOW}Restoring will overwrite your current database data.${C_RESET}"
                echo "A safety backup of your current data will be created first."
                echo ""
                read -p "Restore snapshot '$SNAPSHOT_NAME'? (y/N): " confirm
                if [[ "${confirm,,}" != "y" ]]; then
                    echo "Cancelled."
                    exit 0
                fi
            fi

            echo ""
            snapshot_restore "$_snap_dir" "$_db_info" "$OPT_TABLES"
            exit $?
        else
            echo -e "${C_YELLOW}Schema has changed since this snapshot was taken.${C_RESET}"
            echo ""
            snapshot_compare_schema "$_snap_dir" "$_db_info" 2>/dev/null | tail -n +2
            echo ""
            echo -e "${C_CYAN}Generating download bundle for manual/AI-assisted restore...${C_RESET}"
            snapshot_generate_bundle "$_snap_dir" "$_db_info"
        fi
        ;;

    bundle)
        if [[ -z "$SNAPSHOT_NAME" ]]; then
            echo "Usage: checkpoint snapshot bundle <name>" >&2
            exit 1
        fi

        _snap_dir="$SNAPSHOTS_DIR/$SNAPSHOT_NAME"
        if [[ ! -d "$_snap_dir" ]]; then
            echo -e "${C_RED}Snapshot '$SNAPSHOT_NAME' not found${C_RESET}" >&2
            exit 1
        fi

        _db_info=$(_detect_project_database) || exit 1
        snapshot_generate_bundle "$_snap_dir" "$_db_info"
        ;;

    *)
        echo "Unknown command: $MODE" >&2
        show_help
        exit 1
        ;;
esac
