#!/usr/bin/env bash
# Checkpoint - Cleanup Utility
# Smart cleanup with recommendations and safety features

set -euo pipefail

# ==============================================================================
# LOAD LIBRARY & CONFIGURATION
# ==============================================================================

# Resolve symlinks to get actual script location
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
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
Checkpoint - Cleanup Utility

USAGE:
    backup-cleanup.sh [OPTIONS] [PROJECT_DIR]

OPTIONS:
    --preview, --dry-run    Preview cleanup (no changes)
    --auto                  Execute cleanup automatically
    --recommendations       Show recommendations only
    --database-only         Clean only database backups
    --files-only            Clean only archived files
    --help, -h              Show this help message

EXAMPLES:
    backup-cleanup.sh                    # Preview cleanup for current project
    backup-cleanup.sh --auto             # Execute cleanup
    backup-cleanup.sh /path/to/project   # Clean specific project

EXIT CODES:
    0 - Success
    1 - Configuration error
    2 - Cleanup failed
EOF
    exit 0
fi

# Find and load configuration
PROJECT_DIR="${1:-$PWD}"
CONFIG_FILE="$PROJECT_DIR/.backup-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    color_red "❌ No backup configuration found in: $PROJECT_DIR"
    echo "Run install.sh first or specify project directory:" >&2
    echo "  backup-cleanup.sh /path/to/project" >&2
    exit 1
fi

source "$CONFIG_FILE"

# ==============================================================================
# COMMAND LINE ARGUMENTS
# ==============================================================================

DRY_RUN=false
AUTO_MODE=false
PREVIEW_MODE=false
RECOMMENDATIONS_MODE=false
DATABASE_ONLY=false
FILES_ONLY=false
OLDER_THAN=""
KEEP_LAST=""
RECLAIM_SPACE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --preview|--dry-run)
            PREVIEW_MODE=true
            DRY_RUN=true
            shift
            ;;
        --auto)
            AUTO_MODE=true
            shift
            ;;
        --recommendations)
            RECOMMENDATIONS_MODE=true
            shift
            ;;
        --database-only)
            DATABASE_ONLY=true
            shift
            ;;
        --files-only)
            FILES_ONLY=true
            shift
            ;;
        --older-than)
            OLDER_THAN="${2:-}"
            shift 2 2>/dev/null || shift
            ;;
        --keep-last)
            KEEP_LAST="${2:-}"
            shift 2 2>/dev/null || shift
            ;;
        --reclaim)
            RECLAIM_SPACE="${2:-}"
            shift 2 2>/dev/null || shift
            ;;
        --help|-h)
            cat <<EOF
Checkpoint - Cleanup Utility

Usage:
  backup-cleanup.sh [options]

Modes:
  (interactive)              Launch interactive cleanup wizard
  --preview                  Dry-run, show what would be deleted
  --auto                     Use retention policy (non-interactive)
  --recommendations          Show cleanup recommendations only

Filters:
  --database-only            Clean only database backups
  --files-only               Clean only archived files
  --older-than DAYS          Custom age threshold (e.g., 90d, 60)
  --keep-last N              Keep last N backups
  --reclaim SIZE             Free up specific space (e.g., 1GB, 500MB)

Options:
  --help                     Show this help message

Examples:
  backup-cleanup.sh
  backup-cleanup.sh --preview
  backup-cleanup.sh --auto
  backup-cleanup.sh --recommendations
  backup-cleanup.sh --database-only --older-than 90d
  backup-cleanup.sh --reclaim 1GB --preview

EOF
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# ==============================================================================
# CLEANUP ANALYSIS FUNCTIONS
# ==============================================================================

# Analyze what would be cleaned
analyze_cleanup() {
    local db_retention="${1:-$DB_RETENTION_DAYS}"
    local file_retention="${2:-$FILE_RETENTION_DAYS}"

    # Database backups to delete
    local db_to_delete=()
    local db_size=0

    if [ "$FILES_ONLY" = "false" ] && [ -d "$DATABASE_DIR" ]; then
        while IFS= read -r backup; do
            db_to_delete+=("$backup")
            local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
            db_size=$((db_size + size))
        done < <(find_expired_backups "$DATABASE_DIR" "$db_retention" "*.db.gz")
    fi

    # Archived files to delete
    local files_to_delete=()
    local files_size=0

    if [ "$DATABASE_ONLY" = "false" ] && [ -d "$ARCHIVED_DIR" ]; then
        while IFS= read -r backup; do
            files_to_delete+=("$backup")
            local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
            files_size=$((files_size + size))
        done < <(find_expired_backups "$ARCHIVED_DIR" "$file_retention" "*")
    fi

    # Export results
    echo "${#db_to_delete[@]}|$(format_bytes "$db_size")|${#files_to_delete[@]}|$(format_bytes "$files_size")|$((db_size + files_size))"
}

