#!/usr/bin/env bash
# Checkpoint - Integration Wizard Installer
# Version: 1.2.0
# Detects available platforms and installs selected integrations

set -eo pipefail

# ==============================================================================
# COLORS AND FORMATTING
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INTEGRATIONS_DIR="$PROJECT_ROOT/integrations"

# Mode flags
AUTO_MODE=false
QUIET_MODE=false
SHOW_HELP=false

# Platform availability flags (bash 3.2 compatible)
PLATFORM_AVAILABLE_shell=0
PLATFORM_AVAILABLE_git=0
PLATFORM_AVAILABLE_tmux=0
PLATFORM_AVAILABLE_direnv=0
PLATFORM_AVAILABLE_vscode=0
PLATFORM_AVAILABLE_vim=0

# Platform selection flags
PLATFORM_SELECTED_shell=0
PLATFORM_SELECTED_git=0
PLATFORM_SELECTED_tmux=0
PLATFORM_SELECTED_direnv=0
PLATFORM_SELECTED_vscode=0
PLATFORM_SELECTED_vim=0

# Platform installation status
PLATFORM_INSTALLED_shell=0
PLATFORM_INSTALLED_git=0
PLATFORM_INSTALLED_tmux=0
PLATFORM_INSTALLED_direnv=0
PLATFORM_INSTALLED_vscode=0
PLATFORM_INSTALLED_vim=0

# ==============================================================================
# HELP TEXT
# ==============================================================================

show_help() {
    cat << 'EOF'
Checkpoint Backup System - Integration Installer

USAGE:
    install-integrations.sh [OPTIONS]

OPTIONS:
    --auto              Auto-install all available integrations (non-interactive)
    --quiet             Suppress non-essential output
    --help              Show this help message

DESCRIPTION:
    Interactive wizard that:
    1. Detects available platforms (shell, git, tmux, direnv, VS Code, Vim)
    2. Presents selection menu
    3. Installs selected integrations
    4. Verifies installation success

INTERACTIVE MODE (default):
    Presents menu to select which integrations to install.
    Recommended for first-time setup.

AUTO MODE (--auto):
    Automatically installs all available integrations.
    Useful for scripted/automated setups.

EXAMPLES:
    # Interactive installation (recommended)
    ./bin/install-integrations.sh

    # Auto-install everything available
    ./bin/install-integrations.sh --auto

    # Quiet auto-install
    ./bin/install-integrations.sh --auto --quiet

INTEGRATIONS:
    • Shell Integration       - bash/zsh prompt, aliases, auto-trigger on cd
    • Git Hooks              - Auto-backup on commit/push
    • Tmux Integration       - Status in tmux status bar
    • Direnv Integration     - Auto-trigger on directory changes
    • VS Code Extension      - Commands, status bar, auto-save trigger
    • Vim/Neovim Plugin      - Commands, mappings, auto-trigger on save

SEE ALSO:
    docs/INTEGRATIONS.md              - User guide for all integrations
    docs/INTEGRATION-DEVELOPMENT.md   - Developer guide for creating integrations

EOF
}

# ==============================================================================
# PLATFORM DETECTION
# ==============================================================================

detect_shell() {
    # Check for bash/zsh
    if command -v bash &>/dev/null || command -v zsh &>/dev/null; then
        if [[ -n "$BASH_VERSION" ]] || [[ -n "$ZSH_VERSION" ]]; then
            return 0
        fi
        # Check if shell RC files exist
        if [[ -f "$HOME/.bashrc" ]] || [[ -f "$HOME/.bash_profile" ]] || [[ -f "$HOME/.zshrc" ]]; then
            return 0
        fi
    fi
    return 1
}

detect_git() {
    # Check if git is installed
    command -v git &>/dev/null
}

detect_tmux() {
    # Check if tmux is installed
    command -v tmux &>/dev/null
}

detect_direnv() {
    # Check if direnv is installed
    command -v direnv &>/dev/null
}

