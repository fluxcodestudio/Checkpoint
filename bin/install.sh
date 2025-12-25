#!/bin/bash
# Checkpoint - Installation Script
# Sets up backup system for any project

set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="${1:-$PWD}"

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

if [[ "$OSTYPE" == "darwin"* ]] && ! command -v launchctl &> /dev/null; then
    WARNINGS+=("launchctl not found - automatic backups will not work on macOS")
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
# INTERACTIVE CONFIGURATION
# ==============================================================================

echo "Let's configure backups for your project..."
echo ""

# Project name
read -p "Project name (for backup filenames): " PROJECT_NAME
[ -z "$PROJECT_NAME" ] && PROJECT_NAME=$(basename "$PROJECT_DIR")

# Database configuration
echo ""
echo "Database Configuration:"
echo "1) SQLite database"
echo "2) No database"
read -p "Select option [1-2]: " db_option

DB_PATH=""
DB_TYPE="none"

if [ "$db_option" = "1" ]; then
    read -p "Path to SQLite database file: " DB_PATH
    DB_TYPE="sqlite"
    # Expand ~ to home directory
    DB_PATH="${DB_PATH/#\~/$HOME}"
fi

# Retention policies
echo ""
read -p "Database backup retention (days) [30]: " db_retention
db_retention=${db_retention:-30}

read -p "Archived file retention (days) [60]: " file_retention
file_retention=${file_retention:-60}

# Drive verification
echo ""
read -p "Enable external drive verification? (y/n) [n]: " drive_verify
drive_verify=${drive_verify:-n}

DRIVE_VERIFICATION_ENABLED=false
DRIVE_MARKER_FILE="$PROJECT_DIR/.backup-drive-marker"

if [[ "$drive_verify" =~ ^[Yy] ]]; then
    DRIVE_VERIFICATION_ENABLED=true
    read -p "Drive marker file path [$DRIVE_MARKER_FILE]: " marker_input
    [ -n "$marker_input" ] && DRIVE_MARKER_FILE="$marker_input"

    # Create marker file if it doesn't exist
    if [ ! -f "$DRIVE_MARKER_FILE" ]; then
        touch "$DRIVE_MARKER_FILE"
        echo "✅ Created drive marker file: $DRIVE_MARKER_FILE"
    fi
fi

# Optional features
echo ""
read -p "Enable auto-commit to git after backup? (y/n) [n]: " auto_commit
auto_commit=${auto_commit:-n}

AUTO_COMMIT_ENABLED=false
if [[ "$auto_commit" =~ ^[Yy] ]]; then
    AUTO_COMMIT_ENABLED=true
fi

# Critical file backups
echo ""
echo "Backup gitignored files locally (not to GitHub):"
read -p "  - .env files? (y/n) [y]: " backup_env
backup_env=${backup_env:-y}

read -p "  - Credentials (*.pem, *.key, etc.)? (y/n) [y]: " backup_creds
backup_creds=${backup_creds:-y}

read -p "  - IDE settings? (y/n) [y]: " backup_ide
backup_ide=${backup_ide:-y}

read -p "  - Local notes? (y/n) [y]: " backup_notes
backup_notes=${backup_notes:-y}

read -p "  - Local databases? (y/n) [y]: " backup_dbs
backup_dbs=${backup_dbs:-y}

# Cloud backup
echo ""
read -p "Do you want cloud backup? (Dropbox, Google Drive, etc.) (y/n) [n]: " wants_cloud
wants_cloud=${wants_cloud:-n}

CLOUD_ENABLED=false
CLOUD_CONFIGURED=false

if [[ "$wants_cloud" =~ ^[Yy]$ ]]; then
    # Load dependency manager to handle rclone installation
    source "$PACKAGE_DIR/lib/dependency-manager.sh"

    echo ""
    echo "Cloud backup will be configured..."

    # Check/install rclone
    if require_rclone; then
        CLOUD_ENABLED=true
        CLOUD_CONFIGURED=true
        echo ""
        echo "✅ rclone ready for cloud configuration"
    else
        echo ""
        echo "⚠️  Cloud backup skipped (rclone not installed)"
        echo "   You can enable it later with: backup-cloud-config"
    fi
else
    echo ""
    echo "  ↳ Cloud backup skipped"
    echo "   You can enable it later with: backup-cloud-config"
fi

# ==============================================================================
# CREATE CONFIGURATION FILE
# ==============================================================================

echo ""
echo "Creating configuration file..."

CONFIG_FILE="$PROJECT_DIR/.backup-config.sh"

cat > "$CONFIG_FILE" << EOF
#!/bin/bash
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
# LOGGING
# ==============================================================================

LOG_FILE="\$BACKUP_DIR/backup.log"
FALLBACK_LOG="\$HOME/.claudecode-backups/logs/backup-fallback.log"

# ==============================================================================
# STATE FILES
# ==============================================================================

STATE_DIR="\$HOME/.claudecode-backups/state"
BACKUP_TIME_STATE="\$STATE_DIR/.last-backup-time"
SESSION_FILE="\$STATE_DIR/.current-session-time"
DB_STATE_FILE="\$BACKUP_DIR/.backup-state"
EOF

chmod +x "$CONFIG_FILE"
echo "✅ Configuration saved: $CONFIG_FILE"

# ==============================================================================
# CREATE .CLAUDE DIRECTORY
# ==============================================================================

mkdir -p "$PROJECT_DIR/.claude/hooks"
echo "✅ Created .claude directory"

