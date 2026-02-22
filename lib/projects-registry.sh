#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Projects Registry
# ==============================================================================
# Manages global registry of all projects using Checkpoint
# Location: ~/.config/checkpoint/projects.json
# ==============================================================================

REGISTRY_FILE="${CHECKPOINT_REGISTRY:-$HOME/.config/checkpoint/projects.json}"
REGISTRY_DIR="$(dirname "$REGISTRY_FILE")"
_REGISTRY_LOCK_DIR="$HOME/.config/checkpoint/.registry.lock"

# ==============================================================================
# FILE LOCKING (Fix #6: prevent concurrent corruption)
# ==============================================================================

# Acquire registry lock (mkdir-based atomic locking)
# Timeout: 5 seconds with stale PID detection
_registry_lock() {
    local max_wait=50  # 50 * 0.1s = 5 seconds
    local attempt=0

    while ! mkdir "$_REGISTRY_LOCK_DIR" 2>/dev/null; do
        # Check for stale lock
        if [[ -f "$_REGISTRY_LOCK_DIR/pid" ]]; then
            local lock_pid
            lock_pid=$(cat "$_REGISTRY_LOCK_DIR/pid" 2>/dev/null)
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Stale lock — owning process is dead
                rm -rf "$_REGISTRY_LOCK_DIR"
                continue
            fi
        fi
        ((attempt++))
        if [[ $attempt -ge $max_wait ]]; then
            echo "Warning: Could not acquire registry lock after 5s" >&2
            return 1
        fi
        sleep 0.1
    done
    echo $$ > "$_REGISTRY_LOCK_DIR/pid"
    return 0
}

# Release registry lock
_registry_unlock() {
    rm -rf "$_REGISTRY_LOCK_DIR" 2>/dev/null
}

# Ensure registry exists
init_registry() {
    mkdir -p "$REGISTRY_DIR"
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo '{"version": 1, "projects": []}' > "$REGISTRY_FILE"
    fi
}

# List all registered projects
# Output: one project path per line
list_projects() {
    init_registry
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for p in data.get('projects', []):
    if p.get('enabled', True):
        print(p['path'])
" "$REGISTRY_FILE"
    else
        # Fallback: simple grep (less reliable)
        grep -o '"path": "[^"]*"' "$REGISTRY_FILE" | cut -d'"' -f4
    fi
}

# Check if project is registered
# Args: $1 = project path
is_registered() {
    local project_path="$1"
    init_registry
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for p in data.get('projects', []):
    if p['path'] == sys.argv[2]:
        exit(0)
exit(1)
" "$REGISTRY_FILE" "$project_path"
    else
        grep -q "\"path\": \"$project_path\"" "$REGISTRY_FILE"
    fi
}

# Register a project
# Args: $1 = project path, $2 = project name (optional)
register_project() {
    local project_path="$1"
    local project_name="${2:-$(basename "$project_path")}"

    init_registry

    # Don't re-register
    if is_registered "$project_path"; then
        return 0
    fi

    _registry_lock || return 1

    # Write .checkpoint-id to project for UUID tracking (Fix #11)
    local project_id=""
    if [[ -f "$project_path/.checkpoint-id" ]]; then
        project_id=$(cat "$project_path/.checkpoint-id" 2>/dev/null)
    fi
    if [[ -z "$project_id" ]]; then
        # Generate a UUID
        if command -v uuidgen &>/dev/null; then
            project_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
        else
            project_id=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "$$-$(date +%s)")
        fi
        echo "$project_id" > "$project_path/.checkpoint-id" 2>/dev/null || true
    fi

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, time, sys

registry_file = sys.argv[1]
project_path = sys.argv[2]
project_name = sys.argv[3]
project_id = sys.argv[4]

with open(registry_file) as f:
    data = json.load(f)

data['projects'].append({
    'path': project_path,
    'name': project_name,
    'project_id': project_id,
    'enabled': True,
    'added': int(time.time()),
    'last_backup': None
})

with open(registry_file, 'w') as f:
    json.dump(data, f, indent=2)
" "$REGISTRY_FILE" "$project_path" "$project_name" "$project_id"
        _registry_unlock
        echo "Registered project: $project_name"
    else
        _registry_unlock
        echo "Warning: python3 required for project registration" >&2
        return 1
    fi
}

# Unregister a project
# Args: $1 = project path
unregister_project() {
    local project_path="$1"

    init_registry

    _registry_lock || return 1

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys

registry_file = sys.argv[1]
project_path = sys.argv[2]

with open(registry_file) as f:
    data = json.load(f)

data['projects'] = [p for p in data.get('projects', []) if p['path'] != project_path]

with open(registry_file, 'w') as f:
    json.dump(data, f, indent=2)
" "$REGISTRY_FILE" "$project_path"
        _registry_unlock
        echo "Unregistered project: $project_path"
    else
        _registry_unlock
    fi
}

# Update last backup time for a project
# Args: $1 = project path
update_last_backup() {
    local project_path="$1"

    init_registry

    _registry_lock || return 1

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, time, sys

registry_file = sys.argv[1]
project_path = sys.argv[2]

with open(registry_file) as f:
    data = json.load(f)

for p in data.get('projects', []):
    if p['path'] == project_path:
        p['last_backup'] = int(time.time())
        break

with open(registry_file, 'w') as f:
    json.dump(data, f, indent=2)
" "$REGISTRY_FILE" "$project_path"
    fi
    _registry_unlock
}

