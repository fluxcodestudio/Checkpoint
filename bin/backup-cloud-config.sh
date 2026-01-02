#!/usr/bin/env bash
# Checkpoint - Cloud Backup Configuration Wizard
# Configure cloud storage for backups via rclone

set -euo pipefail

# Resolve symlinks to get actual script location
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load libraries
source "$PROJECT_ROOT/lib/backup-lib.sh"
source "$PROJECT_ROOT/lib/cloud-backup.sh"
source "$PROJECT_ROOT/lib/dependency-manager.sh"

# ==============================================================================
# CLOUD CONFIGURATION WIZARD
# ==============================================================================

wizard() {
    clear
    echo "═══════════════════════════════════════════════════════════"
    echo "  Checkpoint - Cloud Backup Configuration"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Check and install rclone if needed
    if ! require_rclone; then
        echo ""
        echo "❌ Cloud backup requires rclone"
        echo "   Configuration cancelled"
        echo ""
        exit 1
    fi

    echo ""
    echo "✅ rclone ready"
    echo ""

    # Step 1: Backup Location
    echo "1. Where do you want to store backups?"
    echo ""
    echo "   [1] Local only (recommended for speed)"
    echo "   [2] Cloud only (requires internet)"
    echo "   [3] Both local + cloud (best protection)"
    echo ""
    read -p "Choice [1-3]: " location_choice

    case "$location_choice" in
        1) BACKUP_LOCATION="local" ;;
        2) BACKUP_LOCATION="cloud" ;;
        3) BACKUP_LOCATION="both" ;;
        *) BACKUP_LOCATION="local" ;;
    esac

    echo ""

    # Step 2: Local Path (if local or both)
    if [[ "$BACKUP_LOCATION" != "cloud" ]]; then
        echo "2. Choose local backup directory:"
        echo ""
        echo "   [1] Project folder: ./backups"
        echo "   [2] External drive: /Volumes/Backups"
        echo "   [3] Custom path"
        echo ""
        read -p "Choice [1-3]: " local_choice

        case "$local_choice" in
            1) LOCAL_BACKUP_DIR="$PROJECT_DIR/backups" ;;
            2)
                read -p "Enter drive path: " drive_path
                LOCAL_BACKUP_DIR="$drive_path/$PROJECT_NAME"
                ;;
            3)
                read -p "Enter custom path: " custom_path
                LOCAL_BACKUP_DIR="$custom_path"
                ;;
        esac

        # Validate and create directory
        mkdir -p "$LOCAL_BACKUP_DIR" 2>/dev/null || {
            echo "✗ Failed to create directory: $LOCAL_BACKUP_DIR"
            exit 1
        }
        echo "✓ Local backup directory: $LOCAL_BACKUP_DIR"
        echo ""
    fi

    # Step 3: Cloud Configuration (if cloud or both)
    if [[ "$BACKUP_LOCATION" != "local" ]]; then
        echo "3. Choose cloud storage provider:"
        echo ""
        echo "   [1] Dropbox (2GB free)"
        echo "   [2] Google Drive (15GB free)"
        echo "   [3] OneDrive (5GB free)"
        echo "   [4] iCloud Drive (macOS, 5GB free)"
        echo "   [5] Skip cloud setup for now"
        echo ""
        read -p "Choice [1-5]: " cloud_choice

        case "$cloud_choice" in
            1) CLOUD_PROVIDER="dropbox" ;;
            2) CLOUD_PROVIDER="gdrive" ;;
            3) CLOUD_PROVIDER="onedrive" ;;
            4) CLOUD_PROVIDER="icloud" ;;
            5)
                echo "Skipping cloud setup"
                CLOUD_ENABLED=false
                save_config
                exit 0
                ;;
        esac

        CLOUD_ENABLED=true
        echo ""

        # Step 4: rclone Setup
        echo "4. rclone setup:"
        echo ""

        if check_rclone_installed; then
            echo "✓ rclone is already installed"
        else
            echo "⚠  rclone is required for cloud backups"
            echo ""
            echo "   [1] Install rclone now"
            echo "   [2] Skip (I'll install it manually)"
            echo ""
            read -p "Choice [1-2]: " install_choice

            if [[ "$install_choice" == "1" ]]; then
                install_rclone || {
                    echo "✗ Failed to install rclone"
                    exit 1
                }
            else
                echo "⚠  Install rclone manually: curl https://rclone.org/install.sh | bash"
                exit 0
            fi
        fi

        echo ""
        echo "   [1] I already have rclone configured for $CLOUD_PROVIDER"
        echo "   [2] Configure rclone now"
        echo ""
        read -p "Choice [1-2]: " config_choice

        if [[ "$config_choice" == "2" ]]; then
            setup_rclone_remote "$CLOUD_PROVIDER"
        fi

        echo ""

        # Step 5: Select Remote
        echo "5. Available rclone remotes:"
        echo ""

        remotes=$(list_rclone_remotes)
        if [[ -z "$remotes" ]]; then
            echo "✗ No rclone remotes configured"
            echo "Run: rclone config"
            exit 1
        fi

        select remote in $remotes; do
            if [[ -n "$remote" ]]; then
                CLOUD_REMOTE_NAME="$remote"
                break
            fi
        done

        echo "✓ Using remote: $CLOUD_REMOTE_NAME"
        echo ""

        # Test connection
        if test_rclone_connection "$CLOUD_REMOTE_NAME"; then
            echo ""
        else
            echo "✗ Connection test failed"
            exit 1
        fi

        # Step 6: Cloud Path
        read -p "Cloud backup path (e.g., /Backups/MyProject): " cloud_path
        CLOUD_BACKUP_PATH="${cloud_path:-/Backups/$PROJECT_NAME}"
        echo ""

        # Step 7: What to Upload
        echo "6. What to upload to cloud?"
        echo ""
        echo "   [✓] Database backups (compressed, small)"
        read -p "   Upload databases? [Y/n]: " upload_db
        CLOUD_SYNC_DATABASES="${upload_db:-Y}"
        [[ "${CLOUD_SYNC_DATABASES,,}" =~ ^(y|yes)$ ]] && CLOUD_SYNC_DATABASES=true || CLOUD_SYNC_DATABASES=false

        echo "   [✓] Critical files (.env, credentials)"
        read -p "   Upload critical files? [Y/n]: " upload_crit
        CLOUD_SYNC_CRITICAL="${upload_crit:-Y}"
        [[ "${CLOUD_SYNC_CRITICAL,,}" =~ ^(y|yes)$ ]] && CLOUD_SYNC_CRITICAL=true || CLOUD_SYNC_CRITICAL=false

        echo "   [ ] All project files (can be large)"
        read -p "   Upload all files? [y/N]: " upload_all
        CLOUD_SYNC_FILES="${upload_all:-N}"
        [[ "${CLOUD_SYNC_FILES,,}" =~ ^(y|yes)$ ]] && CLOUD_SYNC_FILES=true || CLOUD_SYNC_FILES=false

        echo ""
    fi

    # Summary
    echo "═══════════════════════════════════════════════════════════"
    echo "Configuration Summary:"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Backup Location: $BACKUP_LOCATION"
    [[ "$BACKUP_LOCATION" != "cloud" ]] && echo "Local Directory: $LOCAL_BACKUP_DIR"
    [[ "$BACKUP_LOCATION" != "local" ]] && {
        echo "Cloud Provider:  $CLOUD_PROVIDER"
        echo "Cloud Remote:    $CLOUD_REMOTE_NAME"
        echo "Cloud Path:      $CLOUD_BACKUP_PATH"
        echo "Upload DBs:      $CLOUD_SYNC_DATABASES"
        echo "Upload Critical: $CLOUD_SYNC_CRITICAL"
        echo "Upload All:      $CLOUD_SYNC_FILES"
    }
    echo ""

    read -p "Save configuration? [Y/n]: " save_choice
    if [[ "${save_choice,,}" =~ ^(n|no)$ ]]; then
        echo "Configuration not saved"
        exit 0
    fi

    save_config
    echo ""
    echo "✓ Configuration saved to $CONFIG_FILE"
}

