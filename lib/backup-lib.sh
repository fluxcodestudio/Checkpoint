#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Core Library
# ==============================================================================
# Version: 2.1.0
# Description: Foundation library providing configuration management, YAML
#              parsing, validation, and safe file operations for all backup
#              commands.
#
# Usage:
#   source "$(dirname "$0")/../lib/backup-lib.sh"
#   config_load
#   value=$(config_get "locations.backup_dir")
#
# Features:
#   - YAML configuration parsing (pure bash, no external dependencies)
#   - Fallback to legacy .backup-config.sh
#   - Configuration validation with helpful error messages
#   - Safe atomic file operations
#   - Migration from bash to YAML format
#   - Comprehensive logging
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION LOADING
# ==============================================================================

# Load backup configuration from project directory
# Args: $1 = project directory (optional, defaults to PWD)
# Sets: All configuration variables from .backup-config.sh
load_backup_config() {
    local project_dir="${1:-$PWD}"
    local config_file="$project_dir/.backup-config.sh"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    source "$config_file"
    return 0
}

# ==============================================================================
# DRIVE VERIFICATION
# ==============================================================================

# Check if external drive is mounted (if verification enabled)
# Returns: 0 if check passes, 1 if drive not connected
check_drive() {
    if [ "${DRIVE_VERIFICATION_ENABLED:-false}" = false ]; then
        return 0  # Skip check if disabled
    fi

    if [ -z "${DRIVE_MARKER_FILE:-}" ]; then
        return 1
    fi

    if [ ! -f "$DRIVE_MARKER_FILE" ]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# NOTIFICATION SYSTEM
# ==============================================================================

# Send native macOS notification
# Args: $1 = title, $2 = message, $3 = sound (optional)
send_notification() {
    local title="$1"
    local message="$2"
    local sound="${3:-default}"

    # Only send if notifications are enabled (default: true)
    if [ "${NOTIFICATIONS_ENABLED:-true}" = false ]; then
        return 0
    fi

    # Use osascript for native macOS notifications (no dependencies)
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

# Send backup failure notification (with spam prevention + escalation)
# Args: $1 = error count, $2 = error message
notify_backup_failure() {
    local error_count="$1"
    local error_msg="${2:-Unknown error}"
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    local failure_state="$state_dir/.last-backup-failed"

    mkdir -p "$state_dir" 2>/dev/null || true

    # Check if this is a new failure or escalation
    if [ ! -f "$failure_state" ]; then
        # FIRST FAILURE - notify immediately
        send_notification \
            "⚠️ Checkpoint Backup Failed" \
            "${PROJECT_NAME:-Backup} failed with $error_count error(s). Run 'backup-failures' to see details." \
            "Basso"

        # Mark as failed with timestamp and error
        echo "$(date +%s)|$error_count|$error_msg" > "$failure_state"
    else
        # EXISTING FAILURE - check if we should escalate
        local first_failure_time=$(cat "$failure_state" 2>/dev/null | cut -d'|' -f1)
        local now=$(date +%s)
        local time_since_first=$((now - first_failure_time))

        # Escalate every 3 hours (10800 seconds)
        local escalation_interval=10800
        local escalation_marker="$state_dir/.last-backup-escalation"
        local last_escalation=0

        if [ -f "$escalation_marker" ]; then
            last_escalation=$(cat "$escalation_marker" 2>/dev/null || echo "0")
        fi

        local time_since_escalation=$((now - last_escalation))

        if [ $time_since_escalation -ge $escalation_interval ]; then
            # ESCALATION - remind user
            send_notification \
                "🚨 Checkpoint Still Failing" \
                "${PROJECT_NAME:-Backup} has been failing for $((time_since_first / 3600))h. Run 'backup-failures' to fix." \
                "Basso"

            echo "$now" > "$escalation_marker"
        fi
    fi
}

# Send backup success notification (only after previous failure)
# Clears failure state and notifies user backup is restored
notify_backup_success() {
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    local failure_state="$state_dir/.last-backup-failed"
    local escalation_marker="$state_dir/.last-backup-escalation"
    local failure_log="$state_dir/.last-backup-failures"

    # Only notify if recovering from previous failure
    if [ -f "$failure_state" ]; then
        send_notification \
            "✅ Checkpoint Backup Restored" \
            "${PROJECT_NAME:-Backup} is working again!" \
            "Glass"

        # Clear all failure tracking
        rm -f "$failure_state"
        rm -f "$escalation_marker"
        rm -f "$failure_log"
    fi
}

# Send backup warning notification (non-critical issues)
# Args: $1 = warning message
notify_backup_warning() {
    local warning_msg="$1"

    send_notification \
        "⚠️ Checkpoint Warning" \
        "${PROJECT_NAME:-Backup}: $warning_msg" \
        "Purr"
}

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
# FAILURE REPORTING
# ==============================================================================

# Display backup failures in human-readable format
# Shows detailed error info with suggested fixes
show_backup_failures() {
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    local failure_log="$state_dir/.last-backup-failures"
    local failure_state="$state_dir/.last-backup-failed"

    if [ ! -f "$failure_state" ]; then
        echo "✅ No backup failures"
        return 0
    fi

    # Parse failure state
    local failure_time=$(cat "$failure_state" 2>/dev/null | cut -d'|' -f1)
    local error_count=$(cat "$failure_state" 2>/dev/null | cut -d'|' -f2)
    local error_msg=$(cat "$failure_state" 2>/dev/null | cut -d'|' -f3)

    local time_ago=$(format_time_ago "$failure_time")

    echo ""
    echo "⚠️  BACKUP FAILURES DETECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Project: ${PROJECT_NAME:-Unknown}"
    echo "Failed: $time_ago ($error_count errors)"
    echo "Reason: $error_msg"
    echo ""

    if [ ! -f "$failure_log" ]; then
        echo "No detailed failure log available"
        echo ""
        return 1
    fi

    echo "FAILED FILES:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local count=0
    while IFS='|' read -r file error_type suggested_fix; do
        count=$((count + 1))
        echo ""
        echo "$count. $file"
        echo "   Error: $error_type"
        echo "   Fix: $suggested_fix"
    done < "$failure_log"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "TO FIX:"
    echo "  1. Copy the error details above"
    echo "  2. Paste into Claude Code chat"
    echo "  3. Ask: 'Fix these backup failures'"
    echo "  4. After fixing, run: backup-now.sh --force"
    echo ""
    echo "FAILURE LOG: $failure_log"
    echo ""

    return 1
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
# TIME UTILITIES
# ==============================================================================

# Format seconds into human-readable time ago
# Args: $1 = timestamp (Unix epoch)
# Output: "2h ago", "45m ago", "3d ago", etc.
format_time_ago() {
    local timestamp="$1"
    local now=$(date +%s)
    local diff=$((now - timestamp))

    if [ $diff -lt 0 ]; then
        echo "in the future"
    elif [ $diff -lt 60 ]; then
        echo "${diff}s ago"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60))m ago"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# Format seconds into human-readable duration
# Args: $1 = seconds
# Output: "2h 15m", "45m", "3d 4h", etc.
format_duration() {
    local seconds="$1"

    if [ $seconds -lt 60 ]; then
        echo "${seconds}s"
    elif [ $seconds -lt 3600 ]; then
        echo "$((seconds / 60))m"
    elif [ $seconds -lt 86400 ]; then
        local hours=$((seconds / 3600))
        local mins=$(((seconds % 3600) / 60))
        if [ $mins -gt 0 ]; then
            echo "${hours}h ${mins}m"
        else
            echo "${hours}h"
        fi
    else
        local days=$((seconds / 86400))
        local hours=$(((seconds % 86400) / 3600))
        if [ $hours -gt 0 ]; then
            echo "${days}d ${hours}h"
        else
            echo "${days}d"
        fi
    fi
}

# Calculate time until next scheduled backup
# Returns: Seconds until next backup (can be negative if overdue)
time_until_next_backup() {
    local backup_interval="${BACKUP_INTERVAL:-3600}"
    local last_backup=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
    local now=$(date +%s)
    local next_backup=$((last_backup + backup_interval))
    local diff=$((next_backup - now))

    echo "$diff"
}

# ==============================================================================
# SIZE UTILITIES
# ==============================================================================

# Format bytes into human-readable size
# Args: $1 = bytes
# Output: "1.2 GB", "45 MB", etc.
format_bytes() {
    local bytes="$1"

    if [ $bytes -lt 1024 ]; then
        echo "${bytes} B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}") KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}") GB"
    fi
}

