#!/bin/bash
# ClaudeCode Project Backups - VS Code Integration Installer
# Installs tasks and keybindings for VS Code
# Version: 1.2.0

set -eo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}ClaudeCode Backup System - VS Code Integration Installer${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# ==============================================================================
# DETECT DIRECTORIES
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_TASKS="$SCRIPT_DIR/tasks.json"
TEMPLATE_KEYBINDINGS="$SCRIPT_DIR/keybindings.json"

# Target directory (current directory or specified)
TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "Backup system root: $BACKUP_ROOT"
echo "Target directory: $TARGET_DIR"
echo ""

# ==============================================================================
# CREATE .VSCODE DIRECTORY
# ==============================================================================

VSCODE_DIR="$TARGET_DIR/.vscode"
mkdir -p "$VSCODE_DIR"

echo -e "${GREEN}✅ Created/verified .vscode directory${NC}"
echo ""

# ==============================================================================
# INSTALL TASKS.JSON
# ==============================================================================

TASKS_FILE="$VSCODE_DIR/tasks.json"

echo "Installing tasks.json..."

if [[ -f "$TASKS_FILE" ]]; then
    echo -e "${YELLOW}⚠️  tasks.json already exists${NC}"

    # Check if it has backup tasks
    if grep -q "ClaudeCode.*Backup" "$TASKS_FILE" 2>/dev/null; then
        echo "   Existing tasks.json already has backup tasks"
        read -p "   Overwrite? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "   Skipping tasks.json"
        else
            backup_file="$TASKS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$TASKS_FILE" "$backup_file"
            echo -e "   ${GREEN}✅ Backed up to: $backup_file${NC}"

            cp "$TEMPLATE_TASKS" "$TASKS_FILE"
            echo -e "   ${GREEN}✅ Installed tasks.json${NC}"
        fi
    else
        echo "   Merging with existing tasks.json..."
        backup_file="$TASKS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$TASKS_FILE" "$backup_file"
        echo -e "   ${GREEN}✅ Backed up to: $backup_file${NC}"

        # Merge tasks (simplified - just append)
        echo -e "   ${YELLOW}⚠️  Manual merge required${NC}"
        echo "   Backup tasks saved to: $TEMPLATE_TASKS"
        echo "   Please manually merge tasks from template into $TASKS_FILE"
    fi
else
    cp "$TEMPLATE_TASKS" "$TASKS_FILE"
    echo -e "${GREEN}✅ Installed tasks.json${NC}"
fi

# Update CLAUDECODE_BACKUP_ROOT path in tasks.json
if [[ -f "$TASKS_FILE" ]] && grep -q "CLAUDECODE_BACKUP_ROOT" "$TASKS_FILE"; then
    echo ""
    echo -e "${YELLOW}⚠️  You need to set CLAUDECODE_BACKUP_ROOT environment variable${NC}"
    echo "   Add to your shell RC file (~/.bashrc or ~/.zshrc):"
    echo ""
    echo "   export CLAUDECODE_BACKUP_ROOT=\"$BACKUP_ROOT\""
    echo ""
    echo "   Or update tasks.json to use absolute paths instead of \${env:CLAUDECODE_BACKUP_ROOT}"
fi

echo ""

# ==============================================================================
# KEYBINDINGS INSTRUCTIONS
# ==============================================================================

echo -e "${BLUE}Keybindings Setup (Manual):${NC}"
echo ""
echo "VS Code keybindings are user-global, not per-project."
echo "To add backup keybindings:"
echo ""
echo "1. Open VS Code Command Palette (Ctrl+Shift+P or Cmd+Shift+P)"
echo "2. Type: 'Preferences: Open Keyboard Shortcuts (JSON)'"
echo "3. Add the contents of: $TEMPLATE_KEYBINDINGS"
echo ""
echo "Or copy them now:"
echo ""
cat "$TEMPLATE_KEYBINDINGS"
echo ""

# ==============================================================================
# SUCCESS MESSAGE
# ==============================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ VS Code integration setup complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "What's installed:"
echo "  • .vscode/tasks.json - Backup tasks"
echo ""
echo "Available tasks (Ctrl+Shift+P -> Tasks: Run Task):"
echo "  • Backup: Show Status"
echo "  • Backup: Trigger Now"
echo "  • Backup: Show Config"
echo "  • Backup: Cleanup (Preview)"
echo "  • Backup: List Backups"
echo ""
echo "Suggested keybindings (add manually):"
echo "  • Ctrl+Shift+B S - Show Status"
echo "  • Ctrl+Shift+B N - Backup Now"
echo "  • Ctrl+Shift+B C - Show Config"
echo "  • Ctrl+Shift+B L - Cleanup Preview"
echo "  • Ctrl+Shift+B R - List Backups"
echo ""
echo "Next steps:"
echo "  1. Set CLAUDECODE_BACKUP_ROOT environment variable"
echo "  2. Add keybindings (see above)"
echo "  3. Test: Ctrl+Shift+P -> 'Tasks: Run Task' -> 'Backup: Show Status'"
echo ""
echo "To uninstall:"
echo "  rm $VSCODE_DIR/tasks.json"
echo ""
