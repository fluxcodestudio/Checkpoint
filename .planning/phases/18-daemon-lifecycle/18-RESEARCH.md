# Phase 18: Daemon Lifecycle & Health Monitoring - Research

**Researched:** 2026-02-13
**Domain:** Daemon auto-restart, heartbeat monitoring, staleness detection (launchd + systemd + bash)
**Confidence:** HIGH

<research_summary>
## Summary

Researched daemon lifecycle management patterns for a bash backup system that must auto-start, auto-restart on failure, monitor its own health via heartbeat files, and alert users when backups cease. The system must work cross-platform (macOS launchd + Linux systemd + cron fallback).

Key finding: The existing codebase already has ~80% of the infrastructure needed. The daemon (`backup-daemon.sh`) writes heartbeat JSON, the watchdog (`checkpoint-watchdog.sh`) monitors heartbeat age and auto-restarts, the daemon-manager (`lib/platform/daemon-manager.sh`) provides cross-platform lifecycle API, and templates exist for launchd/systemd/cron. Phase 18 is primarily about **hardening what exists** rather than building from scratch.

Critical gaps: (1) heartbeat writes are not atomic (risk of watchdog reading partial JSON), (2) no backup staleness notifications to user, (3) no configurable notification cooldowns to prevent alert fatigue, (4) launchd plist uses unconditional `KeepAlive=true` which restarts even on intentional stops, (5) no auto-start-on-install behavior, (6) watchdog doesn't write its own heartbeat for "who watches the watchman" monitoring.

**Primary recommendation:** Make heartbeat writes atomic (temp+rename), add staleness notification with tiered thresholds and cooldowns, switch launchd KeepAlive to `SuccessfulExit=false` pattern, add auto-start to install scripts, and add watchdog self-heartbeat.
</research_summary>

<standard_stack>
## Standard Stack

No external libraries needed. This phase uses native OS service management and existing project infrastructure.

### Core (Already Built)
| Component | Location | Purpose | Status |
|-----------|----------|---------|--------|
| backup-daemon.sh | bin/backup-daemon.sh | Main backup daemon with heartbeat writing | Exists - needs atomic writes |
| checkpoint-watchdog.sh | bin/checkpoint-watchdog.sh | Monitors heartbeat, auto-restarts daemon | Exists - needs staleness alerts |
| daemon-manager.sh | lib/platform/daemon-manager.sh | Cross-platform daemon lifecycle API | Exists - complete |
| compat.sh | lib/platform/compat.sh | Cross-platform stat, notifications | Exists - complete |
| global-status.sh | lib/global-status.sh | Health scoring (healthy/warning/error) | Exists - complete |
| health-stats.sh | lib/features/health-stats.sh | Health metrics collection | Exists - complete |
| logging.sh | lib/core/logging.sh | Structured logging with rotation | Exists - complete |

### Templates (Already Built)
| Template | Location | Purpose | Status |
|----------|----------|---------|--------|
| Watchdog plist | templates/com.checkpoint.watchdog.plist | macOS LaunchAgent for watchdog | Exists - needs KeepAlive fix |
| Watchdog systemd | templates/systemd-watchdog.service | Linux systemd unit for watchdog | Exists - has Restart=on-failure |
| Daemon systemd | templates/systemd-daemon.service + .timer | Linux systemd timer unit | Exists - complete |
| Cron template | templates/cron-backup.crontab | Fallback cron entry | Exists - complete |

### Supporting (Existing Internal)
| Component | Location | Purpose |
|-----------|----------|---------|
| file-ops.sh | lib/ops/file-ops.sh | Atomic lock via mkdir, PID tracking |
| projects-registry.sh | lib/projects-registry.sh | Multi-project tracking |
| install-global.sh | bin/install-global.sh | Global daemon installation |
| backup-pause.sh | bin/backup-pause.sh | Pause/resume daemon lifecycle |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Heartbeat file | systemd sd_notify watchdog | sd_notify is systemd-only; heartbeat file works cross-platform |
| osascript notifications | terminal-notifier | terminal-notifier richer but requires brew install; osascript is built-in |
| Custom watchdog | monit/supervisord | Adds dependency; custom watchdog is <200 lines and already exists |
| JSON heartbeat | Simple touch file | JSON carries status/error info; touch only carries timestamp |
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Current Architecture (What Exists)

