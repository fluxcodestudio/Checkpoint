#!/bin/bash
# Checkpoint Project Backups - Shell Integration
# Universal shell integration for bash/zsh
# Version: 1.2.0
#
# Source this file in your ~/.bashrc or ~/.zshrc:
#   source /path/to/backup-shell-integration.sh

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Find integration directory (handle both sourced and direct execution)
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    BACKUP_INTEGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
    # Fallback for when BASH_SOURCE is not available
    BACKUP_INTEGRATION_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi
BACKUP_BIN_DIR="$BACKUP_INTEGRATION_DIR/../bin"

# User-configurable options (set these before sourcing if you want custom values)
: "${BACKUP_AUTO_TRIGGER:=true}"        # Auto-backup on directory change
: "${BACKUP_SHOW_PROMPT:=true}"         # Show status in prompt
: "${BACKUP_TRIGGER_INTERVAL:=300}"     # Debounce interval (seconds)
: "${BACKUP_PROMPT_FORMAT:=emoji}"      # emoji | compact | verbose
: "${BACKUP_ALIASES_ENABLED:=true}"     # Enable quick aliases

# ==============================================================================
# LOAD CORE LIBRARY
# ==============================================================================

BACKUP_INTEGRATION_QUIET_LOAD=true
if [[ -f "$BACKUP_INTEGRATION_DIR/lib/integration-core.sh" ]]; then
    source "$BACKUP_INTEGRATION_DIR/lib/integration-core.sh"
else
    echo "❌ Error: integration-core.sh not found" >&2
    return 1
fi

# Initialize integration
integration_init || return 1

# ==============================================================================
# PROMPT INTEGRATION
# ==============================================================================

# Get status for shell prompt
backup_prompt_status() {
    [[ "$BACKUP_SHOW_PROMPT" != "true" ]] && return

    local status=$(integration_get_status_compact 2>/dev/null)
    local exit_code=$?

    case "$BACKUP_PROMPT_FORMAT" in
        emoji)
            # Just show emoji: ✅ or ⚠️ or ❌
            if [[ $exit_code -eq 0 ]]; then
                echo "${status%% *}"  # Extract first word (emoji)
            fi
            ;;
        compact)
            # Show emoji + time: ✅ 2h
            if [[ $exit_code -eq 0 ]]; then
                local emoji="${status%% *}"
                local time=$(integration_time_since_backup)
                echo "$emoji ${time%% *}"  # emoji + time without "ago"
            fi
            ;;
        verbose)
            # Show full compact status
            if [[ $exit_code -eq 0 ]]; then
                echo "$status"
            fi
            ;;
    esac
}

# Add to prompt based on shell type
if [[ -n "$BASH_VERSION" ]]; then
    # Bash: Add to PS1
    # Only add if not already present
    if [[ "$PS1" != *'backup_prompt_status'* ]]; then
        PS1="\$(backup_prompt_status) $PS1"
    fi
elif [[ -n "$ZSH_VERSION" ]]; then
    # Zsh: Add to PROMPT (requires PROMPT_SUBST)
    setopt PROMPT_SUBST 2>/dev/null
    if [[ "$PROMPT" != *'backup_prompt_status'* ]]; then
        PROMPT='$(backup_prompt_status) '"$PROMPT"
    fi
fi

# ==============================================================================
# AUTO-TRIGGER ON DIRECTORY CHANGE
# ==============================================================================

# Debounced backup trigger
backup_auto_trigger() {
    [[ "$BACKUP_AUTO_TRIGGER" != "true" ]] && return

    # Only trigger if in a git repository (optional optimization)
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        # Trigger backup in background (quiet mode)
        integration_trigger_backup --quiet &>/dev/null &
        disown
    fi
}

# Hook into shell based on type
if [[ -n "$BASH_VERSION" ]]; then
    # Bash: Use PROMPT_COMMAND
    if [[ "$PROMPT_COMMAND" != *'backup_auto_trigger'* ]]; then
        PROMPT_COMMAND="backup_auto_trigger;${PROMPT_COMMAND}"
    fi
