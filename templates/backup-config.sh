#!/bin/bash
# ClaudeCode Project Backups - Configuration Template v1.1
# Copy this to your project root as .backup-config.sh and customize
#
# v1.1 Features: Tiered retention, alerts/notifications, quiet hours, performance optimizations

# Configuration version (for migration detection)
CONFIG_VERSION="1.1"

# ==============================================================================
# PROJECT CONFIGURATION
# ==============================================================================

# Project directory (where your code lives)
# Default: Auto-detected from script location
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Project name (used in backup filenames)
# Example: "MyApp", "ClientProject", "Startup"
PROJECT_NAME="MyProject"

# ==============================================================================
# BACKUP LOCATIONS
# ==============================================================================

# Main backup directory
# Default: PROJECT_DIR/backups (relative to project)
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"

# Database backups subdirectory
DATABASE_DIR="$BACKUP_DIR/databases"

# Current file backups subdirectory
FILES_DIR="$BACKUP_DIR/files"

# Archived file versions subdirectory
ARCHIVED_DIR="$BACKUP_DIR/archived"

# ==============================================================================
# DATABASE CONFIGURATION
# ==============================================================================

# Database path (leave empty if no database)
# Example: "$HOME/.myapp/data/app.db"
DB_PATH=""

# Database type: "sqlite" or "none"
DB_TYPE="sqlite"

# ==============================================================================
# CREDENTIAL STORAGE
# ==============================================================================

# Use OS-native credential store for database passwords
# Options: true/false (default: false)
# When true, Checkpoint checks macOS Keychain / Linux secret-tool / pass
# before falling back to .env file passwords
# Store credentials: checkpoint credential store <db-type> <db-name>
CHECKPOINT_USE_CREDENTIAL_STORE="false"

# ==============================================================================
# RETENTION POLICIES
# ==============================================================================

# Database backup retention (in days)
# How long to keep timestamped database snapshots
DB_RETENTION_DAYS=30

# Archived file retention (in days)
# How long to keep old file versions in archived/
FILE_RETENTION_DAYS=60

# Tiered retention (Phase 5) - smart space management
# Keeps: all backups <24h, hourly 1-7d, daily 7-30d, weekly 30-90d, monthly 90d+
TIERED_RETENTION_ENABLED=true

# ==============================================================================
# BACKUP TRIGGERS
# ==============================================================================

# Backup interval (in seconds)
# Default: 3600 (1 hour)
BACKUP_INTERVAL=3600

# Session idle threshold (in seconds)
# Time of inactivity before considering it a new session
# Default: 600 (10 minutes)
SESSION_IDLE_THRESHOLD=600

# ==============================================================================
# DRIVE VERIFICATION (for external drives)
# ==============================================================================

# Enable drive verification (true/false)
# If true, requires DRIVE_MARKER_FILE to exist before backing up
DRIVE_VERIFICATION_ENABLED=false

# Drive marker file path
# Create an empty file at this location to verify correct drive
DRIVE_MARKER_FILE="$PROJECT_DIR/.backup-drive-marker"

# ==============================================================================
# OPTIONAL FEATURES
# ==============================================================================

# Auto-commit to git after backup (true/false)
AUTO_COMMIT_ENABLED=false

# Git commit message template
GIT_COMMIT_MESSAGE="Auto-backup: $(date '+%Y-%m-%d %H:%M')"

# ==============================================================================
# GITHUB AUTO-PUSH
# ==============================================================================

# Auto-push to GitHub after backup (true/false)
# Requires: git remote configured, authentication set up (gh auth login)
GIT_AUTO_PUSH_ENABLED=false

# Push interval in seconds (default: 7200 = 2 hours)
# Options: 3600 (hourly), 7200 (2 hours), 14400 (4 hours), 86400 (daily)
GIT_PUSH_INTERVAL=7200

# Branch to push (leave empty for current branch)
GIT_PUSH_BRANCH=""

# Remote name (default: origin)
GIT_PUSH_REMOTE="origin"

