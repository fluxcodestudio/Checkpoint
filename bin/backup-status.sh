#!/usr/bin/env bash
# Checkpoint - Enhanced Status Dashboard
# Comprehensive health monitoring and statistics display

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Source foundation library
if [ -f "$LIB_DIR/backup-lib.sh" ]; then
    source "$LIB_DIR/backup-lib.sh"
else
    echo "Error: Foundation library not found: $LIB_DIR/backup-lib.sh" >&2
    exit 1
fi

# ==============================================================================
# COMMAND LINE OPTIONS
# ==============================================================================

OUTPUT_MODE="dashboard"  # dashboard, compact, timeline, json
SHOW_HELP=false
PROJECT_DIR="${1:-$PWD}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_MODE="json"
            shift
            ;;
        --compact)
            OUTPUT_MODE="compact"
            shift
            ;;
        --timeline)
            OUTPUT_MODE="timeline"
            shift
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        *)
            # Assume it's a project directory
            if [ -d "$1" ]; then
                PROJECT_DIR="$1"
            else
                echo "Unknown option or invalid directory: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# ==============================================================================
# HELP TEXT
# ==============================================================================

if [ "$SHOW_HELP" = true ]; then
    cat <<EOF
Checkpoint - Status Dashboard

USAGE:
    backup-status.sh [OPTIONS] [PROJECT_DIR]

OPTIONS:
    --json          Output status as JSON (for scripting)
    --compact       Compact one-line status
    --timeline      Show backup timeline view
    --help, -h      Show this help message

EXAMPLES:
    backup-status.sh                    # Status for current project
    backup-status.sh /path/to/project   # Status for specific project
    backup-status.sh --json             # JSON output for scripting
    backup-status.sh --compact          # Quick one-line status

EXIT CODES:
    0 - System healthy
    1 - Configuration error or warnings detected
    2 - Critical errors detected

EOF
    exit 0
fi

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

if ! load_backup_config "$PROJECT_DIR"; then
    echo "Error: No backup configuration found in: $PROJECT_DIR" >&2
    echo "Run install.sh first or specify project directory" >&2
    exit 1
fi

# Initialize state directories
init_state_dirs

# ==============================================================================
# GATHER SYSTEM STATUS
# ==============================================================================

# Component status
daemon_running=$(check_daemon_status && echo "true" || echo "false")
hooks_installed=$(check_hooks_status "$PROJECT_DIR" && echo "true" || echo "false")
config_valid=$(check_config_status && echo "true" || echo "false")
drive_connected=$(check_drive && echo "true" || echo "false")

# Statistics
db_count=$(count_database_backups)
current_files=$(count_current_files)
archived_files=$(count_archived_files)
total_size=$(get_total_backup_size)
total_size_human=$(format_bytes $total_size)

# Database stats
db_size=0
db_size_human="0 B"
if [ -d "$DATABASE_DIR" ]; then
    db_size=$(get_dir_size_bytes "$DATABASE_DIR")
    db_size_human=$(format_bytes $db_size)
fi

# Last backup info
last_backup_time=$(get_last_backup_time)
if [ $last_backup_time -gt 0 ]; then
    last_backup_ago=$(format_time_ago $last_backup_time)
    last_backup_date=$(date -r $last_backup_time '+%Y-%m-%d %H:%M:%S')
else
    last_backup_ago="Never"
    last_backup_date="Never"
fi

# Next backup info
time_until_next=$(time_until_next_backup)
if [ $time_until_next -gt 0 ]; then
    next_backup_in=$(format_duration $time_until_next)
    next_backup_status="in $next_backup_in (scheduled)"
elif [ $time_until_next -lt 0 ]; then
    next_backup_overdue=$(format_duration $((-time_until_next)))
    next_backup_status="overdue by $next_backup_overdue"
else
    next_backup_status="due now"
fi

# Daemon PID
daemon_pid=""
if [ "$daemon_running" = "true" ]; then
    daemon_pid=$(get_lock_pid "$PROJECT_NAME" || echo "")
fi

# Warnings and errors
warnings=()
errors=()
health_status="HEALTHY"

