#!/usr/bin/env bash
# Checkpoint - Install Skills
# Sets up /checkpoint skill for Claude Code

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

echo "Installing Checkpoint skill for Claude Code..."
echo ""

# Create skills directory
mkdir -p "$SKILLS_DIR"

# ==============================================================================
# Install /checkpoint skill
# ==============================================================================

if [[ -d "$PROJECT_ROOT/.claude/skills/checkpoint" ]]; then
    echo "📦 Installing /checkpoint skill..."

    # If installing to a different project, copy the skill
    if [[ "$PROJECT_ROOT/.claude/skills" != "$SKILLS_DIR" ]]; then
        cp -r "$PROJECT_ROOT/.claude/skills/checkpoint" "$SKILLS_DIR/"
    fi

    chmod +x "$SKILLS_DIR/checkpoint/run.sh"
    echo "   ✅ /checkpoint skill installed"
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