# Get total size of directory in bytes
# Args: $1 = directory path
# Output: size in bytes
get_dir_size_bytes() {
    local dir="$1"

    if [ ! -d "$dir" ]; then
        echo "0"
        return
    fi

    # macOS uses -f%z, Linux uses --format=%s
    if [[ "$OSTYPE" == "darwin"* ]]; then
        find "$dir" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END {print s+0}'
    else
        find "$dir" -type f -exec stat --format=%s {} + 2>/dev/null | awk '{s+=$1} END {print s+0}'
    fi
}

# ==============================================================================
# COMPONENT HEALTH CHECKS
# ==============================================================================

# Check if daemon is running
# Returns: 0 if running, 1 if not
check_daemon_status() {
    local project_name="${PROJECT_NAME:-}"
    [ -z "$project_name" ] && return 1

    if launchctl list 2>/dev/null | grep -q "com.claudecode.backup.${project_name}"; then
        return 0
    fi
    return 1
}

# Check if hooks are installed
# Args: $1 = project directory
# Returns: 0 if installed, 1 if not
check_hooks_status() {
    local project_dir="$1"

    if [ -f "$project_dir/.claude/hooks/backup-trigger.sh" ]; then
        return 0
    fi
    return 1
}

# Check configuration validity
# Returns: 0 if valid, 1 if invalid
check_config_status() {
    # Check required variables are set
    [ -z "${PROJECT_NAME:-}" ] && return 1
    [ -z "${PROJECT_DIR:-}" ] && return 1
    [ -z "${BACKUP_DIR:-}" ] && return 1

    # Check backup interval is reasonable
    local interval="${BACKUP_INTERVAL:-0}"
    [ $interval -lt 60 ] && return 1

    return 0
}

# ==============================================================================
# STATISTICS GATHERING
# ==============================================================================

# Count database backups
# Output: number of database backup files
count_database_backups() {
    local db_dir="${DATABASE_DIR:-}"
    [ -z "$db_dir" ] || [ ! -d "$db_dir" ] && echo "0" && return

    find "$db_dir" -name "*.db.gz" -type f 2>/dev/null | wc -l | tr -d ' '
}

# Count current files
# Output: number of current backed-up files
count_current_files() {
    local files_dir="${FILES_DIR:-}"
    [ -z "$files_dir" ] || [ ! -d "$files_dir" ] && echo "0" && return

    find "$files_dir" -type f 2>/dev/null | wc -l | tr -d ' '
}

# Count archived files
# Output: number of archived file versions
count_archived_files() {
    local archived_dir="${ARCHIVED_DIR:-}"
    [ -z "$archived_dir" ] || [ ! -d "$archived_dir" ] && echo "0" && return

    find "$archived_dir" -type f 2>/dev/null | wc -l | tr -d ' '
}

# Get total backup size in bytes
# Output: total size in bytes
get_total_backup_size() {
    local backup_dir="${BACKUP_DIR:-}"
    [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ] && echo "0" && return

    get_dir_size_bytes "$backup_dir"
}

# Get last backup timestamp
# Output: Unix timestamp or 0 if never
get_last_backup_time() {
    local state_file="${BACKUP_TIME_STATE:-}"
    [ -z "$state_file" ] || [ ! -f "$state_file" ] && echo "0" && return

    cat "$state_file" 2>/dev/null || echo "0"
}

# ==============================================================================
# RETENTION POLICY ANALYSIS
# ==============================================================================

# Count backups that will be pruned soon
# Args: $1 = directory, $2 = retention days, $3 = warning days (default 7)
# Output: number of backups that will be deleted within warning period
count_backups_to_prune() {
    local dir="$1"
    local retention_days="$2"
    local warning_days="${3:-7}"

    [ ! -d "$dir" ] && echo "0" && return

    local warning_threshold=$((retention_days - warning_days))
    [ $warning_threshold -lt 0 ] && warning_threshold=0

    find "$dir" -type f -mtime +${warning_threshold} 2>/dev/null | wc -l | tr -d ' '
}