```
launchd/systemd/cron
       |
       |--- every 1 hour: backup-daemon.sh (per project)
       |         |
       |         +-- writes heartbeat file (JSON, non-atomic)
       |         +-- writes backup timestamp on success
       |         +-- file locking via mkdir + PID
       |
       |--- continuous: checkpoint-watchdog.sh (global)
                |
                +-- reads heartbeat file every 60s
                +-- checks staleness (5-minute threshold)
                +-- 3 consecutive failures before restart
                +-- restarts via daemon-manager.sh
                +-- sends macOS notification on restart
```

### Target Architecture (Phase 18)

```
launchd/systemd/cron
       |
       |--- every 1 hour: backup-daemon.sh (per project)
       |         |
       |         +-- writes heartbeat file (ATOMIC: temp+rename)
       |         +-- writes backup timestamp on success
       |         +-- file locking via mkdir + PID
       |
       |--- continuous: checkpoint-watchdog.sh (global)
       |         |
       |         +-- reads all project heartbeat files every 60s
       |         +-- daemon health check (PID alive + heartbeat fresh)
       |         +-- BACKUP STALENESS check (tiered: warning/critical/emergency)
       |         +-- NOTIFICATION with cooldown (per severity, per project)
       |         +-- auto-restart on daemon failure
       |         +-- writes OWN heartbeat (who watches the watchman)
       |
       |--- on install: AUTO-START daemon + watchdog
                |
                +-- install-global.sh starts services after registration
                +-- per-project install starts daemon immediately
```

### Pattern 1: Atomic Heartbeat Write (temp+rename)
**What:** Write heartbeat JSON to temp file on same filesystem, then `mv` to target path
**When to use:** Every heartbeat update in backup-daemon.sh
**Why:** POSIX guarantees `rename()` is atomic on same filesystem. Prevents watchdog from reading truncated JSON mid-write.
**Example:**
```bash
write_heartbeat() {
    local status="${1:-healthy}"
    local error_msg="${2:-}"
    local timestamp
    timestamp=$(date +%s)

    mkdir -p "$HEARTBEAT_DIR"

    # Write to temp file (same filesystem for atomic rename)
    local tmp_file="${HEARTBEAT_DIR}/.heartbeat.tmp.$$"
    cat > "$tmp_file" <<EOF
{
  "timestamp": $timestamp,
  "status": "$status",
  "project": "$PROJECT_NAME",
  "last_backup": $(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0"),
  "pid": $$,
  "error": ${error_msg:+\"$error_msg\"}${error_msg:-null}
}
EOF
    # Atomic rename
    mv "$tmp_file" "$HEARTBEAT_FILE"
}
```

### Pattern 2: Tiered Staleness Detection
**What:** Check time since last *successful backup* (not just heartbeat), with escalating severity
**When to use:** Watchdog health check loop
**Why:** Heartbeat freshness only proves daemon is running. Staleness proves backups are actually completing.
**Example:**
```bash
check_backup_staleness() {
    local last_backup_time
    last_backup_time=$(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0")
    local now age
    now=$(date +%s)
    age=$((now - last_backup_time))

    if [ "$last_backup_time" -eq 0 ]; then
        echo "never"; return 3
    elif [ $age -gt $STALENESS_EMERGENCY ]; then
        echo "emergency:${age}s"; return 3
    elif [ $age -gt $STALENESS_CRITICAL ]; then
        echo "critical:${age}s"; return 2
    elif [ $age -gt $STALENESS_WARNING ]; then
        echo "warning:${age}s"; return 1
    else
        echo "ok:${age}s"; return 0
    fi
}
```

