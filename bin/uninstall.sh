#!/usr/bin/env bash
# Checkpoint - Uninstaller
# Removes backup system from a project (keeps backup data)

set -euo pipefail

# ==============================================================================
# ORPHAN CLEANUP MODE (Issue #8)
# ==============================================================================

cleanup_orphans() {
    echo "═══════════════════════════════════════════════"
    echo "Checkpoint - Orphan Cleanup"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "Scanning for orphaned LaunchAgents..."
    echo ""

    local orphans_found=0
    local orphans_cleaned=0

    # Scan all Checkpoint LaunchAgents
    for plist in "$HOME/Library/LaunchAgents"/com.claudecode.backup.*.plist; do
        [ -f "$plist" ] || continue

        # Extract project name from plist filename
        local basename="${plist##*/}"
        local project_name="${basename#com.claudecode.backup.}"
        project_name="${project_name%.plist}"

        # Try to find project directory from plist
        local project_dir=""
        if command -v /usr/libexec/PlistBuddy &>/dev/null; then
            project_dir=$(/usr/libexec/PlistBuddy -c "Print :WorkingDirectory" "$plist" 2>/dev/null || echo "")
        fi

        # If we couldn't extract from plist, check state directory
        if [ -z "$project_dir" ]; then
            local state_dir="$HOME/.claudecode-backups/state/$project_name"
            if [ -f "$state_dir/.project-dir" ]; then
                project_dir=$(cat "$state_dir/.project-dir" 2>/dev/null || echo "")
            fi
        fi

        # Check if project directory exists
        if [ -n "$project_dir" ] && [ ! -d "$project_dir" ]; then
            orphans_found=$((orphans_found + 1))
            echo "⚠️  Orphan found: $project_name"
            echo "   Missing: $project_dir"

            if [ "${DRY_RUN:-false}" = "true" ]; then
                echo "   [DRY RUN] Would remove: $plist"
            else
                # Unload and remove
                if launchctl unload "$plist" 2>/dev/null; then
                    rm -f "$plist"
                    orphans_cleaned=$((orphans_cleaned + 1))
                    echo "   ✅ Removed LaunchAgent"
                else
                    echo "   ❌ Failed to unload (may already be unloaded)"
                    rm -f "$plist" 2>/dev/null && orphans_cleaned=$((orphans_cleaned + 1))
                fi

                # Clean up state directory
                local state_dir="$HOME/.claudecode-backups/state/$project_name"
                if [ -d "$state_dir" ]; then
                    rm -rf "$state_dir"
                    echo "   ✅ Cleaned state files"
                fi

                # Clean up lock directory
                local lock_dir="$HOME/.claudecode-backups/locks/${project_name}.lock"
                if [ -d "$lock_dir" ]; then
                    rm -rf "$lock_dir"
                fi
            fi
            echo ""
        fi
    done

    echo "═══════════════════════════════════════════════"
    if [ $orphans_found -eq 0 ]; then
        echo "✅ No orphaned LaunchAgents found"
    elif [ "${DRY_RUN:-false}" = "true" ]; then
        echo "Found $orphans_found orphan(s). Run without --dry-run to clean."
    else
        echo "✅ Cleaned $orphans_cleaned of $orphans_found orphan(s)"
    fi
    echo "═══════════════════════════════════════════════"
}

# Check for orphan cleanup mode
if [ "${1:-}" = "--cleanup-orphans" ] || [ "${1:-}" = "--orphans" ]; then
    if [ "${2:-}" = "--dry-run" ]; then
        DRY_RUN=true
    fi
    cleanup_orphans
    exit 0
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<EOF
Checkpoint - Uninstaller

USAGE:
    uninstall.sh [PROJECT_DIR]       Uninstall from specific project
    uninstall.sh --cleanup-orphans   Find and remove orphaned LaunchAgents
    uninstall.sh --orphans --dry-run Preview orphans without removing

OPTIONS:
    --cleanup-orphans, --orphans  Scan for and remove orphaned LaunchAgents
    --dry-run                     Preview changes without making them
    --help, -h                    Show this help message

EOF
    exit 0
fi

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
echo "Checkpoint - Uninstaller"
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

# Remove Claude Code hooks if they exist
CLAUDE_HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
if [ -d "$CLAUDE_HOOKS_DIR" ]; then
    # Remove backup hook scripts
    rm -f "$CLAUDE_HOOKS_DIR/backup-on-stop.sh"
    rm -f "$CLAUDE_HOOKS_DIR/backup-on-edit.sh"
    rm -f "$CLAUDE_HOOKS_DIR/backup-on-commit.sh"

    # Remove directory if empty
    rmdir "$CLAUDE_HOOKS_DIR" 2>/dev/null || true

    echo "  Claude Code hooks removed"
fi

# Remove hooks from .claude/settings.json if jq is available
CLAUDE_SETTINGS="$PROJECT_DIR/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ] && command -v jq &> /dev/null; then
    # Check if our hooks are in the settings
    if jq -e '.hooks.Stop[0].hooks[0].command | contains("backup-on-stop")' "$CLAUDE_SETTINGS" &> /dev/null; then
        # Remove our hook entries (preserving other hooks)
        jq 'del(.hooks.Stop[] | select(.hooks[].command | contains("backup-on")))
            | del(.hooks.PostToolUse[] | select(.hooks[].command | contains("backup-on")))
            | if .hooks.Stop == [] then del(.hooks.Stop) else . end
            | if .hooks.PostToolUse == [] then del(.hooks.PostToolUse) else . end
            | if .hooks == {} then del(.hooks) else . end' "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp"
        mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
        echo "  Hooks removed from .claude/settings.json"
    fi
fi

# Stop and remove watcher LaunchAgent if exists
WATCHER_PLIST_NAME="com.claudecode.backup-watcher.${PROJECT_NAME}.plist"
WATCHER_PLIST_PATH="$HOME/Library/LaunchAgents/$WATCHER_PLIST_NAME"
if [ -f "$WATCHER_PLIST_PATH" ]; then
    launchctl unload "$WATCHER_PLIST_PATH" 2>/dev/null || true
    rm -f "$WATCHER_PLIST_PATH"
    echo "✅ File watcher removed"
fi

# Clean up watcher PID files
STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"
PROJECT_STATE_DIR="$STATE_DIR/${PROJECT_NAME}"
rm -f "$PROJECT_STATE_DIR/.watcher.pid" "$PROJECT_STATE_DIR/.watcher-timer.pid" 2>/dev/null

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
