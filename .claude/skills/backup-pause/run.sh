#!/bin/bash
# Skill wrapper for backup-pause command

set -euo pipefail

# Find the backup-pause.sh script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Check for global installation
if command -v backup-pause &>/dev/null; then
    backup-pause "$@"
elif [[ -x "$PROJECT_ROOT/bin/backup-pause.sh" ]]; then
    "$PROJECT_ROOT/bin/backup-pause.sh" "$@"
else
    echo "Error: backup-pause command not found"
    exit 1
fi