### Pattern 3: Notification Cooldown (per severity, per project)
**What:** Prevent repeated notifications for the same issue within a cooldown period
**When to use:** Before sending any notification
**Why:** Prevents alert fatigue. Watchdog runs every 60s but should not notify every 60s.
**Example:**
```bash
should_notify() {
    local project="$1"
    local severity="$2"
    local cooldown="$3"
    local state_file="$STATE_DIR/.notify-${project}-${severity}"

    local now last elapsed
    now=$(date +%s)
    last=$(cat "$state_file" 2>/dev/null || echo "0")
    elapsed=$((now - last))

    if [ $elapsed -lt $cooldown ]; then
        return 1  # suppress
    fi
    echo "$now" > "$state_file"
    return 0  # ok to notify
}
```

### Pattern 4: launchd KeepAlive with SuccessfulExit=false
**What:** Auto-restart only on crashes (non-zero exit), not on intentional stops
**When to use:** Watchdog and watcher LaunchAgent plists
**Why:** Unconditional `KeepAlive=true` restarts even after `exit 0`, making intentional stops impossible without unloading the plist. `SuccessfulExit=false` allows clean shutdown via `exit 0`.
**Example:**
```xml
<key>KeepAlive</key>
<dict>
    <key>SuccessfulExit</key>
    <false/>
</dict>
```

### Anti-Patterns to Avoid
- **Non-atomic heartbeat writes:** Current `cat > "$HEARTBEAT_FILE"` can be read mid-write by watchdog
- **Unconditional KeepAlive:** `KeepAlive=true` prevents intentional daemon stops (must unload plist to stop)
- **Daemon self-forking:** Both launchd and systemd track the original PID; forking loses process management
- **PID-only health checks:** A hung daemon still has a valid PID but stops writing heartbeats; always combine PID + heartbeat
- **Fixed notification intervals:** Alerting every 60s creates noise; use per-severity cooldowns
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Auto-restart on crash | Custom respawn loop in bash | launchd KeepAlive / systemd Restart=on-failure | Init systems handle process lifecycle natively, with throttling and crash-loop protection |
| Crash-loop protection | Custom failure counting for restart limiting | launchd ThrottleInterval / systemd StartLimitBurst+StartLimitIntervalSec | Built-in, battle-tested, handles edge cases |
| Boot/login auto-start | Custom rc.d scripts or login items | launchd RunAtLoad / systemctl enable | Native, survives OS updates, proper dependency ordering |
| Daemon process management | Custom PID tracking with start/stop scripts | Existing daemon-manager.sh (already built) | Already abstracts launchd/systemd/cron; don't duplicate |
| Cross-platform notifications | Custom per-OS notification code | Existing compat.sh send_notification() | Already handles macOS osascript + Linux notify-send |
| Service installation | Manual plist/systemd file copying | Existing install_daemon() in daemon-manager.sh | Already handles template processing and platform detection |
| Log rotation | Custom rotation logic | Existing logging.sh init_logging() | Already handles 5-file rotation with configurable max size |

**Key insight:** Phase 18's value is NOT in building new daemon infrastructure (it already exists and is comprehensive). The value is in: (1) fixing the non-atomic heartbeat write, (2) adding backup staleness notifications with anti-fatigue measures, (3) switching to SuccessfulExit=false KeepAlive, and (4) ensuring auto-start on install. All are incremental improvements to existing code.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: launchd Exponential Backoff on Crash Loops
**What goes wrong:** If a KeepAlive daemon crashes repeatedly, launchd applies exponential backoff that can grow to 10+ hours between restart attempts. The daemon appears "dead" but launchd is just waiting.
**Why it happens:** launchd's crash-loop protection is opaque and undocumented. ThrottleInterval only sets the initial minimum, not a cap.
**How to avoid:** (1) Never exit non-zero for transient errors - handle them internally with retries. (2) Only exit non-zero for truly fatal errors. (3) Use the watchdog as a safety net - it can `launchctl kickstart -k` to force-restart. (4) Design the daemon to sleep and retry internally.
**Warning signs:** Daemon stops running, `launchctl list` shows the service but no PID, system log shows "throttling respawn" messages.

