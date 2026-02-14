#!/usr/bin/env bash
# Checkpoint - Installation Script
# Sets up backup system for any project

set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="${1:-$PWD}"

# Source cross-platform daemon manager
source "$PACKAGE_DIR/lib/platform/daemon-manager.sh"

echo "═══════════════════════════════════════════════"
echo "Checkpoint - Installation"
echo "═══════════════════════════════════════════════"
echo ""

# ==============================================================================
# INSTALLATION MODE SELECTION
# ==============================================================================

echo "Choose installation mode:"
echo ""
echo "  [1] Global (recommended)"
echo "      • Install once, use in all projects"
echo "      • Commands available system-wide (backup-now, backup-status, etc.)"
echo "      • Easy updates (git pull, reinstall)"
echo "      • Requires: write access to /usr/local/bin or ~/.local/bin"
echo ""
echo "  [2] Per-Project"
echo "      • Self-contained in this project only"
echo "      • No system modifications needed"
echo "      • Portable (copy project = copy backup system)"
echo "      • Good for: shared systems, containers"
echo ""
read -p "Choose mode (1/2) [1]: " install_mode
install_mode=${install_mode:-1}

if [[ "$install_mode" == "1" ]]; then
    echo ""
    echo "Launching global installer..."
    exec "$PACKAGE_DIR/bin/install-global.sh"
fi

# Continue with per-project installation
echo ""
echo "═══════════════════════════════════════════════"
echo "Per-Project Installation"
echo "═══════════════════════════════════════════════"
echo ""
echo "Package location: $PACKAGE_DIR"
echo "Project location: $PROJECT_DIR"
echo ""

# ==============================================================================
# DEPENDENCY CHECK
# ==============================================================================

echo "Checking dependencies..."
echo ""

MISSING_DEPS=()

# Check required tools
if ! command -v bash &> /dev/null; then
    MISSING_DEPS+=("bash")
fi

if ! command -v git &> /dev/null; then
    MISSING_DEPS+=("git")
fi

if ! command -v gzip &> /dev/null; then
    MISSING_DEPS+=("gzip")
fi

# Check optional but recommended
WARNINGS=()

if ! command -v sqlite3 &> /dev/null; then
    WARNINGS+=("sqlite3 not found - database backups will not work")
fi

_init_sys="$(detect_init_system)"
if [ "$_init_sys" = "launchd" ] && ! command -v launchctl &> /dev/null; then
    WARNINGS+=("launchctl not found - automatic backups may not work")
elif [ "$_init_sys" = "systemd" ] && ! command -v systemctl &> /dev/null; then
    WARNINGS+=("systemctl not found - automatic backups may not work")
fi

# Report missing critical dependencies
if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "❌ Missing required dependencies:"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "   - $dep"
    done
    echo ""
    echo "Please install missing dependencies before running installer."
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "On macOS with Homebrew:"
        echo "  brew install ${MISSING_DEPS[*]}"
        echo ""
        echo "Don't have Homebrew? Install it from: https://brew.sh"
    fi
    exit 1
fi

# Report warnings
if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "⚠️  Warnings:"
    for warning in "${WARNINGS[@]}"; do
        echo "   - $warning"
    done
    echo ""
    read -p "Continue anyway? (y/n): " continue_install
    if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo ""
fi

echo "✅ All required dependencies found"
echo ""

# ==============================================================================
# CHECK BASH VERSION (for TUI dashboard features)
# ==============================================================================

# Load dependency manager
source "$PACKAGE_DIR/lib/dependency-manager.sh"

if ! check_bash_version; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    # Offer to upgrade bash (non-blocking)
    require_bash || true  # Continue even if user declines
    echo ""
fi

# ==============================================================================
# CHECK FOR DIALOG (for best dashboard experience)
# ==============================================================================

if ! check_dialog; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    # Offer to install dialog (non-blocking)
    require_dialog || true  # Continue even if user declines
    echo ""
fi

# ==============================================================================
# PHASE 1: GATHER ALL CONFIGURATION (No installation yet!)
# ==============================================================================

echo "══════════════════════════════════════════════════════════"
echo "  Checkpoint Setup - Quick Configuration"
echo "══════════════════════════════════════════════════════════"
echo ""

# Project name (auto-detected)
PROJECT_NAME=$(basename "$PROJECT_DIR")
echo "Project: $PROJECT_NAME"
echo ""

# Load database detector
source "$PACKAGE_DIR/lib/database-detector.sh" 2>/dev/null || true

# === Question 1: Database Backups ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  1/4: Auto-Detecting Databases"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

detected_dbs=$(detect_databases "$PROJECT_DIR" 2>/dev/null || echo "")

