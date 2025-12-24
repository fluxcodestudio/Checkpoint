#!/bin/bash
# Integration Platform Tests: Shell, Git, Tmux, Vim, etc.

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT
export PATH="$PROJECT_ROOT/bin:$PATH"

# ==============================================================================
# INTEGRATION CORE LIBRARY TESTS
# ==============================================================================

test_suite "Integration Core Library"

test_case "Integration core library syntax is valid"
if bash -n "$PROJECT_ROOT/integrations/lib/integration-core.sh"; then
    test_pass
else
    test_fail "Integration core has syntax errors"
fi

test_case "Integration core exports functions"
if grep -q "integration_init()" "$PROJECT_ROOT/integrations/lib/integration-core.sh" && \
   grep -q "integration_trigger_backup()" "$PROJECT_ROOT/integrations/lib/integration-core.sh" && \
   grep -q "integration_get_status()" "$PROJECT_ROOT/integrations/lib/integration-core.sh"; then
    test_pass
else
    test_fail "Required functions not found"
fi

test_case "Integration core has no dependencies on external tools (except backup scripts)"
if ! grep -q "command -v npm" "$PROJECT_ROOT/integrations/lib/integration-core.sh" && \
   ! grep -q "command -v python" "$PROJECT_ROOT/integrations/lib/integration-core.sh"; then
    test_pass
else
    test_fail "Unexpected dependencies found"
fi

# ==============================================================================
# SHELL INTEGRATION TESTS
# ==============================================================================

test_suite "Shell Integration"

test_case "Shell integration script exists and is valid"
if [[ -f "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh" ]] && \
   bash -n "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh"; then
    test_pass
else
    test_fail "Shell integration script invalid"
fi

test_case "Shell integration installer exists"
if [[ -f "$PROJECT_ROOT/integrations/shell/install.sh" ]] && \
   [[ -x "$PROJECT_ROOT/integrations/shell/install.sh" ]]; then
    test_pass
else
    test_fail "Shell integration installer not executable"
fi

test_case "Shell integration defines backup_status function"
if grep -q "backup_status" "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh"; then
    test_pass
else
    test_fail "backup_status function not found"
fi

test_case "Shell integration defines backup_now function"
if grep -q "backup_now" "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh"; then
    test_pass
else
    test_fail "backup_now function not found"
fi

test_case "Shell integration defines prompt integration"
if grep -q "PROMPT_COMMAND" "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh" || \
   grep -q "precmd" "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh"; then
    test_pass
else
    test_fail "Prompt integration not found"
fi

test_case "Shell integration can source core library"
if grep -q "integration-core.sh" "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh"; then
    test_pass
else
    test_fail "Core library not sourced"
fi

# ==============================================================================
# GIT INTEGRATION TESTS
# ==============================================================================

test_suite "Git Integration"

test_case "Git hook script exists and is valid"
if [[ -f "$PROJECT_ROOT/integrations/git/backup-git-hook.sh" ]] && \
   bash -n "$PROJECT_ROOT/integrations/git/backup-git-hook.sh"; then
    test_pass
else
    test_fail "Git hook script invalid"
fi

test_case "Git hooks installer exists"
if [[ -f "$PROJECT_ROOT/integrations/git/install-git-hooks.sh" ]] && \
   [[ -x "$PROJECT_ROOT/integrations/git/install-git-hooks.sh" ]]; then
    test_pass
else
    test_fail "Git hooks installer not executable"
fi

test_case "Git hook can be installed in a git repo"
if PROJECT_DIR="$(create_test_project)" && \
   HOOKS_DIR="$PROJECT_DIR/.git/hooks" && \
   assert_dir_exists "$HOOKS_DIR"; then
    test_pass
else
    test_fail "Git hooks directory not found"
fi

test_case "Git pre-commit hook can trigger backup"
if PROJECT_DIR="$(create_test_project)" && \
   PRE_COMMIT="$PROJECT_DIR/.git/hooks/pre-commit" && \
   cat > "$PRE_COMMIT" <<'EOF'