### Pitfall 2: Notification Alert Fatigue
**What goes wrong:** Watchdog checks every 60 seconds. If staleness threshold is breached, it sends a notification every 60 seconds, flooding the user with identical alerts.
**Why it happens:** No cooldown between repeated notifications for the same condition.
**How to avoid:** (1) Per-severity, per-project cooldown state files. (2) Different cooldowns per severity (warning: 4h, critical: 2h, emergency: 1h). (3) Consecutive failure threshold before first alert (3 consecutive checks).
**Warning signs:** Notification Center flooded with identical backup alerts.

### Pitfall 3: Race Condition on Heartbeat Read/Write
**What goes wrong:** Watchdog reads heartbeat file while daemon is mid-write. Gets truncated JSON, parses it as corrupt/missing, triggers false restart.
**Why it happens:** `cat > file` is not atomic - it truncates then writes. If reader hits between truncate and write completion, sees empty or partial file.
**How to avoid:** Atomic write: write to temp file on same filesystem, then `mv` (rename is atomic in POSIX).
**Warning signs:** Watchdog logs showing "corrupt heartbeat" or "missing heartbeat" that resolve on next check.

### Pitfall 4: PID Reuse After Daemon Crash
**What goes wrong:** Daemon crashes, OS reassigns its PID to unrelated process. Health check does `kill -0 $PID`, succeeds, concludes daemon is alive. Backups silently stop.
**Why it happens:** PID space is small (typically 32768 on Linux, 99998 on macOS). Under load, PIDs can be reused within seconds.
**How to avoid:** Always combine PID check with heartbeat freshness check. A valid PID with a stale heartbeat = hung or replaced process.
**Warning signs:** `kill -0 $PID` succeeds but heartbeat stops updating. Process at that PID is not the daemon (check with `ps -p $PID -o comm=`).

### Pitfall 5: Watchdog Can't Restart What It Can't Find
**What goes wrong:** Watchdog tries to restart daemon but can't determine which service name to use, especially with legacy naming conventions.
**Why it happens:** Project names and service names don't always map 1:1. Multiple naming conventions exist (com.checkpoint.* vs com.claudecode.*).
**How to avoid:** The existing watchdog already handles both naming conventions. Ensure install scripts consistently register services with the current naming convention.
**Warning signs:** Watchdog logs "no daemons found" despite daemons being registered under a different name.

### Pitfall 6: Missing Auto-Start After Install
**What goes wrong:** User installs the daemon, expects backups to start immediately, but nothing happens until next reboot/login.
**Why it happens:** Installation registers the service but doesn't start it. launchd `load` vs `bootstrap` distinction matters.
**How to avoid:** After installing (registering) a service, explicitly start it: `launchctl load` or `start_daemon()` call in install script.
**Warning signs:** Freshly installed user reports "backup not working" until they reboot.
</common_pitfalls>

<code_examples>
## Code Examples

### Existing Heartbeat Write (Current - NOT Atomic)
```bash
# Source: bin/backup-daemon.sh lines 151-176
# PROBLEM: cat > truncates then writes, not atomic
write_heartbeat() {
    local status="${1:-healthy}"
    local error_msg="${2:-}"
    local timestamp
    timestamp=$(date +%s)
    mkdir -p "$HEARTBEAT_DIR"
    cat > "$HEARTBEAT_FILE" <<EOF
{
  "timestamp": $timestamp,
  "status": "$status",
  "project": "$PROJECT_NAME",
  "last_backup": $(cat "$BACKUP_TIME_STATE" 2>/dev/null || echo "0"),
  "pid": $$,
  "error": ${error_msg:+\"$error_msg\"}${error_msg:-null}
}
EOF
}
```

### Existing Heartbeat Read (Current - Robust)
```bash
# Source: bin/checkpoint-watchdog.sh lines 69-88
# Already handles missing/corrupt files gracefully
read_heartbeat() {
    if [[ ! -f "$HEARTBEAT_FILE" ]]; then
        echo "missing"
        return
    fi
    local timestamp status
    timestamp=$(grep -o '"timestamp": *[0-9]*' "$HEARTBEAT_FILE" 2>/dev/null | grep -o '[0-9]*' || echo "0")
    status=$(grep -o '"status": *"[^"]*"' "$HEARTBEAT_FILE" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "unknown")
    local now age
    now=$(date +%s)
    age=$((now - timestamp))
    if [[ $age -gt $STALE_THRESHOLD ]]; then
        echo "stale:$age"
    else
        echo "$status:$age"
    fi
}
```

