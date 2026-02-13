# Phase 15: Linux Systemd Support - Research

**Researched:** 2026-02-13
**Domain:** Cross-platform daemon management (systemd user services, launchd, cron fallback)
**Confidence:** HIGH

<research_summary>
## Summary

Researched how to extend Checkpoint's daemon management from macOS-only (launchd) to cross-platform (launchd + systemd + cron fallback). The current codebase has 5 daemon components that are hardcoded to launchd: install-global.sh, checkpoint-watchdog.sh, health-stats.sh, backup-watch.sh, and uninstall.sh. The file watcher layer (lib/platform/file-watcher.sh) already supports Linux via inotifywait, but daemon lifecycle management (install, start, stop, status, restart, uninstall) is entirely macOS-specific.

The standard approach for Linux user-level daemons is **systemd user services** (`systemctl --user`), installed to `~/.config/systemd/user/`. These run under the user's own systemd instance and require no root privileges. For systems without systemd (containers, older distros, BSDs), a cron-based polling fallback covers the remaining cases.

**Primary recommendation:** Create a `lib/platform/daemon-manager.sh` abstraction layer (paralleling the existing `lib/platform/file-watcher.sh` pattern) that provides unified `install_daemon()`, `uninstall_daemon()`, `start_daemon()`, `stop_daemon()`, `status_daemon()`, `restart_daemon()`, and `list_daemons()` functions. Each function dispatches to platform-specific implementations based on init system detection. Create systemd `.service` template files in `templates/` parallel to the existing `.plist` templates.
</research_summary>

<standard_stack>
## Standard Stack

### Core (Platform Detection & Service Management)

| Component | Purpose | Why Standard |
|-----------|---------|--------------|
| `uname -s` | OS detection (Darwin vs Linux) | POSIX, available everywhere |
| `/run/systemd/system` dir check | Detect systemd as init system | Recommended by systemd developers; avoids false positives in containers |
| `systemctl --user` | User-level service management | Official systemd interface for non-root services |
| `~/.config/systemd/user/` | Service file installation path | XDG standard, highest user precedence |
| `journalctl --user` | Log access for user services | Native systemd journal integration |
| `loginctl enable-linger` | Persist services beyond login | Required for headless/server deployments |
| `crontab -e` / `@reboot` | Cron fallback for non-systemd Linux | Universal POSIX fallback |

### Supporting

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `systemd-cat` | Explicit journal logging from bash | When scripts need tagged log entries (not just stdout) |
| `logger` | POSIX syslog logging | Alternative to systemd-cat; works on all platforms |
| `readlink -f /proc/1/exe` | Fallback init system detection | When `/run/systemd/system` check is inconclusive |
| `notify-send` | Linux desktop notifications | Parallel to macOS `osascript` notifications |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| systemd user services | System-level services | Requires root; not appropriate for user tools |
| `~/.config/systemd/user/` | `~/.local/share/systemd/user/` | Lower precedence; `~/.config` is standard for user-managed files |
| Direct `journalctl` | File-based logging only | Loses structured logging, rotation, priority filtering |
| `loginctl enable-linger` | Wrapper script + screen/tmux | Fragile; lingering is the systemd-native solution |
| Cron fallback | Supervisor/runit | Adds dependency; cron is universally available |
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended: Platform Abstraction Layer

Mirror the existing `lib/platform/file-watcher.sh` pattern to create `lib/platform/daemon-manager.sh`:

```
lib/platform/
├── file-watcher.sh          # EXISTING - detect_watcher(), start_watcher()
└── daemon-manager.sh         # NEW - detect_init_system(), install_daemon(), etc.
```

### Pattern 1: Init System Detection

**What:** Reliable detection of the running init system from bash
**When to use:** Before any daemon management operation
**Source:** systemd developer recommendation + community best practices

```bash
detect_init_system() {
    local os
    os="$(uname -s)"

    case "$os" in
        Darwin)
            echo "launchd"
            return 0
            ;;
        Linux)
            # Most reliable: check for systemd runtime directory
            # This directory only exists when systemd is actively running as PID 1
            # Correctly returns false in Docker containers on systemd hosts
            if [ -d /run/systemd/system ]; then
                echo "systemd"
                return 0
            fi
            # Fallback: check PID 1 binary
            if command -v readlink >/dev/null 2>&1; then
                local init_path
                init_path="$(readlink -f /proc/1/exe 2>/dev/null)"
                case "$init_path" in
                    */systemd) echo "systemd"; return 0 ;;
                esac
            fi
            # Default: cron fallback
            echo "cron"
            return 0
            ;;
        *)
            echo "cron"
            return 0
            ;;
    esac
}
```

