#!/bin/bash
# Skill wrapper for backup-update command

set -euo pipefail

# Find the backup-update.sh script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Check for global installation
if command -v backup-update &>/dev/null; then
    backup-update "$@"
elif [[ -x "$PROJECT_ROOT/bin/backup-update.sh" ]]; then
    "$PROJECT_ROOT/bin/backup-update.sh" "$@"
else
    echo "Error: backup-update command not found"
    exit 1
fi
