#!/bin/bash
# Checkpoint Control Panel - Interactive TUI dashboard for backup management

set -euo pipefail

# Find checkpoint command
if command -v checkpoint &>/dev/null; then
    # Global installation - explicitly launch TUI dashboard
    if [[ $# -eq 0 ]]; then
        # No arguments = launch TUI dashboard
        exec checkpoint --dashboard
    else
        # Pass through arguments
        checkpoint "$@"
    fi
elif [[ -x "$(dirname "$0")/../../../bin/checkpoint.sh" ]]; then
    # Per-project installation
    if [[ $# -eq 0 ]]; then
        exec "$(dirname "$0")/../../../bin/checkpoint.sh" --dashboard
    else
        "$(dirname "$0")/../../../bin/checkpoint.sh" "$@"
    fi
else
    echo "❌ Checkpoint command not found"
    echo ""
    echo "This skill requires Checkpoint v2.2.1+ with the checkpoint command."
    echo "Please update your installation."
    exit 1
fi
