#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Tiered Retention Policy Library
# ==============================================================================
# Version: 1.0.0
# Description: Time Machine-style snapshot management implementing tiered
#              retention: hourly -> daily -> weekly -> monthly.
#
# Usage:
#   source "$(dirname "$0")/../lib/retention-policy.sh"
#   tier=$(classify_retention_tier "20260102_150000")
#   candidates=$(find_tiered_pruning_candidates "/path/to/backups" "*.tar.gz")
#
# Tier Definitions:
#   - Hourly:  Keep ALL snapshots from last 24 hours
#   - Daily:   Keep ONE per day for last 7 days (oldest of each day)
#   - Weekly:  Keep ONE per week for last 4 weeks (oldest in week)
#   - Monthly: Keep ONE per month for last 12 months (oldest in month)
#   - Expired: Beyond monthly retention - eligible for pruning
# ==============================================================================

set -euo pipefail

# ==============================================================================
# RETENTION TIER CONFIGURATION
# ==============================================================================

# Configurable retention periods (can be overridden via environment)
RETENTION_HOURLY_HOURS="${RETENTION_HOURLY_HOURS:-24}"      # Keep all for 24h
RETENTION_DAILY_DAYS="${RETENTION_DAILY_DAYS:-7}"          # Keep 1/day for 7 days
RETENTION_WEEKLY_WEEKS="${RETENTION_WEEKLY_WEEKS:-4}"      # Keep 1/week for 4 weeks
RETENTION_MONTHLY_MONTHS="${RETENTION_MONTHLY_MONTHS:-12}" # Keep 1/month for 12 months

# ==============================================================================
# TIER CLASSIFICATION FUNCTIONS
# ==============================================================================

# Classify a timestamp into retention tier
# Args: $1 = timestamp (epoch or YYYYMMDD_HHMMSS format)
# Returns: hourly|daily|weekly|monthly|expired
classify_retention_tier() {
    local timestamp="$1"
    local now=$(date +%s)
    local epoch

    # Convert to epoch if in YYYYMMDD_HHMMSS format
    if [[ "$timestamp" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        local year="${timestamp:0:4}"
        local month="${timestamp:4:2}"
        local day="${timestamp:6:2}"
        local hour="${timestamp:9:2}"
        local min="${timestamp:11:2}"
        local sec="${timestamp:13:2}"
        epoch=$(date -j -f "%Y%m%d%H%M%S" "${year}${month}${day}${hour}${min}${sec}" +%s 2>/dev/null || echo 0)
    else
        epoch="$timestamp"
    fi

    local age_seconds=$((now - epoch))
    local age_hours=$((age_seconds / 3600))
    local age_days=$((age_seconds / 86400))
    local age_weeks=$((age_seconds / 604800))
    local age_months=$((age_days / 30))  # Approximate

    if [[ $age_hours -lt $RETENTION_HOURLY_HOURS ]]; then
        echo "hourly"
    elif [[ $age_days -lt $RETENTION_DAILY_DAYS ]]; then
        echo "daily"
    elif [[ $age_weeks -lt $RETENTION_WEEKLY_WEEKS ]]; then
        echo "weekly"
    elif [[ $age_months -lt $RETENTION_MONTHLY_MONTHS ]]; then
        echo "monthly"
    else
        echo "expired"
    fi
}

# Extract timestamp from archived filename
# Args: $1 = filename (e.g., main.js.20260102_150000_5678)
# Returns: timestamp portion (20260102_150000)
extract_timestamp() {
    local filename="$1"
    # Pattern: name.ext.YYYYMMDD_HHMMSS_XXXX or name_YYYYMMDD_HHMMSS.ext
    if [[ "$filename" =~ \.([0-9]{8}_[0-9]{6})_[0-9]+ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$filename" =~ _([0-9]{8}_[0-9]{6})\. ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# ==============================================================================
# TIER GROUPING FUNCTIONS
# ==============================================================================

# Get day key for daily tier grouping
# Args: $1 = timestamp (YYYYMMDD_HHMMSS)
# Returns: YYYYMMDD
get_day_key() {
    local timestamp="$1"
    echo "${timestamp:0:8}"
}

# Get week key for weekly tier grouping (ISO week)
# Args: $1 = timestamp (YYYYMMDD_HHMMSS)
# Returns: YYYY-WXX
get_week_key() {
    local timestamp="$1"
    local year="${timestamp:0:4}"
    local month="${timestamp:4:2}"
    local day="${timestamp:6:2}"
    date -j -f "%Y%m%d" "${year}${month}${day}" "+%G-W%V" 2>/dev/null || echo ""
}

# Get month key for monthly tier grouping
# Args: $1 = timestamp (YYYYMMDD_HHMMSS)
# Returns: YYYYMM
get_month_key() {
    local timestamp="$1"
    echo "${timestamp:0:6}"
}

# Check if snapshot should be kept as tier representative
# Args: $1 = timestamp, $2 = tier (daily|weekly|monthly), $3 = grouped_timestamps_file
# Returns: 0 if keep, 1 if prune
should_keep_as_representative() {
    local timestamp="$1"
    local tier="$2"
    local group_file="$3"

    local key=""
    case "$tier" in
        daily) key=$(get_day_key "$timestamp") ;;
        weekly) key=$(get_week_key "$timestamp") ;;
        monthly) key=$(get_month_key "$timestamp") ;;
        *) return 0 ;;  # hourly: keep all
    esac

    # Find oldest in this group (first occurrence = oldest)
    local oldest=$(grep "^$key " "$group_file" 2>/dev/null | head -1 | cut -d' ' -f2)

    [[ "$timestamp" == "$oldest" ]]
}