### Pattern 2: Unified Daemon Management Interface

**What:** Single function interface that dispatches to platform implementations
**When to use:** All daemon install/uninstall/start/stop/status operations

```bash
# Public API (called by install-global.sh, backup-watch.sh, etc.)
install_daemon()    # Args: service_name, script_path, [options]
uninstall_daemon()  # Args: service_name
start_daemon()      # Args: service_name
stop_daemon()       # Args: service_name
restart_daemon()    # Args: service_name
status_daemon()     # Args: service_name -> returns 0/1
list_daemons()      # Args: pattern -> outputs matching service names

# Internal dispatch (not called directly)
_daemon_launchd_install()
_daemon_launchd_uninstall()
_daemon_systemd_install()
_daemon_systemd_uninstall()
_daemon_cron_install()
_daemon_cron_uninstall()
```

### Pattern 3: systemd User Service File Template

**What:** Template `.service` file parallel to existing `.plist` templates
**Source:** freedesktop.org systemd.service specification

```ini
# templates/systemd-watcher.service
[Unit]
Description=Checkpoint File Watcher - PROJECT_NAME_PLACEHOLDER
Documentation=https://github.com/user/checkpoint
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/bin/bash SCRIPT_PATH_PLACEHOLDER
WorkingDirectory=PROJECT_DIR_PLACEHOLDER
Environment=PATH=/usr/local/bin:/usr/bin:/bin:HOME_PLACEHOLDER/.local/bin
EnvironmentFile=-HOME_PLACEHOLDER/.config/checkpoint/env
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
# Optional hardening
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=default.target
```

### Pattern 4: Notification Abstraction

**What:** Cross-platform desktop notification function
**When to use:** Watchdog alerts, backup completion, error conditions

```bash
send_notification() {
    local title="$1"
    local message="$2"

    case "$(uname -s)" in
        Darwin)
            osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
            ;;
        Linux)
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "$title" "$message" 2>/dev/null || true
            fi
            ;;
    esac
}
```

### Pattern 5: stat Command Abstraction

**What:** Cross-platform file stat operations (macOS vs GNU stat have different flags)
**When to use:** Log rotation, file age checks

```bash
get_file_size() {
    local file="$1"
    case "$(uname -s)" in
        Darwin) stat -f%z "$file" 2>/dev/null || echo 0 ;;
        *)      stat -c%s "$file" 2>/dev/null || echo 0 ;;
    esac
}

get_file_mtime() {
    local file="$1"
    case "$(uname -s)" in
        Darwin) stat -f%m "$file" 2>/dev/null || echo 0 ;;
        *)      stat -c%Y "$file" 2>/dev/null || echo 0 ;;
    esac
}
```

### Recommended File Structure for New/Modified Files

```
templates/
├── launchd-watcher.plist              # EXISTING
├── com.checkpoint.watchdog.plist      # EXISTING
├── systemd-watcher.service            # NEW - file watcher template
├── systemd-daemon.service             # NEW - hourly backup daemon template
├── systemd-watchdog.service           # NEW - watchdog template
└── cron-backup.crontab                # NEW - cron fallback template

lib/platform/
├── file-watcher.sh                    # EXISTING
└── daemon-manager.sh                  # NEW - unified daemon management
```

### Anti-Patterns to Avoid
- **Sprinkling `if [[ "$OSTYPE" == "darwin"* ]]` everywhere:** Centralize in daemon-manager.sh, not in every script
- **Calling `launchctl` directly in scripts outside daemon-manager.sh:** All daemon operations should go through the abstraction
- **Using system-level systemd services:** User-level services (`systemctl --user`) are correct for per-user tools
- **Assuming bash 4+:** The project uses bash 3.2 compatibility; stick to `[ ]` not `[[ ]]` where possible, avoid associative arrays
- **Generating service files at runtime:** Use template files with placeholder substitution (matching existing plist pattern)
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Init system detection | Custom heuristics based on `$OSTYPE` | `/run/systemd/system` directory check | The only method recommended by systemd devs; handles containers correctly |
| Service restart policies | Custom watchdog-only restart logic | systemd `Restart=on-failure` + `RestartSec=5s` | systemd handles restart rate limiting, backoff, and state tracking natively |
| Log rotation for systemd | Custom rotation in bash scripts | journald's built-in rotation | journald handles log size limits, vacuuming, and structured queries |
| User session persistence | Custom screen/tmux wrappers | `loginctl enable-linger` | Native systemd mechanism; survives reboots, no terminal needed |
| Process monitoring on systemd | Custom PID-file-based health checks | `systemctl --user is-active SERVICE` | systemd tracks process state authoritatively |
| Service dependency ordering | Manual sleep-based sequencing | systemd `After=` / `Requires=` directives | Declarative dependencies with proper ordering guarantees |

