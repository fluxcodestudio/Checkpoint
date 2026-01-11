#!/usr/bin/env bash
# Backup Update Skill - Update Checkpoint to latest version
set -euo pipefail

# Find backup-update command
UPDATE_CMD=""
if command -v backup-update &>/dev/null; then
    UPDATE_CMD="backup-update"
elif [[ -f "$HOME/.local/bin/backup-update" ]]; then
    UPDATE_CMD="$HOME/.local/bin/backup-update"
elif [[ -f "./bin/backup-update.sh" ]]; then
    UPDATE_CMD="./bin/backup-update.sh"
fi

# Check for --check-only flag
CHECK_ONLY=false
for arg in "$@"; do
    if [[ "$arg" == "--check-only" ]] || [[ "$arg" == "-c" ]]; then
        CHECK_ONLY=true
    fi
done

if [[ -n "$UPDATE_CMD" ]]; then
    if [[ "$CHECK_ONLY" == "true" ]]; then
        exec "$UPDATE_CMD" --check-only
    else
        exec "$UPDATE_CMD"
    fi
fi

# Fallback: manual update check
echo "═══════════════════════════════════════════════"
echo "Checkpoint - Update Check"
echo "═══════════════════════════════════════════════"

# Get current version
CURRENT_VERSION=""
if [[ -f "$HOME/.local/lib/checkpoint/VERSION" ]]; then
    CURRENT_VERSION=$(cat "$HOME/.local/lib/checkpoint/VERSION")
elif [[ -f "./VERSION" ]]; then
    CURRENT_VERSION=$(cat "./VERSION")
fi

echo ""
echo "Current version: ${CURRENT_VERSION:-unknown}"
echo ""

if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "To update, run: /backup-update"
    exit 0
fi

# Check if we have a source directory
if [[ -d "./bin" ]] && [[ -f "./bin/install-global.sh" ]]; then
    echo "Update source found. Running installer..."
    exec ./bin/install-global.sh
else
    echo "No update source found."
    echo ""
    echo "To update manually:"
    echo "  1. Download latest version from GitHub"
    echo "  2. Run: ./bin/install-global.sh"
    exit 1
fi
