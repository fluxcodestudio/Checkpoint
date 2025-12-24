#!/bin/bash
# ClaudeCode Project Backups - Restore Utility
# Restore files or databases from backups

set -euo pipefail

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

PROJECT_DIR="${1:-$PWD}"
CONFIG_FILE="$PROJECT_DIR/.backup-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ No backup configuration found in: $PROJECT_DIR" >&2
    echo "Run install.sh first or specify project directory: restore.sh /path/to/project" >&2
    exit 1
fi

source "$CONFIG_FILE"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

list_database_backups() {
    echo "Available database backups:"
    echo ""

    if [ ! -d "$DATABASE_DIR" ]; then
        echo "  (none)"
        return
    fi

    find "$DATABASE_DIR" -name "*.db.gz" -type f | sort -r | head -20 | while read -r backup; do
        size=$(du -h "$backup" | cut -f1)
        filename=$(basename "$backup")
        echo "  - $filename ($size)"
    done

    echo ""
    total=$(find "$DATABASE_DIR" -name "*.db.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "Total: $total backups (showing newest 20)"
}

list_file_backups() {
    local file_pattern="$1"

    echo "Available backups for: $file_pattern"
    echo ""

    # Current version
    if [ -f "$FILES_DIR/$file_pattern" ]; then
        size=$(du -h "$FILES_DIR/$file_pattern" | cut -f1)
        mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$FILES_DIR/$file_pattern")
        echo "  CURRENT: $mtime ($size)"
    else
        echo "  CURRENT: (none)"
    fi

    echo ""
    echo "  ARCHIVED VERSIONS:"

    # Find archived versions
    find "$ARCHIVED_DIR" -name "${file_pattern}.*" -type f 2>/dev/null | sort -r | head -20 | while read -r backup; do
        size=$(du -h "$backup" | cut -f1)
        timestamp=$(basename "$backup" | sed "s/${file_pattern}.//")
        # Convert timestamp to readable format
        ts_year="20${timestamp:0:4}"
        ts_month="${timestamp:4:2}"
        ts_day="${timestamp:6:2}"
        ts_hour="${timestamp:9:2}"
        ts_min="${timestamp:11:2}"
        ts_sec="${timestamp:13:2}"
        readable="$ts_year-$ts_month-$ts_day $ts_hour:$ts_min:$ts_sec"
        echo "    - $readable ($size)"
    done
}

restore_database() {
    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        echo "❌ Backup file not found: $backup_file" >&2
        return 1
    fi

    if [ -z "$DB_PATH" ]; then
        echo "❌ No database configured" >&2
        return 1
    fi

    echo "⚠️  This will REPLACE the current database:"
    echo "   From: $backup_file"
    echo "   To: $DB_PATH"
    echo ""
    read -p "Continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        return 1
    fi

    echo "Restoring database..."

    # Backup current database first
    if [ -f "$DB_PATH" ]; then
        current_backup="$DB_PATH.pre-restore.$(date +%Y%m%d_%H%M%S)"
        cp "$DB_PATH" "$current_backup"
        echo "✅ Current database backed up to: $current_backup"
    fi

    # Decompress and restore
    gunzip -c "$backup_file" > "$DB_PATH"

    if [ $? -eq 0 ]; then
        echo "✅ Database restored successfully"
        echo "   Path: $DB_PATH"
    else
        echo "❌ Restore failed" >&2
        return 1
    fi
}

restore_file() {
    local file_path="$1"
    local version="${2:-current}"

    local source_file=""

    if [ "$version" = "current" ]; then
        source_file="$FILES_DIR/$file_path"
    else
        # Find archived version by timestamp
        source_file=$(find "$ARCHIVED_DIR" -name "${file_path}.${version}" -type f 2>/dev/null | head -1)
    fi

    if [ ! -f "$source_file" ]; then
        echo "❌ Backup file not found: $source_file" >&2
        return 1
    fi

    local dest_file="$PROJECT_DIR/$file_path"

    echo "Restoring file:"
    echo "   From: $source_file"
    echo "   To: $dest_file"
    echo ""
    read -p "Continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        return 1
    fi

    # Backup current file first if it exists
    if [ -f "$dest_file" ]; then
        current_backup="$dest_file.pre-restore.$(date +%Y%m%d_%H%M%S)"
        cp "$dest_file" "$current_backup"
        echo "✅ Current file backed up to: $current_backup"
    fi

    # Create directory if needed
    mkdir -p "$(dirname "$dest_file")"

    # Restore
    cp "$source_file" "$dest_file"

    if [ $? -eq 0 ]; then
        echo "✅ File restored successfully"
        echo "   Path: $dest_file"
    else
        echo "❌ Restore failed" >&2
        return 1
    fi
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

echo "═══════════════════════════════════════════════"
echo "ClaudeCode Project Backups - Restore Utility"
echo "═══════════════════════════════════════════════"
echo ""
echo "Project: $PROJECT_NAME"
echo "Backups: $BACKUP_DIR"
echo ""
echo "What do you want to restore?"
echo ""
echo "1) Database (from snapshot)"
echo "2) File (current or archived version)"
echo "3) List all backups"
echo "4) Exit"
echo ""
read -p "Select option [1-4]: " option

case "$option" in
    1)
        # Restore database
        echo ""
        list_database_backups
        echo ""
        read -p "Enter backup filename to restore: " backup_name

        if [ -n "$backup_name" ]; then
            backup_path="$DATABASE_DIR/$backup_name"
            restore_database "$backup_path"
        fi
        ;;

    2)
        # Restore file
        echo ""
        read -p "Enter file path (relative to project root): " file_path

        if [ -n "$file_path" ]; then
            echo ""
            list_file_backups "$file_path"
            echo ""
            echo "Restore options:"
            echo "  - Enter 'current' for latest backup"
            echo "  - Enter timestamp for archived version (YYYYMMDD_HHMMSS)"
            echo ""
            read -p "Version to restore: " version
            version=${version:-current}

            restore_file "$file_path" "$version"
        fi
        ;;

    3)
        # List all backups
        echo ""
        list_database_backups
        echo ""
        echo "═══════════════════════════════════════════════"
        echo ""
        echo "File backups:"
        echo ""

        if [ -d "$FILES_DIR" ]; then
            find "$FILES_DIR" -type f | while read -r file; do
                rel_path="${file#$FILES_DIR/}"
                echo "  - $rel_path"
            done
        else
            echo "  (none)"
        fi

        echo ""
        total_files=$(find "$FILES_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        total_archived=$(find "$ARCHIVED_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo "Total: $total_files current files, $total_archived archived versions"
        ;;

    4)
        echo "Exiting."
        exit 0
        ;;

    *)
        echo "Invalid option" >&2
        exit 1
        ;;
esac

echo ""
echo "═══════════════════════════════════════════════"
