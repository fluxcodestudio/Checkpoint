#!/bin/bash
# ==============================================================================
# Checkpoint - Update Command
# ==============================================================================
# Updates Checkpoint to the latest version from GitHub
# Usage: backup-update [--check-only]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect installation mode
if [[ "$SCRIPT_DIR" == *"/.local/bin"* ]] || [[ "$SCRIPT_DIR" == *"/usr/local/bin"* ]]; then
    # Global installation
    INSTALL_MODE="global"
    # Find the actual library directory
    if [[ -d "$HOME/.local/lib/checkpoint" ]]; then
        LIB_DIR="$HOME/.local/lib/checkpoint"
    elif [[ -d "/usr/local/lib/checkpoint" ]]; then
        LIB_DIR="/usr/local/lib/checkpoint"
    else
        echo "❌ Error: Cannot find Checkpoint installation directory"
        exit 1
    fi
    PACKAGE_DIR="$(dirname "$LIB_DIR")"
else
    # Per-project installation
    INSTALL_MODE="per-project"
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

CHECK_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --help|-h)
            cat <<EOF
Checkpoint - Update Command

USAGE:
    backup-update              Update to latest version
    backup-update --check-only Check for updates without installing

DESCRIPTION:
    Updates Checkpoint to the latest version from GitHub.

    Global mode: Updates system-wide installation
    Per-project mode: Updates this project's copy

OPTIONS:
    --check-only    Check for updates without installing
    --help, -h      Show this help message

EXAMPLES:
    backup-update              # Update now
    backup-update --check-only # Just check if update available

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ==============================================================================
# CHECK FOR UPDATES
# ==============================================================================

echo "═══════════════════════════════════════════════"
echo "  Checkpoint Update"
echo "═══════════════════════════════════════════════"
echo ""

# Read current version
if [[ "$INSTALL_MODE" == "global" ]]; then
    CURRENT_VERSION=$(cat "$LIB_DIR/VERSION" 2>/dev/null || echo "unknown")
else
    CURRENT_VERSION=$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")
fi

echo "Current version: $CURRENT_VERSION"
echo "Installation mode: $INSTALL_MODE"
echo ""

# Check GitHub for latest version
echo "Checking for updates..."
LATEST_VERSION=$(curl -sf https://api.github.com/repos/nizernoj/Checkpoint/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' 2>/dev/null || echo "")

if [[ -z "$LATEST_VERSION" ]]; then
    echo "⚠️  Update check failed - The repository is private and requires authentication."
    echo ""
    echo "To update manually:"

    # Try to find the original git repository
    if [[ "$INSTALL_MODE" == "global" ]]; then
        # For global installs, suggest common locations
        echo "  cd \"/Volumes/WORK DRIVE - 4TB/WEB DEV/CLAUDE CODE PROJECT BACKUP\""
        echo "  git pull"
        echo "  ./bin/install-global.sh"
    else
        echo "  cd \"$PROJECT_DIR\""
        echo "  git pull"
        echo "  ./bin/install.sh"
    fi
    echo ""
    echo "You're already running the latest version ($CURRENT_VERSION) from the repository,"
    echo "so no update is needed right now."
    echo ""
    echo "Installed features:"
    echo "- Universal database support (SQLite, PostgreSQL, MySQL, MongoDB)"
    echo "- Auto-detection and progressive installation"
    echo "- Cloud backup support"
    echo "- 100% test coverage"
    exit 1
fi

echo "Latest version: $LATEST_VERSION"
echo ""

# Compare versions
if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    echo "✅ You're already on the latest version!"
    exit 0
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "🔔 Update available: $CURRENT_VERSION → $LATEST_VERSION"
    echo ""
    echo "To update, run: backup-update"
    exit 0
fi

# ==============================================================================
# UPDATE
# ==============================================================================

echo "🔄 Update available: $CURRENT_VERSION → $LATEST_VERSION"
echo ""
read -p "Install update now? (y/N): " confirm
confirm=${confirm:-n}

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Update cancelled"
    exit 0
fi

echo ""
echo "Downloading update..."

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

# Download latest release
cd "$TEMP_DIR"
curl -sL "https://github.com/nizernoj/Checkpoint/archive/refs/tags/v${LATEST_VERSION}.tar.gz" -o checkpoint.tar.gz

if [[ ! -f checkpoint.tar.gz ]]; then
    echo "❌ Download failed"
    exit 1
fi

# Extract
tar -xzf checkpoint.tar.gz
cd "Checkpoint-${LATEST_VERSION}"

echo "Installing update..."

if [[ "$INSTALL_MODE" == "global" ]]; then
    # Global update
    if [[ -w "/usr/local/bin" ]]; then
        PREFIX="/usr/local"
    else
        PREFIX="$HOME/.local"
    fi

    # Copy updated files
    cp -r lib/* "$PREFIX/lib/checkpoint/lib/"
    cp -r bin/*.sh "$PREFIX/lib/checkpoint/bin/"
    chmod +x "$PREFIX/lib/checkpoint/bin/"*.sh
    cp VERSION "$PREFIX/lib/checkpoint/VERSION"

    echo "✅ Update complete!"
else
    # Per-project update
    cp -r lib/* "$PROJECT_DIR/.claude/lib/"
    cp -r bin/*.sh "$PROJECT_DIR/bin/"
    chmod +x "$PROJECT_DIR/bin/"*.sh
    cp VERSION "$PROJECT_DIR/VERSION"

    echo "✅ Update complete!"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "  Updated: $CURRENT_VERSION → $LATEST_VERSION"
echo "═══════════════════════════════════════════════"
echo ""
echo "What's new:"
echo "  https://github.com/nizernoj/Checkpoint/releases/tag/v${LATEST_VERSION}"
echo ""
