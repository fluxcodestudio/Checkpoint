#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Docker Volume Backup
# Detect, export, and restore Docker named volumes from Compose projects
# ==============================================================================
# @requires: Docker CLI 24.x+, Docker Compose v2 (or v1 fallback), busybox image
# @provides: docker_volumes_enabled, detect_compose_file, discover_project_volumes,
#            filter_volumes, backup_single_volume, backup_volume_safely,
#            backup_docker_volumes, restore_single_volume, list_volume_backups
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_DOCKER_VOLUMES:-}" ] && return || readonly _CHECKPOINT_DOCKER_VOLUMES=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Set logging context
if type log_set_context &>/dev/null; then
    log_set_context "docker-volumes"
fi

# ==============================================================================
# STATUS CHECK
# ==============================================================================

# Check if Docker volume backup is enabled in config
# Returns: 0 if enabled, 1 if disabled
docker_volumes_enabled() {
    if [ "${BACKUP_DOCKER_VOLUMES:-false}" = "true" ]; then
        return 0
    fi
    return 1
}

# ==============================================================================
# COMPOSE FILE DETECTION
# ==============================================================================

# Detect compose file in project directory
# Args: $1 = project directory
# Output: filename of compose file found
# Returns: 0 if found, 1 if not found
detect_compose_file() {
    local project_dir="$1"

    local compose_files="compose.yaml compose.yml docker-compose.yaml docker-compose.yml"
    local filename
    for filename in $compose_files; do
        if [ -f "$project_dir/$filename" ]; then
            echo "$filename"
            return 0
        fi
    done

    return 1
}

# ==============================================================================
# VOLUME DISCOVERY
# ==============================================================================

# Discover named volumes from compose config
# Args: $1 = project directory
# Output: volume names, one per line
# Returns: 0 on success, 1 on failure
discover_project_volumes() {
    local project_dir="$1"

    # Check Docker is available
    if ! command -v docker &>/dev/null; then
        if type log_warn &>/dev/null; then
            log_warn "Docker CLI not found"
        fi
        return 1
    fi

    # Check Docker is running (reuse is_docker_running if available, else inline)
    if type is_docker_running &>/dev/null; then
        if ! is_docker_running; then
            if type log_warn &>/dev/null; then
                log_warn "Docker is not running"
            fi
            return 1
        fi
    else
        # Inline check with timeout
        if command -v timeout &>/dev/null; then
            if ! timeout 5 docker info &>/dev/null 2>&1; then
                return 1
            fi
        elif command -v gtimeout &>/dev/null; then
            if ! gtimeout 5 docker info &>/dev/null 2>&1; then
                return 1
            fi
        else
            if ! docker info &>/dev/null 2>&1; then
                return 1
            fi
        fi
    fi

    # Detect compose command (v2 first, v1 fallback)
    local compose_cmd=""
    if docker compose version &>/dev/null 2>&1; then
        compose_cmd="docker compose"
    elif command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
        if type log_warn &>/dev/null; then
            log_warn "Using deprecated docker-compose v1 — consider upgrading to Compose v2"
        fi
    else
        if type log_warn &>/dev/null; then
            log_warn "Docker Compose not available"
        fi
        return 1
    fi

    # Get volumes from compose config (handles variable interpolation, merges, etc.)
    local volumes
    volumes=$(cd "$project_dir" && $compose_cmd config --volumes 2>/dev/null)

    if [ -z "$volumes" ]; then
        return 1
    fi

    echo "$volumes"
    return 0
}

# ==============================================================================
# VOLUME FILTERING
# ==============================================================================

# Filter volume list based on include/exclude config
# Reads volume names from stdin, outputs filtered list
# Uses: DOCKER_VOLUME_INCLUDES, DOCKER_VOLUME_EXCLUDES
filter_volumes() {
    local includes="${DOCKER_VOLUME_INCLUDES:-}"
    local excludes="${DOCKER_VOLUME_EXCLUDES:-}"

    while IFS= read -r volume; do
        [ -z "$volume" ] && continue

        # If includes are set, only allow listed volumes
        if [ -n "$includes" ]; then
            local found=false
            local IFS_OLD="$IFS"
            IFS=","
            local pattern
            for pattern in $includes; do
                # Trim whitespace
                pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [ "$volume" = "$pattern" ]; then
                    found=true
                    break
                fi
            done
            IFS="$IFS_OLD"
            if [ "$found" = "false" ]; then
                continue
            fi
        fi

        # Check excludes
        if [ -n "$excludes" ]; then
            local excluded=false
            local IFS_OLD="$IFS"
            IFS=","
            local pattern
            for pattern in $excludes; do
                # Trim whitespace
                pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Simple glob matching via case
                case "$volume" in
                    $pattern)
                        excluded=true
                        break
                        ;;
                esac
            done
            IFS="$IFS_OLD"
            if [ "$excluded" = "true" ]; then
                continue
            fi
        fi

        echo "$volume"
    done
}

