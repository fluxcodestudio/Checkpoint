#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Storage Monitoring
# Pre-backup disk space checks, per-project storage breakdown, cleanup suggestions
# ==============================================================================
# @requires: ops/file-ops (for get_backup_disk_usage),
#            ui/time-size-utils (for format_bytes, get_dir_size_bytes),
#            platform/compat (for send_notification, stat_mtime)
# @provides: pre_backup_storage_check, get_volume_stats,
#            get_per_project_storage, suggest_cleanup
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_STORAGE_MONITOR:-}" ] && return || readonly _CHECKPOINT_STORAGE_MONITOR=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Source dependencies (conditional to avoid double-loading)
if [ -z "${_CHECKPOINT_FILE_OPS:-}" ]; then
    source "$_CHECKPOINT_LIB_DIR/ops/file-ops.sh"
fi
if [ -z "${_CHECKPOINT_TIME_SIZE_UTILS:-}" ]; then
    source "$_CHECKPOINT_LIB_DIR/ui/time-size-utils.sh"
fi
if [ -z "${_COMPAT_LOADED:-}" ]; then
    source "$_CHECKPOINT_LIB_DIR/platform/compat.sh"
fi

# State file for notification cooldown
_STORAGE_ALERT_STATE="${HOME}/.checkpoint/storage-alert-last"

# Cache file for per-project storage data
_STORAGE_CACHE_FILE="${HOME}/.checkpoint/storage-cache"

# Cache TTL in seconds (1 hour)
_STORAGE_CACHE_TTL=3600

# ==============================================================================
# PRE-BACKUP STORAGE CHECK
# ==============================================================================

# Check disk space before backup and alert if thresholds exceeded
# Args: $1 = backup directory path
# Returns: 0 (ok), 1 (warning — log + notify but allow), 2 (critical — block)
pre_backup_storage_check() {
    local backup_dir="${1:-${BACKUP_DIR:-}}"

    # Skip if storage checks disabled
    if [ "${STORAGE_CHECK_ENABLED:-true}" != "true" ]; then
        return 0
    fi

    # Need a valid backup directory
    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        return 0
    fi

    local warning_pct="${STORAGE_WARNING_PERCENT:-80}"
    local critical_pct="${STORAGE_CRITICAL_PERCENT:-90}"
    local usage

    usage=$(get_backup_disk_usage)

    if [ "$usage" -ge "$critical_pct" ] 2>/dev/null; then
        _storage_notify "critical" "$usage" "$critical_pct" "$backup_dir"
        return 2
    elif [ "$usage" -ge "$warning_pct" ] 2>/dev/null; then
        _storage_notify "warning" "$usage" "$warning_pct" "$backup_dir"
        return 1
    fi

    return 0
}

# Internal: send storage notification with cooldown
# Args: $1 = level (warning|critical), $2 = usage%, $3 = threshold%, $4 = backup_dir
_storage_notify() {
    local level="$1"
    local usage="$2"
    local threshold="$3"
    local backup_dir="$4"

    local escalation_hours="${NOTIFY_ESCALATION_HOURS:-3}"
    local escalation_seconds=$((escalation_hours * 3600))

    # Check cooldown — only re-notify after NOTIFY_ESCALATION_HOURS
    if [ -f "$_STORAGE_ALERT_STATE" ]; then
        local last_alert_time
        last_alert_time=$(get_file_mtime "$_STORAGE_ALERT_STATE")
        local now
        now=$(date +%s)
        local elapsed=$((now - last_alert_time))
        if [ "$elapsed" -lt "$escalation_seconds" ]; then
            # Within cooldown — skip notification but still return correct code
            return 0
        fi
    fi

    # Update cooldown state file
    mkdir -p "$(dirname "$_STORAGE_ALERT_STATE")"
    date +%s > "$_STORAGE_ALERT_STATE"

    # Log the alert
    local msg=""
    if [ "$level" = "critical" ]; then
        msg="CRITICAL: Disk usage at ${usage}% (threshold: ${threshold}%). Backup blocked."
        log_error "Storage check: $msg" 2>/dev/null || true
    else
        msg="WARNING: Disk usage at ${usage}% (threshold: ${threshold}%). Backup allowed but space is low."
        log_warn "Storage check: $msg" 2>/dev/null || true
    fi

    # Send desktop notification
    send_notification "Checkpoint: Storage ${level}" "$msg"
}

# ==============================================================================
# VOLUME STATISTICS
# ==============================================================================