**Key insight:** systemd replaces both the daemon launcher AND the watchdog on Linux. The existing checkpoint-watchdog.sh heartbeat monitoring is still valuable for detecting *backup* health (stale heartbeats = backups not happening), but process restart should be delegated to systemd's native `Restart=` directive. The watchdog on Linux should focus on backup health monitoring, not process lifecycle.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: PATH Not Available in systemd User Services
**What goes wrong:** Service starts but bash script fails because `fswatch`, `inotifywait`, or other tools not found
**Why it happens:** systemd user services do NOT inherit PATH from `.bashrc`/`.zshrc`/`.bash_profile`. They get a minimal default PATH of `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`.
**How to avoid:** Set `Environment=PATH=...` explicitly in the service file template. Include `/usr/local/bin` (system packages), `~/.local/bin` (pip/user installs), and any other expected paths. Use `%h` specifier for home directory.
**Warning signs:** "command not found" errors in `journalctl --user -u checkpoint-watcher`

### Pitfall 2: Start Rate Limiting Kills the Service Permanently
**What goes wrong:** After a few quick crashes, systemd refuses to restart the service. `systemctl --user status` shows "start-limit-hit".
**Why it happens:** Default `StartLimitIntervalSec=10s` with `StartLimitBurst=5` means 5 crashes in 10 seconds permanently stops restarts. With default `RestartSec=100ms`, this limit is hit in ~0.5 seconds.
**How to avoid:** Always set explicit values: `StartLimitIntervalSec=300` and `StartLimitBurst=5` in `[Unit]`, `RestartSec=5s` in `[Service]`. This gives 5 attempts in 5 minutes with 5-second delays between.
**Warning signs:** Service shows "failed" status but no restart attempts in journal

### Pitfall 3: stat Command Flags Differ Between macOS and GNU/Linux
**What goes wrong:** `stat -f%z` (macOS) fails on Linux; `stat -c%s` (GNU) fails on macOS. Scripts crash with "illegal option" errors.
**Why it happens:** BSD stat and GNU stat have completely different flag syntax.
**How to avoid:** Create `get_file_size()` and `get_file_mtime()` helper functions that dispatch based on `uname -s`. The watchdog already uses `stat -f%z` for log rotation (line 25) — this will break on Linux.
**Warning signs:** "illegal option" errors from stat in logs

### Pitfall 4: User Lingering Not Enabled on Headless/Server Systems
**What goes wrong:** Services stop when user's last SSH session closes. Backups silently cease.
**Why it happens:** Without lingering, the user's systemd instance only runs while at least one session is active. Closing the last terminal/SSH = services stop.
**How to avoid:** Detect headless environments (no `$DISPLAY` or `$WAYLAND_DISPLAY`) and prompt to enable lingering during install. Requires `sudo` — clearly communicate this to the user. Document the limitation for non-root users.
**Warning signs:** Services running after install but gone after reboot/logout

### Pitfall 5: `launchctl list` Called on Linux (and vice versa)
**What goes wrong:** Any script that calls `launchctl` directly will fail on Linux with "command not found."
**Why it happens:** Direct platform-specific calls scattered throughout the codebase instead of going through an abstraction layer.
**How to avoid:** Audit every `launchctl` call in the codebase and route through the new daemon-manager.sh abstraction. Key locations: `health-stats.sh:27,34`, `checkpoint-watchdog.sh:72,82-84`, `install-global.sh:270-271`, `backup-watch.sh`, `uninstall.sh`.
**Warning signs:** "launchctl: command not found" on any Linux system

### Pitfall 6: Cron `@reboot` Not Universally Supported
**What goes wrong:** Daemon doesn't start after system reboot on some Linux systems.
**Why it happens:** `@reboot` is a vixie-cron extension, not POSIX. Some cron implementations (BusyBox crond, some BSDs) don't support it.
**How to avoid:** For the cron fallback, use polling interval only (e.g., `*/5 * * * *`). If the daemon script is designed to be idempotent (check PID, skip if running), frequent cron invocations are safe. Don't rely on `@reboot`.
**Warning signs:** Cron job listed but never runs at boot on Alpine/BusyBox systems
</common_pitfalls>

