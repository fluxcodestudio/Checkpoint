#!/bin/bash
# ClaudeCode Project Backups - Status Checker
# Check backup system health and statistics

set -euo pipefail

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

PROJECT_DIR="${1:-$PWD}"
CONFIG_FILE="$PROJECT_DIR/.backup-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ No backup configuration found in: $PROJECT_DIR" >&2
    echo "Run install.sh first or specify project directory: status.sh /path/to/project" >&2
    exit 1
fi

source "$CONFIG_FILE"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

check_component() {
    local component="$1"
    local path="$2"

    if [ -f "$path" ]; then
        echo "  ✅ $component"
        return 0
    else
        echo "  ❌ $component (missing: $path)"
        return 1
    fi
}

format_time_ago() {
    local timestamp="$1"
    local now=$(date +%s)
    local diff=$((now - timestamp))

    if [ $diff -lt 60 ]; then
        echo "${diff}s ago"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60))m ago"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# ==============================================================================
# STATUS REPORT
# ==============================================================================

echo "═══════════════════════════════════════════════"
echo "ClaudeCode Project Backups - Status Report"
echo "═══════════════════════════════════════════════"
echo ""

# Project Info
echo "📂 Project Information:"
echo "  Name: $PROJECT_NAME"
echo "  Path: $PROJECT_DIR"
echo ""

# Configuration
echo "⚙️  Configuration:"
echo "  Database: ${DB_PATH:-None}"
echo "  Database Type: $DB_TYPE"
echo "  Retention: ${DB_RETENTION_DAYS}d (DB), ${FILE_RETENTION_DAYS}d (files)"
echo "  Drive Verification: $DRIVE_VERIFICATION_ENABLED"
echo "  Auto-commit: $AUTO_COMMIT_ENABLED"
echo ""

# Components Status
echo "🔧 Components:"
all_components_ok=true

check_component "Backup daemon" "$PROJECT_DIR/.claude/backup-daemon.sh" || all_components_ok=false
check_component "Backup trigger" "$PROJECT_DIR/.claude/hooks/backup-trigger.sh" || all_components_ok=false

if [ "$DB_TYPE" != "none" ]; then
    check_component "Database safety hook" "$PROJECT_DIR/.claude/hooks/pre-database.sh" || all_components_ok=false
fi

check_component "Configuration" "$CONFIG_FILE" || all_components_ok=false

echo ""

# LaunchAgent Status
echo "⏰ LaunchAgent (hourly daemon):"
PLIST_FILE="$HOME/Library/LaunchAgents/com.claudecode.backup.${PROJECT_NAME}.plist"

if [ -f "$PLIST_FILE" ]; then
    if launchctl list | grep -q "com.claudecode.backup.${PROJECT_NAME}"; then
        echo "  ✅ Installed and running"
    else
        echo "  ⚠️  Installed but not running"
        echo "     Load with: launchctl load $PLIST_FILE"
    fi
else
    echo "  ❌ Not installed"
    echo "     Run install.sh to set up"
fi

echo ""

# Drive Status (if verification enabled)
if [ "$DRIVE_VERIFICATION_ENABLED" = true ]; then
    echo "💾 External Drive:"

    if [ -f "$DRIVE_MARKER_FILE" ]; then
        echo "  ✅ Connected and verified"
        echo "     Marker: $DRIVE_MARKER_FILE"
    else
        echo "  ❌ Not connected or wrong drive"
        echo "     Expected marker: $DRIVE_MARKER_FILE"
    fi

    echo ""
fi

# Backup Statistics
echo "📊 Backup Statistics:"