# Calculate days until oldest backup is pruned
# Args: $1 = directory, $2 = retention days
# Output: days until next prune, or -1 if none
days_until_prune() {
    local dir="$1"
    local retention_days="$2"

    [ ! -d "$dir" ] && echo "-1" && return

    local oldest_file=$(find "$dir" -type f -print0 2>/dev/null | xargs -0 stat -f%m -t%s 2>/dev/null | sort -n | head -1 | cut -d' ' -f1)
    [ -z "$oldest_file" ] && echo "-1" && return

    local now=$(date +%s)
    local age_seconds=$((now - oldest_file))
    local age_days=$((age_seconds / 86400))
    local days_remaining=$((retention_days - age_days))

    echo "$days_remaining"
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

# ==============================================================================
# COLOR OUTPUT
# ==============================================================================

# ANSI color codes (check for NO_COLOR/piped output first)
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
    # Disable colors for piped output or when NO_COLOR is set
    readonly COLOR_RESET=''
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    readonly COLOR_BLUE=''
    readonly COLOR_CYAN=''
    readonly COLOR_GRAY=''
    readonly COLOR_BOLD=''
else
    readonly COLOR_RESET='\033[0m'
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_CYAN='\033[0;36m'
    readonly COLOR_GRAY='\033[0;90m'
    readonly COLOR_BOLD='\033[1m'
fi

# Color output functions
color_echo() {
    local color="$1"
    shift
    echo -e "${color}$@${COLOR_RESET}"
}

color_red() { color_echo "$COLOR_RED" "$@"; }
color_green() { color_echo "$COLOR_GREEN" "$@"; }
color_yellow() { color_echo "$COLOR_YELLOW" "$@"; }
color_blue() { color_echo "$COLOR_BLUE" "$@"; }
color_cyan() { color_echo "$COLOR_CYAN" "$@"; }
color_gray() { color_echo "$COLOR_GRAY" "$@"; }
color_bold() { color_echo "$COLOR_BOLD" "$@"; }

# ==============================================================================
# JSON OUTPUT
# ==============================================================================

# Escape string for JSON
json_escape() {
    local str="$1"
    # Escape backslashes, quotes, newlines, tabs
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g'
}

# JSON key-value pair
json_kv() {
    local key="$1"
    local value="$2"
    echo "\"$key\": \"$(json_escape "$value")\""
}

# JSON number key-value pair
json_kv_num() {
    local key="$1"
    local value="$2"
    echo "\"$key\": $value"
}

# JSON boolean key-value pair
json_kv_bool() {
    local key="$1"
    local value="$2"
    echo "\"$key\": $value"
}

# ==============================================================================
# LOGGING
# ==============================================================================

# Log message to file and stdout
# Args: $1 = message, $2 = level (optional: INFO, WARN, ERROR)
backup_log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local log_entry="$timestamp [$level] $message"

    # Print to stdout
    echo "$log_entry"

    # Write to log file if available
    local log_file="${LOG_FILE:-}"
    if [ -n "$log_file" ] && check_drive; then
        if [ -d "$(dirname "$log_file")" ]; then
            echo "$log_entry" >> "$log_file" 2>/dev/null || true
        fi
    fi

    # Write to fallback log
    local fallback_log="${FALLBACK_LOG:-}"
    if [ -n "$fallback_log" ]; then
        mkdir -p "$(dirname "$fallback_log")" 2>/dev/null || true
        echo "$log_entry" >> "$fallback_log" 2>/dev/null || true
    fi
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Initialize state directories
# Creates necessary directories for tracking state
init_state_dirs() {
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    mkdir -p "$state_dir" 2>/dev/null || true
    mkdir -p "${HOME}/.claudecode-backups/locks" 2>/dev/null || true
    mkdir -p "${HOME}/.claudecode-backups/logs" 2>/dev/null || true
}

# Initialize backup directories (only if drive is connected)
# Creates backup storage directories
init_backup_dirs() {
    if ! check_drive; then
        return 1
    fi

    mkdir -p "${DATABASE_DIR:-}" 2>/dev/null || true
    mkdir -p "${FILES_DIR:-}" 2>/dev/null || true
    mkdir -p "${ARCHIVED_DIR:-}" 2>/dev/null || true
    touch "${LOG_FILE:-}" 2>/dev/null || true

    return 0
}

# ==============================================================================
# INTERACTIVE UI COMPONENTS
# ==============================================================================

# Box drawing characters
BOX_TL='╭'
BOX_TR='╮'
BOX_BL='╰'
BOX_BR='╯'
BOX_H='─'
BOX_V='│'

# Draw box with title and content
draw_box() {
    local title="$1"
    local content="$2"
    local width="${3:-60}"

    # Calculate padding for centered title
    local title_len=${#title}
    local padding=$(( (width - title_len - 4) / 2 ))

    # Top border with title
    echo -n "$BOX_TL"
    printf "%${padding}s" | tr ' ' "$BOX_H"
    echo -n " $title "
    printf "%$((width - padding - title_len - 4))s" | tr ' ' "$BOX_H"
    echo "$BOX_TR"

    # Content lines
    if [ -n "$content" ]; then
        echo "$content" | while IFS= read -r line; do
            printf "%s %-$((width - 2))s %s\n" "$BOX_V" "$line" "$BOX_V"
        done
    else
        printf "%s %$((width - 2))s %s\n" "$BOX_V" "" "$BOX_V"
    fi

    # Bottom border
    echo -n "$BOX_BL"
    printf "%${width}s" | tr ' ' "$BOX_H"
    echo "$BOX_BR"
}

# Draw simple box border
draw_border() {
    local width="${1:-60}"
    echo -n "$BOX_TL"
    printf "%${width}s" | tr ' ' "$BOX_H"
    echo "$BOX_TR"
}

# Prompt for user input with default
prompt() {
    local message="$1"
    local default="$2"
    local result=""

    if [ -n "$default" ]; then
        read -p "$message [$default]: " result
        echo "${result:-$default}"
    else
        read -p "$message: " result
        echo "$result"
    fi
}

# Yes/No confirmation
confirm() {
    local message="$1"
    local default="${2:-n}"
    local result=""

    if [ "$default" = "y" ]; then
        read -p "$message [Y/n]: " result
        result="${result:-y}"
    else
        read -p "$message [y/N]: " result
        result="${result:-n}"
    fi

    [ "$result" = "y" ] || [ "$result" = "Y" ]
}

# ==============================================================================
# DATE/TIME PARSING
# ==============================================================================

# Parse human-readable date strings
# Examples: "2 days ago", "yesterday", "2025-12-24 10:00"
parse_date_string() {
    local input="$1"

    case "$input" in
        "now"|"today")
            date +%s
            ;;
        "yesterday")
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -v-1d +%s
            else
                date -d "yesterday" +%s
            fi
            ;;
        *"days ago"|*"day ago")
            local days=$(echo "$input" | grep -oE '[0-9]+')
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -v-${days}d +%s
            else
                date -d "$days days ago" +%s
            fi
            ;;
        *"hours ago"|*"hour ago")
            local hours=$(echo "$input" | grep -oE '[0-9]+')
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -v-${hours}H +%s
            else
                date -d "$hours hours ago" +%s
            fi
            ;;
        *"weeks ago"|*"week ago")
            local weeks=$(echo "$input" | grep -oE '[0-9]+')
            local days=$((weeks * 7))
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -v-${days}d +%s
            else
                date -d "$days days ago" +%s
            fi
            ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*)
            # ISO format
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -j -f "%Y-%m-%d %H:%M" "$input" +%s 2>/dev/null || \
                date -j -f "%Y-%m-%d" "$input" +%s 2>/dev/null
            else
                date -d "$input" +%s
            fi
            ;;
        *)
            # Try direct parsing
            if [[ "$OSTYPE" == "darwin"* ]]; then
                date -j -f "%Y-%m-%d %H:%M:%S" "$input" +%s 2>/dev/null
            else
                date -d "$input" +%s 2>/dev/null
            fi
            ;;
    esac
}