detect_vscode() {
    # Check if VS Code is installed (code command available)
    if command -v code &>/dev/null; then
        return 0
    fi

    # Check common VS Code installation paths
    if [[ -d "/Applications/Visual Studio Code.app" ]] || \
       [[ -d "$HOME/Applications/Visual Studio Code.app" ]] || \
       [[ -d "$HOME/.vscode" ]]; then
        return 0
    fi

    return 1
}

detect_vim() {
    # Check if vim or neovim is installed
    if command -v vim &>/dev/null || command -v nvim &>/dev/null; then
        return 0
    fi

    # Check if vim directories exist
    if [[ -d "$HOME/.vim" ]] || [[ -d "$HOME/.config/nvim" ]]; then
        return 0
    fi

    return 1
}

detect_all_platforms() {
    echo -e "${BLUE}Detecting available platforms...${NC}"
    echo ""

    local detected=0

    if detect_shell; then
        PLATFORM_AVAILABLE_shell=1
        echo -e "  ${GREEN}✓${NC} Shell (bash/zsh)"
        ((detected++))
    else
        PLATFORM_AVAILABLE_shell=0
        echo -e "  ${YELLOW}✗${NC} Shell (bash/zsh not detected)"
    fi

    if detect_git; then
        PLATFORM_AVAILABLE_git=1
        echo -e "  ${GREEN}✓${NC} Git"
        ((detected++))
    else
        PLATFORM_AVAILABLE_git=0
        echo -e "  ${YELLOW}✗${NC} Git (not installed)"
    fi

    if detect_tmux; then
        PLATFORM_AVAILABLE_tmux=1
        echo -e "  ${GREEN}✓${NC} Tmux"
        ((detected++))
    else
        PLATFORM_AVAILABLE_tmux=0
        echo -e "  ${YELLOW}✗${NC} Tmux (not installed)"
    fi

    if detect_direnv; then
        PLATFORM_AVAILABLE_direnv=1
        echo -e "  ${GREEN}✓${NC} Direnv"
        ((detected++))
    else
        PLATFORM_AVAILABLE_direnv=0
        echo -e "  ${YELLOW}✗${NC} Direnv (not installed)"
    fi

    if detect_vscode; then
        PLATFORM_AVAILABLE_vscode=1
        echo -e "  ${GREEN}✓${NC} VS Code"
        ((detected++))
    else
        PLATFORM_AVAILABLE_vscode=0
        echo -e "  ${YELLOW}✗${NC} VS Code (not installed)"
    fi

    if detect_vim; then
        PLATFORM_AVAILABLE_vim=1
        echo -e "  ${GREEN}✓${NC} Vim/Neovim"
        ((detected++))
    else
        PLATFORM_AVAILABLE_vim=0
        echo -e "  ${YELLOW}✗${NC} Vim/Neovim (not installed)"
    fi

    echo ""
    echo -e "${CYAN}Found $detected available platform(s)${NC}"
    echo ""

    if [[ $detected -eq 0 ]]; then
        echo -e "${RED}❌ No compatible platforms detected${NC}"
        echo "   Please install at least one of: bash, zsh, git, tmux, direnv, VS Code, Vim/Neovim"
        exit 1
    fi
}

# ==============================================================================
# INTERACTIVE MENU
# ==============================================================================

