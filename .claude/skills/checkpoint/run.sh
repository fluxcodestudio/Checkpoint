#!/bin/bash
# Checkpoint Control Panel - Interactive command center for global and per-project settings

set -euo pipefail

# Find checkpoint command
if command -v checkpoint &>/dev/null; then
    # Global installation
    checkpoint "$@"
elif [[ -x "$(dirname "$0")/../../../bin/checkpoint.sh" ]]; then
    # Per-project installation
    "$(dirname "$0")/../../../bin/checkpoint.sh" "$@"
else
    echo "❌ Checkpoint command not found"
    echo ""
    echo "This skill requires Checkpoint v2.2.0+ with the checkpoint command."
    echo "Please update your installation."
    exit 1
fi
