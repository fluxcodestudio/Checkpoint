# Phase 21: Storage Usage Warnings - Research

**Researched:** 2026-02-16
**Domain:** Disk space monitoring, per-project storage analysis, shell scripting
**Confidence:** HIGH

<research_summary>
## Summary

Researched disk space monitoring patterns for a cross-platform (macOS/Linux) bash backup tool. Key finding: **the codebase already has 60-70% of the infrastructure needed** — `check_disk_space()`, `get_backup_disk_usage()`, `format_bytes()`, `send_notification()`, and the status display all exist.

Phase 21 is primarily a **wiring and enhancement** phase: add pre-backup disk checks, per-project storage breakdown, configurable thresholds, cleanup suggestions, and notification triggers using existing patterns.

**Primary recommendation:** Build on existing `check_disk_space()` in `lib/ops/file-ops.sh` and notification system in `lib/platform/compat.sh`. Add configurable thresholds, per-project `du -s` breakdown, and cleanup action suggestions. No external libraries needed.
</research_summary>

<standard_stack>
## Standard Stack

### Core (All Built-In Shell Tools)
| Tool | Purpose | Why Standard |
|------|---------|-------------|
| `df -P` | Volume-level disk space | POSIX-compliant, cross-platform consistent output |
| `du -s` | Per-directory size calculation | Reliable for 10-50GB dirs, no deps needed |
| `awk` | Parse df/du output | Already used throughout codebase |

### Already Implemented in Codebase
| Function | File | Purpose |
|----------|------|---------|
| `get_backup_disk_usage()` | `lib/ops/file-ops.sh:284` | Get disk usage % for backup dir |
| `check_disk_space()` | `lib/ops/file-ops.sh:298` | Returns 0/1/2 for ok/warning/critical |
| `get_total_backup_size()` | `lib/features/health-stats.sh:108` | Total backup size in bytes |
| `format_bytes()` | `lib/ui/time-size-utils.sh:84` | Human-readable size formatting |
| `get_dir_size_bytes()` | `lib/ui/time-size-utils.sh` | Cross-platform dir size |
| `send_notification()` | `lib/platform/compat.sh:94` | Cross-platform notifications |
| `should_notify()` | `lib/core/config.sh` | Respects quiet hours + urgency |
| `config_get_value()` / `config_set_value()` | `lib/core/config.sh` | Key-value config access |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `du -s` | diskus (Rust) | Faster for huge dirs but adds binary dependency — overkill |
| `df -P` | `statvfs` via python | More precise but adds python dependency — unnecessary |
| Custom thresholds | Fixed 80/90 only | Configurable is better for different user setups |
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Pattern 1: Pre-Backup Gate Check
**What:** Check disk space before starting a backup, skip/warn if insufficient
**When to use:** Every backup cycle in the daemon loop
**Example:**
```bash
# Before running rsync/backup
pre_backup_storage_check() {
    local backup_dir="$1"
    local usage
    usage=$(get_backup_disk_usage "$backup_dir")

    if [ "$usage" -ge "${STORAGE_CRITICAL_PERCENT:-90}" ]; then
        send_notification "Checkpoint" "Backup skipped: disk ${usage}% full"
        log_error "Backup skipped — destination ${usage}% full"
        return 1
    elif [ "$usage" -ge "${STORAGE_WARNING_PERCENT:-80}" ]; then
        send_notification "Checkpoint" "Disk space warning: ${usage}% full"
        log_warning "Destination disk ${usage}% full"
    fi
    return 0
}
```

### Pattern 2: Per-Project Storage Breakdown
**What:** Calculate and display per-project storage consumption from backup directory
**When to use:** In status display and cleanup suggestions
**Example:**
```bash
# Iterate registered projects, du -s each backup subdir
get_per_project_storage() {
    local backup_base="$1"
    while IFS= read -r project_dir; do
        local project_name=$(basename "$project_dir")
        local size_bytes=$(get_dir_size_bytes "$project_dir")
        echo "${size_bytes}|${project_name}"
    done < <(find "$backup_base" -mindepth 1 -maxdepth 1 -type d)
}
# Sort by size descending for display
```