# ==============================================================================
# COPY SCRIPTS
# ==============================================================================

echo ""
echo "Copying backup scripts..."

cp "$PACKAGE_DIR/bin/backup-daemon.sh" "$PROJECT_DIR/.claude/backup-daemon.sh"
chmod +x "$PROJECT_DIR/.claude/backup-daemon.sh"
echo "✅ Installed backup-daemon.sh"

cp "$PACKAGE_DIR/bin/smart-backup-trigger.sh" "$PROJECT_DIR/.claude/hooks/backup-trigger.sh"
chmod +x "$PROJECT_DIR/.claude/hooks/backup-trigger.sh"
echo "✅ Installed backup-trigger.sh"

# Database safety hook (if database configured)
if [ "$DB_TYPE" != "none" ]; then
    cp "$PACKAGE_DIR/templates/pre-database.sh" "$PROJECT_DIR/.claude/hooks/pre-database.sh"
    chmod +x "$PROJECT_DIR/.claude/hooks/pre-database.sh"
    echo "✅ Installed pre-database.sh safety hook"
fi

# ==============================================================================
# UPDATE .GITIGNORE
# ==============================================================================

echo ""
echo "Updating .gitignore..."

GITIGNORE="$PROJECT_DIR/.gitignore"
[ ! -f "$GITIGNORE" ] && touch "$GITIGNORE"

# Add backup directory
if ! grep -q "^backups/$" "$GITIGNORE" 2>/dev/null; then
    echo "" >> "$GITIGNORE"
    echo "# Checkpoint" >> "$GITIGNORE"
    echo "backups/" >> "$GITIGNORE"
    echo ".backup-config.sh" >> "$GITIGNORE"
    echo "✅ Added backups/ to .gitignore"
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

echo "✅ Updated .gitignore"

# ==============================================================================
# INSTALL LAUNCHAGENT (macOS only)
# ==============================================================================

echo ""
read -p "Install LaunchAgent for hourly backups? (y/n) [y]: " install_daemon
install_daemon=${install_daemon:-y}

if [[ "$install_daemon" =~ ^[Yy] ]]; then
    PLIST_FILE="$HOME/Library/LaunchAgents/com.claudecode.backup.${PROJECT_NAME}.plist"
    DAEMON_SCRIPT="$PROJECT_DIR/.claude/backup-daemon.sh"

    cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claudecode.backup.${PROJECT_NAME}</string>

    <key>ProgramArguments</key>
    <array>
        <string>$DAEMON_SCRIPT</string>
    </array>

    <key>StartInterval</key>
    <integer>3600</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardErrorPath</key>
    <string>$HOME/.claudecode-backups/logs/${PROJECT_NAME}-daemon.log</string>

    <key>StandardOutPath</key>
    <string>$HOME/.claudecode-backups/logs/${PROJECT_NAME}-daemon.log</string>
</dict>
</plist>
EOF

    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    launchctl load "$PLIST_FILE"
    echo "✅ LaunchAgent installed and loaded"
    echo "   Log: $HOME/.claudecode-backups/logs/${PROJECT_NAME}-daemon.log"
fi

# ==============================================================================
# CONFIGURE CLAUDE CODE HOOKS
# ==============================================================================

echo ""
read -p "Add backup trigger to Claude Code settings? (y/n) [y]: " install_hook
install_hook=${install_hook:-y}

if [[ "$install_hook" =~ ^[Yy] ]]; then
    SETTINGS_FILE="$HOME/.config/claude/settings.json"

    if [ -f "$SETTINGS_FILE" ]; then
        echo "⚠️  Claude Code settings.json exists"
        echo "   Add this to UserPromptSubmit hooks manually:"
        echo ""
        echo "   {\"type\": \"command\", \"command\": \"$PROJECT_DIR/.claude/hooks/backup-trigger.sh\", \"timeout\": 1}"
        echo ""
    else
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        cat > "$SETTINGS_FILE" << EOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$PROJECT_DIR/.claude/hooks/backup-trigger.sh",
            "timeout": 1
          }
        ]
      }
    ]
  }
}
EOF
        echo "✅ Claude Code settings.json created"
    fi
fi

# ==============================================================================
# INITIAL BACKUP
# ==============================================================================

echo ""
read -p "Run initial backup now? (y/n) [y]: " run_initial
run_initial=${run_initial:-y}

if [[ "$run_initial" =~ ^[Yy] ]]; then
    echo ""
    echo "Running initial backup..."
    "$PROJECT_DIR/.claude/backup-daemon.sh"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Installation Complete!"
echo "═══════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  Project: $PROJECT_NAME"
echo "  Database: ${DB_PATH:-None}"
echo "  Backups: $PROJECT_DIR/backups/"
echo "  Retention: ${db_retention}d (DB), ${file_retention}d (files)"
echo ""
echo "Next steps:"
if [[ "$CLOUD_CONFIGURED" == "true" ]]; then
    echo "  1. Configure cloud storage: $PACKAGE_DIR/bin/backup-cloud-config.sh"
    echo "  2. Backups run automatically every hour"
    echo "  3. Check backups: ls -la $PROJECT_DIR/backups/"
else
    echo "  1. Backups run automatically every hour"
    echo "  2. Backups trigger on first Claude Code prompt in new session"
    echo "  3. Check backups: ls -la $PROJECT_DIR/backups/"
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
echo "═══════════════════════════════════════════════"