show_interactive_menu() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}Checkpoint Backup System - Integration Installer${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Select which integrations to install:"
    echo ""

    local index=1
    # Menu mapping using space-separated string (bash 3.2 compatible)
    local menu_items=""

    if [[ $PLATFORM_AVAILABLE_shell -eq 1 ]]; then
        echo "  ${index}) Shell Integration (bash/zsh)"
        echo "     → Prompt status, aliases, auto-trigger on cd"
        menu_items="$menu_items ${index}:shell"
        ((index++))
    fi

    if [[ $PLATFORM_AVAILABLE_git -eq 1 ]]; then
        echo "  ${index}) Git Hooks"
        echo "     → Auto-backup on commit, pre-push verification"
        menu_items="$menu_items ${index}:git"
        ((index++))
    fi

    if [[ $PLATFORM_AVAILABLE_tmux -eq 1 ]]; then
        echo "  ${index}) Tmux Integration"
        echo "     → Backup status in tmux status bar"
        menu_items="$menu_items ${index}:tmux"
        ((index++))
    fi

    if [[ $PLATFORM_AVAILABLE_direnv -eq 1 ]]; then
        echo "  ${index}) Direnv Integration"
        echo "     → Auto-trigger on directory changes"
        menu_items="$menu_items ${index}:direnv"
        ((index++))
    fi

    if [[ $PLATFORM_AVAILABLE_vscode -eq 1 ]]; then
        echo "  ${index}) VS Code Extension"
        echo "     → Commands, status bar, auto-save trigger"
        menu_items="$menu_items ${index}:vscode"
        ((index++))
    fi

    if [[ $PLATFORM_AVAILABLE_vim -eq 1 ]]; then
        echo "  ${index}) Vim/Neovim Plugin"
        echo "     → Commands, mappings, auto-trigger on save"
        menu_items="$menu_items ${index}:vim"
        ((index++))
    fi

    echo ""
    echo "  a) Install all available"
    echo "  q) Quit"
    echo ""

    while true; do
        read -p "Select options (space-separated numbers, 'a' for all, 'q' to quit): " -r choices

        if [[ "$choices" == "q" ]] || [[ "$choices" == "Q" ]]; then
            echo "Installation cancelled"
            exit 0
        fi

        if [[ "$choices" == "a" ]] || [[ "$choices" == "A" ]]; then
            # Select all available platforms
            [[ $PLATFORM_AVAILABLE_shell -eq 1 ]] && PLATFORM_SELECTED_shell=1
            [[ $PLATFORM_AVAILABLE_git -eq 1 ]] && PLATFORM_SELECTED_git=1
            [[ $PLATFORM_AVAILABLE_tmux -eq 1 ]] && PLATFORM_SELECTED_tmux=1
            [[ $PLATFORM_AVAILABLE_direnv -eq 1 ]] && PLATFORM_SELECTED_direnv=1
            [[ $PLATFORM_AVAILABLE_vscode -eq 1 ]] && PLATFORM_SELECTED_vscode=1
            [[ $PLATFORM_AVAILABLE_vim -eq 1 ]] && PLATFORM_SELECTED_vim=1
            break
        fi

        # Parse space-separated choices
        local valid=true
        for choice in $choices; do
            # Check if choice exists in menu_items
            local found=false
            for item in $menu_items; do
                if [[ "$item" == "${choice}:"* ]]; then
                    found=true
                    break
                fi
            done
            if ! $found; then
                echo -e "${RED}Invalid choice: $choice${NC}"
                valid=false
                break
            fi
        done

        if $valid; then
            # Mark selected platforms
            for choice in $choices; do
                for item in $menu_items; do
                    if [[ "$item" == "${choice}:shell" ]]; then
                        PLATFORM_SELECTED_shell=1
                    elif [[ "$item" == "${choice}:git" ]]; then
                        PLATFORM_SELECTED_git=1
                    elif [[ "$item" == "${choice}:tmux" ]]; then
                        PLATFORM_SELECTED_tmux=1
                    elif [[ "$item" == "${choice}:direnv" ]]; then
                        PLATFORM_SELECTED_direnv=1
                    elif [[ "$item" == "${choice}:vscode" ]]; then
                        PLATFORM_SELECTED_vscode=1
                    elif [[ "$item" == "${choice}:vim" ]]; then
                        PLATFORM_SELECTED_vim=1
                    fi
                done
            done
            break
        fi
    done

    echo ""
    echo -e "${CYAN}Selected integrations:${NC}"
    [[ $PLATFORM_SELECTED_shell -eq 1 ]] && echo -e "  ${GREEN}✓${NC} shell"
    [[ $PLATFORM_SELECTED_git -eq 1 ]] && echo -e "  ${GREEN}✓${NC} git"
    [[ $PLATFORM_SELECTED_tmux -eq 1 ]] && echo -e "  ${GREEN}✓${NC} tmux"
    [[ $PLATFORM_SELECTED_direnv -eq 1 ]] && echo -e "  ${GREEN}✓${NC} direnv"
    [[ $PLATFORM_SELECTED_vscode -eq 1 ]] && echo -e "  ${GREEN}✓${NC} vscode"
    [[ $PLATFORM_SELECTED_vim -eq 1 ]] && echo -e "  ${GREEN}✓${NC} vim"
    echo ""
}

