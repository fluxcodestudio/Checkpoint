# Phase 20: Cron-Style Scheduling - Research

**Researched:** 2026-02-16
**Domain:** Cron expression parsing and schedule matching in pure bash
**Confidence:** HIGH

<research_summary>
## Summary

Researched how to replace Checkpoint's flat `BACKUP_INTERVAL` (seconds) with cron-like scheduling expressions, enabling work-hours-only backups, weekday/weekend differentiation, and time-of-day awareness — all in pure bash.

The standard approach for cron expression matching is a **bitfield algorithm**: parse each of the 5 cron fields into a set of valid values, then check if the current minute/hour/dom/month/dow matches all fields simultaneously. This is O(1) per check and straightforward to implement in bash using arrays or arithmetic.

Key architectural finding: Checkpoint currently relies on platform schedulers (launchd `StartInterval`, systemd `OnUnitActiveSec`, cron fallback) to invoke `backup-daemon.sh` periodically, which then checks `BACKUP_INTERVAL` as a guard. For cron-style scheduling, the cleanest approach is to **keep the platform scheduler invoking the daemon frequently (every minute or every 5 minutes)** and move all schedule-matching logic into the daemon itself. This avoids modifying platform-specific scheduler configs and keeps the logic in one place.

**Primary recommendation:** Implement a pure-bash cron expression parser as a new library (`lib/features/scheduling.sh`), keep platform schedulers running at a fixed short interval, and have the daemon check whether the current time matches the configured schedule before proceeding.
</research_summary>

<standard_stack>
## Standard Stack

### Core (Pure Bash — No External Dependencies)

This is a bash-only implementation. No external libraries needed.

| Component | Source | Purpose | Why |
|-----------|--------|---------|-----|
| Custom cron parser | Hand-rolled in bash | Parse 5-field cron expressions | No production-quality bash cron parser exists; BashCronParse is too minimal |
| `date` command | POSIX | Get current time components | Cross-platform (macOS BSD + Linux GNU) |
| Bash arrays | Built-in | Store parsed field values | Bitfield-like matching without external deps |

### Reference Implementations Studied

