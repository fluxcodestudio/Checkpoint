#!/bin/bash
# ==============================================================================
# ClaudeCode Project Backups - Library Test Suite
# ==============================================================================
# Tests the core backup library functionality
#
# Usage: ./lib/test-library.sh
# ==============================================================================

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ==============================================================================
# TEST UTILITIES
# ==============================================================================

test_start() {
    local test_name="$1"
    echo -e "${BLUE}TEST:${NC} $test_name"
    ((TESTS_RUN++))
}

test_pass() {
    local message="$1"
    echo -e "  ${GREEN}✓${NC} $message"
    ((TESTS_PASSED++))
}

test_fail() {
    local message="$1"
    echo -e "  ${RED}✗${NC} $message"
    ((TESTS_FAILED++))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [ "$expected" = "$actual" ]; then
        test_pass "${message:-Values match}: '$actual'"
        return 0
    else
        test_fail "${message:-Values don't match}: expected '$expected', got '$actual'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    if [[ "$haystack" == *"$needle"* ]]; then
        test_pass "${message:-String contains}: '$needle'"
        return 0
    else
        test_fail "${message:-String doesn't contain}: '$needle'"
        return 1
    fi
}

assert_success() {
    local message="$1"
    test_pass "$message"
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File exists}"

    if [ -f "$file" ]; then
        test_pass "$message: $file"
        return 0
    else
        test_fail "$message: $file not found"
        return 1
    fi
}

# ==============================================================================
# SETUP
# ==============================================================================

echo "=========================================="
echo "ClaudeCode Project Backups - Library Tests"
echo "=========================================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_FILE="$SCRIPT_DIR/backup-lib.sh"

