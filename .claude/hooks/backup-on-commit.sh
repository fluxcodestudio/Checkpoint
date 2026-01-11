#!/usr/bin/env bash
# Trigger backup after Claude makes a git commit
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

cd "$CWD" || exit 0
[ -f .backup-config.sh ] || exit 0

# Trigger backup in background
./bin/smart-backup-trigger.sh &

exit 0