# Find duplicate backups
analyze_duplicates() {
    local duplicates=()
    local dup_size=0

    if [ "$FILES_ONLY" = "false" ] && [ -d "$DATABASE_DIR" ]; then
        while IFS= read -r backup; do
            duplicates+=("$backup")
            local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
            dup_size=$((dup_size + size))
        done < <(find_duplicate_backups "$DATABASE_DIR" "*.db.gz")
    fi

    echo "${#duplicates[@]}|$(format_bytes "$dup_size")"
}

# Find orphaned archives
analyze_orphaned() {
    local orphaned=()
    local orphan_size=0

    if [ "$DATABASE_ONLY" = "false" ] && [ -d "$ARCHIVED_DIR" ]; then
        while IFS= read -r backup; do
            orphaned+=("$backup")
            local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
            orphan_size=$((orphan_size + size))
        done < <(find_orphaned_archives "$ARCHIVED_DIR" "$FILES_DIR" "$PROJECT_DIR")
    fi

    echo "${#orphaned[@]}|$(format_bytes "$orphan_size")"
}

# ==============================================================================
# CLEANUP EXECUTION FUNCTIONS
# ==============================================================================

# Execute cleanup based on retention policy
execute_cleanup() {
    local db_retention="${1:-$DB_RETENTION_DAYS}"
    local file_retention="${2:-$FILE_RETENTION_DAYS}"
    local dry_run="${3:-false}"

    local deleted_count=0
    local freed_size=0

    # Clean database backups
    if [ "$FILES_ONLY" = "false" ] && [ -d "$DATABASE_DIR" ]; then
        local db_files=()
        while IFS= read -r backup; do
            db_files+=("$backup")
        done < <(find_expired_backups "$DATABASE_DIR" "$db_retention" "*.db.gz")

        if [ ${#db_files[@]} -gt 0 ]; then
            local db_size=0
            for file in "${db_files[@]}"; do
                local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
                db_size=$((db_size + size))
            done

            if [ "$dry_run" = "true" ]; then
                color_cyan "ℹ️  [DRY RUN] Would delete ${#db_files[@]} database backups ($(format_bytes "$db_size"))"
            else
                for file in "${db_files[@]}"; do
                    if rm -f "$file" 2>/dev/null; then
                        ((deleted_count++))
                        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
                        freed_size=$((freed_size + size))
                    fi
                done
                color_green "✅ Deleted ${#db_files[@]} database backups ($(format_bytes "$db_size"))"
            fi
        fi
    fi

    # Clean archived files
    if [ "$DATABASE_ONLY" = "false" ] && [ -d "$ARCHIVED_DIR" ]; then
        local archive_files=()
        while IFS= read -r backup; do
            archive_files+=("$backup")
        done < <(find_expired_backups "$ARCHIVED_DIR" "$file_retention" "*")

        if [ ${#archive_files[@]} -gt 0 ]; then
            local archive_size=0
            for file in "${archive_files[@]}"; do
                local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
                archive_size=$((archive_size + size))
            done

            if [ "$dry_run" = "true" ]; then
                color_cyan "ℹ️  [DRY RUN] Would delete ${#archive_files[@]} archived files ($(format_bytes "$archive_size"))"
            else
                for file in "${archive_files[@]}"; do
                    if rm -f "$file" 2>/dev/null; then
                        ((deleted_count++))
                        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
                        freed_size=$((freed_size + size))
                    fi
                done
                color_green "✅ Deleted ${#archive_files[@]} archived files ($(format_bytes "$archive_size"))"

                # Clean empty directories
                find "$ARCHIVED_DIR" -type d -empty -delete 2>/dev/null || true
            fi
        fi
    fi

    if [ "$dry_run" = "false" ] && [ $deleted_count -gt 0 ]; then
        audit_cleanup "POLICY" "$deleted_count" "$(format_bytes "$freed_size")"
    fi

    return 0
}

# Clean duplicate backups
clean_duplicates() {
    local dry_run="${1:-false}"

    if [ "$FILES_ONLY" = "true" ] || [ ! -d "$DATABASE_DIR" ]; then
        return 0
    fi

    local duplicates=()
    while IFS= read -r backup; do
        duplicates+=("$backup")
    done < <(find_duplicate_backups "$DATABASE_DIR" "*.db.gz")

    if [ ${#duplicates[@]} -eq 0 ]; then
        color_cyan "ℹ️  No duplicate backups found"
        return 0
    fi

    local dup_size=0
    for file in "${duplicates[@]}"; do
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        dup_size=$((dup_size + size))
    done

    if [ "$dry_run" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Would delete ${#duplicates[@]} duplicate backups ($(format_bytes "$dup_size"))"
        return 0
    fi

    echo ""
    color_yellow "⚠️  Found ${#duplicates[@]} duplicate database backups ($(format_bytes "$dup_size"))"
    echo ""

    if ! confirm "Delete duplicates?"; then
        color_cyan "ℹ️  Skipped duplicates cleanup"
        return 0
    fi

    local deleted=0
    for file in "${duplicates[@]}"; do
        if rm -f "$file" 2>/dev/null; then
            ((deleted++))
        fi
    done

    color_green "✅ Deleted $deleted duplicate backups ($(format_bytes "$dup_size"))"
    audit_cleanup "DUPLICATES" "$deleted" "$(format_bytes "$dup_size")"
}

# Clean orphaned archives
clean_orphaned() {
    local dry_run="${1:-false}"

    if [ "$DATABASE_ONLY" = "true" ] || [ ! -d "$ARCHIVED_DIR" ]; then
        return 0
    fi

    local orphaned=()
    while IFS= read -r backup; do
        orphaned+=("$backup")
    done < <(find_orphaned_archives "$ARCHIVED_DIR" "$FILES_DIR" "$PROJECT_DIR")

    if [ ${#orphaned[@]} -eq 0 ]; then
        color_cyan "ℹ️  No orphaned archives found"
        return 0
    fi

    local orphan_size=0
    for file in "${orphaned[@]}"; do
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        orphan_size=$((orphan_size + size))
    done

    if [ "$dry_run" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Would delete ${#orphaned[@]} orphaned archives ($(format_bytes "$orphan_size"))"
        return 0
    fi

    echo ""
    color_yellow "⚠️  Found ${#orphaned[@]} orphaned archived files ($(format_bytes "$orphan_size"))"
    echo ""

    if ! confirm "Delete orphaned archives?"; then
        color_cyan "ℹ️  Skipped orphaned cleanup"
        return 0
    fi

    local deleted=0
    for file in "${orphaned[@]}"; do
        if rm -f "$file" 2>/dev/null; then
            ((deleted++))
        fi
    done

    # Clean empty directories
    find "$ARCHIVED_DIR" -type d -empty -delete 2>/dev/null || true

    color_green "✅ Deleted $deleted orphaned archives ($(format_bytes "$orphan_size"))"
    audit_cleanup "ORPHANED" "$deleted" "$(format_bytes "$orphan_size")"
}

# ==============================================================================
# RECOMMENDATIONS MODE
# ==============================================================================

show_recommendations() {
    color_bold "═══════════════════════════════════════════════"
    color_bold "Cleanup Recommendations"
    color_bold "═══════════════════════════════════════════════"
    echo ""

    # Disk usage check
    local disk_usage=$(get_backup_disk_usage)
    local total_size=$(get_total_backup_size)

    color_cyan "Current Status:"
    echo "  Disk usage: ${disk_usage}%"
    echo "  Total backup size: $(format_bytes "$total_size")"
    echo ""

    if [ $disk_usage -ge 90 ]; then
        color_red "  🚨 CRITICAL: Disk usage at ${disk_usage}%"
        echo "     Immediate cleanup recommended"
    elif [ $disk_usage -ge 80 ]; then
        color_yellow "  ⚠️  WARNING: Disk usage at ${disk_usage}%"
        echo "     Cleanup recommended soon"
    else
        color_green "  ✅ Disk usage healthy (${disk_usage}%)"
    fi

    echo ""
    color_bold "──────────────────────────────────────────────"
    color_cyan "Cleanup Opportunities:"
    echo ""

    # Analyze expired backups
    IFS='|' read -r db_count db_size files_count files_size total_size <<< "$(analyze_cleanup)"

    if [ "$db_count" -gt 0 ] || [ "$files_count" -gt 0 ]; then
        echo "  Expired backups (retention policy):"
        [ "$db_count" -gt 0 ] && echo "    • $db_count database backups ($db_size)"
        [ "$files_count" -gt 0 ] && echo "    • $files_count archived files ($files_size)"
        echo "    Total: $(format_bytes "$total_size") can be freed"
        echo ""
    fi

    # Analyze duplicates
    IFS='|' read -r dup_count dup_size <<< "$(analyze_duplicates)"

    if [ "$dup_count" -gt 0 ]; then
        echo "  Duplicate backups:"
        echo "    • $dup_count identical database backups"
        echo "    • $dup_size can be freed"
        echo ""
    fi

    # Analyze orphaned
    IFS='|' read -r orphan_count orphan_size <<< "$(analyze_orphaned)"

    if [ "$orphan_count" -gt 0 ]; then
        echo "  Orphaned archived files:"
        echo "    • $orphan_count archived versions of deleted files"
        echo "    • $orphan_size can be freed"
        echo ""
    fi

    color_bold "──────────────────────────────────────────────"
    echo ""
    color_cyan "To apply recommendations, run:"
    echo "  backup-cleanup.sh --auto"
    echo ""
}

# ==============================================================================
# INTERACTIVE CLEANUP WIZARD
# ==============================================================================

interactive_cleanup() {
    # Analyze current state
    IFS='|' read -r db_count db_size files_count files_size total_size <<< "$(analyze_cleanup)"

    local content=$(cat <<EOF

Current retention policy:
  Database: $DB_RETENTION_DAYS days
  Files:    $FILE_RETENTION_DAYS days

Cleanup preview:
  Database backups to delete: $db_count ($db_size)
  Archived files to delete:   $files_count ($files_size)
  Total space to free:        $(format_bytes "$total_size")

⚠️  Warning: Deleted backups cannot be recovered

Options:
  [1] Proceed with cleanup
  [2] Adjust retention policy (this session only)
  [3] Clean duplicates and orphaned files
  [4] Preview details
  [5] Cancel

EOF
    )

    draw_box "Backup Cleanup" "$content"
    echo ""

    read -p "Select option [1-5]: " option

    case "$option" in
        1)
            echo ""
            if confirm "Proceed with cleanup?"; then
                echo ""
                execute_cleanup "$DB_RETENTION_DAYS" "$FILE_RETENTION_DAYS" "false"
                echo ""
                color_green "✅ Cleanup complete"
            else
                echo "Cancelled."
            fi
            ;;
        2)
            echo ""
            local new_db_retention=$(prompt "Database retention (days)" "$DB_RETENTION_DAYS")
            local new_file_retention=$(prompt "File retention (days)" "$FILE_RETENTION_DAYS")

            # Re-analyze with new retention
            IFS='|' read -r db_count db_size files_count files_size total_size <<< "$(analyze_cleanup "$new_db_retention" "$new_file_retention")"

            echo ""
            color_cyan "With new retention policy:"
            echo "  Database backups to delete: $db_count ($db_size)"
            echo "  Archived files to delete:   $files_count ($files_size)"
            echo "  Total space to free:        $(format_bytes "$total_size")"
            echo ""

            if confirm "Proceed with this cleanup?"; then
                echo ""
                execute_cleanup "$new_db_retention" "$new_file_retention" "false"
                echo ""
                color_green "✅ Cleanup complete"
            else
                echo "Cancelled."
            fi
            ;;
        3)
            echo ""
            clean_duplicates "false"
            echo ""
            clean_orphaned "false"
            ;;
        4)
            echo ""
            execute_cleanup "$DB_RETENTION_DAYS" "$FILE_RETENTION_DAYS" "true"
            ;;
        5|*)
            echo "Cancelled."
            exit 0
            ;;
    esac
}

# ==============================================================================
# MAIN
# ==============================================================================

color_bold "═══════════════════════════════════════════════"
color_bold "Checkpoint - Cleanup Utility"
color_bold "═══════════════════════════════════════════════"
echo ""
color_cyan "Project: $PROJECT_NAME"
color_cyan "Backups: $BACKUP_DIR"
echo ""

# Recommendations mode
if [ "$RECOMMENDATIONS_MODE" = "true" ]; then
    show_recommendations
    exit 0
fi

# Preview mode
if [ "$PREVIEW_MODE" = "true" ]; then
    color_bold "Preview Mode (Dry Run)"
    echo ""
    execute_cleanup "$DB_RETENTION_DAYS" "$FILE_RETENTION_DAYS" "true"
    echo ""
    color_cyan "ℹ️  No changes were made (dry run)"
    exit 0
fi

# Auto mode
if [ "$AUTO_MODE" = "true" ]; then
    color_bold "Auto Cleanup Mode"
    echo ""

    local db_retention="$DB_RETENTION_DAYS"
    local file_retention="$FILE_RETENTION_DAYS"

    # Apply custom retention if specified
    if [ -n "$OLDER_THAN" ]; then
        db_retention="${OLDER_THAN%d}"
        file_retention="${OLDER_THAN%d}"
    fi

    execute_cleanup "$db_retention" "$file_retention" "false"
    echo ""

    # Also clean duplicates and orphaned if found
    clean_duplicates "false"
    echo ""
    clean_orphaned "false"

    echo ""
    color_green "✅ Auto cleanup complete"
    exit 0
fi

# Interactive mode
interactive_cleanup

echo ""
color_bold "═══════════════════════════════════════════════"
