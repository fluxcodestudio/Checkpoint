#!/bin/bash
# Checkpoint Control Panel - Main command for managing Checkpoint

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Find the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Parse arguments
UPDATE=false
STATUS=false
CHECK_UPDATE=false
INFO=false
HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --update)
            UPDATE=true
            shift
            ;;
        --status)
            STATUS=true
            shift
            ;;
        --check-update)
            CHECK_UPDATE=true
            shift
            ;;
        --info)
            INFO=true
            shift
            ;;
        --help|-h)
            HELP=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Function to check for updates
check_for_updates() {
    local current_version=""
    local latest_version=""

    # Get current version
    if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
        current_version=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "unknown")
    else
        current_version="unknown"
    fi

    # Get latest version from GitHub
    latest_version=$(curl -sf https://api.github.com/repos/nizernoj/Checkpoint/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' 2>/dev/null || echo "")

    if [[ -z "$latest_version" ]]; then
        echo -e "${YELLOW}ℹ${NC}  Running development version - updates will be available after first GitHub release"
        return 1
    fi

    if [[ "$current_version" == "$latest_version" ]]; then
        echo -e "${GREEN}✓${NC} You're running the latest version: ${BOLD}v$current_version${NC}"
        return 0
    else
        echo -e "${CYAN}ℹ${NC}  Update available: ${BOLD}v$current_version${NC} → ${BOLD}${GREEN}v$latest_version${NC}"
        return 2
    fi
}

# Function to detect installation mode
detect_installation_mode() {
    if command -v backup-status &>/dev/null; then
        echo "Global"
    else
        echo "Per-Project"
    fi
}

# Function to get config location
get_config_location() {
    local mode=$(detect_installation_mode)
    if [[ "$mode" == "Global" ]]; then
        # Check common locations
        if [[ -f "$HOME/.backup-config.yaml" ]]; then
            echo "$HOME/.backup-config.yaml"
        elif [[ -f "$PROJECT_ROOT/.backup-config.yaml" ]]; then
            echo "$PROJECT_ROOT/.backup-config.yaml"
        else
            echo "Not configured"
        fi
    else
        if [[ -f "$PROJECT_ROOT/.backup-config.yaml" ]]; then
            echo "$PROJECT_ROOT/.backup-config.yaml"
        else
            echo "Not configured"
        fi
    fi
}

# Function to show detailed info
show_info() {
    echo -e "${BOLD}${CYAN}System Information${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local mode=$(detect_installation_mode)
    local config=$(get_config_location)

    echo -e "${BOLD}Installation:${NC}"
    echo -e "  Mode: ${CYAN}$mode${NC}"
    if [[ "$mode" == "Global" ]]; then
        echo -e "  Commands: /usr/local/bin/backup-* or ~/.local/bin/backup-*"
    else
        echo -e "  Commands: $PROJECT_ROOT/bin/backup-*.sh"
    fi
    echo ""

    echo -e "${BOLD}Configuration:${NC}"
    if [[ "$config" != "Not configured" ]]; then
        echo -e "  Location: $config"

        # Try to show project name if configured
        if [[ -f "$config" ]]; then
            local project_name=$(grep "^  name:" "$config" 2>/dev/null | sed 's/.*: *"\?\([^"]*\)"\?/\1/' || echo "")
            if [[ -n "$project_name" ]]; then
                echo -e "  Project: $project_name"
            fi

            # Show backup directory
            local backup_dir=$(grep "^  directory:" "$config" 2>/dev/null | sed 's/.*: *"\?\([^"]*\)"\?/\1/' || echo "")
            if [[ -n "$backup_dir" ]]; then
                echo -e "  Backups: $backup_dir"

                # Show disk usage if directory exists
                if [[ -d "$backup_dir" ]]; then
                    local size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
                    echo -e "  Size: $size"
                fi
            fi
        fi
    else
        echo -e "  ${YELLOW}Not configured yet${NC}"
        echo -e "  Run: ${GREEN}/backup-config wizard${NC}"
    fi
    echo ""

    # Cloud backup status
    if [[ -f "$config" ]]; then
        local cloud_enabled=$(grep "^  enabled:" "$config" 2>/dev/null | grep -i "true" || echo "")
        if [[ -n "$cloud_enabled" ]]; then
            echo -e "${BOLD}Cloud Backup:${NC}"
            local cloud_remote=$(grep "^  remote_name:" "$config" 2>/dev/null | sed 's/.*: *"\?\([^"]*\)"\?/\1/' || echo "")
            if [[ -n "$cloud_remote" ]]; then
                echo -e "  Status: ${GREEN}Enabled${NC}"
                echo -e "  Provider: $cloud_remote"
            fi
            echo ""
        fi
    fi

    # LaunchAgent status (macOS)
    if [[ "$(uname)" == "Darwin" ]]; then
        echo -e "${BOLD}Automation:${NC}"
        local plist="$HOME/Library/LaunchAgents/com.checkpoint.backup.plist"
        if [[ -f "$plist" ]]; then
            if launchctl list | grep -q "com.checkpoint.backup"; then
                echo -e "  LaunchAgent: ${GREEN}Running${NC}"
            else
                echo -e "  LaunchAgent: ${YELLOW}Stopped${NC}"
            fi
        else
            echo -e "  LaunchAgent: ${YELLOW}Not installed${NC}"
        fi
        echo ""
    fi

    echo -e "${BOLD}Quick Actions:${NC}"
    echo -e "  ${GREEN}/checkpoint --update${NC}     Update Checkpoint"
    echo -e "  ${GREEN}/backup-config${NC}          Configure settings"
    echo -e "  ${GREEN}/backup-status${NC}          Full health check"
    echo ""
}

