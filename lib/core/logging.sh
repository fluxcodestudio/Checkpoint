#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Centralized Logging Module
# ==============================================================================
# @requires: none (must load BEFORE config.sh to log config load errors)
# @provides: LOG_LEVEL_* constants, CHECKPOINT_LOG_LEVEL, init_logging,
#            log_error, log_warn, log_info, log_debug, log_trace,
#            log_set_context, parse_log_flags, _toggle_debug_level
#
# Bash 3.2 compatible: NO associative arrays, NO printf '%()T',
# NO declare -A, NO |&
#
# Design: Logging is silent to stdout — only writes to log file.
#         CLI scripts handle their own user-facing output via output.sh.
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_LOGGING:-}" ] && return || readonly _CHECKPOINT_LOGGING=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ==============================================================================
# LOG LEVEL CONSTANTS
# ==============================================================================

readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARN=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_DEBUG=3
readonly LOG_LEVEL_TRACE=4

# Level name lookup (indexed array — bash 3.2 compatible)
# Padded to 5 chars for aligned log output
readonly _LOG_LEVEL_NAMES_0="ERROR"
readonly _LOG_LEVEL_NAMES_1="WARN "
readonly _LOG_LEVEL_NAMES_2="INFO "
readonly _LOG_LEVEL_NAMES_3="DEBUG"
readonly _LOG_LEVEL_NAMES_4="TRACE"

# Current log level — NOT readonly, must be modifiable at runtime
# (SIGUSR1 toggle, --debug flag, config override)
CHECKPOINT_LOG_LEVEL="${CHECKPOINT_LOG_LEVEL:-$LOG_LEVEL_INFO}"

# ==============================================================================
# MODULE STATE
# ==============================================================================

# Log file path (set by init_logging)
_CHECKPOINT_LOG_FILE="${_CHECKPOINT_LOG_FILE:-}"

# Maximum log file size in bytes (default 10MB)
_CHECKPOINT_LOG_MAX_SIZE="${_CHECKPOINT_LOG_MAX_SIZE:-10485760}"

# Context label for log entries (e.g., "backup-now", "daemon", "restore")
_CHECKPOINT_LOG_CONTEXT="${_CHECKPOINT_LOG_CONTEXT:-main}"

# Saved level for SIGUSR1 toggle
_CHECKPOINT_LOG_SAVED_LEVEL=""

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Initialize the logging subsystem
# Args: $1 = log_file path (optional, defaults to /tmp/checkpoint.log)
#       $2 = max_size in bytes (optional, defaults to 10485760 = 10MB)
init_logging() {
    _CHECKPOINT_LOG_FILE="${1:-${LOG_FILE:-/tmp/checkpoint.log}}"
    _CHECKPOINT_LOG_MAX_SIZE="${2:-${CHECKPOINT_LOG_MAX_SIZE:-10485760}}"

    # Create parent directory (keep 2>/dev/null — legitimate use for mkdir)
    mkdir -p "$(dirname "$_CHECKPOINT_LOG_FILE")" 2>/dev/null || true

    # Rotate if needed before starting
    _rotate_log "$_CHECKPOINT_LOG_FILE" "$_CHECKPOINT_LOG_MAX_SIZE"
}

# ==============================================================================
# CORE LOGGING FUNCTION
# ==============================================================================

# Internal log writer — do NOT call directly; use log_error/warn/info/debug/trace
# Args: $1 = numeric level, $2 = level name string, remaining = message
_log() {
    local level="$1"
    local level_name="$2"
    shift 2

    # Guard: skip if below threshold
    if [ "$CHECKPOINT_LOG_LEVEL" -lt "$level" ] 2>/dev/null; then
        return 0
    fi

    # No log file configured — silently skip
    if [ -z "$_CHECKPOINT_LOG_FILE" ]; then
        return 0
    fi

    # Format: [YYYY-MM-DD HH:MM:SS] [LEVEL] [context] message
    # Use date command for bash 3.2 compatibility (NOT printf '%()T')
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Write to log file — never fail the calling script
    printf '[%s] [%s] [%s] %s\n' \
        "$timestamp" "$level_name" "$_CHECKPOINT_LOG_CONTEXT" "$*" \
        >> "$_CHECKPOINT_LOG_FILE" 2>/dev/null || true
}