# Check for issues
if [ "$drive_connected" = "false" ] && [ "$DRIVE_VERIFICATION_ENABLED" = "true" ]; then
    errors+=("Drive not connected: Expected marker at $DRIVE_MARKER_FILE")
    health_status="ERROR"
fi

if [ "$daemon_running" = "false" ]; then
    warnings+=("Daemon not running: Hourly backups disabled")
    if [ "$health_status" = "HEALTHY" ]; then
        health_status="WARNING"
    fi
fi

if [ "$hooks_installed" = "false" ]; then
    warnings+=("Hooks not installed: Manual backups only")
    if [ "$health_status" = "HEALTHY" ]; then
        health_status="WARNING"
    fi
fi

if [ "$config_valid" = "false" ]; then
    errors+=("Configuration invalid: Check required variables")
    health_status="ERROR"
fi

# Check for stale backups (no backup in >2 hours)
if [ $last_backup_time -gt 0 ]; then
    local now=$(date +%s)
    local backup_age=$((now - last_backup_time))
    if [ $backup_age -gt 7200 ]; then
        warnings+=("No backup in $last_backup_ago (expected: hourly)")
        if [ "$health_status" = "HEALTHY" ]; then
            health_status="WARNING"
        fi
    fi
fi

# Check disk space
disk_usage=$(get_backup_disk_usage)
check_disk_space
disk_status=$?
if [ $disk_status -eq 2 ]; then
    errors+=("Disk usage critical: ${disk_usage}% of backup volume")
    health_status="ERROR"
elif [ $disk_status -eq 1 ]; then
    warnings+=("Disk usage high: ${disk_usage}% of backup volume")
    if [ "$health_status" = "HEALTHY" ]; then
        health_status="WARNING"
    fi
fi

# Check retention policy warnings
db_to_prune=$(count_backups_to_prune "$DATABASE_DIR" "$DB_RETENTION_DAYS" 7)
if [ $db_to_prune -gt 0 ]; then
    local days_until=$(days_until_prune "$DATABASE_DIR" "$DB_RETENTION_DAYS")
    if [ $days_until -ge 0 ]; then
        warnings+=("Database backups: $db_to_prune will be pruned in $days_until days")
        if [ "$health_status" = "HEALTHY" ]; then
            health_status="WARNING"
        fi
    fi
fi

# ==============================================================================
# OUTPUT RENDERING
# ==============================================================================

# JSON output
if [ "$OUTPUT_MODE" = "json" ]; then
    cat <<EOF
{
  $(json_kv "status" "$health_status"),
  $(json_kv_num "errorCount" "${#errors[@]}"),
  $(json_kv_num "warningCount" "${#warnings[@]}"),
  "lastBackup": {
    $(json_kv_num "timestamp" "$last_backup_time"),
    $(json_kv "ago" "$last_backup_ago"),
    $(json_kv "date" "$last_backup_date")
  },
  "nextBackup": {
    $(json_kv_num "timeUntil" "$time_until_next"),
    $(json_kv "status" "$next_backup_status")
  },
  "statistics": {
    $(json_kv_num "databaseSnapshots" "$db_count"),
    $(json_kv "databaseSize" "$db_size_human"),
    $(json_kv_num "currentFiles" "$current_files"),
    $(json_kv_num "archivedVersions" "$archived_files"),
    $(json_kv "totalSize" "$total_size_human"),
    $(json_kv_num "totalSizeBytes" "$total_size")
  },
  "components": {
    $(json_kv_bool "daemon" "$daemon_running"),
    $(json_kv "daemonPid" "${daemon_pid:-null}"),
    $(json_kv_bool "hooks" "$hooks_installed"),
    $(json_kv_bool "config" "$config_valid"),
    $(json_kv_bool "drive" "$drive_connected")
  },
  "retention": {
    $(json_kv_num "databaseDays" "$DB_RETENTION_DAYS"),
    $(json_kv_num "fileDays" "$FILE_RETENTION_DAYS"),
    $(json_kv_num "databaseBackupsKept" "$db_count")
  },
  "warnings": [
$(IFS=$'\n'; for w in "${warnings[@]}"; do echo "    \"$(json_escape "$w")\""; done | paste -sd ',' -)
  ],
  "errors": [
$(IFS=$'\n'; for e in "${errors[@]}"; do echo "    \"$(json_escape "$e")\""; done | paste -sd ',' -)
  ]
}
EOF
    exit 0
