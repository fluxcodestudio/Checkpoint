#!/bin/bash
# ClaudeCode Project Backups - Configuration Template
# Copy this to your project root as .backup-config.sh and customize

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
# RETENTION POLICIES
# ==============================================================================

# Database backup retention (in days)
# How long to keep timestamped database snapshots
DB_RETENTION_DAYS=30

# Archived file retention (in days)
# How long to keep old file versions in archived/
FILE_RETENTION_DAYS=60

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

# ==============================================================================
# LOGGING
# ==============================================================================

# Main backup log file
LOG_FILE="$BACKUP_DIR/backup.log"

# Fallback log (if drive disconnected)
FALLBACK_LOG="$HOME/.claudecode-backups/logs/backup-fallback.log"

# ==============================================================================
# STATE FILES (coordination between daemon and hooks)
# ==============================================================================

# State directory
STATE_DIR="$HOME/.claudecode-backups/state"

# Last backup timestamp
BACKUP_TIME_STATE="$STATE_DIR/.last-backup-time"

# Current session tracking
SESSION_FILE="$STATE_DIR/.current-session-time"

# Database state tracking
DB_STATE_FILE="$BACKUP_DIR/.backup-state"
