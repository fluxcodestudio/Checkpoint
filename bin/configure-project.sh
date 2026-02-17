#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Project Configuration Wizard
# ==============================================================================
# Configures backup system for a specific project
# Can be called standalone or from installers
# Usage: configure-project.sh [project-directory]
# ==============================================================================

set -euo pipefail

PROJECT_DIR="${1:-$PWD}"
PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

source "$PACKAGE_DIR/lib/core/logging.sh"
source "$PACKAGE_DIR/lib/platform/daemon-manager.sh"

# Verify project directory exists
if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "❌ Project directory not found: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

echo "══════════════════════════════════════════════════════════"
echo "  Checkpoint - Project Configuration"
echo "══════════════════════════════════════════════════════════"
echo ""
echo "Project: $(basename "$PROJECT_DIR")"
echo "Location: $PROJECT_DIR"
echo ""

# Check if already configured
if [[ -f "$PROJECT_DIR/.backup-config.sh" ]]; then
    echo "⚠️  This project already has a backup configuration."
    echo ""
    read -p "Reconfigure? (y/N): " reconfigure
    reconfigure=${reconfigure:-n}
    if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
        echo "Configuration cancelled."
        exit 0
    fi
    echo ""
fi

# ==============================================================================
# PHASE 1: GATHER CONFIGURATION
# ==============================================================================

# Load database detector
if [[ -f "$PACKAGE_DIR/lib/database-detector.sh" ]]; then
    source "$PACKAGE_DIR/lib/database-detector.sh"
elif [[ -f "/usr/local/lib/checkpoint/lib/database-detector.sh" ]]; then
    source "/usr/local/lib/checkpoint/lib/database-detector.sh"
elif [[ -f "$HOME/.local/lib/checkpoint/lib/database-detector.sh" ]]; then
    source "$HOME/.local/lib/checkpoint/lib/database-detector.sh"
fi

# === Question 1: Database Backups ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  1/6: Auto-Detecting Databases"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

detected_dbs=$(detect_databases "$PROJECT_DIR" 2>/dev/null | grep -v "🔍" || echo "")

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
                    echo "  ⊘ PostgreSQL: $database (remote - will skip)"
                fi
                ;;
            mysql)
                IFS='|' read -r host port database user is_local <<< "$rest"
                if [[ "$is_local" == "true" ]]; then
                    echo "  ✓ MySQL: $database (local)"
                else
                    echo "  ⊘ MySQL: $database (remote - will skip)"
                fi
                ;;
            mongodb)
                IFS='|' read -r host port database user is_local <<< "$rest"
                if [[ "$is_local" == "true" ]]; then
                    echo "  ✓ MongoDB: $database (local)"
                else
                    echo "  ⊘ MongoDB: $database (remote - will skip)"
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
echo "  2/6: Cloud Backup (Optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "  Enable cloud backup? (y/N): " wants_cloud
wants_cloud=${wants_cloud:-n}
echo ""

# === Question 3: Automated Hourly Backups ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  3/6: Automated Hourly Backups"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "  Install hourly backup schedule? (Y/n): " install_daemon
install_daemon=${install_daemon:-y}
echo ""

# === Question 4: GitHub Auto-Push ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  4/5: GitHub Auto-Push (Optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
wants_github_push=n
github_push_interval=7200
if git remote get-url origin &>/dev/null; then
    echo "  Git remote detected: $(git remote get-url origin)"
    read -p "  Auto-push to GitHub every 2 hours? (Y/n): " wants_github_push
    wants_github_push=${wants_github_push:-y}

    if [[ "$wants_github_push" =~ ^[Yy]$ ]]; then
        echo ""
        echo "  Push frequency options:"
        echo "    1) Every hour"
        echo "    2) Every 2 hours (recommended)"
        echo "    3) Every 4 hours"
        echo "    4) Daily"
        read -p "  Choose [1-4] (default: 2): " push_freq_choice
        push_freq_choice=${push_freq_choice:-2}

        case "$push_freq_choice" in
            1) github_push_interval=3600 ;;
            2) github_push_interval=7200 ;;
            3) github_push_interval=14400 ;;
            4) github_push_interval=86400 ;;
            *) github_push_interval=7200 ;;
        esac

        # Check authentication
        if ! check_github_auth 2>/dev/null; then
            echo ""
            echo "  ⚠️  GitHub authentication not detected."
            read -p "  Set up authentication now? (Y/n): " setup_auth
            setup_auth=${setup_auth:-y}
            if [[ "$setup_auth" =~ ^[Yy]$ ]]; then
                setup_github_auth
            fi
        else
            echo "  ✓ GitHub authentication detected"
        fi
    fi
else
    echo "  No git remote configured - skipping"
