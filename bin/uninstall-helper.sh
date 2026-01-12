#!/usr/bin/env bash
# ==============================================================================
# Checkpoint Helper - Menu Bar App Uninstaller
# ==============================================================================

set -euo pipefail

APP_NAME="CheckpointHelper"
APP_PATH="/Applications/$APP_NAME.app"
HELPER_PLIST="$HOME/Library/LaunchAgents/com.checkpoint.helper.plist"

echo "═══════════════════════════════════════════════"
echo "Checkpoint Helper - Uninstall"
echo "═══════════════════════════════════════════════"
echo ""

# Check if installed
if [[ ! -d "$APP_PATH" ]] && [[ ! -f "$HELPER_PLIST" ]]; then
    echo "Checkpoint Helper is not installed."
    exit 0
fi

read -p "Uninstall Checkpoint Helper? (y/n) [n]: " confirm
confirm=${confirm:-n}

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "Stopping helper app..."
pkill -x "$APP_NAME" 2>/dev/null || true

echo "Removing LaunchAgent..."
launchctl unload "$HELPER_PLIST" 2>/dev/null || true
rm -f "$HELPER_PLIST"

echo "Removing from Login Items..."
osascript -e "tell application \"System Events\" to delete login item \"$APP_NAME\"" 2>/dev/null || true

echo "Removing app..."
rm -rf "$APP_PATH"

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Checkpoint Helper Uninstalled"
echo "═══════════════════════════════════════════════"
echo ""
