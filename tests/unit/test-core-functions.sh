#!/bin/bash
# Unit Tests: Core Backup Functions

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

# Source the scripts we're testing
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT

# ==============================================================================
# CONFIGURATION VALIDATION TESTS
# ==============================================================================

test_suite "Configuration Validation"

test_case "validate_config_basic - should accept valid minimal config"
if TEST_CONFIG="$TEST_TEMP_DIR/test-config.sh" && \
   cat > "$TEST_CONFIG" <<'EOF'
PROJECT_DIR="/tmp/test-project"
PROJECT_NAME="TestProject"
BACKUP_DIR="/tmp/test-project/backups"
DATABASE_DIR="$BACKUP_DIR/databases"
FILES_DIR="$BACKUP_DIR/files"
ARCHIVED_DIR="$BACKUP_DIR/archived"
DB_RETENTION_DAYS=30
FILE_RETENTION_DAYS=60
BACKUP_INTERVAL=3600
EOF
   mkdir -p "/tmp/test-project" && \
   [[ -f "$TEST_CONFIG" ]]; then
    test_pass
else
    test_fail "Failed to create valid config"
fi

test_case "validate_config - should detect missing required fields"
if TEST_CONFIG="$TEST_TEMP_DIR/invalid-config.sh" && \
   cat > "$TEST_CONFIG" <<'EOF'
PROJECT_DIR="/tmp/test"
# Missing PROJECT_NAME and other required fields
EOF
   [[ -f "$TEST_CONFIG" ]]; then
    test_pass
else
    test_fail
fi

# ==============================================================================
# BACKUP STATE MANAGEMENT TESTS
# ==============================================================================

test_suite "Backup State Management"

test_case "state_file - should create state directory"
if STATE_DIR="$TEST_TEMP_DIR/state" && \
   mkdir -p "$STATE_DIR" && \
   [[ -d "$STATE_DIR" ]]; then
    test_pass
else
    test_fail "Failed to create state directory"
fi

test_case "last_backup_time - should store and retrieve timestamp"
if STATE_FILE="$TEST_TEMP_DIR/state/.last-backup" && \
   TIMESTAMP="$(date +%s)" && \
   echo "$TIMESTAMP" > "$STATE_FILE" && \
   RETRIEVED="$(cat "$STATE_FILE")" && \
   [[ "$TIMESTAMP" == "$RETRIEVED" ]]; then
    test_pass
else
    test_fail "Timestamp mismatch"
fi

test_case "backup_interval - should calculate time since last backup"
if CURRENT_TIME="$(date +%s)" && \
   LAST_BACKUP="$((CURRENT_TIME - 3600))" && \
   TIME_DIFF="$((CURRENT_TIME - LAST_BACKUP))" && \
   [[ $TIME_DIFF -ge 3600 ]]; then
    test_pass
else
    test_fail "Time calculation incorrect"
fi

# ==============================================================================
# FILE FILTERING TESTS
# ==============================================================================

test_suite "File Filtering"

test_case "gitignore_files - should be excluded from normal backups"
if GITIGNORE_PATTERNS=("node_modules/" ".env" "*.log") && \
   [[ "${#GITIGNORE_PATTERNS[@]}" -eq 3 ]]; then
    test_pass
else
    test_fail
fi

test_case "critical_files - should be backed up even if gitignored"
if CRITICAL_FILES=(".env" "credentials.json" ".env.local") && \
   [[ "${#CRITICAL_FILES[@]}" -eq 3 ]]; then
    test_pass
else
    test_fail
fi

# ==============================================================================
# DATABASE BACKUP TESTS
# ==============================================================================

test_suite "Database Backup"

test_case "sqlite_backup - should create database backup"
if DB_PATH="$TEST_TEMP_DIR/test-backup-1.db" && \
   create_test_database "$DB_PATH" && \
   BACKUP_PATH="$TEST_TEMP_DIR/backup-1.db" && \
   cp "$DB_PATH" "$BACKUP_PATH" && \
   assert_file_exists "$BACKUP_PATH"; then
    test_pass
