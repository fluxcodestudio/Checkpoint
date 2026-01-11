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

# Note: set -e removed for compatibility when sourcing in scripts with errexit

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

# ==============================================================================
# PRUNING CANDIDATE IDENTIFICATION
# ==============================================================================

# Find pruning candidates in a directory using tiered retention
# Args: $1 = directory path, $2 = pattern (e.g., "*.db.gz" or "*")
# Returns: List of files to prune (one per line)
find_tiered_pruning_candidates() {
    local dir="$1"
    local pattern="${2:-*}"
    local temp_dir=$(mktemp -d)
    local candidates_file="$temp_dir/candidates"
    local grouped_file="$temp_dir/grouped"

    # Build list of all files with timestamps
    touch "$grouped_file"

    while IFS= read -r file; do
        local basename=$(basename "$file")
        local timestamp=$(extract_timestamp "$basename")

        if [[ -z "$timestamp" ]]; then
            # No timestamp found - use file mtime
            timestamp=$(stat -f "%Sm" -t "%Y%m%d_%H%M%S" "$file" 2>/dev/null || date +"%Y%m%d_%H%M%S")
        fi

        local tier=$(classify_retention_tier "$timestamp")

        case "$tier" in
            hourly)
                # Keep all hourly snapshots
                ;;
            daily)
                local key=$(get_day_key "$timestamp")
                echo "$key $timestamp $file" >> "$grouped_file"
                ;;
            weekly)
                local key=$(get_week_key "$timestamp")
                echo "$key $timestamp $file" >> "$grouped_file"
                ;;
            monthly)
                local key=$(get_month_key "$timestamp")
                echo "$key $timestamp $file" >> "$grouped_file"
                ;;
            expired)
                # Always prune expired
                echo "$file"
                ;;
        esac
    done < <(find "$dir" -name "$pattern" -type f 2>/dev/null | sort)

    # For each tier group, keep only the oldest (first) and prune the rest
    if [[ -s "$grouped_file" ]]; then
        # Sort by key, then by timestamp to get oldest first
        sort -t' ' -k1,1 -k2,2 "$grouped_file" > "$temp_dir/sorted"

        local prev_key=""
        while IFS=' ' read -r key timestamp file; do
            if [[ "$key" == "$prev_key" ]]; then
                # Not the oldest in this group - prune it
                echo "$file"
            fi
            prev_key="$key"
        done < "$temp_dir/sorted"
    fi

    rm -rf "$temp_dir"
}

# Get retention statistics for a directory
# Args: $1 = directory path
# Returns: tier counts as "hourly:N daily:N weekly:N monthly:N expired:N"
get_retention_stats() {
    local dir="$1"
    local hourly=0 daily=0 weekly=0 monthly=0 expired=0

    while IFS= read -r file; do
        local basename=$(basename "$file")
        local timestamp=$(extract_timestamp "$basename")

        if [[ -z "$timestamp" ]]; then
            timestamp=$(stat -f "%Sm" -t "%Y%m%d_%H%M%S" "$file" 2>/dev/null || date +"%Y%m%d_%H%M%S")
        fi

        local tier=$(classify_retention_tier "$timestamp")

        case "$tier" in
            hourly) ((hourly++)) ;;
            daily) ((daily++)) ;;
            weekly) ((weekly++)) ;;
            monthly) ((monthly++)) ;;
            expired) ((expired++)) ;;
        esac
    done < <(find "$dir" -type f 2>/dev/null)

    echo "hourly:$hourly daily:$daily weekly:$weekly monthly:$monthly expired:$expired"
}

# Calculate space that would be freed by tiered pruning
# Args: $1 = directory path, $2 = pattern
# Returns: bytes
calculate_tiered_savings() {
    local dir="$1"
    local pattern="${2:-*}"
    local total=0

    while IFS= read -r file; do
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        total=$((total + size))
    done < <(find_tiered_pruning_candidates "$dir" "$pattern")

    echo "$total"
}