<code_examples>
## Code Examples

Verified patterns from official systemd documentation and existing codebase conventions:

### systemd User Service File for File Watcher
```ini
# templates/systemd-watcher.service
# Source: freedesktop.org systemd.service(5), systemd.exec(5)
[Unit]
Description=Checkpoint File Watcher - PROJECT_NAME_PLACEHOLDER
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/bin/bash SCRIPT_PATH_PLACEHOLDER
WorkingDirectory=PROJECT_DIR_PLACEHOLDER
Environment=PATH=/usr/local/bin:/usr/bin:/bin:HOME_PLACEHOLDER/.local/bin
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

### systemd Service Installation from Bash
```bash
# Source: ArchWiki systemd/User, Oracle Linux systemd docs
install_systemd_service() {
    local service_name="$1"     # e.g., "checkpoint-watcher-myproject"
    local template_file="$2"    # e.g., "templates/systemd-watcher.service"
    local replacements="$3"     # placeholder=value pairs

    local target_dir="$HOME/.config/systemd/user"
    local target_file="${target_dir}/${service_name}.service"

    mkdir -p "$target_dir"

    # Copy template and apply replacements
    cp "$template_file" "$target_file"
    # Apply placeholder substitution (same pattern as existing plist generation)
    sed -i "s|PROJECT_NAME_PLACEHOLDER|${project_name}|g" "$target_file"
    sed -i "s|SCRIPT_PATH_PLACEHOLDER|${script_path}|g" "$target_file"
    sed -i "s|PROJECT_DIR_PLACEHOLDER|${project_dir}|g" "$target_file"
    sed -i "s|HOME_PLACEHOLDER|${HOME}|g" "$target_file"

    # Reload, enable, and start
    systemctl --user daemon-reload
    systemctl --user enable "$service_name"
    systemctl --user start "$service_name"
}
```

### systemd Service Uninstallation
```bash
# Source: freedesktop.org systemctl(1)
uninstall_systemd_service() {
    local service_name="$1"
    local target_file="$HOME/.config/systemd/user/${service_name}.service"

    if [ -f "$target_file" ]; then
        systemctl --user stop "$service_name" 2>/dev/null || true
        systemctl --user disable "$service_name" 2>/dev/null || true
        rm -f "$target_file"
        systemctl --user daemon-reload
    fi
}
```

### Cross-Platform Daemon Status Check
```bash
# Replace existing health-stats.sh check_daemon_status()
check_daemon_status() {
    local init_system
    init_system="$(detect_init_system)"

    case "$init_system" in
        launchd)
            if launchctl list 2>/dev/null | grep -q "com.checkpoint"; then
                return 0
            fi
            ;;
        systemd)
            # Check for any checkpoint user services
            if systemctl --user is-active --quiet "checkpoint-*" 2>/dev/null; then
                return 0
            fi
            # Fallback: list and grep
            if systemctl --user list-units --type=service --state=active 2>/dev/null | grep -q "checkpoint"; then
                return 0
            fi
            ;;
        cron)
            # Check if cron entries exist and daemon PID is running
            if crontab -l 2>/dev/null | grep -q "checkpoint"; then
                return 0
            fi
            ;;
    esac

    return 1
}
```

### Cron Fallback Installation
```bash
# Source: man7.org crontab(5)
install_cron_fallback() {
    local script_path="$1"
    local interval_minutes="${2:-5}"

    # Add to crontab without removing existing entries
    local existing
    existing="$(crontab -l 2>/dev/null || true)"

    # Check if already installed
    if echo "$existing" | grep -q "$script_path"; then
        return 0  # Already installed
    fi

    # Append new entry
    (echo "$existing"; echo "*/${interval_minutes} * * * * /bin/bash $script_path >> \$HOME/.checkpoint/logs/cron-backup.log 2>&1") | crontab -
}
```

### Cross-Platform Log Viewing
```bash
view_daemon_logs() {
    local service_name="$1"
    local lines="${2:-50}"

    case "$(detect_init_system)" in
        launchd)
            local log_file="$HOME/.claudecode-backups/logs/watcher-${service_name}.log"
            if [ -f "$log_file" ]; then
                tail -n "$lines" "$log_file"
            fi
            ;;
        systemd)
            journalctl --user -u "checkpoint-${service_name}" -n "$lines" --no-pager 2>/dev/null
            ;;
        cron)
            local log_file="$HOME/.checkpoint/logs/cron-backup.log"
            if [ -f "$log_file" ]; then
                tail -n "$lines" "$log_file"
            fi
            ;;
    esac
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `launchctl load/unload` | `launchctl bootstrap/bootout gui/$(id -u)` | macOS 10.10+ (2014), now preferred | Old syntax still works but new syntax is more reliable |
| PID file-based health checks | systemd native `Restart=` + `is-active` | Always in systemd | No custom watchdog needed for process lifecycle on Linux |
| `grep /proc/1/comm` for init detection | `/run/systemd/system` directory check | systemd developer recommendation | Handles containers and edge cases correctly |
| Manual log rotation in bash | journald with `StandardOutput=journal` | systemd native | Automatic rotation, structured queries, priority levels |
| `DefaultRestartSec=100ms` | `DefaultRestartSec=100ms` (unchanged) | Still current | Must explicitly set `RestartSec=5s` to avoid start-limit-hit |

