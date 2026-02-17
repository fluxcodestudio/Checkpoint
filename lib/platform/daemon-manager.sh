#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cross-Platform Daemon Management
# ==============================================================================
# Unified interface for daemon lifecycle management across platforms:
#   - launchd (macOS primary)
#   - systemd (Linux primary)
#   - cron (Linux/other fallback)
#
# Provides: install, uninstall, start, stop, restart, status, list
# Each function dispatches to the correct platform backend.
#
# NOT loaded by backup-lib.sh module loader. Sourced directly by
# install scripts and daemon management commands.
#
# Bash 3.2 compatible: NO associative arrays, NO [[ ]], NO ${var,,},
# NO |&, NO coproc
# ==============================================================================

# Include guard (set -u safe)
[ -n "${_DAEMON_MANAGER_LOADED:-}" ] && return || readonly _DAEMON_MANAGER_LOADED=1

# Set logging context for this module
log_set_context "daemon-mgr"

# Cache init system detection result
_DAEMON_INIT_SYSTEM=""

# ==============================================================================
# detect_init_system
# ==============================================================================
# Detect the init system / service manager for the current platform.
# Returns: "launchd", "systemd", or "cron" on stdout.
#
# Darwin          -> launchd
# Linux + systemd -> systemd (checks /run/systemd/system first, then PID 1)
# Everything else -> cron (fallback)
#
# Result is cached in _DAEMON_INIT_SYSTEM for subsequent calls.
# ==============================================================================

detect_init_system() {
    # Return cached result if available
    if [ -n "$_DAEMON_INIT_SYSTEM" ]; then
        echo "$_DAEMON_INIT_SYSTEM"
        return
    fi

    local os_name
    os_name="$(uname -s)"

    if [ "$os_name" = "Darwin" ]; then
        _DAEMON_INIT_SYSTEM="launchd"
    elif [ -d "/run/systemd/system" ]; then
        # Recommended systemd detection: directory exists on running systemd
        _DAEMON_INIT_SYSTEM="systemd"
    elif [ -f "/proc/1/exe" ] && readlink /proc/1/exe 2>/dev/null | grep -q "systemd"; then
        # Fallback: check if PID 1 is systemd
        _DAEMON_INIT_SYSTEM="systemd"
    else
        _DAEMON_INIT_SYSTEM="cron"
    fi

    echo "$_DAEMON_INIT_SYSTEM"
}

# ==============================================================================
# Service Name Mapping (internal)
# ==============================================================================

# _daemon_launchd_name(service_name) -> com.checkpoint.${service_name}
_daemon_launchd_name() {
    echo "com.checkpoint.${1}"
}

# _daemon_launchd_legacy_name(service_name) -> com.claudecode.backup.${service_name}
_daemon_launchd_legacy_name() {
    echo "com.claudecode.backup.${1}"
}

# _daemon_systemd_name(service_name) -> checkpoint-${service_name}
_daemon_systemd_name() {
    echo "checkpoint-${1}"
}

# _daemon_plist_path(service_name) -> full path to plist file
# Checks new naming first, then legacy naming
_daemon_plist_path() {
    local name="$1"
    local new_path="$HOME/Library/LaunchAgents/$(_daemon_launchd_name "$name").plist"
    local legacy_path="$HOME/Library/LaunchAgents/$(_daemon_launchd_legacy_name "$name").plist"

    if [ -f "$new_path" ]; then
        echo "$new_path"
    elif [ -f "$legacy_path" ]; then
        echo "$legacy_path"
    else
        # Default to new naming for creation
        echo "$new_path"
    fi
}

# _daemon_service_path(service_name) -> full path to systemd service file
_daemon_service_path() {
    echo "$HOME/.config/systemd/user/$(_daemon_systemd_name "$1").service"
}

# _daemon_timer_path(service_name) -> full path to systemd timer file
_daemon_timer_path() {
    echo "$HOME/.config/systemd/user/$(_daemon_systemd_name "$1").timer"
}

# ==============================================================================
# Template Processing (internal)
# ==============================================================================
# _daemon_apply_template(template_file, output_file, project_name, project_dir, script_path)
#
# Replaces placeholders in template with actual values:
#   PROJECT_NAME_PLACEHOLDER  -> project_name
#   PROJECT_DIR_PLACEHOLDER   -> project_dir
#   SCRIPT_PATH_PLACEHOLDER   -> script_path
#   HOME_PLACEHOLDER          -> $HOME
#   INSTALL_DIR_PLACEHOLDER   -> resolved install dir
# ==============================================================================

