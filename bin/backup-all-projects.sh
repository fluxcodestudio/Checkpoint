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

# ==============================================================================
# TWO-PASS DOCKER STRATEGY
# ==============================================================================
# Pass 1: Scan projects for Docker compose files. If found and Docker isn't
#          running, start Docker in background. Back up non-Docker projects
#          first while Docker boots (~30-60s).
# Pass 2: Back up Docker projects last (Docker is ready by then).
# Cleanup: If we started Docker, shut it down after all backups complete.

# Quick scan: check for docker-compose files (doesn't need Docker running)
has_docker_compose() {
    local dir="$1"
    for f in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
        [[ -f "$dir/$f" ]] && return 0
    done
    find "$dir" -maxdepth 2 -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \
        -o -name "compose.yml" -o -name "compose.yaml" \) \
        -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | grep -q . 2>/dev/null
}

# Classify projects into standard vs Docker
docker_projects=()
non_docker_projects=()
while IFS= read -r project_path; do
    [[ -z "$project_path" ]] && continue
    [[ ! -d "$project_path" ]] && continue
    if has_docker_compose "$project_path"; then
        docker_projects+=("$project_path")
    else
        non_docker_projects+=("$project_path")
    fi
done < <(list_projects)

daemon_log "Projects: ${#non_docker_projects[@]} standard, ${#docker_projects[@]} with Docker"

# Pre-start Docker if needed (boots in background while we back up standard projects)
_docker_started_by_us=false
if [[ ${#docker_projects[@]} -gt 0 ]] && ! is_docker_running; then
    if [[ "${AUTO_START_DOCKER:-true}" == "true" ]]; then
        daemon_log "🐳 Starting Docker Desktop (will back up Docker projects last)..."
        open -a Docker 2>/dev/null || true
        _docker_started_by_us=true
    fi
fi

# Helper: back up a single project
backup_one_project() {
    local project_path="$1"

    ((project_index++)) || true
    local project_name
    project_name="$(basename "$project_path")"
    log_set_context "all-projects:$project_name"

    write_progress_heartbeat "$project_name"

    daemon_log "─────────────────────────────────────────────"
    daemon_log "Project: $project_name"
    daemon_log "Path: $project_path"

    if [[ ! -d "$project_path" ]]; then
        daemon_log "  ⚠️  Directory not found - skipping"
        ((skipped++)) || true
        write_progress_heartbeat "$project_name"
        return
    fi

    if [[ ! -f "$project_path/.backup-config.sh" ]]; then
        daemon_log "  ⚠️  No config found - skipping"
        ((skipped++)) || true
        write_progress_heartbeat "$project_name"
        return
    fi

    daemon_log "  🚀 Running backup..."

    local backup_cmd
    if [[ "$FORCE_BACKUP" == "true" ]]; then
        backup_cmd="$SCRIPT_DIR/backup-now.sh --force"
    else
        backup_cmd="$SCRIPT_DIR/backup-daemon.sh"
    fi

    export CHECKPOINT_SYNC_INDEX="$project_index"
    export CHECKPOINT_SYNC_TOTAL="$project_count"
    export CHECKPOINT_SYNC_PROJECT="$project_name"
    export CHECKPOINT_SYNC_BACKED_UP="$backed_up"
    export CHECKPOINT_SYNC_FAILED="$failed"
    export CHECKPOINT_SYNC_SKIPPED="$skipped"

    if (cd "$project_path" && $backup_cmd 2>&1); then
        daemon_log "  ✅ Backup complete"
        ((backed_up++)) || true
        update_last_backup "$project_path"
    else
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            daemon_log "  ✅ Backup complete (with warnings)"
            ((backed_up++)) || true
        else
            daemon_log "  ❌ Backup failed (exit code: $exit_code)"
            ((failed++)) || true
        fi
    fi

    write_progress_heartbeat "$project_name"
}

# PASS 1: Standard projects (while Docker boots in background)
if [[ ${#non_docker_projects[@]} -gt 0 ]]; then
    daemon_log "── Pass 1: Standard projects ──────────────────"
    for project_path in "${non_docker_projects[@]}"; do
        backup_one_project "$project_path"
    done
fi

# PASS 2: Docker projects (Docker should be ready by now)
if [[ ${#docker_projects[@]} -gt 0 ]]; then
    daemon_log "── Pass 2: Docker projects ────────────────────"

    if [[ "$_docker_started_by_us" == "true" ]] && ! is_docker_running; then
        daemon_log "  ⏳ Waiting for Docker Desktop..."
        _wait=0
        while ! is_docker_running && [[ $_wait -lt 90 ]]; do
            sleep 3
            _wait=$((_wait + 3))
        done
        if is_docker_running; then
            daemon_log "  ✓ Docker ready (${_wait}s)"
            mkdir -p "$CHECKPOINT_CACHE_DIR" 2>/dev/null || true
            [[ ! -L "$CHECKPOINT_DOCKER_FLAG" ]] && touch "$CHECKPOINT_DOCKER_FLAG"
        else
            daemon_log "  ⚠ Docker failed to start — Docker DB dumps will be skipped"
        fi
    fi

    for project_path in "${docker_projects[@]}"; do
        backup_one_project "$project_path"
    done
fi

# Cleanup: Stop Docker if we started it (only after ALL backups complete)
if [[ "$_docker_started_by_us" == "true" ]] || did_we_start_docker; then
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