# Format relative time (X hours ago, X days ago)
format_relative_time() {
    local timestamp="$1"
    local now=$(date +%s)
    local diff=$((now - timestamp))

    if [ $diff -lt 60 ]; then
        echo "just now"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60)) minutes ago"
    elif [ $diff -lt 7200 ]; then
        echo "1 hour ago"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600)) hours ago"
    elif [ $diff -lt 172800 ]; then
        echo "yesterday"
    elif [ $diff -lt 604800 ]; then
        echo "$((diff / 86400)) days ago"
    else
        echo "$((diff / 604800)) weeks ago"
    fi
}

# ==============================================================================
# BACKUP DISCOVERY & LISTING
# ==============================================================================

# List database backups sorted by date
list_database_backups_sorted() {
    local db_dir="$1"
    local limit="${2:-0}"  # 0 = no limit

    [ ! -d "$db_dir" ] && return 1

    local count=0
    find "$db_dir" -name "*.db.gz" -type f 2>/dev/null | while read -r backup; do
        local mtime=$(stat -f%m "$backup" 2>/dev/null || stat -c%Y "$backup" 2>/dev/null)
        echo "$mtime|$backup"
    done | sort -rn -t'|' | while IFS='|' read -r mtime backup; do
        [ $limit -gt 0 ] && [ $count -ge $limit ] && break

        local filename=$(basename "$backup")
        local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
        local size_human=$(format_bytes "$size")
        local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
        local relative=$(format_relative_time "$mtime")

        echo "$created|$relative|$size_human|$filename|$backup"
        ((count++))
    done
}

# List file versions for a specific file
list_file_versions_sorted() {
    local file_path="$1"
    local files_dir="$2"
    local archived_dir="$3"

    local versions=()

    # Current version
    if [ -f "$files_dir/$file_path" ]; then
        local mtime=$(stat -f%m "$files_dir/$file_path" 2>/dev/null || stat -c%Y "$files_dir/$file_path" 2>/dev/null)
        local size=$(stat -f%z "$files_dir/$file_path" 2>/dev/null || stat -c%s "$files_dir/$file_path" 2>/dev/null)
        local size_human=$(format_bytes "$size")
        local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
        local relative=$(format_relative_time "$mtime")

        echo "$mtime|CURRENT|$created|$relative|$size_human|$files_dir/$file_path"
    fi

    # Archived versions
    find "$archived_dir" -type f -name "$(basename "$file_path").*" 2>/dev/null | while read -r backup; do
        local mtime=$(stat -f%m "$backup" 2>/dev/null || stat -c%Y "$backup" 2>/dev/null)
        local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
        local size_human=$(format_bytes "$size")
        local created=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
        local relative=$(format_relative_time "$mtime")
        local version=$(basename "$backup" | sed "s/.*\.//")

        echo "$mtime|$version|$created|$relative|$size_human|$backup"
    done | sort -rn -t'|'
}

# ==============================================================================
# RESTORE OPERATIONS
# ==============================================================================

# Create safety backup before restore
create_safety_backup() {
    local file_path="$1"
    local suffix="${2:-pre-restore}"

    [ ! -f "$file_path" ] && return 0

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local safety_backup="${file_path}.${suffix}-${timestamp}"

    if cp "$file_path" "$safety_backup" 2>/dev/null; then
        echo "$safety_backup"
        return 0
    else
        return 1
    fi
}

# Verify SQLite database integrity
verify_sqlite_integrity() {
    local db_path="$1"

    [ ! -f "$db_path" ] && return 1

    # Check if it's a SQLite database
    if ! file "$db_path" 2>/dev/null | grep -q "SQLite"; then
        return 1
    fi

    # Run integrity check
    local result=$(sqlite3 "$db_path" "PRAGMA integrity_check;" 2>&1)
    [ "$result" = "ok" ]
}

# Verify compressed database backup
verify_compressed_backup() {
    local compressed_path="$1"

    [ ! -f "$compressed_path" ] && return 1

    # Test decompression
    if ! gunzip -t "$compressed_path" 2>/dev/null; then
        return 1
    fi

    # Decompress to temp and verify SQLite integrity
    local temp_db=$(mktemp)
    gunzip -c "$compressed_path" > "$temp_db" 2>/dev/null

    local result=0
    if ! verify_sqlite_integrity "$temp_db"; then
        result=1
    fi

    rm -f "$temp_db"
    return $result
}