if [ -n "$detected_dbs" ]; then
    echo "$detected_dbs" | while IFS='|' read -r db_type rest; do
        case "$db_type" in
            sqlite)
                db_name=$(basename "$rest")
                echo "  ✓ SQLite: $db_name"
                ;;
            postgresql)
                IFS='|' read -r host port database user is_local <<< "$rest"
                if [[ "$is_local" == "true" ]]; then
                    echo "  ✓ PostgreSQL: $database (local)"
                else
                    echo "  ⊘ PostgreSQL: $database (remote)"
                fi
                ;;
            mysql)
                IFS='|' read -r host port database user is_local <<< "$rest"
                if [[ "$is_local" == "true" ]]; then
                    echo "  ✓ MySQL: $database (local)"
                else
                    echo "  ⊘ MySQL: $database (remote)"
                fi
                ;;
            mongodb)
                IFS='|' read -r host port database user is_local <<< "$rest"
                if [[ "$is_local" == "true" ]]; then
                    echo "  ✓ MongoDB: $database (local)"
                else
                    echo "  ⊘ MongoDB: $database (remote)"
                fi
                ;;
        esac
    done
    echo ""
    read -p "  Back up local databases? (Y/n): " backup_dbs_choice
    backup_dbs_choice=${backup_dbs_choice:-y}
    ENABLE_DATABASE_BACKUP=true
    if [[ ! "$backup_dbs_choice" =~ ^[Yy]?$ ]]; then
        ENABLE_DATABASE_BACKUP=false
    fi
else
    echo "  No databases detected"
    ENABLE_DATABASE_BACKUP=false
fi
echo ""

# === Question 2: Cloud Backup ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  2/4: Cloud Backup (Optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Which cloud service do you use?"
echo "    1) Dropbox"
echo "    2) iCloud Drive"
echo "    3) Google Drive"
echo "    4) OneDrive"
echo "    5) Box"
echo "    6) pCloud"
echo "    7) MEGA"
echo "    8) Other (enter path)"
echo "    9) None / Skip"
echo ""
read -p "  Select [1-9]: " cloud_choice
cloud_choice=${cloud_choice:-9}

CLOUD_FOLDER_PATH=""
wants_cloud="n"

