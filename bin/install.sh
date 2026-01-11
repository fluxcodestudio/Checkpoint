#!/usr/bin/env bash
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
echo "  1/5: Auto-Detecting Databases"
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
echo "  2/5: Cloud Backup (Optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "  Enable cloud backup? (y/N): " wants_cloud
wants_cloud=${wants_cloud:-n}
echo ""

# === Question 3: Automated Hourly Backups ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  3/5: Automated Hourly Backups (macOS only)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "  Install hourly backup schedule? (Y/n): " install_daemon
install_daemon=${install_daemon:-y}
echo ""

# === Question 4: Claude Code Integration ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  4/5: Claude Code Integration (Optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "  Add backup trigger to Claude Code? (Y/n): " install_hook
install_hook=${install_hook:-y}
echo ""

# === Question 5: Initial Backup ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  5/5: Initial Backup"
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

echo "  [1/5] Creating configuration..."

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
EOF

chmod +x "$CONFIG_FILE"
echo "        ✓ Configuration created"

# ==============================================================================
# CREATE .CLAUDE DIRECTORY
# ==============================================================================

mkdir -p "$PROJECT_DIR/.claude/hooks" >/dev/null 2>&1

# ==============================================================================
# COPY SCRIPTS
# ==============================================================================

echo "  [2/5] Installing scripts..."

# Create bin/ directory for easy access to commands
mkdir -p "$PROJECT_DIR/bin"

# Copy all command scripts to bin/
cp "$PACKAGE_DIR/bin/backup-now.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-status.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-restore.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-cleanup.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-cloud-config.sh" "$PROJECT_DIR/bin/"
cp "$PACKAGE_DIR/bin/backup-daemon.sh" "$PROJECT_DIR/.claude/"
cp "$PACKAGE_DIR/bin/smart-backup-trigger.sh" "$PROJECT_DIR/.claude/hooks/backup-trigger.sh"

# Make all scripts executable
chmod +x "$PROJECT_DIR/bin/"*.sh
chmod +x "$PROJECT_DIR/.claude/backup-daemon.sh"
chmod +x "$PROJECT_DIR/.claude/hooks/backup-trigger.sh"

# Copy library files
mkdir -p "$PROJECT_DIR/.claude/lib"
cp -r "$PACKAGE_DIR/lib/"* "$PROJECT_DIR/.claude/lib/"

echo "        ✓ Scripts installed"

# ==============================================================================
# UPDATE .GITIGNORE
# ==============================================================================

echo "  [3/5] Configuring .gitignore..."

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
# INSTALL LAUNCHAGENT (macOS only)
# ==============================================================================

if [[ "$install_daemon" =~ ^[Yy] ]]; then
    echo "  [4/5] Installing automation..."
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
    launchctl load "$PLIST_FILE" 2>&1 >/dev/null
    echo "        ✓ Hourly backups enabled"

    # Install watcher LaunchAgent if enabled
    if [ "${WATCHER_ENABLED:-false}" = "true" ]; then
        WATCHER_PLIST_NAME="com.claudecode.backup-watcher.${PROJECT_NAME}.plist"
        WATCHER_PLIST_PATH="$HOME/Library/LaunchAgents/$WATCHER_PLIST_NAME"

        # Create from template
        sed -e "s|PROJECT_NAME_PLACEHOLDER|$PROJECT_NAME|g" \
            -e "s|PROJECT_DIR_PLACEHOLDER|$PROJECT_DIR|g" \
            -e "s|HOME_PLACEHOLDER|$HOME|g" \
            "$PACKAGE_DIR/templates/launchd-watcher.plist" > "$WATCHER_PLIST_PATH"

        # Load LaunchAgent
        launchctl unload "$WATCHER_PLIST_PATH" 2>/dev/null || true
        launchctl load "$WATCHER_PLIST_PATH"
        echo "        ✓ File watcher installed (debounce: ${DEBOUNCE_SECONDS:-60}s)"
    fi
fi

# ==============================================================================
# CONFIGURE CLAUDE CODE HOOKS
# ==============================================================================

if [[ "$install_hook" =~ ^[Yy] ]]; then
    echo "  [5/5] Configuring Claude Code integration..."
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
        echo "        ✓ Claude Code integration enabled"
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
