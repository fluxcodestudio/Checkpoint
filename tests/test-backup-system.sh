#!/bin/bash
# ClaudeCode Project Backups - Test Suite
# Comprehensive tests for backup system functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_PROJECT="/tmp/test-backup-project-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

# ==============================================================================
# TEST HELPERS
# ==============================================================================

test_start() {
    echo -n "Testing: $1 ... "
}

test_pass() {
    echo -e "${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}FAIL${NC}"
    echo "  Error: $1"
    ((TESTS_FAILED++))
}

cleanup() {
    echo ""
    echo "Cleaning up test project..."
    rm -rf "$TEST_PROJECT"

    # Remove test LaunchAgent if exists
    test_plist="$HOME/Library/LaunchAgents/com.claudecode.backup.TestProject.plist"
    if [ -f "$test_plist" ]; then
        launchctl unload "$test_plist" 2>/dev/null || true
        rm "$test_plist"
    fi
}

trap cleanup EXIT

# ==============================================================================
# SETUP TEST PROJECT
# ==============================================================================

echo "═══════════════════════════════════════════════"
echo "ClaudeCode Project Backups - Test Suite"
echo "═══════════════════════════════════════════════"
echo ""
echo "Setting up test project: $TEST_PROJECT"

mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Initialize git
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

# Create test files
mkdir -p src tests
echo "print('Hello World')" > src/app.py
echo "# Test Suite" > tests/test_app.py
echo "# README" > README.md
echo "API_KEY=secret123" > .env
touch credentials.json

git add src/ tests/ README.md
git commit -m "Initial commit" -q

echo "✅ Test project created"
echo ""

# ==============================================================================
# TEST 1: Installation
# ==============================================================================

test_start "Installation script exists and is executable"
if [ -x "$PACKAGE_DIR/bin/install.sh" ]; then
    test_pass
else
    test_fail "install.sh not found or not executable"
fi

test_start "Configuration template exists"
if [ -f "$PACKAGE_DIR/templates/backup-config.sh" ]; then
    test_pass
else
    test_fail "backup-config.sh template not found"
fi

test_start "Backup daemon script exists"
if [ -x "$PACKAGE_DIR/bin/backup-daemon.sh" ]; then
    test_pass
else
    test_fail "backup-daemon.sh not found or not executable"
fi

# ==============================================================================
# TEST 2: Configuration Creation
# ==============================================================================

test_start "Create test configuration"

cat > "$TEST_PROJECT/.backup-config.sh" << 'EOF'
PROJECT_DIR="$PWD"
PROJECT_NAME="TestProject"

BACKUP_DIR="$PROJECT_DIR/backups"
DATABASE_DIR="$BACKUP_DIR/databases"
FILES_DIR="$BACKUP_DIR/files"
ARCHIVED_DIR="$BACKUP_DIR/archived"

DB_PATH=""
DB_TYPE="none"

DB_RETENTION_DAYS=7
FILE_RETENTION_DAYS=14

BACKUP_INTERVAL=3600
SESSION_IDLE_THRESHOLD=600

DRIVE_VERIFICATION_ENABLED=false
DRIVE_MARKER_FILE=""

AUTO_COMMIT_ENABLED=false

BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=false
BACKUP_LOCAL_NOTES=false
BACKUP_LOCAL_DATABASES=false

LOG_FILE="$BACKUP_DIR/backup.log"
FALLBACK_LOG="$HOME/.claudecode-backups/logs/backup-fallback.log"

STATE_DIR="$HOME/.claudecode-backups/state"
BACKUP_TIME_STATE="$STATE_DIR/.last-backup-time"
SESSION_FILE="$STATE_DIR/.current-session-time"
DB_STATE_FILE="$BACKUP_DIR/.backup-state"
EOF

if [ -f ".backup-config.sh" ]; then
    test_pass
else
    test_fail "Failed to create configuration"
fi

# ==============================================================================
# TEST 3: Script Installation
# ==============================================================================

test_start "Install backup daemon"

mkdir -p .claude/hooks
cp "$PACKAGE_DIR/bin/backup-daemon.sh" .claude/backup-daemon.sh
chmod +x .claude/backup-daemon.sh

if [ -x ".claude/backup-daemon.sh" ]; then
    test_pass
else
    test_fail "Failed to install backup daemon"
fi

test_start "Install backup trigger hook"

cp "$PACKAGE_DIR/bin/smart-backup-trigger.sh" .claude/hooks/backup-trigger.sh
chmod +x .claude/hooks/backup-trigger.sh

if [ -x ".claude/hooks/backup-trigger.sh" ]; then
    test_pass
