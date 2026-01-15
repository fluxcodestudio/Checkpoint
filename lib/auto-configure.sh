#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Auto-Configuration Engine
# ==============================================================================
# Automatically discovers and configures projects with smart defaults.
# Only prompts when genuinely ambiguous.
#
# Philosophy:
#   - Opt-out, not opt-in (configure everything by default)
#   - Safe defaults (never backup remote/production databases)
#   - Minimal prompts (only ask when genuinely ambiguous)
#   - Transparent (show what was configured)
#   - Reversible (easy to change via dashboard)
# ==============================================================================

set -euo pipefail

# Load database detector if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ -f "$SCRIPT_DIR/database-detector.sh" ]]; then
    source "$SCRIPT_DIR/database-detector.sh"
fi

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Common project locations to scan
DEFAULT_PROJECT_DIRS=(
    "$HOME/Developer"
    "$HOME/Projects"
    "$HOME/Code"
    "$HOME/code"
    "$HOME/repos"
    "$HOME/Sites"
    "$HOME/sites"
    "$HOME/work"
    "$HOME/Work"
    "$HOME/src"
    "$HOME/git"
)

# Cloud sync folder detection
CLOUD_FOLDERS=(
    "$HOME/Dropbox"
    "$HOME/Google Drive"
    "$HOME/Library/CloudStorage"
    "$HOME/iCloud Drive"
    "$HOME/OneDrive"
)

# Project indicators (files that indicate a project root)
PROJECT_INDICATORS=(
    ".git"
    "package.json"
    "Cargo.toml"
    "go.mod"
    "requirements.txt"
    "setup.py"
    "pyproject.toml"
    "Gemfile"
    "composer.json"
    "pom.xml"
    "build.gradle"
    "Makefile"
    "CMakeLists.txt"
    ".project"
)

# Directories to skip during scanning
SKIP_DIRS=(
    "node_modules"
    ".git"
    "__pycache__"
    ".venv"
    "venv"
    "vendor"
    "build"
    "dist"
    "target"
    ".cache"
    ".npm"
    ".yarn"
)

# Default settings
DEFAULT_DB_RETENTION=30
DEFAULT_FILE_RETENTION=60
DEFAULT_BACKUP_INTERVAL=3600
MAX_PROJECT_SIZE_MB=5000  # Warn if project > 5GB

# ==============================================================================
# PROJECT DISCOVERY
# ==============================================================================

# Find all project directories
# Output: One project path per line
discover_projects() {
    local search_dirs=("${@:-${DEFAULT_PROJECT_DIRS[@]}}")
    local found_projects=()

    for base_dir in "${search_dirs[@]}"; do
        [[ ! -d "$base_dir" ]] && continue

        # Find directories containing project indicators
        while IFS= read -r -d '' indicator_path; do
            local project_dir
            project_dir=$(dirname "$indicator_path")

            # Skip if inside a skip directory
            local skip=false
            for skip_dir in "${SKIP_DIRS[@]}"; do
                if [[ "$project_dir" == *"/$skip_dir/"* ]] || [[ "$project_dir" == *"/$skip_dir" ]]; then
                    skip=true
                    break
                fi
            done
            [[ "$skip" == "true" ]] && continue

            # Resolve to real path and deduplicate
            local real_path
            real_path=$(cd "$project_dir" 2>/dev/null && pwd -P) || continue

            # Check if already found (avoid duplicates from symlinks)
            local already_found=false
            for found in "${found_projects[@]:-}"; do
                if [[ "$found" == "$real_path" ]]; then
                    already_found=true
                    break
                fi
            done

            if [[ "$already_found" == "false" ]]; then
                found_projects+=("$real_path")
                echo "$real_path"
            fi
        done < <(find "$base_dir" -maxdepth 4 -type f \( \
            -name "package.json" -o \
            -name "Cargo.toml" -o \
            -name "go.mod" -o \
            -name "requirements.txt" -o \
            -name "pyproject.toml" -o \
            -name "Gemfile" -o \
            -name "composer.json" \
        \) -print0 2>/dev/null)

        # Also find .git directories (handles projects without package managers)
        while IFS= read -r -d '' git_dir; do
            local project_dir
            project_dir=$(dirname "$git_dir")

            local real_path
            real_path=$(cd "$project_dir" 2>/dev/null && pwd -P) || continue

            local already_found=false
            for found in "${found_projects[@]:-}"; do
                if [[ "$found" == "$real_path" ]]; then
                    already_found=true
                    break
                fi
            done

            if [[ "$already_found" == "false" ]]; then
                found_projects+=("$real_path")
                echo "$real_path"
            fi
        done < <(find "$base_dir" -maxdepth 3 -type d -name ".git" -print0 2>/dev/null)
    done
}

