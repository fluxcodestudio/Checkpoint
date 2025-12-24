#!/bin/bash
# Checkpoint Project Backups - Tmux Integration Installer
# Installs tmux status bar and keybinding integration
# Version: 1.2.0

set -eo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Checkpoint Backup System - Tmux Integration Installer${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# ==============================================================================
# CHECK TMUX INSTALLATION
# ==============================================================================

if ! command -v tmux &>/dev/null; then
    echo -e "${RED}❌ Error: tmux not found${NC}" >&2
    echo "" >&2
    echo "Please install tmux first:" >&2
    echo "" >&2
    echo "  macOS:   brew install tmux" >&2
    echo "  Ubuntu:  apt install tmux" >&2
    echo "  CentOS:  yum install tmux" >&2
    echo "" >&2
    exit 1
fi

echo -e "${GREEN}✅ tmux found: $(command -v tmux)${NC}"
echo "   Version: $(tmux -V)"
echo ""

# ==============================================================================
# DETECT DIRECTORIES
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/backup-tmux.conf"
STATUS_SCRIPT="$SCRIPT_DIR/backup-tmux-status.sh"

# Make status script executable
chmod +x "$STATUS_SCRIPT"

echo "Backup system root: $BACKUP_ROOT"
echo "Tmux config template: $TEMPLATE_FILE"
echo "Status script: $STATUS_SCRIPT"
echo ""

# ==============================================================================
# CHECK EXISTING TMUX CONF
# ==============================================================================

TMUX_CONF="${HOME}/.tmux.conf"

if [[ ! -f "$TMUX_CONF" ]]; then
    echo "Creating new ~/.tmux.conf"
    touch "$TMUX_CONF"
fi

# Check if already integrated
if grep -q "Checkpoint.*Backup.*Tmux" "$TMUX_CONF" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Tmux backup integration already exists${NC}"
    echo ""
    read -p "Reinstall/update anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi

    # Remove old integration
    echo "Removing old integration..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' '/# Checkpoint.*Backup.*Tmux/,/^$/d' "$TMUX_CONF"
    else
        sed -i '/# Checkpoint.*Backup.*Tmux/,/^$/d' "$TMUX_CONF"
    fi
fi

# Backup existing tmux.conf
BACKUP_FILE="$TMUX_CONF.backup.$(date +%Y%m%d_%H%M%S)"
cp "$TMUX_CONF" "$BACKUP_FILE"
echo -e "${GREEN}✅ Backed up tmux.conf to: $BACKUP_FILE${NC}"
echo ""

# ==============================================================================
# INSTALL CONFIGURATION
# ==============================================================================

echo "Installing tmux integration..."

# Add integration to tmux.conf
{
    echo ""
    echo "# Checkpoint Project Backups - Tmux Integration"
    echo "# Installed: $(date)"
    echo ""

    # Read template and update paths
    while IFS= read -r line; do
        # Update the backup-status-script path
        if [[ "$line" == *'set-option -g @backup-status-script'* ]]; then
            echo "set-option -g @backup-status-script \"$STATUS_SCRIPT\""
        else
            echo "$line"
        fi
    done < "$TEMPLATE_FILE"

} >> "$TMUX_CONF"

echo -e "${GREEN}✅ Added configuration to ~/.tmux.conf${NC}"
echo ""

# ==============================================================================
# RELOAD TMUX
# ==============================================================================

echo "Reloading tmux configuration..."

if tmux info &>/dev/null; then
    # Tmux is running, reload config
    if tmux source-file "$TMUX_CONF"; then
        echo -e "${GREEN}✅ Tmux configuration reloaded${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not reload tmux config${NC}"
        echo "   Run manually: tmux source-file ~/.tmux.conf"
    fi
else
    echo -e "${YELLOW}⚠️  Tmux not running - config will load on next start${NC}"
fi

echo ""

# ==============================================================================
# SUCCESS MESSAGE
# ==============================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Tmux integration installed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "What's installed:"
echo "  • Status bar shows backup status (refreshes every 60s)"
echo "  • Keybindings for backup commands"
echo ""
echo "Status bar formats (set in ~/.tmux.conf):"
echo "  • emoji     - Just emoji: ✅"
echo "  • compact   - Emoji + time: ✅ 2h"
echo "  • verbose   - Full status: ✅ All backups current"
echo ""
echo "Default keybindings (prefix is usually Ctrl-b):"
echo "  • prefix + s - Show backup status"
echo "  • prefix + n - Backup now"
echo "  • prefix + c - Show config"
echo "  • prefix + l - Cleanup preview"
echo "  • prefix + r - List backups"
echo ""
echo "Customization:"
echo "  1. Edit ~/.tmux.conf to change:"
echo "     - Status format (@backup-status-format)"
echo "     - Refresh interval (status-interval)"
echo "     - Keybindings (bind-key)"
echo "     - Status bar position (status-right/status-left)"
echo ""
echo "  2. Reload tmux config:"
echo "     tmux source-file ~/.tmux.conf"
echo ""
echo "Test it:"
echo "  1. Look at your tmux status bar (should show ✅ or ⚠️ or ❌)"
echo "  2. Try keybindings: Ctrl-b then s (show status)"
echo ""
echo "To uninstall:"
echo "  1. Edit ~/.tmux.conf and remove Checkpoint Backup section"
echo "  2. Reload: tmux source-file ~/.tmux.conf"
echo ""
