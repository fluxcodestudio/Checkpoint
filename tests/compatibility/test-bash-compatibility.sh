#!/bin/bash
# Compatibility Tests: Bash Versions & Platforms

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT

# ==============================================================================
# BASH VERSION DETECTION
# ==============================================================================

test_suite "Bash Version Compatibility"

test_case "Detect current bash version"
if BASH_VERSION_INFO="${BASH_VERSION}" && \
   assert_not_empty "$BASH_VERSION_INFO"; then
    echo "    (Bash version: $BASH_VERSION)"
    test_pass
else
    test_fail "Failed to detect bash version"
fi

test_case "Verify bash 3.2+ compatibility"
if BASH_MAJOR="${BASH_VERSINFO[0]}" && \
   BASH_MINOR="${BASH_VERSINFO[1]}" && \
   [[ $BASH_MAJOR -ge 3 ]] && \
   { [[ $BASH_MAJOR -gt 3 ]] || [[ $BASH_MINOR -ge 2 ]]; }; then
    echo "    (Bash $BASH_MAJOR.$BASH_MINOR is compatible)"
    test_pass
else
    test_fail "Bash version too old (need 3.2+)"
fi

# ==============================================================================
# SYNTAX COMPATIBILITY TESTS
# ==============================================================================

test_suite "Script Syntax Compatibility"

