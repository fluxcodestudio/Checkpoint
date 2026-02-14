#!/usr/bin/env bash
# ==============================================================================
# Checkpoint Helper - Menu Bar App Installer
# ==============================================================================
# Builds and installs the CheckpointHelper menu bar app.
# Called automatically by install-global.sh or can be run standalone.
# ==============================================================================

set -euo pipefail

# Helper app is macOS only (native menu bar app)
if [ "$(uname -s)" != "Darwin" ]; then
    echo "Helper app is macOS only"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PACKAGE_DIR/lib/core/logging.sh"
source "$PACKAGE_DIR/lib/platform/daemon-manager.sh"
HELPER_DIR="$PACKAGE_DIR/helper"
APP_NAME="CheckpointHelper"
APP_PATH="/Applications/$APP_NAME.app"
PREBUILT_APP="$HELPER_DIR/$APP_NAME.app"

echo "═══════════════════════════════════════════════"
echo "Checkpoint Helper - Menu Bar App"
echo "═══════════════════════════════════════════════"
echo ""

# Already guarded at top of script — we're on macOS

# Check for Xcode command line tools
if ! xcode-select -p &>/dev/null; then
    echo "❌ Xcode Command Line Tools not found"
    echo ""
    echo "Install with:"
    echo "  xcode-select --install"
    echo ""
    exit 1
fi

# Check for existing app and offer to update
if [[ -d "$APP_PATH" ]]; then
    echo "CheckpointHelper is already installed."
    read -p "Reinstall/update? (y/n) [y]: " confirm
    confirm=${confirm:-y}
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Skipping helper app installation."
        exit 0
    fi
    echo ""
fi

# Stop existing helper if running
pkill -x "$APP_NAME" 2>/dev/null || true

# Check for pre-built app first
if [[ -d "$PREBUILT_APP" ]]; then
    echo "Installing pre-built helper app..."
    rm -rf "$APP_PATH"
    cp -r "$PREBUILT_APP" "$APP_PATH"
else
    # Build from source
    echo "Building helper app from source..."
    echo ""

    if [[ ! -f "$HELPER_DIR/build.sh" ]]; then
        echo "❌ Helper source not found at $HELPER_DIR"
        exit 1
    fi

    cd "$HELPER_DIR"
    if ./build.sh release; then
        echo ""
        echo "Installing to /Applications..."
        rm -rf "$APP_PATH"
        cp -r "$HELPER_DIR/$APP_NAME.app" "$APP_PATH"
        rm -rf "$HELPER_DIR/$APP_NAME.app"
    else
        echo "❌ Build failed"
        exit 1
    fi
fi

# Sign the app
echo "Signing app..."
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true

# Add to Login Items
echo "Adding to Login Items..."
osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP_PATH\", hidden:true}" 2>/dev/null || {
    echo "⚠️  Could not add to Login Items automatically."
    echo "   Add manually: System Preferences → Users & Groups → Login Items"
}

# Install helper daemon via daemon-manager.sh (handles launchd/systemd/cron)
install_daemon "helper" "$APP_PATH/Contents/MacOS/$APP_NAME" "$HOME" "checkpoint" "watchdog"

# Start the app
echo "Starting Checkpoint Helper..."
open "$APP_PATH"

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Checkpoint Helper Installed!"
echo "═══════════════════════════════════════════════"
echo ""
echo "The menu bar app will:"
echo "  • Show backup status in menu bar"
echo "  • Alert you if daemon stops"
echo "  • Provide quick backup controls"
echo "  • Start automatically at login"
echo ""
