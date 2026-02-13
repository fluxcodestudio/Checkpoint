#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Global Uninstaller
# ==============================================================================
# Removes Checkpoint from system-wide installation
# Usage: ./bin/uninstall-global.sh
# ==============================================================================

set -euo pipefail

echo "═══════════════════════════════════════════════"
echo "Checkpoint - Global Uninstaller"
echo "═══════════════════════════════════════════════"
echo ""

# Detect installation location
if [[ -d "$HOME/.local/lib/checkpoint" ]]; then
    INSTALL_PREFIX="$HOME/.local"
    INSTALL_MODE="user (~/.local)"
elif [[ -d "/usr/local/lib/checkpoint" ]]; then
    INSTALL_PREFIX="/usr/local"
    INSTALL_MODE="system (/usr/local)"
else
    echo "❌ No global Checkpoint installation found"
    echo ""
    echo "Checked locations:"
    echo "  - $HOME/.local/lib/checkpoint"
    echo "  - /usr/local/lib/checkpoint"
    echo ""
    exit 1
fi

BIN_DIR="$INSTALL_PREFIX/bin"
LIB_DIR="$INSTALL_PREFIX/lib/checkpoint"

echo "Found installation: $INSTALL_MODE"
echo ""
echo "⚠️  WARNING: This will remove Checkpoint globally"
echo ""
echo "What will be removed:"
echo "  - Library files: $LIB_DIR"
echo "  - Commands: checkpoint, backup-*, etc."
echo "  - Symlinks from: $BIN_DIR"
echo ""
echo "What will be KEPT:"
echo "  - All project backup data (backups/ folders in projects)"
echo "  - Per-project configurations (.backup-config.sh)"
echo "  - LaunchAgents (per-project daemons)"
echo "  - Global config: ~/.config/checkpoint/"
echo ""
read -p "Continue with uninstall? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Uninstalling..."

# Remove symlinks from bin directory
echo ""
echo "Removing command symlinks..."
for cmd in checkpoint backup-now backup-status backup-restore backup-cleanup \
           backup-cloud-config backup-daemon backup-update backup-pause \
           backup-all backup-uninstall configure-project install-helper uninstall-helper \
           bootstrap.sh; do
    if [[ -L "$BIN_DIR/$cmd" ]] || [[ -f "$BIN_DIR/$cmd" ]]; then
        rm -f "$BIN_DIR/$cmd"
        echo "  ✓ Removed: $cmd"
    fi
done

# Remove library directory
echo ""
echo "Removing library files..."
if [[ -d "$LIB_DIR" ]]; then
    rm -rf "$LIB_DIR"
    echo "  ✓ Removed: $LIB_DIR"
fi

# Remove helper app if installed
APP_NAME="CheckpointHelper"
APP_PATH="/Applications/$APP_NAME.app"
HELPER_PLIST="$HOME/Library/LaunchAgents/com.checkpoint.helper.plist"

if [[ -d "$APP_PATH" ]] || [[ -f "$HELPER_PLIST" ]]; then
    echo ""
    echo "Removing Checkpoint Helper menu bar app..."
    pkill -x "$APP_NAME" 2>/dev/null || true
    launchctl unload "$HELPER_PLIST" 2>/dev/null || true
    rm -f "$HELPER_PLIST"
    rm -rf "$APP_PATH"
    osascript -e "tell application \"System Events\" to delete login item \"$APP_NAME\"" 2>/dev/null || true
    echo "  ✓ Removed: Checkpoint Helper"
fi

# Remove global daemon plist
GLOBAL_PLIST="$HOME/Library/LaunchAgents/com.checkpoint.global-daemon.plist"
if [[ -f "$GLOBAL_PLIST" ]]; then
    echo ""
    echo "Removing global daemon..."
    launchctl unload "$GLOBAL_PLIST" 2>/dev/null || true
    rm -f "$GLOBAL_PLIST"
    echo "  ✓ Removed: Global daemon LaunchAgent"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Global uninstall complete"
echo "═══════════════════════════════════════════════"
echo ""
echo "What remains (safe to delete manually if desired):"
echo "  - Global config: ~/.config/checkpoint/"
echo "  - Project backups: <project>/backups/"
echo "  - LaunchAgents: ~/Library/LaunchAgents/com.claudecode.backup.*.plist"
echo ""
echo "To remove global config:"
echo "  rm -rf ~/.config/checkpoint/"
echo ""
echo "To reinstall:"
echo "  cd /path/to/Checkpoint"
echo "  ./bin/install.sh"
echo ""
echo "═══════════════════════════════════════════════"