# Last push timestamp tracking - PROJECT-SPECIFIC
GIT_PUSH_STATE="$STATE_DIR/${PROJECT_NAME}/.last-git-push"

# ==============================================================================
# CRITICAL FILES TO BACKUP (even if gitignored)
# ==============================================================================

# Backup .env files
BACKUP_ENV_FILES=true

# Backup credentials (*.pem, *.key, credentials.json, etc.)
BACKUP_CREDENTIALS=true

# Backup IDE settings (.vscode/, .idea/, etc.)
BACKUP_IDE_SETTINGS=true

# Backup local notes (NOTES.md, *.private.md, etc.)
BACKUP_LOCAL_NOTES=true

# Backup local databases (*.db, *.sqlite, etc.)
BACKUP_LOCAL_DATABASES=true

# AI Tool Artifacts — include .claude/, .cursor/, .aider, .windsurf/ etc.
BACKUP_AI_ARTIFACTS=true
# Extra directories to include (comma-separated, relative to project root)
AI_ARTIFACT_EXTRA_DIRS=""
# Extra files to include (comma-separated, relative to project root)
AI_ARTIFACT_EXTRA_FILES=""

# ==============================================================================
# CLOUD FOLDER DESTINATION (auto-sync via desktop app)
# ==============================================================================

# Enable cloud folder backup (true/false)
# When enabled, backups write to a cloud-synced folder (Dropbox/GDrive/iCloud/OneDrive)
# This provides automatic cloud backup via the desktop sync app - no API calls needed
CLOUD_FOLDER_ENABLED=true

# Cloud folder path (auto-detected if empty)
# Examples:
#   "$HOME/Dropbox/Backups/Checkpoint"
#   "$HOME/Google Drive/Backups/Checkpoint"
#   "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Backups/Checkpoint"
# Leave empty to auto-detect first available cloud folder
CLOUD_FOLDER_PATH=""

# Project subfolder within cloud backup (uses PROJECT_NAME by default)
# Backups will be stored at: $CLOUD_FOLDER_PATH/$CLOUD_PROJECT_FOLDER/
CLOUD_PROJECT_FOLDER="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

# Keep local backup in addition to cloud folder (true/false)
# If true, maintains backup in both PROJECT/backups/ and cloud folder
# If false, only backs up to cloud folder (saves local disk space)
CLOUD_FOLDER_ALSO_LOCAL=true

# ==============================================================================
# CLOUD BACKUP (via rclone)
# ==============================================================================
# Note: Cloud folder backup (above) is preferred when available.
# rclone is used as fallback when cloud folder is unavailable or for additional remotes.

# Enable cloud backup (true/false)
# Requires rclone to be installed and configured
CLOUD_ENABLED=false

# Cloud provider remote name (as configured in rclone)
# Run 'rclone config' to set up a remote
CLOUD_REMOTE_NAME=""

# Path on cloud storage for backups
# e.g., "checkpoint-backups/project-name"
CLOUD_BACKUP_PATH=""

# Cloud backup retention in days (default: 30)
# Backups older than this will be automatically deleted
CLOUD_RETENTION_DAYS=30

# Minimum number of cloud backups to keep (default: 5)
# Even if older than retention period, keep at least this many
CLOUD_MIN_BACKUP_COUNT=5

# What to sync to cloud
CLOUD_SYNC_DATABASES=true   # Sync database backups
CLOUD_SYNC_CRITICAL=true    # Sync critical files (.env, credentials)
CLOUD_SYNC_FILES=false      # Sync all file backups (can be large)

# ==============================================================================
# FILE SIZE LIMITS
# ==============================================================================

# Maximum file size to backup (in bytes)
# Default: 104857600 (100MB)
# Files larger than this will be skipped with a warning
# Set to 0 to disable size limit (backup all files regardless of size)
MAX_BACKUP_FILE_SIZE=104857600

# Backup large files anyway (overrides MAX_BACKUP_FILE_SIZE)
# Set to true if you have specific large files you need backed up
BACKUP_LARGE_FILES=false

