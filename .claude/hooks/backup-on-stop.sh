#!/usr/bin/env bash
# Trigger backup when Claude finishes responding
set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract working directory
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

cd "$CWD" || exit 0

# Check if backup config exists (project has backups enabled)
[ -f .backup-config.sh ] || exit 0

# Trigger backup in background (non-blocking)
./bin/smart-backup-trigger.sh &

exit 0
