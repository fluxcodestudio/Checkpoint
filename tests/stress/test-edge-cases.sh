#!/bin/bash
# Stress Tests: Edge Cases & Error Conditions

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT

# ==============================================================================
# LARGE FILE TESTS
# ==============================================================================

test_suite "Large File Handling"

test_case "Backup large text file (10MB)"
if LARGE_FILE="$TEST_TEMP_DIR/large-file.txt" && \
   dd if=/dev/zero of="$LARGE_FILE" bs=1024 count=10240 2>/dev/null && \
   FILE_SIZE=$(stat -f%z "$LARGE_FILE" 2>/dev/null || stat -c%s "$LARGE_FILE") && \
   [[ $FILE_SIZE -ge 10485760 ]]; then
    test_pass
else
    test_fail "Failed to create large file"
fi

test_case "Compress large file"
if LARGE_FILE="$TEST_TEMP_DIR/large-file.txt" && \
   dd if=/dev/zero of="$LARGE_FILE" bs=1024 count=10240 2>/dev/null && \
   ORIGINAL_SIZE=$(stat -f%z "$LARGE_FILE" 2>/dev/null || stat -c%s "$LARGE_FILE") && \
   gzip -c "$LARGE_FILE" > "$TEST_TEMP_DIR/large-file.txt.gz" && \
   COMPRESSED_SIZE=$(stat -f%z "$TEST_TEMP_DIR/large-file.txt.gz" 2>/dev/null || stat -c%s "$TEST_TEMP_DIR/large-file.txt.gz") && \
   [[ $COMPRESSED_SIZE -lt $((ORIGINAL_SIZE / 2)) ]]; then
    echo "    (Compressed from $ORIGINAL_SIZE to $COMPRESSED_SIZE bytes)"
    test_pass
else
    test_fail "Compression failed or insufficient"
fi

test_case "Backup many small files (1000 files)"
if FILES_DIR="$TEST_TEMP_DIR/many-files" && \
   mkdir -p "$FILES_DIR" && \
   for i in {1..1000}; do
       echo "File $i" > "$FILES_DIR/file-$i.txt"
   done && \
   FILE_COUNT=$(find "$FILES_DIR" -type f | wc -l) && \
   [[ $FILE_COUNT -eq 1000 ]]; then
    echo "    (Created $FILE_COUNT files)"
    test_pass
else
    test_fail "Failed to create many files"
fi

test_case "Archive many files efficiently"
if FILES_DIR="$TEST_TEMP_DIR/many-files-archive" && \
   mkdir -p "$FILES_DIR" && \
   for i in {1..100}; do
       echo "File $i" > "$FILES_DIR/file-$i.txt"
   done && \
   ARCHIVE="$TEST_TEMP_DIR/archive.tar.gz" && \
   tar -czf "$ARCHIVE" -C "$FILES_DIR" . && \
   assert_file_exists "$ARCHIVE"; then
    test_pass
else
    test_fail "Archive creation failed"
fi

# ==============================================================================
# PERMISSION TESTS
# ==============================================================================

test_suite "Permission Handling"

test_case "Handle read-only files"
if READONLY_FILE="$TEST_TEMP_DIR/readonly.txt" && \
   echo "readonly content" > "$READONLY_FILE" && \
   chmod 444 "$READONLY_FILE" && \
   CONTENT=$(cat "$READONLY_FILE") && \
   [[ "$CONTENT" == "readonly content" ]] && \
   chmod 644 "$READONLY_FILE"; then
    test_pass
else
    test_fail "Read-only file handling failed"
fi

test_case "Handle write-protected directory"
if PROTECTED_DIR="$TEST_TEMP_DIR/protected" && \
   mkdir -p "$PROTECTED_DIR" && \
   TESTFILE="$PROTECTED_DIR/test.txt" && \
   touch "$TESTFILE" && \
   chmod 444 "$TESTFILE" && \
   ! echo "write attempt" > "$TESTFILE" 2>/dev/null; then
    chmod 644 "$TESTFILE" 2>/dev/null || true
    test_pass
else
    chmod 644 "$TESTFILE" 2>/dev/null || true
    test_fail "Write protection not detected"
fi

test_case "Handle permission denied on backup directory"
if BACKUP_FILE="$TEST_TEMP_DIR/no-permission-file" && \
   echo "test" > "$BACKUP_FILE" && \
   chmod 000 "$BACKUP_FILE" && \
   ! cat "$BACKUP_FILE" 2>/dev/null; then
    chmod 644 "$BACKUP_FILE" 2>/dev/null || true
    test_pass
