#!/usr/bin/env bash
# Checkpoint - Restore Wizard
# Interactive restore with multiple modes and safety features

set -euo pipefail

# ==============================================================================
# LOAD LIBRARY & CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# Load backup library
if [ -f "$LIB_DIR/backup-lib.sh" ]; then
    source "$LIB_DIR/backup-lib.sh"
else
    echo "❌ Error: backup-lib.sh not found" >&2
    exit 1
fi

# Check for --help before loading config
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << 'EOF'
Checkpoint - Restore Wizard

USAGE:
    backup-restore.sh [OPTIONS] [PROJECT_DIR]

OPTIONS:
    --list                  List available backups
    --database              Restore database
    --file PATH             Restore specific file
    --version TIMESTAMP     Restore specific version
    --dry-run               Preview restore (no changes)
    --help, -h              Show this help message

EXAMPLES:
    backup-restore.sh                    # Interactive restore wizard
    backup-restore.sh --list             # List available backups
    backup-restore.sh --database         # Restore database interactively
    backup-restore.sh /path/to/project   # Restore from specific project

EXIT CODES:
    0 - Success
    1 - Configuration error
    2 - Restore failed
EOF
    exit 0
fi

# Find and load configuration
PROJECT_DIR="${1:-$PWD}"
CONFIG_FILE="$PROJECT_DIR/.backup-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    color_red "❌ No backup configuration found in: $PROJECT_DIR"
    echo "Run install.sh first or specify project directory:" >&2
    echo "  backup-restore.sh /path/to/project" >&2
    exit 1
fi

source "$CONFIG_FILE"

# ==============================================================================
# COMMAND LINE ARGUMENTS
# ==============================================================================

DRY_RUN=false
LIST_MODE=false
RESTORE_TYPE=""
RESTORE_TARGET=""
RESTORE_VERSION=""
RESTORE_AT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --list)
            LIST_MODE=true
            shift
            ;;
        database)
            RESTORE_TYPE="database"
            shift
            ;;
        file)
            RESTORE_TYPE="file"
            RESTORE_TARGET="${2:-}"
            shift 2 2>/dev/null || shift
            ;;
        --at)
            RESTORE_AT="${2:-}"
            shift 2 2>/dev/null || shift
            ;;
        --version)
            RESTORE_VERSION="${2:-}"
            shift 2 2>/dev/null || shift
            ;;
        --help|-h)
            cat <<EOF
Checkpoint - Restore Wizard

Usage:
  backup-restore.sh [options] [mode]

Modes:
  (interactive)              Launch interactive wizard
  database                   Restore latest database
  database --at "DATETIME"   Restore database from specific time
  file PATH                  Restore specific file
  file PATH --version N      Restore specific version
  --list                     List all available backups

Options:
  --dry-run                  Preview restore without executing
  --help                     Show this help message

Examples:
  backup-restore.sh
  backup-restore.sh database
  backup-restore.sh database --at "2025-12-24 10:00"
  backup-restore.sh file src/config.js
  backup-restore.sh file src/config.js --version 3
  backup-restore.sh --list

Date/Time Formats:
  "2 days ago", "yesterday", "last week"
  "2025-12-24 10:00", "2025-12-24"

EOF
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# ==============================================================================
# RESTORE FUNCTIONS
# ==============================================================================

