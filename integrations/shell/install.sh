#!/bin/bash
# Checkpoint Project Backups - Shell Integration Installer
# Installs shell integration for bash/zsh

set -eo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Checkpoint Backup System - Shell Integration Installer${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Detect script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_FILE="$SCRIPT_DIR/backup-shell-integration.sh"

# Detect shell
detect_shell() {
    if [[ -n "$ZSH_VERSION" ]]; then
        echo "zsh"
    elif [[ -n "$BASH_VERSION" ]]; then
        echo "bash"
    else
        echo "unknown"
    fi
}

# Get shell RC file
get_rc_file() {
    local shell_type=$(detect_shell)

    case "$shell_type" in
        zsh)
            echo "$HOME/.zshrc"
            ;;
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                echo "$HOME/.bashrc"
            else
                echo "$HOME/.bash_profile"
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# Main installation
main() {
    local shell_type=$(detect_shell)
    local rc_file=$(get_rc_file)

    echo "Detected shell: $shell_type"
    echo "Shell RC file: $rc_file"
    echo ""

    # Check if already installed
    if [[ -f "$rc_file" ]] && grep -q "backup-shell-integration.sh" "$rc_file"; then
        echo -e "${YELLOW}⚠️  Shell integration already installed${NC}"
        echo ""
        read -p "Reinstall anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled"
            exit 0
        fi
    fi

    # Backup RC file
    if [[ -f "$rc_file" ]]; then
        local backup_file="$rc_file.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$rc_file" "$backup_file"
        echo -e "${GREEN}✅ Backed up $rc_file to $backup_file${NC}"
    fi

    # Add source line to RC file
    echo ""  >> "$rc_file"
    echo "# Checkpoint Backup System - Shell Integration"  >> "$rc_file"
    echo "source \"$INTEGRATION_FILE\""  >> "$rc_file"

    echo -e "${GREEN}✅ Added integration to $rc_file${NC}"
    echo ""

    # Configuration options
    echo -e "${BLUE}Configuration (optional):${NC}"
    echo "You can customize by adding these BEFORE the source line in $rc_file:"
    echo ""
    echo "  export BACKUP_AUTO_TRIGGER=true          # Auto-backup on cd (default: true)"
    echo "  export BACKUP_SHOW_PROMPT=true           # Show in prompt (default: true)"
    echo "  export BACKUP_TRIGGER_INTERVAL=300       # Debounce seconds (default: 300)"
    echo "  export BACKUP_PROMPT_FORMAT=emoji        # emoji|compact|verbose (default: emoji)"
    echo "  export BACKUP_ALIASES_ENABLED=true       # Enable aliases (default: true)"
    echo ""

    # Success
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Shell integration installed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Reload your shell:"
    echo "     source $rc_file"
    echo ""
    echo "  2. Try the commands:"
    echo "     backup status"
    echo "     backup help"
    echo "     bs              # Quick alias"
    echo ""
    echo "  3. Your prompt now shows backup status: $(source "$INTEGRATION_FILE" && backup_prompt_status)"
    echo ""
}

# Run main
main