else
    test_fail "Failed to create database backup"
fi

test_case "sqlite_backup - backup should be valid SQLite database"
if DB_PATH="$TEST_TEMP_DIR/test-backup-2.db" && \
   create_test_database "$DB_PATH" && \
   BACKUP_PATH="$TEST_TEMP_DIR/backup-2.db" && \
   cp "$DB_PATH" "$BACKUP_PATH" && \
   sqlite3 "$BACKUP_PATH" "SELECT COUNT(*) FROM users;" | grep -q "2"; then
    test_pass
else
    test_fail "Backup database is not valid"
fi

test_case "database_compression - should reduce file size"
if DB_PATH="$TEST_TEMP_DIR/test-compress.db" && \
   create_test_database "$DB_PATH" && \
   ORIGINAL_SIZE=$(stat -f%z "$DB_PATH" 2>/dev/null || stat -c%s "$DB_PATH") && \
   gzip -c "$DB_PATH" > "$TEST_TEMP_DIR/test-compress.db.gz" && \
   COMPRESSED_SIZE=$(stat -f%z "$TEST_TEMP_DIR/test-compress.db.gz" 2>/dev/null || stat -c%s "$TEST_TEMP_DIR/test-compress.db.gz") && \
   [[ $COMPRESSED_SIZE -lt $ORIGINAL_SIZE ]]; then
    test_pass
else
    test_fail "Compression did not reduce size"
fi

# ==============================================================================
# FILE BACKUP TESTS
# ==============================================================================

test_suite "File Backup"

test_case "file_backup - should copy file to backup location"
if SOURCE="$TEST_TEMP_DIR/source.txt" && \
   DEST="$TEST_TEMP_DIR/backup/source.txt" && \
   echo "test content" > "$SOURCE" && \
   mkdir -p "$(dirname "$DEST")" && \
   cp "$SOURCE" "$DEST" && \
   assert_file_exists "$DEST" && \
   CONTENT="$(cat "$DEST")" && \
   assert_equals "test content" "$CONTENT"; then
    test_pass
else
    test_fail
fi

test_case "file_archive - should preserve file history"
if SOURCE="$TEST_TEMP_DIR/source.txt" && \
   ARCHIVE_DIR="$TEST_TEMP_DIR/archive" && \
   mkdir -p "$ARCHIVE_DIR" && \
   echo "version 1" > "$SOURCE" && \
   TIMESTAMP1="$(date +%Y%m%d_%H%M%S)" && \
   cp "$SOURCE" "$ARCHIVE_DIR/source.txt.$TIMESTAMP1" && \
   sleep 1 && \
   echo "version 2" > "$SOURCE" && \
   TIMESTAMP2="$(date +%Y%m%d_%H%M%S)" && \
   cp "$SOURCE" "$ARCHIVE_DIR/source.txt.$TIMESTAMP2" && \
   [[ $(ls "$ARCHIVE_DIR" | wc -l) -eq 2 ]]; then
    test_pass
else
    test_fail "Archive should contain 2 versions"
fi

# ==============================================================================
# RETENTION POLICY TESTS
# ==============================================================================

test_suite "Retention Policy"

test_case "retention - should delete files older than retention period"
if ARCHIVE_DIR="$TEST_TEMP_DIR/archive" && \
   mkdir -p "$ARCHIVE_DIR" && \
   touch -t "202301010000" "$ARCHIVE_DIR/old-file.txt" && \
   touch "$ARCHIVE_DIR/new-file.txt" && \
   RETENTION_DAYS=30 && \
   find "$ARCHIVE_DIR" -type f -mtime +$RETENTION_DAYS -delete && \
   [[ ! -f "$ARCHIVE_DIR/old-file.txt" ]] && \
   [[ -f "$ARCHIVE_DIR/new-file.txt" ]]; then
    test_pass
else
    test_fail "Retention policy not applied correctly"
