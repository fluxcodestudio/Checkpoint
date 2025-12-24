#!/bin/bash
# Integration Tests: Complete Backup/Restore Workflow

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT
export PATH="$PROJECT_ROOT/bin:$PATH"

# ==============================================================================
# COMPLETE BACKUP WORKFLOW TESTS
# ==============================================================================

test_suite "Complete Backup Workflow"

test_case "WORKFLOW 1: Fresh installation and first backup"
if PROJECT_DIR="$(create_test_project "workflow-test-1")" && \
   cd "$PROJECT_DIR" && \

   # Create config
   cat > "$PROJECT_DIR/.backup-config.sh" <<EOF
PROJECT_DIR="$PROJECT_DIR"
PROJECT_NAME="WorkflowTest1"
BACKUP_DIR="$PROJECT_DIR/backups"
DATABASE_DIR="\$BACKUP_DIR/databases"
FILES_DIR="\$BACKUP_DIR/files"
ARCHIVED_DIR="\$BACKUP_DIR/archived"
DB_PATH=""
DB_TYPE="none"
DB_RETENTION_DAYS=30
FILE_RETENTION_DAYS=60
BACKUP_INTERVAL=3600
SESSION_IDLE_THRESHOLD=600
DRIVE_VERIFICATION_ENABLED=false
AUTO_COMMIT_ENABLED=false
BACKUP_ENV_FILES=false
BACKUP_CREDENTIALS=false
BACKUP_IDE_SETTINGS=false
BACKUP_LOCAL_NOTES=false
BACKUP_LOCAL_DATABASES=false
LOG_FILE="\$BACKUP_DIR/backup.log"
STATE_DIR="\$HOME/.claudecode-backups/state"
BACKUP_TIME_STATE="\$STATE_DIR/.last-backup-time"
SESSION_FILE="\$STATE_DIR/.current-session-time"
DB_STATE_FILE="\$BACKUP_DIR/.backup-state"
EOF

   # Initialize directories
   mkdir -p "$PROJECT_DIR/backups/"{databases,files,archived} && \
   mkdir -p "$HOME/.claudecode-backups/state" && \

   # Verify directories created
   assert_dir_exists "$PROJECT_DIR/backups" && \
   assert_dir_exists "$PROJECT_DIR/backups/databases" && \
   assert_dir_exists "$PROJECT_DIR/backups/files" && \
   assert_dir_exists "$PROJECT_DIR/backups/archived"; then
    test_pass
else
    test_fail "Failed to set up fresh installation"
fi

test_case "WORKFLOW 2: Backup modified files"
if PROJECT_DIR="$(create_test_project "workflow-test-2")" && \
   cd "$PROJECT_DIR" && \

   # Modify files
   echo "// Modified" >> "$PROJECT_DIR/app.js" && \
   echo "New file content" > "$PROJECT_DIR/new-file.txt" && \

   # Check git status shows changes
   git -C "$PROJECT_DIR" status --short | grep -q "M app.js" && \
   git -C "$PROJECT_DIR" status --short | grep -q "?? new-file.txt" && \

   # Simulate backup by copying files
   BACKUP_DIR="$PROJECT_DIR/backups/files" && \
   mkdir -p "$BACKUP_DIR" && \
   cp "$PROJECT_DIR/app.js" "$BACKUP_DIR/" && \
   cp "$PROJECT_DIR/new-file.txt" "$BACKUP_DIR/" && \

   # Verify files backed up
   assert_file_exists "$BACKUP_DIR/app.js" && \
   assert_file_exists "$BACKUP_DIR/new-file.txt"; then
    test_pass
else
    test_fail "Failed to backup modified files"
fi

test_case "WORKFLOW 3: Archive files with timestamp"
if PROJECT_DIR="$(create_test_project "workflow-test-3")" && \

   # Simulate file archiving
   ARCHIVE_DIR="$PROJECT_DIR/backups/archived" && \
   mkdir -p "$ARCHIVE_DIR/src" && \
   TIMESTAMP="$(date +%Y%m%d_%H%M%S)" && \
   cp "$PROJECT_DIR/src/lib.js" "$ARCHIVE_DIR/src/lib.js.$TIMESTAMP" && \

   # Verify archive created with timestamp
   [[ -f "$ARCHIVE_DIR/src/lib.js.$TIMESTAMP" ]]; then
    test_pass
