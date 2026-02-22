#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Backup State Tracking
# ==============================================================================
# @requires: core/error-codes (for get_error_description, get_error_suggestion, format_error_with_fix)
# @requires: core/output (for color functions, json helpers)
# @requires: core/config (for NOTIFY_*, QUIET_HOURS settings, should_notify)
# @provides: send_notification, notify_backup_failure, notify_backup_success,
#            notify_backup_warning, init_backup_state, add_file_failure,
#            add_database_failure, calculate_severity, requires_immediate_action,
#            get_severity_reason, write_backup_state, read_backup_state,
#            show_backup_failures
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_STATE:-}" ] && return || readonly _CHECKPOINT_STATE=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ==============================================================================
# PROJECT STATE IDENTITY (Fix: same-basename collision prevention)
# ==============================================================================
# Returns a unique state subdirectory name for the current project.
# Uses PROJECT_NAME + first 8 chars of .checkpoint-id (if it exists) to avoid
# collisions between projects with the same basename in different directories.
# Falls back to PROJECT_NAME alone for backward compatibility.
get_project_state_id() {
    local project_dir="${1:-${PROJECT_DIR:-$PWD}}"
    local project_name="${2:-${PROJECT_NAME:-$(basename "$project_dir")}}"
    local id_file="$project_dir/.checkpoint-id"

    if [ -f "$id_file" ]; then
        local project_id
        project_id=$(cat "$id_file" 2>/dev/null)
        if [ -n "$project_id" ]; then
            local short_id="${project_id:0:8}"
            echo "${project_name}-${short_id}"
            return 0
        fi
    fi
    # Fallback: use project name only (backward compatible)
    echo "$project_name"
}

# ==============================================================================
# NOTIFICATION SYSTEM
# ==============================================================================

# Send native macOS notification
# Args: $1 = title, $2 = message, $3 = sound (optional), $4 = urgency (optional: critical, high, medium, low)
send_notification() {
    local title="$1"
    local message="$2"
    local sound="${3:-default}"
    local urgency="${4:-medium}"

    # Only send if notifications are enabled (default: true)
    if [ "${NOTIFICATIONS_ENABLED:-true}" = false ]; then
        return 0
    fi

    # Check if should notify (quiet hours, preferences)
    if ! should_notify "$urgency"; then
        # Log suppressed notification
        echo "[$(date)] Notification suppressed (quiet hours): $title" >> "${BACKUP_LOG_FILE:-/dev/null}" 2>/dev/null || true
        return 0
    fi

    # Handle sound preference
    if [[ "${NOTIFY_SOUND:-default}" == "none" ]]; then
        sound=""
    elif [[ "${NOTIFY_SOUND:-default}" != "default" ]]; then
        sound="${NOTIFY_SOUND}"
    fi

    # Use osascript for native macOS notifications (no dependencies)
    if [[ -n "$sound" ]]; then
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
    else
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    fi
}

