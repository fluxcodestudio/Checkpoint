#!/bin/bash
# Checkpoint - Testing Framework
# Lightweight testing framework for bash scripts (no external dependencies)

set -euo pipefail

# ==============================================================================
# TEST FRAMEWORK CORE
# ==============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_TEST_NAME=""
CURRENT_SUITE_NAME=""

# Test output capture
TEST_OUTPUT=""
TEST_EXIT_CODE=0

# Fixtures
TEST_TEMP_DIR=""
TEST_FIXTURES_DIR=""

# ==============================================================================
# ASSERTION FUNCTIONS
# ==============================================================================

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-"Expected '$expected', got '$actual'"}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        return 1
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-"Expected NOT '$expected', but got '$actual'"}"

    if [[ "$expected" != "$actual" ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-"Expected to contain '$needle'"}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        echo "  Haystack: $haystack"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-"Expected NOT to contain '$needle'"}"

    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-"Expected file to exist: $file"}"

    if [[ -f "$file" ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local message="${2:-"Expected file NOT to exist: $file"}"

    if [[ ! -f "$file" ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-"Expected directory to exist: $dir"}"

    if [[ -d "$dir" ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        return 1
    fi
}

assert_success() {
    local exit_code="${1:-$?}"
    local message="${2:-"Expected command to succeed (exit 0)"}"

    if [[ $exit_code -eq 0 ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message (exit code: $exit_code)"
        return 1
    fi
}

assert_failure() {
    local exit_code="${1:-$?}"
    local message="${2:-"Expected command to fail (exit non-zero)"}"

    if [[ $exit_code -ne 0 ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-"Expected exit code $expected, got $actual"}"

    if [[ $expected -eq $actual ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        return 1
    fi
}

assert_empty() {
    local value="$1"
    local message="${2:-"Expected empty value"}"

    if [[ -z "$value" ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message (got: '$value')"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-"Expected non-empty value"}"

    if [[ -n "$value" ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        return 1
    fi
}

assert_matches() {
    local text="$1"
    local pattern="$2"
    local message="${3:-"Expected to match pattern: $pattern"}"

    if [[ "$text" =~ $pattern ]]; then
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        echo "  Text: $text"
        return 1
    fi
}

# ==============================================================================
# TEST RUNNER FUNCTIONS
# ==============================================================================

test_suite() {
    CURRENT_SUITE_NAME="$1"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}Test Suite: $CURRENT_SUITE_NAME${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

test_case() {
    CURRENT_TEST_NAME="$1"
    ((TESTS_RUN++))

    echo -ne "  ${CYAN}▶${NC} $CURRENT_TEST_NAME ... "
}

test_pass() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}"
}

test_fail() {
    local message="${1:-}"
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}"
    if [[ -n "$message" ]]; then
        echo -e "    ${RED}$message${NC}"
    fi
}

test_skip() {
    local reason="${1:-No reason provided}"
    ((TESTS_SKIPPED++))
    echo -e "${YELLOW}⊘ SKIP${NC} ($reason)"
}

# ==============================================================================
# FIXTURE MANAGEMENT
# ==============================================================================

setup_test_env() {
    # Create temporary test directory
    TEST_TEMP_DIR="$(mktemp -d -t checkpoint-test-XXXXXX)"
    TEST_FIXTURES_DIR="$TEST_TEMP_DIR/fixtures"
    mkdir -p "$TEST_FIXTURES_DIR"

    # Export for tests to use
    export TEST_TEMP_DIR
    export TEST_FIXTURES_DIR
}

# Auto-setup on source (ensure TEST_TEMP_DIR is always set)
if [[ -z "${TEST_TEMP_DIR:-}" ]]; then
    setup_test_env
fi

teardown_test_env() {
    # Clean up temporary directory
    if [[ -n "$TEST_TEMP_DIR" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

create_test_project() {
    local project_name="${1:-test-project}"
    local project_dir="$TEST_TEMP_DIR/$project_name"

    mkdir -p "$project_dir"

    # Initialize git
    git -C "$project_dir" init -q
    git -C "$project_dir" config user.email "test@checkpoint.test"
    git -C "$project_dir" config user.name "Test User"

    # Create sample files
    echo "# Test Project" > "$project_dir/README.md"
    echo "console.log('test');" > "$project_dir/app.js"
    mkdir -p "$project_dir/src"
    echo "export const test = true;" > "$project_dir/src/lib.js"

    # Initial commit
    git -C "$project_dir" add .
    git -C "$project_dir" commit -q -m "Initial commit"

    echo "$project_dir"
}

create_test_database() {
    local db_path="$1"
    local db_dir="$(dirname "$db_path")"

    mkdir -p "$db_dir"

    # Create SQLite database
    sqlite3 "$db_path" <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT);
INSERT INTO users VALUES (1, 'Alice', 'alice@test.com');
INSERT INTO users VALUES (2, 'Bob', 'bob@test.com');
CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT, content TEXT);
INSERT INTO posts VALUES (1, 1, 'First Post', 'Hello World');
INSERT INTO posts VALUES (2, 2, 'Second Post', 'Testing');
EOF
}

# ==============================================================================
# COMMAND EXECUTION HELPERS
# ==============================================================================

run_command() {
    local output_file="$TEST_TEMP_DIR/.command_output"
    set +e
    "$@" > "$output_file" 2>&1
    TEST_EXIT_CODE=$?
    TEST_OUTPUT="$(cat "$output_file")"
    set -e
    return $TEST_EXIT_CODE
}

# ==============================================================================
# REPORTING
# ==============================================================================

print_test_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Test Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Total:   $TESTS_RUN"
    echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
    fi

    if [[ $TESTS_SKIPPED -gt 0 ]]; then
        echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    fi

    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
        echo ""
        return 1
    fi
}

# ==============================================================================
# MAIN TEST RUNNER
# ==============================================================================

run_test_file() {
    local test_file="$1"

    if [[ ! -f "$test_file" ]]; then
        echo -e "${RED}Error: Test file not found: $test_file${NC}"
        return 1
    fi

    # Setup
    setup_test_env

    # Source and run test file
    # shellcheck source=/dev/null
    source "$test_file"

    # Teardown
    teardown_test_env
}

run_all_tests() {
    local test_dir="$1"

    echo -e "${BOLD}Running all tests in: $test_dir${NC}"

    # Find all test files
    local test_files=()
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$test_dir" -name "test-*.sh" -print0 | sort -z)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No test files found${NC}"
        return 1
    fi

    # Run each test file
    for test_file in "${test_files[@]}"; do
        echo -e "\n${CYAN}Running: $(basename "$test_file")${NC}"
        run_test_file "$test_file"
    done

    # Print summary
    print_test_summary
}
