#!/bin/bash
# Claude Code Skill: backup-now (from Checkpoint)
# Trigger immediate backup

set -euo pipefail

# Get the backup scripts directory
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"

# Execute the backup-now script
exec "$BIN_DIR/backup-now.sh" "$@"