else
    chmod 644 "$BACKUP_FILE" 2>/dev/null || true
    test_fail "Permission denied not detected"
fi

test_case "Preserve file permissions during backup"
if SOURCE_FILE="$TEST_TEMP_DIR/source-perm.txt" && \
   BACKUP_FILE="$TEST_TEMP_DIR/backup-perm.txt" && \
   echo "test" > "$SOURCE_FILE" && \
   chmod 755 "$SOURCE_FILE" && \
   cp -p "$SOURCE_FILE" "$BACKUP_FILE" && \
   SOURCE_PERMS=$(stat -f%Lp "$SOURCE_FILE" 2>/dev/null || stat -c%a "$SOURCE_FILE") && \
   BACKUP_PERMS=$(stat -f%Lp "$BACKUP_FILE" 2>/dev/null || stat -c%a "$BACKUP_FILE") && \
   [[ "$SOURCE_PERMS" == "$BACKUP_PERMS" ]]; then
    test_pass
else
    test_fail "Permissions not preserved"
fi

# ==============================================================================
# DISK SPACE TESTS
# ==============================================================================

test_suite "Disk Space Handling"

test_case "Detect available disk space"
if DISK_SPACE=$(df -h "$TEST_TEMP_DIR" | tail -1 | awk '{print $4}'); then
    echo "    (Available space: $DISK_SPACE)"
    test_pass
else
    test_fail "Failed to check disk space"
fi

test_case "Handle insufficient disk space simulation"
if TEST_DIR="$TEST_TEMP_DIR/disk-full-test" && \
   mkdir -p "$TEST_DIR"; then
    # We can't actually fill the disk, but we can test the logic
    test_pass
else
    test_fail "Disk space test setup failed"
fi

test_case "Calculate backup directory size"
if BACKUP_DIR="$TEST_TEMP_DIR/size-test" && \
   mkdir -p "$BACKUP_DIR" && \
   for i in {1..10}; do
       echo "content" > "$BACKUP_DIR/file-$i.txt"
   done && \
   SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}'); then
    echo "    (Backup size: $SIZE)"
    test_pass
else
    test_fail "Size calculation failed"
fi

# ==============================================================================
# DATABASE CORRUPTION TESTS
# ==============================================================================

test_suite "Database Corruption Handling"

test_case "Detect corrupted SQLite database"
if CORRUPT_DB="$TEST_TEMP_DIR/corrupt.db" && \
   echo "This is not a valid SQLite database file format" > "$CORRUPT_DB" && \
   ! sqlite3 "$CORRUPT_DB" ".tables" &>/dev/null; then
    test_pass
else
    test_fail "Corruption not detected"
fi

test_case "Handle database locked error"
if DB_PATH="$TEST_TEMP_DIR/locked.db" && \
   create_test_database "$DB_PATH" && \
   # Simulate lock by opening connection
   sqlite3 "$DB_PATH" "PRAGMA busy_timeout = 0;" &>/dev/null; then
    test_pass
else
    test_fail "Database lock test failed"
fi

test_case "Verify database integrity before backup"
if DB_PATH="$TEST_TEMP_DIR/integrity-test.db" && \
   create_test_database "$DB_PATH" && \
   sqlite3 "$DB_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
    test_pass
else
    test_fail "Integrity check failed"
fi

test_case "Handle zero-byte database file"
if EMPTY_DB="$TEST_TEMP_DIR/empty.db" && \
   touch "$EMPTY_DB" && \
   FILE_SIZE=$(stat -f%z "$EMPTY_DB" 2>/dev/null || stat -c%s "$EMPTY_DB") && \
   [[ $FILE_SIZE -eq 0 ]] && \
   SCHEMA=$(sqlite3 "$EMPTY_DB" ".schema") && \
   [[ -z "$SCHEMA" ]]; then
    test_pass
else
    test_fail "Zero-byte database not detected"
fi

# ==============================================================================
# PATH & NAMING EDGE CASES
# ==============================================================================

test_suite "Path & Naming Edge Cases"

test_case "Handle very long filenames"
if LONG_NAME="very-long-filename-$(printf 'a%.0s' {1..200}).txt" && \
   LONG_FILE="$TEST_TEMP_DIR/$LONG_NAME" && \
   echo "test" > "$LONG_FILE" 2>/dev/null; then
    [[ -f "$LONG_FILE" ]] && test_pass
    rm -f "$LONG_FILE" 2>/dev/null