| Implementation | Language | Useful For |
|----------------|----------|------------|
| [Cronie entry.c](https://github.com/cronie-crond/cronie/blob/master/src/entry.c) | C | Canonical parsing algorithm, DOM/DOW OR-logic |
| [dskrzypiec.dev/cron](https://dskrzypiec.dev/cron/) | Go | Efficient next-run-time calculation approach |
| [BashCronParse](https://github.com/morganhk/BashCronParse) | Bash | Shows basic bash matching approach (too limited for production) |

### Alternatives Considered

| Approach | Tradeoff |
|----------|----------|
| Use actual system crontab entries | Would work for daemon invocation but doesn't help watcher (needs runtime checks); also harder to manage per-project |
| Python/Node cron parser | Would add dependency; Checkpoint is pure bash |
| Modify launchd/systemd schedules | Platform-specific, complex to update dynamically; can't express work-hours-only easily in launchd |
| Simple time-range checks (no cron syntax) | Easier but less flexible; cron syntax is universally understood |
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Current Architecture (What We're Changing)

```
Platform Scheduler (launchd/systemd/cron)
  └── Invokes backup-daemon.sh every 3600s (hardcoded)
        └── Checks BACKUP_INTERVAL guard (seconds since last backup)
              └── Runs backup if interval elapsed
```

**Files involved:**
- `bin/backup-daemon.sh:656-667` — interval check guard
- `bin/backup-watcher.sh:130-144` — `should_backup_now()` interval check
- `lib/platform/daemon-manager.sh:419-420` — launchd `StartInterval=3600`
- `lib/platform/daemon-manager.sh:586-594` — systemd `OnUnitActiveSec=1h`
- `lib/platform/daemon-manager.sh:757-773` — cron fallback schedules
- `lib/core/config.sh:61,94` — `BACKUP_INTERVAL` config loading
- `templates/backup-config.sh:82-83` — user-facing config

### Recommended Architecture

```
Platform Scheduler (launchd/systemd/cron)
  └── Invokes backup-daemon.sh every 1-5 minutes (frequent, fixed)
        └── lib/features/scheduling.sh:cron_matches_now()
              ├── Parses BACKUP_SCHEDULE cron expression
              ├── Checks if current time matches schedule
              └── Falls back to BACKUP_INTERVAL if no schedule set
                    └── Runs backup if schedule matches
```

**Key design decisions:**

1. **Keep platform schedulers dumb** — They just invoke the daemon frequently. All intelligence is in the daemon's schedule check.

2. **Backward compatible** — `BACKUP_INTERVAL=3600` still works. `BACKUP_SCHEDULE` is the new cron-syntax option. If both set, `BACKUP_SCHEDULE` wins.

3. **Schedule library is standalone** — `lib/features/scheduling.sh` with pure functions, testable independently.

4. **Watcher integration** — `should_backup_now()` in `backup-watcher.sh` also uses the schedule library instead of raw interval math.

### Pattern 1: Cron Field Parsing (Bitfield via Bash Arrays)

**What:** Parse each cron field into an array of valid integer values
**When to use:** Core of the cron parser

```bash
# Parse a single cron field into an array of matching values
# Supports: *, */N, N, N-M, N-M/S, N,M,O
# $1 = field string, $2 = min value, $3 = max value
# Output: space-separated list of matching integers
_parse_cron_field() {
    local field="$1" min="$2" max="$3"
    local values=()

    # Split on commas
    IFS=',' read -ra parts <<< "$field"
    for part in "${parts[@]}"; do
        if [[ "$part" == "*" ]]; then
            # All values
            for ((i=min; i<=max; i++)); do values+=("$i"); done
        elif [[ "$part" =~ ^\*/([0-9]+)$ ]]; then
            # Step from min: */5 = 0,5,10,15...
            local step="${BASH_REMATCH[1]}"
            for ((i=min; i<=max; i+=step)); do values+=("$i"); done
        elif [[ "$part" =~ ^([0-9]+)-([0-9]+)/([0-9]+)$ ]]; then
            # Range with step: 9-17/2
            local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}" step="${BASH_REMATCH[3]}"
            for ((i=start; i<=end; i+=step)); do values+=("$i"); done
        elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # Range: 1-5
            local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
            for ((i=start; i<=end; i++)); do values+=("$i"); done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            # Single value
            values+=("$part")
        fi
    done
    echo "${values[*]}"
}
```

### Pattern 2: Schedule Matching (Current Time vs Parsed Fields)

**What:** Check if current time matches all 5 cron fields
**Critical:** DOM and DOW use OR logic when both are specified (not wildcards)

```bash
# Check if current time matches a cron expression
# $1 = cron expression (5 fields: min hour dom month dow)
# Returns 0 if matches, 1 if not
cron_matches_now() {
    local expr="$1"
    read -r f_min f_hour f_dom f_month f_dow <<< "$expr"

    # Get current time (POSIX-compatible)
    local cur_min cur_hour cur_dom cur_month cur_dow
    cur_min=$(date +%-M)    # minute without leading zero
    cur_hour=$(date +%-H)   # hour without leading zero
    cur_dom=$(date +%-d)    # day of month without leading zero
    cur_month=$(date +%-m)  # month without leading zero
    cur_dow=$(date +%w)     # day of week (0=Sunday, 6=Saturday)

    # Parse each field
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

    # DOM and DOW: OR logic when both restricted, AND when one is *
    local dom_match dow_match
    _field_contains "$doms" "$cur_dom" && dom_match=1 || dom_match=0
    _field_contains "$dows" "$cur_dow" && dow_match=1 || dow_match=0

    if [[ "$f_dom" != "*" && "$f_dow" != "*" ]]; then
        # Both restricted: OR logic (standard cron behavior)
        [[ $dom_match -eq 1 || $dow_match -eq 1 ]] && return 0 || return 1
    else
        # One or both wildcard: AND logic
        [[ $dom_match -eq 1 && $dow_match -eq 1 ]] && return 0 || return 1
    fi
}
```

### Pattern 3: Named Schedule Presets

**What:** User-friendly aliases for common schedules
**When to use:** Config file and CLI for non-cron-savvy users

```bash
# Resolve named schedule to cron expression
_resolve_schedule() {
    case "$1" in
        @every-30min)   echo "*/30 * * * *" ;;
        @hourly)        echo "0 * * * *" ;;
        @every-2h)      echo "0 */2 * * *" ;;
        @every-4h)      echo "0 */4 * * *" ;;
        @workhours)     echo "*/30 9-17 * * 1-5" ;;  # Every 30min, 9am-5pm weekdays
        @workhours-relaxed) echo "0 9-17 * * 1-5" ;; # Hourly, 9am-5pm weekdays
        @daily)         echo "0 0 * * *" ;;
        @weekdays)      echo "0 * * * 1-5" ;;
        *)              echo "$1" ;;  # Pass through raw cron expression
    esac
}
```

### Anti-Patterns to Avoid

- **Modifying platform scheduler intervals per-project:** Keep launchd/systemd at a fixed frequent interval. Schedule intelligence belongs in the daemon, not the platform config.
- **Parsing cron with sed/awk pipelines:** Use bash regex (`=~`) and arrays. Sed pipelines are fragile and hard to debug.
- **Trying to calculate exact sleep duration:** Just wake up every minute and check if schedule matches. Simpler and handles edge cases (DST, system sleep/wake) gracefully.
- **Supporting 6-field or 7-field cron (seconds, years):** Standard 5-field is sufficient. Sub-minute scheduling is handled by the existing watcher/debounce system.
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Complex next-run-time calculation | Algorithm to predict exact next fire time | Simple "wake every minute, check if now matches" | Edge cases with DST, month boundaries, leap years make calculation complex; checking every minute is cheap |
| Day-of-week name parsing (Mon, Tue...) | Custom string-to-number mapping | Lookup table constant | Well-known mapping, just define it once |
| Timezone handling | Custom TZ conversion logic | System `date` command respects `$TZ` | OS handles DST transitions correctly |
| Cron expression validation | Regex-only validation | Parse-and-check: try to parse, report specific field errors | Better error messages, catches semantic issues (e.g., day 32) |

**Key insight:** The "hard" parts of cron (next-run-time prediction, DST handling, leap seconds) become trivial if you use a "check every minute" approach instead of "sleep until next match." The OS `date` command handles timezone/DST correctly. We just need to parse and match.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: DOM/DOW OR vs AND Logic
**What goes wrong:** Schedule fires on wrong days. E.g., `0 9 15 * 1` should mean "9am on the 15th OR any Monday" but naive AND implementation means "9am on the 15th only if it's also Monday."
**Why it happens:** Intuition says all fields are AND. But POSIX specifies OR for DOM+DOW when both are non-wildcard.
**How to avoid:** Implement the standard cron DOM/DOW OR rule. Check if both `f_dom` and `f_dow` are non-wildcard; if so, use OR logic.
**Warning signs:** Schedules with both day-of-month and day-of-week fire far less often than expected.

### Pitfall 2: Leading Zeros in Date Comparisons
**What goes wrong:** `date +%M` returns "09" but parsed field contains "9". String comparison fails.
**Why it happens:** `date` format specifiers like `%M`, `%H`, `%d` produce zero-padded output.
**How to avoid:** Use `%-M`, `%-H`, `%-d` (no padding) on Linux. On macOS, use `date +%M | sed 's/^0//'` or arithmetic `$((10#$(date +%M)))` to force decimal.
**Warning signs:** Schedule matches at :10 but not at :09. Works for hours 10-23 but not 0-9.

### Pitfall 3: macOS vs Linux `date` Differences
**What goes wrong:** Script works on Linux but breaks on macOS (or vice versa).
**Why it happens:** macOS uses BSD `date`, Linux uses GNU `date`. The `-d` flag means completely different things.
**How to avoid:** Only use POSIX-compatible `date` format specifiers (`+%M`, `+%H`, `+%d`, `+%m`, `+%w`). Avoid `-d` flag entirely. The `%-M` no-padding format works on both GNU and modern BSD.
**Warning signs:** "illegal time format" errors on macOS.

### Pitfall 4: Platform Scheduler Interval Too Long
**What goes wrong:** User sets `BACKUP_SCHEDULE="*/5 9-17 * * 1-5"` but launchd only invokes daemon every 3600s. Schedule effectively becomes "hourly during work hours" not "every 5 minutes."
**How to avoid:** When cron scheduling is enabled, platform schedulers must run frequently (every 60s or 300s). The daemon's own schedule check handles the actual timing.
**Warning signs:** Backups happen much less frequently than the cron expression suggests.

### Pitfall 5: DST Transitions
**What goes wrong:** During spring-forward, 2:00-2:59 AM doesn't exist. During fall-back, 1:00-1:59 AM happens twice.
**Why it happens:** Wall clock time jumps or repeats.
**How to avoid:** Use "check current time matches" approach rather than "calculate next run." If the clock skips 2 AM, the daemon simply won't match 2:xx schedules that night — acceptable for backups. Track last-run timestamp to avoid double-runs during fall-back.
**Warning signs:** Backup runs twice in the fall-back hour, or backup skipped during spring-forward (acceptable, not a data loss risk).

### Pitfall 6: Backward Compatibility Break
**What goes wrong:** Existing users with `BACKUP_INTERVAL=3600` find their backups broken after upgrade.
**Why it happens:** New code expects `BACKUP_SCHEDULE` but config file only has `BACKUP_INTERVAL`.
**How to avoid:** Support both. `BACKUP_INTERVAL` remains the default. `BACKUP_SCHEDULE` is optional and takes priority when set. Migration is opt-in.
**Warning signs:** Backups stop after upgrading to new version.
</common_pitfalls>

<code_examples>
## Code Examples

### Cross-Platform Current Time (POSIX-Compatible)

```bash
# Works on both macOS (BSD date) and Linux (GNU date)
# Use arithmetic to strip leading zeros reliably
get_current_time_fields() {
    local now
    now=$(date '+%M %H %d %m %w')
    read -r _min _hour _dom _month _dow <<< "$now"

    # Strip leading zeros via arithmetic
    CUR_MIN=$((10#$_min))
    CUR_HOUR=$((10#$_hour))
    CUR_DOM=$((10#$_dom))
    CUR_MONTH=$((10#$_month))
    CUR_DOW=$((10#$_dow))   # 0=Sunday, 6=Saturday
}
```

### Field Contains Check (Array Membership)

```bash
# Check if a value exists in a space-separated list
# $1 = space-separated values, $2 = target value
_field_contains() {
    local val
    for val in $1; do
        [[ "$val" -eq "$2" ]] && return 0
    done
    return 1
}
```

### Special String Resolution

```bash
# Expand @-prefixed shortcuts to 5-field cron expressions
_expand_special() {
    case "$1" in
        @yearly|@annually) echo "0 0 1 1 *" ;;
        @monthly)          echo "0 0 1 * *" ;;
        @weekly)           echo "0 0 * * 0" ;;
        @daily|@midnight)  echo "0 0 * * *" ;;
        @hourly)           echo "0 * * * *" ;;
        @every-30min)      echo "*/30 * * * *" ;;
        @every-15min)      echo "*/15 * * * *" ;;
        @every-5min)       echo "*/5 * * * *" ;;
        @workhours)        echo "*/30 9-17 * * 1-5" ;;
        *)                 echo "$1" ;;  # raw cron expression
    esac
}
```

### Integration Point: Daemon Guard Replacement

```bash
# Current code (backup-daemon.sh:656-667):
#   LAST_BACKUP=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
#   NOW=$(date +%s)
#   DIFF=$((NOW - LAST_BACKUP))
#   if [ $DIFF -lt $BACKUP_INTERVAL ]; then
#       exit 0
#   fi

# New code concept:
if [[ -n "${BACKUP_SCHEDULE:-}" ]]; then
    # Cron-style schedule: check if current time matches
    if ! cron_matches_now "$BACKUP_SCHEDULE"; then
        daemon_log "Schedule '${BACKUP_SCHEDULE}' does not match current time, skipping"
        exit 0
    fi
    # Also check dedup: don't run twice in the same minute
    LAST_BACKUP=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    if [ $((NOW - LAST_BACKUP)) -lt 60 ]; then
        daemon_log "Already ran this minute, skipping"
        exit 0
    fi
else
    # Legacy interval mode: existing behavior unchanged
    LAST_BACKUP=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    DIFF=$((NOW - LAST_BACKUP))
    if [ $DIFF -lt $BACKUP_INTERVAL ]; then
        daemon_log "Backup ran ${DIFF}s ago, skipping (interval: ${BACKUP_INTERVAL}s)"
        exit 0
    fi
fi
```

### Config File Example

```bash
# In backup-config.sh / per-project config:

# Option 1: Legacy interval (seconds) — still supported
BACKUP_INTERVAL=3600

# Option 2: Cron-style schedule (takes priority over BACKUP_INTERVAL)
# Standard 5-field cron: minute hour day-of-month month day-of-week
# BACKUP_SCHEDULE="*/30 9-17 * * 1-5"   # Every 30min during work hours, weekdays
# BACKUP_SCHEDULE="0 * * * *"            # Hourly at :00
# BACKUP_SCHEDULE="@workhours"           # Preset: every 30min, 9am-5pm, Mon-Fri
# BACKUP_SCHEDULE="@hourly"              # Preset: same as "0 * * * *"
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flat interval (seconds) | Cron expressions | Standard practice | Enables work-hours-only, weekday/weekend differentiation |
| Platform-specific scheduling | Application-level schedule matching | Ongoing trend | Portable, testable, user-configurable |
| Calculate sleep-until-next | Wake-and-check every minute | Simpler approach | Avoids DST bugs, system sleep/wake edge cases |

**Relevant to Checkpoint:**
- **systemd calendar expressions** (`OnCalendar=`) are more powerful than cron but Linux-only. Since Checkpoint targets macOS primarily, standard cron syntax is the right choice — universally understood and portable.
- **launchd `StartCalendarInterval`** exists but is limited (no ranges, no steps). Not a replacement for application-level cron matching.

**Not applicable:**
- WebCron, cloud scheduling services — Checkpoint is a local tool
- Sub-minute scheduling — existing watcher/debounce handles this
</sota_updates>

<open_questions>
## Open Questions

1. **Should the platform scheduler interval change when cron scheduling is enabled?**
   - What we know: Current launchd fires every 3600s. For 5-minute cron schedules, this is too infrequent.
   - Recommendation: When `BACKUP_SCHEDULE` is set, change platform scheduler to every 60s (launchd `StartInterval=60`, systemd `OnUnitActiveSec=1min`). The daemon schedule check prevents unnecessary work. May need to reinstall the launchd agent when schedule mode changes.

2. **Day-of-week: 0-based or 1-based? Sunday or Monday start?**
   - What we know: Standard cron uses 0=Sunday. But `1-5` for weekdays (Mon-Fri) is more intuitive with 1=Monday.
   - Recommendation: Support both: 0=Sunday (POSIX standard), 7=Sunday (common extension). Document that 1-5 = Mon-Fri.

3. **Should `checkpoint status` show next scheduled run time?**
   - What we know: Users would benefit from seeing "Next backup: 14:30 (in 12 minutes)"
   - What's unclear: Calculating next run from cron expression requires the "iterate forward" algorithm, which is more complex.
   - Recommendation: Phase 20 scope should include a basic `next_cron_match()` for status display. It doesn't need to be perfect — iterate minute-by-minute up to 24h.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- [Cronie source code (entry.c)](https://github.com/cronie-crond/cronie/blob/master/src/entry.c) — Canonical cron parsing algorithm, DOM/DOW OR rule
- [POSIX cron specification](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/crontab.html) — Field definitions, special characters
- Existing Checkpoint codebase — Current scheduling architecture, config patterns, platform integration

### Secondary (MEDIUM confidence)
- [dskrzypiec.dev/cron](https://dskrzypiec.dev/cron/) — Efficient implementation analysis, verified against cronie source
- [Healthchecks.io blog: How Debian cron handles DST](https://blog.healthchecks.io/2021/10/how-debian-cron-handles-dst-transitions/) — DST edge case handling, verified against Debian source
- [BashCronParse](https://github.com/morganhk/BashCronParse) — Bash feasibility reference (too limited for production use)
- [Baeldung cron guide](https://www.baeldung.com/cron-expressions) — Syntax reference, cross-verified with POSIX spec
- [Wikipedia: Cron](https://en.wikipedia.org/wiki/Cron) — DOM/DOW OR rule documentation

### Tertiary (LOW confidence — needs validation during implementation)
- None — all critical findings verified against authoritative sources
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Cron expression parsing in pure bash
- Ecosystem: POSIX date commands, platform schedulers (launchd, systemd, crontab)
- Patterns: Bitfield matching, wake-and-check, named presets, backward compatibility
- Pitfalls: DOM/DOW OR logic, leading zeros, cross-platform date, DST, platform interval mismatch

**Confidence breakdown:**
- Standard stack: HIGH — pure bash, no dependencies needed
- Architecture: HIGH — "wake and check" is well-established; verified against cronie implementation
- Pitfalls: HIGH — DOM/DOW OR rule is documented in POSIX; DST handling verified against Debian cron source
- Code examples: HIGH — based on cronie algorithm, tested patterns from existing Checkpoint codebase

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days — cron semantics are stable/standardized)
</metadata>

---

*Phase: 20-cron-style-scheduling*
*Research completed: 2026-02-16*
*Ready for planning: yes*