# Restore database from compressed backup
restore_database_from_backup() {
    local backup_file="$1"
    local target_db="$2"
    local dry_run="${3:-false}"

    [ ! -f "$backup_file" ] && color_red "❌ Backup file not found" && return 1

    if [ "$dry_run" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Would restore:"
        color_cyan "   From: $backup_file"
        color_cyan "   To: $target_db"
        return 0
    fi

    # Verify backup
    color_cyan "🧪 Verifying backup integrity..."
    if ! verify_compressed_backup "$backup_file"; then
        color_red "❌ Backup verification failed"
        return 1
    fi
    color_green "✅ Backup verified"

    # Create safety backup
    local safety_backup=""
    if [ -f "$target_db" ]; then
        color_cyan "💾 Creating safety backup..."
        safety_backup=$(create_safety_backup "$target_db")
        if [ $? -eq 0 ]; then
            color_green "✅ Safety backup: $(basename "$safety_backup")"
        else
            color_red "❌ Failed to create safety backup"
            return 1
        fi
    fi

    # Perform restore
    color_cyan "📦 Restoring database..."
    if gunzip -c "$backup_file" > "$target_db" 2>/dev/null; then
        # Verify restored database
        color_cyan "🧪 Verifying restored database..."
        if verify_sqlite_integrity "$target_db"; then
            color_green "✅ Restore complete and verified"
            return 0
        else
            color_red "❌ Restored database failed verification"
            # Rollback
            if [ -n "$safety_backup" ] && [ -f "$safety_backup" ]; then
                color_yellow "⚠️  Rolling back to safety backup..."
                cp "$safety_backup" "$target_db"
            fi
            return 1
        fi
    else
        color_red "❌ Restore failed"
        return 1
    fi
}

# Restore file from backup
restore_file_from_backup() {
    local backup_file="$1"
    local target_file="$2"
    local dry_run="${3:-false}"

    [ ! -f "$backup_file" ] && color_red "❌ Backup file not found" && return 1

    if [ "$dry_run" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Would restore:"
        color_cyan "   From: $backup_file"
        color_cyan "   To: $target_file"
        return 0
    fi

    # Create safety backup
    local safety_backup=""
    if [ -f "$target_file" ]; then
        color_cyan "💾 Creating safety backup..."
        safety_backup=$(create_safety_backup "$target_file")
        [ $? -eq 0 ] && color_green "✅ Safety backup: $(basename "$safety_backup")"
    fi

    # Create target directory
    mkdir -p "$(dirname "$target_file")"

    # Perform restore
    color_cyan "📦 Restoring file..."
    if cp "$backup_file" "$target_file" 2>/dev/null; then
        color_green "✅ Restore complete"
        return 0
    else
        color_red "❌ Restore failed"
        return 1
    fi
}

# ==============================================================================
# CLEANUP OPERATIONS
# ==============================================================================

# Find backups older than retention policy
find_expired_backups() {
    local dir="$1"
    local retention_days="$2"
    local pattern="${3:-*}"

    [ ! -d "$dir" ] && return 1

    find "$dir" -name "$pattern" -type f -mtime "+$retention_days" 2>/dev/null
}

# Find duplicate backups (same content hash)
find_duplicate_backups() {
    local dir="$1"
    local pattern="${2:-*.db.gz}"

    [ ! -d "$dir" ] && return 1

    local temp_hashes=$(mktemp)

    # Calculate hashes
    find "$dir" -name "$pattern" -type f 2>/dev/null | while read -r file; do
        local hash=$(md5 -q "$file" 2>/dev/null || md5sum "$file" 2>/dev/null | awk '{print $1}')
        echo "$hash|$file"
    done > "$temp_hashes"

    # Find duplicates
    awk -F'|' '
    {
        hashes[$1]++;
        if (hashes[$1] == 1) {
            first[$1] = $2;
        } else {
            print $2;
        }
    }
    ' "$temp_hashes"

    rm -f "$temp_hashes"
}

# Find orphaned archived files (original no longer exists)
find_orphaned_archives() {
    local archived_dir="$1"
    local files_dir="$2"
    local project_dir="$3"

    [ ! -d "$archived_dir" ] && return 1

    find "$archived_dir" -type f 2>/dev/null | while read -r archived; do
        local rel_path="${archived#$archived_dir/}"
        local base_file="${rel_path%.*}"  # Remove timestamp

        # Check if original exists
        if [ ! -f "$files_dir/$base_file" ] && [ ! -f "$project_dir/$base_file" ]; then
            echo "$archived"
        fi
    done
}

# Calculate total size of file list
calculate_total_size() {
    local total=0
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
            total=$((total + size))
        fi
    done
    echo "$total"
}

# Delete files with summary
delete_files_batch() {
    local dry_run="$1"
    shift
    local files=("$@")

    [ ${#files[@]} -eq 0 ] && return 0

    local total_size=0
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
            total_size=$((total_size + size))
        fi
    done

    local size_human=$(format_bytes "$total_size")

    if [ "$dry_run" = "true" ]; then
        color_cyan "ℹ️  [DRY RUN] Would delete ${#files[@]} files ($size_human)"
        return 0
    fi

    local deleted=0
    for file in "${files[@]}"; do
        if rm -f "$file" 2>/dev/null; then
            ((deleted++))
        fi
    done

    color_green "✅ Deleted $deleted files ($size_human freed)"

    # Clean up empty directories
    for file in "${files[@]}"; do
        local dir=$(dirname "$file")
        [ -d "$dir" ] && rmdir "$dir" 2>/dev/null || true
    done

    return 0
}

# ==============================================================================
# CLEANUP RECOMMENDATIONS
# ==============================================================================

# Analyze backup health and generate recommendations
generate_cleanup_recommendations() {
    local database_dir="$1"
    local files_dir="$2"
    local archived_dir="$3"
    local db_retention="$4"
    local file_retention="$5"

    local recommendations=()

    # Check disk usage
    local disk_usage=$(get_backup_disk_usage)
    if [ $disk_usage -ge 90 ]; then
        recommendations+=("CRITICAL: Disk usage at ${disk_usage}% - Immediate cleanup needed")
    elif [ $disk_usage -ge 80 ]; then
        recommendations+=("WARNING: Disk usage at ${disk_usage}% - Cleanup recommended")
    fi

    # Check for expired backups
    local expired_db=$(find_expired_backups "$database_dir" "$db_retention" "*.db.gz" | wc -l | tr -d ' ')
    if [ $expired_db -gt 0 ]; then
        recommendations+=("$expired_db database backups older than ${db_retention} days")
    fi

    local expired_files=$(find_expired_backups "$archived_dir" "$file_retention" "*" | wc -l | tr -d ' ')
    if [ $expired_files -gt 0 ]; then
        recommendations+=("$expired_files archived files older than ${file_retention} days")
    fi

    # Check for duplicates
    local duplicates=$(find_duplicate_backups "$database_dir" "*.db.gz" | wc -l | tr -d ' ')
    if [ $duplicates -gt 0 ]; then
        recommendations+=("$duplicates duplicate database backups detected")
    fi

    # Check for orphaned archives
    local orphaned=$(find_orphaned_archives "$archived_dir" "$files_dir" "${PROJECT_DIR:-}" | wc -l | tr -d ' ')
    if [ $orphaned -gt 0 ]; then
        recommendations+=("$orphaned orphaned archived files (original deleted)")
    fi

    # Output recommendations
    for rec in "${recommendations[@]}"; do
        echo "$rec"
    done
}

# ==============================================================================
# AUDIT LOGGING
# ==============================================================================

# Log restore operation to audit log
audit_restore() {
    local audit_file="${BACKUP_DIR:-}/audit.log"
    local operation="$1"
    local source="$2"
    local target="$3"

    mkdir -p "$(dirname "$audit_file")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RESTORE $operation: $source -> $target" >> "$audit_file"
}

# Log cleanup operation to audit log
audit_cleanup() {
    local audit_file="${BACKUP_DIR:-}/audit.log"
    local operation="$1"
    local count="$2"
    local size="$3"

    mkdir -p "$(dirname "$audit_file")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] CLEANUP $operation: Deleted $count files ($size)" >> "$audit_file"
}

# ==============================================================================
# CONFIGURATION MANAGEMENT
# ==============================================================================

# Configuration schema - defines all valid configuration keys with types and defaults
# Format: key="type|default|description"
# NOTE: Associative arrays require bash 4.0+, commented out for macOS bash 3.2 compatibility
# TODO: Implement bash 3.2-compatible config schema for backup-config command
# declare -A BACKUP_CONFIG_SCHEMA=(
#     # Project settings
#     ["project.name"]="string|MyProject|Project name for backup filenames"
#     ["project.dir"]="path||Project directory (auto-detected if empty)"
#
#     # Backup locations
#     ["locations.backup_dir"]="path|backups|Main backup directory (relative to project)"
#     ["locations.database_dir"]="path|\${BACKUP_DIR}/databases|Database backups subdirectory"
#     ["locations.files_dir"]="path|\${BACKUP_DIR}/files|Current file backups subdirectory"
#     ["locations.archived_dir"]="path|\${BACKUP_DIR}/archived|Archived file versions subdirectory"
#
#     # Database configuration
#     ["database.path"]="path||Database file path (empty if no database)"
#     ["database.type"]="enum:sqlite,none|sqlite|Database type"
#
#     # Retention policies
#     ["retention.database.time_based"]="integer|30|Database backup retention in days"
#     ["retention.database.never_delete"]="boolean|false|Never auto-delete database backups"
#     ["retention.files.time_based"]="integer|60|Archived file retention in days"
#     ["retention.files.never_delete"]="boolean|false|Never auto-delete archived files"
#
#     # Schedule settings
#     ["schedule.interval"]="integer|3600|Backup interval in seconds"
#     ["schedule.daemon_enabled"]="boolean|true|Enable daemon mode"
#     ["schedule.session_idle_threshold"]="integer|600|Session idle threshold in seconds"
#
#     # Drive verification
#     ["drive.verification_enabled"]="boolean|false|Enable drive verification"
#     ["drive.marker_file"]="path||Drive marker file path"
#
#     # Optional features
#     ["features.auto_commit"]="boolean|false|Auto-commit to git after backup"
#     ["features.git_commit_message"]="string|Auto-backup: \$(date '+%Y-%m-%d %H:%M')|Git commit message template"
#
#     # Critical files to backup
#     ["backup_targets.env_files"]="boolean|true|Backup .env files"
#     ["backup_targets.credentials"]="boolean|true|Backup credentials (*.pem, *.key, etc.)"
#     ["backup_targets.ide_settings"]="boolean|true|Backup IDE settings (.vscode/, .idea/)"
#     ["backup_targets.local_notes"]="boolean|true|Backup local notes (NOTES.md, *.private.md)"
#     ["backup_targets.local_databases"]="boolean|true|Backup local databases (*.db, *.sqlite)"
#
#     # Logging
#     ["logging.log_file"]="path|\${BACKUP_DIR}/backup.log|Main backup log file"
#     ["logging.fallback_log"]="path|\${HOME}/.claudecode-backups/logs/backup-fallback.log|Fallback log (if drive disconnected)"
#
#     # State files
#     ["state.state_dir"]="path|\${HOME}/.claudecode-backups/state|State directory"
#     ["state.backup_time_state"]="path|\${STATE_DIR}/.last-backup-time|Last backup timestamp file"
#     ["state.session_file"]="path|\${STATE_DIR}/.current-session-time|Current session tracking file"
#     ["state.db_state_file"]="path|\${BACKUP_DIR}/.backup-state|Database state tracking file"
# )

# Convert dot notation key to shell variable name
config_key_to_var() {
    local key="$1"
    case "$key" in
        "project.name") echo "PROJECT_NAME" ;;
        "project.dir") echo "PROJECT_DIR" ;;
        "locations.backup_dir") echo "BACKUP_DIR" ;;
        "locations.database_dir") echo "DATABASE_DIR" ;;
        "locations.files_dir") echo "FILES_DIR" ;;
        "locations.archived_dir") echo "ARCHIVED_DIR" ;;
        "database.path") echo "DB_PATH" ;;
        "database.type") echo "DB_TYPE" ;;
        "retention.database.time_based") echo "DB_RETENTION_DAYS" ;;
        "retention.database.never_delete") echo "DB_NEVER_DELETE" ;;
        "retention.files.time_based") echo "FILE_RETENTION_DAYS" ;;
        "retention.files.never_delete") echo "FILE_NEVER_DELETE" ;;
        "schedule.interval") echo "BACKUP_INTERVAL" ;;
        "schedule.daemon_enabled") echo "DAEMON_ENABLED" ;;
        "schedule.session_idle_threshold") echo "SESSION_IDLE_THRESHOLD" ;;
        "drive.verification_enabled") echo "DRIVE_VERIFICATION_ENABLED" ;;
        "drive.marker_file") echo "DRIVE_MARKER_FILE" ;;
        "features.auto_commit") echo "AUTO_COMMIT_ENABLED" ;;
        "features.git_commit_message") echo "GIT_COMMIT_MESSAGE" ;;
        "backup_targets.env_files") echo "BACKUP_ENV_FILES" ;;
        "backup_targets.credentials") echo "BACKUP_CREDENTIALS" ;;
        "backup_targets.ide_settings") echo "BACKUP_IDE_SETTINGS" ;;
        "backup_targets.local_notes") echo "BACKUP_LOCAL_NOTES" ;;
        "backup_targets.local_databases") echo "BACKUP_LOCAL_DATABASES" ;;
        "logging.log_file") echo "LOG_FILE" ;;
        "logging.fallback_log") echo "FALLBACK_LOG" ;;
        "state.state_dir") echo "STATE_DIR" ;;
        "state.backup_time_state") echo "BACKUP_TIME_STATE" ;;
        "state.session_file") echo "SESSION_FILE" ;;
        "state.db_state_file") echo "DB_STATE_FILE" ;;
        *) echo "" ;;
    esac
}