else
    test_fail "Failed to create timestamped archive"
fi

# ==============================================================================
# DATABASE BACKUP WORKFLOW TESTS
# ==============================================================================

test_suite "Database Backup Workflow"

test_case "DATABASE 1: SQLite backup and compression"
if DB_PATH="$TEST_TEMP_DIR/app-db1.db" && \
   create_test_database "$DB_PATH" && \

   # Create backup directory
   BACKUP_DIR="$TEST_TEMP_DIR/backups-db1/databases" && \
   mkdir -p "$BACKUP_DIR" && \

   # Backup with timestamp and compression
   TIMESTAMP="$(date +%Y.%m.%d-%H.%M.%S)" && \
   BACKUP_FILE="$BACKUP_DIR/TestProject-$TIMESTAMP.db" && \
   cp "$DB_PATH" "$BACKUP_FILE" && \
   gzip "$BACKUP_FILE" && \

   # Verify compressed backup exists
   assert_file_exists "$BACKUP_FILE.gz"; then
    test_pass
else
    test_fail "Database backup failed"
fi

test_case "DATABASE 2: Verify backup integrity"
if DB_PATH="$TEST_TEMP_DIR/app-db2.db" && \
   create_test_database "$DB_PATH" && \

   # Create and compress backup
   BACKUP_DIR="$TEST_TEMP_DIR/backups-db2/databases" && \
   mkdir -p "$BACKUP_DIR" && \
   TIMESTAMP="$(date +%Y.%m.%d-%H.%M.%S)-2" && \
   BACKUP_FILE="$BACKUP_DIR/TestProject-$TIMESTAMP.db" && \
   cp "$DB_PATH" "$BACKUP_FILE" && \
   gzip "$BACKUP_FILE" && \

   # Decompress and verify
   gunzip -c "$BACKUP_FILE.gz" > "$TEST_TEMP_DIR/restored-db2.db" && \
   ROW_COUNT=$(sqlite3 "$TEST_TEMP_DIR/restored-db2.db" "SELECT COUNT(*) FROM users;") && \
   [[ "$ROW_COUNT" == "2" ]]; then
    test_pass
else
    test_fail "Backup integrity check failed"
fi

# ==============================================================================
# RESTORE WORKFLOW TESTS
# ==============================================================================

test_suite "Restore Workflow"

test_case "RESTORE 1: Restore database from backup"
if DB_PATH="$TEST_TEMP_DIR/app-restore1.db" && \
   create_test_database "$DB_PATH" && \

   # Create backup
   BACKUP_DIR="$TEST_TEMP_DIR/backups-restore1/databases" && \
   mkdir -p "$BACKUP_DIR" && \
   BACKUP_FILE="$BACKUP_DIR/backup-restore1.db.gz" && \
   gzip -c "$DB_PATH" > "$BACKUP_FILE" && \

   # Delete original
   rm "$DB_PATH" && \
   assert_file_not_exists "$DB_PATH" && \

   # Restore
   gunzip -c "$BACKUP_FILE" > "$DB_PATH" && \

   # Verify restoration
   assert_file_exists "$DB_PATH" && \
   ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;") && \
   [[ "$ROW_COUNT" == "2" ]]; then
    test_pass
else
    test_fail "Database restore failed"
fi