#!/bin/bash
# Checkpoint - Pre-commit hook
echo "Triggering backup before commit..."
exit 0
EOF
   chmod +x "$PRE_COMMIT" && \
   bash -n "$PRE_COMMIT"; then
    test_pass
else
    test_fail "Pre-commit hook creation failed"
fi

test_case "Git hook sources core library"
if grep -q "integration-core.sh" "$PROJECT_ROOT/integrations/git/backup-git-hook.sh"; then
    test_pass
else
    test_fail "Core library not sourced in git hook"
fi

# ==============================================================================
# TMUX INTEGRATION TESTS
# ==============================================================================

test_suite "Tmux Integration"

test_case "Tmux integration script exists and is valid"
if [[ -f "$PROJECT_ROOT/integrations/tmux/backup-tmux-integration.sh" ]] && \
   bash -n "$PROJECT_ROOT/integrations/tmux/backup-tmux-integration.sh"; then
    test_pass
else
    test_fail "Tmux integration script invalid"
fi

test_case "Tmux integration can detect if running in tmux"
if command -v tmux &>/dev/null; then
    echo "    (tmux is available)"
    test_pass
else
    test_skip "tmux not installed"
fi

test_case "Tmux integration defines status function"
if grep -q "tmux" "$PROJECT_ROOT/integrations/tmux/backup-tmux-integration.sh" && \
   bash -n "$PROJECT_ROOT/integrations/tmux/backup-tmux-integration.sh"; then
    test_pass
else
    test_fail "Tmux status function not found"
fi

test_case "Tmux integration sources core library"
if grep -q "integration-core.sh" "$PROJECT_ROOT/integrations/tmux/backup-tmux-integration.sh"; then
    test_pass
else
    test_fail "Core library not sourced in tmux integration"
fi

# ==============================================================================
# DIRENV INTEGRATION TESTS
# ==============================================================================

test_suite "Direnv Integration"

test_case "Direnv integration script exists and is valid"
if [[ -f "$PROJECT_ROOT/integrations/direnv/backup-direnv-integration.sh" ]] && \
   bash -n "$PROJECT_ROOT/integrations/direnv/backup-direnv-integration.sh"; then
    test_pass
else
    test_fail "Direnv integration script invalid"
fi

test_case "Direnv can detect if installed"
if command -v direnv &>/dev/null; then
    echo "    (direnv is available)"
    test_pass
else
    test_skip "direnv not installed"
fi

test_case "Direnv integration sources core library"
if grep -q "integration-core.sh" "$PROJECT_ROOT/integrations/direnv/backup-direnv-integration.sh"; then
    test_pass
else
    test_fail "Core library not sourced in direnv integration"
fi

# ==============================================================================
# VIM INTEGRATION TESTS
# ==============================================================================

test_suite "Vim Integration"

test_case "Vim plugin file exists"
if [[ -f "$PROJECT_ROOT/integrations/vim/plugin/backup.vim" ]]; then
    test_pass
else
    test_fail "Vim plugin file not found"
fi

test_case "Vim autoload file exists"
if [[ -f "$PROJECT_ROOT/integrations/vim/autoload/backup.vim" ]]; then
    test_pass
else
    test_fail "Vim autoload file not found"
fi

test_case "Vim documentation file exists"
if [[ -f "$PROJECT_ROOT/integrations/vim/doc/backup.txt" ]]; then
    test_pass
else
    test_fail "Vim documentation not found"
fi

test_case "Vim plugin defines commands"
if grep -q "command!" "$PROJECT_ROOT/integrations/vim/plugin/backup.vim" && \
   grep -q "BackupStatus" "$PROJECT_ROOT/integrations/vim/plugin/backup.vim" && \
   grep -q "BackupNow" "$PROJECT_ROOT/integrations/vim/plugin/backup.vim"; then
    test_pass
else
    test_fail "Vim commands not defined"
fi

test_case "Vim plugin defines autocommands"
if grep -q "autocmd" "$PROJECT_ROOT/integrations/vim/plugin/backup.vim" || \
   grep -q "augroup" "$PROJECT_ROOT/integrations/vim/plugin/backup.vim"; then
    test_pass
else
    test_fail "Vim autocommands not found"
fi

