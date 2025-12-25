#!/bin/bash
# ==============================================================================
# Checkpoint - Global Installation
# ==============================================================================
# Installs Checkpoint system-wide for use across all projects
# Usage: ./bin/install-global.sh
# ==============================================================================

set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Load dependency manager
source "$PACKAGE_DIR/lib/dependency-manager.sh"

echo "═══════════════════════════════════════════════"
echo "Checkpoint - Global Installation"
echo "═══════════════════════════════════════════════"
echo ""
echo "This will install Checkpoint system-wide."
echo "Commands will be available in all projects."
echo ""

# Load dependency manager
source "$PACKAGE_DIR/lib/dependency-manager.sh"

# ==============================================================================
# CHECK BASH VERSION (for TUI dashboard features)
# ==============================================================================

if ! check_bash_version; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    # Offer to upgrade bash (non-blocking)
    require_bash || true  # Continue even if user declines
    echo ""
fi

# ==============================================================================
# CHECK FOR DIALOG (for best dashboard experience)
# ==============================================================================

if ! check_dialog; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    # Offer to install dialog (non-blocking)
    require_dialog || true  # Continue even if user declines
    echo ""
fi

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

create_symlink "checkpoint.sh" "checkpoint"
create_symlink "backup-now.sh" "backup-now"
create_symlink "backup-status.sh" "backup-status"
create_symlink "backup-restore.sh" "backup-restore"
create_symlink "backup-cleanup.sh" "backup-cleanup"
create_symlink "backup-cloud-config.sh" "backup-cloud-config"
create_symlink "backup-daemon.sh" "backup-daemon"
create_symlink "backup-update.sh" "backup-update"
create_symlink "backup-pause.sh" "backup-pause"
create_symlink "configure-project.sh" "configure-project"
create_symlink "uninstall-global.sh" "backup-uninstall"

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
echo "  checkpoint              Interactive command center"
echo "  backup-now              Run backup immediately"
echo "  backup-status           View backup status"
echo "  backup-restore          Restore from backup"
echo "  backup-cleanup          Clean old backups"
echo "  backup-cloud-config     Configure cloud storage"
echo "  backup-update           Update to latest version"
echo "  backup-uninstall        Uninstall Checkpoint globally"
echo ""

# ==============================================================================
# OPTIONAL: CONFIGURE CURRENT PROJECT
# ==============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "Configure a project now? (Y/n): " configure_now
configure_now=${configure_now:-y}
echo ""

if [[ "$configure_now" =~ ^[Yy]$ ]]; then
    # Ask for project directory
    read -p "Project directory [current: $PWD]: " project_path
    project_path=${project_path:-$PWD}

    # Expand ~ to home directory
    project_path="${project_path/#\~/$HOME}"

    # Convert to absolute path
    project_path=$(cd "$project_path" 2>/dev/null && pwd || echo "$project_path")

    if [[ ! -d "$project_path" ]]; then
        echo "❌ Directory not found: $project_path"
        echo "   You can configure projects later by running:"
        echo "   cd /your/project && backup-now"
        echo ""
    else
        echo "Configuring: $project_path"
        echo ""

        # Run project configuration wizard
        "$LIB_DIR/bin/configure-project.sh" "$project_path"
    fi
else
    echo "Next steps:"
    echo "  1. Navigate to any project directory"
    echo "  2. Run: backup-now"
    echo "  3. Follow the configuration wizard"
    echo ""
fi

echo "To uninstall:"
echo "  backup-uninstall"
echo ""
echo "Or manually:"
echo "  rm -rf $LIB_DIR"
echo "  rm -f $BIN_DIR/{backup-*,checkpoint,configure-project}"
echo ""
echo "═══════════════════════════════════════════════"