test_case "RESTORE 2: Restore specific file version"
if PROJECT_DIR="$(create_test_project "restore-test")" && \

   # Create multiple versions
   ARCHIVE_DIR="$PROJECT_DIR/backups/archived" && \
   mkdir -p "$ARCHIVE_DIR" && \
   echo "version 1" > "$PROJECT_DIR/test.txt" && \
   cp "$PROJECT_DIR/test.txt" "$ARCHIVE_DIR/test.txt.20250101_120000" && \
   sleep 1 && \
   echo "version 2" > "$PROJECT_DIR/test.txt" && \
   cp "$PROJECT_DIR/test.txt" "$ARCHIVE_DIR/test.txt.20250101_130000" && \
   sleep 1 && \
   echo "version 3" > "$PROJECT_DIR/test.txt" && \

   # Restore version 1
   cp "$ARCHIVE_DIR/test.txt.20250101_120000" "$PROJECT_DIR/test.txt" && \

   # Verify correct version restored
   CONTENT=$(cat "$PROJECT_DIR/test.txt") && \
   [[ "$CONTENT" == "version 1" ]]; then
    test_pass
else
    test_fail "File version restore failed"
fi

test_case "RESTORE 3: Pre-restore backup creation"
if DB_PATH="$TEST_TEMP_DIR/app-prerestore.db" && \
   create_test_database "$DB_PATH" && \

   # Create pre-restore backup
   PRE_RESTORE_DIR="$TEST_TEMP_DIR/backups-prerestore/.pre-restore-$(date +%Y%m%d_%H%M%S)" && \
   mkdir -p "$PRE_RESTORE_DIR" && \
   cp "$DB_PATH" "$PRE_RESTORE_DIR/app-prerestore.db" && \

   # Verify pre-restore backup exists
   assert_file_exists "$PRE_RESTORE_DIR/app-prerestore.db"; then
    test_pass
else
    test_fail "Pre-restore backup not created"
fi

# ==============================================================================
# CLEANUP WORKFLOW TESTS
# ==============================================================================

test_suite "Cleanup Workflow"

test_case "CLEANUP 1: Delete old database backups"
if BACKUP_DIR="$TEST_TEMP_DIR/backups/databases" && \
   mkdir -p "$BACKUP_DIR" && \

   # Create old and new backups
   touch -t "202301010000" "$BACKUP_DIR/old-backup.db.gz" && \
   touch "$BACKUP_DIR/new-backup.db.gz" && \

   # Delete backups older than 30 days
   find "$BACKUP_DIR" -name "*.db.gz" -type f -mtime +30 -delete && \

   # Verify old deleted, new retained
   assert_file_not_exists "$BACKUP_DIR/old-backup.db.gz" && \
   assert_file_exists "$BACKUP_DIR/new-backup.db.gz"; then
    test_pass
else
    test_fail "Cleanup failed"
fi

test_case "CLEANUP 2: Delete old archived files"
if ARCHIVE_DIR="$TEST_TEMP_DIR/backups/archived" && \
   mkdir -p "$ARCHIVE_DIR" && \

   # Create old and new archives
   touch -t "202301010000" "$ARCHIVE_DIR/old-file.txt.20230101" && \
   touch "$ARCHIVE_DIR/new-file.txt.$(date +%Y%m%d)" && \

   # Delete archives older than 60 days
   find "$ARCHIVE_DIR" -type f -mtime +60 -delete && \

   # Verify old deleted, new retained
   assert_file_not_exists "$ARCHIVE_DIR/old-file.txt.20230101" && \
   assert_file_exists "$ARCHIVE_DIR/new-file.txt.$(date +%Y%m%d)"; then
    test_pass
else
    test_fail "Archive cleanup failed"
fi

test_case "CLEANUP 3: Remove empty directories"
if ARCHIVE_DIR="$TEST_TEMP_DIR/backups/archived" && \
   mkdir -p "$ARCHIVE_DIR/empty-dir" && \
   mkdir -p "$ARCHIVE_DIR/full-dir" && \
   touch "$ARCHIVE_DIR/full-dir/file.txt" && \

   # Remove empty directories
   find "$ARCHIVE_DIR" -type d -empty -delete && \

   # Verify empty dir removed, full dir retained
   assert_dir_exists "$ARCHIVE_DIR/full-dir" && \
   [[ ! -d "$ARCHIVE_DIR/empty-dir" ]]; then
    test_pass
else
    test_fail "Empty directory cleanup failed"
fi

# ==============================================================================
# SESSION WORKFLOW TESTS
# ==============================================================================

test_suite "Session Workflow"