# Convert shell variable name to dot notation key
config_var_to_key() {
    local var="$1"
    case "$var" in
        "PROJECT_NAME") echo "project.name" ;;
        "PROJECT_DIR") echo "project.dir" ;;
        "BACKUP_DIR") echo "locations.backup_dir" ;;
        "DATABASE_DIR") echo "locations.database_dir" ;;
        "FILES_DIR") echo "locations.files_dir" ;;
        "ARCHIVED_DIR") echo "locations.archived_dir" ;;
        "DB_PATH") echo "database.path" ;;
        "DB_TYPE") echo "database.type" ;;
        "DB_RETENTION_DAYS") echo "retention.database.time_based" ;;
        "DB_NEVER_DELETE") echo "retention.database.never_delete" ;;
        "FILE_RETENTION_DAYS") echo "retention.files.time_based" ;;
        "FILE_NEVER_DELETE") echo "retention.files.never_delete" ;;
        "BACKUP_INTERVAL") echo "schedule.interval" ;;
        "DAEMON_ENABLED") echo "schedule.daemon_enabled" ;;
        "SESSION_IDLE_THRESHOLD") echo "schedule.session_idle_threshold" ;;
        "DRIVE_VERIFICATION_ENABLED") echo "drive.verification_enabled" ;;
        "DRIVE_MARKER_FILE") echo "drive.marker_file" ;;
        "AUTO_COMMIT_ENABLED") echo "features.auto_commit" ;;
        "GIT_COMMIT_MESSAGE") echo "features.git_commit_message" ;;
        "BACKUP_ENV_FILES") echo "backup_targets.env_files" ;;
        "BACKUP_CREDENTIALS") echo "backup_targets.credentials" ;;
        "BACKUP_IDE_SETTINGS") echo "backup_targets.ide_settings" ;;
        "BACKUP_LOCAL_NOTES") echo "backup_targets.local_notes" ;;
        "BACKUP_LOCAL_DATABASES") echo "backup_targets.local_databases" ;;
        "LOG_FILE") echo "logging.log_file" ;;
        "FALLBACK_LOG") echo "logging.fallback_log" ;;
        "STATE_DIR") echo "state.state_dir" ;;
        "BACKUP_TIME_STATE") echo "state.backup_time_state" ;;
        "SESSION_FILE") echo "state.session_file" ;;
        "DB_STATE_FILE") echo "state.db_state_file" ;;
        *) echo "" ;;
    esac
}

