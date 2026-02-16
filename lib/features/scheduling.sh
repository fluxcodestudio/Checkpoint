#!/bin/bash
# Checkpoint - Cron Expression Parser and Schedule Matcher
# Pure-bash library for parsing cron expressions and checking schedule matches.
# Standalone: does not source any other checkpoint libraries.

# ==============================================================================
# INTERNAL: FIELD PARSING
# ==============================================================================

# Parse a single cron field into a space-separated list of matching integers.
# Supports: *, */N, N, N-M, N-M/S, N,M,O, and combinations via commas.
# $1 = field string, $2 = min value, $3 = max value
# Output: space-separated list of matching integers on stdout
_parse_cron_field() {
    local field="$1" min="$2" max="$3"
    local values=()
    local i

    # Split on commas
    IFS=',' read -ra parts <<< "$field"
    for part in "${parts[@]}"; do
        if [[ "$part" == "*" ]]; then
            for ((i=min; i<=max; i++)); do values+=("$i"); done
        elif [[ "$part" =~ ^\*/([0-9]+)$ ]]; then
            local step="${BASH_REMATCH[1]}"
            for ((i=min; i<=max; i+=step)); do values+=("$i"); done
        elif [[ "$part" =~ ^([0-9]+)-([0-9]+)/([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}" step="${BASH_REMATCH[3]}"
            for ((i=start; i<=end; i+=step)); do values+=("$i"); done
        elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
            for ((i=start; i<=end; i++)); do values+=("$i"); done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            values+=("$part")
        fi
    done
    echo "${values[*]}"
}

# ==============================================================================
# INTERNAL: FIELD MEMBERSHIP CHECK
# ==============================================================================

# Check if an integer exists in a space-separated list (integer comparison).
# $1 = space-separated values, $2 = target value
# Returns 0 if found, 1 if not
_field_contains() {
    local val
    for val in $1; do
        [[ "$val" -eq "$2" ]] && return 0
    done
    return 1
}

# ==============================================================================
# PRESET RESOLUTION
# ==============================================================================

# Map @-prefixed schedule presets to 5-field cron expressions.
# Raw cron expressions pass through unchanged.
# $1 = schedule string (preset or raw cron)
# Output: 5-field cron expression on stdout
_resolve_schedule() {
    case "$1" in
        @every-5min)        echo "*/5 * * * *" ;;
        @every-15min)       echo "*/15 * * * *" ;;
        @every-30min)       echo "*/30 * * * *" ;;
        @hourly)            echo "0 * * * *" ;;
        @every-2h)          echo "0 */2 * * *" ;;
        @every-4h)          echo "0 */4 * * *" ;;
        @workhours)         echo "*/30 9-17 * * 1-5" ;;
        @workhours-relaxed) echo "0 9-17 * * 1-5" ;;
        @daily)             echo "0 0 * * *" ;;
        @weekdays)          echo "0 * * * 1-5" ;;
        *)                  echo "$1" ;;
    esac
}

# ==============================================================================
# VALIDATION
# ==============================================================================

# Validate a schedule expression (preset or raw cron).
# Returns 0 if valid, 1 if invalid. Error messages go to stderr.
# $1 = schedule string
validate_schedule() {
    local schedule="$1"

    # Empty check
    if [[ -z "$schedule" ]]; then
        echo "Error: schedule is empty" >&2
        return 1
    fi

    # Resolve presets
    local expr
    expr=$(_resolve_schedule "$schedule")

    # Split into fields
    local fields
    read -ra fields <<< "$expr"

    # Must have exactly 5 fields
    if [[ ${#fields[@]} -ne 5 ]]; then
        echo "Error: expected 5 fields, got ${#fields[@]}" >&2
        return 1
    fi

    # Field ranges: min(0-59) hour(0-23) dom(1-31) month(1-12) dow(0-7)
    local field_names=("minute" "hour" "day-of-month" "month" "day-of-week")
    local field_mins=(0 0 1 1 0)
    local field_maxs=(59 23 31 12 7)

    local idx
    for idx in 0 1 2 3 4; do
        local f="${fields[$idx]}"
        local fmin="${field_mins[$idx]}"
        local fmax="${field_maxs[$idx]}"
        local fname="${field_names[$idx]}"

        # Try to parse the field
        local parsed
        parsed=$(_parse_cron_field "$f" "$fmin" "$fmax")

        # Check that we got values
        if [[ -z "$parsed" ]]; then
            echo "Error: invalid ${fname} field: '$f'" >&2
            return 1
        fi

        # Check all values are within range
        local val
        for val in $parsed; do
            if [[ "$val" -lt "$fmin" || "$val" -gt "$fmax" ]]; then
                echo "Error: ${fname} value $val out of range ($fmin-$fmax)" >&2
                return 1
            fi
        done

        # Check for bad ranges (start > end) in range expressions
        IFS=',' read -ra parts <<< "$f"
        for part in "${parts[@]}"; do
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)(/[0-9]+)?$ ]]; then
                local rstart="${BASH_REMATCH[1]}" rend="${BASH_REMATCH[2]}"
                if [[ "$rstart" -gt "$rend" ]]; then
                    echo "Error: ${fname} range $rstart-$rend has start > end" >&2
                    return 1
                fi
            fi
        done
    done

    return 0
}