_daemon_apply_template() {
    local template_file="$1"
    local output_file="$2"
    local project_name="$3"
    local project_dir="$4"
    local script_path="$5"

    # Resolve install dir: script_path minus the trailing /bin/something.sh
    local install_dir
    install_dir="$(cd "$(dirname "$script_path")/.." 2>/dev/null && pwd)" || install_dir="$project_dir"

    sed -e "s|PROJECT_NAME_PLACEHOLDER|${project_name}|g" \
        -e "s|PROJECT_DIR_PLACEHOLDER|${project_dir}|g" \
        -e "s|SCRIPT_PATH_PLACEHOLDER|${script_path}|g" \
        -e "s|HOME_PLACEHOLDER|${HOME}|g" \
        -e "s|INSTALL_DIR_PLACEHOLDER|${install_dir}|g" \
        "$template_file" > "$output_file"
}

# ==============================================================================
# _daemon_find_template(service_type, init_system)
# ==============================================================================
# Locate the correct template file for the given service type and init system.
# Searches relative to this script's directory (../../templates/).
#
# Args:
#   $1 - service_type: "watcher" | "daemon" | "watchdog"
#   $2 - init_system: "launchd" | "systemd" | "cron"
#
# Output: path to template file on stdout, or empty string if not found
# ==============================================================================

_daemon_find_template() {
    local service_type="$1"
    local init_system="$2"
    local template_dir
    template_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/templates"

    local template=""

    case "${init_system}" in
        launchd)
            case "$service_type" in
                watcher)  template="${template_dir}/launchd-watcher.plist" ;;
                watchdog) template="${template_dir}/com.checkpoint.watchdog.plist" ;;
                daemon)   template="" ;;  # daemon plist is generated inline (no template yet)
            esac
            ;;
        systemd)
            case "$service_type" in
                watcher)  template="${template_dir}/systemd-watcher.service" ;;
                daemon)   template="${template_dir}/systemd-daemon.service" ;;
                watchdog) template="${template_dir}/systemd-watchdog.service" ;;
            esac
            ;;
        cron)
            template="${template_dir}/cron-backup.crontab"
            ;;
    esac

    if [ -n "$template" ] && [ -f "$template" ]; then
        echo "$template"
    fi
}

# ==============================================================================
# install_daemon
# ==============================================================================
# Install and activate a daemon/service for the given project.
#
# Args:
#   $1 - service_name:  unique name (e.g., "myproject-watcher")
#   $2 - script_path:   absolute path to the script to run
#   $3 - project_dir:   absolute path to the project directory
#   $4 - project_name:  human-readable project name
#   $5 - service_type:  "watcher" | "daemon" | "watchdog"
#
# Returns: 0 on success, 1 on failure
# ==============================================================================

install_daemon() {
    local service_name="$1"
    local script_path="$2"
    local project_dir="$3"
    local project_name="$4"
    local service_type="${5:-daemon}"

    local init_system
    init_system="$(detect_init_system)"

    case "$init_system" in
        launchd)  _install_daemon_launchd "$service_name" "$script_path" "$project_dir" "$project_name" "$service_type" ;;
        systemd)  _install_daemon_systemd "$service_name" "$script_path" "$project_dir" "$project_name" "$service_type" ;;
        cron)     _install_daemon_cron "$service_name" "$script_path" "$project_dir" "$project_name" "$service_type" ;;
    esac
}

# ==============================================================================
# uninstall_daemon
# ==============================================================================
# Stop and remove a daemon/service.
#
# Args:
#   $1 - service_name: the same name passed to install_daemon
#
# Returns: 0 on success, 1 on failure
# ==============================================================================

uninstall_daemon() {
    local service_name="$1"

    local init_system
    init_system="$(detect_init_system)"

    case "$init_system" in
        launchd)  _uninstall_daemon_launchd "$service_name" ;;
        systemd)  _uninstall_daemon_systemd "$service_name" ;;
        cron)     _uninstall_daemon_cron "$service_name" ;;
    esac
}

# ==============================================================================
# start_daemon
# ==============================================================================
# Start a stopped daemon.
#
# Args:
#   $1 - service_name
#
# Returns: 0 on success, 1 on failure
# ==============================================================================