**New tools/patterns to consider:**
- **systemd specifiers** (`%h`, `%t`, `%u`, `%E`, etc.): Allow portable service files without hardcoded paths. `%h` resolves to `$HOME` at runtime — eliminates need for sed replacement of HOME_PLACEHOLDER in some cases
- **`EnvironmentFile=-` (dash prefix):** Makes the env file optional (no error if missing). Good for optional config overlays
- **`ExecSearchPath=`:** Newer alternative to `Environment=PATH=...` that only affects executable lookup, not the process environment
- **`PrivateTmp=true` + `NoNewPrivileges=true`:** Security hardening directives that work in user services too — minimal cost, good practice

**Deprecated/outdated:**
- **`launchctl load/unload`:** Apple deprecated in favor of `launchctl bootstrap/bootout`, though the old syntax still works
- **PID file-based process management:** systemd tracks process state natively; PID files are unnecessary for systemd-managed services
- **`/etc/init.d/` scripts:** Entirely superseded by systemd on modern Linux
</sota_updates>

<codebase_impact>
## Codebase Impact Analysis

Files that currently contain macOS-specific daemon management code and need updating:

### Must Change (direct launchctl/macOS dependencies)

| File | Lines | What Needs Changing |
|------|-------|---------------------|
| `lib/features/health-stats.sh` | 27, 34 | `launchctl list` calls in `check_daemon_status()` |
| `bin/checkpoint-watchdog.sh` | 25, 72, 77-85 | `stat -f%z` (macOS-only), `launchctl list`, `launchctl unload/load` |
| `bin/install-global.sh` | 231, 246-271 | `if darwin` guard around LaunchAgent install; needs systemd parallel |
| `bin/backup-watch.sh` | Various | Watcher start/stop may reference launchd |
| `bin/uninstall.sh` | Various | `launchctl unload` for cleanup |
| `bin/uninstall-global.sh` | Various | LaunchAgent removal |
| `bin/install.sh` | 81-82, 1154-1186 | launchctl checks, plist generation |

### Must Create (new files)

| File | Purpose |
|------|---------|
| `lib/platform/daemon-manager.sh` | Unified daemon management abstraction |
| `templates/systemd-watcher.service` | File watcher service template |
| `templates/systemd-daemon.service` | Hourly backup daemon service template |
| `templates/systemd-watchdog.service` | Watchdog monitor service template |

### stat Command Portability Issues

The `stat` command flags differ between macOS and GNU/Linux. These specific calls need abstraction:

| File | Line | macOS Syntax | GNU Equivalent |
|------|------|-------------|----------------|
| `checkpoint-watchdog.sh` | 25 | `stat -f%z "$LOG_FILE"` | `stat -c%s "$LOG_FILE"` |
| `lib/features/health-stats.sh` | 147 | `stat -f%m -t%s` | `stat -c%Y` |

### Notification Portability

| File | Line | macOS | Linux Equivalent |
|------|------|-------|-----------------|
| `checkpoint-watchdog.sh` | 106 | `osascript -e "display notification..."` | `notify-send` |
</codebase_impact>

<open_questions>
## Open Questions

1. **Should the global daemon (hourly timer) use systemd timer units instead of `Type=simple` with sleep?**
   - What we know: systemd has dedicated timer units (`*.timer` + `*.service` pairs) that are the "right" way to run periodic tasks. The current macOS approach uses `StartInterval` in the plist.
   - What's unclear: Whether the added complexity of timer+service pairs is worth it vs. a simple `ExecStart` script that the watcher triggers.
   - Recommendation: Use `Type=simple` for the watcher daemon (long-running). For the hourly backup daemon, a systemd timer unit would be more idiomatic, but a simple cron-style approach also works. Decide during planning — timer units are cleaner but add template complexity.