save_config() {
    # Append cloud config to existing .backup-config.sh
    CONFIG_FILE="${CONFIG_FILE:-$PROJECT_DIR/.backup-config.sh}"

    # Remove old cloud config if exists
    if [[ -f "$CONFIG_FILE" ]]; then
        sed -i.bak '/# Cloud Backup Configuration/,/# End Cloud Config/d' "$CONFIG_FILE"
    fi

    # Append new cloud config
    cat >> "$CONFIG_FILE" << EOF

# Cloud Backup Configuration
BACKUP_LOCATION="${BACKUP_LOCATION:-local}"
LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR:-\$BACKUP_DIR}"
CLOUD_ENABLED=${CLOUD_ENABLED:-false}
CLOUD_PROVIDER="${CLOUD_PROVIDER:-}"
CLOUD_REMOTE_NAME="${CLOUD_REMOTE_NAME:-}"
CLOUD_BACKUP_PATH="${CLOUD_BACKUP_PATH:-}"
CLOUD_SYNC_DATABASES=${CLOUD_SYNC_DATABASES:-true}
CLOUD_SYNC_CRITICAL=${CLOUD_SYNC_CRITICAL:-true}
CLOUD_SYNC_FILES=${CLOUD_SYNC_FILES:-false}
# End Cloud Config
EOF
}

# ==============================================================================
# MAIN
# ==============================================================================

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: backup-cloud-config"
    echo ""
    echo "Interactive wizard to configure cloud backup via rclone"
    echo ""
    echo "Supports: Dropbox, Google Drive, OneDrive, iCloud Drive"
    exit 0
fi

wizard