# Send backup failure notification (with spam prevention + escalation)
# Args: $1 = error count, $2 = total files attempted, $3 = files succeeded, $4 = first error code (optional)
notify_backup_failure() {
    local error_count="$1"
    local total_files="${2:-0}"
    local succeeded_files="${3:-0}"
    local first_error_code="${4:-EUNK000}"
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    local project_name="${PROJECT_NAME:-unknown}"
    local project_state_dir="$state_dir/$project_name"
    local failure_state="$project_state_dir/.last-backup-failed"
    local failure_log="$project_state_dir/.last-backup-failures"

    # Check if error notifications enabled
    if [[ "${NOTIFY_ON_ERROR:-true}" != "true" ]]; then
        return 0
    fi

    mkdir -p "$project_state_dir" 2>/dev/null || { log_debug "Failed to create project state dir: $project_state_dir"; true; }

    # Generate LLM-ready prompt from failure log
    local llm_prompt=""
    if [ -f "$failure_log" ]; then
        llm_prompt="Fix these Checkpoint backup failures:\n\n"
        while IFS='|' read -r file error_type suggested_fix; do
            llm_prompt+="File: $file\nError: $error_type\nFix: $suggested_fix\n\n"
        done < "$failure_log"
    fi

    # Get actionable fix for first error
    local first_fix
    first_fix=$(get_error_suggestion "$first_error_code")
    local error_desc
    error_desc=$(get_error_description "$first_error_code")

    # Check if this is a new failure or escalation
    if [ ! -f "$failure_state" ]; then
        # FIRST FAILURE - notify immediately with details and actionable fix
        local summary="$succeeded_files/$total_files files backed up. $error_count FAILED."

        # Include first actionable fix in notification (truncated for display)
        local short_fix="${first_fix:0:50}"
        [[ ${#first_fix} -gt 50 ]] && short_fix="${short_fix}..."

        send_notification \
            "⚠️ Checkpoint Backup Incomplete" \
            "${PROJECT_NAME}: $summary Fix: $short_fix" \
            "Basso" \
            "critical"

        # Mark as failed with timestamp, counts, error code, and LLM prompt
        echo "$(date +%s)|$error_count|$succeeded_files|$total_files|$first_error_code|$llm_prompt" > "$failure_state"

        # Also write LLM prompt to separate file for easy access
        echo "$llm_prompt" > "$project_state_dir/.last-backup-llm-prompt"
    else
        # EXISTING FAILURE - check if we should escalate
        local first_failure_time
        first_failure_time=$(cat "$failure_state" 2>/dev/null | cut -d'|' -f1)
        local now
        now=$(date +%s)
        local time_since_first=$((now - first_failure_time))

        # Use configurable escalation interval (default 3 hours)
        local escalation_hours=${NOTIFY_ESCALATION_HOURS:-3}
        local escalation_interval=$((escalation_hours * 3600))
        local escalation_marker="$project_state_dir/.last-backup-escalation"
        local last_escalation=0

        if [ -f "$escalation_marker" ]; then
            last_escalation=$(cat "$escalation_marker" 2>/dev/null || echo "0")
        fi

        local time_since_escalation=$((now - last_escalation))

        if [ $time_since_escalation -ge $escalation_interval ]; then
            # ESCALATION - remind user with error code and fix
            local short_fix="${first_fix:0:40}"
            [[ ${#first_fix} -gt 40 ]] && short_fix="${short_fix}..."

            send_notification \
                "🚨 Checkpoint Still Incomplete" \
                "${PROJECT_NAME}: $first_error_code for $((time_since_first / 3600))h. $short_fix" \
                "Basso" \
                "high"

            echo "$now" > "$escalation_marker"
        fi
    fi
}

# Send backup success notification (only after previous failure)
# Clears failure state and notifies user backup is restored
notify_backup_success() {
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    local project_name="${PROJECT_NAME:-unknown}"
    local project_state_dir="$state_dir/$project_name"
    local failure_state="$project_state_dir/.last-backup-failed"
    local escalation_marker="$project_state_dir/.last-backup-escalation"
    local failure_log="$project_state_dir/.last-backup-failures"

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
# BACKUP STATE TRACKING (JSON)
# ==============================================================================

# Global state tracking variables
declare -a BACKUP_STATE_FAILURES=()
BACKUP_STATE_TOTAL_FILES=0
BACKUP_STATE_SUCCEEDED_FILES=0
BACKUP_STATE_FAILED_FILES=0
BACKUP_STATE_TOTAL_DBS=0
BACKUP_STATE_SUCCEEDED_DBS=0
BACKUP_STATE_FAILED_DBS=0

# Initialize backup state tracking
init_backup_state() {
    BACKUP_STATE_FAILURES=()
    BACKUP_STATE_TOTAL_FILES=0
    BACKUP_STATE_SUCCEEDED_FILES=0
    BACKUP_STATE_FAILED_FILES=0
    BACKUP_STATE_TOTAL_DBS=0
    BACKUP_STATE_SUCCEEDED_DBS=0
    BACKUP_STATE_FAILED_DBS=0
}

# Add file failure to state
# Args: $1 = file path, $2 = error_code, $3 = error_message, $4 = suggested_fix, $5 = retry_count
add_file_failure() {
    local file="$1"
    local error_code="$2"
    local error_message="${3:-Unknown error}"
    local suggested_fix="$4"
    local retry_count="${5:-3}"

    # Escape for JSON
    file=$(echo "$file" | sed 's/\\/\\\\/g; s/"/\\"/g')
    error_message=$(echo "$error_message" | sed 's/\\/\\\\/g; s/"/\\"/g')
    suggested_fix=$(echo "$suggested_fix" | sed 's/\\/\\\\/g; s/"/\\"/g')

    local failure_json="{\"type\":\"file\",\"path\":\"$file\",\"error_code\":\"$error_code\",\"error_message\":\"$error_message\",\"suggested_fix\":\"$suggested_fix\",\"retry_count\":$retry_count}"

    BACKUP_STATE_FAILURES+=("$failure_json")
    BACKUP_STATE_FAILED_FILES=$((BACKUP_STATE_FAILED_FILES + 1))
}

# Add database failure to state
# Args: $1 = db path, $2 = error_code, $3 = error_message, $4 = suggested_fix
add_database_failure() {
    local db_path="$1"
    local error_code="$2"
    local error_message="${3:-Unknown error}"
    local suggested_fix="$4"

    # Escape for JSON
    db_path=$(echo "$db_path" | sed 's/\\/\\\\/g; s/"/\\"/g')
    error_message=$(echo "$error_message" | sed 's/\\/\\\\/g; s/"/\\"/g')
    suggested_fix=$(echo "$suggested_fix" | sed 's/\\/\\\\/g; s/"/\\"/g')

    local failure_json="{\"type\":\"database\",\"path\":\"$db_path\",\"error_code\":\"$error_code\",\"error_message\":\"$error_message\",\"suggested_fix\":\"$suggested_fix\"}"

    BACKUP_STATE_FAILURES+=("$failure_json")
    BACKUP_STATE_FAILED_DBS=$((BACKUP_STATE_FAILED_DBS + 1))
}

# Calculate severity level based on failures
# Returns: critical, high, medium, low
calculate_severity() {
    local total_items=$((BACKUP_STATE_TOTAL_FILES + BACKUP_STATE_TOTAL_DBS))
    local failed_items=$((BACKUP_STATE_FAILED_FILES + BACKUP_STATE_FAILED_DBS))

    # No failures
    if [ $failed_items -eq 0 ]; then
        echo "none"
        return
    fi

    # Check for critical error types
    for failure in "${BACKUP_STATE_FAILURES[@]}"; do
        if echo "$failure" | grep -q '"error_code":"disk_full"'; then
            echo "critical"
            return
        fi
        if echo "$failure" | grep -q '"error_code":"drive_disconnected"'; then
            echo "high"
            return
        fi
    done

    # Calculate failure percentage
    local failure_percent=$((failed_items * 100 / total_items))

    if [ $failure_percent -ge 50 ]; then
        echo "high"  # More than half failed
    elif [ $failure_percent -ge 10 ]; then
        echo "medium"  # 10-50% failed
    else
        echo "low"  # Less than 10% failed
    fi
}

# Determine if immediate action required
requires_immediate_action() {
    local severity=$(calculate_severity)

    case "$severity" in
        critical|high)
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Get human-readable reason for severity
get_severity_reason() {
    local severity=$(calculate_severity)
    local total_items=$((BACKUP_STATE_TOTAL_FILES + BACKUP_STATE_TOTAL_DBS))
    local failed_items=$((BACKUP_STATE_FAILED_FILES + BACKUP_STATE_FAILED_DBS))

    # Check for specific error types
    for failure in "${BACKUP_STATE_FAILURES[@]}"; do
        if echo "$failure" | grep -q '"error_code":"disk_full"'; then
            echo "Disk full - no space for backups"
            return
        fi
        if echo "$failure" | grep -q '"error_code":"drive_disconnected"'; then
            echo "Backup drive disconnected"
            return
        fi
    done

    # Generic reasons based on count
    if [ $failed_items -eq 1 ]; then
        echo "Single file failed to backup"
    elif [ $failed_items -lt 5 ]; then
        echo "$failed_items files failed to backup"
    else
        local failure_percent=$((failed_items * 100 / total_items))
        echo "$failure_percent% of files failed to backup"
    fi
}

# Write complete backup state to JSON file
write_backup_state() {
    local exit_code="$1"
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    local project_name="${PROJECT_NAME:-unknown}"
    local state_file="$state_dir/${project_name}/last-backup.json"

    mkdir -p "$state_dir/$project_name" 2>/dev/null || { log_debug "Failed to create state dir: $state_dir/$project_name"; true; }

    # Determine status from exit code
    local status="unknown"
    case "$exit_code" in
        0) status="complete_success" ;;
        1) status="partial_success" ;;
        2) status="total_failure" ;;
    esac

    # Calculate severity
    local severity=$(calculate_severity)
    local immediate=$(requires_immediate_action)
    local reason=$(get_severity_reason)

    # Determine actions based on severity
    local retry_recommended="true"
    local stop_daemon="false"
    local block_cloud="false"
    local send_notification="true"
    local notification_urgency="medium"
    local escalate_hours=3

    case "$severity" in
        critical)
            stop_daemon="true"
            block_cloud="true"
            notification_urgency="critical"
            escalate_hours=1
            ;;
        high)
            block_cloud="true"
            notification_urgency="high"
            escalate_hours=2
            ;;
        medium)
            notification_urgency="medium"
            escalate_hours=3
            ;;
        low)
            notification_urgency="low"
            escalate_hours=6
            ;;
        none)
            send_notification="false"
            ;;
    esac

    # Build notification message
    local notification_title="Checkpoint Backup"
    local notification_message=""
    local notification_details=""

    case "$status" in
        complete_success)
            notification_title="✅ Checkpoint Backup Complete"
            notification_message="${PROJECT_NAME}: All files backed up successfully"
            notification_details="$BACKUP_STATE_SUCCEEDED_FILES files, $BACKUP_STATE_SUCCEEDED_DBS databases"
            ;;
        partial_success)
            notification_title="⚠️ Checkpoint Backup Incomplete"
            notification_message="${PROJECT_NAME}: $BACKUP_STATE_SUCCEEDED_FILES/$BACKUP_STATE_TOTAL_FILES files backed up. $BACKUP_STATE_FAILED_FILES FAILED."
            notification_details="Run 'backup-failures' for fix instructions"
            ;;
        total_failure)
            notification_title="❌ Checkpoint Backup Failed"
            notification_message="${PROJECT_NAME}: Backup completely failed"
            notification_details="Run 'backup-failures' for details"
            ;;
    esac

    # Build failures array
    local failures_json="["
    local first=true
    for failure in "${BACKUP_STATE_FAILURES[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            failures_json+=","
        fi
        failures_json+="$failure"
    done
    failures_json+="]"

    # Generate LLM prompt
    local llm_prompt="Fix these Checkpoint backup failures:\\n\\n"
    for failure in "${BACKUP_STATE_FAILURES[@]}"; do
        local file
        file=$(echo "$failure" | grep -o '"path":"[^"]*"' | cut -d'"' -f4 || true)
        local error_code
        error_code=$(echo "$failure" | grep -o '"error_code":"[^"]*"' | cut -d'"' -f4 || true)
        local fix
        fix=$(echo "$failure" | grep -o '"suggested_fix":"[^"]*"' | cut -d'"' -f4 || true)

        llm_prompt+="File: $file\\nError: $error_code\\nFix: $fix\\n\\n"
    done

    # Write JSON state
    cat > "$state_file" << EOF
{
  "backup_id": "$(date +%Y%m%d_%H%M%S)",
  "timestamp": $(date +%s),
  "exit_code": $exit_code,
  "status": "$status",

  "summary": {
    "total_files": $BACKUP_STATE_TOTAL_FILES,
    "succeeded_files": $BACKUP_STATE_SUCCEEDED_FILES,
    "failed_files": $BACKUP_STATE_FAILED_FILES,
    "total_databases": $BACKUP_STATE_TOTAL_DBS,
    "succeeded_databases": $BACKUP_STATE_SUCCEEDED_DBS,
    "failed_databases": $BACKUP_STATE_FAILED_DBS
  },

  "severity": {
    "level": "$severity",
    "reason": "$reason",
    "requires_immediate_action": $immediate
  },

  "failures": $failures_json,

  "actions": {
    "retry_recommended": $retry_recommended,
    "retry_delay_seconds": 3600,
    "stop_daemon": $stop_daemon,
    "block_cloud_upload": $block_cloud,
    "send_notification": $send_notification,
    "notification_urgency": "$notification_urgency",
    "escalate_after_hours": $escalate_hours
  },

  "notification": {
    "title": "$notification_title",
    "message": "$notification_message",
    "details": "$notification_details"
  },

  "llm_prompt": "$llm_prompt"
}
EOF

    echo "$state_file"
}

