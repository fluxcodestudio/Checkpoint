#!/bin/bash
# Checkpoint - Smoke Test
# Quick validation that all core functionality works

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Test counters
PASSED=0
FAILED=0
TOTAL=0

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

test_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
}

test_fail() {
    local msg="$1"
    echo -e "${RED}✗ FAIL${NC} - $msg"
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
}

# ==============================================================================
# TESTS
# ==============================================================================

echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}Checkpoint - Smoke Test${NC}"
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

# 1. SYNTAX VALIDATION
echo -e "${CYAN}[1/6] Syntax Validation${NC}"

echo -n "  backup-status.sh syntax ... "
if bash -n "$PROJECT_ROOT/bin/backup-status.sh" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error"
fi

echo -n "  backup-now.sh syntax ... "
if bash -n "$PROJECT_ROOT/bin/backup-now.sh" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error"
fi

echo -n "  backup-config.sh syntax ... "
if bash -n "$PROJECT_ROOT/bin/backup-config.sh" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error"
fi

echo -n "  backup-restore.sh syntax ... "
if bash -n "$PROJECT_ROOT/bin/backup-restore.sh" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error"
fi

echo -n "  backup-cleanup.sh syntax ... "
if bash -n "$PROJECT_ROOT/bin/backup-cleanup.sh" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error"
fi

echo -n "  install-integrations.sh syntax ... "
if bash -n "$PROJECT_ROOT/bin/install-integrations.sh" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error"
fi

# 2. BASH 3.2 COMPATIBILITY
echo ""
echo -e "${CYAN}[2/6] Bash 3.2 Compatibility${NC}"

echo -n "  No associative arrays (declare -A) ... "
if ! grep -r "declare -A" "$PROJECT_ROOT/bin"/*.sh 2>/dev/null; then
    test_pass
else
    test_fail "found declare -A"
fi

echo -n "  Bash version is 3.2+ ... "
BASH_MAJOR="${BASH_VERSINFO[0]}"
BASH_MINOR="${BASH_VERSINFO[1]}"
if [[ $BASH_MAJOR -ge 3 ]] && { [[ $BASH_MAJOR -gt 3 ]] || [[ $BASH_MINOR -ge 2 ]]; }; then
    test_pass
else
    test_fail "bash too old"
fi

# 3. FILE EXISTENCE
echo ""
echo -e "${CYAN}[3/6] Required Files${NC}"

echo -n "  bin/backup-status.sh exists ... "
if [[ -f "$PROJECT_ROOT/bin/backup-status.sh" ]]; then
    test_pass
else
    test_fail "missing"
fi

echo -n "  bin/backup-now.sh exists ... "
if [[ -f "$PROJECT_ROOT/bin/backup-now.sh" ]]; then
    test_pass
else
    test_fail "missing"
fi

echo -n "  integrations/lib/integration-core.sh exists ... "
if [[ -f "$PROJECT_ROOT/integrations/lib/integration-core.sh" ]]; then
    test_pass
else
    test_fail "missing"
fi

echo -n "  docs/INTEGRATIONS.md exists ... "
if [[ -f "$PROJECT_ROOT/docs/INTEGRATIONS.md" ]]; then
    test_pass
else
    test_fail "missing"
fi

# 4. HELP COMMANDS
echo ""
echo -e "${CYAN}[4/6] Help Commands${NC}"

echo -n "  backup-status --help works ... "
if bash "$PROJECT_ROOT/bin/backup-status.sh" --help &>/dev/null; then
    test_pass
else
    test_fail "command failed"
fi

echo -n "  backup-now --help works ... "
if bash "$PROJECT_ROOT/bin/backup-now.sh" --help &>/dev/null; then
    test_pass
else
    test_fail "command failed"
fi

echo -n "  install-integrations --help works ... "
if bash "$PROJECT_ROOT/bin/install-integrations.sh" --help &>/dev/null; then
    test_pass
else
    test_fail "command failed"
fi

# 5. INTEGRATION FILES
echo ""
echo -e "${CYAN}[5/6] Integration Files${NC}"

echo -n "  Shell integration syntax ... "
if bash -n "$PROJECT_ROOT/integrations/shell/backup-shell-integration.sh" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error"
fi

echo -n "  Git hook syntax ... "
if bash -n "$PROJECT_ROOT/integrations/git/hooks/pre-commit" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error"
fi

echo -n "  Integration core library syntax ... "
if bash -n "$PROJECT_ROOT/integrations/lib/integration-core.sh" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error"
fi

echo -n "  Vim plugin exists ... "
if [[ -f "$PROJECT_ROOT/integrations/vim/plugin/backup.vim" ]]; then
    test_pass
else
    test_fail "missing"
fi

# 6. DOCUMENTATION
echo ""
echo -e "${CYAN}[6/6] Documentation${NC}"

echo -n "  README.md exists and mentions Checkpoint ... "
if [[ -f "$PROJECT_ROOT/README.md" ]] && grep -q "Checkpoint" "$PROJECT_ROOT/README.md"; then
    test_pass
else
    test_fail "missing or outdated"
fi

echo -n "  CHANGELOG.md exists ... "
if [[ -f "$PROJECT_ROOT/CHANGELOG.md" ]]; then
    test_pass
else
    test_fail "missing"
fi

echo -n "  VERSION file exists ... "
if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
    test_pass
else
    test_fail "missing"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

echo ""
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}Test Summary${NC}"
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Total:  $TOTAL"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "  ${RED}Failed: $FAILED${NC}"
fi
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✓ ALL SMOKE TESTS PASSED${NC}"
    echo ""
    echo -e "${GREEN}Checkpoint is ready for use!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
    echo ""
    echo -e "${RED}Please review failures before using Checkpoint${NC}"
    echo ""
    exit 1
fi