# Get project info as JSON
# Args: $1 = project path
get_project_info() {
    local project_path="$1"

    init_registry

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys

registry_file = sys.argv[1]
project_path = sys.argv[2]

with open(registry_file) as f:
    data = json.load(f)

for p in data.get('projects', []):
    if p['path'] == project_path:
        print(json.dumps(p))
        exit(0)
print('null')
" "$REGISTRY_FILE" "$project_path"
    fi
}

# Enable/disable a project
# Args: $1 = project path, $2 = enabled (true/false)
set_project_enabled() {
    local project_path="$1"
    local enabled="$2"

    init_registry

    _registry_lock || return 1

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys

registry_file = sys.argv[1]
project_path = sys.argv[2]
enabled = sys.argv[3].lower() == 'true'

with open(registry_file) as f:
    data = json.load(f)

for p in data.get('projects', []):
    if p['path'] == project_path:
        p['enabled'] = enabled
        break

with open(registry_file, 'w') as f:
    json.dump(data, f, indent=2)
" "$REGISTRY_FILE" "$project_path" "$enabled"
    fi
    _registry_unlock
}

# Count registered projects
count_projects() {
    init_registry
    list_projects | wc -l | tr -d ' '
}

# Clean up orphaned projects (directories that no longer exist)
# Fix #12: Use while-read instead of for-in to handle paths with spaces
# Fix #11: Search for moved projects by UUID before removing
cleanup_orphaned() {
    init_registry
    local removed=0
    local relocated=0

    while IFS= read -r project_path; do
        if [[ ! -d "$project_path" ]]; then
            # Fix #11: Before removing, check if project moved (search by UUID)
            local project_id=""
            if command -v python3 &>/dev/null; then
                project_id=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for p in data.get('projects', []):
    if p['path'] == sys.argv[2]:
        print(p.get('project_id', ''))
        break
" "$REGISTRY_FILE" "$project_path" 2>/dev/null)
            fi

            local found_new_path=""
            if [[ -n "$project_id" ]]; then
                # Search multiple locations for the same .checkpoint-id
                # 1. Parent directory (renamed in place)
                # 2. Grandparent directory (moved nearby)
                # 3. Common project directories (moved elsewhere)
                local _search_dirs=()
                local parent_dir
                parent_dir=$(dirname "$project_path")
                [[ -d "$parent_dir" ]] && _search_dirs+=("$parent_dir")
                local grandparent_dir
                grandparent_dir=$(dirname "$parent_dir")
                [[ -d "$grandparent_dir" ]] && [[ "$grandparent_dir" != "$parent_dir" ]] && _search_dirs+=("$grandparent_dir")
                # Add common project base directories
                for _base in "$HOME/Projects" "$HOME/Developer" "$HOME/Code" "$HOME/repos" "$HOME/src" "$HOME/Sites" "$HOME/Desktop" "$HOME/Documents"; do
                    [[ -d "$_base" ]] && _search_dirs+=("$_base")
                done
                # Add /Volumes project directories (macOS external drives)
                for _vol_dir in /Volumes/*/Projects /Volumes/*/Developer /Volumes/*/Code; do
                    [[ -d "$_vol_dir" ]] && _search_dirs+=("$_vol_dir")
                done

                # Deduplicate search dirs
                local -a _unique_dirs=()
                local _seen=""
                for _sd in "${_search_dirs[@]}"; do
                    if [[ "$_seen" != *"|$_sd|"* ]]; then
                        _unique_dirs+=("$_sd")
                        _seen="${_seen}|$_sd|"
                    fi
                done

                for _search_dir in "${_unique_dirs[@]}"; do
                    [[ -n "$found_new_path" ]] && break
                    while IFS= read -r -d '' id_file; do
                        local candidate_id
                        candidate_id=$(cat "$id_file" 2>/dev/null)
                        if [[ "$candidate_id" == "$project_id" ]]; then
                            found_new_path=$(dirname "$id_file")
                            break
                        fi
                    done < <(find "$_search_dir" -maxdepth 4 -name ".checkpoint-id" -print0 2>/dev/null)
                done
            fi

            if [[ -n "$found_new_path" ]] && [[ -d "$found_new_path" ]]; then
                # Project was moved — update registry entry
                if command -v python3 &>/dev/null; then
                    _registry_lock || continue
                    python3 -c "
import json, sys
registry_file = sys.argv[1]
old_path = sys.argv[2]
new_path = sys.argv[3]
with open(registry_file) as f:
    data = json.load(f)
for p in data.get('projects', []):
    if p['path'] == old_path:
        p['path'] = new_path
        p['name'] = new_path.rstrip('/').split('/')[-1]
        break
with open(registry_file, 'w') as f:
    json.dump(data, f, indent=2)
" "$REGISTRY_FILE" "$project_path" "$found_new_path"
                    _registry_unlock
                    echo "Relocated project: $project_path -> $found_new_path"
                    ((relocated++))
                fi
            else
                unregister_project "$project_path"
                ((removed++))
            fi
        fi
    done < <(list_projects)

    echo "Removed $removed orphaned projects, relocated $relocated"
}