# Function to show help
show_help() {
    echo -e "${BOLD}${CYAN}Checkpoint - Control Panel${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  /checkpoint [OPTIONS]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  ${GREEN}--update${NC}          Check and install updates"
    echo -e "  ${GREEN}--check-update${NC}    Check for updates only (don't install)"
    echo -e "  ${GREEN}--status${NC}          Show status dashboard (default)"
    echo -e "  ${GREEN}--info${NC}            Show detailed system information"
    echo -e "  ${GREEN}--help, -h${NC}        Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  /checkpoint                   # Show status dashboard"
    echo -e "  /checkpoint --update          # Update Checkpoint"
    echo -e "  /checkpoint --info            # Show system details"
    echo ""
}

# Function to show status
show_status() {
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  Checkpoint Control Panel${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Version and installation mode
    local mode=$(detect_installation_mode)
    if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
        local version=$(cat "$PROJECT_ROOT/VERSION")
        echo -e "${BOLD}Version:${NC} v$version ${CYAN}($mode)${NC}"
    else
        echo -e "${BOLD}Mode:${NC} ${CYAN}$mode${NC}"
    fi

    # Configuration location
    local config=$(get_config_location)
    if [[ "$config" != "Not configured" ]]; then
        echo -e "${BOLD}Config:${NC} $config"
    fi

    echo ""

    # Check for updates
    check_for_updates
    echo ""

    # Backup status
    if command -v backup-status &>/dev/null; then
        backup-status --compact
    elif [[ -x "$PROJECT_ROOT/bin/backup-status.sh" ]]; then
        "$PROJECT_ROOT/bin/backup-status.sh" --compact
    fi

    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Quick Commands:${NC}"
    echo -e "  ${GREEN}/checkpoint --update${NC}       Update Checkpoint"
    echo -e "  ${GREEN}/backup-now${NC}              Create backup now"
    echo -e "  ${GREEN}/backup-pause${NC}            Pause/resume backups"
    echo -e "  ${GREEN}/backup-restore${NC}          Restore from backup"
    echo -e "  ${GREEN}/backup-cleanup${NC}          Clean old backups"
    echo ""
    echo -e "${BOLD}More Commands:${NC}"
    echo -e "  ${CYAN}/backup-config${NC}           Configure settings"
    echo -e "  ${CYAN}/backup-status${NC}           Detailed status"
    echo -e "  ${CYAN}/backup-cloud-config${NC}     Cloud backup setup"
    echo ""
}

# Handle help flag
if [[ "$HELP" == true ]]; then
    show_help
    exit 0
fi

# Handle info flag
if [[ "$INFO" == true ]]; then
    show_info
    exit 0
fi

# Handle update flag
if [[ "$UPDATE" == true ]] || [[ "$CHECK_UPDATE" == true ]]; then
    check_for_updates
    update_status=$?

    if [[ $update_status -eq 2 ]] && [[ "$UPDATE" == true ]]; then
        echo ""
        echo -e "${CYAN}ℹ${NC}  Starting update..."

        if command -v backup-update &>/dev/null; then
            backup-update
        elif [[ -x "$PROJECT_ROOT/bin/backup-update.sh" ]]; then
            "$PROJECT_ROOT/bin/backup-update.sh"
        else
            echo -e "${RED}✗${NC} Update command not found"
            exit 1
        fi
    fi
    exit 0
fi

# Handle status flag
if [[ "$STATUS" == true ]]; then
    show_status
    exit 0
fi

# Default: show control panel
show_status