# ==============================================================================
# BACKUP FUNCTIONS
# ==============================================================================

# Backup a single Docker volume to tar.gz archive
# Args: $1 = volume name, $2 = backup directory
# Returns: 0 on success, 1 on failure
backup_single_volume() {
    local volume_name="$1"
    local backup_dir="$2"
    local host_backup_dir="$backup_dir/docker-volumes"

    mkdir -p "$host_backup_dir"

    local backup_file="${volume_name}.tar.gz"

    # Export volume data via busybox container
    # CRITICAL: Use -C /data . to avoid nested directory structures
    if ! docker run --rm \
        -v "${volume_name}:/data:ro" \
        -v "${host_backup_dir}:/backup" \
        busybox tar czf "/backup/${backup_file}" -C /data . 2>&1; then
        echo "Error: Failed to backup volume $volume_name" >&2
        return 1
    fi

    # Encrypt if encryption is enabled
    if type encryption_enabled &>/dev/null && encryption_enabled; then
        if type encrypt_file &>/dev/null; then
            local src_path="${host_backup_dir}/${backup_file}"
            local enc_path="${host_backup_dir}/${backup_file}.age"
            if encrypt_file "$src_path" "$enc_path"; then
                rm -f "$src_path"
                if type log_info &>/dev/null; then
                    log_info "Volume $volume_name backed up and encrypted"
                fi
            else
                echo "Warning: Encryption failed for $volume_name, keeping unencrypted" >&2
            fi
        fi
    fi

    return 0
}

# Backup a volume with container stop/start for data consistency
# Args: $1 = volume name, $2 = backup directory
# Returns: 0 on success, 1 on failure
backup_volume_safely() {
    local volume_name="$1"
    local backup_dir="$2"
    local stopped_containers=""
    local backup_result=0

    # Find containers using this volume
    local containers
    containers=$(docker ps --filter "volume=${volume_name}" --format "{{.Names}}" 2>/dev/null)

    # Stop containers using this volume
    if [ -n "$containers" ]; then
        local container
        while IFS= read -r container; do
            [ -z "$container" ] && continue
            if type log_info &>/dev/null; then
                log_info "Stopping container $container for volume backup"
            fi
            if docker stop "$container" >/dev/null 2>&1; then
                if [ -n "$stopped_containers" ]; then
                    stopped_containers="$stopped_containers $container"
                else
                    stopped_containers="$container"
                fi
            else
                echo "Warning: Failed to stop container $container" >&2
            fi
        done <<< "$containers"
    fi

    # Perform backup
    backup_single_volume "$volume_name" "$backup_dir"
    backup_result=$?

    # Restart stopped containers (always, even on failure)
    if [ -n "$stopped_containers" ]; then
        local container
        for container in $stopped_containers; do
            if type log_info &>/dev/null; then
                log_info "Restarting container $container"
            fi
            if ! docker start "$container" >/dev/null 2>&1; then
                echo "Warning: Failed to restart container $container" >&2
            fi
        done
    fi

    return "$backup_result"
}

