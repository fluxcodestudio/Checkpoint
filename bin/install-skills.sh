#!/usr/bin/env bash
# Checkpoint - Install Skills
# Sets up /checkpoint skill for Claude Code

set -euo pipefail

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

USER_SKILLS_DIR="$HOME/.claude/skills"
PROJECT_SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

echo "Installing Checkpoint skill for Claude Code..."
echo ""
echo "Choose installation location:"
echo "  [1] User (~/.claude/skills) - Available globally in all projects"
echo "  [2] Project (.claude/skills) - Only available in this project"
echo ""
read -p "Install where? (1/2) [1]: " install_choice
install_choice=${install_choice:-1}

if [[ "$install_choice" == "1" ]]; then
    SKILLS_DIR="$USER_SKILLS_DIR"
    INSTALL_SCOPE="globally (all projects)"
else
    SKILLS_DIR="$PROJECT_SKILLS_DIR"
    INSTALL_SCOPE="in this project only"
fi

echo ""
echo "Installing $INSTALL_SCOPE..."
echo ""

# Create skills directory
mkdir -p "$SKILLS_DIR"

# ==============================================================================
# Install /checkpoint skill (new single-file format)
# ==============================================================================

SKILL_SOURCE=""
if [[ -f "$PROJECT_ROOT/skills/checkpoint.md" ]]; then
    SKILL_SOURCE="$PROJECT_ROOT/skills/checkpoint.md"
elif [[ -f "$PROJECT_ROOT/../skills/checkpoint.md" ]]; then
    SKILL_SOURCE="$PROJECT_ROOT/../skills/checkpoint.md"
fi

if [[ -n "$SKILL_SOURCE" ]]; then
    echo "📦 Installing /checkpoint skill..."
    cp "$SKILL_SOURCE" "$SKILLS_DIR/checkpoint.md"
    echo "   ✅ /checkpoint skill installed"
    echo ""
else
    echo "⚠️  Checkpoint skill not found in package"
    echo "   You can manually copy checkpoint.md to $SKILLS_DIR/"
    echo ""
fi

# ==============================================================================
# Summary
# ==============================================================================

echo "═══════════════════════════════════════════════════════════"
echo "✅ Checkpoint skill installed!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Claude Code Integration:"
echo "  /checkpoint              Open interactive command center"
echo ""
echo "Inside the command center you can:"
echo "  • View backup status and health"
echo "  • Run backups immediately"
echo "  • Restore files and databases"
echo "  • Configure settings (global + per-project)"
echo "  • Clean up old backups"
echo "  • Update Checkpoint"
echo "  • Pause/resume automation"
echo "  • Uninstall"
echo ""
echo "Direct CLI commands (also shown in /checkpoint):"
echo "  checkpoint                   # Interactive dashboard"
echo "  checkpoint --status          # Quick status view"
echo "  checkpoint --update          # Check for updates"
echo "  checkpoint --global          # Edit global settings"
echo "  checkpoint --project         # Configure this project"
echo ""
echo "  backup-now                   # Run backup immediately"
echo "  backup-status                # View status dashboard"
echo "  backup-restore               # Restore from backups"
echo "  backup-cleanup               # Clean old backups"
echo "  backup-cloud-config          # Configure cloud storage"
echo "  backup-update                # Update to latest version"
echo "  backup-pause                 # Pause/resume backups"
echo "  backup-uninstall             # Uninstall Checkpoint"
echo ""
echo "Try it now:"
echo "  /checkpoint"
echo "═══════════════════════════════════════════════════════════"
