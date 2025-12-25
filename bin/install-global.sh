#!/bin/bash
# ==============================================================================
# Checkpoint - Global Installation
# ==============================================================================
# Installs Checkpoint system-wide for use across all projects
# Usage: ./bin/install-global.sh
# ==============================================================================

set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "═══════════════════════════════════════════════"
echo "Checkpoint - Global Installation"
echo "═══════════════════════════════════════════════"
echo ""
echo "This will install Checkpoint system-wide."
echo "Commands will be available in all projects."
echo ""

# Determine installation prefix
if [[ -w "/usr/local/bin" ]]; then
    INSTALL_PREFIX="/usr/local"
    echo "Installing to: /usr/local (system-wide)"
else
    INSTALL_PREFIX="$HOME/.local"
    echo "Installing to: ~/.local (user-only, no sudo required)"
    echo ""
    echo "⚠️  Make sure ~/.local/bin is in your PATH:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
read -p "Continue with installation? (y/n) [y]: " confirm
confirm=${confirm:-y}

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 0
fi

# Create directories
BIN_DIR="$INSTALL_PREFIX/bin"
LIB_DIR="$INSTALL_PREFIX/lib/checkpoint"

echo ""
echo "Creating directories..."
mkdir -p "$BIN_DIR"
mkdir -p "$LIB_DIR/bin"
mkdir -p "$LIB_DIR/lib"
mkdir -p "$LIB_DIR/templates"
mkdir -p "$LIB_DIR/integrations"

# Copy library files
echo "Installing library files..."
cp -r "$PACKAGE_DIR/lib/"* "$LIB_DIR/lib/"
echo "✅ Libraries installed to $LIB_DIR/lib/"

# Copy binary scripts
echo "Installing scripts..."
cp -r "$PACKAGE_DIR/bin/"*.sh "$LIB_DIR/bin/"
chmod +x "$LIB_DIR/bin/"*.sh
echo "✅ Scripts installed to $LIB_DIR/bin/"

# Copy templates
echo "Installing templates..."
cp -r "$PACKAGE_DIR/templates/"* "$LIB_DIR/templates/"
echo "✅ Templates installed to $LIB_DIR/templates/"

# Copy integrations
echo "Installing integrations..."
cp -r "$PACKAGE_DIR/integrations/"* "$LIB_DIR/integrations/"
echo "✅ Integrations installed to $LIB_DIR/integrations/"

# Copy VERSION file
cp "$PACKAGE_DIR/VERSION" "$LIB_DIR/VERSION"

# Create command symlinks
echo ""
echo "Creating command symlinks..."

create_symlink() {
    local script="$1"
    local command="$2"
    local target="$BIN_DIR/$command"

    # Remove existing symlink/file
    rm -f "$target"

    # Create symlink
    ln -s "$LIB_DIR/bin/$script" "$target"

    echo "  ✅ $command → $LIB_DIR/bin/$script"
}

create_symlink "backup-now.sh" "backup-now"
create_symlink "backup-status.sh" "backup-status"
create_symlink "backup-restore.sh" "backup-restore"
create_symlink "backup-cleanup.sh" "backup-cleanup"
create_symlink "backup-cloud-config.sh" "backup-cloud-config"
create_symlink "backup-daemon.sh" "backup-daemon"

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Global Installation Complete!"
echo "═══════════════════════════════════════════════"
echo ""
echo "Installation details:"
echo "  Binaries: $BIN_DIR"
echo "  Libraries: $LIB_DIR"
echo ""
echo "Available commands (system-wide):"
echo "  backup-now              Run backup immediately"
echo "  backup-status           View backup status"
echo "  backup-restore          Restore from backup"
echo "  backup-cleanup          Clean old backups"
echo "  backup-cloud-config     Configure cloud storage"
echo ""
echo "Next steps:"
echo "  1. Navigate to any project directory"
echo "  2. Run: backup-cloud-config (to set up per-project)"
echo "  3. Or create .backup-config.sh manually"
echo ""
echo "To uninstall:"
echo "  rm -rf $LIB_DIR"
echo "  rm -f $BIN_DIR/backup-*"
echo ""
echo "═══════════════════════════════════════════════"
