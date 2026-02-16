#!/bin/bash
# ==============================================================================
# Checkpoint - Global Configuration
# ==============================================================================
# This file contains default settings that apply to ALL projects
# Per-project settings in .backup-config.sh can override these defaults
# Location: ~/.config/checkpoint/config.sh
# ==============================================================================

# ==============================================================================
# RETENTION POLICIES (Global Defaults)
# ==============================================================================

# How long to keep database backups (days)
DEFAULT_DB_RETENTION_DAYS=30

# How long to keep archived file versions (days)
DEFAULT_FILE_RETENTION_DAYS=60

# ==============================================================================
# CLOUD BACKUP (Global Defaults)
# ==============================================================================

# Enable cloud backup by default for new projects
DEFAULT_CLOUD_ENABLED=false

# Preferred cloud provider: dropbox | gdrive | onedrive | icloud
DEFAULT_CLOUD_PROVIDER=""

# Default rclone remote name (if configured)
DEFAULT_CLOUD_REMOTE_NAME=""

# Sync databases to cloud by default
DEFAULT_CLOUD_SYNC_DATABASES=true

# Sync critical files (.env, credentials) to cloud by default
DEFAULT_CLOUD_SYNC_CRITICAL=true

# Sync all project files to cloud by default
DEFAULT_CLOUD_SYNC_FILES=false

# ==============================================================================
# FILE BACKUP (Global Defaults)
# ==============================================================================

# Backup .env files by default
DEFAULT_BACKUP_ENV_FILES=true

# Backup credentials (credentials.json, *.pem, etc.) by default
DEFAULT_BACKUP_CREDENTIALS=true

# Backup IDE settings (.vscode, .idea, etc.) by default
DEFAULT_BACKUP_IDE_SETTINGS=true

# Backup AI coding tool artifacts (.claude/, .cursor/, .aider, etc.) by default
DEFAULT_BACKUP_AI_ARTIFACTS=true

# ==============================================================================
# AUTOMATION (Global Defaults)
# ==============================================================================

# Backup interval for hourly daemon (seconds)
DEFAULT_BACKUP_INTERVAL=3600

# Session idle threshold - trigger backup after this much idle time (seconds)
DEFAULT_SESSION_IDLE_THRESHOLD=600

# Install hourly backups (macOS LaunchAgent) by default for new projects
DEFAULT_INSTALL_HOURLY_BACKUPS=true

# ==============================================================================
# INTEGRATIONS (Global Preferences)
# ==============================================================================

# Enable Claude Code integration globally
CLAUDE_CODE_INTEGRATION=true

# Enable Git pre-commit hooks globally
GIT_HOOKS_ENABLED=false

# Enable Shell integration (prompt indicator) globally
SHELL_INTEGRATION_ENABLED=false

# ==============================================================================
# NOTIFICATIONS (Global Preferences)
# ==============================================================================

# Show desktop notifications on backup complete (macOS only)
DESKTOP_NOTIFICATIONS=false

# Notify on backup failures only
NOTIFY_ON_FAILURE_ONLY=true

# ==============================================================================
# ADVANCED (Global Settings)
# ==============================================================================

# Compression level for database backups (1-9, 9=maximum)
COMPRESSION_LEVEL=6

# Enable debug logging
DEBUG_MODE=false

# Auto-update Checkpoint (check for updates weekly)
AUTO_UPDATE_CHECK=true

# ==============================================================================
# VERSION
# ==============================================================================

# Config file version (for migrations)
GLOBAL_CONFIG_VERSION="2.2.0"