# Get disk volume statistics for a path
# Args: $1 = path on the volume
# Output: total_kb|used_kb|avail_kb|pct_used
get_volume_stats() {
    local path="${1:-.}"

    if [ ! -e "$path" ]; then
        echo "0|0|0|0"
        return 1
    fi

    # Single df call with POSIX output, parsed in one awk pass
    df -Pk "$path" 2>/dev/null | awk 'NR==2 {
        gsub(/%/, "", $5)
        print $2 "|" $3 "|" $4 "|" $5
    }'
}

# ==============================================================================
# PER-PROJECT STORAGE BREAKDOWN
# ==============================================================================

# Get storage breakdown by registered project
# Args: $1 = backup base directory
# Output: size_bytes|project_name lines sorted by size descending
get_per_project_storage() {
    local backup_base="${1:-${BACKUP_DIR:-}}"

    if [ -z "$backup_base" ]; then
        return 1
    fi

    # Check cache freshness
    if [ -f "$_STORAGE_CACHE_FILE" ]; then
        local cache_mtime
        cache_mtime=$(get_file_mtime "$_STORAGE_CACHE_FILE")
        local now
        now=$(date +%s)
        local cache_age=$((now - cache_mtime))

        if [ "$cache_age" -lt "$_STORAGE_CACHE_TTL" ]; then
            # Cache is fresh — return cached data
            cat "$_STORAGE_CACHE_FILE"
            return 0
        fi
    fi

    # Cache is stale or missing — regenerate
    local results=""
    local project_path

    # Source projects-registry if not already loaded
    if ! type list_projects >/dev/null 2>&1; then
        if [ -f "$_CHECKPOINT_LIB_DIR/../lib/projects-registry.sh" ]; then
            source "$_CHECKPOINT_LIB_DIR/../lib/projects-registry.sh"
        elif [ -f "$_CHECKPOINT_LIB_DIR/projects-registry.sh" ]; then
            source "$_CHECKPOINT_LIB_DIR/projects-registry.sh"
        fi
    fi

    if ! type list_projects >/dev/null 2>&1; then
        return 1
    fi

    while IFS= read -r project_path; do
        [ -z "$project_path" ] && continue

        local project_name
        project_name=$(basename "$project_path")

        # Look for backup dir within the project's backup location
        local project_backup_dir=""
        if [ -f "$project_path/.backup-config.sh" ]; then
            # Try to extract BACKUP_DIR from config
            project_backup_dir=$(grep "^BACKUP_DIR=" "$project_path/.backup-config.sh" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
        fi

        # Fallback to standard backup location
        if [ -z "$project_backup_dir" ] || [ ! -d "$project_backup_dir" ]; then
            project_backup_dir="$project_path/backups"
        fi

        if [ -d "$project_backup_dir" ]; then
            local size_bytes
            size_bytes=$(get_dir_size_bytes "$project_backup_dir")
            results="${results}${size_bytes}|${project_name}\n"
        fi
    done < <(list_projects)

    # Sort by size descending and write to cache
    mkdir -p "$(dirname "$_STORAGE_CACHE_FILE")"
    printf '%b' "$results" | sort -t'|' -k1 -rn > "$_STORAGE_CACHE_FILE"

    cat "$_STORAGE_CACHE_FILE"
}

# ==============================================================================
# CLEANUP SUGGESTIONS
# ==============================================================================

# Suggest cleanup actions when disk space is low
# Args: $1 = backup directory
# Output: formatted text lines for display
suggest_cleanup() {
    local backup_dir="${1:-${BACKUP_DIR:-}}"

    # Only show if enabled
    if [ "${STORAGE_CLEANUP_SUGGEST:-true}" != "true" ]; then
        return 0
    fi

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        return 0
    fi

    local archived_dir="${backup_dir}/archived"
    local old_count=0

    # Count archived files older than 30 days
    if [ -d "$archived_dir" ]; then
        old_count=$(find "$archived_dir" -type f -mtime +30 2>/dev/null | wc -l | tr -d ' ')
    fi

    echo "Storage Cleanup Suggestions:"
    echo "───────────────────────────────"

    if [ "$old_count" -gt 0 ]; then
        echo "  - $old_count archived files older than 30 days"
    fi

    # Show top 5 largest project backups (from cached per-project data)
    if [ -f "$_STORAGE_CACHE_FILE" ]; then
        echo "  - Top backup consumers:"
        local count=0
        while IFS='|' read -r size_bytes project_name; do
            [ -z "$size_bytes" ] && continue
            local formatted_size
            formatted_size=$(format_bytes "$size_bytes")
            echo "      ${formatted_size}  ${project_name}"
            count=$((count + 1))
            [ "$count" -ge 5 ] && break
        done < "$_STORAGE_CACHE_FILE"
    fi

    echo ""
    echo "  Run: checkpoint cleanup --dry-run"
}