fi

# Compact output
if [ "$OUTPUT_MODE" = "compact" ]; then
    if [ "$health_status" = "HEALTHY" ]; then
        echo -e "${COLOR_GREEN}✅ HEALTHY${COLOR_RESET} | Last: $last_backup_ago | DBs: $db_count | Files: $current_files/$archived_files | Size: $total_size_human"
    elif [ "$health_status" = "WARNING" ]; then
        echo -e "${COLOR_YELLOW}⚠️  WARNING${COLOR_RESET} | ${#warnings[@]} warnings | Last: $last_backup_ago | DBs: $db_count | Files: $current_files/$archived_files"
    else
        echo -e "${COLOR_RED}❌ ERROR${COLOR_RESET} | ${#errors[@]} errors | Last: $last_backup_ago"
    fi
    exit 0
fi

# Timeline output
if [ "$OUTPUT_MODE" = "timeline" ]; then
    echo ""
    color_bold "Backup Timeline - $PROJECT_NAME"
    echo ""

    # Database backups
    if [ $db_count -gt 0 ]; then
        color_cyan "Database Backups ($db_count):"
        echo ""
        find "$DATABASE_DIR" -name "*.db.gz" -type f 2>/dev/null | while read -r file; do
            local mtime=$(stat -f%m "$file")
            local size=$(stat -f%z "$file")
            local ago=$(format_time_ago $mtime)
            local date=$(date -r $mtime '+%Y-%m-%d %H:%M:%S')
            local size_human=$(format_bytes $size)
            echo "  $date ($ago) - $(basename "$file") - $size_human"
        done | sort -r | head -20
        echo ""
    fi

    # Recent file changes
    color_cyan "Recent File Changes (last 20):"
    echo ""
    if [ -d "$FILES_DIR" ]; then
        find "$FILES_DIR" -type f 2>/dev/null | while read -r file; do
            local mtime=$(stat -f%m "$file")
            local size=$(stat -f%z "$file")
            local ago=$(format_time_ago $mtime)
            local date=$(date -r $mtime '+%Y-%m-%d %H:%M:%S')
            local rel_path="${file#$FILES_DIR/}"
            echo "$mtime|$date|$ago|$rel_path"
        done | sort -rn | head -20 | while IFS='|' read -r _ date ago path; do
            echo "  $date ($ago) - $path"
        done
    else
        echo "  No files backed up yet"
    fi
    echo ""

    exit 0
fi

# ==============================================================================
# DASHBOARD OUTPUT (Default)
# ==============================================================================

echo ""
echo "╭──────────────────────────────────────────────────────────────╮"
printf "│ %-60s │\n" "Backup Status - $PROJECT_NAME"
echo "│                                                              │"

# Overall health
if [ "$health_status" = "HEALTHY" ]; then
    printf "│ ${COLOR_GREEN}✅ HEALTHY${COLOR_RESET}%-49s │\n" ""
elif [ "$health_status" = "WARNING" ]; then
    printf "│ ${COLOR_YELLOW}⚠️  WARNING${COLOR_RESET}%-48s │\n" ""
else
    printf "│ ${COLOR_RED}❌ ERROR${COLOR_RESET}%-50s │\n" ""
fi

echo "│                                                              │"

# Last backup
printf "│ Last Backup:    %-45s │\n" "$last_backup_ago ($last_backup_date)"
printf "│ Next Backup:    %-45s │\n" "$next_backup_status"

echo "│                                                              │"
echo "│ ${COLOR_CYAN}📊 Statistics${COLOR_RESET}                                             │"

# Statistics
printf "│   Database Snapshots:  %-35s │\n" "$db_count ($db_size_human compressed)"
printf "│   Current Files:       %-35s │\n" "$current_files files"
printf "│   Archived Versions:   %-35s │\n" "$archived_files versions"
printf "│   Total Size:          %-35s │\n" "$total_size_human"

echo "│                                                              │"
echo "│ ${COLOR_CYAN}🔧 Components${COLOR_RESET}                                             │"

