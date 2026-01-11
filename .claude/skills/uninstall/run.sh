#!/usr/bin/env bash
# Uninstall Skill - Remove Checkpoint from project
set -euo pipefail

PROJECT_DIR="${PWD}"

# Find uninstall script
UNINSTALL_CMD=""
if [[ -f "./bin/uninstall.sh" ]]; then
    UNINSTALL_CMD="./bin/uninstall.sh"
elif [[ -f "$HOME/.local/lib/checkpoint/bin/uninstall.sh" ]]; then
    UNINSTALL_CMD="$HOME/.local/lib/checkpoint/bin/uninstall.sh"
elif command -v backup-uninstall &>/dev/null; then
    UNINSTALL_CMD="backup-uninstall"
fi

# Parse arguments
FORCE=false
KEEP_DATA=true
for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE=true
            ;;
        --no-keep-data)
            KEEP_DATA=false
            ;;
    esac
done

if [[ -z "$UNINSTALL_CMD" ]]; then
    echo "Error: Checkpoint uninstaller not found"
    echo ""
    echo "Manual uninstall steps:"
    echo "  1. Remove .backup-config.sh"
    echo "  2. Remove .claude/backup-daemon.sh"
    echo "  3. Unload LaunchAgent:"
    echo "     launchctl unload ~/Library/LaunchAgents/com.claudecode.backup.*.plist"
    echo "  4. Remove LaunchAgent plist file"
    exit 1
fi

echo "═══════════════════════════════════════════════"
echo "Checkpoint - Uninstall"
echo "═══════════════════════════════════════════════"
echo ""
echo "Project: $(basename "$PROJECT_DIR")"
echo "Path: $PROJECT_DIR"
echo ""

if [[ "$FORCE" != "true" ]]; then
    echo "This will remove the Checkpoint backup system from this project."
    if [[ "$KEEP_DATA" == "true" ]]; then
        echo "Backup data will be preserved."
    else
        echo "WARNING: Backup data will be DELETED!"
    fi
    echo ""
    read -p "Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Run uninstaller
if [[ "$FORCE" == "true" ]]; then
    echo "yes" | exec "$UNINSTALL_CMD" "$PROJECT_DIR"
else
    exec "$UNINSTALL_CMD" "$PROJECT_DIR"
fi