# Function to scan for cloud folder
scan_for_cloud_folder() {
    local folder_name="$1"
    local found_paths=()

    # Check home directory
    [[ -d "$HOME/$folder_name" ]] && found_paths+=("$HOME/$folder_name")

    # Check all mounted volumes
    for vol in /Volumes/*; do
        [[ -d "$vol/$folder_name" ]] && found_paths+=("$vol/$folder_name")
    done

    # Return first found path
    if [[ ${#found_paths[@]} -gt 0 ]]; then
        echo "${found_paths[0]}"
    fi
}

# Map service name to rclone provider name
get_rclone_provider_name() {
    case "$1" in
        dropbox) echo "dropbox" ;;
        google|gdrive) echo "drive" ;;
        onedrive) echo "onedrive" ;;
        box) echo "box" ;;
        pcloud) echo "pcloud" ;;
        mega) echo "mega" ;;
        *) echo "$1" ;;
    esac
}

# Setup rclone for a specific provider
# Returns 0 on success, 1 on failure
# Sets: CLOUD_RCLONE_REMOTE, CLOUD_RCLONE_ENABLED
setup_rclone_for_provider() {
    local service_name="$1"
    local provider=$(get_rclone_provider_name "$service_name")
    local remote_name="checkpoint-${service_name}"

    echo ""
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Setting up direct cloud upload via rclone"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check if rclone is installed
    if ! command -v rclone &>/dev/null; then
        echo "  rclone is not installed."
        echo "  rclone enables direct cloud uploads without desktop apps."
        echo ""

        # Check if we can install it
        if command -v brew &>/dev/null; then
            read -p "  Install rclone via Homebrew? (Y/n): " install_rclone
            install_rclone=${install_rclone:-y}

            if [[ "$install_rclone" =~ ^[Yy]$ ]]; then
                echo "  Installing rclone..."
                if brew install rclone 2>/dev/null; then
                    echo "  ✓ rclone installed successfully"
                else
                    echo "  ✗ Failed to install rclone"
                    echo "  Please install manually: https://rclone.org/install/"
                    return 1
                fi
            else
                echo "  Skipping rclone setup"
                return 1
            fi
        else
            echo "  Please install rclone manually:"
            echo "    • macOS: brew install rclone"
            echo "    • Or visit: https://rclone.org/install/"
            echo ""
            read -p "  Press Enter after installing rclone (or 's' to skip): " wait_install
            if [[ "$wait_install" == "s" ]]; then
                return 1
            fi
            if ! command -v rclone &>/dev/null; then
                echo "  ✗ rclone still not found"
                return 1
            fi
        fi
    else
        echo "  ✓ rclone is installed"
    fi

    echo ""

    # Check for existing remote
    if rclone listremotes 2>/dev/null | grep -q "^${remote_name}:$"; then
        echo "  ✓ Found existing rclone remote: $remote_name"
        read -p "  Use this remote? (Y/n): " use_existing
        use_existing=${use_existing:-y}
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            # Test the connection
            echo "  Testing connection..."
            if rclone lsd "${remote_name}:" &>/dev/null; then
                echo "  ✓ Connection successful!"
                CLOUD_RCLONE_REMOTE="$remote_name"
                CLOUD_RCLONE_ENABLED=true
                CLOUD_RCLONE_PATH="Backups/Checkpoint"
                wants_cloud="y"
                return 0
            else
                echo "  ✗ Connection failed. Let's reconfigure."
            fi
        fi
    fi

    # Configure new remote
    echo "  Configuring rclone for ${service_name}..."
    echo ""
    echo "  This will open an interactive setup."
    echo "  You'll need to authorize access to your ${service_name} account."
    echo ""
    read -p "  Continue with setup? (Y/n): " do_config
    do_config=${do_config:-y}

    if [[ ! "$do_config" =~ ^[Yy]$ ]]; then
        echo "  Skipping rclone setup"
        return 1
    fi

    # Run rclone config
    echo ""
    echo "  Starting rclone configuration..."
    echo "  ─────────────────────────────────────────────"

    if rclone config create "$remote_name" "$provider" 2>/dev/null; then
        echo "  ─────────────────────────────────────────────"
        echo ""

        # Test connection
        echo "  Testing connection..."
        if rclone lsd "${remote_name}:" &>/dev/null; then
            echo "  ✓ Connection successful!"
            CLOUD_RCLONE_REMOTE="$remote_name"
            CLOUD_RCLONE_ENABLED=true
            CLOUD_RCLONE_PATH="Backups/Checkpoint"
            wants_cloud="y"
            return 0
        else
            echo "  ✗ Connection test failed"
            echo "  You may need to run 'rclone config' manually to complete setup"
            return 1
        fi
    else
        echo "  ─────────────────────────────────────────────"
        echo ""
        echo "  ✗ rclone configuration failed"
        echo "  Try running 'rclone config' manually"
        return 1
    fi
}

# Show fallback menu when cloud folder not found
# Args: $1 = service name, $2 = supports_rclone (true/false)
show_cloud_fallback_menu() {
    local service_name="$1"
    local supports_rclone="${2:-true}"

    echo ""
    echo "  What would you like to do?"
    if [[ "$supports_rclone" == "true" ]]; then
        echo "    1) Enter folder path manually"
        echo "    2) Setup direct upload via rclone (no desktop app needed)"
        echo "    3) Skip cloud backup"
        echo ""
        read -p "  Select [1-3]: " fallback_choice
        fallback_choice=${fallback_choice:-3}

        case "$fallback_choice" in
            1)
                read -p "  Enter ${service_name} folder path: " manual_path
                if [[ -n "$manual_path" && -d "$manual_path" ]]; then
                    CLOUD_FOLDER_PATH="$manual_path/Backups/Checkpoint"
                    wants_cloud="y"
                    echo "  ✓ Using: $CLOUD_FOLDER_PATH"
                else
                    echo "  ✗ Invalid path or directory not found"
                fi
                ;;
            2)
                setup_rclone_for_provider "$service_name"
                ;;
            *)
                echo "  Skipping cloud backup"
                ;;
        esac
    else
        echo "    1) Enter folder path manually"
        echo "    2) Skip cloud backup"
        echo ""
        echo "  Note: ${service_name} doesn't support direct upload via rclone."
        echo ""
        read -p "  Select [1-2]: " fallback_choice
        fallback_choice=${fallback_choice:-2}

        case "$fallback_choice" in
            1)
                read -p "  Enter ${service_name} folder path: " manual_path
                if [[ -n "$manual_path" && -d "$manual_path" ]]; then
                    CLOUD_FOLDER_PATH="$manual_path/Backups/Checkpoint"
                    wants_cloud="y"
                    echo "  ✓ Using: $CLOUD_FOLDER_PATH"
                else
                    echo "  ✗ Invalid path or directory not found"
                fi
                ;;
            *)
                echo "  Skipping cloud backup"
                ;;
        esac
    fi
}

# Initialize rclone variables
CLOUD_RCLONE_ENABLED=false
CLOUD_RCLONE_REMOTE=""
CLOUD_RCLONE_PATH=""

case "$cloud_choice" in
    1) # Dropbox
        echo ""
        echo "  Scanning for Dropbox folder..."
        detected_path=$(scan_for_cloud_folder "Dropbox")
        if [[ -n "$detected_path" ]]; then
            echo "  ✓ Found: $detected_path"
            read -p "  Use this location? (Y/n): " use_detected
            use_detected=${use_detected:-y}
            if [[ "$use_detected" =~ ^[Yy]$ ]]; then
                CLOUD_FOLDER_PATH="$detected_path/Backups/Checkpoint"
                wants_cloud="y"
            else
                show_cloud_fallback_menu "dropbox" "true"
            fi
        else
            echo "  ✗ Dropbox folder not found"
            show_cloud_fallback_menu "dropbox" "true"
        fi
        ;;
    2) # iCloud Drive
        echo ""
        ICLOUD_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
        if [[ -d "$ICLOUD_PATH" ]]; then
            echo "  ✓ Found: iCloud Drive"
            read -p "  Use this location? (Y/n): " use_detected
            use_detected=${use_detected:-y}
            if [[ "$use_detected" =~ ^[Yy]$ ]]; then
                CLOUD_FOLDER_PATH="$ICLOUD_PATH/Backups/Checkpoint"
                wants_cloud="y"
            else
                show_cloud_fallback_menu "iCloud" "false"
            fi
        else
            echo "  ✗ iCloud Drive not found"
            show_cloud_fallback_menu "iCloud" "false"
        fi
        ;;
    3) # Google Drive
        echo ""
        echo "  Scanning for Google Drive folder..."
        detected_path=""
        # Check CloudStorage location (newer)
        for gd in "$HOME/Library/CloudStorage"/GoogleDrive-*; do
            if [[ -d "$gd" ]]; then
                detected_path="$gd"
                break
            fi
        done
        # Check legacy location
        if [[ -z "$detected_path" ]]; then
            detected_path=$(scan_for_cloud_folder "Google Drive")
        fi

        if [[ -n "$detected_path" ]]; then
            echo "  ✓ Found: $detected_path"
            read -p "  Use this location? (Y/n): " use_detected
            use_detected=${use_detected:-y}
            if [[ "$use_detected" =~ ^[Yy]$ ]]; then
                CLOUD_FOLDER_PATH="$detected_path/Backups/Checkpoint"
                wants_cloud="y"
            else
                show_cloud_fallback_menu "google" "true"
            fi
        else
            echo "  ✗ Google Drive not found"
            show_cloud_fallback_menu "google" "true"
        fi
        ;;
    4) # OneDrive
        echo ""
        echo "  Scanning for OneDrive folder..."
        detected_path=""
        for od in "$HOME/Library/CloudStorage"/OneDrive-*; do
            if [[ -d "$od" ]]; then
                detected_path="$od"
                break
            fi
        done

        if [[ -n "$detected_path" ]]; then
            echo "  ✓ Found: $detected_path"
            read -p "  Use this location? (Y/n): " use_detected
            use_detected=${use_detected:-y}
            if [[ "$use_detected" =~ ^[Yy]$ ]]; then
                CLOUD_FOLDER_PATH="$detected_path/Backups/Checkpoint"
                wants_cloud="y"
            else
                show_cloud_fallback_menu "onedrive" "true"
            fi
        else
            echo "  ✗ OneDrive not found"
            show_cloud_fallback_menu "onedrive" "true"
        fi
        ;;
    5) # Box
        echo ""
        echo "  Scanning for Box folder..."
        detected_path=""
        # Check CloudStorage location (newer macOS)
        for box in "$HOME/Library/CloudStorage"/Box-*; do
            if [[ -d "$box" ]]; then
                detected_path="$box"
                break
            fi
        done
        # Check legacy locations
        if [[ -z "$detected_path" ]]; then
            detected_path=$(scan_for_cloud_folder "Box")
        fi
        if [[ -z "$detected_path" ]] && [[ -d "$HOME/Box Sync" ]]; then
            detected_path="$HOME/Box Sync"
        fi

        if [[ -n "$detected_path" ]]; then
            echo "  ✓ Found: $detected_path"
            read -p "  Use this location? (Y/n): " use_detected
            use_detected=${use_detected:-y}
            if [[ "$use_detected" =~ ^[Yy]$ ]]; then
                CLOUD_FOLDER_PATH="$detected_path/Backups/Checkpoint"
                wants_cloud="y"
            else
                show_cloud_fallback_menu "box" "true"
            fi
        else
            echo "  ✗ Box folder not found"
            show_cloud_fallback_menu "box" "true"
        fi
        ;;
    6) # pCloud
        echo ""
        echo "  Scanning for pCloud folder..."
        detected_path=""
        # Check common pCloud locations
        if [[ -d "$HOME/pCloud Drive" ]]; then
            detected_path="$HOME/pCloud Drive"
        elif [[ -d "$HOME/pCloudDrive" ]]; then
            detected_path="$HOME/pCloudDrive"
        else
            detected_path=$(scan_for_cloud_folder "pCloud Drive")
            if [[ -z "$detected_path" ]]; then
                detected_path=$(scan_for_cloud_folder "pCloudDrive")
            fi
        fi

        if [[ -n "$detected_path" ]]; then
            echo "  ✓ Found: $detected_path"
            read -p "  Use this location? (Y/n): " use_detected
            use_detected=${use_detected:-y}
            if [[ "$use_detected" =~ ^[Yy]$ ]]; then
                CLOUD_FOLDER_PATH="$detected_path/Backups/Checkpoint"
                wants_cloud="y"
            else
                show_cloud_fallback_menu "pcloud" "true"
            fi
        else
            echo "  ✗ pCloud folder not found"
            show_cloud_fallback_menu "pcloud" "true"
        fi
        ;;
    7) # MEGA
        echo ""
        echo "  Scanning for MEGA folder..."
        detected_path=""
        # Check common MEGA sync locations
        if [[ -d "$HOME/MEGA" ]]; then
            detected_path="$HOME/MEGA"
        elif [[ -d "$HOME/MEGAsync" ]]; then
            detected_path="$HOME/MEGAsync"
        else
            detected_path=$(scan_for_cloud_folder "MEGA")
            if [[ -z "$detected_path" ]]; then
                detected_path=$(scan_for_cloud_folder "MEGAsync")
            fi
        fi

        if [[ -n "$detected_path" ]]; then
            echo "  ✓ Found: $detected_path"
            read -p "  Use this location? (Y/n): " use_detected
            use_detected=${use_detected:-y}
            if [[ "$use_detected" =~ ^[Yy]$ ]]; then
                CLOUD_FOLDER_PATH="$detected_path/Backups/Checkpoint"
                wants_cloud="y"
            else
                show_cloud_fallback_menu "mega" "true"
            fi
        else
            echo "  ✗ MEGA folder not found"
            show_cloud_fallback_menu "mega" "true"
        fi
        ;;
    8) # Other
        echo ""
        read -p "  Enter cloud sync folder path: " manual_path
        if [[ -n "$manual_path" && -d "$manual_path" ]]; then
            CLOUD_FOLDER_PATH="$manual_path/Backups/Checkpoint"
            wants_cloud="y"
            echo "  ✓ Using: $CLOUD_FOLDER_PATH"
        else
            echo "  ✗ Invalid path"
        fi
        ;;
    *) # None/Skip
        echo "  Skipping cloud backup"
        ;;
esac

if [[ -n "$CLOUD_FOLDER_PATH" ]]; then
    echo ""
    echo "  Cloud backups will sync to local folder:"
    echo "    $CLOUD_FOLDER_PATH"

    # Offer rclone as fallback if cloud folder is on external drive
    if [[ "$CLOUD_FOLDER_PATH" == /Volumes/* ]]; then
        echo ""
        echo "  ⚠️  Cloud folder is on external drive."
        echo "  Would you like to also configure direct cloud upload (via rclone)"
        echo "  as a fallback when the drive isn't connected?"
        echo ""
        read -p "  Set up rclone as fallback? (Y/n): " setup_rclone_fallback
        setup_rclone_fallback=${setup_rclone_fallback:-y}

        if [[ "$setup_rclone_fallback" =~ ^[Yy]$ ]]; then
            echo ""
            # Check if rclone is installed
            if ! command -v rclone &>/dev/null; then
                echo "  rclone not installed. Installing via Homebrew..."
                if command -v brew &>/dev/null; then
                    brew install rclone
                else
                    echo "  ✗ Homebrew not found. Please install rclone manually:"
                    echo "    brew install rclone"
                    echo "    rclone config"
                fi
            fi

            if command -v rclone &>/dev/null; then
                # Check for existing remotes
                existing_remotes=$(rclone listremotes 2>/dev/null | sed 's/:$//')
                if [[ -n "$existing_remotes" ]]; then
                    echo "  Existing rclone remotes:"
                    echo "$existing_remotes" | while read -r remote; do
                        echo "    - $remote"
                    done
                    echo ""
                    read -p "  Use existing remote name (or 'new' to create): " rclone_remote_choice

                    if [[ "$rclone_remote_choice" == "new" ]]; then
                        echo "  Launching rclone config wizard..."
                        rclone config
                        echo ""
                        read -p "  Enter the new remote name you created: " CLOUD_RCLONE_REMOTE
                    else
                        CLOUD_RCLONE_REMOTE="$rclone_remote_choice"
                    fi
                else
                    echo "  No rclone remotes configured."
                    echo "  Launching rclone config wizard..."
                    rclone config
                    echo ""
                    read -p "  Enter the remote name you created: " CLOUD_RCLONE_REMOTE
                fi

                if [[ -n "$CLOUD_RCLONE_REMOTE" ]]; then
                    CLOUD_RCLONE_PATH="Backups/Checkpoint"
                    echo "  ✓ rclone fallback configured: ${CLOUD_RCLONE_REMOTE}:${CLOUD_RCLONE_PATH}"
                fi
            fi
        fi
    fi
fi
if [[ "$CLOUD_RCLONE_ENABLED" == "true" ]]; then
    echo ""
    echo "  Cloud backups will upload directly via rclone:"
    echo "    ${CLOUD_RCLONE_REMOTE}:${CLOUD_RCLONE_PATH}"
fi
if [[ -n "$CLOUD_RCLONE_REMOTE" ]] && [[ "$CLOUD_RCLONE_ENABLED" != "true" ]]; then
    echo ""
    echo "  rclone fallback configured (when drive unavailable):"
    echo "    ${CLOUD_RCLONE_REMOTE}:${CLOUD_RCLONE_PATH}"
fi
echo ""

# === Question 3: Automated Hourly Backups ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  3/4: Automated Hourly Backups"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "  Install hourly backup schedule? (Y/n): " install_daemon
install_daemon=${install_daemon:-y}
echo ""

# === Question 4: Initial Backup ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  4/4: Initial Backup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "  Run initial backup after installation? (Y/n): " run_initial
run_initial=${run_initial:-y}
echo ""

# ==============================================================================
# DEPENDENCY CHECK & CONSOLIDATED APPROVAL
# ==============================================================================

# Load dependency manager
source "$PACKAGE_DIR/lib/dependency-manager.sh"

# Check what dependencies are needed
needed_tools=()

if [[ "$wants_cloud" =~ ^[Yy]$ ]] && ! check_rclone; then
    needed_tools+=("rclone (cloud backup)")
fi

# Check database tools if databases detected
if [ -n "$detected_dbs" ] && [[ "$ENABLE_DATABASE_BACKUP" == "true" ]]; then
    if echo "$detected_dbs" | grep -q "^postgresql|" && ! check_postgres_tools; then
        needed_tools+=("pg_dump (PostgreSQL backup)")
    fi
    if echo "$detected_dbs" | grep -q "^mysql|" && ! check_mysql_tools; then
        needed_tools+=("mysqldump (MySQL backup)")
    fi
    if echo "$detected_dbs" | grep -q "^mongodb|" && ! check_mongodb_tools; then
        needed_tools+=("mongodump (MongoDB backup)")
    fi
fi

# If tools are needed, ask for blanket permission ONCE
if [ ${#needed_tools[@]} -gt 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Additional Tools Needed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  The following tools will be installed:"
    echo ""
    for tool in "${needed_tools[@]}"; do
        echo "    • $tool"
    done
    echo ""
    read -p "  Install these tools automatically? (Y/n): " install_tools
    install_tools=${install_tools:-y}
    echo ""

    if [[ ! "$install_tools" =~ ^[Yy]?$ ]]; then
        echo "⚠️  Installation cancelled - required tools not approved"
        exit 1
    fi
fi

# ==============================================================================
# PHASE 2: INSTALLATION (No more questions!)
# ==============================================================================

echo "══════════════════════════════════════════════════════════"
echo "  Installing Checkpoint..."
echo "══════════════════════════════════════════════════════════"
echo ""

# Smart defaults
db_retention=30
file_retention=60
DRIVE_VERIFICATION_ENABLED=false
DRIVE_MARKER_FILE="$PROJECT_DIR/.backup-drive-marker"
AUTO_COMMIT_ENABLED=false
backup_env=y
backup_creds=y
backup_ide=y
backup_notes=y
backup_dbs=y
DB_PATH=""
DB_TYPE="none"

# Install dependencies silently (user already approved above)
CLOUD_ENABLED=false
CLOUD_CONFIGURED=false

if [[ "$wants_cloud" =~ ^[Yy]$ ]]; then
    if ! check_rclone; then
        echo "  → Installing rclone..."
        install_rclone >/dev/null 2>&1
    fi
    if check_rclone; then
        CLOUD_ENABLED=true
        CLOUD_CONFIGURED=true
    fi
fi

# Install database tools silently if needed
if [ -n "$detected_dbs" ] && [[ "$ENABLE_DATABASE_BACKUP" == "true" ]]; then
    if echo "$detected_dbs" | grep -q "^postgresql|" && ! check_postgres_tools; then
        echo "  → Installing PostgreSQL tools..."
        install_postgres_tools >/dev/null 2>&1
    fi
    if echo "$detected_dbs" | grep -q "^mysql|" && ! check_mysql_tools; then
        echo "  → Installing MySQL tools..."
        install_mysql_tools >/dev/null 2>&1
    fi
    if echo "$detected_dbs" | grep -q "^mongodb|" && ! check_mongodb_tools; then
        echo "  → Installing MongoDB tools..."
        install_mongodb_tools >/dev/null 2>&1
    fi
fi
echo ""

# ==============================================================================
# CREATE CONFIGURATION FILE
# ==============================================================================

echo "  [1/4] Creating configuration..."

CONFIG_FILE="$PROJECT_DIR/.backup-config.sh"

cat > "$CONFIG_FILE" << EOF
#!/usr/bin/env bash
# Checkpoint - Configuration
# Auto-generated by install.sh on $(date)

# ==============================================================================
# PROJECT CONFIGURATION
# ==============================================================================

PROJECT_DIR="$PROJECT_DIR"
PROJECT_NAME="$PROJECT_NAME"

# ==============================================================================
# BACKUP LOCATIONS
# ==============================================================================

BACKUP_DIR="$PROJECT_DIR/backups"
DATABASE_DIR="\$BACKUP_DIR/databases"
FILES_DIR="\$BACKUP_DIR/files"
ARCHIVED_DIR="\$BACKUP_DIR/archived"

# ==============================================================================
# DATABASE CONFIGURATION
# ==============================================================================

DB_PATH="$DB_PATH"
DB_TYPE="$DB_TYPE"

# ==============================================================================
# RETENTION POLICIES
# ==============================================================================

DB_RETENTION_DAYS=$db_retention
FILE_RETENTION_DAYS=$file_retention

# ==============================================================================
# BACKUP TRIGGERS
# ==============================================================================

BACKUP_INTERVAL=3600
SESSION_IDLE_THRESHOLD=600

# ==============================================================================
# DRIVE VERIFICATION
# ==============================================================================

DRIVE_VERIFICATION_ENABLED=$DRIVE_VERIFICATION_ENABLED
DRIVE_MARKER_FILE="$DRIVE_MARKER_FILE"

# ==============================================================================
# OPTIONAL FEATURES
# ==============================================================================

AUTO_COMMIT_ENABLED=$AUTO_COMMIT_ENABLED
GIT_COMMIT_MESSAGE="Auto-backup: \$(date '+%Y-%m-%d %H:%M')"

# ==============================================================================
# CRITICAL FILES TO BACKUP
# ==============================================================================

BACKUP_ENV_FILES=$([ "$backup_env" = "y" ] && echo "true" || echo "false")
BACKUP_CREDENTIALS=$([ "$backup_creds" = "y" ] && echo "true" || echo "false")
BACKUP_IDE_SETTINGS=$([ "$backup_ide" = "y" ] && echo "true" || echo "false")
BACKUP_LOCAL_NOTES=$([ "$backup_notes" = "y" ] && echo "true" || echo "false")
BACKUP_LOCAL_DATABASES=$([ "$backup_dbs" = "y" ] && echo "true" || echo "false")

# ==============================================================================
# FILE SIZE LIMITS
# ==============================================================================

# Backup all files regardless of size (set to false to skip large files)
BACKUP_LARGE_FILES=true

# Max file size in bytes (0 = no limit). Only applies if BACKUP_LARGE_FILES=false
MAX_BACKUP_FILE_SIZE=0

# ==============================================================================
# DATABASE BACKUP
# ==============================================================================

# Backup remote databases (Neon, Supabase, PlanetScale, MongoDB Atlas, etc.)
BACKUP_REMOTE_DATABASES=true

# Auto-start local database servers if not running (PostgreSQL, MySQL)
AUTO_START_LOCAL_DB=true

# Stop database server after backup (only if we started it)
STOP_DB_AFTER_BACKUP=true

# Backup databases running in Docker containers
BACKUP_DOCKER_DATABASES=true

# Auto-start Docker Desktop if not running (macOS)
AUTO_START_DOCKER=true

# Stop Docker after backup (only if we started it, and only after ALL backups complete)
STOP_DOCKER_AFTER_BACKUP=true

# ==============================================================================
# LOGGING
# ==============================================================================

LOG_FILE="\$BACKUP_DIR/backup.log"
FALLBACK_LOG="\$HOME/.claudecode-backups/logs/backup-fallback.log"

# ==============================================================================
# NOTIFICATIONS
# ==============================================================================

NOTIFICATIONS_ENABLED=true

# ==============================================================================
# STATE FILES
# ==============================================================================

STATE_DIR="\$HOME/.claudecode-backups/state"
BACKUP_TIME_STATE="\$STATE_DIR/.last-backup-time"
SESSION_FILE="\$STATE_DIR/.current-session-time"
DB_STATE_FILE="\$BACKUP_DIR/.backup-state"

# ==============================================================================
# CLOUD FOLDER SYNC (via Dropbox/iCloud/Google Drive desktop app)
# ==============================================================================

CLOUD_FOLDER_ENABLED=$([ -n "$CLOUD_FOLDER_PATH" ] && echo "true" || echo "false")
CLOUD_FOLDER_PATH="$CLOUD_FOLDER_PATH"

# ==============================================================================
# CLOUD DIRECT UPLOAD (via rclone - no desktop app needed)
# ==============================================================================

CLOUD_RCLONE_ENABLED=$CLOUD_RCLONE_ENABLED
CLOUD_RCLONE_REMOTE="$CLOUD_RCLONE_REMOTE"
CLOUD_RCLONE_PATH="$CLOUD_RCLONE_PATH"
EOF

chmod +x "$CONFIG_FILE"
echo "        ✓ Configuration created"

# ==============================================================================
# UPDATE GLOBAL CONFIG (for rclone fallback to work across all projects)
# ==============================================================================

GLOBAL_CONFIG_DIR="$HOME/.config/checkpoint"
GLOBAL_CONFIG_FILE="$GLOBAL_CONFIG_DIR/config.sh"

# Create global config directory if needed
mkdir -p "$GLOBAL_CONFIG_DIR" 2>/dev/null || true

# Update global config with rclone settings if configured
if [[ -n "$CLOUD_RCLONE_REMOTE" ]]; then
    if [[ -f "$GLOBAL_CONFIG_FILE" ]]; then
        # Update existing global config
        if grep -q "^CLOUD_RCLONE_REMOTE=" "$GLOBAL_CONFIG_FILE"; then
            # Update existing rclone remote setting
            sed -i.bak "s|^CLOUD_RCLONE_REMOTE=.*|CLOUD_RCLONE_REMOTE=\"$CLOUD_RCLONE_REMOTE\"|" "$GLOBAL_CONFIG_FILE"
            rm -f "${GLOBAL_CONFIG_FILE}.bak"
        else
            # Add rclone settings to existing config
            cat >> "$GLOBAL_CONFIG_FILE" << RCLONE_CONFIG

# ==============================================================================
# CLOUD DIRECT UPLOAD (via rclone - fallback when drive unavailable)
# ==============================================================================

CLOUD_RCLONE_ENABLED=false
CLOUD_RCLONE_REMOTE="$CLOUD_RCLONE_REMOTE"
CLOUD_RCLONE_PATH="Backups/Checkpoint"
RCLONE_CONFIG
        fi
        echo "        ✓ Global config updated with rclone fallback"
    else
        # Create new global config with essential settings
        cat > "$GLOBAL_CONFIG_FILE" << GLOBAL_CONFIG
#!/bin/bash
# ==============================================================================
# Checkpoint - Global Configuration
# ==============================================================================
# Auto-generated by install.sh on $(date)
# Per-project settings in .backup-config.sh can override these defaults
# ==============================================================================

# ==============================================================================
# CLOUD FOLDER SYNC (Direct folder sync to Dropbox/iCloud/Google Drive)
# ==============================================================================
# Note: If CLOUD_FOLDER_PATH is not set here, global config value is used

CLOUD_FOLDER_ENABLED=$CLOUD_FOLDER_ENABLED
$([ -n "$CLOUD_FOLDER_PATH" ] && echo "CLOUD_FOLDER_PATH=\"$CLOUD_FOLDER_PATH\"" || echo "# CLOUD_FOLDER_PATH not set - using global config")

# ==============================================================================
# CLOUD DIRECT UPLOAD (via rclone - fallback when drive unavailable)
# ==============================================================================

CLOUD_RCLONE_ENABLED=false
CLOUD_RCLONE_REMOTE="$CLOUD_RCLONE_REMOTE"
CLOUD_RCLONE_PATH="Backups/Checkpoint"

# ==============================================================================
# RETENTION POLICIES (Global Defaults)
# ==============================================================================

DEFAULT_DB_RETENTION_DAYS=30
DEFAULT_FILE_RETENTION_DAYS=60

# ==============================================================================
# VERSION
# ==============================================================================

GLOBAL_CONFIG_VERSION="2.3.0"
GLOBAL_CONFIG
        chmod +x "$GLOBAL_CONFIG_FILE"
        echo "        ✓ Global config created with rclone fallback"
    fi
fi

# ==============================================================================
# COPY SCRIPTS
# ==============================================================================

echo "  [2/4] Installing scripts..."

# Create bin/ directory for easy access to commands
mkdir -p "$PROJECT_DIR/bin"

# Copy all command scripts to bin/
cp "$PACKAGE_DIR/bin/backup-now.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-status.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-restore.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-cleanup.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-cloud-config.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-daemon.sh" "$PROJECT_DIR/.claude/"

# Make all scripts executable
chmod +x "$PROJECT_DIR/bin/"*.sh
chmod +x "$PROJECT_DIR/.claude/backup-daemon.sh"

# Copy library files
mkdir -p "$PROJECT_DIR/.claude/lib"
cp -r "$PACKAGE_DIR/lib/"* "$PROJECT_DIR/.claude/lib/"

echo "        ✓ Scripts installed"

# ==============================================================================
# UPDATE .GITIGNORE
# ==============================================================================

echo "  [3/4] Configuring .gitignore..."

GITIGNORE="$PROJECT_DIR/.gitignore"
[ ! -f "$GITIGNORE" ] && touch "$GITIGNORE"

# Add backup directory
if ! grep -q "^backups/$" "$GITIGNORE" 2>/dev/null; then
    echo "" >> "$GITIGNORE"
    echo "# Checkpoint" >> "$GITIGNORE"
    echo "backups/" >> "$GITIGNORE"
    echo ".backup-config.sh" >> "$GITIGNORE"
fi

# Add critical files if backup enabled
if [ "$backup_env" = "y" ] && ! grep -q "^\.env$" "$GITIGNORE" 2>/dev/null; then
    echo ".env" >> "$GITIGNORE"
    echo ".env.*" >> "$GITIGNORE"
fi

if [ "$backup_creds" = "y" ] && ! grep -q "^\*\.pem$" "$GITIGNORE" 2>/dev/null; then
    echo "*.pem" >> "$GITIGNORE"
    echo "*.key" >> "$GITIGNORE"
    echo "credentials.json" >> "$GITIGNORE"
    echo "secrets.*" >> "$GITIGNORE"
fi

echo "        ✓ .gitignore updated"

# ==============================================================================
# INSTALL BACKUP DAEMON (cross-platform via daemon-manager.sh)
# ==============================================================================

if [[ "$install_daemon" =~ ^[Yy] ]]; then
    echo "  [4/4] Installing automation..."
    DAEMON_SCRIPT="$PROJECT_DIR/.claude/backup-daemon.sh"

    # Install backup daemon via daemon-manager.sh (handles launchd/systemd/cron)
    install_daemon "$PROJECT_NAME" "$DAEMON_SCRIPT" "$PROJECT_DIR" "$PROJECT_NAME" "daemon"
    echo "        ✓ Hourly backups enabled"

    # Auto-start daemon immediately
    start_daemon "$PROJECT_NAME" 2>/dev/null && \
        echo "        ✓ Daemon started" || \
        echo "        ⚠ Daemon will start on next login"

    # Install watcher daemon if enabled
    if [ "${WATCHER_ENABLED:-false}" = "true" ]; then
        WATCHER_SCRIPT="$PACKAGE_DIR/bin/backup-watcher.sh"
        install_daemon "watcher-$PROJECT_NAME" "$WATCHER_SCRIPT" "$PROJECT_DIR" "$PROJECT_NAME" "watcher"
        echo "        ✓ File watcher installed (debounce: ${DEBOUNCE_SECONDS:-60}s)"

        # Auto-start watcher immediately
        start_daemon "watcher-$PROJECT_NAME" 2>/dev/null && \
            echo "        ✓ Watcher started" || \
            echo "        ⚠ Watcher will start on next login"
    fi
fi

# ==============================================================================
# INITIAL BACKUP
# ==============================================================================

if [[ "$run_initial" =~ ^[Yy] ]]; then
    echo "  → Running initial backup..."
    "$PROJECT_DIR/bin/backup-now.sh" >/dev/null 2>&1 && echo "        ✓ Initial backup complete" || echo "        ⚠ Backup completed with warnings"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  ✅ Checkpoint Installed Successfully!"
echo "══════════════════════════════════════════════════════════"
echo ""
echo "  Commands:"
echo "    ./bin/backup-now.sh         Run backup now"
echo "    ./bin/backup-status.sh      View backup status"
echo "    ./bin/backup-restore.sh     Restore from backup"
echo ""
if [[ "$CLOUD_CONFIGURED" == "true" ]]; then
    echo "  Next: Configure cloud storage"
    echo "    ./bin/backup-cloud-config.sh"
    echo "  2. Backups run automatically every hour"
    echo "  3. Check backups: ls -la $PROJECT_DIR/backups/"
else
    echo "  1. Backups run automatically every hour"
    echo "  2. Check backups: ls -la $PROJECT_DIR/backups/"
    echo "  4. View logs: tail -f $PROJECT_DIR/backups/backup.log"
fi
echo ""
echo "Utilities:"
echo "  - Restore files: $PACKAGE_DIR/bin/restore.sh"
echo "  - Check status: $PACKAGE_DIR/bin/status.sh"
if [[ "$CLOUD_CONFIGURED" != "true" ]]; then
    echo "  - Setup cloud: $PACKAGE_DIR/bin/backup-cloud-config.sh"
fi
echo "  - Uninstall: $PACKAGE_DIR/bin/uninstall.sh"
echo ""
echo "🔒 Security: Downloads are SHA256-verified, credentials use OS keychain"
echo ""
echo "═══════════════════════════════════════════════"
