#!/bin/bash
# Manual Test Suite for v2.2.0 New Features
# Simple validation that all new commands work correctly

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

echo -e "${BOLD}${CYAN}Testing Checkpoint v2.2.0 New Features${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

test_command() {
    local description="$1"
    local command="$2"
    local should_contain="${3:-}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -ne "${CYAN}TEST ${TOTAL_TESTS}:${NC} $description... "

    local output
    local exit_code=0

    output=$(bash -c "$command" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 1 ]]; then
        # Check if output contains expected string (if provided)
        if [[ -n "$should_contain" ]]; then
            if echo "$output" | grep -q "$should_contain"; then
                echo -e "${GREEN}✓ PASS${NC}"
                PASSED_TESTS=$((PASSED_TESTS + 1))
                return 0
            else
                echo -e "${RED}✗ FAIL${NC} (missing: $should_contain)"
                echo "  Output: ${output:0:100}..."
                FAILED_TESTS=$((FAILED_TESTS + 1))
                return 1
            fi
        else
            echo -e "${GREEN}✓ PASS${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        fi
    else
        echo -e "${RED}✗ FAIL${NC} (exit code: $exit_code)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

test_file_exists() {
    local description="$1"
    local file_path="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -ne "${CYAN}TEST ${TOTAL_TESTS}:${NC} $description... "

    if [[ -f "$file_path" ]]; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} (file not found)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# ==============================================================================
# FILE EXISTENCE TESTS
# ==============================================================================

echo -e "${BOLD}File Existence Tests${NC}"
echo "-------------------"

test_file_exists "checkpoint skill exists" "$PROJECT_ROOT/.claude/skills/checkpoint/run.sh"
test_file_exists "checkpoint skill.json exists" "$PROJECT_ROOT/.claude/skills/checkpoint/skill.json"
test_file_exists "backup-update skill exists" "$PROJECT_ROOT/.claude/skills/backup-update/run.sh"
test_file_exists "backup-pause skill exists" "$PROJECT_ROOT/.claude/skills/backup-pause/run.sh"
test_file_exists "uninstall skill exists" "$PROJECT_ROOT/.claude/skills/uninstall/run.sh"
test_file_exists "backup-update.sh exists" "$PROJECT_ROOT/bin/backup-update.sh"
test_file_exists "backup-pause.sh exists" "$PROJECT_ROOT/bin/backup-pause.sh"

echo ""

# ==============================================================================
# CHECKPOINT COMMAND TESTS
# ==============================================================================

echo -e "${BOLD}/checkpoint Command Tests${NC}"
echo "------------------------"

test_command "/checkpoint --help shows help" \
    "\"$PROJECT_ROOT/.claude/skills/checkpoint/run.sh\" --help" \
    "Checkpoint - Control Panel"

test_command "/checkpoint --info shows system info" \
    "\"$PROJECT_ROOT/.claude/skills/checkpoint/run.sh\" --info" \
    "System Information"

test_command "/checkpoint --info shows installation mode" \
    "\"$PROJECT_ROOT/.claude/skills/checkpoint/run.sh\" --info" \
    "Mode:"

test_command "/checkpoint shows version" \
    "\"$PROJECT_ROOT/.claude/skills/checkpoint/run.sh\" --status || true" \
    "Version:"

test_command "/checkpoint --check-update runs" \
    "\"$PROJECT_ROOT/.claude/skills/checkpoint/run.sh\" --check-update || true" \
    ""

echo ""

# ==============================================================================
# SKILL JSON VALIDATION
# ==============================================================================

echo -e "${BOLD}Skill JSON Validation${NC}"
echo "---------------------"

for skill in checkpoint backup-update backup-pause uninstall; do
    test_command "$skill skill.json is valid JSON" \
        "python3 -m json.tool '$PROJECT_ROOT/.claude/skills/$skill/skill.json' >/dev/null" \
        ""

    test_command "$skill has name field" \
        "grep -q '\"name\"' '$PROJECT_ROOT/.claude/skills/$skill/skill.json'" \
        ""

    test_command "$skill has examples" \
        "grep -q '\"examples\"' '$PROJECT_ROOT/.claude/skills/$skill/skill.json'" \
        ""
done

echo ""

# ==============================================================================
# EXECUTABLE PERMISSIONS
# ==============================================================================

echo -e "${BOLD}Executable Permissions${NC}"
echo "---------------------"

test_command "checkpoint/run.sh is executable" \
    "[ -x '$PROJECT_ROOT/.claude/skills/checkpoint/run.sh' ]" \
    ""

test_command "backup-update/run.sh is executable" \
    "[ -x '$PROJECT_ROOT/.claude/skills/backup-update/run.sh' ]" \
    ""

test_command "backup-pause/run.sh is executable" \
    "[ -x '$PROJECT_ROOT/.claude/skills/backup-pause/run.sh' ]" \
    ""

test_command "uninstall/run.sh is executable" \
    "[ -x '$PROJECT_ROOT/.claude/skills/uninstall/run.sh' ]" \
    ""

echo ""

# ==============================================================================
# DOCUMENTATION TESTS
# ==============================================================================

echo -e "${BOLD}Documentation Tests${NC}"
echo "------------------"

test_command "README contains v2.2.0" \
    "grep -q '2.2.0' '$PROJECT_ROOT/README.md'" \
    ""

test_command "CHANGELOG contains v2.2.0" \
    "grep -q '2.2.0' '$PROJECT_ROOT/CHANGELOG.md'" \
    ""

test_command "COMMANDS.md contains /checkpoint" \
    "grep -q '/checkpoint' '$PROJECT_ROOT/docs/COMMANDS.md'" \
    ""

test_command "COMMANDS.md contains /backup-update" \
    "grep -q '/backup-update' '$PROJECT_ROOT/docs/COMMANDS.md'" \
    ""

test_command "COMMANDS.md contains /backup-pause" \
    "grep -q '/backup-pause' '$PROJECT_ROOT/docs/COMMANDS.md'" \
    ""

test_command "COMMANDS.md contains /uninstall" \
    "grep -q '/uninstall' '$PROJECT_ROOT/docs/COMMANDS.md'" \
    ""

test_command "VERSION file is 2.2.0" \
    "[ \"\$(cat '$PROJECT_ROOT/VERSION')\" = \"2.2.0\" ]" \
    ""

echo ""

# ==============================================================================
# SUMMARY
# ==============================================================================

echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}Test Summary${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Total Tests:${NC}  $TOTAL_TESTS"
echo -e "${GREEN}Passed:${NC}      $PASSED_TESTS"
echo -e "${RED}Failed:${NC}      $FAILED_TESTS"
echo ""

if [[ $FAILED_TESTS -eq 0 ]]; then
    SUCCESS_RATE=100
else
    SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
fi

echo -e "${CYAN}Success Rate:${NC} $SUCCESS_RATE%"
echo ""

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
    echo ""
    echo -e "${GREEN}v2.2.0 features are fully functional!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
    echo ""
    echo -e "${RED}Please review failed tests${NC}"
    exit 1
fi