# List all backups
list_all_backups() {
    color_bold "═══════════════════════════════════════════════"
    color_bold "Database Backups"
    color_bold "═══════════════════════════════════════════════"
    echo ""

    if [ -d "$DATABASE_DIR" ]; then
        local count=0
        list_database_backups_sorted "$DATABASE_DIR" | while IFS='|' read -r created relative size filename path; do
            printf "  %-25s %-20s %10s\n" "$created" "($relative)" "$size"
            ((count++))
        done

        local total=$(find "$DATABASE_DIR" -name "*.db.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo ""
        color_cyan "Total: $total database backups"
    else
        echo "  (none)"
    fi

    echo ""
    color_bold "═══════════════════════════════════════════════"
    color_bold "Backed-up Files"
    color_bold "═══════════════════════════════════════════════"
    echo ""

    if [ -d "$FILES_DIR" ]; then
        find "$FILES_DIR" -type f 2>/dev/null | while read -r file; do
            local rel_path="${file#$FILES_DIR/}"
            echo "  $rel_path"
        done

        local total_files=$(find "$FILES_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        local total_archived=$(find "$ARCHIVED_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo ""
        color_cyan "Total: $total_files current files, $total_archived archived versions"
    else
        echo "  (none)"
    fi

    echo ""
}

# Interactive database restore wizard
restore_database_interactive() {
    local content=$(cat <<EOF

What would you like to restore?

  [1] Database backup (latest)
  [2] Database backup (choose from list)
  [3] Database backup (specific date/time)
  [4] Cancel

EOF
    )

    draw_box "Database Restore" "$content"
    echo ""

    read -p "Select option [1-4]: " db_option

    case "$db_option" in
        1)
            restore_latest_database
            ;;
        2)
            restore_database_from_list
            ;;
        3)
            restore_database_at_time
            ;;
        4|*)
            echo "Cancelled."
            exit 0
            ;;
    esac
}