# Component status
if [ "$daemon_running" = "true" ]; then
    if [ -n "$daemon_pid" ]; then
        printf "│   ${COLOR_GREEN}✅${COLOR_RESET} Daemon:           Running (PID $daemon_pid)%-17s │\n" ""
    else
        printf "│   ${COLOR_GREEN}✅${COLOR_RESET} Daemon:           Running%-28s │\n" ""
    fi
else
    printf "│   ${COLOR_RED}❌${COLOR_RESET} Daemon:           Not running%-23s │\n" ""
fi

if [ "$hooks_installed" = "true" ]; then
    printf "│   ${COLOR_GREEN}✅${COLOR_RESET} Hook:             Installed%-24s │\n" ""
else
    printf "│   ${COLOR_RED}❌${COLOR_RESET} Hook:             Not installed%-20s │\n" ""
fi

if [ "$config_valid" = "true" ]; then
    printf "│   ${COLOR_GREEN}✅${COLOR_RESET} Configuration:    Valid%-29s │\n" ""
else
    printf "│   ${COLOR_RED}❌${COLOR_RESET} Configuration:    Invalid%-27s │\n" ""
fi

if [ "$DRIVE_VERIFICATION_ENABLED" = "true" ]; then
    if [ "$drive_connected" = "true" ]; then
        printf "│   ${COLOR_GREEN}✅${COLOR_RESET} Drive:            Connected%-25s │\n" ""
    else
        printf "│   ${COLOR_RED}❌${COLOR_RESET} Drive:            Not connected%-21s │\n" ""
    fi
fi

# Cloud Backup Status
if [ "${CLOUD_ENABLED:-false}" = "true" ]; then
    # Load cloud library to get status
    SCRIPT_DIR="$(dirname "$0")"
    CLOUD_LIB="$SCRIPT_DIR/../lib/cloud-backup.sh"
    if [ -f "$CLOUD_LIB" ]; then
        source "$CLOUD_LIB"
        cloud_last_upload=$(get_cloud_status)
        if check_rclone_installed && test_rclone_connection "${CLOUD_REMOTE_NAME:-}" 2>&1 | grep -q "successful"; then
            printf "│   ${COLOR_GREEN}✅${COLOR_RESET} Cloud:            $cloud_last_upload%-$((25 - ${#cloud_last_upload}))s │\n" ""
        else
            printf "│   ${COLOR_YELLOW}⚠️${COLOR_RESET}  Cloud:            Not connected%-21s │\n" ""
        fi
    else
        printf "│   ${COLOR_RED}❌${COLOR_RESET} Cloud:            Library missing%-20s │\n" ""
    fi
fi

# Warnings
if [ ${#warnings[@]} -gt 0 ]; then
    echo "│                                                              │"
    echo "│ ${COLOR_YELLOW}⚠️  Warnings${COLOR_RESET}                                              │"
    for warning in "${warnings[@]}"; do
        # Word wrap long warnings
        local wrapped=$(echo "$warning" | fold -w 56 -s)
        while IFS= read -r line; do
            printf "│   • %-56s │\n" "$line"
        done <<< "$wrapped"
    done
fi

# Errors
if [ ${#errors[@]} -gt 0 ]; then
    echo "│                                                              │"
    echo "│ ${COLOR_RED}❌ Errors${COLOR_RESET}                                                 │"
    for error in "${errors[@]}"; do
        # Word wrap long errors
        local wrapped=$(echo "$error" | fold -w 56 -s)
        while IFS= read -r line; do
            printf "│   • %-56s │\n" "$line"
        done <<< "$wrapped"
    done
fi

# Retention policies
echo "│                                                              │"
echo "│ ${COLOR_CYAN}📅 Retention Policies${COLOR_RESET}                                      │"
printf "│   Database:    %-42s │\n" "$DB_RETENTION_DAYS days ($db_count snapshots kept)"
printf "│   Files:       %-42s │\n" "$FILE_RETENTION_DAYS days ($archived_files versions kept)"

echo "│                                                              │"
echo "╰──────────────────────────────────────────────────────────────╯"
echo ""

# Exit code based on health
if [ "$health_status" = "ERROR" ]; then
    exit 2
elif [ "$health_status" = "WARNING" ]; then
    exit 1
else
    exit 0
fi
