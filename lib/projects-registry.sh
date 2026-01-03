#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Projects Registry
# ==============================================================================
# Manages global registry of all projects using Checkpoint
# Location: ~/.config/checkpoint/projects.json
# ==============================================================================

REGISTRY_FILE="${CHECKPOINT_REGISTRY:-$HOME/.config/checkpoint/projects.json}"
REGISTRY_DIR="$(dirname "$REGISTRY_FILE")"

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
import json
with open('$REGISTRY_FILE') as f:
    data = json.load(f)
for p in data.get('projects', []):
    if p.get('enabled', True):
        print(p['path'])
"
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
import json
with open('$REGISTRY_FILE') as f:
    data = json.load(f)
for p in data.get('projects', []):
    if p['path'] == '$project_path':
        exit(0)
exit(1)
"
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

    if command -v python3 &>/dev/null; then
        python3 -c "
import json
import time

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

data['projects'].append({
    'path': '$project_path',
    'name': '$project_name',
    'enabled': True,
    'added': int(time.time()),
    'last_backup': None
})

with open('$REGISTRY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
        echo "Registered project: $project_name"
    else
        echo "Warning: python3 required for project registration" >&2
        return 1
    fi
}

# Unregister a project
# Args: $1 = project path
unregister_project() {
    local project_path="$1"

    init_registry

    if command -v python3 &>/dev/null; then
        python3 -c "
import json

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

data['projects'] = [p for p in data.get('projects', []) if p['path'] != '$project_path']

with open('$REGISTRY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
        echo "Unregistered project: $project_path"
    fi
}

# Update last backup time for a project
# Args: $1 = project path
update_last_backup() {
    local project_path="$1"

    init_registry

    if command -v python3 &>/dev/null; then
        python3 -c "
import json
import time

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

for p in data.get('projects', []):
    if p['path'] == '$project_path':
        p['last_backup'] = int(time.time())
        break

with open('$REGISTRY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
}

# Get project info as JSON
# Args: $1 = project path
get_project_info() {
    local project_path="$1"

    init_registry

    if command -v python3 &>/dev/null; then
        python3 -c "
import json

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

for p in data.get('projects', []):
    if p['path'] == '$project_path':
        print(json.dumps(p))
        exit(0)
print('null')
"
    fi
}

# Enable/disable a project
# Args: $1 = project path, $2 = enabled (true/false)
set_project_enabled() {
    local project_path="$1"
    local enabled="$2"

    init_registry

    if command -v python3 &>/dev/null; then
        python3 -c "
import json

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

for p in data.get('projects', []):
    if p['path'] == '$project_path':
        p['enabled'] = $enabled
        break

with open('$REGISTRY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
}

# Count registered projects
count_projects() {
    init_registry
    list_projects | wc -l | tr -d ' '
}

# Clean up orphaned projects (directories that no longer exist)
cleanup_orphaned() {
    init_registry
    local removed=0

    for project_path in $(list_projects); do
        if [[ ! -d "$project_path" ]]; then
            unregister_project "$project_path"
            ((removed++))
        fi
    done

    echo "Removed $removed orphaned projects"
}