### Pattern 3: Existing Config Variable Convention
**What:** Follow established `: "${VAR:=default}"` pattern with config mapping
**When to use:** Adding new STORAGE_* config variables
```bash
# In lib/core/config.sh — follow existing pattern:
: "${STORAGE_WARNING_PERCENT:=80}"
: "${STORAGE_CRITICAL_PERCENT:=90}"
: "${STORAGE_CHECK_ENABLED:=true}"
: "${STORAGE_CLEANUP_SUGGEST:=true}"
```

### Anti-Patterns to Avoid
- **Blocking backup on warning (only on critical):** Warning should notify but still backup — critical should skip
- **Running du on every backup cycle:** Cache per-project sizes, refresh periodically (every N backups or hourly)
- **Platform-specific df parsing without -P flag:** Always use `df -P` for POSIX output
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Notification delivery | New notification system | Existing `send_notification()` | Already cross-platform, tested |
| Quiet hours logic | New time window check | Existing `should_notify()` + `is_quiet_hours()` | Already handles edge cases |
| Size formatting | printf with manual units | Existing `format_bytes()` | Already handles B/KB/MB/GB |
| Config variable access | Direct env var reads | Existing `config_get_value()` | Handles layered defaults |
| Health status aggregation | New status tracker | Existing health status pattern in `backup-status.sh` | Already has WARNING/ERROR/HEALTHY |
| Disk usage percentage | Custom df parsing | Existing `get_backup_disk_usage()` | Already cross-platform |

**Key insight:** This phase is 70% integration of existing components. The novel work is: per-project breakdown, configurable thresholds (replacing hardcoded 80/90), cleanup suggestions, and pre-backup gating.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: `df` Output Parsing Across Platforms
**What goes wrong:** macOS BSD df and Linux GNU df produce subtly different output
**Why it happens:** Different implementations of the same command
**How to avoid:** Always use `df -P` (POSIX mode) which guarantees consistent column format. Existing `get_backup_disk_usage()` already handles this but verify.
**Warning signs:** Tests pass on macOS but fail on Linux (or vice versa)

### Pitfall 2: `du -s` Performance on Large Backup Directories
**What goes wrong:** `du -s` takes 10+ seconds on very large backup dirs, blocking the backup cycle
**Why it happens:** `du` walks the entire directory tree synchronously
**How to avoid:** Cache per-project sizes; refresh on a schedule (not every backup). Run `du` in background if needed. Use `du -s` not `du -sh` for machine-parseable output.
**Warning signs:** Backup cycle duration increases noticeably after adding storage checks

### Pitfall 3: Alert Spam When Disk Stays Full
**What goes wrong:** User gets notified every backup cycle that disk is 85% full
**Why it happens:** No throttling on repeated notifications for same condition
**How to avoid:** Use existing `NOTIFY_ESCALATION_HOURS` pattern — only re-notify after cooldown period. Track last notification time for storage alerts specifically.
**Warning signs:** User disables all notifications because storage alerts are too frequent

### Pitfall 4: Percentage-Only Thresholds on Large Volumes
**What goes wrong:** 80% of a 4TB drive = 800GB free, which is plenty. But 80% of 256GB SSD = 50GB free, which may not be.
**Why it happens:** Percentage thresholds don't account for absolute available space
**How to avoid:** Support both percentage AND absolute minimum free space thresholds. Default to percentage but allow `STORAGE_MIN_FREE_GB=50` override.
**Warning signs:** Users on large drives getting false warnings, users on small drives not getting warnings soon enough
</common_pitfalls>

<code_examples>
## Code Examples

### Cross-Platform Disk Space (POSIX)
```bash
# Source: POSIX df specification + existing codebase pattern
# df -P guarantees: Filesystem 512-blocks Used Available Capacity Mounted-on
get_volume_stats() {
    local path="$1"
    local df_output
    df_output=$(df -Pk "$path" | awk 'NR==2')

    local total_kb=$(echo "$df_output" | awk '{print $2}')
    local used_kb=$(echo "$df_output" | awk '{print $3}')
    local avail_kb=$(echo "$df_output" | awk '{print $4}')
    local pct_used=$(echo "$df_output" | awk '{gsub(/%/,""); print $5}')

    echo "${total_kb}|${used_kb}|${avail_kb}|${pct_used}"
}
```