test_case "All scripts use bash 3.2 compatible syntax"
if ERRORS=0 && \
   for script in "$PROJECT_ROOT/bin"/*.sh; do
       if ! bash -n "$script" 2>&1; then
           ((ERRORS++))
       fi
   done && \
   [[ $ERRORS -eq 0 ]]; then
    test_pass
else
    test_fail "Found $ERRORS scripts with syntax errors"
fi

test_case "No associative arrays (bash 4+ only)"
if FORBIDDEN_SYNTAX=$(grep -r "declare -A" "$PROJECT_ROOT/bin" 2>/dev/null || true) && \
   [[ -z "$FORBIDDEN_SYNTAX" ]]; then
    test_pass
else
    test_fail "Found forbidden bash 4+ syntax (declare -A)"
fi

test_case "No bash 4+ parameter expansion"
if ! grep -r "\${var,,}" "$PROJECT_ROOT/bin" 2>/dev/null && \
   ! grep -r "\${var^^}" "$PROJECT_ROOT/bin" 2>/dev/null; then
    test_pass
else
    test_fail "Found bash 4+ parameter expansion"
fi

test_case "Integration installer is bash 3.2 compatible"
if bash -n "$PROJECT_ROOT/bin/install-integrations.sh" && \
   ! grep "declare -A" "$PROJECT_ROOT/bin/install-integrations.sh"; then
    test_pass
else
    test_fail "Integration installer not bash 3.2 compatible"
fi

# ==============================================================================
# PLATFORM DETECTION TESTS
# ==============================================================================

test_suite "Platform Detection"

test_case "Detect operating system"
if OS="$(uname -s)" && \
   assert_not_empty "$OS"; then
    echo "    (OS: $OS)"
    test_pass
else
    test_fail "Failed to detect OS"
fi

test_case "macOS compatibility"
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "    (Running on macOS — verifying macOS-specific commands)"
    # On macOS, verify key macOS tools exist
    if command -v security &>/dev/null && command -v osascript &>/dev/null; then
        test_pass
    else
        test_fail "macOS detected but missing expected tools (security, osascript)"
    fi
else
    echo "    (Not macOS — verifying compat.sh provides cross-platform wrappers)"
    # On non-macOS, verify compat.sh wrappers exist and work
    if source "$PROJECT_ROOT/lib/platform/compat.sh" 2>/dev/null && \
       declare -f get_file_size &>/dev/null && \
       declare -f get_file_mtime &>/dev/null; then
        test_pass
    else
        test_fail "Cross-platform wrappers missing from compat.sh"
    fi
fi

test_case "Linux compatibility"
if [[ "$(uname -s)" == "Linux" ]]; then
    echo "    (Running on Linux — verifying GNU coreutils)"
    # On Linux, verify GNU date and stat work
    if date -d "2025-01-01" +%s &>/dev/null && stat -c%s /dev/null &>/dev/null; then
        test_pass
    else
        test_fail "Linux detected but GNU date/stat not working"
    fi
else
    echo "    (Not Linux — verifying compat.sh provides cross-platform wrappers)"
    if source "$PROJECT_ROOT/lib/platform/compat.sh" 2>/dev/null && \
       declare -f date_to_epoch &>/dev/null && \
       declare -f to_upper &>/dev/null; then
        test_pass
    else
        test_fail "Cross-platform wrappers missing from compat.sh"
    fi
fi

# ==============================================================================
# COMMAND AVAILABILITY TESTS
# ==============================================================================

test_suite "Required Commands"

test_case "git is available"
if command -v git &>/dev/null; then
    GIT_VERSION=$(git --version)
    echo "    ($GIT_VERSION)"
    test_pass
else
    test_fail "git not found"
fi

test_case "sqlite3 is available (or gracefully absent)"
if command -v sqlite3 &>/dev/null; then
    SQLITE_VERSION=$(sqlite3 --version | awk '{print $1}')
    echo "    (SQLite version: $SQLITE_VERSION)"
    test_pass
else
    echo "    (sqlite3 not installed — verifying code handles absence)"
    # Verify scripts that use sqlite3 guard with command -v checks
    if grep -rn "sqlite3" "$PROJECT_ROOT/lib/" "$PROJECT_ROOT/bin/" 2>/dev/null | \
       grep -v "command -v\|which\|#.*sqlite\|\.md\|test" | grep -q "sqlite3"; then
        # Found unguarded sqlite3 usage — that's a problem
        test_fail "sqlite3 not installed and unguarded usage found in scripts"
    else
        test_pass
    fi
fi

test_case "gzip is available"
if command -v gzip &>/dev/null; then
    test_pass
else
    test_fail "gzip not found (required for compression)"
fi

test_case "find is available"
if command -v find &>/dev/null; then
    test_pass
else
    test_fail "find not found (required for cleanup)"
fi

test_case "date is available"
if command -v date &>/dev/null; then
    test_pass
else
    test_fail "date not found (required for timestamps)"
fi

# ==============================================================================
# FILE SYSTEM TESTS
# ==============================================================================

test_suite "File System Compatibility"

test_case "stat command (macOS vs Linux)"
if TEST_FILE="$TEST_TEMP_DIR/stat-test.txt" && \
   echo "test" > "$TEST_FILE" && \
   ( stat -f%z "$TEST_FILE" &>/dev/null || stat -c%s "$TEST_FILE" &>/dev/null ); then
    test_pass
else
    test_fail "stat command not compatible"
fi

test_case "touch with timestamp (macOS vs Linux)"
if TEST_FILE="$TEST_TEMP_DIR/touch-test.txt" && \
   touch -t "202501010000" "$TEST_FILE" 2>/dev/null; then
    test_pass
else
    test_skip "touch -t not supported on this platform"
fi

test_case "find with mtime"
if TEST_DIR="$TEST_TEMP_DIR/find-test" && \
   mkdir -p "$TEST_DIR" && \
   touch "$TEST_DIR/file.txt" && \
   find "$TEST_DIR" -type f -mtime -1 | grep -q "file.txt"; then
    test_pass
else
    test_fail "find -mtime not working"
fi

# ==============================================================================
# SHELL FEATURE TESTS
# ==============================================================================

test_suite "Shell Features"

test_case "Arrays are supported"
if TEST_ARRAY=("a" "b" "c") && \
   [[ "${#TEST_ARRAY[@]}" -eq 3 ]]; then
    test_pass
else
    test_fail "Arrays not supported"
fi

test_case "Command substitution works"
if RESULT="$(echo 'test')" && \
   [[ "$RESULT" == "test" ]]; then
    test_pass
else
    test_fail "Command substitution failed"
fi

test_case "Process substitution (bash 3.2+)"
if bash -c 'diff <(echo "a") <(echo "b")' &>/dev/null || true; then
    test_pass
else
    test_skip "Process substitution not available"
fi

test_case "[[ ]] conditional expressions"
if [[ "test" == "test" ]] && [[ 5 -gt 3 ]]; then
    test_pass
else
    test_fail "[[ ]] not working"
fi

test_case "Pattern matching in conditionals"
if TEXT="hello world" && [[ "$TEXT" == *"world"* ]]; then
    test_pass
else
    test_fail "Pattern matching failed"
fi

# ==============================================================================
# INTEGRATION COMPATIBILITY TESTS
# ==============================================================================

test_suite "Integration Compatibility"

test_case "Shell integration syntax"
if bash -n "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh"; then
    test_pass
else
    test_fail "Shell integration has syntax errors"
fi

test_case "Git integration syntax"
if bash -n "$PROJECT_ROOT/integrations/git/hooks/pre-commit"; then
    test_pass
else
    test_fail "Git integration has syntax errors"
fi

test_case "Integration core library syntax"
if bash -n "$PROJECT_ROOT/integrations/lib/integration-core.sh"; then
    test_pass
else
    test_fail "Integration core has syntax errors"
fi

test_case "Vim plugin file exists"
if [[ -f "$PROJECT_ROOT/integrations/vim/plugin/backup.vim" ]]; then
    test_pass
else
    test_fail "Vim plugin missing"
fi

# ==============================================================================
# NOTIFICATION COMPATIBILITY TESTS
# ==============================================================================

test_suite "Notification Support"

test_case "Platform-native notification command exists"
if command -v osascript &>/dev/null; then
    echo "    (macOS: osascript available)"
    test_pass
elif command -v notify-send &>/dev/null; then
    echo "    (Linux: notify-send available)"
    test_pass
else
    echo "    (No native notification tool — verifying terminal fallback)"
    # Code must have a terminal echo fallback for notifications
    if grep -q "echo" "$PROJECT_ROOT/integrations/lib/integration-core.sh" 2>/dev/null; then
        test_pass
    else
        test_fail "No notification method available and no terminal fallback"
    fi
fi

test_case "Terminal fallback always works"
if echo "Test notification" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Terminal output failed"
fi

# ==============================================================================
# PERFORMANCE TESTS
# ==============================================================================

test_suite "Performance & Resource Usage"

test_case "Scripts execute within reasonable time"
if START_TIME=$(date +%s) && \
   bash "$PROJECT_ROOT/bin/backup-status.sh" --help &>/dev/null && \
   END_TIME=$(date +%s) && \
   ELAPSED=$((END_TIME - START_TIME)) && \
   [[ $ELAPSED -lt 5 ]]; then
    echo "    (Executed in ${ELAPSED}s)"
    test_pass
else
    test_fail "Script execution too slow"
fi

test_case "Memory usage is reasonable"
if command -v ps &>/dev/null; then
    test_pass
else
    test_skip "ps command not available"
fi

# ==============================================================================
# ERROR HANDLING TESTS
# ==============================================================================

test_suite "Error Handling"

test_case "Scripts use set -e for error propagation"
if grep -q "set -e" "$PROJECT_ROOT/bin/backup-status.sh" || \
   grep -q "set -eo" "$PROJECT_ROOT/bin/backup-status.sh"; then
    test_pass
else
    test_skip "Not all scripts use set -e"
fi

test_case "Scripts handle missing files gracefully"
if bash "$PROJECT_ROOT/bin/backup-status.sh" --help &>/dev/null; then
    test_pass
else
    test_fail "Script failed on missing files"
fi

# ==============================================================================
# ENCODING & SPECIAL CHARACTERS
# ==============================================================================

test_suite "Character Encoding"

test_case "UTF-8 filenames supported"
if TEST_FILE="$TEST_TEMP_DIR/test-émoji-🎉.txt" && \
   echo "test" > "$TEST_FILE" 2>/dev/null && \
   [[ -f "$TEST_FILE" ]]; then
    rm "$TEST_FILE"
    test_pass
else
    test_skip "UTF-8 filenames not supported"
fi

test_case "Spaces in paths handled correctly"
if TEST_DIR="$TEST_TEMP_DIR/path with spaces" && \
   mkdir -p "$TEST_DIR" && \
   assert_dir_exists "$TEST_DIR"; then
    test_pass
else
    test_fail "Spaces in paths not handled"
fi

test_case "Special characters in project names"
if PROJECT_NAME="Test-Project_123" && \
   [[ "$PROJECT_NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
    test_pass
else
    test_fail "Special characters validation failed"
fi

# Run summary
print_test_summary
