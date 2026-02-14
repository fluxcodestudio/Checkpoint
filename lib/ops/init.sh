#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Initialization
# ==============================================================================
# @requires: core/config (for check_drive)
# @provides: init_state_dirs, init_backup_dirs
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_INIT:-}" ] && return || readonly _CHECKPOINT_INIT=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Initialize state directories
# Creates necessary directories for tracking state
init_state_dirs() {
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    mkdir -p "$state_dir" 2>/dev/null || { log_debug "Failed to create state dir: $state_dir"; true; }
    mkdir -p "${HOME}/.claudecode-backups/locks" 2>/dev/null || { log_debug "Failed to create locks dir"; true; }
    mkdir -p "${HOME}/.claudecode-backups/logs" 2>/dev/null || { log_debug "Failed to create logs dir"; true; }
}

# Initialize backup directories (only if drive is connected)
# Creates backup storage directories
init_backup_dirs() {
    if ! check_drive; then
        return 1
    fi

    mkdir -p "${DATABASE_DIR:-}" 2>/dev/null || { log_debug "Failed to create DATABASE_DIR: ${DATABASE_DIR:-}"; true; }
    mkdir -p "${FILES_DIR:-}" 2>/dev/null || { log_debug "Failed to create FILES_DIR: ${FILES_DIR:-}"; true; }
    mkdir -p "${ARCHIVED_DIR:-}" 2>/dev/null || { log_debug "Failed to create ARCHIVED_DIR: ${ARCHIVED_DIR:-}"; true; }
    touch "${LOG_FILE:-}" 2>/dev/null || { log_debug "Failed to create LOG_FILE: ${LOG_FILE:-}"; true; }

    return 0
}
