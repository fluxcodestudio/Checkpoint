#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Docker Volume Backup CLI
# Manage Docker volume backups: list, backup, restore, status
# Usage: checkpoint docker-volumes [list|backup|restore|status] [OPTIONS]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Source foundation library (loads core, ops, ui, platform, features)
source "$LIB_DIR/backup-lib.sh"

# Source Docker volume backup library
source "$LIB_DIR/features/docker-volumes.sh"

# ==============================================================================
# HELP TEXT
# ==============================================================================

show_help() {
    cat <<EOF
Checkpoint - Docker Volume Backup

USAGE
    checkpoint docker-volumes                  List detected volumes (default)
    checkpoint docker-volumes list             List detected volumes and backups
    checkpoint docker-volumes backup [OPTIONS] Manual volume backup
    checkpoint docker-volumes restore VOLUME   Restore a volume from backup
    checkpoint docker-volumes status           Show Docker volume backup config

COMMANDS
    list                    Show detected volumes and existing backups
    backup [--all]          Backup all detected volumes
    backup VOLUME_NAME      Backup a specific volume
    restore VOLUME [--from FILE]  Restore volume from backup (latest if no --from)
    status                  Show configuration and Docker status

OPTIONS
    --help, -h              Show this help

EXAMPLES
    checkpoint docker-volumes                       List volumes
    checkpoint docker-volumes backup --all           Backup all volumes
    checkpoint docker-volumes backup myapp_pgdata    Backup specific volume
    checkpoint docker-volumes restore myapp_pgdata   Restore from latest backup
    checkpoint docker-volumes restore myapp_pgdata --from backups/docker-volumes/myapp_pgdata.tar.gz
    checkpoint docker-volumes status                 Check config status

EOF
}

# ==============================================================================
# LOAD PROJECT CONFIG
# ==============================================================================

# Try to load project config for current directory
load_backup_config "$PWD" 2>/dev/null || true

# ==============================================================================
# COMMANDS
# ==============================================================================

cmd_list() {
    local project_dir="$PWD"
    local backup_dir="${BACKUP_DIR:-$project_dir/backups}"

    echo "Docker Volume Backup — List"
    echo "═══════════════════════════════════════"
    echo ""

    # Check Docker
    if ! command -v docker &>/dev/null; then
        echo "Docker CLI not found"
        return 1
    fi

    # Detect compose file
    local compose_file
    compose_file=$(detect_compose_file "$project_dir") || true
    if [ -z "$compose_file" ]; then
        echo "No compose file found in $project_dir"
        echo ""
        echo "Supported: compose.yaml, compose.yml, docker-compose.yaml, docker-compose.yml"
        return 0
    fi
    echo "Compose file: $compose_file"
    echo ""

    # Discover volumes
    local volumes
    volumes=$(discover_project_volumes "$project_dir" 2>/dev/null) || true
    if [ -z "$volumes" ]; then
        echo "No named volumes found (Docker may not be running)"
        return 0
    fi

    echo "Detected Volumes:"
    echo "─────────────────────────────"

    local vol_dir="$backup_dir/docker-volumes"

    while IFS= read -r volume; do
        [ -z "$volume" ] && continue

        local backup_info="no backup"
        # Check for existing backups
        if [ -f "$vol_dir/${volume}.tar.gz.age" ]; then
            local size mod_date
            size=$(stat -f "%z" "$vol_dir/${volume}.tar.gz.age" 2>/dev/null || echo "0")
            mod_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$vol_dir/${volume}.tar.gz.age" 2>/dev/null || echo "unknown")
            if [ "$size" -gt 1048576 ] 2>/dev/null; then
                backup_info="$((size / 1048576))MB, $mod_date 🔐"
            elif [ "$size" -gt 1024 ] 2>/dev/null; then
                backup_info="$((size / 1024))KB, $mod_date 🔐"
            else
                backup_info="${size}B, $mod_date 🔐"
            fi
        elif [ -f "$vol_dir/${volume}.tar.gz" ]; then
            local size mod_date
            size=$(stat -f "%z" "$vol_dir/${volume}.tar.gz" 2>/dev/null || echo "0")
            mod_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$vol_dir/${volume}.tar.gz" 2>/dev/null || echo "unknown")
            if [ "$size" -gt 1048576 ] 2>/dev/null; then
                backup_info="$((size / 1048576))MB, $mod_date"
            elif [ "$size" -gt 1024 ] 2>/dev/null; then
                backup_info="$((size / 1024))KB, $mod_date"
            else
                backup_info="${size}B, $mod_date"
            fi
        fi

        echo "  $volume  ($backup_info)"
    done <<< "$volumes"

    echo ""
}

