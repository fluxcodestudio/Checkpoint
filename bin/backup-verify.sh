#!/usr/bin/env bash
# Checkpoint - Backup Verification CLI
# Verify integrity of backup files, databases, and cloud sync
# Usage: backup-verify [OPTIONS] [PROJECT_DIR]

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Source foundation library
source "$LIB_DIR/backup-lib.sh"

# Structured logging context
log_set_context "verify"
parse_log_flags "$@"

# ==============================================================================
# COMMAND LINE OPTIONS
# ==============================================================================

OUTPUT_MODE="dashboard"  # dashboard, json, compact
VERIFY_MODE="quick"      # quick, full
INCLUDE_CLOUD=false
SHOW_HELP=false
PROJECT_DIR="$PWD"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_MODE="json"
            shift
            ;;
        --compact)
            OUTPUT_MODE="compact"
            shift
            ;;
        --full)
            VERIFY_MODE="full"
            shift
            ;;
        --cloud)
            INCLUDE_CLOUD=true
            shift
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        *)
            # Assume it's a project directory
            if [ -d "$1" ]; then
                PROJECT_DIR="$1"
            else
                echo "Unknown option or invalid directory: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# ==============================================================================
# HELP TEXT
# ==============================================================================

if [ "$SHOW_HELP" = true ]; then
    cat <<EOF
Checkpoint Backup Verification

Usage: backup-verify [OPTIONS] [PROJECT_DIR]

Options:
  --full          Full verification (SHA256 hashes + deep integrity)
  --cloud         Include cloud sync verification
  --json          Machine-readable JSON output
  --compact       Single-line summary output
  --help, -h      Show this help

Exit codes:
  0  All checks passed
  1  One or more checks failed
  2  Verification could not run (missing config, active backup)

Examples:
  backup-verify                    Quick verify current project
  backup-verify --full             Full integrity check with hashes
  backup-verify --json             JSON output for scripting
  backup-verify --full --cloud     Full check including cloud sync
  backup-verify /path/to/project   Verify specific project

EOF
    exit 0
fi

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

if ! load_backup_config "$PROJECT_DIR"; then
    echo "Error: No backup configuration found in: $PROJECT_DIR" >&2
    echo "Run install.sh first or specify project directory" >&2
    exit 2
fi

# Set defaults for optional config variables
DATABASE_DIR="${DATABASE_DIR:-${BACKUP_DIR:-./backups}/databases}"

# State management defaults
STATE_DIR="${STATE_DIR:-$HOME/.checkpoint/state}"
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

# ==============================================================================
# VALIDATE BACKUP DIRECTORY
# ==============================================================================

if [ ! -d "${BACKUP_DIR:-}" ]; then
    echo "Error: Backup directory does not exist: ${BACKUP_DIR:-<not set>}" >&2
    exit 2
fi

# ==============================================================================
# CHECK FOR ACTIVE BACKUP
# ==============================================================================

lock_pid=$(get_lock_pid "$PROJECT_NAME" 2>/dev/null) || true
if [ -n "$lock_pid" ]; then
    echo "Warning: Backup is currently in progress (PID $lock_pid)" >&2
    echo "Verification may produce inaccurate results during an active backup." >&2
    exit 2
fi

# ==============================================================================
# RUN VERIFICATION
# ==============================================================================

verify_exit=0

if [ "$VERIFY_MODE" = "full" ]; then
    verify_backup_full "$BACKUP_DIR" || verify_exit=$?
else
    verify_backup_quick "$BACKUP_DIR" || verify_exit=$?
fi

# Cloud verification (opt-in)
cloud_exit=0
if [ "$INCLUDE_CLOUD" = true ]; then
    verify_cloud_backup "$BACKUP_DIR" || cloud_exit=$?
fi

# ==============================================================================
# GENERATE REPORT
# ==============================================================================

case "$OUTPUT_MODE" in
    json)
        generate_verification_report "json"
        ;;
    compact)
        generate_verification_report "compact"
        ;;
    *)
        generate_verification_report "human"
        ;;
esac

# ==============================================================================
# SAVE VERIFICATION STATE
# ==============================================================================

state_project_dir="$STATE_DIR/$PROJECT_NAME"
mkdir -p "$state_project_dir" 2>/dev/null || true

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)

# Write last verification result (always JSON regardless of output mode)
cat > "$state_project_dir/last-verification.json" <<EOF
{
  $(json_kv "timestamp" "$ts"),
  $(json_kv "project" "$PROJECT_NAME"),
  $(json_kv "mode" "$VERIFY_MODE"),
  $(json_kv "overall_status" "$VERIFY_OVERALL"),
  $(json_kv "cloud_status" "$VERIFY_CLOUD_STATUS"),
  "files": {$(json_kv_num "total" "$VERIFY_FILES_TOTAL"), $(json_kv_num "passed" "$VERIFY_FILES_PASSED"), $(json_kv_num "failed" "$VERIFY_FILES_FAILED")},
  "databases": {$(json_kv_num "total" "$VERIFY_DBS_TOTAL"), $(json_kv_num "passed" "$VERIFY_DBS_PASSED"), $(json_kv_num "failed" "$VERIFY_DBS_FAILED")}
}
EOF

# ==============================================================================
# EXIT CODE
# ==============================================================================

# Exit 1 if any verification failures, 0 if all pass
if [ $verify_exit -eq 2 ]; then
    exit 2
elif [ $verify_exit -ne 0 ] || [ $cloud_exit -ne 0 ]; then
    exit 1
else
    exit 0
fi