else
    test_fail "Failed to install backup trigger"
fi

# ==============================================================================
# TEST 4: First Backup
# ==============================================================================

test_start "Run first backup"

./.claude/backup-daemon.sh > /dev/null 2>&1

if [ -d "backups" ]; then
    test_pass
else
    test_fail "Backup directory not created"
fi

test_start "Backup directory structure created"

if [ -d "backups/databases" ] && [ -d "backups/files" ] && [ -d "backups/archived" ]; then
    test_pass
else
    test_fail "Backup subdirectories not created"
fi

test_start "Files backed up"

if [ -f "backups/files/src/app.py" ] && [ -f "backups/files/README.md" ]; then
    test_pass
else
    test_fail "Files not backed up"
fi

test_start "Critical files backed up (.env)"

if [ -f "backups/files/.env" ]; then
    test_pass
else
    test_fail ".env file not backed up"
fi

test_start "Backup log created"

if [ -f "backups/backup.log" ]; then
    test_pass
else
    test_fail "backup.log not created"
fi

# ==============================================================================
# TEST 5: File Change Detection
# ==============================================================================

test_start "Modify file and detect change"

echo "print('Updated')" > src/app.py
./.claude/backup-daemon.sh > /dev/null 2>&1

if [ -f "backups/files/src/app.py" ]; then
    content=$(cat backups/files/src/app.py)
    if [ "$content" = "print('Updated')" ]; then
        test_pass
    else
        test_fail "File content not updated"
    fi
else
    test_fail "Changed file not backed up"
fi

test_start "Old version archived"

archived_count=$(find backups/archived -name "app.py.*" 2>/dev/null | wc -l | tr -d ' ')
if [ "$archived_count" -gt 0 ]; then
    test_pass
else
    test_fail "Old version not archived"
fi

# ==============================================================================
# TEST 6: Unchanged File Detection
# ==============================================================================

test_start "Skip unchanged files"

# Run backup again without changes
./.claude/backup-daemon.sh > /dev/null 2>&1

# Should still only have 1 archived version
archived_count=$(find backups/archived -name "app.py.*" 2>/dev/null | wc -l | tr -d ' ')
if [ "$archived_count" -eq 1 ]; then
    test_pass
else
    test_fail "Created duplicate archived version for unchanged file"
fi

# ==============================================================================
# TEST 7: Coordination State
# ==============================================================================

test_start "State file created"

if [ -f "$HOME/.claudecode-backups/state/.last-backup-time" ]; then
    test_pass
else
    test_fail "State file not created"
fi

test_start "State file contains timestamp"

if [ -s "$HOME/.claudecode-backups/state/.last-backup-time" ]; then
    timestamp=$(cat "$HOME/.claudecode-backups/state/.last-backup-time")
    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        test_pass
    else
        test_fail "State file contains invalid timestamp"
    fi
else
    test_fail "State file is empty"
fi

# ==============================================================================
# TEST 8: Backup Skipping (Coordination)
# ==============================================================================

test_start "Skip backup when recently run"

# Backup should skip (< 1 hour since last)
output=$(./.claude/backup-daemon.sh 2>&1)

if echo "$output" | grep -q "skipping"; then
    test_pass
else
    test_fail "Did not skip recent backup"
fi

# ==============================================================================
# TEST 9: Utilities
# ==============================================================================

test_start "Status script exists"

if [ -x "$PACKAGE_DIR/bin/status.sh" ]; then
    test_pass
else
    test_fail "status.sh not found"
fi

test_start "Restore script exists"

if [ -x "$PACKAGE_DIR/bin/restore.sh" ]; then
    test_pass
else
    test_fail "restore.sh not found"
fi

test_start "Uninstall script exists"

if [ -x "$PACKAGE_DIR/bin/uninstall.sh" ]; then
    test_pass
else
    test_fail "uninstall.sh not found"
fi

# ==============================================================================
# TEST 10: Backup Trigger Hook
# ==============================================================================

test_start "Backup trigger hook runs"

output=$(./.claude/hooks/backup-trigger.sh 2>&1; echo $?)

if [ "$output" = "0" ]; then
    test_pass
else
    test_fail "Backup trigger hook failed"
fi

# ==============================================================================
# TEST 11: Gitignore Patterns
# ==============================================================================

test_start "Backups directory not in git"

git status --porcelain | grep -q "backups/" || status_ok=true

if [ "$status_ok" = true ]; then
    test_pass
else
    test_fail "Backups directory tracked by git"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

echo ""
echo "═══════════════════════════════════════════════"
echo "Test Results"
echo "═══════════════════════════════════════════════"
echo ""
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