if [ -d "$BACKUP_DIR" ]; then
    # Database backups
    if [ -d "$DATABASE_DIR" ]; then
        db_count=$(find "$DATABASE_DIR" -name "*.db.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ $db_count -gt 0 ]; then
            db_total_size=$(du -sh "$DATABASE_DIR" 2>/dev/null | cut -f1)
            newest_db=$(find "$DATABASE_DIR" -name "*.db.gz" -type f 2>/dev/null | sort -r | head -1)
            if [ -n "$newest_db" ]; then
                newest_db_name=$(basename "$newest_db")
                newest_db_time=$(stat -f%m "$newest_db")
                echo "  Databases: $db_count backups ($db_total_size total)"
                echo "    Latest: $newest_db_name"
                echo "    Created: $(format_time_ago $newest_db_time)"
            else
                echo "  Databases: $db_count backups"
            fi
        else
            echo "  Databases: 0 backups"
        fi
    else
        echo "  Databases: 0 backups"
    fi

    # File backups
    if [ -d "$FILES_DIR" ]; then
        file_count=$(find "$FILES_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ $file_count -gt 0 ]; then
            files_total_size=$(du -sh "$FILES_DIR" 2>/dev/null | cut -f1)
            echo "  Current Files: $file_count files ($files_total_size total)"
        else
            echo "  Current Files: 0 files"
        fi
    else
        echo "  Current Files: 0 files"
    fi

    # Archived files
    if [ -d "$ARCHIVED_DIR" ]; then
        archived_count=$(find "$ARCHIVED_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ $archived_count -gt 0 ]; then
            archived_total_size=$(du -sh "$ARCHIVED_DIR" 2>/dev/null | cut -f1)
            echo "  Archived Versions: $archived_count files ($archived_total_size total)"
        else
            echo "  Archived Versions: 0 files"
        fi
    else
        echo "  Archived Versions: 0 files"
    fi
else
    echo "  ⚠️  Backup directory not found"
    echo "     Run backup-daemon.sh to initialize"
fi

echo ""

# Last Backup
echo "🕒 Last Backup:"

if [ -f "$BACKUP_TIME_STATE" ]; then
    last_backup=$(cat "$BACKUP_TIME_STATE")
    echo "  $(format_time_ago $last_backup)"
else
    echo "  Never (no state file found)"
fi

echo ""

# Recent Activity (from log)
echo "📝 Recent Activity:"

if [ -f "$LOG_FILE" ]; then
    echo "  Last 5 entries from backup.log:"
    echo ""
    tail -5 "$LOG_FILE" | sed 's/^/    /'
    echo ""
    echo "  Full log: $LOG_FILE"
else
    echo "  (no log file yet)"
fi

echo ""

# Health Check
echo "🏥 Health Check:"
health_issues=0

# Check if backups are running
if [ -f "$BACKUP_TIME_STATE" ]; then
    last_backup=$(cat "$BACKUP_TIME_STATE")
    now=$(date +%s)
    diff=$((now - last_backup))

    # Warn if no backup in >2 hours
    if [ $diff -gt 7200 ]; then
        echo "  ⚠️  No backup in $(format_time_ago $last_backup)"
        echo "     Expected: hourly backups"
        ((health_issues++))
    fi
fi

# Check if drive is connected (if verification enabled)
if [ "$DRIVE_VERIFICATION_ENABLED" = true ] && [ ! -f "$DRIVE_MARKER_FILE" ]; then
    echo "  ⚠️  External drive not connected"
    ((health_issues++))
fi

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo "  ⚠️  Backup directory missing"
    ((health_issues++))
fi

# Check if LaunchAgent is running
if [ -f "$PLIST_FILE" ]; then
    if ! launchctl list | grep -q "com.claudecode.backup.${PROJECT_NAME}"; then
        echo "  ⚠️  LaunchAgent not running"
        ((health_issues++))
    fi
fi

if [ $health_issues -eq 0 ]; then
    echo "  ✅ All systems operational"
fi

echo ""

# Overall Status
echo "═══════════════════════════════════════════════"
if [ $health_issues -eq 0 ] && [ "$all_components_ok" = true ]; then
    echo "✅ Backup system healthy"
else
    echo "⚠️  $health_issues issue(s) detected"
fi
echo "═══════════════════════════════════════════════"
