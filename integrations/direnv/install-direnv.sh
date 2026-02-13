#!/bin/bash
# Checkpoint Project Backups - Direnv Integration Installer
# Sets up direnv for automatic per-project backup configuration
# Version: 1.2.0

set -eo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Checkpoint Backup System - Direnv Installer${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# ==============================================================================
# CHECK DIRENV INSTALLATION
# ==============================================================================

if ! command -v direnv &>/dev/null; then
    echo -e "${RED}❌ Error: direnv not found${NC}" >&2
    echo "" >&2
    echo "Please install direnv first:" >&2
    echo "" >&2
    echo "  macOS:   brew install direnv" >&2
    echo "  Ubuntu:  apt install direnv" >&2
    echo "  Generic: See https://direnv.net/docs/installation.html" >&2
    echo "" >&2
    echo "Then configure your shell:" >&2
    echo "" >&2
    echo "  bash:    echo 'eval \"\$(direnv hook bash)\"' >> ~/.bashrc" >&2
    echo "  zsh:     echo 'eval \"\$(direnv hook zsh)\"' >> ~/.zshrc" >&2
    echo "" >&2
    exit 1
fi

echo -e "${GREEN}✅ direnv found: $(command -v direnv)${NC}"
echo ""

# ==============================================================================
# DETECT DIRECTORIES
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/.envrc"

# Target directory (current directory or specified)
TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "Backup system root: $BACKUP_ROOT"
echo "Target directory: $TARGET_DIR"
echo ""

# ==============================================================================
# CHECK EXISTING .ENVRC
# ==============================================================================

ENVRC_FILE="$TARGET_DIR/.envrc"

if [[ -f "$ENVRC_FILE" ]]; then
    echo -e "${YELLOW}⚠️  .envrc already exists in target directory${NC}"
    echo ""

    # Check if it already has backup integration
    if grep -q "CLAUDECODE_BACKUP" "$ENVRC_FILE" 2>/dev/null; then
        echo "The existing .envrc appears to have Checkpoint Backup integration."
        echo ""
        read -p "Overwrite anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled"
            exit 0
        fi
    else
        echo "Backing up existing .envrc..."
        backup_file="$ENVRC_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ENVRC_FILE" "$backup_file"
        echo -e "${GREEN}✅ Backed up to: $backup_file${NC}"
        echo ""

        read -p "Append backup integration to existing .envrc? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo "Installation cancelled"
            exit 0
        fi

        # Append mode
        echo "" >> "$ENVRC_FILE"
        echo "# === Checkpoint Backup System Integration ===" >> "$ENVRC_FILE"
        cat "$TEMPLATE_FILE" >> "$ENVRC_FILE"

        # Update the path in the appended content
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|export CLAUDECODE_BACKUP_ROOT=.*|export CLAUDECODE_BACKUP_ROOT=\"$BACKUP_ROOT\"|" "$ENVRC_FILE"
        else
            sed -i "s|export CLAUDECODE_BACKUP_ROOT=.*|export CLAUDECODE_BACKUP_ROOT=\"$BACKUP_ROOT\"|" "$ENVRC_FILE"
        fi

        echo -e "${GREEN}✅ Appended backup integration to existing .envrc${NC}"
        APPEND_MODE=true
    fi
fi

# ==============================================================================
# INSTALL .ENVRC (IF NOT APPEND MODE)
# ==============================================================================

if [[ "${APPEND_MODE:-false}" != "true" ]]; then
    # Copy template
    cp "$TEMPLATE_FILE" "$ENVRC_FILE"
    echo -e "${GREEN}✅ Created .envrc in $TARGET_DIR${NC}"

    # Update the path to backup system
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS sed requires empty string after -i
        sed -i '' "s|export CLAUDECODE_BACKUP_ROOT=.*|export CLAUDECODE_BACKUP_ROOT=\"$BACKUP_ROOT\"|" "$ENVRC_FILE"
    else
        sed -i "s|export CLAUDECODE_BACKUP_ROOT=.*|export CLAUDECODE_BACKUP_ROOT=\"$BACKUP_ROOT\"|" "$ENVRC_FILE"
    fi

    echo -e "${GREEN}✅ Updated backup root path in .envrc${NC}"
fi

echo ""

# ==============================================================================
# ALLOW DIRENV
# ==============================================================================

echo "Allowing direnv for this directory..."
cd "$TARGET_DIR"
if direnv allow; then
    echo -e "${GREEN}✅ direnv allowed${NC}"
else
    echo -e "${YELLOW}⚠️  direnv allow failed - you may need to run manually:${NC}"
    echo "   cd $TARGET_DIR && direnv allow"
fi

echo ""

# ==============================================================================
# SUCCESS MESSAGE
# ==============================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Direnv integration installed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "What happens now:"
echo "  • When you cd into $TARGET_DIR,"
echo "    direnv will automatically:"
echo "    - Add backup commands to PATH"
echo "    - Load backup configuration"
echo "    - Enable quick aliases (bs, bn, etc.)"
echo ""
echo "Next steps:"
echo ""
echo "  1. Exit and re-enter the directory to trigger direnv:"
echo "     cd .. && cd $TARGET_DIR"
echo ""
echo "  2. Test the commands:"
echo "     backup status"
echo "     bs                  # Quick alias"
echo ""
echo "  3. Customize .envrc to your needs:"
echo "     nano $ENVRC_FILE"
echo ""
echo "Configuration tips:"
echo "  • Edit BACKUP_PROMPT_FORMAT for different status displays"
echo "  • Set BACKUP_AUTO_TRIGGER=false to disable auto-backups"
echo "  • Uncomment shell integration source line for full features"
echo ""
echo "To uninstall:"
echo "  rm $ENVRC_FILE"
echo ""