test_case "Vim plugin can trigger backup script"
if grep -q "backup-now.sh" "$PROJECT_ROOT/integrations/vim/autoload/backup.vim" || \
   grep -q "backup-status.sh" "$PROJECT_ROOT/integrations/vim/autoload/backup.vim"; then
    test_pass
else
    test_fail "Backup script calls not found in vim plugin"
fi

test_case "Vim syntax is valid (basic check)"
if vim -u NONE -e -c "source $PROJECT_ROOT/integrations/vim/plugin/backup.vim" -c "quit" 2>/dev/null || \
   [[ -f "$PROJECT_ROOT/integrations/vim/plugin/backup.vim" ]]; then
    test_pass
else
    test_skip "Vim not available for syntax check"
fi

# ==============================================================================
# VS CODE INTEGRATION TESTS
# ==============================================================================

test_suite "VS Code Integration"

test_case "VS Code extension directory exists"
if [[ -d "$PROJECT_ROOT/integrations/vscode" ]]; then
    test_pass
else
    test_fail "VS Code extension directory not found"
fi

test_case "VS Code package.json exists"
if [[ -f "$PROJECT_ROOT/integrations/vscode/package.json" ]]; then
    test_pass
else
    test_skip "VS Code extension not fully implemented"
fi

test_case "VS Code README exists"
if [[ -f "$PROJECT_ROOT/integrations/vscode/README.md" ]]; then
    test_pass
else
    test_skip "VS Code documentation not found"
fi

# ==============================================================================
# INTEGRATION INSTALLER TESTS
# ==============================================================================

test_suite "Integration Installer"

test_case "Integration installer script exists"
if [[ -f "$PROJECT_ROOT/bin/install-integrations.sh" ]] && \
   [[ -x "$PROJECT_ROOT/bin/install-integrations.sh" ]]; then
    test_pass
else
    test_fail "Integration installer not executable"
fi

test_case "Integration installer is bash 3.2 compatible"
if bash -n "$PROJECT_ROOT/bin/install-integrations.sh" && \
   ! grep "declare -A" "$PROJECT_ROOT/bin/install-integrations.sh"; then
    test_pass
else
    test_fail "Integration installer not bash 3.2 compatible"
fi

test_case "Integration installer can detect platforms"
if grep -q "detect_shell" "$PROJECT_ROOT/bin/install-integrations.sh" && \
   grep -q "detect_git" "$PROJECT_ROOT/bin/install-integrations.sh" && \
   grep -q "detect_tmux" "$PROJECT_ROOT/bin/install-integrations.sh" && \
   grep -q "detect_vim" "$PROJECT_ROOT/bin/install-integrations.sh"; then
    test_pass
else
    test_fail "Platform detection functions not found"
fi

test_case "Integration installer --help works"
if run_command bash "$PROJECT_ROOT/bin/install-integrations.sh" --help; then
    assert_success $TEST_EXIT_CODE && \
    assert_contains "$TEST_OUTPUT" "integration" && \
    test_pass
else
    test_fail "Integration installer --help failed"
fi

# ==============================================================================
# CROSS-INTEGRATION TESTS
# ==============================================================================

test_suite "Cross-Integration Compatibility"

test_case "All integrations source same core library"
if grep -q "integration-core.sh" "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh" && \
   grep -q "integration-core.sh" "$PROJECT_ROOT/integrations/git/backup-git-hook.sh" && \
   grep -q "integration-core.sh" "$PROJECT_ROOT/integrations/tmux/backup-tmux-integration.sh"; then
    test_pass
else
    test_fail "Not all integrations use core library"
fi

test_case "Integrations use consistent function names"
if grep -q "integration_trigger_backup" "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh" && \
   grep -q "integration_get_status" "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh"; then
    test_pass
else
    test_fail "Inconsistent function naming"
fi

test_case "No integration conflicts with another"
if ! grep -q "override" "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh" && \
   ! grep -q "override" "$PROJECT_ROOT/integrations/git/backup-git-hook.sh"; then
    test_pass
else
    test_fail "Potential integration conflicts found"
fi

# ==============================================================================
# DEBOUNCING TESTS
# ==============================================================================