2. **Should `loginctl enable-linger` be offered during install or documented only?**
   - What we know: Lingering requires root/sudo. Not all users have sudo access. Without it, services stop on logout.
   - What's unclear: How many target users are on headless servers vs desktop Linux.
   - Recommendation: Detect if running headless (no `$DISPLAY`), suggest enabling linger with clear explanation. Don't require it — document the limitation for non-linger setups.

3. **Should the macOS plist creation code also be migrated into daemon-manager.sh?**
   - What we know: Plist generation is currently inline in install-global.sh (lines 246-271) and install.sh (lines 1154-1186).
   - What's unclear: Whether to refactor macOS code simultaneously or just add Linux support alongside.
   - Recommendation: Migrate macOS plist code into daemon-manager.sh as the launchd backend. This gives a clean abstraction for both platforms and prevents future duplication. The refactor is straightforward since the patterns are already well-established.

4. **Template service name convention: `checkpoint-watcher-PROJECT` or `com.checkpoint.watcher.PROJECT`?**
   - What we know: systemd convention uses hyphenated names (e.g., `docker-compose-app`). macOS convention uses reverse-DNS (e.g., `com.checkpoint.watcher`).
   - What's unclear: Whether to maintain the same naming across platforms.
   - Recommendation: Use `checkpoint-watcher-PROJECT.service` for systemd (follows Linux convention) and keep `com.checkpoint.watcher.PROJECT.plist` for macOS (follows Apple convention). The daemon-manager abstraction handles the mapping.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- [freedesktop.org - systemd.service(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) - ExecStart, Restart, Type directives
- [freedesktop.org - systemd.exec(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html) - Environment, StandardOutput, security options
- [freedesktop.org - systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html) - Unit file paths, specifiers (%h, %t, etc.)
- [freedesktop.org - loginctl(1)](https://www.freedesktop.org/software/systemd/man/latest/loginctl.html) - enable-linger documentation
- [ArchWiki - systemd/User](https://wiki.archlinux.org/title/Systemd/User) - User service setup, management, environment
- [man7.org - systemd.service(5)](https://man7.org/linux/man-pages/man5/systemd.service.5.html) - Alternative official reference
- [man7.org - crontab(5)](https://man7.org/linux/man-pages/man5/crontab.5.html) - Cron syntax and @reboot support

### Secondary (MEDIUM confidence)
- [Michael Stapelberg - Indefinite Service Restarts (2024)](https://michael.stapelberg.ch/posts/2024-01-17-systemd-indefinite-service-restarts/) - StartLimitIntervalSec=0 pattern, restart rate limiting analysis
- [Red Hat - Self-healing Services](https://www.redhat.com/en/blog/systemd-automate-recovery) - Restart policy best practices
- [DigitalOcean - journalctl Guide](https://www.digitalocean.com/community/tutorials/how-to-use-journalctl-to-view-and-manipulate-systemd-logs) - Journal querying patterns
- [Oracle Linux - Creating User-Based systemd Service](https://docs.oracle.com/en/operating-systems/oracle-linux/9/systemd/CreatingasystemdUserBasedService.html) - User service installation paths
- [Sebastian Jambor - systemd by example Part 4](https://seb.jambor.dev/posts/systemd-by-example-part-4-installing-units/) - Enable/WantedBy mechanics

### Tertiary (LOW confidence - needs validation)
- None - all findings cross-verified with official documentation
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: systemd user services, launchd (existing), cron fallback
- Ecosystem: systemctl, journalctl, loginctl, notify-send, crontab
- Patterns: Platform abstraction layer, template-based service generation, init detection
- Pitfalls: PATH inheritance, start rate limiting, stat portability, lingering, cron @reboot

**Confidence breakdown:**
- Standard stack: HIGH - verified with freedesktop.org official docs
- Architecture: HIGH - mirrors existing file-watcher.sh pattern already proven in codebase
- Pitfalls: HIGH - documented in official docs and confirmed by multiple expert sources
- Code examples: HIGH - from official systemd documentation and verified ArchWiki patterns

**Research date:** 2026-02-13
**Valid until:** 2026-03-15 (30 days - systemd ecosystem is stable, no expected breaking changes)
</metadata>

---

*Phase: 15-linux-systemd-support*
*Research completed: 2026-02-13*
*Ready for planning: yes*