### Existing Daemon Manager API (Cross-Platform)
```bash
# Source: lib/platform/daemon-manager.sh
# Already provides full lifecycle management
detect_init_system   # Returns: launchd | systemd | cron
install_daemon "name" "script_path" "project_dir" "project_name" "type"
start_daemon "name"
stop_daemon "name"
restart_daemon "name"
status_daemon "name"  # Returns 0 if running
list_daemons "pattern"
uninstall_daemon "name"
```

### launchd kickstart (Force Restart)
```bash
# Source: launchd.plist(5) man page - verified
# Force-restart a service regardless of KeepAlive state
launchctl kickstart -k "gui/$(id -u)/com.checkpoint.watchdog"

# Check why a service was started
launchctl blame "gui/$(id -u)/com.checkpoint.watchdog"

# Print detailed service info
launchctl print "gui/$(id -u)/com.checkpoint.watchdog"
```

### systemd Watchdog Integration
```bash
# Source: systemd.service(5), sd_notify(3) - verified
# For systemd watchdog, the wrapper must send keepalive at half WatchdogSec interval
# If WatchdogSec=60, send WATCHDOG=1 every 30 seconds

# In wrapper script:
/bin/systemd-notify --ready           # Signal startup complete
/bin/systemd-notify WATCHDOG=1        # Pet the watchdog (send heartbeat)
/bin/systemd-notify "STATUS=Healthy"  # Update status shown in systemctl
```

