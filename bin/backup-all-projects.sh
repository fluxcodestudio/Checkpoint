#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Global Backup Daemon
# ==============================================================================
# Backs up ALL registered projects
# Designed to be run by a single global LaunchAgent
# ==============================================================================

set -euo pipefail

# Parse arguments
FORCE_BACKUP=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            FORCE_BACKUP=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Source libraries
source "$LIB_DIR/projects-registry.sh"
source "$LIB_DIR/database-detector.sh"

# Logging
LOG_FILE="$HOME/.config/checkpoint/daemon.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# ==============================================================================
# MAIN
# ==============================================================================

log "═══════════════════════════════════════════════"
log "Checkpoint Global Daemon - Starting"
log "═══════════════════════════════════════════════"

# Get list of registered projects
project_count=$(count_projects)
log "Registered projects: $project_count"

if [[ "$project_count" -eq 0 ]]; then
    log "No projects registered. Run 'backup-now' in a project to register it."
    exit 0
fi

# Track results
backed_up=0
skipped=0
failed=0

# Backup each project
while IFS= read -r project_path; do
    if [[ -z "$project_path" ]]; then
        continue
    fi

    project_name="$(basename "$project_path")"
    log "─────────────────────────────────────────────"
    log "Project: $project_name"
    log "Path: $project_path"

    # Check if project directory exists
    if [[ ! -d "$project_path" ]]; then
        log "  ⚠️  Directory not found - skipping"
        ((skipped++))
        continue
    fi

    # Check if config exists
    if [[ ! -f "$project_path/.backup-config.sh" ]]; then
        log "  ⚠️  No config found - skipping"
        ((skipped++))
        continue
    fi

    # Run backup for this project
    log "  🚀 Running backup..."

    # Use backup-now --force or backup-daemon depending on force flag
    if [[ "$FORCE_BACKUP" == "true" ]]; then
        backup_cmd="$SCRIPT_DIR/backup-now.sh --force"
    else
        backup_cmd="$SCRIPT_DIR/backup-daemon.sh"
    fi

    if (cd "$project_path" && $backup_cmd 2>&1); then
        log "  ✅ Backup complete"
        ((backed_up++)) || true

        # Update last backup in registry
        update_last_backup "$project_path"
    else
        exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            log "  ✅ Backup complete (with warnings)"
            ((backed_up++)) || true
        else
            log "  ❌ Backup failed (exit code: $exit_code)"
            ((failed++)) || true
        fi
    fi

done < <(list_projects)

# Cleanup: Stop Docker if we started it (only after ALL backups complete)
if did_we_start_docker; then
    log "🐳 Cleaning up Docker..."
    stop_docker
fi

# Summary
log "═══════════════════════════════════════════════"
log "Checkpoint Global Daemon - Complete"
log "═══════════════════════════════════════════════"
log "  Backed up: $backed_up"
log "  Skipped:   $skipped"
log "  Failed:    $failed"
log "═══════════════════════════════════════════════"

# Write global heartbeat for helper app
HEARTBEAT_DIR="$HOME/.checkpoint"
HEARTBEAT_FILE="$HEARTBEAT_DIR/daemon.heartbeat"
mkdir -p "$HEARTBEAT_DIR"

now=$(date +%s)
if [[ $failed -gt 0 ]]; then
    status="error"
    error_msg="$failed project(s) failed"
elif [[ $skipped -gt 0 ]] && [[ $backed_up -eq 0 ]]; then
    status="stale"
    error_msg="$skipped project(s) skipped"
else
    status="healthy"
    error_msg=""
fi

if [[ -n "$error_msg" ]]; then
    error_json="\"$error_msg\""
else
    error_json="null"
fi

cat > "$HEARTBEAT_FILE" <<EOF
{
  "timestamp": $now,
  "status": "$status",
  "project": "global",
  "last_backup": $now,
  "last_backup_files": $backed_up,
  "error": $error_json,
  "pid": $$
}
EOF

# Cleanup orphaned projects periodically (every 24 hours)
CLEANUP_STATE="$HOME/.config/checkpoint/.last-cleanup"
if [[ -f "$CLEANUP_STATE" ]]; then
    last_cleanup=$(cat "$CLEANUP_STATE" 2>/dev/null || echo "0")
    now=$(date +%s)
    if (( now - last_cleanup > 86400 )); then
        log "Running orphan cleanup..."
        cleanup_orphaned
        echo "$now" > "$CLEANUP_STATE"
    fi
else
    echo "$(date +%s)" > "$CLEANUP_STATE"
fi

exit 0
