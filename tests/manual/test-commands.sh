#!/bin/bash
# Checkpoint - Command Testing Script
# Validates backup-status and backup-now implementations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "Checkpoint - Command Testing"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

# Test function
test_command() {
    local name="$1"
    local command="$2"
    local expected_exit="$3"

    echo -n "Testing: $name... "

    if eval "$command" > /dev/null 2>&1; then
        actual_exit=0
    else
        actual_exit=$?
    fi

    if [ $actual_exit -eq $expected_exit ]; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((pass_count++))
    else
        echo -e "${RED}❌ FAIL${NC} (expected exit $expected_exit, got $actual_exit)"
        ((fail_count++))
    fi
}

# Test function that checks output
test_output() {
    local name="$1"
    local command="$2"
    local pattern="$3"

    echo -n "Testing: $name... "

    output=$(eval "$command" 2>&1)

    if echo "$output" | grep -q "$pattern"; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((pass_count++))
    else
        echo -e "${RED}❌ FAIL${NC} (pattern not found: $pattern)"
        ((fail_count++))
        echo "  Output: ${output:0:100}..."
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Foundation Library Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1: Library exists and is sourceable
test_command "Library file exists" "test -f '$PROJECT_ROOT/lib/backup-lib.sh'" 0
test_command "Library is sourceable" "source '$PROJECT_ROOT/lib/backup-lib.sh' && test -n \"\$BACKUP_LIB_LOADED\"" 0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "backup-status Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 2: backup-status script exists and is executable
test_command "Script file exists" "test -f '$PROJECT_ROOT/bin/backup-status.sh'" 0
test_command "Script is executable" "test -x '$PROJECT_ROOT/bin/backup-status.sh'" 0

# Test 3: Help text
test_output "Help flag works" "'$PROJECT_ROOT/bin/backup-status.sh' --help" "Checkpoint"
test_output "Help shows usage" "'$PROJECT_ROOT/bin/backup-status.sh' --help" "USAGE"
test_output "Help shows options" "'$PROJECT_ROOT/bin/backup-status.sh' --help" "OPTIONS"

# Test 4: Output modes exist
test_output "JSON mode exists" "'$PROJECT_ROOT/bin/backup-status.sh' --help" "--json"
test_output "Compact mode exists" "'$PROJECT_ROOT/bin/backup-status.sh' --help" "--compact"
test_output "Timeline mode exists" "'$PROJECT_ROOT/bin/backup-status.sh' --help" "--timeline"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "backup-now Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 5: backup-now script exists and is executable
test_command "Script file exists" "test -f '$PROJECT_ROOT/bin/backup-now.sh'" 0
test_command "Script is executable" "test -x '$PROJECT_ROOT/bin/backup-now.sh'" 0

# Test 6: Help text
test_output "Help flag works" "'$PROJECT_ROOT/bin/backup-now.sh' --help" "Checkpoint"
test_output "Help shows usage" "'$PROJECT_ROOT/bin/backup-now.sh' --help" "USAGE"
test_output "Help shows options" "'$PROJECT_ROOT/bin/backup-now.sh' --help" "OPTIONS"

# Test 7: Options exist
test_output "Force option exists" "'$PROJECT_ROOT/bin/backup-now.sh' --help" "--force"
test_output "Dry-run option exists" "'$PROJECT_ROOT/bin/backup-now.sh' --help" "--dry-run"
test_output "Database-only option exists" "'$PROJECT_ROOT/bin/backup-now.sh' --help" "--database-only"
test_output "Files-only option exists" "'$PROJECT_ROOT/bin/backup-now.sh' --help" "--files-only"
test_output "Verbose option exists" "'$PROJECT_ROOT/bin/backup-now.sh' --help" "--verbose"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Skills Installer Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 8: Skills installer exists
test_command "Installer file exists" "test -f '$PROJECT_ROOT/bin/install-skills.sh'" 0
test_command "Installer is executable" "test -x '$PROJECT_ROOT/bin/install-skills.sh'" 0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Library Function Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Source library for function tests
source "$PROJECT_ROOT/lib/backup-lib.sh"

# Test 9: Time formatting
test_output "format_time_ago function" "echo \$(format_time_ago \$((\$(date +%s) - 7200)))" "2h ago"
test_output "format_duration function" "echo \$(format_duration 3665)" "1h 1m"

# Test 10: Size formatting
test_output "format_bytes function (KB)" "echo \$(format_bytes 2048)" "2.0 KB"
test_output "format_bytes function (MB)" "echo \$(format_bytes 2097152)" "2.0 MB"
test_output "format_bytes function (GB)" "echo \$(format_bytes 2147483648)" "2.0 GB"

# Test 11: JSON utilities
test_output "json_escape function" "echo \$(json_escape 'test')" "test"
test_output "json_kv function" "echo \$(json_kv 'key' 'value')" '"key": "value"'
test_output "json_kv_num function" "echo \$(json_kv_num 'count' 42)" '"count": 42'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "backup-config Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test: backup-config script exists and is executable
test_command "Script file exists" "test -f '$PROJECT_ROOT/bin/backup-config.sh'" 0
test_command "Script is executable" "test -x '$PROJECT_ROOT/bin/backup-config.sh'" 0

# Test: Help text
test_output "Help flag works" "'$PROJECT_ROOT/bin/backup-config.sh' --help" "backup-config"
test_output "Help shows usage" "'$PROJECT_ROOT/bin/backup-config.sh' --help" "USAGE"
test_output "Help shows commands" "'$PROJECT_ROOT/bin/backup-config.sh' --help" "COMMANDS"

# Test: Commands exist in help
test_output "Get command exists" "'$PROJECT_ROOT/bin/backup-config.sh' --help" "get"
test_output "Set command exists" "'$PROJECT_ROOT/bin/backup-config.sh' --help" "set"
test_output "Wizard command exists" "'$PROJECT_ROOT/bin/backup-config.sh' --help" "wizard"
test_output "Validate command exists" "'$PROJECT_ROOT/bin/backup-config.sh' --help" "validate"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "backup-cleanup Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test: backup-cleanup script exists and is executable
test_command "Script file exists" "test -f '$PROJECT_ROOT/bin/backup-cleanup.sh'" 0
test_command "Script is executable" "test -x '$PROJECT_ROOT/bin/backup-cleanup.sh'" 0

# Test: Help text
test_output "Help flag works" "'$PROJECT_ROOT/bin/backup-cleanup.sh' --help" "Cleanup Utility"
test_output "Help shows usage" "'$PROJECT_ROOT/bin/backup-cleanup.sh' --help" "USAGE"
test_output "Help shows options" "'$PROJECT_ROOT/bin/backup-cleanup.sh' --help" "OPTIONS"

# Test: Options exist
test_output "Preview option exists" "'$PROJECT_ROOT/bin/backup-cleanup.sh' --help" "--preview"
test_output "Auto option exists" "'$PROJECT_ROOT/bin/backup-cleanup.sh' --help" "--auto"
test_output "Recommendations option exists" "'$PROJECT_ROOT/bin/backup-cleanup.sh' --help" "--recommendations"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "backup-restore Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test: backup-restore script exists and is executable
test_command "Script file exists" "test -f '$PROJECT_ROOT/bin/backup-restore.sh'" 0
test_command "Script is executable" "test -x '$PROJECT_ROOT/bin/backup-restore.sh'" 0

# Test: Help text
test_output "Help flag works" "'$PROJECT_ROOT/bin/backup-restore.sh' --help" "Restore Wizard"
test_output "Help shows usage" "'$PROJECT_ROOT/bin/backup-restore.sh' --help" "USAGE"
test_output "Help shows options" "'$PROJECT_ROOT/bin/backup-restore.sh' --help" "OPTIONS"

# Test: Options exist
test_output "List option exists" "'$PROJECT_ROOT/bin/backup-restore.sh' --help" "--list"
test_output "Database option exists" "'$PROJECT_ROOT/bin/backup-restore.sh' --help" "--database"
test_output "File option exists" "'$PROJECT_ROOT/bin/backup-restore.sh' --help" "--file"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Integration Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 12: Scripts can source library
test_command "backup-status sources library" "grep -q 'source.*backup-lib.sh' '$PROJECT_ROOT/bin/backup-status.sh'" 0
test_command "backup-now sources library" "grep -q 'source.*backup-lib.sh' '$PROJECT_ROOT/bin/backup-now.sh'" 0
test_command "backup-config sources library" "grep -q 'source.*backup-lib.sh' '$PROJECT_ROOT/bin/backup-config.sh'" 0
test_command "backup-cleanup sources library" "grep -q 'source.*backup-lib.sh' '$PROJECT_ROOT/bin/backup-cleanup.sh'" 0
test_command "backup-restore sources library" "grep -q 'source.*backup-lib.sh' '$PROJECT_ROOT/bin/backup-restore.sh'" 0

# Test 13: Scripts have proper shebang
test_command "backup-status has shebang" "head -1 '$PROJECT_ROOT/bin/backup-status.sh' | grep -q '^#!/bin/bash'" 0
test_command "backup-now has shebang" "head -1 '$PROJECT_ROOT/bin/backup-now.sh' | grep -q '^#!/bin/bash'" 0
test_command "backup-config has shebang" "head -1 '$PROJECT_ROOT/bin/backup-config.sh' | grep -q '^#!/bin/bash'" 0
test_command "backup-cleanup has shebang" "head -1 '$PROJECT_ROOT/bin/backup-cleanup.sh' | grep -q '^#!/bin/bash'" 0
test_command "backup-restore has shebang" "head -1 '$PROJECT_ROOT/bin/backup-restore.sh' | grep -q '^#!/bin/bash'" 0

# Test 14: Scripts use strict mode
test_command "backup-status uses strict mode" "grep -q 'set -euo pipefail' '$PROJECT_ROOT/bin/backup-status.sh'" 0
test_command "backup-now uses strict mode" "grep -q 'set -euo pipefail' '$PROJECT_ROOT/bin/backup-now.sh'" 0
test_command "backup-config uses strict mode" "grep -q 'set -euo pipefail' '$PROJECT_ROOT/bin/backup-config.sh'" 0
test_command "backup-cleanup uses strict mode" "grep -q 'set -euo pipefail' '$PROJECT_ROOT/bin/backup-cleanup.sh'" 0
test_command "backup-restore uses strict mode" "grep -q 'set -euo pipefail' '$PROJECT_ROOT/bin/backup-restore.sh'" 0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Documentation Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 15: Documentation exists
test_command "Implementation guide exists" "test -f '$PROJECT_ROOT/docs/BACKUP-COMMANDS-IMPLEMENTATION.md'" 0

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Test Results Summary"
echo "═══════════════════════════════════════════════════════════"
echo ""

total_tests=$((pass_count + fail_count))
pass_rate=$(awk "BEGIN {printf \"%.1f\", ($pass_count/$total_tests)*100}")

echo "Total tests: $total_tests"
echo -e "Passed: ${GREEN}$pass_count${NC}"
echo -e "Failed: ${RED}$fail_count${NC}"
echo "Pass rate: $pass_rate%"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./bin/install-skills.sh"
    echo "  2. Test: /backup-status --help"
    echo "  3. Test: /backup-now --dry-run"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    echo ""
    echo "Please fix the failing tests before proceeding."
    exit 1
fi