cmd_backup() {
    local project_dir="$PWD"
    local backup_dir="${BACKUP_DIR:-$project_dir/backups}"
    local backup_all=false
    local target_volume=""

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) backup_all=true; shift ;;
            *) target_volume="$1"; shift ;;
        esac
    done

    echo "Docker Volume Backup — Manual Backup"
    echo "═══════════════════════════════════════"
    echo ""

    if [ "$backup_all" = true ]; then
        # Backup all detected volumes
        local volumes
        volumes=$(discover_project_volumes "$project_dir" 2>/dev/null) || true
        if [ -z "$volumes" ]; then
            echo "No volumes found to backup"
            return 1
        fi

        local filtered
        filtered=$(echo "$volumes" | filter_volumes)
        if [ -z "$filtered" ]; then
            echo "All volumes excluded by filter"
            return 0
        fi

        local total=0 succeeded=0
        while IFS= read -r volume; do
            [ -z "$volume" ] && continue
            total=$((total + 1))
            echo "Backing up: $volume..."
            if backup_volume_safely "$volume" "$backup_dir"; then
                echo "  Done: $volume"
                succeeded=$((succeeded + 1))
            else
                echo "  Failed: $volume"
            fi
        done <<< "$filtered"

        echo ""
        echo "Complete: $succeeded/$total volumes backed up"
    elif [ -n "$target_volume" ]; then
        echo "Backing up: $target_volume..."
        if backup_volume_safely "$target_volume" "$backup_dir"; then
            echo "Done: $target_volume backed up"
        else
            echo "Failed: $target_volume backup failed"
            return 1
        fi
    else
        echo "Specify a volume name or use --all"
        echo ""
        echo "Usage:"
        echo "  checkpoint docker-volumes backup --all"
        echo "  checkpoint docker-volumes backup VOLUME_NAME"
        return 1
    fi
}

cmd_restore() {
    local volume_name="${1:-}"
    local backup_file=""

    if [ -z "$volume_name" ]; then
        echo "Usage: checkpoint docker-volumes restore VOLUME_NAME [--from FILE]"
        return 1
    fi
    shift

    # Parse --from
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) backup_file="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done

    local backup_dir="${BACKUP_DIR:-$PWD/backups}"
    local vol_dir="$backup_dir/docker-volumes"

    # Find backup file if not specified
    if [ -z "$backup_file" ]; then
        if [ -f "$vol_dir/${volume_name}.tar.gz.age" ]; then
            backup_file="$vol_dir/${volume_name}.tar.gz.age"
        elif [ -f "$vol_dir/${volume_name}.tar.gz" ]; then
            backup_file="$vol_dir/${volume_name}.tar.gz"
        else
            echo "No backup found for volume: $volume_name"
            echo "Expected: $vol_dir/${volume_name}.tar.gz"
            return 1
        fi
    fi

    echo "Docker Volume Backup — Restore"
    echo "═══════════════════════════════════════"
    echo ""
    echo "Volume:  $volume_name"
    echo "From:    $backup_file"
    echo ""

    if restore_single_volume "$volume_name" "$backup_file"; then
        echo ""
        echo "Restore complete: $volume_name"
    else
        echo ""
        echo "Restore failed: $volume_name"
        return 1
    fi
}

cmd_status() {
    echo "Docker Volume Backup — Status"
    echo "═══════════════════════════════════════"
    echo ""

    # Feature enabled
    if docker_volumes_enabled; then
        echo "  Feature:         Enabled (BACKUP_DOCKER_VOLUMES=true)"
    else
        echo "  Feature:         Disabled (set BACKUP_DOCKER_VOLUMES=true to enable)"
    fi

    # Docker running
    if command -v docker &>/dev/null; then
        if docker info &>/dev/null 2>&1; then
            echo "  Docker:          Running"
        else
            echo "  Docker:          Not running"
        fi
    else
        echo "  Docker:          Not installed"
    fi

    # Compose file
    local compose_file
    compose_file=$(detect_compose_file "$PWD" 2>/dev/null) || true
    if [ -n "$compose_file" ]; then
        echo "  Compose file:    $compose_file"
    else
        echo "  Compose file:    Not found"
    fi

    # Volumes
    local volumes
    volumes=$(discover_project_volumes "$PWD" 2>/dev/null) || true
    if [ -n "$volumes" ]; then
        local count
        count=$(echo "$volumes" | wc -l | tr -d ' ')
        echo "  Volumes found:   $count"
    else
        echo "  Volumes found:   0"
    fi

    # Include/exclude patterns
    if [ -n "${DOCKER_VOLUME_INCLUDES:-}" ]; then
        echo "  Include filter:  $DOCKER_VOLUME_INCLUDES"
    fi
    if [ -n "${DOCKER_VOLUME_EXCLUDES:-}" ]; then
        echo "  Exclude filter:  $DOCKER_VOLUME_EXCLUDES"
    fi

    echo ""
}

# ==============================================================================
# ARGUMENT PARSING & DISPATCH
# ==============================================================================

MODE="${1:-list}"

case "$MODE" in
    list)
        cmd_list
        ;;
    backup)
        shift
        cmd_backup "$@"
        ;;
    restore)
        shift
        cmd_restore "$@"
        ;;
    status)
        cmd_status
        ;;
    --help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $MODE" >&2
        echo "Use --help for usage information" >&2
        exit 1
        ;;
esac