start_daemon() {
    local service_name="$1"

    local init_system
    init_system="$(detect_init_system)"

    case "$init_system" in
        launchd)  _start_daemon_launchd "$service_name" ;;
        systemd)  _start_daemon_systemd "$service_name" ;;
        cron)     : ;;  # cron runs on schedule, no-op
    esac
}

# ==============================================================================
# stop_daemon
# ==============================================================================
# Stop a running daemon.
#
# Args:
#   $1 - service_name
#
# Returns: 0 on success, 1 on failure
# ==============================================================================

stop_daemon() {
    local service_name="$1"

    local init_system
    init_system="$(detect_init_system)"

    case "$init_system" in
        launchd)  _stop_daemon_launchd "$service_name" ;;
        systemd)  _stop_daemon_systemd "$service_name" ;;
        cron)     _stop_daemon_cron "$service_name" ;;
    esac
}

# ==============================================================================
# restart_daemon
# ==============================================================================
# Restart a daemon (stop + start).
#
# Args:
#   $1 - service_name
#
# Returns: 0 on success, 1 on failure
# ==============================================================================

restart_daemon() {
    local service_name="$1"

    local init_system
    init_system="$(detect_init_system)"

    case "$init_system" in
        launchd)  _restart_daemon_launchd "$service_name" ;;
        systemd)  _restart_daemon_systemd "$service_name" ;;
        cron)     _stop_daemon_cron "$service_name"; : ;;  # stop then cron reschedules
    esac
}

# ==============================================================================
# status_daemon
# ==============================================================================
# Check if a daemon is running.
#
# Args:
#   $1 - service_name
#
# Returns: 0 if running, 1 if stopped/not found
# ==============================================================================

status_daemon() {
    local service_name="$1"

    local init_system
    init_system="$(detect_init_system)"

    case "$init_system" in
        launchd)  _status_daemon_launchd "$service_name" ;;
        systemd)  _status_daemon_systemd "$service_name" ;;
        cron)     _status_daemon_cron "$service_name" ;;
    esac
}

# ==============================================================================
# list_daemons
# ==============================================================================
# List daemons matching a pattern.
#
# Args:
#   $1 - pattern (grep pattern to filter results)
#
# Output: matching daemon names/entries on stdout
# Returns: 0 if matches found, 1 if none
# ==============================================================================

list_daemons() {
    local pattern="${1:-checkpoint}"

    local init_system
    init_system="$(detect_init_system)"

    case "$init_system" in
        launchd)  _list_daemons_launchd "$pattern" ;;
        systemd)  _list_daemons_systemd "$pattern" ;;
        cron)     _list_daemons_cron "$pattern" ;;
    esac
}

# ==============================================================================
# LAUNCHD BACKEND (macOS)
# ==============================================================================

