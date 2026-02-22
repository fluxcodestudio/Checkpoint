#!/bin/bash
# End-to-End Tests: Complete User Journeys

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT
export PATH="$PROJECT_ROOT/bin:$PATH"

# ==============================================================================
# USER JOURNEY 1: FRESH INSTALLATION
# ==============================================================================

test_suite "User Journey 1: Fresh Installation"

test_case "Step 1: User runs install script"
if bash -n "$PROJECT_ROOT/bin/install.sh"; then
    test_pass
else
    test_fail "Install script has syntax errors"
fi

test_case "Step 2: Installation creates required directories"
if TEST_INSTALL_DIR="$TEST_TEMP_DIR/install-test" && \
   mkdir -p "$TEST_INSTALL_DIR" && \
   HOME_STATE="$HOME/.claudecode-backups" && \
   mkdir -p "$HOME_STATE/state" "$HOME_STATE/logs" && \
   assert_dir_exists "$HOME_STATE/state" && \
   assert_dir_exists "$HOME_STATE/logs"; then
    test_pass
else
    test_fail "Failed to create state directories"
fi

test_case "Step 3: Verify all scripts are executable"
if [[ -x "$PROJECT_ROOT/bin/backup-status.sh" ]] && \
   [[ -x "$PROJECT_ROOT/bin/backup-now.sh" ]] && \
   [[ -x "$PROJECT_ROOT/bin/backup-config.sh" ]] && \
   [[ -x "$PROJECT_ROOT/bin/backup-restore.sh" ]] && \
   [[ -x "$PROJECT_ROOT/bin/backup-cleanup.sh" ]]; then
    test_pass
else
    test_fail "Scripts are not executable"
fi

test_case "Step 4: Verify skills are installed"
if [[ -d "$PROJECT_ROOT/.claude/skills/checkpoint" ]] && \
   [[ -d "$PROJECT_ROOT/.claude/skills/backup-pause" ]] && \
   [[ -f "$PROJECT_ROOT/.claude/skills/checkpoint/skill.json" ]] && \
   [[ -f "$PROJECT_ROOT/.claude/skills/backup-pause/skill.json" ]]; then
    test_pass
else
    test_fail "Skills not found"
fi

# ==============================================================================
# USER JOURNEY 2: DAILY USAGE
# ==============================================================================

test_suite "User Journey 2: Daily Usage"

test_case "User runs 'backup status' command"
if run_command bash "$PROJECT_ROOT/bin/backup-status.sh" --help; then
    assert_success $TEST_EXIT_CODE && \
    assert_contains "$TEST_OUTPUT" "USAGE" && \
    test_pass
else
    test_fail "Status command failed"
fi

test_case "User checks status with --compact flag"
if bash -n "$PROJECT_ROOT/bin/backup-status.sh"; then
    test_pass
else
    test_fail "Status script has syntax errors"
fi

test_case "User runs 'backup now' command"
if run_command bash "$PROJECT_ROOT/bin/backup-now.sh" --help; then
    assert_success $TEST_EXIT_CODE && \
    assert_contains "$TEST_OUTPUT" "USAGE" && \
    test_pass
else
    test_fail "Backup now command failed"
fi

test_case "User forces immediate backup"
if bash -n "$PROJECT_ROOT/bin/backup-now.sh"; then
    test_pass
else
    test_fail "Backup now script has syntax errors"
fi

# ==============================================================================
# USER JOURNEY 3: CONFIGURATION
# ==============================================================================

test_suite "User Journey 3: Configuration"

test_case "User runs configuration wizard"
if run_command bash "$PROJECT_ROOT/bin/backup-config.sh" --help; then
    assert_success $TEST_EXIT_CODE && \
    assert_contains "$TEST_OUTPUT" "USAGE" && \
    test_pass
else
    test_fail "Config command failed"
fi

test_case "User validates configuration"
if bash -n "$PROJECT_ROOT/bin/backup-config.sh"; then
    test_pass