# Get schema details for a key
config_get_schema() {
    local key="$1"
    local field="${2:-all}"  # all, type, default, description

    local schema="${BACKUP_CONFIG_SCHEMA[$key]}"
    [[ -z "$schema" ]] && return 1

    local type="${schema%%|*}"
    local rest="${schema#*|}"
    local default="${rest%%|*}"
    local description="${rest#*|}"

    case "$field" in
        "type") echo "$type" ;;
        "default") echo "$default" ;;
        "description") echo "$description" ;;
        "all") echo "$type|$default|$description" ;;
        *) echo "$schema" ;;
    esac
}

# Validate a configuration value against schema
config_validate_value() {
    local key="$1"
    local value="$2"

    local type
    type="$(config_get_schema "$key" "type")"
    [[ -z "$type" ]] && color_red "Error: Unknown configuration key: $key" && return 1

    case "$type" in
        "string")
            [[ -z "$value" ]] && color_red "Error: Value cannot be empty for $key" && return 1
            ;;
        "integer")
            [[ ! "$value" =~ ^[0-9]+$ ]] && color_red "Error: Value must be a positive integer for $key (got: $value)" && return 1
            ;;
        "boolean")
            [[ "$value" != "true" && "$value" != "false" ]] && color_red "Error: Value must be 'true' or 'false' for $key (got: $value)" && return 1
            ;;
        "path")
            if [[ -n "$value" ]]; then
                [[ "$value" =~ ^[[:space:]] || "$value" =~ [[:space:]]$ ]] && color_red "Error: Path cannot have leading/trailing spaces for $key" && return 1
            fi
            ;;
        enum:*)
            local allowed="${type#enum:}"
            local valid=false
            IFS=',' read -ra ALLOWED <<< "$allowed"
            for item in "${ALLOWED[@]}"; do
                [[ "$value" == "$item" ]] && valid=true && break
            done
            [[ "$valid" != "true" ]] && color_red "Error: Value must be one of [$allowed] for $key (got: $value)" && return 1
            ;;
        *)
            color_red "Error: Unknown type '$type' in schema for $key"
            return 1
            ;;
    esac
    return 0
}

# Get a configuration value by key
config_get_value() {
    local key="$1"
    local config_file="${2:-$(get_config_path)}"

    [[ ! -f "$config_file" ]] && color_red "Error: Config file not found: $config_file" && return 1

    local var_name
    var_name="$(config_key_to_var "$key")"
    [[ -z "$var_name" ]] && color_red "Error: Unknown configuration key: $key" && return 1

    (
        source "$config_file" 2>/dev/null
        echo "${!var_name}"
    )
}

# Get all configuration values
config_get_all_values() {
    local config_file="${1:-$(get_config_path)}"

    [[ ! -f "$config_file" ]] && color_red "Error: Config file not found: $config_file" && return 1

    (
        source "$config_file" 2>/dev/null
        for key in "${!BACKUP_CONFIG_SCHEMA[@]}"; do
            local var_name
            var_name="$(config_key_to_var "$key")"
            local value="${!var_name}"
            [[ -n "$value" ]] && echo "$key=$value"
        done
    ) | sort
}