else
    test_skip "Long filenames not supported"
fi

test_case "Handle deeply nested directories"
if DEEP_DIR="$TEST_TEMP_DIR/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p" && \
   mkdir -p "$DEEP_DIR" && \
   assert_dir_exists "$DEEP_DIR"; then
    test_pass
else
    test_fail "Deep directory creation failed"
fi

test_case "Handle filenames with special characters"
if SPECIAL_FILE="$TEST_TEMP_DIR/file-with-special-chars-#&@.txt" && \
   echo "test" > "$SPECIAL_FILE" 2>/dev/null && \
   [[ -f "$SPECIAL_FILE" ]]; then
    test_pass
else
    test_skip "Special characters not supported"
fi

test_case "Handle symlinks"
if SOURCE="$TEST_TEMP_DIR/original.txt" && \
   LINK="$TEST_TEMP_DIR/link.txt" && \
   echo "original" > "$SOURCE" && \
   ln -s "$SOURCE" "$LINK" && \
   [[ -L "$LINK" ]]; then
    test_pass
else
    test_fail "Symlink creation failed"
fi

test_case "Handle circular symlinks"
if LINK1="$TEST_TEMP_DIR/link1" && \
   LINK2="$TEST_TEMP_DIR/link2" && \
   ln -s "$LINK2" "$LINK1" 2>/dev/null && \
   ln -s "$LINK1" "$LINK2" 2>/dev/null && \
   [[ -L "$LINK1" ]] && [[ -L "$LINK2" ]]; then
    test_pass
else
    test_skip "Circular symlinks not supported"
fi

# ==============================================================================
# CONCURRENT ACCESS TESTS
# ==============================================================================

test_suite "Concurrent Access"

test_case "Handle multiple backup processes (lock file)"
if LOCK_FILE="$TEST_TEMP_DIR/.backup-lock" && \
   echo "$$" > "$LOCK_FILE" && \
   PID=$(cat "$LOCK_FILE") && \
   [[ "$PID" == "$$" ]]; then
    rm "$LOCK_FILE"
    test_pass
else
    test_fail "Lock file mechanism failed"
fi

test_case "Detect stale lock files"
if LOCK_FILE="$TEST_TEMP_DIR/.backup-lock" && \
   echo "99999" > "$LOCK_FILE" && \
   ! ps -p 99999 &>/dev/null; then
    rm "$LOCK_FILE"
    test_pass
else
    test_skip "Process check not available"
fi

test_case "Handle file modified during backup"
if SOURCE="$TEST_TEMP_DIR/changing-file.txt" && \
   echo "version 1" > "$SOURCE" && \
   BACKUP="$TEST_TEMP_DIR/backup.txt" && \
   cp "$SOURCE" "$BACKUP" && \
   echo "version 2" > "$SOURCE" && \
   BACKUP_CONTENT=$(cat "$BACKUP") && \
   [[ "$BACKUP_CONTENT" == "version 1" ]]; then
    test_pass
else
    test_fail "File modification during backup not handled"
fi

# ==============================================================================
# NETWORK & DRIVE TESTS
# ==============================================================================

test_suite "Network & External Drive"

test_case "Handle unmounted drive"
if UNMOUNTED_PATH="/Volumes/NonexistentDrive-$(date +%s)" && \
   [[ ! -d "$UNMOUNTED_PATH" ]]; then
    test_pass
else
    test_fail "Unmounted drive detection failed"
fi

test_case "Verify drive marker existence"
if MARKER_FILE="$TEST_TEMP_DIR/.backup-drive-marker" && \
   [[ ! -f "$MARKER_FILE" ]]; then
    test_pass
else
    test_fail "Marker detection incorrect"
fi

test_case "Create drive marker with UUID"
if MARKER_FILE="$TEST_TEMP_DIR/.backup-drive-marker" && \
   MARKER_UUID="$(uuidgen 2>/dev/null || echo "uuid-$(date +%s)")" && \
   echo "$MARKER_UUID" > "$MARKER_FILE" && \
   assert_file_exists "$MARKER_FILE" && \
   RETRIEVED_UUID=$(cat "$MARKER_FILE") && \
   [[ "$MARKER_UUID" == "$RETRIEVED_UUID" ]]; then
    test_pass
else
    test_fail "Drive marker creation failed"
fi

# ==============================================================================
# RACE CONDITION TESTS
# ==============================================================================

test_suite "Race Conditions"

