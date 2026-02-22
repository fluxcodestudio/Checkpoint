#!/usr/bin/env bash
# Checkpoint - Uninstaller
# Removes backup system from a project (keeps backup data)

set -euo pipefail

_UNINSTALL_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$_UNINSTALL_SCRIPT_DIR/../lib/core/logging.sh"
source "$_UNINSTALL_SCRIPT_DIR/../lib/platform/daemon-manager.sh"

# Core backup library (provides get_project_state_id via ops/state.sh)
if [ -f "$_UNINSTALL_SCRIPT_DIR/../lib/backup-lib.sh" ]; then
    source "$_UNINSTALL_SCRIPT_DIR/../lib/backup-lib.sh"
fi

# ==============================================================================
# ORPHAN CLEANUP MODE (Issue #8)
# ==============================================================================

cleanup_orphans() {
    echo "═══════════════════════════════════════════════"
    echo "Checkpoint - Orphan Cleanup"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "Scanning for orphaned daemons..."
    echo ""

    local orphans_found=0
    local orphans_cleaned=0

    # List all checkpoint daemons via daemon-manager.sh (handles launchd/systemd/cron)
    local daemon_list
    daemon_list="$(list_daemons "checkpoint" 2>/dev/null || true)"
    # Also check legacy naming
    local legacy_list
    legacy_list="$(list_daemons "claudecode" 2>/dev/null || true)"

    if [ -n "$legacy_list" ]; then
        if [ -n "$daemon_list" ]; then
            daemon_list="$(printf '%s\n%s' "$daemon_list" "$legacy_list")"
        else
            daemon_list="$legacy_list"
        fi
    fi

    if [ -z "$daemon_list" ]; then
        echo "═══════════════════════════════════════════════"
        echo "✅ No orphaned daemons found"
        echo "═══════════════════════════════════════════════"
        return 0
    fi

    # Extract service names from platform-specific list output
    echo "$daemon_list" | while IFS= read -r line; do
        [ -z "$line" ] && continue

        # Extract service name from various formats
        local service_name=""
        case "$line" in
            *com.checkpoint.*)
                # launchd format: extract after com.checkpoint.
                service_name="$(echo "$line" | sed 's/.*com\.checkpoint\.\([^ 	]*\).*/\1/')"
                ;;
            *com.claudecode.backup.*)
                # legacy launchd format: extract after com.claudecode.backup.
                service_name="$(echo "$line" | sed 's/.*com\.claudecode\.backup\.\([^ 	]*\).*/\1/')"
                ;;
            *checkpoint-*)
                # systemd format: extract after checkpoint-
                service_name="$(echo "$line" | sed 's/.*checkpoint-\([^ 	.]*\).*/\1/')"
                ;;
            *"# checkpoint:"*)
                # cron format: extract after # checkpoint:
                service_name="$(echo "$line" | sed 's/.*# checkpoint:\(.*\)/\1/')"
                ;;
        esac

        [ -z "$service_name" ] && continue

        # Skip non-project daemons (watchdog, helper, watcher prefixes handled below)
        case "$service_name" in
            watchdog|helper) continue ;;
        esac

        # Strip watcher- prefix to get project name for directory check
        local project_name="$service_name"
        case "$service_name" in
            watcher-*) project_name="${service_name#watcher-}" ;;
        esac

        # Try to find project directory from state
        local project_dir=""
        local state_dir="$HOME/.claudecode-backups/state/$project_name"
        if [ -f "$state_dir/.project-dir" ]; then
            project_dir="$(cat "$state_dir/.project-dir" 2>/dev/null || true)"
        fi
        # Also check new state location
        local state_dir2="$HOME/.checkpoint/state/$project_name"
        if [ -z "$project_dir" ] && [ -f "$state_dir2/.project-dir" ]; then
            project_dir="$(cat "$state_dir2/.project-dir" 2>/dev/null || true)"
        fi

        # Check if project directory exists
        if [ -n "$project_dir" ] && [ ! -d "$project_dir" ]; then
            orphans_found=$((orphans_found + 1))
            echo "  Orphan found: $service_name"
            echo "   Missing: $project_dir"

            if [ "${DRY_RUN:-false}" = "true" ]; then
                echo "   [DRY RUN] Would remove daemon: $service_name"
            else
                # Uninstall via daemon-manager.sh (handles launchd/systemd/cron)
                if uninstall_daemon "$service_name"; then
                    orphans_cleaned=$((orphans_cleaned + 1))
                    echo "   Removed daemon"
                else
                    echo "   Failed to remove (may already be removed)"
                fi

                # Clean up state directory
                if [ -d "$state_dir" ]; then
                    rm -rf "$state_dir"
                    echo "   Cleaned state files"
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
        echo "✅ No orphaned daemons found"
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
    uninstall.sh --cleanup-orphans   Find and remove orphaned daemons
    uninstall.sh --orphans --dry-run Preview orphans without removing

OPTIONS:
    --cleanup-orphans, --orphans  Scan for and remove orphaned daemons
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
echo "  - Backup scripts (.claude/backup-daemon.sh)"
echo "  - Backup daemon (hourly schedule)"
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

# Stop and remove watcher daemon via daemon-manager.sh (handles launchd/systemd/cron)
uninstall_daemon "watcher-$PROJECT_NAME" 2>/dev/null && echo "✅ File watcher removed" || true

# Clean up watcher PID files
STATE_DIR="${STATE_DIR:-$HOME/.claudecode-backups/state}"
_PROJECT_STATE_ID=$(get_project_state_id "${PROJECT_DIR:-$PWD}" "${PROJECT_NAME:-}" 2>/dev/null || echo "$PROJECT_NAME")
PROJECT_STATE_DIR="$STATE_DIR/${_PROJECT_STATE_ID}"
rm -f "$PROJECT_STATE_DIR/.watcher.pid" "$PROJECT_STATE_DIR/.watcher-timer.pid" 2>/dev/null

# Stop and remove backup daemon via daemon-manager.sh (handles launchd/systemd/cron)
uninstall_daemon "$PROJECT_NAME" 2>/dev/null && echo "✅ Backup daemon removed" || true

# Remove backup scripts
if [ -f "$PROJECT_DIR/.claude/backup-daemon.sh" ]; then
    rm "$PROJECT_DIR/.claude/backup-daemon.sh"
    echo "✅ Removed backup-daemon.sh"
fi

# Remove configuration
if [ -f "$CONFIG_FILE" ]; then
    rm "$CONFIG_FILE"
    echo "✅ Removed configuration"
fi

# Clean up empty directories
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
