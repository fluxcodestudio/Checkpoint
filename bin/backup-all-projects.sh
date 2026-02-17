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

# Source logging module directly (this script doesn't use backup-lib.sh)
source "$LIB_DIR/core/logging.sh"
init_logging "$HOME/.config/checkpoint/checkpoint.log"
log_set_context "all-projects"
parse_log_flags "$@"

# Source libraries
source "$LIB_DIR/projects-registry.sh"
source "$LIB_DIR/database-detector.sh"

# Legacy logging (user-facing output + log file)
LOG_FILE="$HOME/.config/checkpoint/daemon.log"
mkdir -p "$(dirname "$LOG_FILE")"

daemon_log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
    log_info "$1"
}

# ==============================================================================
# MAIN
# ==============================================================================

daemon_log "═══════════════════════════════════════════════"
daemon_log "Checkpoint Global Daemon - Starting"
daemon_log "═══════════════════════════════════════════════"

# Lockfile: prevent concurrent backup-all runs
LOCK_FILE="$HOME/.checkpoint/.backup-all.lock"
mkdir -p "$(dirname "$LOCK_FILE")"

cleanup_lock() {
    rm -f "$LOCK_FILE"
}
trap cleanup_lock EXIT

if [[ -f "$LOCK_FILE" ]]; then
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        if [[ "$FORCE_BACKUP" == "true" ]]; then
            # Force run takes priority — terminate the existing run
            daemon_log "Force backup requested. Stopping existing run (PID $lock_pid)."
            kill "$lock_pid" 2>/dev/null
            # Wait briefly for it to exit and clean up its lock
            for i in 1 2 3 4 5; do
                kill -0 "$lock_pid" 2>/dev/null || break
                sleep 1
            done
            rm -f "$LOCK_FILE"
        else
            daemon_log "Another backup-all is already running (PID $lock_pid). Skipping."
            exit 0
        fi
    else
        daemon_log "Stale lock found (PID $lock_pid no longer running). Removing."
        rm -f "$LOCK_FILE"
    fi
fi
echo $$ > "$LOCK_FILE"

# Get list of registered projects
project_count=$(count_projects)
daemon_log "Registered projects: $project_count"

if [[ "$project_count" -eq 0 ]]; then
    daemon_log "No projects registered. Run 'backup-now' in a project to register it."
    exit 0
fi

# Track results
backed_up=0
skipped=0
failed=0
project_index=0

# Progress heartbeat for menu bar widget (Dropbox-style live progress)
HEARTBEAT_DIR="$HOME/.checkpoint"
PROGRESS_HEARTBEAT_FILE="$HEARTBEAT_DIR/daemon.heartbeat"

write_progress_heartbeat() {
    local current_project="${1:-}"
    local tmp_file="${HEARTBEAT_DIR}/.heartbeat.progress.tmp.$$"
    local now
    now=$(date +%s)
    mkdir -p "$HEARTBEAT_DIR"
    cat > "$tmp_file" <<PEOF
{
  "timestamp": $now,
  "status": "syncing",
  "project": "global",
  "last_backup": $now,
  "last_backup_files": $backed_up,
  "error": null,
  "pid": $$,
  "syncing_project_index": $project_index,
  "syncing_total_projects": $project_count,
  "syncing_current_project": "$current_project",
  "syncing_backed_up": $backed_up,
  "syncing_failed": $failed,
  "syncing_skipped": $skipped
}
PEOF
    mv "$tmp_file" "$PROGRESS_HEARTBEAT_FILE"
}

# Backup each project
while IFS= read -r project_path; do
    if [[ -z "$project_path" ]]; then
        continue
    fi

    ((project_index++)) || true
    project_name="$(basename "$project_path")"
    log_set_context "all-projects:$project_name"

    # Write progress heartbeat BEFORE starting this project
    write_progress_heartbeat "$project_name"

    daemon_log "─────────────────────────────────────────────"
    daemon_log "Project: $project_name"
    daemon_log "Path: $project_path"

    # Check if project directory exists
    if [[ ! -d "$project_path" ]]; then
        daemon_log "  ⚠️  Directory not found - skipping"
        ((skipped++)) || true
        write_progress_heartbeat "$project_name"
        continue
    fi

    # Check if config exists
    if [[ ! -f "$project_path/.backup-config.sh" ]]; then
        daemon_log "  ⚠️  No config found - skipping"
        ((skipped++)) || true
        write_progress_heartbeat "$project_name"
        continue
    fi

    # Run backup for this project
    daemon_log "  🚀 Running backup..."

    # Use backup-now --force or backup-daemon depending on force flag
    if [[ "$FORCE_BACKUP" == "true" ]]; then
        backup_cmd="$SCRIPT_DIR/backup-now.sh --force"
    else
        backup_cmd="$SCRIPT_DIR/backup-daemon.sh"
    fi

    # Export sync progress so backup-daemon.sh can include it in heartbeats
    export CHECKPOINT_SYNC_INDEX="$project_index"
    export CHECKPOINT_SYNC_TOTAL="$project_count"
    export CHECKPOINT_SYNC_PROJECT="$project_name"
    export CHECKPOINT_SYNC_BACKED_UP="$backed_up"
    export CHECKPOINT_SYNC_FAILED="$failed"
    export CHECKPOINT_SYNC_SKIPPED="$skipped"

    if (cd "$project_path" && $backup_cmd 2>&1); then
        daemon_log "  ✅ Backup complete"
        ((backed_up++)) || true

        # Update last backup in registry
        update_last_backup "$project_path"
    else
        exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            daemon_log "  ✅ Backup complete (with warnings)"
            ((backed_up++)) || true
        else
            daemon_log "  ❌ Backup failed (exit code: $exit_code)"
            ((failed++)) || true
        fi
    fi

    # Write progress heartbeat AFTER this project completes
    write_progress_heartbeat "$project_name"

done < <(list_projects)

# Cleanup: Stop Docker if we started it (only after ALL backups complete)
if did_we_start_docker; then
    daemon_log "🐳 Cleaning up Docker..."
    stop_docker
fi

# Summary
daemon_log "═══════════════════════════════════════════════"
daemon_log "Checkpoint Global Daemon - Complete"
daemon_log "═══════════════════════════════════════════════"
daemon_log "  Backed up: $backed_up"
daemon_log "  Skipped:   $skipped"
daemon_log "  Failed:    $failed"
daemon_log "═══════════════════════════════════════════════"

# Write global heartbeat for helper app (uses HEARTBEAT_DIR defined above)
HEARTBEAT_FILE="$PROGRESS_HEARTBEAT_FILE"

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
  "pid": $$,
  "syncing_project_index": 0,
  "syncing_total_projects": 0,
  "syncing_current_project": "",
  "syncing_backed_up": $backed_up,
  "syncing_failed": $failed,
  "syncing_skipped": $skipped
}
EOF

# Cleanup orphaned projects periodically (every 24 hours)
CLEANUP_STATE="$HOME/.config/checkpoint/.last-cleanup"
if [[ -f "$CLEANUP_STATE" ]]; then
    last_cleanup=$(cat "$CLEANUP_STATE" 2>/dev/null || echo "0")
    now=$(date +%s)
    if (( now - last_cleanup > 86400 )); then
        daemon_log "Running orphan cleanup..."
        cleanup_orphaned
        echo "$now" > "$CLEANUP_STATE"
    fi
else
    echo "$(date +%s)" > "$CLEANUP_STATE"
fi

exit 0