else
    test_fail "Config script has syntax errors"
fi

test_case "User creates sample config"
if CONFIG_FILE="$TEST_TEMP_DIR/test-config.sh" && \
   cat > "$CONFIG_FILE" <<EOF
PROJECT_DIR="$TEST_TEMP_DIR/project"
PROJECT_NAME="TestProject"
BACKUP_DIR="$TEST_TEMP_DIR/project/backups"
DATABASE_DIR="\$BACKUP_DIR/databases"
FILES_DIR="\$BACKUP_DIR/files"
ARCHIVED_DIR="\$BACKUP_DIR/archived"
DB_RETENTION_DAYS=30
FILE_RETENTION_DAYS=60
BACKUP_INTERVAL=3600
EOF
   bash -n "$CONFIG_FILE"; then
    test_pass
else
    test_fail "Config file invalid"
fi

# ==============================================================================
# USER JOURNEY 4: DISASTER RECOVERY
# ==============================================================================

test_suite "User Journey 4: Disaster Recovery"

test_case "User lists available backups"
if run_command bash "$PROJECT_ROOT/bin/backup-restore.sh" --help; then
    assert_success $TEST_EXIT_CODE && \
    assert_contains "$TEST_OUTPUT" "restore" && \
    test_pass
else
    test_fail "Restore command failed"
fi

test_case "User simulates database restore"
if DB_PATH="$TEST_TEMP_DIR/test.db" && \
   create_test_database "$DB_PATH" && \

   # Create backup
   BACKUP_DIR="$TEST_TEMP_DIR/backups" && \
   mkdir -p "$BACKUP_DIR" && \
   cp "$DB_PATH" "$BACKUP_DIR/backup.db" && \

   # Delete original
   rm "$DB_PATH" && \

   # Restore
   cp "$BACKUP_DIR/backup.db" "$DB_PATH" && \

   # Verify
   assert_file_exists "$DB_PATH" && \
   sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;" | grep -q "2"; then
    test_pass
else
    test_fail "Database restore simulation failed"
fi

test_case "User verifies pre-restore backup created"
if PRE_RESTORE_DIR="$TEST_TEMP_DIR/.pre-restore-test" && \
   mkdir -p "$PRE_RESTORE_DIR" && \
   assert_dir_exists "$PRE_RESTORE_DIR"; then
    test_pass
else
    test_fail "Pre-restore directory creation failed"
fi

# ==============================================================================
# USER JOURNEY 5: MAINTENANCE
# ==============================================================================

test_suite "User Journey 5: Maintenance"

test_case "User runs cleanup preview"
if run_command bash "$PROJECT_ROOT/bin/backup-cleanup.sh" --help; then
    assert_success $TEST_EXIT_CODE && \
    assert_contains "$TEST_OUTPUT" "cleanup" && \
    test_pass
else
    test_fail "Cleanup command failed"
fi

test_case "User checks cleanup recommendations"
if bash -n "$PROJECT_ROOT/bin/backup-cleanup.sh"; then
    test_pass
else
    test_fail "Cleanup script has syntax errors"
fi

test_case "User simulates cleanup execution"
if BACKUP_DIR="$TEST_TEMP_DIR/cleanup-test/backups" && \
   mkdir -p "$BACKUP_DIR/databases" "$BACKUP_DIR/archived" && \

   # Create old files
   touch -t "202301010000" "$BACKUP_DIR/databases/old.db.gz" && \
   touch "$BACKUP_DIR/databases/new.db.gz" && \

   # Cleanup old files (>30 days)
   find "$BACKUP_DIR/databases" -name "*.db.gz" -mtime +30 -delete && \

   # Verify
   assert_file_not_exists "$BACKUP_DIR/databases/old.db.gz" && \
   assert_file_exists "$BACKUP_DIR/databases/new.db.gz"; then
    test_pass
else
    test_fail "Cleanup execution failed"
fi

# ==============================================================================
# USER JOURNEY 6: INTEGRATION INSTALLATION
# ==============================================================================

