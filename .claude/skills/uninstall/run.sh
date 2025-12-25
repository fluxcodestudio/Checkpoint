#!/bin/bash
# Skill wrapper for uninstall command

set -euo pipefail

# Find the uninstall.sh script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Check for global installation
if command -v checkpoint-uninstall &>/dev/null; then
    checkpoint-uninstall "$@"
elif [[ -x "$PROJECT_ROOT/bin/uninstall.sh" ]]; then
    "$PROJECT_ROOT/bin/uninstall.sh" "$@"
else
    echo "Error: uninstall command not found"
    exit 1
fi