_install_daemon_launchd() {
    local service_name="$1"
    local script_path="$2"
    local project_dir="$3"
    local project_name="$4"
    local service_type="$5"

    local launchd_label
    launchd_label="$(_daemon_launchd_name "$service_name")"
    local plist_path="$HOME/Library/LaunchAgents/${launchd_label}.plist"

    mkdir -p "$HOME/Library/LaunchAgents" 2>/dev/null || true

    # Unload existing if present (handles both new and legacy naming)
    local existing_plist
    existing_plist="$(_daemon_plist_path "$service_name")"
    if [ -f "$existing_plist" ]; then
        local _svc_err
        if ! _svc_err=$(launchctl unload "$existing_plist" 2>&1); then
            log_debug "launchctl unload (pre-install): $_svc_err"
        fi
    fi

    # Find and apply template
    local template
    template="$(_daemon_find_template "$service_type" "launchd")"

    if [ -n "$template" ]; then
        _daemon_apply_template "$template" "$plist_path" "$project_name" "$project_dir" "$script_path"
    else
        # Generate inline plist for daemon type (no template file exists yet)
        local log_dir="$HOME/.checkpoint/logs"
        mkdir -p "$log_dir" 2>/dev/null || true

        cat > "$plist_path" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${launchd_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${script_path}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${project_dir}</string>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${log_dir}/${service_name}.out</string>
    <key>StandardErrorPath</key>
    <string>${log_dir}/${service_name}.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:${HOME}/.local/bin</string>
    </dict>
</dict>
</plist>
PLIST_EOF
    fi

    # Load the LaunchAgent
    local _svc_err
    if ! _svc_err=$(launchctl load -w "$plist_path" 2>&1); then
        log_debug "launchctl load -w $plist_path: $_svc_err"
    else
        log_info "Installed launchd agent: $launchd_label"
    fi
}

_uninstall_daemon_launchd() {
    local service_name="$1"
    local _svc_err

    # Check both new and legacy naming
    local plist_path
    plist_path="$(_daemon_plist_path "$service_name")"

    if [ -f "$plist_path" ]; then
        if ! _svc_err=$(launchctl unload "$plist_path" 2>&1); then
            log_debug "launchctl unload $plist_path: $_svc_err"
        fi
        rm -f "$plist_path"
    fi

    # Also clean up the other naming convention if it exists
    local new_path="$HOME/Library/LaunchAgents/$(_daemon_launchd_name "$service_name").plist"
    local legacy_path="$HOME/Library/LaunchAgents/$(_daemon_launchd_legacy_name "$service_name").plist"

    if [ -f "$new_path" ]; then
        if ! _svc_err=$(launchctl unload "$new_path" 2>&1); then
            log_debug "launchctl unload $new_path: $_svc_err"
        fi
        rm -f "$new_path"
    fi
    if [ -f "$legacy_path" ]; then
        if ! _svc_err=$(launchctl unload "$legacy_path" 2>&1); then
            log_debug "launchctl unload $legacy_path: $_svc_err"
        fi
        rm -f "$legacy_path"
    fi
    log_info "Uninstalled launchd agent: $service_name"
}

_start_daemon_launchd() {
    local service_name="$1"
    local plist_path
    plist_path="$(_daemon_plist_path "$service_name")"

    if [ -f "$plist_path" ]; then
        local _svc_err
        if ! _svc_err=$(launchctl load -w "$plist_path" 2>&1); then
            log_debug "launchctl load -w $plist_path: $_svc_err"
        fi
    else
        return 1
    fi
}

_stop_daemon_launchd() {
    local service_name="$1"
    local plist_path
    plist_path="$(_daemon_plist_path "$service_name")"

    if [ -f "$plist_path" ]; then
        local _svc_err
        if ! _svc_err=$(launchctl unload "$plist_path" 2>&1); then
            log_debug "launchctl unload $plist_path: $_svc_err"
        fi
    else
        return 1
    fi
}

_restart_daemon_launchd() {
    local service_name="$1"
    local plist_path
    plist_path="$(_daemon_plist_path "$service_name")"

    if [ -f "$plist_path" ]; then
        local _svc_err
        if ! _svc_err=$(launchctl unload "$plist_path" 2>&1); then
            log_debug "launchctl unload (restart) $plist_path: $_svc_err"
        fi
        sleep 1
        if ! _svc_err=$(launchctl load -w "$plist_path" 2>&1); then
            log_debug "launchctl load -w (restart) $plist_path: $_svc_err"
        fi
    else
        return 1
    fi
}

_status_daemon_launchd() {
    local service_name="$1"

    # Check both naming conventions
    local launchd_name
    launchd_name="$(_daemon_launchd_name "$service_name")"
    local legacy_name
    legacy_name="$(_daemon_launchd_legacy_name "$service_name")"

    if launchctl list 2>/dev/null | grep -q "$launchd_name"; then
        return 0
    elif launchctl list 2>/dev/null | grep -q "$legacy_name"; then
        return 0
    else
        return 1
    fi
}

_list_daemons_launchd() {
    local pattern="$1"
    launchctl list 2>/dev/null | grep "$pattern" || true
}

# ==============================================================================
# SYSTEMD BACKEND (Linux)
# ==============================================================================

_install_daemon_systemd() {
    local service_name="$1"
    local script_path="$2"
    local project_dir="$3"
    local project_name="$4"
    local service_type="$5"

    local systemd_name
    systemd_name="$(_daemon_systemd_name "$service_name")"
    local service_path="$HOME/.config/systemd/user/${systemd_name}.service"

    # Ensure user systemd directory exists
    mkdir -p "$HOME/.config/systemd/user" 2>/dev/null || true

    # Stop existing service if running
    local _svc_err
    if ! _svc_err=$(systemctl --user stop "$systemd_name" 2>&1); then
        log_debug "systemctl stop (pre-install) $systemd_name: $_svc_err"
    fi

    # Find and apply template
    local template
    template="$(_daemon_find_template "$service_type" "systemd")"

    if [ -n "$template" ]; then
        _daemon_apply_template "$template" "$service_path" "$project_name" "$project_dir" "$script_path"
    else
        return 1
    fi

    # For daemon type, also install the timer unit
    if [ "$service_type" = "daemon" ]; then
        local timer_template
        timer_template="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/templates/systemd-daemon.timer"
        if [ -f "$timer_template" ]; then
            local timer_path="$HOME/.config/systemd/user/${systemd_name}.timer"
            _daemon_apply_template "$timer_template" "$timer_path" "$project_name" "$project_dir" "$script_path"
        fi
    fi

    # Reload systemd, enable, and start
    if ! _svc_err=$(systemctl --user daemon-reload 2>&1); then
        log_debug "systemctl daemon-reload: $_svc_err"
    fi

    if [ "$service_type" = "daemon" ]; then
        # Timer-activated: enable and start the timer, not the service
        if ! _svc_err=$(systemctl --user enable "${systemd_name}.timer" 2>&1); then
            log_debug "systemctl enable ${systemd_name}.timer: $_svc_err"
        fi
        if ! _svc_err=$(systemctl --user start "${systemd_name}.timer" 2>&1); then
            log_debug "systemctl start ${systemd_name}.timer: $_svc_err"
        else
            log_info "Installed and started systemd timer: ${systemd_name}.timer"
        fi
    else
        # Long-running: enable and start the service directly
        if ! _svc_err=$(systemctl --user enable "$systemd_name" 2>&1); then
            log_debug "systemctl enable $systemd_name: $_svc_err"
        fi
        if ! _svc_err=$(systemctl --user start "$systemd_name" 2>&1); then
            log_debug "systemctl start $systemd_name: $_svc_err"
        else
            log_info "Installed and started systemd service: $systemd_name"
        fi
    fi
}

_uninstall_daemon_systemd() {
    local service_name="$1"
    local _svc_err

    local systemd_name
    systemd_name="$(_daemon_systemd_name "$service_name")"
    local service_path
    service_path="$(_daemon_service_path "$service_name")"
    local timer_path
    timer_path="$(_daemon_timer_path "$service_name")"

    # Stop and disable service
    if ! _svc_err=$(systemctl --user stop "$systemd_name" 2>&1); then
        log_debug "systemctl stop $systemd_name: $_svc_err"
    fi
    if ! _svc_err=$(systemctl --user disable "$systemd_name" 2>&1); then
        log_debug "systemctl disable $systemd_name: $_svc_err"
    fi

    # Stop and disable timer if it exists
    if [ -f "$timer_path" ]; then
        if ! _svc_err=$(systemctl --user stop "${systemd_name}.timer" 2>&1); then
            log_debug "systemctl stop ${systemd_name}.timer: $_svc_err"
        fi
        if ! _svc_err=$(systemctl --user disable "${systemd_name}.timer" 2>&1); then
            log_debug "systemctl disable ${systemd_name}.timer: $_svc_err"
        fi
        rm -f "$timer_path"
    fi

    # Remove service file
    rm -f "$service_path"

    # Reload daemon
    if ! _svc_err=$(systemctl --user daemon-reload 2>&1); then
        log_debug "systemctl daemon-reload: $_svc_err"
    fi
    log_info "Uninstalled systemd service: $systemd_name"
}

_start_daemon_systemd() {
    local service_name="$1"
    local _svc_err

    local systemd_name
    systemd_name="$(_daemon_systemd_name "$service_name")"
    local timer_path
    timer_path="$(_daemon_timer_path "$service_name")"

    # If timer exists, start the timer; otherwise start the service
    if [ -f "$timer_path" ]; then
        if ! _svc_err=$(systemctl --user start "${systemd_name}.timer" 2>&1); then
            log_debug "systemctl start ${systemd_name}.timer: $_svc_err"
        fi
    else
        if ! _svc_err=$(systemctl --user start "$systemd_name" 2>&1); then
            log_debug "systemctl start $systemd_name: $_svc_err"
        fi
    fi
}

_stop_daemon_systemd() {
    local service_name="$1"
    local _svc_err

    local systemd_name
    systemd_name="$(_daemon_systemd_name "$service_name")"
    local timer_path
    timer_path="$(_daemon_timer_path "$service_name")"

    # Stop timer if exists
    if [ -f "$timer_path" ]; then
        if ! _svc_err=$(systemctl --user stop "${systemd_name}.timer" 2>&1); then
            log_debug "systemctl stop ${systemd_name}.timer: $_svc_err"
        fi
    fi

    # Stop service
    if ! _svc_err=$(systemctl --user stop "$systemd_name" 2>&1); then
        log_debug "systemctl stop $systemd_name: $_svc_err"
    fi
}

_restart_daemon_systemd() {
    local service_name="$1"
    local _svc_err

    local systemd_name
    systemd_name="$(_daemon_systemd_name "$service_name")"
    local timer_path
    timer_path="$(_daemon_timer_path "$service_name")"

    if [ -f "$timer_path" ]; then
        if ! _svc_err=$(systemctl --user restart "${systemd_name}.timer" 2>&1); then
            log_debug "systemctl restart ${systemd_name}.timer: $_svc_err"
        fi
    else
        if ! _svc_err=$(systemctl --user restart "$systemd_name" 2>&1); then
            log_debug "systemctl restart $systemd_name: $_svc_err"
        fi
    fi
}

_status_daemon_systemd() {
    local service_name="$1"

    local systemd_name
    systemd_name="$(_daemon_systemd_name "$service_name")"

    systemctl --user is-active --quiet "$systemd_name" 2>/dev/null
}

_list_daemons_systemd() {
    local pattern="$1"
    systemctl --user list-units --type=service 2>/dev/null | grep "$pattern" || true
}

# ==============================================================================
# CRON BACKEND (fallback)
# ==============================================================================

_install_daemon_cron() {
    local service_name="$1"
    local script_path="$2"
    local project_dir="$3"
    local project_name="$4"
    local service_type="$5"

    local log_dir="$HOME/.checkpoint/logs"
    mkdir -p "$log_dir" 2>/dev/null || true

    # Build crontab entry based on service type
    local cron_schedule cron_entry
    case "$service_type" in
        watcher)
            # Watchers run every 5 minutes
            cron_schedule="*/5 * * * *"
            ;;
        daemon)
            # Daemons run hourly
            cron_schedule="0 * * * *"
            ;;
        watchdog)
            # Watchdog checks every minute
            cron_schedule="* * * * *"
            ;;
        *)
            cron_schedule="0 * * * *"
            ;;
    esac

    cron_entry="${cron_schedule} /bin/bash ${script_path} >> ${log_dir}/cron-${service_name}.log 2>&1 # checkpoint:${service_name}"

    # Remove existing entry for this service name, then add new one
    local current_crontab
    current_crontab="$(crontab -l 2>/dev/null || true)"

    # Filter out old entry and add new
    local new_crontab
    new_crontab="$(echo "$current_crontab" | grep -v "# checkpoint:${service_name}$" || true)"

    if [ -n "$new_crontab" ]; then
        printf '%s\n%s\n' "$new_crontab" "$cron_entry" | crontab -
    else
        echo "$cron_entry" | crontab -
    fi
}