# ==============================================================================
# PROJECT ANALYSIS
# ==============================================================================

# Analyze a project and output JSON-like config
# Args: $1 = project directory
# Output: Key-value pairs for configuration
analyze_project() {
    local project_dir="$1"
    local project_name
    project_name=$(basename "$project_dir")

    # Initialize analysis results
    local project_type="unknown"
    local has_git=false
    local db_type="none"
    local db_path=""
    local db_is_local=true
    local needs_input=false
    local needs_input_reason=""
    local project_size_mb=0
    local is_cloud_synced=false
    local cloud_provider=""

    # Check if git repo
    [[ -d "$project_dir/.git" ]] && has_git=true

    # Detect project type
    if [[ -f "$project_dir/package.json" ]]; then
        if grep -q '"next"' "$project_dir/package.json" 2>/dev/null; then
            project_type="nextjs"
        elif grep -q '"react"' "$project_dir/package.json" 2>/dev/null; then
            project_type="react"
        elif grep -q '"vue"' "$project_dir/package.json" 2>/dev/null; then
            project_type="vue"
        elif grep -q '"express"' "$project_dir/package.json" 2>/dev/null; then
            project_type="express"
        else
            project_type="nodejs"
        fi
    elif [[ -f "$project_dir/Cargo.toml" ]]; then
        project_type="rust"
    elif [[ -f "$project_dir/go.mod" ]]; then
        project_type="go"
    elif [[ -f "$project_dir/requirements.txt" ]] || [[ -f "$project_dir/pyproject.toml" ]]; then
        if [[ -f "$project_dir/manage.py" ]]; then
            project_type="django"
        elif [[ -f "$project_dir/app.py" ]] || [[ -f "$project_dir/wsgi.py" ]]; then
            project_type="flask"
        else
            project_type="python"
        fi
    elif [[ -f "$project_dir/Gemfile" ]]; then
        if [[ -f "$project_dir/config/routes.rb" ]]; then
            project_type="rails"
        else
            project_type="ruby"
        fi
    elif [[ -f "$project_dir/composer.json" ]]; then
        if [[ -d "$project_dir/artisan" ]] || grep -q "laravel" "$project_dir/composer.json" 2>/dev/null; then
            project_type="laravel"
        else
            project_type="php"
        fi
    fi

    # Detect database
    local detected_dbs=()

    # Check .env files for database URLs
    for env_file in "$project_dir/.env" "$project_dir/.env.local" "$project_dir/.env.development"; do
        [[ ! -f "$env_file" ]] && continue

        # SQLite
        if grep -qE "DATABASE_URL.*sqlite|DB_CONNECTION.*sqlite" "$env_file" 2>/dev/null; then
            local sqlite_path
            sqlite_path=$(grep -oE "sqlite:.*\.db|sqlite:.*\.sqlite" "$env_file" 2>/dev/null | sed 's/sqlite://' | head -1)
            if [[ -n "$sqlite_path" ]]; then
                detected_dbs+=("sqlite|$sqlite_path")
            fi
        fi

        # PostgreSQL
        if grep -qE "DATABASE_URL.*postgres|DB_CONNECTION.*pgsql|POSTGRES_" "$env_file" 2>/dev/null; then
            local pg_host
            pg_host=$(grep -oE "(localhost|127\.0\.0\.1|postgres://localhost)" "$env_file" 2>/dev/null | head -1)
            if [[ -n "$pg_host" ]]; then
                detected_dbs+=("postgresql|local")
            else
                detected_dbs+=("postgresql|remote")
            fi
        fi

        # MySQL
        if grep -qE "DATABASE_URL.*mysql|DB_CONNECTION.*mysql|MYSQL_" "$env_file" 2>/dev/null; then
            local mysql_host
            mysql_host=$(grep -oE "(localhost|127\.0\.0\.1|mysql://localhost)" "$env_file" 2>/dev/null | head -1)
            if [[ -n "$mysql_host" ]]; then
                detected_dbs+=("mysql|local")
            else
                detected_dbs+=("mysql|remote")
            fi
        fi

        # MongoDB
        if grep -qE "MONGO|mongodb://" "$env_file" 2>/dev/null; then
            local mongo_host
            mongo_host=$(grep -oE "(localhost|127\.0\.0\.1|mongodb://localhost)" "$env_file" 2>/dev/null | head -1)
            if [[ -n "$mongo_host" ]]; then
                detected_dbs+=("mongodb|local")
            else
                detected_dbs+=("mongodb|remote")
            fi
        fi
    done

    # Check for SQLite files directly
    local sqlite_files
    sqlite_files=$(find "$project_dir" -maxdepth 3 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) \
        ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/vendor/*" 2>/dev/null | head -5)

    if [[ -n "$sqlite_files" ]]; then
        while IFS= read -r db_file; do
            [[ -z "$db_file" ]] && continue
            # Verify it's actually a SQLite file
            if file "$db_file" 2>/dev/null | grep -q "SQLite"; then
                detected_dbs+=("sqlite|$db_file")
            fi
        done <<< "$sqlite_files"
    fi

    # Deduplicate and determine primary database
    local unique_dbs=()
    local seen_types=""
    for db in "${detected_dbs[@]:-}"; do
        local db_t="${db%%|*}"
        if [[ "$seen_types" != *"$db_t"* ]]; then
            unique_dbs+=("$db")
            seen_types="$seen_types $db_t"
        fi
    done

    # Determine database configuration
    local local_db_count=0
    local remote_db_count=0

    for db in "${unique_dbs[@]:-}"; do
        local db_t="${db%%|*}"
        local db_loc="${db#*|}"

        if [[ "$db_loc" == "remote" ]]; then
            ((remote_db_count++)) || true
        else
            ((local_db_count++)) || true
            # Set as primary if first local DB
            if [[ "$db_type" == "none" ]]; then
                db_type="$db_t"
                if [[ "$db_t" == "sqlite" ]]; then
                    db_path="$db_loc"
                fi
            fi
        fi
    done

    # Flag if multiple local databases (needs user input)
    if [[ $local_db_count -gt 1 ]]; then
        needs_input=true
        needs_input_reason="multiple_databases"
    fi

    # Calculate project size
    project_size_mb=$(du -sm "$project_dir" 2>/dev/null | cut -f1 || echo "0")

    if [[ $project_size_mb -gt $MAX_PROJECT_SIZE_MB ]]; then
        needs_input=true
        needs_input_reason="large_project"
    fi

    # Check if in cloud-synced folder
    for cloud_folder in "${CLOUD_FOLDERS[@]}"; do
        if [[ "$project_dir" == "$cloud_folder"* ]]; then
            is_cloud_synced=true
            cloud_provider=$(basename "$cloud_folder")
            break
        fi
    done

    # Output results
    cat <<EOF
PROJECT_DIR="$project_dir"
PROJECT_NAME="$project_name"
PROJECT_TYPE="$project_type"
HAS_GIT=$has_git
DB_TYPE="$db_type"
DB_PATH="$db_path"
DB_IS_LOCAL=$db_is_local
PROJECT_SIZE_MB=$project_size_mb
IS_CLOUD_SYNCED=$is_cloud_synced
CLOUD_PROVIDER="$cloud_provider"
NEEDS_INPUT=$needs_input
NEEDS_INPUT_REASON="$needs_input_reason"
LOCAL_DB_COUNT=$local_db_count
REMOTE_DB_COUNT=$remote_db_count
EOF
}

# ==============================================================================
# CONFIGURATION GENERATION
# ==============================================================================

# Generate a backup config for a project
# Args: $1 = project directory, $2 = output file (optional, defaults to PROJECT/.backup-config.sh)
generate_config() {
    local project_dir="$1"
    local output_file="${2:-$project_dir/.backup-config.sh}"
    local project_name
    project_name=$(basename "$project_dir")

    # Analyze project
    local analysis
    analysis=$(analyze_project "$project_dir")
    eval "$analysis"

    # Generate config file
    cat > "$output_file" << CONFIGEOF
#!/usr/bin/env bash
# Checkpoint - Project Configuration
# Auto-generated on $(date)
# Project: $PROJECT_NAME
# Type: $PROJECT_TYPE

# ==============================================================================
# PROJECT SETTINGS
# ==============================================================================

PROJECT_DIR="$PROJECT_DIR"
PROJECT_NAME="$PROJECT_NAME"

# ==============================================================================
# BACKUP LOCATIONS
# ==============================================================================

BACKUP_DIR="\$PROJECT_DIR/backups"
DATABASE_DIR="\$BACKUP_DIR/databases"
FILES_DIR="\$BACKUP_DIR/files"
ARCHIVED_DIR="\$BACKUP_DIR/archived"

# ==============================================================================
# DATABASE
# ==============================================================================

DB_TYPE="$DB_TYPE"
DB_PATH="$DB_PATH"

# ==============================================================================
# RETENTION (days)
# ==============================================================================

DB_RETENTION_DAYS=$DEFAULT_DB_RETENTION
FILE_RETENTION_DAYS=$DEFAULT_FILE_RETENTION

# ==============================================================================
# AUTOMATION
# ==============================================================================

BACKUP_INTERVAL=$DEFAULT_BACKUP_INTERVAL
SESSION_IDLE_THRESHOLD=600

# ==============================================================================
# FILE BACKUP OPTIONS
# ==============================================================================

BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=true
BACKUP_LOCAL_NOTES=true
BACKUP_LOCAL_DATABASES=true

# ==============================================================================
# OPTIONAL FEATURES
# ==============================================================================

DRIVE_VERIFICATION_ENABLED=false
AUTO_COMMIT_ENABLED=false
NOTIFICATIONS_ENABLED=true

# ==============================================================================
# STATE & LOGGING
# ==============================================================================

STATE_DIR="\$HOME/.checkpoint/state/\$PROJECT_NAME"
LOG_FILE="\$BACKUP_DIR/backup.log"
FALLBACK_LOG="\$HOME/.checkpoint/logs/\$PROJECT_NAME.log"
CONFIGEOF

    chmod +x "$output_file"
    echo "$output_file"
}

# ==============================================================================
# PROJECT REGISTRATION
# ==============================================================================

# Register a project in the global registry
# Args: $1 = project directory
register_project() {
    local project_dir="$1"
    local project_name
    project_name=$(basename "$project_dir")
    local registry="$HOME/.config/checkpoint/projects.json"

    # Ensure registry directory exists
    mkdir -p "$(dirname "$registry")"

    # Initialize registry if not exists
    if [[ ! -f "$registry" ]]; then
        echo '{"version": 1, "projects": []}' > "$registry"
    fi

    # Check if already registered
    if grep -q "\"path\": \"$project_dir\"" "$registry" 2>/dev/null; then
        return 0  # Already registered
    fi

    # Add project to registry using Python (more reliable JSON handling)
    if command -v python3 &>/dev/null; then
        python3 << PYEOF
import json
import os
from datetime import datetime

registry_path = os.path.expanduser("$registry")
project_dir = "$project_dir"
project_name = "$project_name"

with open(registry_path, 'r') as f:
    data = json.load(f)

# Add new project
data['projects'].append({
    'name': project_name,
    'path': project_dir,
    'added': datetime.now().isoformat(),
    'enabled': True
})

with open(registry_path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
    else
        # Fallback: simple append (less elegant but works)
        local temp_file
        temp_file=$(mktemp)
        sed 's/\]$//' "$registry" > "$temp_file"
        echo ",{\"name\":\"$project_name\",\"path\":\"$project_dir\",\"enabled\":true}]}" >> "$temp_file"
        mv "$temp_file" "$registry"
    fi
}

# ==============================================================================
# BATCH AUTO-CONFIGURATION
# ==============================================================================

# Auto-configure all discovered projects
# Returns: Number of projects configured, number needing input
auto_configure_all() {
    local configured=0
    local needs_input=0
    local skipped=0
    local projects_needing_input=()

    echo "Discovering projects..."

    local projects
    projects=$(discover_projects)

    if [[ -z "$projects" ]]; then
        echo "No projects found in default locations."
        echo ""
        echo "Default search paths:"
        for dir in "${DEFAULT_PROJECT_DIRS[@]}"; do
            echo "  • $dir"
        done
        return 1
    fi

    local total
    total=$(echo "$projects" | wc -l | tr -d ' ')
    echo "Found $total potential projects."
    echo ""

    while IFS= read -r project_dir; do
        [[ -z "$project_dir" ]] && continue

        local project_name
        project_name=$(basename "$project_dir")

        # Skip if already configured
        if [[ -f "$project_dir/.backup-config.sh" ]]; then
            echo "  ⏭  $project_name (already configured)"
            ((skipped++)) || true
            continue
        fi

        # Analyze project
        local analysis
        analysis=$(analyze_project "$project_dir")
        eval "$analysis"

        if [[ "$NEEDS_INPUT" == "true" ]]; then
            echo "  ⚠  $project_name (needs input: $NEEDS_INPUT_REASON)"
            projects_needing_input+=("$project_dir|$NEEDS_INPUT_REASON")
            ((needs_input++)) || true
        else
            # Auto-configure
            generate_config "$project_dir" >/dev/null
            register_project "$project_dir"

            local db_info=""
            [[ "$DB_TYPE" != "none" ]] && db_info=" + $DB_TYPE"
            echo "  ✓  $project_name ($PROJECT_TYPE$db_info)"
            ((configured++)) || true
        fi
    done <<< "$projects"

    echo ""
    echo "═══════════════════════════════════════════════"
    echo "Auto-Configuration Summary"
    echo "═══════════════════════════════════════════════"
    echo "  Configured: $configured"
    echo "  Skipped:    $skipped (already configured)"
    echo "  Need input: $needs_input"
    echo ""

    # Handle projects needing input
    if [[ $needs_input -gt 0 ]]; then
        echo "Projects requiring configuration:"
        echo ""

        for entry in "${projects_needing_input[@]}"; do
            local proj_dir="${entry%%|*}"
            local reason="${entry#*|}"
            local proj_name
            proj_name=$(basename "$proj_dir")

            case "$reason" in
                multiple_databases)
                    handle_multiple_databases "$proj_dir"
                    ;;
                large_project)
                    handle_large_project "$proj_dir"
                    ;;
                *)
                    echo "  $proj_name: Unknown issue ($reason)"
                    ;;
            esac
        done
    fi

    # Export for caller
    export AUTO_CONFIG_CONFIGURED=$configured
    export AUTO_CONFIG_NEEDS_INPUT=$needs_input
    export AUTO_CONFIG_SKIPPED=$skipped
}

# ==============================================================================
# INTERACTIVE HANDLERS (for edge cases)
# ==============================================================================

# Handle projects with multiple databases
handle_multiple_databases() {
    local project_dir="$1"
    local project_name
    project_name=$(basename "$project_dir")

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $project_name - Multiple Databases Detected"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Find all databases
    local dbs=()
    local idx=1

    # Check for SQLite files
    while IFS= read -r db_file; do
        [[ -z "$db_file" ]] && continue
        if file "$db_file" 2>/dev/null | grep -q "SQLite"; then
            local rel_path="${db_file#$project_dir/}"
            dbs+=("sqlite|$db_file|$rel_path")
            echo "  [$idx] SQLite: $rel_path"
            ((idx++)) || true
        fi
    done < <(find "$project_dir" -maxdepth 3 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) \
        ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null)

    # Check .env for other databases
    if grep -qE "postgres|pgsql" "$project_dir/.env" 2>/dev/null; then
        dbs+=("postgresql|env|PostgreSQL (from .env)")
        echo "  [$idx] PostgreSQL (from .env)"
        ((idx++)) || true
    fi

    if grep -qE "mysql" "$project_dir/.env" 2>/dev/null; then
        dbs+=("mysql|env|MySQL (from .env)")
        echo "  [$idx] MySQL (from .env)"
        ((idx++)) || true
    fi

    echo "  [A] All local databases"
    echo "  [N] None (skip database backup)"
    echo ""

    read -p "  Which database(s) to backup? [1]: " choice
    choice=${choice:-1}

    local db_type="none"
    local db_path=""

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        # For "all", use the first SQLite found (we'll add multi-db support later)
        for db in "${dbs[@]}"; do
            local t="${db%%|*}"
            if [[ "$t" == "sqlite" ]]; then
                db_type="sqlite"
                db_path=$(echo "$db" | cut -d'|' -f2)
                break
            fi
        done
    elif [[ "$choice" =~ ^[Nn]$ ]]; then
        db_type="none"
        db_path=""
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -le ${#dbs[@]} ]]; then
        local selected="${dbs[$((choice-1))]}"
        db_type="${selected%%|*}"
        db_path=$(echo "$selected" | cut -d'|' -f2)
    fi

    # Generate config with selected database
    local config_file="$project_dir/.backup-config.sh"
    generate_config "$project_dir" "$config_file"

    # Update database settings if different from auto-detected
    if [[ "$db_type" != "none" ]] && [[ -n "$db_path" ]] && [[ "$db_path" != "env" ]]; then
        sed -i '' "s|^DB_TYPE=.*|DB_TYPE=\"$db_type\"|" "$config_file"
        sed -i '' "s|^DB_PATH=.*|DB_PATH=\"$db_path\"|" "$config_file"
    fi

    register_project "$project_dir"
    echo "  ✓ Configured with $db_type"
    echo ""
}

# Handle large projects
handle_large_project() {
    local project_dir="$1"
    local project_name
    project_name=$(basename "$project_dir")
    local size_mb
    size_mb=$(du -sm "$project_dir" 2>/dev/null | cut -f1)
    local size_gb
    size_gb=$(echo "scale=1; $size_mb / 1024" | bc)

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $project_name - Large Project (${size_gb}GB)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  This project is larger than 5GB."
    echo "  Large file backups may be slow and use significant disk space."
    echo ""
    echo "  [1] Backup git-tracked files only (recommended)"
    echo "  [2] Backup all files (may be slow)"
    echo "  [S] Skip this project"
    echo ""

    read -p "  Choice [1]: " choice
    choice=${choice:-1}

    if [[ "$choice" =~ ^[Ss]$ ]]; then
        echo "  ⏭  Skipped"
        return 0
    fi

    generate_config "$project_dir" >/dev/null

    if [[ "$choice" == "1" ]]; then
        # Add large file exclusion to config
        echo "" >> "$project_dir/.backup-config.sh"
        echo "# Large project - git-tracked files only" >> "$project_dir/.backup-config.sh"
        echo "BACKUP_GIT_ONLY=true" >> "$project_dir/.backup-config.sh"
    fi

    register_project "$project_dir"
    echo "  ✓ Configured"
    echo ""
}

# ==============================================================================
# INSTALL DAEMON FOR PROJECT
# ==============================================================================

# Install LaunchAgent for a project
# Args: $1 = project directory
install_project_daemon() {
    local project_dir="$1"
    local project_name
    project_name=$(basename "$project_dir")
    local safe_name
    safe_name=$(echo "$project_name" | tr ' ' '_' | tr -cd '[:alnum:]_-')

    local plist_file="$HOME/Library/LaunchAgents/com.checkpoint.backup.${safe_name}.plist"
    local daemon_script

    # Find daemon script
    if [[ -f "$HOME/.local/lib/checkpoint/bin/backup-daemon.sh" ]]; then
        daemon_script="$HOME/.local/lib/checkpoint/bin/backup-daemon.sh"
    elif [[ -f "/usr/local/lib/checkpoint/bin/backup-daemon.sh" ]]; then
        daemon_script="/usr/local/lib/checkpoint/bin/backup-daemon.sh"
    else
        echo "Warning: Daemon script not found, skipping LaunchAgent for $project_name"
        return 1
    fi

    # Create log directory
    mkdir -p "$HOME/.checkpoint/logs"

    cat > "$plist_file" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.checkpoint.backup.${safe_name}</string>
    <key>ProgramArguments</key>
    <array>
        <string>$daemon_script</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$project_dir</string>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.checkpoint/logs/${safe_name}.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.checkpoint/logs/${safe_name}.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$HOME/.local/bin</string>
    </dict>
</dict>
</plist>
PLISTEOF

    # Load the agent
    launchctl unload "$plist_file" 2>/dev/null || true
    launchctl load -w "$plist_file" 2>/dev/null

    return 0
}

# ==============================================================================
# MAIN (for testing)
# ==============================================================================

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    case "${1:-}" in
        discover)
            discover_projects "${@:2}"
            ;;
        analyze)
            analyze_project "${2:-.}"
            ;;
        configure)
            generate_config "${2:-.}"
            ;;
        auto)
            auto_configure_all
            ;;
        *)
            echo "Usage: $0 {discover|analyze|configure|auto} [args]"
            echo ""
            echo "Commands:"
            echo "  discover [dirs...]  Find all projects"
            echo "  analyze [dir]       Analyze a project"
            echo "  configure [dir]     Generate config for a project"
            echo "  auto                Auto-configure all projects"
            ;;
    esac
fi
