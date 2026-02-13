#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - File Operations
# ==============================================================================
# @requires: core/error-codes (for map_error_to_code), core/output (for color functions)
# @provides: copy_with_retry, track_file_failure, acquire_backup_lock,
#            release_backup_lock, get_lock_pid, get_file_hash,
#            files_identical_hash, get_backup_disk_usage, check_disk_space
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_FILE_OPS:-}" ] && return || readonly _CHECKPOINT_FILE_OPS=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ==============================================================================
# RETRY LOGIC FOR TRANSIENT FAILURES
# ==============================================================================

# Copy file with retry logic for transient errors
# Args: $1 = source, $2 = destination, $3 = max retries (default: 3)
# Returns: 0 on success, 1 on permanent failure
# Sets: COPY_FAILURE_REASON (permission_denied|disk_full|read_error|unknown)
copy_with_retry() {
    local src="$1"
    local dest="$2"
    local max_retries="${3:-3}"
    local retry_delay=1
    local attempt=1
    local last_error=""

    while [ $attempt -le $max_retries ]; do
        # Attempt copy and capture error
        last_error=$(cp "$src" "$dest" 2>&1) && return 0

        # Detect error type from error message
        if echo "$last_error" | grep -qi "permission denied"; then
            COPY_FAILURE_REASON="permission_denied"
            return 1  # Don't retry permission errors
        elif echo "$last_error" | grep -qi "no space left"; then
            COPY_FAILURE_REASON="disk_full"
            return 1  # Don't retry disk full errors
        elif echo "$last_error" | grep -qi "input/output error"; then
            COPY_FAILURE_REASON="read_error"
            # Continue retrying for I/O errors (transient)
        else
            COPY_FAILURE_REASON="unknown"
        fi

        # Copy failed - check if we should retry
        if [ $attempt -lt $max_retries ]; then
            # Log retry attempt (if verbose)
            if [ "${VERBOSE:-false}" = true ]; then
                echo "      Retry $attempt/$max_retries for $(basename "$src")..." >&2
            fi

            sleep $retry_delay
            retry_delay=$((retry_delay * 2))  # Exponential backoff: 1s, 2s, 4s
        fi

        attempt=$((attempt + 1))
    done

    # All retries exhausted
    return 1
}

# Track file backup failure with actionable error message
# Args: $1 = file path, $2 = error type, $3 = failure log file
track_file_failure() {
    local file="$1"
    local error_type="$2"
    local failure_log="$3"

    local suggested_fix=""

    case "$error_type" in
        "permission_denied")
            suggested_fix="Run: chmod +r \"$file\" or check file permissions"
            ;;
        "file_missing")
            suggested_fix="File was deleted during backup (ignore if intentional)"
            ;;
        "read_error")
            suggested_fix="File may be locked by another process. Close editors/apps using this file"
            ;;
        "size_mismatch")
            suggested_fix="File was modified during backup. Retry backup to capture current version"
            ;;
        "copy_failed")
            suggested_fix="Check disk space and file system integrity"
            ;;
        "verification_failed")
            suggested_fix="Backup corrupted. Check disk space and file system health"
            ;;
        *)
            suggested_fix="Unknown error. Run 'backup-failures' for details"
            ;;
    esac

    echo "$file|$error_type|$suggested_fix" >> "$failure_log"
}

# ==============================================================================
# FILE LOCKING
# ==============================================================================

# Acquire backup lock
# Args: $1 = project name
# Returns: 0 if lock acquired, 1 if lock already held
# Sets: LOCK_DIR, LOCK_PID_FILE
acquire_backup_lock() {
    local project_name="$1"

    LOCK_DIR="${HOME}/.claudecode-backups/locks/${project_name}.lock"
    LOCK_PID_FILE="$LOCK_DIR/pid"

    # Try to acquire lock by creating directory (atomic operation)
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_PID_FILE"
        return 0
    fi

    # Lock exists - check if it's stale
    if [ -f "$LOCK_PID_FILE" ]; then
        local lock_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null)
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            # Process is running - lock is valid
            return 1
        else
            # Process is dead - lock is stale, clean it up
            rm -rf "$LOCK_DIR"
            # Try to acquire lock again
            if mkdir "$LOCK_DIR" 2>/dev/null; then
                echo $$ > "$LOCK_PID_FILE"
                return 0
            fi
            return 1
        fi
    else
        # Lock directory exists but no PID file - probably stale
        rm -rf "$LOCK_DIR"
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo $$ > "$LOCK_PID_FILE"
            return 0
        fi
        return 1
    fi
}

# Release backup lock
# Uses: LOCK_DIR (must be set by acquire_backup_lock)
release_backup_lock() {
    if [ -n "${LOCK_DIR:-}" ]; then
        rm -rf "$LOCK_DIR"
    fi
}

