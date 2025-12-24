#!/bin/bash
# ClaudeCode Project Backups - Integration Testing Framework
# Tests all integration modules
# Version: 1.2.0

set -eo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INTEGRATIONS_DIR="$PROJECT_ROOT/integrations"

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================================================
# TEST FRAMEWORK
# ==============================================================================

# Print test header
test_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Run a test
# Usage: run_test TEST_NAME COMMAND [ARGS...]
run_test() {
    local test_name="$1"
    shift

    ((TESTS_RUN++))

    echo -n "Testing: $test_name ... "

    if "$@" &>/dev/null; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

# Run a test with output check
run_test_output() {
    local test_name="$1"
    local expected="$2"
    shift 2

    ((TESTS_RUN++))

    echo -n "Testing: $test_name ... "

    local output=$("$@" 2>&1)

    if echo "$output" | grep -q "$expected"; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        echo "   Expected: $expected"
        echo "   Got: $output"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

# ==============================================================================
# TEST SUITES
# ==============================================================================

# Test integration-core.sh
test_integration_core() {
    test_header "Testing Integration Core Library"

    local core_lib="$INTEGRATIONS_DIR/lib/integration-core.sh"

    run_test "Core library exists" test -f "$core_lib"
    run_test "Core library is readable" test -r "$core_lib"

    # Source the library
    if source "$core_lib" 2>/dev/null; then
        echo -e "${GREEN}✅ Core library sourced successfully${NC}"

        # Test exported functions
        run_test "integration_init function exists" type integration_init
        run_test "integration_trigger_backup function exists" type integration_trigger_backup
        run_test "integration_get_status function exists" type integration_get_status
        run_test "integration_get_status_compact function exists" type integration_get_status_compact
        run_test "integration_get_status_emoji function exists" type integration_get_status_emoji
        run_test "integration_should_trigger function exists" type integration_should_trigger
        run_test "integration_check_lock function exists" type integration_check_lock
        run_test "integration_format_time_ago function exists" type integration_format_time_ago
        run_test "integration_time_since_backup function exists" type integration_time_since_backup
    else
        echo -e "${RED}❌ Failed to source core library${NC}"
        ((TESTS_FAILED++))
    fi
}

# Test notification.sh
test_notification() {
    test_header "Testing Notification Library"

    local notification_lib="$INTEGRATIONS_DIR/lib/notification.sh"

    run_test "Notification library exists" test -f "$notification_lib"
    run_test "Notification library is readable" test -r "$notification_lib"

    # Source the library
    if source "$notification_lib" 2>/dev/null; then
        echo -e "${GREEN}✅ Notification library sourced successfully${NC}"

        # Test exported functions
        run_test "notify function exists" type notify
        run_test "notify_success function exists" type notify_success
        run_test "notify_error function exists" type notify_error
        run_test "notify_warning function exists" type notify_warning
        run_test "notify_info function exists" type notify_info
        run_test "test_notifications function exists" type test_notifications

        # Test backend detection
        run_test "Notification backend detected" test -n "$NOTIFICATION_BACKEND"
    else
        echo -e "${RED}❌ Failed to source notification library${NC}"
        ((TESTS_FAILED++))
    fi
}

# Test status-formatter.sh
test_status_formatter() {
    test_header "Testing Status Formatter Library"

    local formatter_lib="$INTEGRATIONS_DIR/lib/status-formatter.sh"

    run_test "Status formatter library exists" test -f "$formatter_lib"
    run_test "Status formatter library is readable" test -r "$formatter_lib"

    # Source the library
    if source "$formatter_lib" 2>/dev/null; then
        echo -e "${GREEN}✅ Status formatter library sourced successfully${NC}"

        # Test exported functions
        run_test "format_status function exists" type format_status
        run_test "format_success function exists" type format_success
        run_test "format_warning function exists" type format_warning
        run_test "format_error function exists" type format_error
        run_test "format_duration function exists" type format_duration
        run_test "format_time_ago function exists" type format_time_ago
        run_test "format_size function exists" type format_size

        # Test emoji constants
        run_test "EMOJI_SUCCESS defined" test -n "$EMOJI_SUCCESS"
        run_test "EMOJI_WARNING defined" test -n "$EMOJI_WARNING"
        run_test "EMOJI_ERROR defined" test -n "$EMOJI_ERROR"
    else
        echo -e "${RED}❌ Failed to source status formatter library${NC}"
        ((TESTS_FAILED++))
    fi
}

# Test shell integration
test_shell_integration() {
    test_header "Testing Shell Integration"

    local shell_integration="$INTEGRATIONS_DIR/shell/backup-shell-integration.sh"
    local shell_installer="$INTEGRATIONS_DIR/shell/install.sh"

    run_test "Shell integration script exists" test -f "$shell_integration"
    run_test "Shell integration is readable" test -r "$shell_integration"
    run_test "Shell installer exists" test -f "$shell_installer"
    run_test "Shell installer is executable" test -x "$shell_installer"
    run_test "Shell README exists" test -f "$INTEGRATIONS_DIR/shell/README.md"
}

# Test git hooks integration
test_git_hooks() {
    test_header "Testing Git Hooks Integration"

    local hooks_dir="$INTEGRATIONS_DIR/git/hooks"
    local installer="$INTEGRATIONS_DIR/git/install-git-hooks.sh"

    run_test "Git hooks directory exists" test -d "$hooks_dir"
    run_test "Git installer exists" test -f "$installer"
    run_test "Git installer is executable" test -x "$installer"

    # Test hook files
    run_test "pre-commit hook exists" test -f "$hooks_dir/pre-commit"
    run_test "pre-commit hook is executable" test -x "$hooks_dir/pre-commit"
    run_test "post-commit hook exists" test -f "$hooks_dir/post-commit"
    run_test "post-commit hook is executable" test -x "$hooks_dir/post-commit"
    run_test "pre-push hook exists" test -f "$hooks_dir/pre-push"
    run_test "pre-push hook is executable" test -x "$hooks_dir/pre-push"

    run_test "Git hooks README exists" test -f "$INTEGRATIONS_DIR/git/README.md"
}

# Test direnv integration
test_direnv() {
    test_header "Testing Direnv Integration"

    local envrc_template="$INTEGRATIONS_DIR/direnv/.envrc"
    local installer="$INTEGRATIONS_DIR/direnv/install-direnv.sh"

    run_test "Direnv .envrc template exists" test -f "$envrc_template"
    run_test "Direnv .envrc is readable" test -r "$envrc_template"
    run_test "Direnv installer exists" test -f "$installer"
    run_test "Direnv installer is executable" test -x "$installer"
    run_test "Direnv README exists" test -f "$INTEGRATIONS_DIR/direnv/README.md"

    # Test .envrc content
    run_test_output "Direnv .envrc has CLAUDECODE_BACKUP_ROOT" "CLAUDECODE_BACKUP_ROOT" cat "$envrc_template"
    run_test_output "Direnv .envrc has PATH export" "PATH.*bin" cat "$envrc_template"
}

# Test tmux integration
test_tmux() {
    test_header "Testing Tmux Integration"

    local tmux_status="$INTEGRATIONS_DIR/tmux/backup-tmux-status.sh"
    local tmux_conf="$INTEGRATIONS_DIR/tmux/backup-tmux.conf"
    local installer="$INTEGRATIONS_DIR/tmux/install-tmux.sh"

    run_test "Tmux status script exists" test -f "$tmux_status"
    run_test "Tmux status script is executable" test -x "$tmux_status"
    run_test "Tmux config template exists" test -f "$tmux_conf"
    run_test "Tmux config is readable" test -r "$tmux_conf"
    run_test "Tmux installer exists" test -f "$installer"
    run_test "Tmux installer is executable" test -x "$installer"
    run_test "Tmux README exists" test -f "$INTEGRATIONS_DIR/tmux/README.md"

    # Test tmux.conf content
    run_test_output "Tmux config has @backup-status-script" "@backup-status-script" cat "$tmux_conf"
    run_test_output "Tmux config has keybindings" "bind-key" cat "$tmux_conf"
}

# Test VS Code integration
test_vscode() {
    test_header "Testing VS Code Integration"

    local tasks_json="$INTEGRATIONS_DIR/vscode/tasks.json"
    local keybindings_json="$INTEGRATIONS_DIR/vscode/keybindings.json"
    local installer="$INTEGRATIONS_DIR/vscode/install-vscode.sh"

    run_test "VS Code tasks.json exists" test -f "$tasks_json"
    # Note: VS Code JSON files use JSONC (JSON with Comments), so standard JSON validators may fail
    # We'll just check if the file is readable instead
    run_test "VS Code tasks.json is readable" test -r "$tasks_json"
    run_test "VS Code keybindings.json exists" test -f "$keybindings_json"
    run_test "VS Code keybindings.json is readable" test -r "$keybindings_json"
    run_test "VS Code installer exists" test -f "$installer"
    run_test "VS Code installer is executable" test -x "$installer"
    run_test "VS Code README exists" test -f "$INTEGRATIONS_DIR/vscode/README.md"

    # Test tasks.json content
    run_test_output "VS Code tasks has Backup: Show Status" "Backup: Show Status" cat "$tasks_json"
    run_test_output "VS Code tasks has CLAUDECODE_BACKUP_ROOT" "CLAUDECODE_BACKUP_ROOT" cat "$tasks_json"
}

# Test integration directory structure
test_directory_structure() {
    test_header "Testing Integration Directory Structure"

    run_test "integrations directory exists" test -d "$INTEGRATIONS_DIR"
    run_test "integrations/lib exists" test -d "$INTEGRATIONS_DIR/lib"
    run_test "integrations/shell exists" test -d "$INTEGRATIONS_DIR/shell"
    run_test "integrations/git exists" test -d "$INTEGRATIONS_DIR/git"
    run_test "integrations/direnv exists" test -d "$INTEGRATIONS_DIR/direnv"
    run_test "integrations/tmux exists" test -d "$INTEGRATIONS_DIR/tmux"
    run_test "integrations/vscode exists" test -d "$INTEGRATIONS_DIR/vscode"
}

# ==============================================================================
# MAIN TEST RUNNER
# ==============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  ClaudeCode Backup System - Integration Test Suite       ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Project root: $PROJECT_ROOT"
    echo "Integrations directory: $INTEGRATIONS_DIR"
    echo ""

    # Run all test suites
    test_directory_structure
    test_integration_core
    test_notification
    test_status_formatter
    test_shell_integration
    test_git_hooks
    test_direnv
    test_tmux
    test_vscode

    # ==============================================================================
    # SUMMARY
    # ==============================================================================

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}TEST SUMMARY${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
        echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ❌ SOME TESTS FAILED                                    ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
        exit 1
    else
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅ ALL TESTS PASSED                                     ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
        exit 0
    fi
}

# Run main
main "$@"