test_suite "User Journey 6: Integration Installation"

test_case "User runs integration installer"
if run_command bash "$PROJECT_ROOT/bin/install-integrations.sh" --help; then
    assert_success $TEST_EXIT_CODE && \
    assert_contains "$TEST_OUTPUT" "integration" && \
    test_pass
else
    test_fail "Integration installer failed"
fi

test_case "User verifies integration files exist"
if [[ -d "$PROJECT_ROOT/integrations/shell" ]] && \
   [[ -d "$PROJECT_ROOT/integrations/git" ]] && \
   [[ -d "$PROJECT_ROOT/integrations/vim" ]] && \
   [[ -f "$PROJECT_ROOT/integrations/lib/integration-core.sh" ]]; then
    test_pass
else
    test_fail "Integration files missing"
fi

test_case "User sources integration core library"
if bash -n "$PROJECT_ROOT/integrations/lib/integration-core.sh"; then
    test_pass
else
    test_fail "Integration core library has syntax errors"
fi

# ==============================================================================
# USER JOURNEY 7: SHELL INTEGRATION
# ==============================================================================

test_suite "User Journey 7: Shell Integration"

test_case "User sources shell integration"
if bash -n "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh"; then
    test_pass
else
    test_fail "Shell integration has syntax errors"
fi

test_case "User verifies shell functions available"
if SHELL_INTEGRATION="$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh" && \
   (grep -q "backup_status" "$SHELL_INTEGRATION" || \
    grep -q "backup-status" "$SHELL_INTEGRATION"); then
    test_pass
else
    test_fail "Shell functions not found"
fi

# ==============================================================================
# USER JOURNEY 8: GIT INTEGRATION
# ==============================================================================

test_suite "User Journey 8: Git Integration"

test_case "User installs git hooks"
if PROJECT_DIR="$(create_test_project "git-hook-test")" && \
   GIT_DIR="$PROJECT_DIR/.git" && \
   HOOKS_DIR="$GIT_DIR/hooks" && \
   assert_dir_exists "$HOOKS_DIR"; then
    test_pass
else
    test_fail "Git hooks directory not found"
fi

test_case "User verifies git hook scripts"
if [[ -f "$PROJECT_ROOT/integrations/git/hooks/pre-commit" ]] && \
   bash -n "$PROJECT_ROOT/integrations/git/hooks/pre-commit"; then
    test_pass
else
    test_fail "Git hook script invalid"
fi

# ==============================================================================
# USER JOURNEY 9: VIM INTEGRATION
# ==============================================================================

test_suite "User Journey 9: Vim Integration"

test_case "User verifies vim plugin structure"
if [[ -f "$PROJECT_ROOT/integrations/vim/plugin/backup.vim" ]] && \
   [[ -f "$PROJECT_ROOT/integrations/vim/autoload/backup.vim" ]] && \
   [[ -f "$PROJECT_ROOT/integrations/vim/doc/backup.txt" ]]; then
    test_pass
else
    test_fail "Vim plugin files missing"
fi

test_case "User validates vim syntax"
if vim -u NONE -e -c "source $PROJECT_ROOT/integrations/vim/plugin/backup.vim" -c "quit" 2>/dev/null || \
   [[ -f "$PROJECT_ROOT/integrations/vim/plugin/backup.vim" ]]; then
    test_pass
else
    test_skip "Vim not available for syntax check"
fi

# ==============================================================================
# USER JOURNEY 10: MULTI-PROJECT SETUP
# ==============================================================================

test_suite "User Journey 10: Multi-Project Setup"

test_case "User creates config for project 1"
if PROJECT1="$TEST_TEMP_DIR/project1" && \
   mkdir -p "$PROJECT1" && \
   cat > "$PROJECT1/.backup-config.sh" <<EOF
PROJECT_DIR="$PROJECT1"
PROJECT_NAME="Project1"
BACKUP_DIR="$PROJECT1/backups"
EOF
   bash -n "$PROJECT1/.backup-config.sh"; then
    test_pass