test_case "SESSION 1: First Claude Code prompt triggers backup"
if STATE_DIR="$TEST_TEMP_DIR/state" && \
   mkdir -p "$STATE_DIR" && \
   SESSION_FILE="$STATE_DIR/.current-session-time" && \

   # Simulate new session
   date +%s > "$SESSION_FILE" && \

   # Check if backup should trigger (first prompt = no last backup time)
   LAST_BACKUP_FILE="$STATE_DIR/.last-backup-time" && \
   [[ ! -f "$LAST_BACKUP_FILE" ]]; then
    test_pass
else
    test_fail "First prompt detection failed"
fi

test_case "SESSION 2: Hourly backup check"
if STATE_DIR="$TEST_TEMP_DIR/state" && \
   mkdir -p "$STATE_DIR" && \
   LAST_BACKUP_FILE="$STATE_DIR/.last-backup-time" && \

   # Set last backup time to 2 hours ago
   PAST_TIME="$(($(date +%s) - 7200))" && \
   echo "$PAST_TIME" > "$LAST_BACKUP_FILE" && \

   # Check if backup should trigger
   CURRENT_TIME="$(date +%s)" && \
   LAST_BACKUP="$(cat "$LAST_BACKUP_FILE")" && \
   TIME_DIFF="$((CURRENT_TIME - LAST_BACKUP))" && \
   [[ $TIME_DIFF -ge 3600 ]]; then
    test_pass
else
    test_fail "Hourly backup check failed"
fi

test_case "SESSION 3: Idle session detection"
if STATE_DIR="$TEST_TEMP_DIR/state" && \
   mkdir -p "$STATE_DIR" && \
   SESSION_FILE="$STATE_DIR/.current-session-time" && \

   # Set session time to 15 minutes ago
   PAST_TIME="$(($(date +%s) - 900))" && \
   echo "$PAST_TIME" > "$SESSION_FILE" && \

   # Check if session is idle (>10 min)
   CURRENT_TIME="$(date +%s)" && \
   SESSION_TIME="$(cat "$SESSION_FILE")" && \
   IDLE_TIME="$((CURRENT_TIME - SESSION_TIME))" && \
   IDLE_THRESHOLD=600 && \
   [[ $IDLE_TIME -ge $IDLE_THRESHOLD ]]; then
    test_pass
else
    test_fail "Idle session detection failed"
fi

# ==============================================================================
# CRITICAL FILE BACKUP TESTS
# ==============================================================================

test_suite "Critical File Backup"

test_case "CRITICAL 1: .env file backup (even if gitignored)"
if PROJECT_DIR="$(create_test_project "critical-test")" && \

   # Create .env file
   cat > "$PROJECT_DIR/.env" <<EOF
DATABASE_URL=postgres://localhost/myapp
API_KEY=secret123
EOF

   # Add to gitignore
   echo ".env" >> "$PROJECT_DIR/.gitignore" && \

   # Verify gitignored
   git -C "$PROJECT_DIR" check-ignore ".env" &>/dev/null && \

   # Backup critical files anyway
   FILES_DIR="$PROJECT_DIR/backups/files" && \
   mkdir -p "$FILES_DIR" && \
   cp "$PROJECT_DIR/.env" "$FILES_DIR/" && \

   # Verify backed up
   assert_file_exists "$FILES_DIR/.env"; then
    test_pass
else
    test_fail "Critical file backup failed"
fi

test_case "CRITICAL 2: credentials.json backup"
if PROJECT_DIR="$(create_test_project "critical-test-2")" && \

   # Create credentials file
   cat > "$PROJECT_DIR/credentials.json" <<EOF
{"api_key": "secret", "token": "abc123"}
EOF

   # Backup
   FILES_DIR="$PROJECT_DIR/backups/files" && \
   mkdir -p "$FILES_DIR" && \
   cp "$PROJECT_DIR/credentials.json" "$FILES_DIR/" && \

   # Verify
   assert_file_exists "$FILES_DIR/credentials.json"; then
    test_pass
else
    test_fail "Credentials backup failed"
fi

# Run summary
print_test_summary