_uninstall_daemon_cron() {
    local service_name="$1"

    local current_crontab
    current_crontab="$(crontab -l 2>/dev/null || true)"

    if [ -z "$current_crontab" ]; then
        return 0
    fi

    local new_crontab
    new_crontab="$(echo "$current_crontab" | grep -v "# checkpoint:${service_name}$" || true)"

    if [ -n "$new_crontab" ]; then
        echo "$new_crontab" | crontab -
    else
        crontab -r 2>/dev/null || true
    fi
}

_stop_daemon_cron() {
    local service_name="$1"

    # Check for PID file
    local pid_file="$HOME/.checkpoint/${service_name}.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid="$(cat "$pid_file" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
    fi
}

_status_daemon_cron() {
    local service_name="$1"

    # Check if crontab entry exists
    if crontab -l 2>/dev/null | grep -q "# checkpoint:${service_name}$"; then
        # Entry exists; check if a process is running
        local pid_file="$HOME/.checkpoint/${service_name}.pid"
        if [ -f "$pid_file" ]; then
            local pid
            pid="$(cat "$pid_file" 2>/dev/null || true)"
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                return 0  # running
            fi
        fi
        # Crontab entry exists but process not running (scheduled)
        return 0
    fi

    return 1  # not installed
}

_list_daemons_cron() {
    local pattern="$1"
    crontab -l 2>/dev/null | grep "$pattern" || true
}
