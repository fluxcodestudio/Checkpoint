#!/bin/bash
# ==============================================================================
# Checkpoint - Dependency Manager
# ==============================================================================
# Version: 2.2.0
# Description: Progressive dependency installation with user consent
#
# Usage:
#   source lib/dependency-manager.sh
#   require_rclone || exit 1
#   require_postgres_tools || exit 1
#   require_dialog || exit 1
# ==============================================================================

# ==============================================================================
# BASH VERSION CHECK (for TUI features)
# ==============================================================================

# Check if bash version is 4.0 or higher
# Returns: 0 if >= 4.0, 1 if < 4.0
check_bash_version() {
    local bash_version
    bash_version=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local major_version="${bash_version%%.*}"

    [[ "$major_version" -ge 4 ]]
}

# Get current bash version
get_bash_version() {
    bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Install modern bash with user consent
# Returns: 0 if installed successfully, 1 if failed or user declined
install_bash() {
    local current_version
    current_version=$(get_bash_version)

    echo ""
    echo "═══════════════════════════════════════════════"
    echo "Bash Upgrade Recommended"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "Current bash version: $current_version (macOS default)"
    echo "Recommended: bash 4.0+ for full TUI dashboard features"
    echo ""
    echo "Upgrading bash will:"
    echo "  • Enable interactive TUI menus with dialog"
    echo "  • Provide enhanced command center experience"
    echo "  • Install bash 5.2+ via Homebrew"
    echo "  • Size: ~2MB"
    echo ""
    echo "Note: The dashboard still works with bash 3.2 using text menus"
    echo ""

    read -p "Upgrade bash now? (y/N) [N]: " install_choice
    install_choice=${install_choice:-n}

    if [[ ! "$install_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "⊘ Bash upgrade skipped"
        echo "  Dashboard will use text-based menus (fully functional)"
        echo ""
        echo "To upgrade manually later:"
        echo "  brew install bash"
        echo "  sudo bash -c 'echo /usr/local/bin/bash >> /etc/shells'"
        echo "  chsh -s /usr/local/bin/bash"
        echo ""
        return 1
    fi

    echo ""
    echo "Installing bash..."

    if [[ "$(uname -s)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            echo "Using Homebrew..."
            if brew install bash; then
                echo "✅ bash installed successfully"
                echo ""
                echo "To make it your default shell:"
                echo "  sudo bash -c 'echo /usr/local/bin/bash >> /etc/shells'"
                echo "  chsh -s /usr/local/bin/bash"
                echo "  # Then restart your terminal"
                echo ""
                return 0
            else
                echo "❌ Installation failed"
                return 1
            fi
        else
            echo "❌ Homebrew required for bash installation"
            echo "Install Homebrew: https://brew.sh"
            return 1
        fi
    else
        echo "Bash upgrade on Linux:"
        if command -v apt-get &>/dev/null; then
            sudo apt-get install -y bash
        elif command -v yum &>/dev/null; then
            sudo yum install -y bash
        fi
        return $?
    fi
}

# Require bash 4.0+ (check, prompt to upgrade if missing)
# Returns: 0 if >= 4.0 or user declined (non-blocking), 1 only on critical error
require_bash() {
    if check_bash_version; then
        return 0
    fi

    # Offer upgrade but don't block installation
    install_bash || return 0  # Return success even if user declines
}

# ==============================================================================
# DIALOG/WHIPTAIL (for TUI dashboard)
# ==============================================================================

# Check if dialog or whiptail is installed
# Returns: 0 if installed, 1 if not
check_dialog() {
    command -v dialog &>/dev/null || command -v whiptail &>/dev/null
}

# Install dialog with user consent
# Returns: 0 if installed successfully, 1 if failed or user declined
install_dialog() {
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "Enhanced Dashboard Experience"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "For the best dashboard experience, install dialog:"
    echo "  • Creates beautiful TUI menus (like Superstack)"
    echo "  • Free, open-source tool"
    echo "  • Size: ~500KB"
    echo "  • Optional: Dashboard works without it"
    echo ""

    read -p "Install dialog for better UX? (Y/n) [Y]: " install_choice
    install_choice=${install_choice:-y}

    if [[ ! "$install_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "⊘ dialog installation skipped"
        echo "  Dashboard will use simple text menus (still fully functional)"
        echo ""
        return 1
    fi

    echo ""
    echo "Installing dialog..."

    # Detect platform and install
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS
        if command -v brew &>/dev/null; then
            if brew install dialog 2>/dev/null; then
                echo "✓ dialog installed successfully"
                return 0
            else
                echo "✗ Failed to install dialog via Homebrew"
                return 1
            fi
        else
            echo "✗ Homebrew not found. Install dialog manually:"
            echo "  1. Install Homebrew: https://brew.sh"
            echo "  2. Run: brew install dialog"
            return 1
        fi
    elif [[ "$(uname -s)" == "Linux" ]]; then
        # Linux
        if command -v apt-get &>/dev/null; then
            if sudo apt-get install -y dialog 2>/dev/null; then
                echo "✓ dialog installed successfully"
                return 0
            fi
        elif command -v yum &>/dev/null; then
            if sudo yum install -y dialog 2>/dev/null; then
                echo "✓ dialog installed successfully"
                return 0
            fi
        elif command -v dnf &>/dev/null; then
            if sudo dnf install -y dialog 2>/dev/null; then
                echo "✓ dialog installed successfully"
                return 0
            fi
        fi

        echo "✗ Could not install dialog automatically"
        echo "  Install manually: sudo apt-get install dialog"
        return 1
    else
        echo "✗ Unsupported platform for automatic installation"
        return 1
    fi
}

# Require dialog (check and install if needed)
# Returns: 0 if available, 1 if not available and installation failed/declined
require_dialog() {
    if check_dialog; then
        return 0
    fi

    install_dialog
    return $?
}

# ==============================================================================
# RCLONE (for cloud backup)
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

# ==============================================================================
# POSTGRESQL TOOLS
# ==============================================================================

# Check if PostgreSQL client tools are installed
# Returns: 0 if installed, 1 if not
check_postgres_tools() {
    command -v pg_dump &>/dev/null && command -v pg_restore &>/dev/null
}

# Install PostgreSQL client tools with user consent
# Returns: 0 if installed successfully, 1 if failed or user declined
install_postgres_tools() {
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "PostgreSQL Tools Installation Required"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "PostgreSQL backup requires pg_dump:"
    echo "  • Part of PostgreSQL client tools"
    echo "  • Free, open-source (PostgreSQL license)"
    echo "  • Size: ~5MB"
    echo ""

    read -p "Install PostgreSQL tools now? (y/n) [y]: " install_choice
    install_choice=${install_choice:-y}

    if [[ ! "$install_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "⊘ PostgreSQL tools installation skipped"
        echo ""
        echo "To install manually:"
        if [[ "$(uname -s)" == "Darwin" ]]; then
            echo "  brew install libpq"
        else
            echo "  sudo apt-get install postgresql-client  # Debian/Ubuntu"
            echo "  sudo yum install postgresql  # RedHat/CentOS"
        fi
        echo ""
        return 1
    fi

    echo ""
    echo "Installing PostgreSQL tools..."

    if [[ "$(uname -s)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            echo "Using Homebrew..."
            if brew install libpq && brew link --force libpq; then
                echo "✅ PostgreSQL tools installed"
                return 0
            else
                echo "❌ Installation failed"
                return 1
            fi
        else
            echo "❌ Homebrew required for macOS installation"
            return 1
        fi
    else
        # Try apt-get first (Debian/Ubuntu)
        if command -v apt-get &>/dev/null; then
            if sudo apt-get install -y postgresql-client; then
                echo "✅ PostgreSQL tools installed"
                return 0
            fi
        # Try yum (RedHat/CentOS)
        elif command -v yum &>/dev/null; then
            if sudo yum install -y postgresql; then
                echo "✅ PostgreSQL tools installed"
                return 0
            fi
        fi
        echo "❌ Installation failed"
        return 1
    fi
}

# Require PostgreSQL tools (check, prompt to install if missing)
# Returns: 0 if available, 1 if not available
require_postgres_tools() {
    if check_postgres_tools; then
        return 0
    fi

    if install_postgres_tools; then
        if check_postgres_tools; then
            return 0
        else
            echo "❌ PostgreSQL tools installation verification failed"
            return 1
        fi
    else
        return 1
    fi
}

# ==============================================================================
# MYSQL TOOLS
# ==============================================================================

# Check if MySQL client tools are installed
# Returns: 0 if installed, 1 if not
check_mysql_tools() {
    command -v mysqldump &>/dev/null
}

# Install MySQL client tools with user consent
# Returns: 0 if installed successfully, 1 if failed or user declined
install_mysql_tools() {
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "MySQL Tools Installation Required"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "MySQL backup requires mysqldump:"
    echo "  • Part of MySQL client tools"
    echo "  • Free, open-source (GPL license)"
    echo "  • Size: ~10MB"
    echo ""

    read -p "Install MySQL tools now? (y/n) [y]: " install_choice
    install_choice=${install_choice:-y}

    if [[ ! "$install_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "⊘ MySQL tools installation skipped"
        echo ""
        echo "To install manually:"
        if [[ "$(uname -s)" == "Darwin" ]]; then
            echo "  brew install mysql-client"
        else
            echo "  sudo apt-get install mysql-client  # Debian/Ubuntu"
            echo "  sudo yum install mysql  # RedHat/CentOS"
        fi
        echo ""
        return 1
    fi

    echo ""
    echo "Installing MySQL tools..."

    if [[ "$(uname -s)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            echo "Using Homebrew..."
            if brew install mysql-client && brew link --force mysql-client; then
                echo "✅ MySQL tools installed"
                return 0
            else
                echo "❌ Installation failed"
                return 1
            fi
        else
            echo "❌ Homebrew required for macOS installation"
            return 1
        fi
    else
        if command -v apt-get &>/dev/null; then
            if sudo apt-get install -y mysql-client; then
                echo "✅ MySQL tools installed"
                return 0
            fi
        elif command -v yum &>/dev/null; then
            if sudo yum install -y mysql; then
                echo "✅ MySQL tools installed"
                return 0
            fi
        fi
        echo "❌ Installation failed"
        return 1
    fi
}

# Require MySQL tools (check, prompt to install if missing)
# Returns: 0 if available, 1 if not available
require_mysql_tools() {
    if check_mysql_tools; then
        return 0
    fi

    if install_mysql_tools; then
        if check_mysql_tools; then
            return 0
        else
            echo "❌ MySQL tools installation verification failed"
            return 1
        fi
    else
        return 1
    fi
}

# ==============================================================================
# MONGODB TOOLS
# ==============================================================================

# Check if MongoDB tools are installed
# Returns: 0 if installed, 1 if not
check_mongodb_tools() {
    command -v mongodump &>/dev/null && command -v mongorestore &>/dev/null
}

# Install MongoDB tools with user consent
# Returns: 0 if installed successfully, 1 if failed or user declined
install_mongodb_tools() {
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "MongoDB Tools Installation Required"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "MongoDB backup requires mongodump:"
    echo "  • Part of MongoDB Database Tools"
    echo "  • Free, open-source (Apache 2.0 license)"
    echo "  • Size: ~30MB"
    echo ""

    read -p "Install MongoDB tools now? (y/n) [y]: " install_choice
    install_choice=${install_choice:-y}

    if [[ ! "$install_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "⊘ MongoDB tools installation skipped"
        echo ""
        echo "To install manually:"
        if [[ "$(uname -s)" == "Darwin" ]]; then
            echo "  brew tap mongodb/brew"
            echo "  brew install mongodb-database-tools"
        else
            echo "  Visit: https://www.mongodb.com/try/download/database-tools"
        fi
        echo ""
        return 1
    fi

    echo ""
    echo "Installing MongoDB tools..."

    if [[ "$(uname -s)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            echo "Using Homebrew..."
            if brew tap mongodb/brew && brew install mongodb-database-tools; then
                echo "✅ MongoDB tools installed"
                return 0
            else
                echo "❌ Installation failed"
                return 1
            fi
        else
            echo "❌ Homebrew required for macOS installation"
            return 1
        fi
    else
        echo "❌ Automatic installation not available for Linux"
        echo "Please visit: https://www.mongodb.com/try/download/database-tools"
        return 1
    fi
}

# Require MongoDB tools (check, prompt to install if missing)
# Returns: 0 if available, 1 if not available
require_mongodb_tools() {
    if check_mongodb_tools; then
        return 0
    fi

    if install_mongodb_tools; then
        if check_mongodb_tools; then
            return 0
        else
            echo "❌ MongoDB tools installation verification failed"
            return 1
        fi
    else
        return 1
    fi
}