# ==============================================================================
# CONVENIENCE FUNCTIONS
# ==============================================================================

log_error() { _log "$LOG_LEVEL_ERROR" "ERROR" "$@"; }
log_warn()  { _log "$LOG_LEVEL_WARN"  "WARN " "$@"; }
log_info()  { _log "$LOG_LEVEL_INFO"  "INFO " "$@"; }
log_debug() { _log "$LOG_LEVEL_DEBUG" "DEBUG" "$@"; }
log_trace() { _log "$LOG_LEVEL_TRACE" "TRACE" "$@"; }

# ==============================================================================
# CONTEXT MANAGEMENT
# ==============================================================================

# Set the context label for subsequent log entries
# Args: $1 = context string (e.g., "backup-now", "daemon", "restore")
log_set_context() {
    _CHECKPOINT_LOG_CONTEXT="${1:-main}"
}

# ==============================================================================
# LOG ROTATION
# ==============================================================================

# Rotate log files when they exceed max size
# Args: $1 = log_file path, $2 = max_size in bytes
_rotate_log() {
    local log_file="${1:-$_CHECKPOINT_LOG_FILE}"
    local max_size="${2:-$_CHECKPOINT_LOG_MAX_SIZE}"
    local max_files=5

    # Guard: file must exist
    [ -f "$log_file" ] || return 0

    # Get file size — use get_file_size if available (from platform/compat.sh),
    # otherwise fall back to wc -c
    local current_size=0
    if command -v get_file_size >/dev/null 2>&1; then
        current_size="$(get_file_size "$log_file")"
    else
        current_size="$(wc -c < "$log_file" 2>/dev/null | tr -d ' ')"
    fi
    current_size="${current_size:-0}"

    # Only rotate if over threshold
    if [ "$current_size" -le "$max_size" ] 2>/dev/null; then
        return 0
    fi

    # Shift existing rotated files: .4 -> .5, .3 -> .4, .2 -> .3, .1 -> .2
    local i
    for (( i = max_files - 1; i >= 1; i-- )); do
        local next=$(( i + 1 ))
        if [ -f "${log_file}.${i}" ]; then
            mv "${log_file}.${i}" "${log_file}.${next}" 2>/dev/null || true
        fi
    done

    # Move current log to .1
    mv "$log_file" "${log_file}.1" 2>/dev/null || true

    # Create fresh empty log file
    : > "$log_file" 2>/dev/null || true
}

# ==============================================================================
# CLI FLAG PARSING
# ==============================================================================

# Scan CLI arguments for log-level flags
# Args: "$@" (pass-through from CLI argument list)
# Sets: CHECKPOINT_LOG_LEVEL accordingly
# Does NOT consume arguments — just scans; caller's shift loop handles consumption
parse_log_flags() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --debug)
                CHECKPOINT_LOG_LEVEL="$LOG_LEVEL_DEBUG"
                ;;
            --trace)
                CHECKPOINT_LOG_LEVEL="$LOG_LEVEL_TRACE"
                ;;
            --quiet)
                CHECKPOINT_LOG_LEVEL="$LOG_LEVEL_ERROR"
                ;;
        esac
    done
}

# ==============================================================================
# SIGUSR1 DEBUG TOGGLE
# ==============================================================================

# Toggle between current level and DEBUG — for daemon runtime debugging
# Usage: trap '_toggle_debug_level' USR1
_toggle_debug_level() {
    if [ -n "$_CHECKPOINT_LOG_SAVED_LEVEL" ]; then
        # Restore previous level
        CHECKPOINT_LOG_LEVEL="$_CHECKPOINT_LOG_SAVED_LEVEL"
        _CHECKPOINT_LOG_SAVED_LEVEL=""
        log_info "Debug toggle: restored log level to $CHECKPOINT_LOG_LEVEL"
    else
        # Save current level and switch to DEBUG
        _CHECKPOINT_LOG_SAVED_LEVEL="$CHECKPOINT_LOG_LEVEL"
        CHECKPOINT_LOG_LEVEL="$LOG_LEVEL_DEBUG"
        log_info "Debug toggle: switched to DEBUG (was $_CHECKPOINT_LOG_SAVED_LEVEL)"
    fi
}