### Per-Project Size with Caching
```bash
# Cache pattern: store sizes in state file, refresh periodically
STORAGE_CACHE_FILE="${STATE_DIR}/storage-cache.json"
STORAGE_CACHE_MAX_AGE=3600  # 1 hour

get_cached_project_sizes() {
    if [ -f "$STORAGE_CACHE_FILE" ]; then
        local age=$(( $(date +%s) - $(stat_mtime "$STORAGE_CACHE_FILE") ))
        if [ "$age" -lt "$STORAGE_CACHE_MAX_AGE" ]; then
            cat "$STORAGE_CACHE_FILE"
            return 0
        fi
    fi
    # Cache miss — recalculate
    refresh_project_sizes
}
```

### Cleanup Suggestions Pattern
```bash
# Suggest actions based on what's consuming space
suggest_cleanup() {
    local backup_dir="$1"

    echo "Storage cleanup suggestions:"

    # 1. Check for old archives beyond retention
    local old_archives=$(find "$backup_dir" -name "*.tar.gz" -mtime +30 2>/dev/null | wc -l)
    [ "$old_archives" -gt 0 ] && echo "  - $old_archives archives older than 30 days"

    # 2. Show largest projects
    echo "  - Largest backup projects:"
    du -sk "$backup_dir"/*/  2>/dev/null | sort -rn | head -5 | while read size dir; do
        echo "    $(format_bytes $((size * 1024))): $(basename "$dir")"
    done

    # 3. Suggest running retention cleanup
    echo "  - Run: checkpoint cleanup --dry-run"
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Fixed 80/90% thresholds | Configurable per-user thresholds | Users with different volume sizes need different settings |
| Percentage-only checks | Percentage + absolute minimum free space | Better accuracy across volume sizes |
| Check only on error | Pre-backup gate check | Prevents filling disk completely |

**Patterns from monitoring tools:**
- Multi-tier alerts (warning → critical → block) are industry standard
- Escalation cooldowns prevent alert fatigue
- Both percentage and absolute thresholds recommended

**Nothing exotic needed:** This is a well-solved domain. Shell built-ins (`df`, `du`) are sufficient. No external dependencies required.
</sota_updates>

<open_questions>
## Open Questions

1. **Should backup be blocked at critical threshold or just warned?**
   - Recommendation: Block at critical (90%+) to prevent filling disk completely. User can override with config.

2. **Should per-project sizes include archived versions?**
   - Recommendation: Yes — show total footprint including archives, since that's what consumes disk.

3. **Should cleanup suggestions auto-execute or just display?**
   - Recommendation: Display only with `--dry-run` suggestion. Never auto-delete user data.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Codebase analysis: `lib/ops/file-ops.sh` — existing `check_disk_space()`, `get_backup_disk_usage()`
- Codebase analysis: `lib/platform/compat.sh` — existing `send_notification()`, platform detection
- Codebase analysis: `lib/core/config.sh` — existing config variable patterns, notification settings
- Codebase analysis: `lib/features/health-stats.sh` — existing `get_total_backup_size()`
- Codebase analysis: `lib/ui/time-size-utils.sh` — existing `format_bytes()`, `get_dir_size_bytes()`
- Codebase analysis: `bin/backup-status.sh` — existing status display with disk warning integration

### Secondary (MEDIUM confidence)
- POSIX df specification — `df -P` for cross-platform output
- Industry monitoring tools (Veritas, EventSentry) — 80/90% threshold standards
- diskus benchmarks — confirms `du -s` adequate for <50GB dirs

### Tertiary (LOW confidence - needs validation)
- None — all findings verified against codebase or standards
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Shell built-ins (df, du, awk)
- Ecosystem: Existing codebase infrastructure (notifications, config, status)
- Patterns: Pre-backup gating, per-project breakdown, alert escalation
- Pitfalls: Cross-platform df, du performance, alert spam, percentage-only thresholds

**Confidence breakdown:**
- Standard stack: HIGH — all shell built-ins, no external deps
- Architecture: HIGH — building on well-established codebase patterns
- Pitfalls: HIGH — known cross-platform issues documented
- Code examples: HIGH — based on existing codebase patterns

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days — stable domain, no ecosystem churn)
</metadata>

---

*Phase: 21-storage-warnings*
*Research completed: 2026-02-16*
*Ready for planning: yes*