# Main entry point: backup all Docker volumes for a project
# Args: $1 = project directory, $2 = backup directory
# Returns: 0 if all succeed, 1 if any fail
backup_docker_volumes() {
    local project_dir="$1"
    local backup_dir="$2"

    # Check enabled
    if ! docker_volumes_enabled; then
        return 0
    fi

    # Detect compose file
    local compose_file
    compose_file=$(detect_compose_file "$project_dir")
    if [ $? -ne 0 ]; then
        if type log_info &>/dev/null; then
            log_info "No compose file found in $project_dir — skipping volume backup"
        fi
        return 0
    fi

    # Discover volumes
    local volumes
    volumes=$(discover_project_volumes "$project_dir")
    if [ -z "$volumes" ]; then
        if type log_info &>/dev/null; then
            log_info "No named volumes found in $compose_file"
        fi
        return 0
    fi

    # Filter volumes
    local filtered
    filtered=$(echo "$volumes" | filter_volumes)
    if [ -z "$filtered" ]; then
        if type log_info &>/dev/null; then
            log_info "All volumes excluded by filter"
        fi
        return 0
    fi

    # Create backup directory
    mkdir -p "$backup_dir/docker-volumes"

    # Backup each volume
    local total=0
    local backed_up=0
    local skipped=0
    local failed=0
    local has_failure=false

    while IFS= read -r volume; do
        [ -z "$volume" ] && continue
        total=$((total + 1))

        echo "  🐳 Backing up volume: $volume"
        if backup_volume_safely "$volume" "$backup_dir"; then
            backed_up=$((backed_up + 1))
            echo "  ✅ Volume: $volume"
        else
            failed=$((failed + 1))
            has_failure=true
            echo "  ❌ Volume: $volume (backup failed)"
        fi
    done <<< "$filtered"

    skipped=$((total - backed_up - failed))

    # Log summary
    if type log_info &>/dev/null; then
        log_info "Docker volumes: $backed_up backed up, $skipped skipped, $failed failed (of $total)"
    fi
    echo "  📦 Docker volumes: $backed_up backed up, $skipped skipped, $failed failed"

    if [ "$has_failure" = "true" ]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# RESTORE FUNCTIONS
# ==============================================================================

# Restore a single Docker volume from backup archive
# Args: $1 = volume name, $2 = backup file path (.tar.gz or .tar.gz.age)
# Returns: 0 on success, 1 on failure
restore_single_volume() {
    local volume_name="$1"
    local backup_file="$2"
    local restore_file="$backup_file"
    local temp_decrypt=""

    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file not found: $backup_file" >&2
        return 1
    fi

    # Handle encrypted backups
    case "$backup_file" in
        *.age)
            if ! type decrypt_file &>/dev/null; then
                echo "Error: Encryption module not loaded — cannot decrypt $backup_file" >&2
                return 1
            fi
            temp_decrypt=$(mktemp -t "checkpoint_vol_decrypt.XXXXXX.tar.gz") || {
                echo "Error: Failed to create temp file for decryption" >&2
                return 1
            }
            if ! decrypt_file "$backup_file" "$temp_decrypt"; then
                rm -f "$temp_decrypt"
                echo "Error: Failed to decrypt $backup_file" >&2
                return 1
            fi
            restore_file="$temp_decrypt"
            ;;
    esac

    # Create volume if it doesn't exist
    if ! docker volume inspect "$volume_name" &>/dev/null 2>&1; then
        if ! docker volume create "$volume_name" >/dev/null 2>&1; then
            [ -n "$temp_decrypt" ] && rm -f "$temp_decrypt"
            echo "Error: Failed to create volume $volume_name" >&2
            return 1
        fi
    fi

    # Clear existing data to prevent mixed state
    docker run --rm -v "${volume_name}:/data" busybox sh -c "rm -rf /data/* /data/.[!.]* /data/..?*" 2>/dev/null

    # Extract backup into volume
    local restore_dir
    restore_dir=$(dirname "$restore_file")
    local restore_basename
    restore_basename=$(basename "$restore_file")

    if ! docker run --rm \
        -v "${volume_name}:/data" \
        -v "${restore_dir}:/backup:ro" \
        busybox tar xzf "/backup/${restore_basename}" -C /data 2>&1; then
        [ -n "$temp_decrypt" ] && rm -f "$temp_decrypt"
        echo "Error: Failed to restore volume $volume_name" >&2
        return 1
    fi

    # Clean up temp decrypt file
    [ -n "$temp_decrypt" ] && rm -f "$temp_decrypt"

    echo "Restored volume: $volume_name"
    return 0
}

# ==============================================================================
# LISTING
# ==============================================================================

# List volume backups in a backup directory
# Args: $1 = backup directory
# Output: volume name, size, date for each backup file
list_volume_backups() {
    local backup_dir="$1"
    local vol_dir="$backup_dir/docker-volumes"

    if [ ! -d "$vol_dir" ]; then
        echo "No volume backups found in $backup_dir"
        return 0
    fi

    local found=false

    echo "Docker Volume Backups:"
    echo "─────────────────────────────"

    local file
    for file in "$vol_dir"/*.tar.gz "$vol_dir"/*.tar.gz.age; do
        [ -f "$file" ] || continue
        found=true

        local basename
        basename=$(basename "$file")

        # Extract volume name from filename
        local vol_name
        case "$basename" in
            *.tar.gz.age)
                vol_name="${basename%.tar.gz.age}"
                ;;
            *.tar.gz)
                vol_name="${basename%.tar.gz}"
                ;;
        esac

        # Get file size (portable)
        local size
        if stat --version &>/dev/null 2>&1; then
            # GNU stat
            size=$(stat --format="%s" "$file" 2>/dev/null)
        else
            # BSD stat (macOS)
            size=$(stat -f "%z" "$file" 2>/dev/null)
        fi

        # Human-readable size
        local human_size
        if [ -n "$size" ]; then
            if [ "$size" -gt 1073741824 ]; then
                human_size="$((size / 1073741824))GB"
            elif [ "$size" -gt 1048576 ]; then
                human_size="$((size / 1048576))MB"
            elif [ "$size" -gt 1024 ]; then
                human_size="$((size / 1024))KB"
            else
                human_size="${size}B"
            fi
        else
            human_size="unknown"
        fi

        # Get modification date (portable)
        local mod_date
        if stat --version &>/dev/null 2>&1; then
            mod_date=$(stat --format="%y" "$file" 2>/dev/null | cut -d' ' -f1)
        else
            mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null)
        fi

        local encrypted=""
        case "$basename" in
            *.age) encrypted=" 🔐" ;;
        esac

        echo "  $vol_name  ($human_size, $mod_date)$encrypted"
    done

    if [ "$found" = "false" ]; then
        echo "  No volume backups found"
    fi
}
