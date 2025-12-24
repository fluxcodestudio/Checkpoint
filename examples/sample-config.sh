#!/bin/bash
# ClaudeCode Project Backups - Example Configurations
# Copy and customize these for different project types

# ==============================================================================
# EXAMPLE 1: Standard Web App (with SQLite database)
# ==============================================================================

# Use case: Full-stack web app on external drive
# - SQLite database
# - External drive with verification
# - Backs up .env, credentials
# - 30-day database retention, 60-day file retention

PROJECT_DIR="/Volumes/WorkDrive/MyWebApp"
PROJECT_NAME="MyWebApp"

BACKUP_DIR="$PROJECT_DIR/backups"
DATABASE_DIR="$BACKUP_DIR/databases"
FILES_DIR="$BACKUP_DIR/files"
ARCHIVED_DIR="$BACKUP_DIR/archived"

DB_PATH="$HOME/.mywebapp/data/app.db"
DB_TYPE="sqlite"

DB_RETENTION_DAYS=30
FILE_RETENTION_DAYS=60

BACKUP_INTERVAL=3600
SESSION_IDLE_THRESHOLD=600

DRIVE_VERIFICATION_ENABLED=true
DRIVE_MARKER_FILE="$PROJECT_DIR/.backup-drive-marker"

AUTO_COMMIT_ENABLED=false

BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=true
BACKUP_LOCAL_NOTES=true
BACKUP_LOCAL_DATABASES=true

LOG_FILE="$BACKUP_DIR/backup.log"
FALLBACK_LOG="$HOME/.claudecode-backups/logs/backup-fallback.log"

STATE_DIR="$HOME/.claudecode-backups/state"
BACKUP_TIME_STATE="$STATE_DIR/.last-backup-time"
SESSION_FILE="$STATE_DIR/.current-session-time"
DB_STATE_FILE="$BACKUP_DIR/.backup-state"

# ==============================================================================
# EXAMPLE 2: Simple Project (no database, internal drive)
# ==============================================================================

# Use case: Small coding project on internal drive
# - No database
# - No drive verification
# - Only backs up code files
# - Shorter retention (7 days)

# PROJECT_DIR="$HOME/Projects/SimpleApp"
# PROJECT_NAME="SimpleApp"
#
# BACKUP_DIR="$PROJECT_DIR/backups"
# DATABASE_DIR="$BACKUP_DIR/databases"
# FILES_DIR="$BACKUP_DIR/files"
# ARCHIVED_DIR="$BACKUP_DIR/archived"
#
# DB_PATH=""
# DB_TYPE="none"
#
# DB_RETENTION_DAYS=7
# FILE_RETENTION_DAYS=7
#
# BACKUP_INTERVAL=3600
# SESSION_IDLE_THRESHOLD=600
#
# DRIVE_VERIFICATION_ENABLED=false
# DRIVE_MARKER_FILE=""
#
# AUTO_COMMIT_ENABLED=false
#
# BACKUP_ENV_FILES=false
# BACKUP_CREDENTIALS=false
# BACKUP_IDE_SETTINGS=false
# BACKUP_LOCAL_NOTES=false
# BACKUP_LOCAL_DATABASES=false
#
# LOG_FILE="$BACKUP_DIR/backup.log"
# FALLBACK_LOG="$HOME/.claudecode-backups/logs/backup-fallback.log"
#
# STATE_DIR="$HOME/.claudecode-backups/state"
# BACKUP_TIME_STATE="$STATE_DIR/.last-backup-time"
# SESSION_FILE="$STATE_DIR/.current-session-time"
# DB_STATE_FILE="$BACKUP_DIR/.backup-state"

# ==============================================================================
# EXAMPLE 3: Multi-Computer Setup (mobile external drive)
# ==============================================================================

# Use case: External drive moves between Desktop and Laptop
# - Same config on both computers
# - Drive verification critical
# - Git auto-commit enabled
# - Long retention (90 days)

# PROJECT_DIR="/Volumes/WorkDrive/SharedProject"
# PROJECT_NAME="SharedProject"
#
# BACKUP_DIR="$PROJECT_DIR/backups"
# DATABASE_DIR="$BACKUP_DIR/databases"
# FILES_DIR="$BACKUP_DIR/files"
# ARCHIVED_DIR="$BACKUP_DIR/archived"
#
# DB_PATH="$HOME/.sharedproject/data.db"
# DB_TYPE="sqlite"
#
# DB_RETENTION_DAYS=90
# FILE_RETENTION_DAYS=90
#
# BACKUP_INTERVAL=3600
# SESSION_IDLE_THRESHOLD=600
#
# # CRITICAL: Same marker file on both computers
# DRIVE_VERIFICATION_ENABLED=true
# DRIVE_MARKER_FILE="/Volumes/WorkDrive/SharedProject/.backup-drive-marker"
#
# # Enable auto-commit for sync
# AUTO_COMMIT_ENABLED=true
#
# BACKUP_ENV_FILES=true
# BACKUP_CREDENTIALS=true
# BACKUP_IDE_SETTINGS=true
# BACKUP_LOCAL_NOTES=true
# BACKUP_LOCAL_DATABASES=true
#
# LOG_FILE="$BACKUP_DIR/backup.log"
# FALLBACK_LOG="$HOME/.claudecode-backups/logs/backup-fallback.log"
#
# STATE_DIR="$HOME/.claudecode-backups/state"
# BACKUP_TIME_STATE="$STATE_DIR/.last-backup-time"
# SESSION_FILE="$STATE_DIR/.current-session-time"
# DB_STATE_FILE="$BACKUP_DIR/.backup-state"

# ==============================================================================
# EXAMPLE 4: Client Project (aggressive backups)
# ==============================================================================

# Use case: High-value client work, paranoid backups
# - Backup every 30 minutes (not hourly)
# - Very long retention (180 days = 6 months)
# - Backup everything
# - Auto-commit enabled

# PROJECT_DIR="/Volumes/ClientDrive/ClientProject"
# PROJECT_NAME="ClientProject"
#
# BACKUP_DIR="$PROJECT_DIR/backups"
# DATABASE_DIR="$BACKUP_DIR/databases"
# FILES_DIR="$BACKUP_DIR/files"
# ARCHIVED_DIR="$BACKUP_DIR/archived"
#
# DB_PATH="$HOME/.clientproject/data.db"
# DB_TYPE="sqlite"
#
# # Long retention (6 months)
# DB_RETENTION_DAYS=180
# FILE_RETENTION_DAYS=180
#
# # Aggressive backup (every 30 minutes)
# BACKUP_INTERVAL=1800
# SESSION_IDLE_THRESHOLD=300
#
# DRIVE_VERIFICATION_ENABLED=true
# DRIVE_MARKER_FILE="$PROJECT_DIR/.backup-drive-marker"
#
# AUTO_COMMIT_ENABLED=true
#
# # Backup everything
# BACKUP_ENV_FILES=true
# BACKUP_CREDENTIALS=true
# BACKUP_IDE_SETTINGS=true
# BACKUP_LOCAL_NOTES=true
# BACKUP_LOCAL_DATABASES=true
#
# LOG_FILE="$BACKUP_DIR/backup.log"
# FALLBACK_LOG="$HOME/.claudecode-backups/logs/backup-fallback.log"
#
# STATE_DIR="$HOME/.claudecode-backups/state"
# BACKUP_TIME_STATE="$STATE_DIR/.last-backup-time"
# SESSION_FILE="$STATE_DIR/.current-session-time"
# DB_STATE_FILE="$BACKUP_DIR/.backup-state"