# Restore latest database backup
restore_latest_database() {
    if [ ! -d "$DATABASE_DIR" ]; then
        color_red "❌ No database backups found"
        exit 1
    fi

    local latest=$(list_database_backups_sorted "$DATABASE_DIR" 1 | head -1)

    if [ -z "$latest" ]; then
        color_red "❌ No database backups found"
        exit 1
    fi

    IFS='|' read -r created relative size filename path <<< "$latest"

    echo ""
    local preview=$(cat <<EOF

⚠️  CAUTION: This will replace your current database

Source:      $filename
Size:        $size
Created:     $created ($relative)
Destination: $DB_PATH

Safety backup will be created before restore

EOF
    )

    draw_box "Restore Preview" "$preview"
    echo ""

    if [ "$DRY_RUN" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Skipping confirmation"
    else
        if ! confirm "Continue?"; then
            echo "Cancelled."
            exit 0
        fi
        echo ""
    fi

    # Perform restore
    restore_database_from_backup "$path" "$DB_PATH" "$DRY_RUN"

    if [ $? -eq 0 ]; then
        echo ""
        color_green "✅ Restore complete"
        audit_restore "DATABASE" "$path" "$DB_PATH"
    else
        echo ""
        color_red "❌ Restore failed"
        exit 1
    fi
}

# Restore database from numbered list
restore_database_from_list() {
    echo ""
    color_bold "Available Database Backups:"
    echo ""

    local backups=()
    local index=1

    while IFS='|' read -r created relative size filename path; do
        printf "  [%2d] %-25s %-20s %10s\n" "$index" "$created" "($relative)" "$size"
        backups+=("$path")
        ((index++))

        [ $index -gt 20 ] && break
    done < <(list_database_backups_sorted "$DATABASE_DIR")

    local total=$(find "$DATABASE_DIR" -name "*.db.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ $total -gt 20 ]; then
        echo ""
        color_gray "  (Showing newest 20 of $total total backups)"
    fi

    echo ""
    read -p "Enter number [1-${#backups[@]}] or 0 to cancel: " selection

    if [ "$selection" -eq 0 ] 2>/dev/null; then
        echo "Cancelled."
        exit 0
    fi

    if [ "$selection" -ge 1 ] 2>/dev/null && [ "$selection" -le "${#backups[@]}" ]; then
        local selected_backup="${backups[$((selection - 1))]}"
        local filename=$(basename "$selected_backup")
        local size=$(stat -f%z "$selected_backup" 2>/dev/null || stat -c%s "$selected_backup" 2>/dev/null)
        local size_human=$(format_bytes "$size")

        echo ""
        local preview=$(cat <<EOF

⚠️  CAUTION: This will replace your current database

Source:      $filename
Size:        $size_human
Destination: $DB_PATH

Safety backup will be created before restore

EOF
        )

        draw_box "Restore Preview" "$preview"
        echo ""

        if [ "$DRY_RUN" = "true" ]; then
            color_cyan "ℹ️  [DRY RUN] Skipping confirmation"
        else
            if ! confirm "Continue?"; then
                echo "Cancelled."
                exit 0
            fi
            echo ""
        fi

        # Perform restore
        restore_database_from_backup "$selected_backup" "$DB_PATH" "$DRY_RUN"

        if [ $? -eq 0 ]; then
            echo ""
            color_green "✅ Restore complete"
            audit_restore "DATABASE" "$selected_backup" "$DB_PATH"
        else
            echo ""
            color_red "❌ Restore failed"
            exit 1
        fi
    else
        color_red "Invalid selection"
        exit 1
    fi
}

# Restore database at specific time
restore_database_at_time() {
    echo ""
    read -p "Enter date/time (e.g., '2 days ago', '2025-12-24 10:00'): " datetime

    if [ -z "$datetime" ]; then
        color_red "❌ No date/time specified"
        exit 1
    fi

    local target_timestamp=$(parse_date_string "$datetime")

    if [ -z "$target_timestamp" ] || [ "$target_timestamp" = "0" ]; then
        color_red "❌ Invalid date/time format"
        exit 1
    fi

    # Find closest backup to target time
    local closest_backup=""
    local closest_diff=999999999

    while IFS='|' read -r created relative size filename path; do
        local mtime=$(stat -f%m "$path" 2>/dev/null || stat -c%Y "$path" 2>/dev/null)
        local diff=$((target_timestamp - mtime))
        [ $diff -lt 0 ] && diff=$((diff * -1))

        if [ $diff -lt $closest_diff ]; then
            closest_diff=$diff
            closest_backup="$path"
        fi
    done < <(list_database_backups_sorted "$DATABASE_DIR")

    if [ -z "$closest_backup" ]; then
        color_red "❌ No suitable backup found"
        exit 1
    fi

    local filename=$(basename "$closest_backup")
    local mtime=$(stat -f%m "$closest_backup" 2>/dev/null || stat -c%Y "$closest_backup" 2>/dev/null)
    local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    local size=$(stat -f%z "$closest_backup" 2>/dev/null || stat -c%s "$closest_backup" 2>/dev/null)
    local size_human=$(format_bytes "$size")

    echo ""
    local preview=$(cat <<EOF

⚠️  CAUTION: This will replace your current database

Requested:   $datetime
Closest:     $created ($(format_relative_time "$mtime"))
Source:      $filename
Size:        $size_human
Destination: $DB_PATH

Safety backup will be created before restore

EOF
    )

    draw_box "Restore Preview" "$preview"
    echo ""

    if [ "$DRY_RUN" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Skipping confirmation"
    else
        if ! confirm "Continue?"; then
            echo "Cancelled."
            exit 0
        fi
        echo ""
    fi

    # Perform restore
    restore_database_from_backup "$closest_backup" "$DB_PATH" "$DRY_RUN"

    if [ $? -eq 0 ]; then
        echo ""
        color_green "✅ Restore complete"
        audit_restore "DATABASE_AT_TIME" "$closest_backup" "$DB_PATH"
    else
        echo ""
        color_red "❌ Restore failed"
        exit 1
    fi
}

# Interactive file restore wizard
restore_file_interactive() {
    echo ""
    read -p "Enter file path (relative to project root): " file_path

    if [ -z "$file_path" ]; then
        color_red "❌ No file path specified"
        exit 1
    fi

    # Check if file has any backups
    if [ ! -f "$FILES_DIR/$file_path" ]; then
        local archived_count=$(find "$ARCHIVED_DIR" -type f -name "$(basename "$file_path").*" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$archived_count" -eq 0 ]; then
            color_red "❌ No backups found for: $file_path"
            exit 1
        fi
    fi

    echo ""
    color_bold "Available versions of $file_path:"
    echo ""

    local versions=()
    local index=1

    while IFS='|' read -r mtime version created relative size path; do
        printf "  [%2d] %-12s %-25s %-20s %10s\n" "$index" "$version" "$created" "($relative)" "$size"
        versions+=("$path")
        ((index++))
    done < <(list_file_versions_sorted "$file_path" "$FILES_DIR" "$ARCHIVED_DIR")

    echo ""
    read -p "Select version to restore [1-${#versions[@]}] or 0 to cancel: " selection

    if [ "$selection" -eq 0 ] 2>/dev/null; then
        echo "Cancelled."
        exit 0
    fi

    if [ "$selection" -ge 1 ] 2>/dev/null && [ "$selection" -le "${#versions[@]}" ]; then
        local selected_backup="${versions[$((selection - 1))]}"
        local target_file="$PROJECT_DIR/$file_path"

        echo ""
        local preview=$(cat <<EOF

⚠️  This will replace the current file

Source:      $(basename "$selected_backup")
Destination: $target_file

Safety backup will be created if file exists

EOF
        )

        draw_box "Restore Preview" "$preview"
        echo ""

        if [ "$DRY_RUN" = "true" ]; then
            color_cyan "ℹ️  [DRY RUN] Skipping confirmation"
        else
            if ! confirm "Continue?"; then
                echo "Cancelled."
                exit 0
            fi
            echo ""
        fi

        # Perform restore
        restore_file_from_backup "$selected_backup" "$target_file" "$DRY_RUN"

        if [ $? -eq 0 ]; then
            echo ""
            color_green "✅ Restore complete"
            audit_restore "FILE" "$selected_backup" "$target_file"
        else
            echo ""
            color_red "❌ Restore failed"
            exit 1
        fi
    else
        color_red "Invalid selection"
        exit 1
    fi
}

# ==============================================================================
# MAIN WIZARD
# ==============================================================================

color_bold "═══════════════════════════════════════════════"
color_bold "Checkpoint - Restore Wizard"
color_bold "═══════════════════════════════════════════════"
echo ""
color_cyan "Project: $PROJECT_NAME"
color_cyan "Backups: $BACKUP_DIR"
echo ""

# List mode
if [ "$LIST_MODE" = "true" ]; then
    list_all_backups
    exit 0
fi

# Non-interactive modes
if [ -n "$RESTORE_TYPE" ]; then
    case "$RESTORE_TYPE" in
        database)
            if [ -n "$RESTORE_AT" ]; then
                RESTORE_AT="$RESTORE_AT"
                restore_database_at_time
            else
                restore_latest_database
            fi
            ;;
        file)
            if [ -z "$RESTORE_TARGET" ]; then
                color_red "❌ No file path specified"
                exit 1
            fi
            file_path="$RESTORE_TARGET"
            restore_file_interactive
            ;;
    esac
    exit 0
fi

# Interactive wizard
local content=$(cat <<EOF

What would you like to restore?

  [1] Database backup
  [2] Individual file(s)
  [3] Browse all backups
  [4] Exit

EOF
)

draw_box "Backup Restore Wizard" "$content"
echo ""

read -p "Select option [1-4]: " option

case "$option" in
    1)
        restore_database_interactive
        ;;
    2)
        restore_file_interactive
        ;;
    3)
        echo ""
        list_all_backups
        ;;
    4)
        echo "Exiting."
        exit 0
        ;;
    *)
        color_red "Invalid option"
        exit 1
        ;;
esac

echo ""
color_bold "═══════════════════════════════════════════════"