fi
echo ""

# === Question 5: Initial Backup ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  5/5: Initial Backup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "  Run initial backup now? (Y/n): " run_initial
run_initial=${run_initial:-y}
echo ""

# ==============================================================================
# PHASE 2: CREATE CONFIGURATION FILE
# ==============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Creating Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PROJECT_NAME=$(basename "$PROJECT_DIR")
BACKUP_DIR="$PROJECT_DIR/backups"

# Create .backup-config.sh
cat > "$PROJECT_DIR/.backup-config.sh" << EOF
#!/usr/bin/env bash
# Checkpoint Configuration
# Auto-generated on $(date)

# Project
PROJECT_NAME="$PROJECT_NAME"
PROJECT_DIR="$PROJECT_DIR"
BACKUP_DIR="$BACKUP_DIR"

# Database
DB_TYPE="$([ "$ENABLE_DATABASE_BACKUP" == "true" ] && echo "auto" || echo "none")"
DB_RETENTION_DAYS=30

# Files
FILE_RETENTION_DAYS=60

# Automation
BACKUP_INTERVAL=3600
SESSION_IDLE_THRESHOLD=600

# Cloud Backup
CLOUD_ENABLED=$([ "$wants_cloud" =~ ^[Yy]$ ] && echo "true" || echo "false")
BACKUP_LOCATION="local"

# GitHub Auto-Push
GIT_AUTO_PUSH_ENABLED=$([ "$wants_github_push" =~ ^[Yy]$ ] && echo "true" || echo "false")
GIT_PUSH_INTERVAL=$github_push_interval
GIT_PUSH_REMOTE="origin"
GIT_PUSH_BRANCH=""
GIT_PUSH_STATE="\$STATE_DIR/\${PROJECT_NAME}/.last-git-push"

# Optional Features
HOOKS_ENABLED=false

# Critical Files
BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=true
EOF

chmod +x "$PROJECT_DIR/.backup-config.sh"
echo "  ✓ Created .backup-config.sh"

# Add to .gitignore
if [[ -f "$PROJECT_DIR/.gitignore" ]]; then
    if ! grep -q "^backups/$" "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        echo "" >> "$PROJECT_DIR/.gitignore"
        echo "# Checkpoint backups" >> "$PROJECT_DIR/.gitignore"
        echo "backups/" >> "$PROJECT_DIR/.gitignore"
        echo "  ✓ Added backups/ to .gitignore"
    fi
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"/{databases,files,archived}
echo "  ✓ Created backup directory structure"

echo ""

# ==============================================================================
# PHASE 3: OPTIONAL FEATURES
# ==============================================================================

# Cloud backup setup
if [[ "$wants_cloud" =~ ^[Yy]$ ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Cloud Backup Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Run cloud config wizard
    if command -v backup-cloud-config &>/dev/null; then
        backup-cloud-config
    elif [[ -x "$PACKAGE_DIR/bin/backup-cloud-config.sh" ]]; then
        "$PACKAGE_DIR/bin/backup-cloud-config.sh"
    fi
fi

# Backup daemon setup (cross-platform via daemon-manager.sh)
if [[ "$install_daemon" =~ ^[Yy]$ ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Installing Hourly Backup Schedule"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Find backup-daemon command
    if command -v backup-daemon &>/dev/null; then
        DAEMON_CMD="backup-daemon"
    elif [[ -x "$PACKAGE_DIR/bin/backup-daemon.sh" ]]; then
        DAEMON_CMD="$PACKAGE_DIR/bin/backup-daemon.sh"
    fi

    if [[ -n "${DAEMON_CMD:-}" ]]; then
        install_daemon "$PROJECT_NAME" "$DAEMON_CMD" "$PROJECT_DIR" "$PROJECT_NAME" "daemon"
        echo "  ✓ Hourly backups configured"
    fi
fi

# ==============================================================================
# PHASE 4: INITIAL BACKUP
# ==============================================================================

if [[ "$run_initial" =~ ^[Yy]$ ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Running Initial Backup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Find backup-now command
    if command -v backup-now &>/dev/null; then
        backup-now
    elif [[ -x "$PACKAGE_DIR/bin/backup-now.sh" ]]; then
        "$PACKAGE_DIR/bin/backup-now.sh"
    fi
fi

# ==============================================================================
# DONE
# ==============================================================================

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Configuration Complete!"
echo "═══════════════════════════════════════════════"
echo ""
echo "Project: $PROJECT_NAME"
echo "Backups: $BACKUP_DIR"
echo ""
echo "Available commands:"
echo "  backup-now              Run backup immediately"
echo "  backup-status           View backup status"
echo "  backup-restore          Restore files"
echo ""