# ==============================================================================
# TIMESTAMP CONFIGURATION (Issue #13)
# ==============================================================================

# Use UTC timestamps for backup filenames (true/false)
# Default: false (use local time)
# Set to true for consistent timestamps across timezones
USE_UTC_TIMESTAMPS=false

# ==============================================================================
# FILE WATCHER SETTINGS
# ==============================================================================

# Enable automatic file watching (primary trigger mechanism for backups)
# Uses native file system events (fswatch on macOS, inotifywait on Linux)
# with polling fallback. Triggers backup after quiet period.
WATCHER_ENABLED=false

# Seconds of inactivity before triggering backup (default: 60)
# Lower values = more frequent backups, higher values = fewer backups
DEBOUNCE_SECONDS=60

# Additional paths to exclude from watching (beyond defaults)
# Defaults always excluded:
#   VCS:          .git, .hg, .svn
#   Dependencies: node_modules, vendor/, .venv, venv/, __pycache__, bower_components
#   Build output: dist/, build/, .next/, .nuxt/, .parcel-cache, coverage/
#   IDE/Editor:   .idea, .swp, .swo, 4913, .#
#   OS metadata:  .DS_Store
#   Project:      backups/, .cache, .planning/, .claudecode-backups, .terraform
#   Compiled:     .pyc
# Example: WATCHER_EXCLUDES=("vendor" "tmp" ".terraform")
# WATCHER_EXCLUDES=()

# Poll interval in seconds (only used when no native file watcher available)
# Native watchers (fswatch, inotifywait) don't use this — they're event-driven
# Default: 30 seconds
# POLL_INTERVAL=30

# ==============================================================================
# LOGGING
# ==============================================================================

# Main backup log file
LOG_FILE="$BACKUP_DIR/backup.log"

# Fallback log (if drive disconnected) - PROJECT-SPECIFIC
FALLBACK_LOG="$HOME/.claudecode-backups/logs/${PROJECT_NAME}/backup-fallback.log"

# ==============================================================================
# ALERTS AND NOTIFICATIONS
# ==============================================================================

# Alert thresholds (when backup is considered stale)
# Warning state: backup older than this many hours
ALERT_WARNING_HOURS=24

# Error state: backup older than this many hours
ALERT_ERROR_HOURS=72

# Notification preferences
NOTIFY_ON_SUCCESS=false      # Notify after successful backup (useful after fixing issues)
NOTIFY_ON_WARNING=true       # Notify when backup becomes stale (warning threshold)
NOTIFY_ON_ERROR=true         # Notify on backup failures

# Escalation: hours between repeated notifications for same issue
NOTIFY_ESCALATION_HOURS=3

# Notification sound: default, Basso, Glass, Hero, Pop, none
NOTIFY_SOUND="default"

# Per-project notification override (set to false to silence this project)
PROJECT_NOTIFY_ENABLED=true

# ==============================================================================
# QUIET HOURS
# ==============================================================================

# Suppress non-critical notifications during quiet hours
# Format: START-END in 24-hour time (e.g., "22-07" for 10pm to 7am)
# Leave empty to disable quiet hours
QUIET_HOURS=""

# Block even critical errors during quiet hours (default: false = critical errors always notify)
QUIET_HOURS_BLOCK_ERRORS=false

# ==============================================================================
# STATE FILES (coordination between daemon and hooks)
# ==============================================================================

# State directory (global base - each project gets its own subdirectory)
STATE_DIR="$HOME/.claudecode-backups/state"

# Last backup timestamp - PROJECT-SPECIFIC
BACKUP_TIME_STATE="$STATE_DIR/${PROJECT_NAME}/.last-backup-time"

# Current session tracking - PROJECT-SPECIFIC
SESSION_FILE="$STATE_DIR/${PROJECT_NAME}/.current-session-time"

# Database state tracking
DB_STATE_FILE="$BACKUP_DIR/.backup-state"
