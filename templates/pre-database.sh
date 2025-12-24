#!/bin/bash
# ClaudeCode Project Backups - Database Safety Hook
# Blocks destructive database operations without explicit user approval

# Read command from stdin
read -r command

# Dangerous patterns to detect
DANGEROUS_PATTERNS=(
    "DROP DATABASE"
    "DROP TABLE"
    "TRUNCATE"
    "DELETE FROM"
    "rm.*\.db"
    "rm.*\.sqlite"
    "sqlite3.*DROP"
)

is_dangerous=false
matched_pattern=""

# Check if command matches any dangerous pattern
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    if echo "$command" | grep -iE "$pattern" > /dev/null; then
        is_dangerous=true
        matched_pattern="$pattern"
        break
    fi
done

# Block if dangerous
if [ "$is_dangerous" = true ]; then
    echo "⚠️  CRITICAL DATABASE OPERATION DETECTED"
    echo "Pattern matched: $matched_pattern"
    echo "Backups: $PWD/backups/databases/"
    echo ""
    echo "This operation has been blocked for safety."
    echo "To proceed, bypass this hook or restore from backups if needed."
    exit 1
fi

exit 0
