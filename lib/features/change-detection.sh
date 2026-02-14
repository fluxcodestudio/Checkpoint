#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Fast Change Detection
# Optimized functions for detecting file changes with minimal latency
# ==============================================================================
# @requires: none
# @provides: has_changes, get_changed_files_fast
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_CHANGE_DETECTION:-}" ] && return || readonly _CHECKPOINT_CHANGE_DETECTION=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ==============================================================================
# FAST CHANGE DETECTION
# ==============================================================================
# Optimized functions for detecting file changes with minimal latency.
# Uses parallel git commands and early-exit patterns.

# Fast check if there are any changes (yes/no only, no file list)
# Args: $1 = minutes threshold for non-git fallback (optional, default 60)
# Returns: 0 if changes exist, 1 if no changes
has_changes() {
    local mmin_threshold="${1:-60}"

    if git rev-parse --git-dir > /dev/null 2>&1; then
        # Git repo: single fast status check
        # Using head -1 for early exit on first match
        [ -n "$(git status --porcelain 2>/dev/null | head -1)" ]
    else
        # Non-git: check for recent modifications
        [ -n "$(find . -type f -mmin -"$mmin_threshold" \
            ! -path '*/.git/*' \
            ! -path '*/node_modules/*' \
            ! -path '*/backups/*' \
            ! -path '*/.DS_Store' \
            2>/dev/null | head -1)" ]
    fi
}

# Get changed files using parallel git commands
# Args: $1 = output file path
# Returns: 0 on success, writes changed files to output file (one per line)
# Note: Falls back to sequential if not in git repo
get_changed_files_fast() {
    local output_file="$1"
    local tmp1 tmp2 tmp3

    # Ensure output file exists and is empty
    : > "$output_file"

    # Check if we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        # Not a git repo - return empty (caller handles non-git case)
        return 0
    fi

    # Create temp files for parallel execution
    tmp1=$(mktemp) || return 1
    tmp2=$(mktemp) || { rm -f "$tmp1"; return 1; }
    tmp3=$(mktemp) || { rm -f "$tmp1" "$tmp2"; return 1; }

    # Trap to ensure cleanup (use ${var:-} to avoid set -u errors when trap
    # leaks to calling function scope on RETURN)
    trap 'rm -f "${tmp1:-}" "${tmp2:-}" "${tmp3:-}" 2>/dev/null; trap - RETURN' RETURN

    # Parallel execution of git commands
    git diff --name-only > "$tmp1" 2>/dev/null &
    local pid1=$!
    git diff --cached --name-only > "$tmp2" 2>/dev/null &
    local pid2=$!
    git ls-files --others --exclude-standard > "$tmp3" 2>/dev/null &
    local pid3=$!

    # Wait for all to complete (ignore individual failures)
    wait $pid1 2>/dev/null || true
    wait $pid2 2>/dev/null || true
    wait $pid3 2>/dev/null || true

    # Combine and deduplicate results
    cat "$tmp1" "$tmp2" "$tmp3" 2>/dev/null | sort -u > "$output_file"

    # Cleanup handled by trap
    return 0
}