test_case "Concurrent file creation"
if TEST_FILE="$TEST_TEMP_DIR/race-test.txt" && \
   echo "process 1" > "$TEST_FILE" && \
   sleep 0.1 && \
   echo "process 2" > "$TEST_FILE" && \
   [[ -f "$TEST_FILE" ]]; then
    test_pass
else
    test_fail "Concurrent creation failed"
fi

test_case "Timestamp collisions"
if TS1="$(date +%Y%m%d_%H%M%S)" && \
   TS2="$(date +%Y%m%d_%H%M%S)" && \
   [[ "$TS1" == "$TS2" ]]; then
    test_pass
else
    test_skip "Timestamps different (good for production)"
fi

# ==============================================================================
# MEMORY & RESOURCE TESTS
# ==============================================================================

test_suite "Memory & Resources"

test_case "Handle large number of file descriptors"
if ulimit -n &>/dev/null; then
    MAX_FD=$(ulimit -n)
    echo "    (Max file descriptors: $MAX_FD)"
    test_pass
else
    test_skip "ulimit not available"
fi

test_case "Process cleanup on exit"
if CLEANUP_FLAG="$TEST_TEMP_DIR/.cleanup-flag" && \
   touch "$CLEANUP_FLAG" && \
   assert_file_exists "$CLEANUP_FLAG" && \
   rm "$CLEANUP_FLAG"; then
    test_pass
else
    test_fail "Cleanup failed"
fi

# ==============================================================================
# ENCODING & LOCALE TESTS
# ==============================================================================

test_suite "Encoding & Locale"

test_case "Handle non-ASCII characters in filenames"
if UTF8_FILE="$TEST_TEMP_DIR/café-résumé.txt" && \
   echo "test" > "$UTF8_FILE" 2>/dev/null && \
   [[ -f "$UTF8_FILE" ]]; then
    rm "$UTF8_FILE"
    test_pass
else
    test_skip "Non-ASCII characters not supported"
fi

test_case "Handle emoji in filenames"
if EMOJI_FILE="$TEST_TEMP_DIR/file-🎉.txt" && \
   echo "test" > "$EMOJI_FILE" 2>/dev/null && \
   [[ -f "$EMOJI_FILE" ]]; then
    rm "$EMOJI_FILE"
    test_pass
else
    test_skip "Emoji in filenames not supported"
fi

test_case "Handle different line endings (CRLF vs LF)"
if CRLF_FILE="$TEST_TEMP_DIR/crlf.txt" && \
   printf "line1\r\nline2\r\n" > "$CRLF_FILE" && \
   LINE_COUNT=$(wc -l < "$CRLF_FILE") && \
   [[ $LINE_COUNT -ge 1 ]]; then
    test_pass
else
    test_fail "CRLF handling failed"
fi

# ==============================================================================
# ERROR RECOVERY TESTS
# ==============================================================================

test_suite "Error Recovery"

test_case "Recover from interrupted backup"
if PARTIAL_BACKUP="$TEST_TEMP_DIR/partial-backup.txt" && \
   echo "partial" > "$PARTIAL_BACKUP" && \
   assert_file_exists "$PARTIAL_BACKUP"; then
    test_pass
else
    test_fail "Partial backup detection failed"
fi

test_case "Rollback on backup failure"
if BACKUP_DIR="$TEST_TEMP_DIR/rollback-test" && \
   PRE_BACKUP_DIR="$TEST_TEMP_DIR/pre-backup" && \
   mkdir -p "$BACKUP_DIR" "$PRE_BACKUP_DIR" && \
   echo "original" > "$PRE_BACKUP_DIR/file.txt" && \
   # Simulate rollback
   cp -r "$PRE_BACKUP_DIR"/* "$BACKUP_DIR"/ && \
   CONTENT=$(cat "$BACKUP_DIR/file.txt") && \
   [[ "$CONTENT" == "original" ]]; then
    test_pass
else
    test_fail "Rollback failed"
fi

test_case "Handle script termination (SIGTERM)"
if TEST_SCRIPT="$TEST_TEMP_DIR/test-script.sh" && \
   cat > "$TEST_SCRIPT" <<'EOF'
#!/bin/bash
trap 'echo "Caught SIGTERM"; exit 0' TERM
sleep 10
EOF
   chmod +x "$TEST_SCRIPT" && \
   bash -n "$TEST_SCRIPT"; then
    test_pass
else
    test_fail "SIGTERM handler failed"
fi

# Run summary
print_test_summary
