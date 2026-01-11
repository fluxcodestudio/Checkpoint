#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Cloud Folder Detector
# ==============================================================================
# Version: 2.3.0
# Description: Detect cloud-synced folders on macOS for automatic backup
#              via desktop sync apps (Dropbox, Google Drive, iCloud, OneDrive).
#
# Usage:
#   source lib/cloud-folder-detector.sh
#   detect_all_cloud_folders
#   get_cloud_backup_root "/path/to/cloud/folder"
#
# Features:
#   - Auto-detects Dropbox, Google Drive, iCloud, OneDrive
#   - Validates folders are writable before returning
#   - Supports custom folder locations
#   - Returns structured output for integration
# ==============================================================================

# ==============================================================================
# DETECTION: DROPBOX
# ==============================================================================

# Detect Dropbox folder location
# Checks standard paths and parses ~/.dropbox/info.json for custom location
# Returns: 0 and echoes path if found, 1 if not found
detect_dropbox_folder() {
    local dropbox_path=""

    # Method 1: Parse ~/.dropbox/info.json (most reliable for custom locations)
    if [[ -f "$HOME/.dropbox/info.json" ]]; then
        # Extract path from JSON (handles both personal and business accounts)
        dropbox_path=$(grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.dropbox/info.json" 2>/dev/null | head -1 | sed 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        if [[ -n "$dropbox_path" && -d "$dropbox_path" && -w "$dropbox_path" ]]; then
            echo "$dropbox_path"
            return 0
        fi
    fi

    # Method 2: Check macOS CloudStorage location (newer Dropbox versions)
    local cloudstorage_dropbox="$HOME/Library/CloudStorage"
    if [[ -d "$cloudstorage_dropbox" ]]; then
        local dropbox_dirs
        dropbox_dirs=$(find "$cloudstorage_dropbox" -maxdepth 1 -type d -name "Dropbox*" 2>/dev/null)
        while IFS= read -r dir; do
            [[ -z "$dir" ]] && continue
            if [[ -d "$dir" && -w "$dir" ]]; then
                echo "$dir"
                return 0
            fi
        done <<< "$dropbox_dirs"
    fi

    # Method 3: Check standard ~/Dropbox location
    if [[ -d "$HOME/Dropbox" && -w "$HOME/Dropbox" ]]; then
        echo "$HOME/Dropbox"
        return 0
    fi

    return 1
}

# ==============================================================================
# DETECTION: GOOGLE DRIVE
# ==============================================================================

# Detect Google Drive folder location
# Checks standard paths and CloudStorage locations
# Returns: 0 and echoes path if found, 1 if not found
detect_gdrive_folder() {
    local gdrive_path=""

    # Method 1: Check macOS CloudStorage location (Drive for Desktop)
    # Pattern: ~/Library/CloudStorage/GoogleDrive-{email}/My Drive
    local cloudstorage_gdrive="$HOME/Library/CloudStorage"
    if [[ -d "$cloudstorage_gdrive" ]]; then
        local gdrive_dirs
        gdrive_dirs=$(find "$cloudstorage_gdrive" -maxdepth 1 -type d -name "GoogleDrive-*" 2>/dev/null)
        while IFS= read -r dir; do
            [[ -z "$dir" ]] && continue
            if [[ -d "$dir" ]]; then
            # Check for "My Drive" subdirectory (personal files)
            if [[ -d "$dir/My Drive" && -w "$dir/My Drive" ]]; then
                echo "$dir/My Drive"
                return 0
            fi
            # Fallback to root of drive folder
            if [[ -w "$dir" ]]; then
                echo "$dir"
                return 0
            fi
            fi
        done <<< "$gdrive_dirs"
    fi

    # Method 2: Check legacy location
    if [[ -d "$HOME/Google Drive" && -w "$HOME/Google Drive" ]]; then
        # Check for My Drive subdirectory
        if [[ -d "$HOME/Google Drive/My Drive" && -w "$HOME/Google Drive/My Drive" ]]; then
            echo "$HOME/Google Drive/My Drive"
            return 0
        fi
        echo "$HOME/Google Drive"
        return 0
    fi

    return 1
}

# ==============================================================================
# DETECTION: ICLOUD DRIVE
# ==============================================================================

# Detect iCloud Drive folder location
# Returns: 0 and echoes path if found, 1 if not found
detect_icloud_folder() {
    local icloud_path="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

    if [[ -d "$icloud_path" && -w "$icloud_path" ]]; then
        echo "$icloud_path"
        return 0
    fi

    return 1
}

# ==============================================================================
# DETECTION: ONEDRIVE
# ==============================================================================

# Detect OneDrive folder location
# Checks standard paths and CloudStorage locations (personal and business)
# Returns: 0 and echoes path if found, 1 if not found
detect_onedrive_folder() {
    # Method 1: Check macOS CloudStorage location (newer OneDrive versions)
    # Handles both personal (OneDrive-Personal) and business (OneDrive-CompanyName)
    local cloudstorage_onedrive="$HOME/Library/CloudStorage"
    if [[ -d "$cloudstorage_onedrive" ]]; then
        local onedrive_dirs
        onedrive_dirs=$(find "$cloudstorage_onedrive" -maxdepth 1 -type d -name "OneDrive*" 2>/dev/null)
        while IFS= read -r dir; do
            [[ -z "$dir" ]] && continue
            if [[ -d "$dir" && -w "$dir" ]]; then
                echo "$dir"
                return 0
            fi
        done <<< "$onedrive_dirs"
    fi

    # Method 2: Check standard ~/OneDrive location
    if [[ -d "$HOME/OneDrive" && -w "$HOME/OneDrive" ]]; then
        echo "$HOME/OneDrive"
        return 0
    fi

    # Method 3: Check with dash prefix (some configurations)
    if [[ -d "$HOME/OneDrive - Personal" && -w "$HOME/OneDrive - Personal" ]]; then
        echo "$HOME/OneDrive - Personal"
        return 0
    fi

    return 1
}

# ==============================================================================
# UNIFIED DETECTION
# ==============================================================================

# Detect all available cloud-synced folders
# Returns: List of detected cloud services with paths, one per line
#          Format: "service|path"
detect_all_cloud_folders() {
    local found=0

    # Check Dropbox
    local dropbox_path
    if dropbox_path=$(detect_dropbox_folder); then
        echo "dropbox|$dropbox_path"
        found=1
    fi

    # Check Google Drive
    local gdrive_path
    if gdrive_path=$(detect_gdrive_folder); then
        echo "gdrive|$gdrive_path"
        found=1
    fi

    # Check iCloud
    local icloud_path
    if icloud_path=$(detect_icloud_folder); then
        echo "icloud|$icloud_path"
        found=1
    fi

    # Check OneDrive
    local onedrive_path
    if onedrive_path=$(detect_onedrive_folder); then
        echo "onedrive|$onedrive_path"
        found=1
    fi

    if [[ $found -eq 0 ]]; then
        return 1
    fi

    return 0
}

# Get the first available cloud folder (for auto-detection)
# Returns: 0 and echoes path of first found cloud folder, 1 if none found
get_first_cloud_folder() {
    local result
    result=$(detect_all_cloud_folders | head -1)

    if [[ -n "$result" ]]; then
        # Extract just the path (after the |)
        echo "${result#*|}"
        return 0
    fi

    return 1
}

# ==============================================================================
# BACKUP ROOT HELPERS
# ==============================================================================

# Get the backup root directory within a cloud folder
# Creates the path if it doesn't exist
# Args:
#   $1 - Cloud folder path
#   $2 - Backup subfolder name (default: "Backups/Checkpoint")
# Returns: Full path to backup root
get_cloud_backup_root() {
    local cloud_folder="$1"
    local backup_subfolder="${2:-Backups/Checkpoint}"

    if [[ -z "$cloud_folder" ]]; then
        echo "Error: No cloud folder path specified" >&2
        return 1
    fi

    if [[ ! -d "$cloud_folder" ]]; then
        echo "Error: Cloud folder does not exist: $cloud_folder" >&2
        return 1
    fi

    local backup_root="$cloud_folder/$backup_subfolder"

    # Create backup root if it doesn't exist
    if [[ ! -d "$backup_root" ]]; then
        if ! mkdir -p "$backup_root" 2>/dev/null; then
            echo "Error: Cannot create backup directory: $backup_root" >&2
            return 1
        fi
    fi

    # Verify it's writable
    if [[ ! -w "$backup_root" ]]; then
        echo "Error: Backup directory not writable: $backup_root" >&2
        return 1
    fi

    echo "$backup_root"
    return 0
}

# Auto-detect cloud folder and return backup root
# Convenience function combining detection and root creation
# Args:
#   $1 - Backup subfolder name (default: "Backups/Checkpoint")
# Returns: Full path to backup root in first available cloud folder
auto_detect_cloud_backup_root() {
    local backup_subfolder="${1:-Backups/Checkpoint}"

    local cloud_folder
    if ! cloud_folder=$(get_first_cloud_folder); then
        echo "Error: No cloud folders detected" >&2
        return 1
    fi

    get_cloud_backup_root "$cloud_folder" "$backup_subfolder"
}

# ==============================================================================
# DISPLAY HELPERS
# ==============================================================================

# Display detected cloud folders in human-readable format
show_detected_cloud_folders() {
    echo ""
    echo "🔍 Scanning for cloud-synced folders..."
    echo ""

    local clouds
    clouds=$(detect_all_cloud_folders)

    if [[ -z "$clouds" ]]; then
        echo "  No cloud folders detected"
        echo ""
        echo "  Supported services:"
        echo "    • Dropbox (dropbox.com)"
        echo "    • Google Drive (drive.google.com)"
        echo "    • iCloud Drive (icloud.com)"
        echo "    • OneDrive (onedrive.com)"
        echo ""
        return 1
    fi

    echo "  Detected cloud folders:"
    echo ""

    while IFS='|' read -r service path; do
        case "$service" in
            dropbox)
                echo "    ✓ Dropbox"
                ;;
            gdrive)
                echo "    ✓ Google Drive"
                ;;
            icloud)
                echo "    ✓ iCloud Drive"
                ;;
            onedrive)
                echo "    ✓ OneDrive"
                ;;
        esac
        echo "      Path: $path"
        echo ""
    done <<< "$clouds"

    return 0
}