# Read backup state from JSON
# Returns: 0 if state exists, 1 otherwise
read_backup_state() {
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    local project_name="${PROJECT_NAME:-unknown}"
    local state_file="$state_dir/${project_name}/last-backup.json"

    if [ ! -f "$state_file" ]; then
        return 1
    fi

    cat "$state_file"
    return 0
}

# ==============================================================================
# FAILURE REPORTING
# ==============================================================================

# Display backup failures from JSON state
# Shows detailed error info with suggested fixes
show_backup_failures() {
    local state_dir="${STATE_DIR:-$HOME/.claudecode-backups/state}"
    local project_name="${PROJECT_NAME:-unknown}"
    local state_file="$state_dir/${project_name}/last-backup.json"

    # Check if state file exists
    if [ ! -f "$state_file" ]; then
        echo "✅ No backup failures - state file not found"
        echo ""
        echo "This could mean:"
        echo "  • No backups have been run yet"
        echo "  • All previous backups succeeded"
        echo ""
        return 0
    fi

    # Read JSON state (using grep to avoid requiring jq)
    local exit_code
    exit_code=$(grep -o '"exit_code": *[0-9]*' "$state_file" | grep -o '[0-9]*$' || true)
    local backup_status
    backup_status=$(grep -o '"status": *"[^"]*"' "$state_file" | head -1 | cut -d'"' -f4 || true)
    local timestamp
    timestamp=$(grep -o '"timestamp": *[0-9]*' "$state_file" | grep -o '[0-9]*$' || true)

    # If exit code is 0, no failures
    if [ "$exit_code" = "0" ]; then
        echo "✅ No backup failures - last backup succeeded"
        echo ""
        local time_ago=$(format_time_ago "$timestamp")
        echo "Last backup: $time_ago"
        echo ""
        return 0
    fi

    # Extract summary
    local total_files
    total_files=$(grep -o '"total_files": *[0-9]*' "$state_file" | grep -o '[0-9]*$' || echo "0")
    local succeeded_files
    succeeded_files=$(grep -o '"succeeded_files": *[0-9]*' "$state_file" | grep -o '[0-9]*$' || echo "0")
    local failed_files
    failed_files=$(grep -o '"failed_files": *[0-9]*' "$state_file" | grep -o '[0-9]*$' || echo "0")

    # Extract severity
    local severity
    severity=$(grep -o '"level": *"[^"]*"' "$state_file" | head -1 | cut -d'"' -f4 || true)
    local reason
    reason=$(grep -o '"reason": *"[^"]*"' "$state_file" | head -1 | cut -d'"' -f4 || true)
    local immediate
    immediate=$(grep -o '"requires_immediate_action": *[^,}]*' "$state_file" | grep -o '[a-z]*$' || true)

    local time_ago=$(format_time_ago "$timestamp")

    echo ""
    echo "⚠️  BACKUP FAILURES DETECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Project: ${PROJECT_NAME:-Unknown}"
    echo "Status: $backup_status"
    echo "Failed: $time_ago ($failed_files errors)"
    if [ "${total_files:-0}" -gt 0 ]; then
        echo "Success Rate: $succeeded_files/$total_files files ($(( succeeded_files * 100 / total_files ))%)"
    else
        echo "Success Rate: $succeeded_files/$total_files files"
    fi
    echo ""
    echo "Severity: $(echo $severity | tr '[:lower:]' '[:upper:]')"
    echo "Reason: $reason"
    if [ "$immediate" = "true" ]; then
        echo "⚠️  REQUIRES IMMEDIATE ACTION"
    fi
    echo ""

    # Parse and display failures from JSON
    echo "FAILED FILES:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Extract failures array (single line or multi-line)
    # Use sed to extract everything between "failures": [ and ]
    local failures_json=$(sed -n '/"failures": *\[/,/\]/p' "$state_file" | sed '1s/.*\[/[/; $s/\].*/]/')

    # Split failures by },{ to handle multiple failure objects
    local count=0
    echo "$failures_json" | grep -o '{[^}]*}' | while IFS= read -r failure_obj; do
        count=$((count + 1))

        # Extract fields from each failure object
        local file_path
        file_path=$(echo "$failure_obj" | grep -o '"path": *"[^"]*"' | cut -d'"' -f4 || true)
        local error_code
        error_code=$(echo "$failure_obj" | grep -o '"error_code": *"[^"]*"' | cut -d'"' -f4 || true)
        local suggested_fix
        suggested_fix=$(echo "$failure_obj" | grep -o '"suggested_fix": *"[^"]*"' | cut -d'"' -f4 || true)

        # Display failure
        if [ -n "$file_path" ]; then
            echo "$count. $file_path"
            echo "   Error: $error_code"
            echo "   Fix: $suggested_fix"
            echo ""
        fi
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📋 COPY THIS PROMPT INTO CLAUDE CODE CHAT:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Extract and display LLM prompt
    local llm_prompt
    llm_prompt=$(grep -o '"llm_prompt": *"[^"]*"' "$state_file" | cut -d'"' -f4 || true)
    # Unescape newlines
    echo "$llm_prompt" | sed 's/\\n/\n/g'

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "AFTER CLAUDE FIXES THE ISSUES:"
    echo "  1. Apply the fixes Claude suggests"
    echo "  2. Run: backup-now.sh --force"
    echo "  3. Verify: 100% backed up = TRUE SUCCESS"
    echo ""

    # Show actions
    local stop_daemon
    stop_daemon=$(grep -o '"stop_daemon": *[^,}]*' "$state_file" | grep -o '[a-z]*$' || true)
    local block_cloud
    block_cloud=$(grep -o '"block_cloud_upload": *[^,}]*' "$state_file" | grep -o '[a-z]*$' || true)

    if [ "$stop_daemon" = "true" ]; then
        echo "⚠️  WARNING: Daemon stopped due to critical failure"
        echo "    Restart after fixing: backup-now.sh --force"
        echo ""
    fi

    if [ "$block_cloud" = "true" ]; then
        echo "🔒 CLOUD UPLOAD BLOCKED"
        echo "    Fix failures before syncing to cloud (malware/critical errors)"
        echo ""
    fi

    echo "JSON STATE: $state_file"
    echo ""

    return 1
}