# ==============================================================================
# INSTALLATION FUNCTIONS
# ==============================================================================

install_shell_integration() {
    echo -e "${BLUE}Installing Shell Integration...${NC}"

    local installer="$INTEGRATIONS_DIR/shell/install.sh"

    if [[ ! -f "$installer" ]]; then
        echo -e "${RED}❌ Installer not found: $installer${NC}"
        return 1
    fi

    # Run installer (it's interactive by default)
    if bash "$installer"; then
        PLATFORM_INSTALLED_shell=1
        echo -e "${GREEN}✅ Shell integration installed${NC}"
        return 0
    else
        echo -e "${RED}❌ Shell integration installation failed${NC}"
        return 1
    fi
}

install_git_integration() {
    echo -e "${BLUE}Installing Git Hooks...${NC}"

    # Check if we're in a git repository
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${YELLOW}⚠️  Not in a git repository. Git hooks install requires a git repo.${NC}"
        echo "   You can install git hooks later from within a git repository:"
        echo "   $INTEGRATIONS_DIR/git/install-git-hooks.sh"
        return 1
    fi

    local installer="$INTEGRATIONS_DIR/git/install-git-hooks.sh"

    if [[ ! -f "$installer" ]]; then
        echo -e "${RED}❌ Installer not found: $installer${NC}"
        return 1
    fi

    if bash "$installer"; then
        PLATFORM_INSTALLED_git=1
        echo -e "${GREEN}✅ Git hooks installed${NC}"
        return 0
    else
        echo -e "${RED}❌ Git hooks installation failed${NC}"
        return 1
    fi
}

install_tmux_integration() {
    echo -e "${BLUE}Installing Tmux Integration...${NC}"

    local integration_file="$INTEGRATIONS_DIR/tmux/backup-tmux-integration.sh"
    local tmux_conf="$HOME/.tmux.conf"

    if [[ ! -f "$integration_file" ]]; then
        echo -e "${RED}❌ Integration file not found: $integration_file${NC}"
        return 1
    fi

    # Backup tmux.conf if it exists
    if [[ -f "$tmux_conf" ]]; then
        local backup_file="$tmux_conf.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$tmux_conf" "$backup_file"
        echo -e "${GREEN}✅ Backed up $tmux_conf to $backup_file${NC}"
    fi

    # Check if already installed
    if [[ -f "$tmux_conf" ]] && grep -q "backup-tmux-integration.sh" "$tmux_conf"; then
        echo -e "${YELLOW}⚠️  Tmux integration already in $tmux_conf${NC}"
    else
        # Add to tmux.conf
        echo "" >> "$tmux_conf"
        echo "# Checkpoint Backup System - Tmux Integration" >> "$tmux_conf"
        echo "run-shell \"$integration_file\"" >> "$tmux_conf"
        echo -e "${GREEN}✅ Added integration to $tmux_conf${NC}"
    fi

    echo ""
    echo "Reload tmux configuration:"
    echo "  tmux source-file $tmux_conf"
    echo "Or restart tmux"

    PLATFORM_INSTALLED_tmux=1
    return 0
}

install_direnv_integration() {
    echo -e "${BLUE}Installing Direnv Integration...${NC}"

    local integration_file="$INTEGRATIONS_DIR/direnv/backup-direnv-integration.sh"
    local direnv_config="$HOME/.config/direnv/direnvrc"

    if [[ ! -f "$integration_file" ]]; then
        echo -e "${RED}❌ Integration file not found: $integration_file${NC}"
        return 1
    fi

    # Create direnv config directory
    mkdir -p "$(dirname "$direnv_config")"

    # Backup direnvrc if it exists
    if [[ -f "$direnv_config" ]]; then
        local backup_file="$direnv_config.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$direnv_config" "$backup_file"
        echo -e "${GREEN}✅ Backed up $direnv_config to $backup_file${NC}"
    fi

    # Check if already installed
    if [[ -f "$direnv_config" ]] && grep -q "backup-direnv-integration.sh" "$direnv_config"; then
        echo -e "${YELLOW}⚠️  Direnv integration already in $direnv_config${NC}"
    else
        # Add to direnvrc
        echo "" >> "$direnv_config"
        echo "# Checkpoint Backup System - Direnv Integration" >> "$direnv_config"
        echo "source \"$integration_file\"" >> "$direnv_config"
        echo -e "${GREEN}✅ Added integration to $direnv_config${NC}"
    fi

    PLATFORM_INSTALLED_direnv=1
    return 0
}

