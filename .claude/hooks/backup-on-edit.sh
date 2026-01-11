#!/usr/bin/env bash
# Trigger backup after Claude edits/writes files
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

cd "$CWD" || exit 0
[ -f .backup-config.sh ] || exit 0

# Log edit event (optional, for debugging)
# FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
# echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") Edit: $FILE_PATH" >> ~/.claudecode-backups/logs/hook-events.log

# Trigger backup in background
./bin/smart-backup-trigger.sh &

exit 0
