#!/bin/bash
# ClaudeCode Project Backups - Uninstaller
# Removes backup system from a project (keeps backup data)

set -euo pipefail

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

PROJECT_DIR="${1:-$PWD}"
CONFIG_FILE="$PROJECT_DIR/.backup-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ No backup configuration found in: $PROJECT_DIR" >&2
    echo "Nothing to uninstall." >&2
    exit 1
fi

source "$CONFIG_FILE"

# ==============================================================================
# UNINSTALL
# ==============================================================================

echo "═══════════════════════════════════════════════"
echo "ClaudeCode Project Backups - Uninstaller"
echo "═══════════════════════════════════════════════"
echo ""
echo "Project: $PROJECT_NAME"
echo "Path: $PROJECT_DIR"
echo ""
echo "⚠️  WARNING: This will remove the backup system"
echo ""
echo "What will be removed:"
echo "  - Backup scripts (.claude/backup-daemon.sh, hooks)"
echo "  - LaunchAgent (hourly daemon)"
echo "  - Configuration file (.backup-config.sh)"
echo ""
echo "What will be KEPT:"
echo "  - All backup data ($BACKUP_DIR)"
echo "  - Backup logs"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Uninstalling..."

# Stop and remove LaunchAgent
PLIST_FILE="$HOME/Library/LaunchAgents/com.claudecode.backup.${PROJECT_NAME}.plist"

if [ -f "$PLIST_FILE" ]; then
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    rm "$PLIST_FILE"
    echo "✅ LaunchAgent removed"
fi

# Remove backup scripts
if [ -f "$PROJECT_DIR/.claude/backup-daemon.sh" ]; then
    rm "$PROJECT_DIR/.claude/backup-daemon.sh"
    echo "✅ Removed backup-daemon.sh"
fi

if [ -f "$PROJECT_DIR/.claude/hooks/backup-trigger.sh" ]; then
    rm "$PROJECT_DIR/.claude/hooks/backup-trigger.sh"
    echo "✅ Removed backup-trigger.sh"
fi

if [ -f "$PROJECT_DIR/.claude/hooks/pre-database.sh" ]; then
    rm "$PROJECT_DIR/.claude/hooks/pre-database.sh"
    echo "✅ Removed pre-database.sh"
fi

# Remove configuration
if [ -f "$CONFIG_FILE" ]; then
    rm "$CONFIG_FILE"
    echo "✅ Removed configuration"
fi

# Clean up empty directories
if [ -d "$PROJECT_DIR/.claude/hooks" ] && [ -z "$(ls -A "$PROJECT_DIR/.claude/hooks")" ]; then
    rmdir "$PROJECT_DIR/.claude/hooks"
fi

if [ -d "$PROJECT_DIR/.claude" ] && [ -z "$(ls -A "$PROJECT_DIR/.claude")" ]; then
    rmdir "$PROJECT_DIR/.claude"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Uninstall complete"
echo "═══════════════════════════════════════════════"
echo ""
echo "Backup data preserved at: $BACKUP_DIR"
echo ""
echo "To completely remove all backups:"
echo "  rm -rf $BACKUP_DIR"
echo ""
echo "To reinstall:"
echo "  Run install.sh again"
echo ""
echo "═══════════════════════════════════════════════"