install_vscode_integration() {
    echo -e "${BLUE}Installing VS Code Extension...${NC}"

    local extension_dir="$INTEGRATIONS_DIR/vscode"

    if [[ ! -d "$extension_dir" ]]; then
        echo -e "${RED}❌ VS Code extension directory not found: $extension_dir${NC}"
        return 1
    fi

    echo ""
    echo "VS Code extension installation:"
    echo "  1. Open VS Code"
    echo "  2. Press Cmd+Shift+P (macOS) or Ctrl+Shift+P (Linux/Windows)"
    echo "  3. Type 'Extensions: Install from VSIX'"
    echo "  4. Navigate to: $extension_dir"
    echo "  5. Select the .vsix file"
    echo ""
    echo "Or install from command line:"
    echo "  code --install-extension $extension_dir/*.vsix"
    echo ""
    echo -e "${CYAN}Note: VS Code extension requires manual installation or building from source${NC}"
    echo "      See: $extension_dir/README.md"

    PLATFORM_INSTALLED_vscode=0
    return 1
}

install_vim_integration() {
    echo -e "${BLUE}Installing Vim/Neovim Plugin...${NC}"

    local plugin_dir="$INTEGRATIONS_DIR/vim"

    if [[ ! -d "$plugin_dir" ]]; then
        echo -e "${RED}❌ Vim plugin directory not found: $plugin_dir${NC}"
        return 1
    fi

    echo ""
    echo "Vim/Neovim plugin installation options:"
    echo ""
    echo "1) Using vim-plug (add to ~/.vimrc or ~/.config/nvim/init.vim):"
    echo "   Plug '$plugin_dir'"
    echo "   Then run: :PlugInstall"
    echo ""
    echo "2) Using Vundle:"
    echo "   Plugin '$plugin_dir'"
    echo "   Then run: :PluginInstall"
    echo ""
    echo "3) Using Pathogen:"
    echo "   ln -s $plugin_dir ~/.vim/bundle/backup"
    echo ""
    echo "4) Using native package manager:"
    echo "   mkdir -p ~/.vim/pack/plugins/start"
    echo "   ln -s $plugin_dir ~/.vim/pack/plugins/start/backup"
    echo ""
    echo "5) For Neovim:"
    echo "   mkdir -p ~/.local/share/nvim/site/pack/plugins/start"
    echo "   ln -s $plugin_dir ~/.local/share/nvim/site/pack/plugins/start/backup"
    echo ""
    echo "Configuration (add to your vimrc):"
    echo "   let g:backup_bin_path = '$SCRIPT_DIR'"
    echo ""
    echo -e "${CYAN}Note: Vim plugin requires manual configuration${NC}"
    echo "      See: $plugin_dir/README.md"

    PLATFORM_INSTALLED_vim=0
    return 1
}

# ==============================================================================
# INSTALLATION ORCHESTRATION
# ==============================================================================