elif [[ -n "$ZSH_VERSION" ]]; then
    # Zsh: Use chpwd hook
    if ! (( ${chpwd_functions[(I)backup_auto_trigger]} )); then
        chpwd_functions+=(backup_auto_trigger)
    fi
fi

# ==============================================================================
# QUICK COMMAND ALIASES
# ==============================================================================

if [[ "$BACKUP_ALIASES_ENABLED" == "true" ]]; then
    alias bs='$BACKUP_BIN_DIR/backup-status.sh'
    alias bn='$BACKUP_BIN_DIR/backup-now.sh'
    alias bc='$BACKUP_BIN_DIR/backup-config.sh'
    alias bcl='$BACKUP_BIN_DIR/backup-cleanup.sh'
    alias br='$BACKUP_BIN_DIR/backup-restore.sh'
fi

# ==============================================================================
# UNIFIED BACKUP COMMAND
# ==============================================================================

# Main backup command dispatcher
# Usage: backup {status|now|config|cleanup|restore} [OPTIONS]
backup() {
    case "$1" in
        status|s)
            shift
            "$BACKUP_BIN_DIR/backup-status.sh" "$@"
            ;;
        now|n)
            shift
            "$BACKUP_BIN_DIR/backup-now.sh" "$@"
            ;;
        config|cfg|c)
            shift
            "$BACKUP_BIN_DIR/backup-config.sh" "$@"
            ;;
        cleanup|clean|cl)
            shift
            "$BACKUP_BIN_DIR/backup-cleanup.sh" "$@"
            ;;
        restore|r)
            shift
            "$BACKUP_BIN_DIR/backup-restore.sh" "$@"
            ;;
        help|h|--help|-h)
            cat << 'EOF'
backup - Checkpoint Project Backups Shell Integration

USAGE:
    backup <command> [options]

COMMANDS:
    status, s       Show backup status dashboard
    now, n          Trigger backup now
    config, c       Manage configuration
    cleanup, cl     Clean up old backups
    restore, r      Restore from backup
    help, h         Show this help

QUICK ALIASES:
    bs              Alias for: backup status
    bn              Alias for: backup now
    bc              Alias for: backup config
    bcl             Alias for: backup cleanup
    br              Alias for: backup restore

EXAMPLES:
    backup status             # Show full dashboard
    backup now --force        # Force immediate backup
    backup cleanup --preview  # Preview cleanup
    bs --compact              # Quick status (via alias)
    bn --dry-run              # Preview backup (via alias)

CONFIGURATION:
    Set these before sourcing this file in ~/.bashrc or ~/.zshrc:

    BACKUP_AUTO_TRIGGER=true          # Auto-backup on cd
    BACKUP_SHOW_PROMPT=true           # Show status in prompt
    BACKUP_TRIGGER_INTERVAL=300       # Debounce (seconds)
    BACKUP_PROMPT_FORMAT=emoji        # emoji|compact|verbose
    BACKUP_ALIASES_ENABLED=true       # Enable aliases

For more information:
    backup status --help
    backup now --help
EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Run 'backup help' for usage information" >&2
            return 1
            ;;
    esac
}

# ==============================================================================
# GIT INTEGRATION (OPTIONAL)
# ==============================================================================

# Auto-backup before git commit
# To use: Add to your .bashrc/zshrc:
#   alias git-safe-commit='backup_git_pre_commit && git commit'
backup_git_pre_commit() {
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "🔄 Creating backup before commit..."
        integration_trigger_backup --force
    fi
}

# ==============================================================================
# INSTALLATION COMPLETE
# ==============================================================================

echo "✅ Backup shell integration loaded"
echo "   Commands: backup {status|now|config|cleanup|restore}"
if [[ "$BACKUP_ALIASES_ENABLED" == "true" ]]; then
    echo "   Aliases: bs, bn, bc, bcl, br"
fi
if [[ "$BACKUP_SHOW_PROMPT" == "true" ]]; then
    echo "   Prompt: $(backup_prompt_status)"
fi
echo "   Type 'backup help' for more information"