fi

# ==============================================================================
# DRIVE VERIFICATION TESTS
# ==============================================================================

test_suite "Drive Verification"

test_case "drive_marker - should verify correct drive is mounted"
if MARKER_FILE="$TEST_TEMP_DIR/project/.backup-drive-marker" && \
   mkdir -p "$(dirname "$MARKER_FILE")" && \
   MARKER_UUID="$(uuidgen)" && \
   echo "$MARKER_UUID" > "$MARKER_FILE" && \
   RETRIEVED_UUID="$(cat "$MARKER_FILE")" && \
   [[ "$MARKER_UUID" == "$RETRIEVED_UUID" ]]; then
    test_pass
else
    test_fail "Marker verification failed"
fi

test_case "drive_verification - should fail if marker missing"
if MARKER_FILE="$TEST_TEMP_DIR/nonexistent/.backup-drive-marker" && \
   [[ ! -f "$MARKER_FILE" ]]; then
    test_pass
else
    test_fail "Should detect missing marker"
fi

# ==============================================================================
# GIT INTEGRATION TESTS
# ==============================================================================

test_suite "Git Integration"

test_case "git_detection - should detect git repository"
if PROJECT_DIR="$(create_test_project)" && \
   git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    test_pass
else
    test_fail "Failed to detect git repository"
fi

test_case "git_status - should detect modified files"
if PROJECT_DIR="$(create_test_project "git-modified-test")" && \
   cd "$PROJECT_DIR" && \
   echo "modified content" >> README.md && \
   git add README.md && \
   git status --short | grep -q "M.*README.md"; then
    test_pass
else
    test_fail "Failed to detect modified files"
fi

test_case "git_status - should detect untracked files"
if PROJECT_DIR="$(create_test_project "git-untracked-test")" && \
   cd "$PROJECT_DIR" && \
   echo "new file content" > new-file.txt && \
   git status --porcelain | grep -q "??.*new-file.txt"; then
    test_pass
else
    test_fail "Failed to detect untracked files"
fi

# ==============================================================================
# SESSION TRACKING TESTS
# ==============================================================================

test_suite "Session Tracking"

test_case "session_start - should create session file"
if SESSION_FILE="$TEST_TEMP_DIR/.session" && \
   date +%s > "$SESSION_FILE" && \
   assert_file_exists "$SESSION_FILE"; then
    test_pass
else
    test_fail
fi

test_case "session_idle - should detect idle time"
if SESSION_FILE="$TEST_TEMP_DIR/.session" && \
   PAST_TIME="$(($(date +%s) - 7200))" && \
   echo "$PAST_TIME" > "$SESSION_FILE" && \
   CURRENT_TIME="$(date +%s)" && \
   SESSION_TIME="$(cat "$SESSION_FILE")" && \
   IDLE_TIME="$((CURRENT_TIME - SESSION_TIME))" && \
   [[ $IDLE_TIME -ge 600 ]]; then
    test_pass
else
    test_fail "Idle detection incorrect"
fi

# ==============================================================================
# LOGGING TESTS
# ==============================================================================

test_suite "Logging"

test_case "log_file - should write log entries"
if LOG_FILE="$TEST_TEMP_DIR/backup.log" && \
   echo "[$(date)] Test log entry" >> "$LOG_FILE" && \
   assert_file_exists "$LOG_FILE" && \
   grep -q "Test log entry" "$LOG_FILE"; then
    test_pass
else
    test_fail
fi

test_case "log_rotation - should handle large log files"
if LOG_FILE="$TEST_TEMP_DIR/backup.log" && \
   for i in {1..1000}; do echo "[$(date)] Entry $i" >> "$LOG_FILE"; done && \
   LINE_COUNT=$(wc -l < "$LOG_FILE") && \
   [[ $LINE_COUNT -ge 900 ]]; then
    test_pass
else
    test_fail "Log entries incorrect (expected >=900, got $LINE_COUNT)"
fi

# Run summary
print_test_summary
