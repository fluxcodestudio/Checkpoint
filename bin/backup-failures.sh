#!/usr/bin/env bash
# Checkpoint - Backup Failures Viewer
# Display detailed backup failure information with copy-paste-ready format for AI troubleshooting

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Source foundation library
if [ -f "$LIB_DIR/backup-lib.sh" ]; then
    source "$LIB_DIR/backup-lib.sh"
else
    echo "Error: Foundation library not found: $LIB_DIR/backup-lib.sh" >&2
    exit 1
fi

# ==============================================================================
# COMMAND LINE OPTIONS
# ==============================================================================

PROJECT_DIR="${1:-${PWD}}"
SHOW_HELP=false

if [ "$PROJECT_DIR" = "--help" ] || [ "$PROJECT_DIR" = "-h" ]; then
    SHOW_HELP=true
fi

# ==============================================================================
# HELP TEXT
# ==============================================================================

if [ "$SHOW_HELP" = true ]; then
    cat <<EOF
Checkpoint - Backup Failures Viewer

Display detailed backup failure information with AI-ready error logs.

USAGE:
    backup-failures.sh [PROJECT_DIR]

EXAMPLES:
    backup-failures.sh              # Check current project
    backup-failures.sh /path/to/project

WORKFLOW WHEN BACKUPS FAIL:
    1. Run 'backup-failures.sh' to see detailed errors
    2. Copy the error output
    3. Paste into Claude Code chat
    4. Ask: "Fix these backup failures"
    5. After Claude fixes the issues, run: backup-now.sh --force

EOF
    exit 0
fi

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

if ! load_backup_config "$PROJECT_DIR"; then
    echo "Error: No backup configuration found in: $PROJECT_DIR" >&2
    echo "This project is not configured for backups." >&2
    echo "Run install.sh first." >&2
    exit 1
fi

# Initialize state directories
init_state_dirs

# ==============================================================================
# SHOW FAILURES
# ==============================================================================

echo ""
echo "Checkpoint - Backup Failure Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Use library function to show failures
show_backup_failures

exit_code=$?

# Add copy-paste section if failures exist
if [ $exit_code -ne 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "COPY-PASTE FORMAT FOR CLAUDE CODE:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Generate clean copy-paste format
    state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    failure_log="$state_dir/.last-backup-failures"

    if [ -f "$failure_log" ]; then
        cat <<'COPY_PASTE_START'
Please fix these Checkpoint backup failures:

Project: REPLACE_PROJECT_NAME
Backup Dir: REPLACE_BACKUP_DIR

FAILURES:
COPY_PASTE_START

        # Replace placeholders
        sed "s/REPLACE_PROJECT_NAME/$PROJECT_NAME/g; s|REPLACE_BACKUP_DIR|$BACKUP_DIR|g"

        echo ""

        # Show each failure in clean format
        local count=0
        while IFS='|' read -r file error_type suggested_fix; do
            count=$((count + 1))
            echo "$count. File: $file"
            echo "   Error: $error_type"
            echo "   Suggested fix: $suggested_fix"
            echo ""
        done < "$failure_log"

        cat <<'COPY_PASTE_END'

After fixing these issues, I'll run: backup-now.sh --force
COPY_PASTE_END
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

exit $exit_code