install_selected_integrations() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}Installing Selected Integrations${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    local total=0
    local successful=0
    local failed=0
    local skipped=0

    # Count total selected
    [[ $PLATFORM_SELECTED_shell -eq 1 ]] && ((total++))
    [[ $PLATFORM_SELECTED_git -eq 1 ]] && ((total++))
    [[ $PLATFORM_SELECTED_tmux -eq 1 ]] && ((total++))
    [[ $PLATFORM_SELECTED_direnv -eq 1 ]] && ((total++))
    [[ $PLATFORM_SELECTED_vscode -eq 1 ]] && ((total++))
    [[ $PLATFORM_SELECTED_vim -eq 1 ]] && ((total++))

    if [[ $total -eq 0 ]]; then
        echo -e "${YELLOW}No integrations selected${NC}"
        return 0
    fi

    # Install each selected platform
    if [[ $PLATFORM_SELECTED_shell -eq 1 ]]; then
        if install_shell_integration; then
            ((successful++))
        else
            ((failed++))
        fi
        echo ""
    fi

    if [[ $PLATFORM_SELECTED_git -eq 1 ]]; then
        if install_git_integration; then
            ((successful++))
        else
            ((skipped++))
        fi
        echo ""
    fi

    if [[ $PLATFORM_SELECTED_tmux -eq 1 ]]; then
        if install_tmux_integration; then
            ((successful++))
        else
            ((failed++))
        fi
        echo ""
    fi

    if [[ $PLATFORM_SELECTED_direnv -eq 1 ]]; then
        if install_direnv_integration; then
            ((successful++))
        else
            ((failed++))
        fi
        echo ""
    fi

    if [[ $PLATFORM_SELECTED_vscode -eq 1 ]]; then
        if install_vscode_integration; then
            ((skipped++))
        else
            ((successful++))
        fi
        echo ""
    fi

    if [[ $PLATFORM_SELECTED_vim -eq 1 ]]; then
        if install_vim_integration; then
            ((skipped++))
        else
            ((successful++))
        fi
        echo ""
    fi

    # Summary
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}Installation Summary${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Total selected: $total"
    echo -e "  ${GREEN}Successful: $successful${NC}"
    if [[ $failed -gt 0 ]]; then
        echo -e "  ${RED}Failed: $failed${NC}"
    fi
    if [[ $skipped -gt 0 ]]; then
        echo -e "  ${YELLOW}Manual setup required: $skipped${NC}"
    fi
    echo ""

    if [[ $successful -gt 0 ]]; then
        echo -e "${GREEN}✅ Integration installation completed!${NC}"
        echo ""
        echo "Next steps:"

        if [[ $PLATFORM_INSTALLED_shell -eq 1 ]]; then
            echo "  • Reload your shell: source ~/.bashrc or source ~/.zshrc"
        fi

        if [[ $PLATFORM_INSTALLED_tmux -eq 1 ]]; then
            echo "  • Reload tmux: tmux source-file ~/.tmux.conf"
        fi

        echo ""
        echo "Documentation:"
        echo "  • User Guide: $PROJECT_ROOT/docs/INTEGRATIONS.md"
        echo "  • Developer Guide: $PROJECT_ROOT/docs/INTEGRATION-DEVELOPMENT.md"
        echo ""
        echo "Test your integrations:"
        echo "  backup status"
        echo "  bs              # Quick alias (shell integration)"
        echo ""
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --quiet)
                QUIET_MODE=true
                shift
                ;;
            --help|-h)
                SHOW_HELP=true
                shift
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done

    # Show help if requested
    if $SHOW_HELP; then
        show_help
        exit 0
    fi

    # Header
    if ! $QUIET_MODE; then
        echo ""
    fi

    # Detect platforms
    detect_all_platforms

    # Auto mode or interactive mode
    if $AUTO_MODE; then
        echo -e "${CYAN}Auto-install mode: Installing all available integrations${NC}"
        echo ""

        # Select all available platforms
        [[ $PLATFORM_AVAILABLE_shell -eq 1 ]] && PLATFORM_SELECTED_shell=1
        [[ $PLATFORM_AVAILABLE_git -eq 1 ]] && PLATFORM_SELECTED_git=1
        [[ $PLATFORM_AVAILABLE_tmux -eq 1 ]] && PLATFORM_SELECTED_tmux=1
        [[ $PLATFORM_AVAILABLE_direnv -eq 1 ]] && PLATFORM_SELECTED_direnv=1
        [[ $PLATFORM_AVAILABLE_vscode -eq 1 ]] && PLATFORM_SELECTED_vscode=1
        [[ $PLATFORM_AVAILABLE_vim -eq 1 ]] && PLATFORM_SELECTED_vim=1
    else
        # Interactive menu
        show_interactive_menu
    fi

    # Install selected integrations
    install_selected_integrations
}

# Run main
main "$@"