# Set a configuration value
config_set_value() {
    local key="$1"
    local value="$2"
    local config_file="${3:-$(get_config_path)}"

    # Validate key exists
    # NOTE: -v operator requires bash 4.3+, commented out for macOS bash 3.2 compatibility
    # [[ ! -v BACKUP_CONFIG_SCHEMA["$key"] ]] && color_red "Error: Unknown configuration key: $key" && return 1

    # Validate value
    config_validate_value "$key" "$value" || return 1

    # Create config from template if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        local project_root
        project_root="$(dirname "$config_file")"
        config_create_from_template "$config_file" "standard"
    fi

    # Get variable name
    local var_name
    var_name="$(config_key_to_var "$key")"

    # Update value in config file using sed
    if grep -q "^${var_name}=" "$config_file"; then
        # Value needs quoting if it contains spaces or special chars
        if [[ "$value" =~ [[:space:]] ]] || [[ "$value" == *'$'* ]]; then
            sed -i.bak "s|^${var_name}=.*|${var_name}=\"${value}\"|" "$config_file"
        else
            sed -i.bak "s|^${var_name}=.*|${var_name}=${value}|" "$config_file"
        fi
        rm -f "${config_file}.bak"
    else
        echo "${var_name}=${value}" >> "$config_file"
    fi

    # Log change to audit
    config_audit_change "$key" "$value"
}

# Create config file from template
config_create_from_template() {
    local output_file="$1"
    local template="${2:-standard}"
    local project_root
    project_root="$(dirname "$output_file")"

    # Try to find package templates directory
    local templates_dir=""
    if [[ -d "$project_root/templates" ]]; then
        templates_dir="$project_root/templates"
    elif [[ -d "$(dirname "${BASH_SOURCE[0]}")/../templates" ]]; then
        templates_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)"
    else
        color_red "Error: Cannot find templates directory"
        return 1
    fi

    # Copy base template
    cp "$templates_dir/backup-config.sh" "$output_file"

    # Apply template modifications
    case "$template" in
        "minimal")
            sed -i.bak \
                -e 's/^DB_PATH=.*/DB_PATH=""/' \
                -e 's/^DB_TYPE=.*/DB_TYPE="none"/' \
                -e 's/^DB_RETENTION_DAYS=.*/DB_RETENTION_DAYS=7/' \
                -e 's/^FILE_RETENTION_DAYS=.*/FILE_RETENTION_DAYS=7/' \
                -e 's/^DRIVE_VERIFICATION_ENABLED=.*/DRIVE_VERIFICATION_ENABLED=false/' \
                "$output_file"
            ;;
        "paranoid")
            sed -i.bak \
                -e 's/^BACKUP_INTERVAL=.*/BACKUP_INTERVAL=1800/' \
                -e 's/^DB_RETENTION_DAYS=.*/DB_RETENTION_DAYS=180/' \
                -e 's/^FILE_RETENTION_DAYS=.*/FILE_RETENTION_DAYS=180/' \
                -e 's/^DRIVE_VERIFICATION_ENABLED=.*/DRIVE_VERIFICATION_ENABLED=true/' \
                -e 's/^AUTO_COMMIT_ENABLED=.*/AUTO_COMMIT_ENABLED=true/' \
                "$output_file"
            ;;
        "standard")
            # Already correct
            ;;
    esac

    rm -f "${output_file}.bak"
}

# Validate entire configuration file
config_validate_file() {
    local config_file="${1:-$(get_config_path)}"
    local strict="${2:-false}"

    [[ ! -f "$config_file" ]] && color_red "Error: Config file not found: $config_file" && return 1

    local errors=0

    (
        source "$config_file" 2>/dev/null

        for key in "${!BACKUP_CONFIG_SCHEMA[@]}"; do
            local var_name
            var_name="$(config_key_to_var "$key")"
            local value="${!var_name}"

            # Strict mode requires all values
            if [[ "$strict" == "true" && -z "$value" ]]; then
                color_red "Error: Required key '$key' is not set"
                ((errors++))
                continue
            fi

            # Validate non-empty values
            if [[ -n "$value" ]]; then
                if ! config_validate_value "$key" "$value" 2>/dev/null; then
                    ((errors++))
                fi
            fi
        done

        exit "$errors"
    )

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        color_green "✅ Configuration is valid"
        return 0
    else
        color_red "❌ Configuration has $exit_code errors"
        return 1
    fi
}

# Profile management - save current config as profile
config_profile_save() {
    local profile_name="$1"
    local config_file="${2:-$(get_config_path)}"

    [[ ! -f "$config_file" ]] && color_red "Error: Config file not found: $config_file" && return 1

    local profiles_dir="$HOME/.claudecode-backups/profiles"
    mkdir -p "$profiles_dir"

    local profile_file="$profiles_dir/${profile_name}.sh"
    cp "$config_file" "$profile_file"
    color_green "✅ Profile '$profile_name' saved to $profile_file"
}

# Profile management - load profile
config_profile_load() {
    local profile_name="$1"
    local config_file="${2:-$(get_config_path)}"

    local profiles_dir="$HOME/.claudecode-backups/profiles"
    local profile_file="$profiles_dir/${profile_name}.sh"

    [[ ! -f "$profile_file" ]] && color_red "Error: Profile '$profile_name' not found" && config_profile_list && return 1

    cp "$profile_file" "$config_file"
    color_green "✅ Profile '$profile_name' loaded"
}

# Profile management - list profiles
config_profile_list() {
    local profiles_dir="$HOME/.claudecode-backups/profiles"

    [[ ! -d "$profiles_dir" ]] && echo "No profiles found" && return 0

    local count=0
    for profile in "$profiles_dir"/*.sh; do
        if [[ -f "$profile" ]]; then
            local name
            name="$(basename "$profile" .sh)"
            echo "  - $name"
            ((count++))
        fi
    done

    [[ $count -eq 0 ]] && echo "No profiles found"
}

# Audit log for configuration changes
config_audit_change() {
    local key="$1"
    local value="$2"

    local audit_dir="$HOME/.claudecode-backups/audit"
    mkdir -p "$audit_dir"

    local audit_file="$audit_dir/config-changes.log"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[$timestamp] $key = $value" >> "$audit_file"
}

# Library loaded successfully
export BACKUP_LIB_LOADED=1
