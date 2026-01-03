#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Global Backup Daemon
# ==============================================================================
# Backs up ALL registered projects
# Designed to be run by a single global LaunchAgent
# ==============================================================================

set -euo pipefail

# Resolve symlinks to get actual script location
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Source libraries
source "$LIB_DIR/projects-registry.sh"

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

    # Use backup-daemon.sh which respects intervals
    if (cd "$project_path" && "$SCRIPT_DIR/backup-daemon.sh" 2>&1); then
        log "  ✅ Backup complete"
        ((backed_up++))

        # Update last backup in registry
        update_last_backup "$project_path"
    else
        exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            log "  ✅ Backup complete (with warnings)"
            ((backed_up++))
        else
            log "  ❌ Backup failed (exit code: $exit_code)"
            ((failed++))
        fi
    fi

done < <(list_projects)

# Summary
log "═══════════════════════════════════════════════"
log "Checkpoint Global Daemon - Complete"
log "═══════════════════════════════════════════════"
log "  Backed up: $backed_up"
log "  Skipped:   $skipped"
log "  Failed:    $failed"
log "═══════════════════════════════════════════════"

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