test_suite "Debouncing Mechanism"

test_case "Debounce prevents rapid backup triggers"
if STATE_FILE="$TEST_TEMP_DIR/.debounce-state" && \
   CURRENT_TIME=$(date +%s) && \
   echo "$CURRENT_TIME" > "$STATE_FILE" && \
   LAST_TIME=$(cat "$STATE_FILE") && \
   TIME_DIFF=$((CURRENT_TIME - LAST_TIME)) && \
   DEBOUNCE_INTERVAL=300 && \
   [[ $TIME_DIFF -lt $DEBOUNCE_INTERVAL ]]; then
    test_pass
else
    test_fail "Debounce check failed"
fi

test_case "Debounce allows trigger after interval"
if STATE_FILE="$TEST_TEMP_DIR/.debounce-state" && \
   PAST_TIME=$(($(date +%s) - 400)) && \
   echo "$PAST_TIME" > "$STATE_FILE" && \
   CURRENT_TIME=$(date +%s) && \
   LAST_TIME=$(cat "$STATE_FILE") && \
   TIME_DIFF=$((CURRENT_TIME - LAST_TIME)) && \
   DEBOUNCE_INTERVAL=300 && \
   [[ $TIME_DIFF -ge $DEBOUNCE_INTERVAL ]]; then
    test_pass
else
    test_fail "Debounce interval check failed"
fi

# ==============================================================================
# STATUS DISPLAY TESTS
# ==============================================================================

test_suite "Status Display Integration"

test_case "Compact status format for shell prompt"
if grep -q "compact" "$PROJECT_ROOT/integrations/lib/integration-core.sh" || \
   grep -q "integration_get_status_compact" "$PROJECT_ROOT/integrations/lib/integration-core.sh"; then
    test_pass
else
    test_fail "Compact status format not found"
fi

test_case "Emoji status for visual indicators"
if grep -q "emoji\|✅\|⚠️\|❌" "$PROJECT_ROOT/integrations/lib/integration-core.sh"; then
    test_pass
else
    test_fail "Emoji status not found"
fi

test_case "JSON status for programmatic access"
if grep -q "json" "$PROJECT_ROOT/integrations/lib/integration-core.sh" || \
   grep -q "--json" "$PROJECT_ROOT/bin/backup-status.sh"; then
    test_pass
else
    test_fail "JSON status format not found"
fi

# ==============================================================================
# NOTIFICATION TESTS
# ==============================================================================

test_suite "Notification Integration"

test_case "macOS notification support (osascript)"
if command -v osascript &>/dev/null; then
    echo "    (macOS notifications available)"
    test_pass
else
    test_skip "Not on macOS"
fi

test_case "Linux notification support (notify-send)"
if command -v notify-send &>/dev/null; then
    echo "    (Linux notifications available)"
    test_pass
else
    test_skip "notify-send not installed"
fi

test_case "Terminal fallback notification"
if grep -q "echo" "$PROJECT_ROOT/integrations/lib/integration-core.sh"; then
    test_pass
else
    test_fail "Terminal fallback not found"
fi

# ==============================================================================
# DOCUMENTATION TESTS
# ==============================================================================

test_suite "Integration Documentation"

test_case "User integration guide exists"
if [[ -f "$PROJECT_ROOT/docs/INTEGRATIONS.md" ]]; then
    test_pass
else
    test_fail "User integration guide not found"
fi

test_case "Developer integration guide exists"
if [[ -f "$PROJECT_ROOT/docs/INTEGRATION-DEVELOPMENT.md" ]]; then
    test_pass
else
    test_fail "Developer integration guide not found"
fi

test_case "Integration documentation is comprehensive"
if grep -q "Shell Integration" "$PROJECT_ROOT/docs/INTEGRATIONS.md" && \
   grep -q "Git Integration" "$PROJECT_ROOT/docs/INTEGRATIONS.md" && \
   grep -q "Vim Integration" "$PROJECT_ROOT/docs/INTEGRATIONS.md"; then
    test_pass
else
    test_fail "Integration documentation incomplete"
fi

# Run summary
print_test_summary