### Existing Notification (Cross-Platform)
```bash
# Source: lib/platform/compat.sh
# Already provides cross-platform notification
send_notification "Checkpoint Alert" "Backup stale for 4 hours"
# macOS: osascript display notification
# Linux: notify-send
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `KeepAlive=true` (unconditional) | `KeepAlive/SuccessfulExit=false` | Best practice, always recommended | Allows intentional daemon stops without plist unload |
| `launchctl load/unload` | `launchctl bootstrap/bootout` | macOS 10.10+ (launchctl v2) | Modern API, better error reporting |
| PID file only health check | PID + heartbeat + staleness combined | Industry standard | Catches hung processes, not just dead ones |
| Alert on every check | Cooldown + consecutive failure threshold | Monitoring best practice (Datadog, Icinga) | Prevents notification fatigue |
| Manual daemon start after install | Auto-start on install | User expectation | Immediate backup protection, no reboot needed |

**New patterns to consider:**
- **systemd RestartSteps + RestartMaxDelaySec** (systemd 254+): Controlled exponential backoff with a cap, unlike launchd's unbounded backoff. If targeting modern Linux distros, this replaces manual backoff logic.
- **Healthchecks.io integration** (optional): Dead-man's-switch pattern where daemon pings an external URL after each backup. External service alerts if no ping arrives. Free tier available. NOT a requirement but a nice optional integration point.

**Deprecated/outdated:**
- **`launchctl load/unload`:** Replaced by `bootstrap/bootout` in launchctl v2. Legacy commands still work but produce deprecation warnings on newer macOS.
- **`KeepAlive/NetworkState`:** Apple confirms this key "is no longer implemented." Do not use.
- **`KeepAlive/PathState`:** Apple says it's "race-prone." Use heartbeat file checking in the watchdog script instead.
</sota_updates>

<open_questions>
## Open Questions

1. **Per-project vs global heartbeat monitoring**
   - What we know: The daemon runs per-project (each project has its own daemon). The watchdog runs globally (one instance).
   - What's unclear: Should the watchdog iterate all registered projects and check each project's heartbeat? Or should each project daemon register its own heartbeat and the watchdog check all?
   - Recommendation: The watchdog should iterate all registered projects via projects-registry.sh and check each project's last-backup-time. This matches the existing dashboard pattern in global-status.sh.

2. **Staleness thresholds: project-level overrides**
   - What we know: Global defaults exist (HEALTH_WARNING_HOURS=24, HEALTH_ERROR_HOURS=72). Per-project overrides exist (ALERT_WARNING_HOURS, ALERT_ERROR_HOURS in config).
   - What's unclear: Should Phase 18 staleness thresholds reuse these existing thresholds or add new ones?
   - Recommendation: Reuse existing health thresholds from global-status.sh. Don't add another set of thresholds. Map existing WARNING/ERROR to the notification escalation levels.

3. **Watchdog heartbeat ("who watches the watchman")**
   - What we know: The daemon writes heartbeats. The watchdog monitors heartbeats. But nothing monitors the watchdog.
   - What's unclear: Is this necessary? launchd/systemd already restart the watchdog if it crashes.
   - Recommendation: Add a simple watchdog heartbeat file (`~/.checkpoint/watchdog.heartbeat`). Dashboard can show watchdog status. Low effort, high observability value.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- **Existing codebase analysis** — bin/backup-daemon.sh (heartbeat write, lines 149-176), bin/checkpoint-watchdog.sh (heartbeat monitoring), lib/platform/daemon-manager.sh (851 lines, cross-platform lifecycle), templates/*.plist and *.service (service templates)
- **launchd.plist(5) man page** — KeepAlive semantics, ThrottleInterval, RunAtLoad, ProcessType — https://keith.github.io/xcode-man-pages/launchd.plist.5.html
- **Apple Developer: Creating Launch Daemons and Agents** — Official lifecycle management guide — https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
- **systemd.service(5)** — Restart=, RestartSec=, StartLimitBurst, WatchdogSec — https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html
- **sd_notify(3)** — WATCHDOG=1, --ready signaling — https://www.freedesktop.org/software/systemd/man/latest/sd_notify.html
- **POSIX rename atomicity** — Verified: rename() is atomic on same filesystem — https://rcrowley.org/2010/01/06/things-unix-can-do-atomically.html

### Secondary (MEDIUM confidence)
- **launchd exponential backoff** — Documented in community reports and Apple forums; confirmed pattern but exact backoff formula is undocumented — https://github.com/openclaw/openclaw/issues/4632
- **Datadog alert fatigue best practices** — Cooldown, consecutive failure threshold, hysteresis patterns — https://www.datadoghq.com/blog/best-practices-to-prevent-alert-fatigue/
- **Healthchecks.io documentation** — Dead man's switch pattern, grace periods — https://healthchecks.io/docs/
- **Borgmatic monitoring docs** — Backup tool health monitoring patterns — https://torsion.org/borgmatic/how-to/monitor-your-backups/
- **Medo's systemd watchdog guide** — Practical wrapper script pattern — https://www.medo64.com/2019/01/systemd-watchdog-for-any-service/
- **launchd.info tutorial** — Comprehensive launchd reference — https://www.launchd.info/

### Tertiary (LOW confidence - needs validation)
- None — all findings verified against official documentation or existing codebase
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: launchd (macOS), systemd (Linux), bash daemon patterns
- Ecosystem: Existing project infrastructure (daemon-manager, watchdog, heartbeat, notifications)
- Patterns: Atomic heartbeat, tiered staleness, notification cooldown, KeepAlive/SuccessfulExit
- Pitfalls: Exponential backoff, alert fatigue, race conditions, PID reuse

**Confidence breakdown:**
- Standard stack: HIGH — all components already exist in codebase, verified by direct code reading
- Architecture: HIGH — patterns verified against official launchd/systemd documentation
- Pitfalls: HIGH — exponential backoff confirmed in multiple sources; race conditions are well-documented POSIX behavior
- Code examples: HIGH — examples from existing codebase + official man pages

**Research date:** 2026-02-13
**Valid until:** 2026-03-13 (30 days — launchd/systemd APIs are stable)
</metadata>

---

*Phase: 18-daemon-lifecycle*
*Research completed: 2026-02-13*
*Ready for planning: yes*