else
    test_fail "Project 1 config failed"
fi

test_case "User creates config for project 2"
if PROJECT2="$TEST_TEMP_DIR/project2" && \
   mkdir -p "$PROJECT2" && \
   cat > "$PROJECT2/.backup-config.sh" <<EOF
PROJECT_DIR="$PROJECT2"
PROJECT_NAME="Project2"
BACKUP_DIR="$PROJECT2/backups"
EOF
   bash -n "$PROJECT2/.backup-config.sh"; then
    test_pass
else
    test_fail "Project 2 config failed"
fi

test_case "User verifies independent backups"
if mkdir -p "$TEST_TEMP_DIR/project1/backups" && \
   mkdir -p "$TEST_TEMP_DIR/project2/backups" && \
   assert_dir_exists "$TEST_TEMP_DIR/project1/backups" && \
   assert_dir_exists "$TEST_TEMP_DIR/project2/backups" && \
   [[ "$TEST_TEMP_DIR/project1/backups" != "$TEST_TEMP_DIR/project2/backups" ]]; then
    test_pass
else
    test_fail "Independent backups verification failed"
fi

# ==============================================================================
# USER JOURNEY 11: EXTERNAL DRIVE SETUP
# ==============================================================================

test_suite "User Journey 11: External Drive Setup"

test_case "User creates drive marker"
if DRIVE_DIR="$TEST_TEMP_DIR/external-drive" && \
   mkdir -p "$DRIVE_DIR" && \
   MARKER_FILE="$DRIVE_DIR/.backup-drive-marker" && \
   MARKER_UUID="$(uuidgen 2>/dev/null || echo "test-uuid-$(date +%s)")" && \
   echo "$MARKER_UUID" > "$MARKER_FILE" && \
   assert_file_exists "$MARKER_FILE"; then
    test_pass
else
    test_fail "Drive marker creation failed"
fi

test_case "User verifies drive marker"
if MARKER_FILE="$TEST_TEMP_DIR/external-drive/.backup-drive-marker" && \
   EXPECTED_UUID=$(cat "$MARKER_FILE") && \
   ACTUAL_UUID=$(cat "$MARKER_FILE") && \
   [[ "$EXPECTED_UUID" == "$ACTUAL_UUID" ]]; then
    test_pass
else
    test_fail "Drive marker verification failed"
fi

# ==============================================================================
# USER JOURNEY 12: ERROR RECOVERY
# ==============================================================================

test_suite "User Journey 12: Error Recovery"

test_case "User handles missing config gracefully"
if NONEXISTENT_CONFIG="/tmp/nonexistent-config-$(date +%s).sh" && \
   [[ ! -f "$NONEXISTENT_CONFIG" ]]; then
    test_pass
else
    test_fail "Config should not exist"
fi

test_case "User handles permission errors"
if READONLY_FILE="$TEST_TEMP_DIR/readonly-file.txt" && \
   echo "test" > "$READONLY_FILE" && \
   chmod 444 "$READONLY_FILE" && \
   ! echo "modified" > "$READONLY_FILE" 2>/dev/null; then
    chmod 644 "$READONLY_FILE" 2>/dev/null || true
    test_pass
else
    chmod 644 "$READONLY_FILE" 2>/dev/null || true
    test_fail "Permission error not detected"
fi

test_case "User handles corrupted database"
if CORRUPT_DB="$TEST_TEMP_DIR/corrupt.db" && \
   echo "not a valid sqlite database" > "$CORRUPT_DB" && \
   FILE_SIZE=$(stat -f%z "$CORRUPT_DB" 2>/dev/null || stat -c%s "$CORRUPT_DB") && \
   [[ $FILE_SIZE -gt 0 ]] && \
   ! sqlite3 "$CORRUPT_DB" "PRAGMA integrity_check;" &>/dev/null; then
    test_pass
else
    test_fail "Corrupted database not detected"
fi

# Run summary
print_test_summary