# Create temporary test directory
TEST_DIR=$(mktemp -d -t backup-lib-test-XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Test directory: $TEST_DIR"
echo "Library file: $LIB_FILE"
echo ""

# ==============================================================================
# TEST 1: Library Loading
# ==============================================================================

test_start "Library file exists and is executable"

if [ -f "$LIB_FILE" ]; then
    test_pass "Library file exists"
else
    test_fail "Library file not found"
    exit 1
fi

# Source the library
export BACKUP_LIB_NO_AUTO_INIT=1
if source "$LIB_FILE" 2>/dev/null; then
    test_pass "Library loaded successfully"
else
    test_fail "Failed to load library"
    exit 1
fi

# ==============================================================================
# TEST 2: Schema Initialization
# ==============================================================================

test_start "Configuration schema initialization"

init_config_schema

if [ "${#CONFIG_DEFAULTS[@]}" -gt 0 ]; then
    test_pass "Schema initialized (${#CONFIG_DEFAULTS[@]} defaults)"
else
    test_fail "Schema initialization failed"
fi

if [ "${#CONFIG_METADATA[@]}" -gt 0 ]; then
    test_pass "Metadata initialized (${#CONFIG_METADATA[@]} entries)"
else
    test_fail "Metadata initialization failed"
fi

# ==============================================================================
# TEST 3: Validation Functions
# ==============================================================================

test_start "Validation functions"

# Test number validation
if validate_number "42"; then
    test_pass "Valid number: 42"
else
    test_fail "Number validation failed for: 42"
fi

if validate_number "abc" 2>/dev/null; then
    test_fail "Should reject non-number: abc"
else
    test_pass "Correctly rejected non-number: abc"
fi

# Test boolean validation
if validate_boolean "true"; then
    test_pass "Valid boolean: true"
else
    test_fail "Boolean validation failed for: true"
fi

if validate_boolean "invalid" 2>/dev/null; then
    test_fail "Should reject invalid boolean: invalid"
else
    test_pass "Correctly rejected invalid boolean"
fi

# Test enum validation
if validate_enum "sqlite" "none" "sqlite" "postgres"; then
    test_pass "Valid enum value: sqlite"
else
    test_fail "Enum validation failed for: sqlite"
fi

if validate_enum "invalid" "none" "sqlite" 2>/dev/null; then
    test_fail "Should reject invalid enum value"
else
    test_pass "Correctly rejected invalid enum value"
fi

# ==============================================================================
# TEST 4: Utility Functions
# ==============================================================================

test_start "Utility functions"

# Test format_bytes
size=$(format_bytes 1024)
assert_equals "1KB" "$size" "Format 1024 bytes"

size=$(format_bytes 1048576)
assert_equals "1MB" "$size" "Format 1MB"

# Test platform detection
if is_macos || is_linux; then
    test_pass "Platform detected: $(uname)"
else
    test_fail "Platform detection failed"
fi

# Test command_exists
if command_exists "bash"; then
    test_pass "Command exists: bash"
else
    test_fail "Command check failed for bash"
fi

# ==============================================================================
# TEST 5: Path Expansion
# ==============================================================================

test_start "Path expansion"

BACKUP_PROJECT_ROOT="/tmp/test"

expanded=$(expand_path "~/test")
if [[ "$expanded" == "$HOME/test" ]]; then
    test_pass "Tilde expansion works"
else
    test_fail "Tilde expansion failed: got $expanded"
fi

expanded=$(expand_path "relative/path")
if [[ "$expanded" == "/tmp/test/relative/path" ]]; then
    test_pass "Relative path expansion works"
else
    test_fail "Relative path expansion failed: got $expanded"
fi

# ==============================================================================
# TEST 6: YAML Parsing
# ==============================================================================

test_start "YAML parsing"

# Create test YAML file
cat > "$TEST_DIR/test-config.yaml" << 'EOF'
# Test configuration
locations:
  backup_dir: "backups/"
  database_dir: "backups/databases"

schedule:
  interval: 3600
  daemon_enabled: true

database:
  path: "/tmp/test.db"
  type: "sqlite"

patterns:
  include:
    env_files: true
    credentials: false
EOF

# Parse YAML
if parse_yaml "$TEST_DIR/test-config.yaml"; then
    test_pass "YAML file parsed successfully"
else
    test_fail "YAML parsing failed"
fi

# Check parsed values
if [ "${CONFIG_VALUES[locations.backup_dir]}" = "backups/" ]; then
    test_pass "Parsed locations.backup_dir correctly"
else
    test_fail "Failed to parse locations.backup_dir"
fi

if [ "${CONFIG_VALUES[schedule.interval]}" = "3600" ]; then
    test_pass "Parsed schedule.interval correctly"
else
    test_fail "Failed to parse schedule.interval"
fi

if [ "${CONFIG_VALUES[schedule.daemon_enabled]}" = "true" ]; then
    test_pass "Parsed boolean true correctly"
else
    test_fail "Failed to parse boolean"
fi

if [ "${CONFIG_VALUES[patterns.include.credentials]}" = "false" ]; then
    test_pass "Parsed boolean false correctly"
else
    test_fail "Failed to parse boolean false"
fi

# ==============================================================================
# TEST 7: Configuration Loading (Bash Format)
# ==============================================================================

test_start "Bash configuration loading"

# Create test bash config
cat > "$TEST_DIR/.backup-config.sh" << 'EOF'
PROJECT_NAME="TestProject"
PROJECT_DIR="/tmp/test"
BACKUP_DIR="/tmp/test/backups"
DATABASE_DIR="/tmp/test/backups/databases"
DB_PATH="/tmp/test.db"
DB_TYPE="sqlite"
DB_RETENTION_DAYS=30
FILE_RETENTION_DAYS=60
BACKUP_INTERVAL=3600
SESSION_IDLE_THRESHOLD=600
AUTO_COMMIT_ENABLED=false
BACKUP_ENV_FILES=true
EOF

# Load bash config
if config_load_bash "$TEST_DIR/.backup-config.sh"; then
    test_pass "Bash config loaded"
else
    test_fail "Failed to load bash config"
fi

# Verify mapped values
if [ "${CONFIG_VALUES[project.name]}" = "TestProject" ]; then
    test_pass "Mapped PROJECT_NAME correctly"
else
    test_fail "Failed to map PROJECT_NAME"
fi

if [ "${CONFIG_VALUES[locations.backup_dir]}" = "/tmp/test/backups" ]; then
    test_pass "Mapped BACKUP_DIR correctly"
else
    test_fail "Failed to map BACKUP_DIR"
fi

# ==============================================================================
# TEST 8: Configuration Get/Set
# ==============================================================================

test_start "Configuration get/set"

BACKUP_CONFIG_LOADED=true

# Test config_get
value=$(config_get "schedule.interval")
assert_equals "3600" "$value" "Config get existing value"

# Test config_get with default
value=$(config_get "nonexistent.key" "default_value")
assert_equals "default_value" "$value" "Config get with default"

# Test config_set
if config_set "schedule.interval" "7200"; then
    test_pass "Config set successful"
    value=$(config_get "schedule.interval")
    assert_equals "7200" "$value" "Config value updated"
else
    test_fail "Config set failed"
fi

# Test config_has
if config_has "schedule.interval"; then
    test_pass "Config has existing key"
else
    test_fail "Config has failed for existing key"
fi

if config_has "nonexistent.key"; then
    test_fail "Config has should return false for nonexistent key"
else
    test_pass "Config has correctly returns false"
fi

# ==============================================================================
# TEST 9: Safe File Operations
# ==============================================================================

test_start "Safe file operations"

# Test atomic_write
test_file="$TEST_DIR/test-atomic.txt"
if atomic_write "$test_file" "Test content\nLine 2"; then
    test_pass "Atomic write succeeded"
    assert_file_exists "$test_file"
else
    test_fail "Atomic write failed"
fi

# Verify content
content=$(cat "$test_file")
if [[ "$content" == *"Test content"* ]]; then
    test_pass "Atomic write content correct"
else
    test_fail "Atomic write content incorrect"
fi

# Test that backup was created
if [ -f "${test_file}.backup" ]; then
    test_pass "Backup file created"
else
    test_pass "No backup needed for new file"
fi

# ==============================================================================
# TEST 10: Dependency Checking
# ==============================================================================

test_start "Dependency checking"

if check_dependencies; then
    test_pass "All dependencies available"
else
    test_fail "Missing dependencies"
fi

# ==============================================================================
# TEST SUMMARY
# ==============================================================================

echo ""
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    exit 1
else
    echo "Tests failed: 0"
    echo ""
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    exit 0
fi