# ==============================================================================
# SCHEDULE MATCHING
# ==============================================================================

# Check if the current time matches a cron expression.
# $1 = cron expression (5 fields or preset)
# $2 = optional injected time for testing: "min hour dom month dow"
# Returns 0 if matches, 1 if not
cron_matches_now() {
    local schedule="$1"
    local injected_time="${2:-}"

    # Resolve presets
    local expr
    expr=$(_resolve_schedule "$schedule")

    # Split expression into fields
    local f_min f_hour f_dom f_month f_dow
    read -r f_min f_hour f_dom f_month f_dow <<< "$expr"

    # Get current time (or use injected time for testing)
    local cur_min cur_hour cur_dom cur_month cur_dow
    if [[ -n "$injected_time" ]]; then
        read -r cur_min cur_hour cur_dom cur_month cur_dow <<< "$injected_time"
    else
        local now
        now=$(date '+%M %H %d %m %w')
        read -r _min _hour _dom _month _dow <<< "$now"
        # Strip leading zeros via arithmetic
        cur_min=$((10#$_min))
        cur_hour=$((10#$_hour))
        cur_dom=$((10#$_dom))
        cur_month=$((10#$_month))
        cur_dow=$((10#$_dow))
    fi

    # Parse each cron field into list of valid values
    local mins hours doms months dows
    mins=$(_parse_cron_field "$f_min" 0 59)
    hours=$(_parse_cron_field "$f_hour" 0 23)
    doms=$(_parse_cron_field "$f_dom" 1 31)
    months=$(_parse_cron_field "$f_month" 1 12)
    dows=$(_parse_cron_field "$f_dow" 0 6)

    # Check minute, hour, month (always AND)
    _field_contains "$mins" "$cur_min" || return 1
    _field_contains "$hours" "$cur_hour" || return 1
    _field_contains "$months" "$cur_month" || return 1

    # DOM and DOW: OR logic when both non-wildcard, AND when either is wildcard
    local dom_match=0 dow_match=0
    _field_contains "$doms" "$cur_dom" && dom_match=1
    _field_contains "$dows" "$cur_dow" && dow_match=1

    if [[ "$f_dom" != "*" && "$f_dow" != "*" ]]; then
        # Both restricted: OR logic (POSIX cron behavior)
        [[ $dom_match -eq 1 || $dow_match -eq 1 ]] && return 0 || return 1
    else
        # One or both wildcard: AND logic
        [[ $dom_match -eq 1 && $dow_match -eq 1 ]] && return 0 || return 1
    fi
}

# ==============================================================================
# NEXT MATCH CALCULATION
# ==============================================================================

# Calculate minutes until the next cron match, iterating minute-by-minute.
# $1 = cron expression (5 fields or preset)
# $2 = optional injected start time: "min hour dom month dow"
# Output: "MINUTES_UNTIL HH:MM" on stdout
# Searches up to 1440 minutes (24 hours). Returns "no match within 24h" if none.
next_cron_match() {
    local schedule="$1"
    local injected_time="${2:-}"

    # Get starting time components
    local s_min s_hour s_dom s_month s_dow
    if [[ -n "$injected_time" ]]; then
        read -r s_min s_hour s_dom s_month s_dow <<< "$injected_time"
    else
        local now
        now=$(date '+%M %H %d %m %w')
        read -r _min _hour _dom _month _dow <<< "$now"
        s_min=$((10#$_min))
        s_hour=$((10#$_hour))
        s_dom=$((10#$_dom))
        s_month=$((10#$_month))
        s_dow=$((10#$_dow))
    fi

    local min="$s_min"
    local hour="$s_hour"
    local dom="$s_dom"
    local month="$s_month"
    local dow="$s_dow"

    local i
    for ((i=0; i<=1440; i++)); do
        local time_str="$min $hour $dom $month $dow"
        if cron_matches_now "$schedule" "$time_str"; then
            printf "%d %02d:%02d\n" "$i" "$hour" "$min"
            return 0
        fi

        # Advance by one minute
        min=$((min + 1))
        if [[ $min -ge 60 ]]; then
            min=0
            hour=$((hour + 1))
            if [[ $hour -ge 24 ]]; then
                hour=0
                dom=$((dom + 1))
                dow=$(( (dow + 1) % 7 ))
                # Simplified: cap dom at 28 to avoid month-length complexity
                if [[ $dom -gt 28 ]]; then
                    dom=1
                    month=$((month + 1))
                    if [[ $month -gt 12 ]]; then
                        month=1
                    fi
                fi
            fi
        fi
    done

    echo "no match within 24h"
    return 1
}
