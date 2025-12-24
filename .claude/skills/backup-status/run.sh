#!/bin/bash
# Claude Code Skill: backup-status (from Checkpoint)
# Show backup system health and statistics

set -euo pipefail

# Get the backup scripts directory
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"

# Execute the backup-status script
exec "$BIN_DIR/backup-status.sh" "$@"
