#!/bin/bash
# Checkpoint Project Backups - Git Hooks Installer
# Installs git hooks for automatic backup integration
# Version: 1.2.0

set -eo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Checkpoint Backup System - Git Hooks Installer${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# ==============================================================================
# DETECT GIT REPOSITORY
# ==============================================================================

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo -e "${RED}❌ Error: Not in a git repository${NC}" >&2
    echo "   Please run this from within a git repository" >&2
    exit 1
fi

GIT_DIR="$(git rev-parse --git-dir)"
HOOKS_DIR="$GIT_DIR/hooks"

echo "Git directory: $GIT_DIR"
echo "Hooks directory: $HOOKS_DIR"
echo ""

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_DIR"

# ==============================================================================
# DETECT SCRIPT LOCATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_HOOKS_DIR="$SCRIPT_DIR/hooks"

if [[ ! -d "$SOURCE_HOOKS_DIR" ]]; then
    echo -e "${RED}❌ Error: Hooks directory not found: $SOURCE_HOOKS_DIR${NC}" >&2
    exit 1
fi

# ==============================================================================
# INSTALL HOOKS
# ==============================================================================

HOOKS=("pre-commit" "post-commit" "pre-push")
INSTALLED=0
SKIPPED=0
BACKED_UP=0

for hook in "${HOOKS[@]}"; do
    source_hook="$SOURCE_HOOKS_DIR/$hook"
    target_hook="$HOOKS_DIR/$hook"

    echo -n "Installing $hook... "

    # Check if source hook exists
    if [[ ! -f "$source_hook" ]]; then
        echo -e "${RED}SKIP${NC} (source not found)"
        ((SKIPPED++))
        continue
    fi

    # Backup existing hook if present
    if [[ -f "$target_hook" ]]; then
        backup_file="$target_hook.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$target_hook" "$backup_file"
        echo -e "${YELLOW}BACKUP${NC} → $backup_file"
        ((BACKED_UP++))
    fi

    # Copy and make executable
    cp "$source_hook" "$target_hook"
    chmod +x "$target_hook"
    echo -e "${GREEN}✅ OK${NC}"
    ((INSTALLED++))
done

echo ""

# ==============================================================================
# CONFIGURATION OPTIONS
# ==============================================================================

echo -e "${BLUE}Configuration (optional):${NC}"
echo "You can customize hook behavior with environment variables in your shell RC file:"
echo ""
echo "  # Disable specific hooks"
echo "  export BACKUP_GIT_PRE_COMMIT_DISABLED=false    # Disable pre-commit backup"
echo "  export BACKUP_GIT_POST_COMMIT_DISABLED=false   # Disable post-commit status"
echo "  export BACKUP_GIT_PRE_PUSH_DISABLED=false      # Disable pre-push verification"
echo ""
echo "  # Quiet mode (suppress output)"
echo "  export BACKUP_GIT_QUIET=false                  # Disable all hook messages"
echo ""
echo "  # Failure handling"
echo "  export BACKUP_GIT_BLOCK_ON_FAILURE=false       # Block commits if backup fails"
echo "  export BACKUP_GIT_BLOCK_PUSH_ON_FAILURE=false  # Block pushes if backup fails"
echo ""
echo "  # Pre-push timing"
echo "  export BACKUP_GIT_MAX_BACKUP_AGE=3600          # Max age before auto-backup (seconds)"
echo ""

# ==============================================================================
# SUMMARY
# ==============================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Installation Summary${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Installed: $INSTALLED hooks"
echo "  Backed up: $BACKED_UP existing hooks"
echo "  Skipped: $SKIPPED hooks"
echo ""

if [[ $INSTALLED -gt 0 ]]; then
    echo -e "${GREEN}✅ Git hooks installed successfully!${NC}"
    echo ""
    echo "What happens now:"
    echo "  • pre-commit: Auto-backup before each commit"
    echo "  • post-commit: Show backup status after commit"
    echo "  • pre-push: Verify backup is current before push"
    echo ""
    echo "Test it:"
    echo "  git commit -m 'Test backup integration'"
    echo ""
else
    echo -e "${YELLOW}⚠️  No hooks were installed${NC}"
fi

# ==============================================================================
# UNINSTALL INSTRUCTIONS
# ==============================================================================

echo "To uninstall:"
echo "  rm $HOOKS_DIR/{pre-commit,post-commit,pre-push}"
if [[ $BACKED_UP -gt 0 ]]; then
    echo "  # Restore backups:"
    echo "  ls -la $HOOKS_DIR/*.backup.*"
fi
echo ""