# Get PID of process holding backup lock
# Args: $1 = project name
# Returns: PID if lock is held, empty if not
get_lock_pid() {
    local project_name="$1"
    local lock_dir="${HOME}/.claudecode-backups/locks/${project_name}.lock"
    local lock_pid_file="$lock_dir/pid"

    if [ -f "$lock_pid_file" ]; then
        local pid=$(cat "$lock_pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    return 1
}

# ==============================================================================
# HASH-BASED FILE COMPARISON
# ==============================================================================

# Get file hash (uses mtime-based cache for performance)
# Args: $1 = file path
# Returns: SHA256 hash (64 chars) on stdout, returns 1 on error
# Cache format: filepath|mtime|sha256hash (pipe-delimited)
get_file_hash() {
    local file="$1"
    local hash_cache="${BACKUP_DIR:-.}/.hash-cache"
    local file_mtime file_hash cached_line cached_mtime cached_hash

    # Validate file exists
    [ ! -f "$file" ] && return 1

    # Get current mtime (macOS format)
    file_mtime=$(stat -f%m "$file" 2>/dev/null) || return 1

    # Check cache for existing hash
    if [ -f "$hash_cache" ]; then
        # Escape special regex chars in file path for grep
        local escaped_file
        escaped_file=$(printf '%s' "$file" | sed 's/[[\.*^$()+?{|\\]/\\&/g')
        cached_line=$(grep "^${escaped_file}|" "$hash_cache" 2>/dev/null | head -1) || true
        if [ -n "$cached_line" ]; then
            cached_mtime=$(echo "$cached_line" | cut -d'|' -f2)
            cached_hash=$(echo "$cached_line" | cut -d'|' -f3)
            if [ "$file_mtime" = "$cached_mtime" ] && [ -n "$cached_hash" ]; then
                echo "$cached_hash"
                return 0
            fi
        fi
    fi

    # Compute new hash (macOS uses shasum, not sha256sum)
    file_hash=$(shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1) || return 1

    # Validate hash looks correct (64 hex chars)
    if [ ${#file_hash} -ne 64 ]; then
        return 1
    fi

    # Update cache atomically
    local tmp_cache
    tmp_cache=$(mktemp 2>/dev/null) || return 1

    # Ensure cache directory exists
    mkdir -p "$(dirname "$hash_cache")" 2>/dev/null || true

    # Remove old entry for this file (if any) and add new one
    if [ -f "$hash_cache" ]; then
        local escaped_file
        escaped_file=$(printf '%s' "$file" | sed 's/[[\.*^$()+?{|\\]/\\&/g')
        grep -v "^${escaped_file}|" "$hash_cache" 2>/dev/null > "$tmp_cache" || true
    fi
    echo "${file}|${file_mtime}|${file_hash}" >> "$tmp_cache"

    # Atomic replace
    mv "$tmp_cache" "$hash_cache" 2>/dev/null || {
        rm -f "$tmp_cache"
        # Still return hash even if cache update fails
        echo "$file_hash"
        return 0
    }

    echo "$file_hash"
    return 0
}

# Fast file comparison using size check + hash comparison
# Args: $1 = file1, $2 = file2
# Returns: 0 if files are identical, 1 if different or error
files_identical_hash() {
    local file1="$1"
    local file2="$2"

    # Both files must exist
    [ ! -f "$file1" ] && return 1
    [ ! -f "$file2" ] && return 1

    # Quick size check first (very fast, eliminates most differences)
    local size1 size2
    size1=$(stat -f%z "$file1" 2>/dev/null) || return 1
    size2=$(stat -f%z "$file2" 2>/dev/null) || return 1

    # Different sizes = definitely different
    if [ "$size1" != "$size2" ]; then
        return 1
    fi

    # Same size - compare hashes
    local hash1 hash2
    hash1=$(get_file_hash "$file1") || return 1
    hash2=$(get_file_hash "$file2") || return 1

    # Compare hashes
    [ "$hash1" = "$hash2" ]
}

# ==============================================================================
# DISK SPACE ANALYSIS
# ==============================================================================

# Get disk usage percentage for backup directory
# Output: percentage (0-100)
get_backup_disk_usage() {
    local backup_dir="${BACKUP_DIR:-}"
    [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ] && echo "0" && return

    # Get the filesystem the backup directory is on
    if [[ "$OSTYPE" == "darwin"* ]]; then
        df -k "$backup_dir" | awk 'NR==2 {gsub(/%/,""); print $5}'
    else
        df -k "$backup_dir" | awk 'NR==2 {gsub(/%/,""); print $5}'
    fi
}

# Check if disk space is critically low
# Returns: 0 if OK, 1 if warning (>80%), 2 if critical (>90%)
check_disk_space() {
    local usage=$(get_backup_disk_usage)

    if [ $usage -ge 90 ]; then
        return 2
    elif [ $usage -ge 80 ]; then
        return 1
    fi

    return 0
}
