#!/bin/bash
# ==============================================================================
# Checkpoint - Dependency Manager
# ==============================================================================
# Version: 2.1.0
# Description: Progressive dependency installation with user consent
#
# Usage:
#   source lib/dependency-manager.sh
#   require_rclone || exit 1
# ==============================================================================

# Check if rclone is installed
# Returns: 0 if installed, 1 if not
check_rclone() {
    command -v rclone &>/dev/null
}

# Install rclone with user consent
# Returns: 0 if installed successfully, 1 if failed or user declined
install_rclone() {
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "rclone Installation Required"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "Cloud backup requires rclone:"
    echo "  • Free, open-source tool (MIT license)"
    echo "  • Supports 40+ cloud providers"
    echo "  • Size: ~50MB"
    echo "  • Homepage: https://rclone.org"
    echo ""

    read -p "Install rclone now? (y/n) [y]: " install_choice
    install_choice=${install_choice:-y}

    if [[ ! "$install_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "⊘ rclone installation skipped"
        echo ""
        echo "To install manually:"
        if [[ "$(uname -s)" == "Darwin" ]]; then
            echo "  brew install rclone"
        else
            echo "  curl https://rclone.org/install.sh | sudo bash"
        fi
        echo ""
        return 1
    fi

    echo ""
    echo "Installing rclone..."

    # Determine installation method
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS
        if command -v brew &>/dev/null; then
            echo "Using Homebrew..."
            if brew install rclone; then
                echo "✅ rclone installed via Homebrew"
                return 0
            else
                echo "❌ Homebrew installation failed"
                return 1
            fi
        else
            echo "Homebrew not found, using official install script..."
            if curl https://rclone.org/install.sh | bash; then
                echo "✅ rclone installed"
                return 0
            else
                echo "❌ Installation failed"
                return 1
            fi
        fi
    else
        # Linux
        echo "Using official install script..."
        if curl https://rclone.org/install.sh | sudo bash; then
            echo "✅ rclone installed"
            return 0
        else
            echo "❌ Installation failed"
            return 1
        fi
    fi
}

# Require rclone (check, prompt to install if missing)
# Returns: 0 if available (installed or already present), 1 if not available
require_rclone() {
    # Already installed
    if check_rclone; then
        return 0
    fi

    # Not installed, prompt to install
    if install_rclone; then
        # Verify installation succeeded
        if check_rclone; then
            return 0
        else
            echo "❌ rclone installation verification failed"
            return 1
        fi
    else
        # User declined or installation failed
        return 1
    fi
}
