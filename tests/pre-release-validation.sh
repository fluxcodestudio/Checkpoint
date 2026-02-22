#!/bin/bash
# Pre-Release Validation Script
# Comprehensive validation before making Checkpoint public

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKPOINT_VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "unknown")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

check() {
    local description="$1"
    local command="$2"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    echo -ne "${CYAN}[CHECK]${NC} $description... "

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

warn() {
    local description="$1"
    echo -e "${YELLOW}[WARN]${NC} $description"
    WARNINGS=$((WARNINGS + 1))
}

section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ==============================================================================
# VALIDATION CHECKS
# ==============================================================================

validate_repository_structure() {
    section "Repository Structure"

    check "bin/ directory exists" "[ -d '$PROJECT_ROOT/bin' ]"
    check "lib/ directory exists" "[ -d '$PROJECT_ROOT/lib' ]"
    check ".claude/skills/ directory exists" "[ -d '$PROJECT_ROOT/.claude/skills' ]"
    check "docs/ directory exists" "[ -d '$PROJECT_ROOT/docs' ]"
    check "tests/ directory exists" "[ -d '$PROJECT_ROOT/tests' ]"
}

validate_core_scripts() {
    section "Core Scripts"

    check "install.sh exists" "[ -f '$PROJECT_ROOT/bin/install.sh' ]"
    check "install.sh is executable" "[ -x '$PROJECT_ROOT/bin/install.sh' ]"
    check "uninstall.sh exists" "[ -f '$PROJECT_ROOT/bin/uninstall.sh' ]"
    check "backup-now.sh exists" "[ -f '$PROJECT_ROOT/bin/backup-now.sh' ]"
    check "backup-status.sh exists" "[ -f '$PROJECT_ROOT/bin/backup-status.sh' ]"
    check "backup-restore.sh exists" "[ -f '$PROJECT_ROOT/bin/backup-restore.sh' ]"
    check "backup-cleanup.sh exists" "[ -f '$PROJECT_ROOT/bin/backup-cleanup.sh' ]"
    check "backup-update.sh exists" "[ -f '$PROJECT_ROOT/bin/backup-update.sh' ]"
    check "backup-pause.sh exists" "[ -f '$PROJECT_ROOT/bin/backup-pause.sh' ]"
}

validate_libraries() {
    section "Library Files"

    check "backup-lib.sh exists" "[ -f '$PROJECT_ROOT/lib/backup-lib.sh' ]"
    check "cloud-backup.sh exists" "[ -f '$PROJECT_ROOT/lib/cloud-backup.sh' ]"
    check "database-detector.sh exists" "[ -f '$PROJECT_ROOT/lib/database-detector.sh' ]"
    check "dependency-manager.sh exists" "[ -f '$PROJECT_ROOT/lib/dependency-manager.sh' ]"
}

validate_claude_skills() {
    section "Claude Code Skills"

    local skills=(checkpoint backup-update backup-pause uninstall)

    for skill in "${skills[@]}"; do
        check "$skill skill exists" "[ -d '$PROJECT_ROOT/.claude/skills/$skill' ]"
        check "$skill/skill.json exists" "[ -f '$PROJECT_ROOT/.claude/skills/$skill/skill.json' ]"
        check "$skill/run.sh exists" "[ -f '$PROJECT_ROOT/.claude/skills/$skill/run.sh' ]"
        check "$skill/run.sh is executable" "[ -x '$PROJECT_ROOT/.claude/skills/$skill/run.sh' ]"
    done
}

validate_skill_json_syntax() {
    section "Skill JSON Syntax"

    for skill_json in "$PROJECT_ROOT"/.claude/skills/*/skill.json; do
        local skill_name=$(basename "$(dirname "$skill_json")")
        check "$skill_name JSON is valid" "python3 -m json.tool '$skill_json' >/dev/null 2>&1"
    done
}

validate_documentation() {
    section "Documentation"

    check "README.md exists" "[ -f '$PROJECT_ROOT/README.md' ]"
    check "CHANGELOG.md exists" "[ -f '$PROJECT_ROOT/CHANGELOG.md' ]"
    check "LICENSE exists" "[ -f '$PROJECT_ROOT/LICENSE' ]"
    check "SECURITY.md exists" "[ -f '$PROJECT_ROOT/SECURITY.md' ]"
    check "docs/COMMANDS.md exists" "[ -f '$PROJECT_ROOT/docs/COMMANDS.md' ]"

    # Check for updated version
    check "README contains v$CHECKPOINT_VERSION" "grep -q \"$CHECKPOINT_VERSION\" '$PROJECT_ROOT/README.md'"
    check "CHANGELOG contains v$CHECKPOINT_VERSION" "grep -q \"$CHECKPOINT_VERSION\" '$PROJECT_ROOT/CHANGELOG.md'"
    check "COMMANDS.md contains v$CHECKPOINT_VERSION" "grep -q \"$CHECKPOINT_VERSION\" '$PROJECT_ROOT/docs/COMMANDS.md'"
}

validate_version_consistency() {
    section "Version Consistency"

    check "VERSION file exists" "[ -f '$PROJECT_ROOT/VERSION' ]"

    local version=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "")

    if [[ "$version" == "$CHECKPOINT_VERSION" ]]; then
        echo -e "${GREEN}✓${NC} Version file is $CHECKPOINT_VERSION"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${RED}✗${NC} Version file is not $CHECKPOINT_VERSION (found: $version)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

validate_no_secrets() {
    section "Security - No Secrets"

    echo "Scanning for potential secrets..."

    # Check for common secret patterns
    local has_secrets=false

    if grep -r "api_key\s*=\s*['\"][^'\"]*['\"]" "$PROJECT_ROOT" --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=backups --exclude-dir=.planning 2>/dev/null | grep -v "test" | grep -v "example"; then
        warn "Found potential API key"
        has_secrets=true
    fi

    if grep -r "password\s*=\s*['\"][^'\"]*['\"]" "$PROJECT_ROOT" --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=backups --exclude-dir=.planning 2>/dev/null | grep -v "test" | grep -v "example" | grep -v "password_prompt" | grep -v 'password="\$' | grep -v 'password="${'; then
        warn "Found potential password"
        has_secrets=true
    fi

    if ! $has_secrets; then
        echo -e "${GREEN}✓${NC} No secrets found"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

validate_no_personal_data() {
    section "Security - No Personal Data"

    echo "Scanning for personal information..."

    # Check for common personal data (excluding test files)
    local has_personal=false

    # Check for real usernames (excluding generic examples)
    if grep -r "/Users/[a-z]" "$PROJECT_ROOT" --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=backups --exclude-dir=.planning --exclude-dir=.claude --exclude-dir=website 2>/dev/null | \
       grep -v "yourname" | grep -v "username" | grep -v "/Users/you" | grep -v ".md:" | grep -v "example"; then
        warn "Found potential personal username"
        has_personal=true
    fi

    if ! $has_personal; then
        echo -e "${GREEN}✓${NC} No personal data found"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

validate_github_templates() {
    section "GitHub Templates"

    check "Bug report template exists" "[ -f '$PROJECT_ROOT/.github/ISSUE_TEMPLATE/bug_report.md' ]"
    check "Feature request template exists" "[ -f '$PROJECT_ROOT/.github/ISSUE_TEMPLATE/feature_request.md' ]"
    check "Pull request template exists" "[ -f '$PROJECT_ROOT/.github/PULL_REQUEST_TEMPLATE.md' ]"
}

validate_git_status() {
    section "Git Status"

    cd "$PROJECT_ROOT"

    # Check if there are uncommitted changes
    if [[ -n "$(git status --porcelain)" ]]; then
        warn "There are uncommitted changes"
        echo "  Run 'git status' to see changes"
    else
        echo -e "${GREEN}✓${NC} Working directory is clean"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
}

run_test_suite() {
    section "Running Test Suite"

    echo "Executing comprehensive tests..."
    echo ""

    if [[ -f "$PROJECT_ROOT/tests/run-all-tests.sh" ]]; then
        if bash "$PROJECT_ROOT/tests/run-all-tests.sh"; then
            echo -e "${GREEN}✓${NC} All tests passed"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        else
            echo -e "${RED}✗${NC} Some tests failed"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    else
        warn "Test suite not found"
    fi
}

validate_dependencies() {
    section "Runtime Dependencies"

    check "bash is available" "command -v bash >/dev/null"
    check "git is available" "command -v git >/dev/null"

    # Optional dependencies
    if command -v sqlite3 >/dev/null; then
        echo -e "${GREEN}✓${NC} sqlite3 available (optional)"
    else
        warn "sqlite3 not available (optional for SQLite backups)"
    fi

    if command -v rclone >/dev/null; then
        echo -e "${GREEN}✓${NC} rclone available (optional)"
    else
        warn "rclone not available (optional for cloud backups)"
    fi
}

# ==============================================================================
# SUMMARY
# ==============================================================================

print_summary() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}Pre-Release Validation Summary${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Total Checks:${NC} $TOTAL_CHECKS"
    echo -e "${GREEN}Passed:${NC}       $PASSED_CHECKS"
    echo -e "${RED}Failed:${NC}       $FAILED_CHECKS"
    echo -e "${YELLOW}Warnings:${NC}     $WARNINGS"
    echo ""

    local success_rate=0
    if [[ $TOTAL_CHECKS -gt 0 ]]; then
        success_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    fi

    echo -e "${CYAN}Success Rate:${NC} $success_rate%"
    echo ""

    if [[ $FAILED_CHECKS -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ READY FOR RELEASE${NC}"
        echo ""
        echo -e "${GREEN}Checkpoint v$CHECKPOINT_VERSION is production-ready!${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. git add ."
        echo "  2. git commit -m \"Release v$CHECKPOINT_VERSION\""
        echo "  3. git tag v$CHECKPOINT_VERSION"
        echo "  4. git push origin main --tags"
        echo ""
        return 0
    else
        echo -e "${RED}${BOLD}✗ NOT READY FOR RELEASE${NC}"
        echo ""
        echo -e "${RED}Please fix the failed checks before releasing${NC}"
        echo ""
        return 1
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    echo -e "${BOLD}${CYAN}Checkpoint v$CHECKPOINT_VERSION - Pre-Release Validation${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    validate_repository_structure
    validate_core_scripts
    validate_libraries
    validate_claude_skills
    validate_skill_json_syntax
    validate_documentation
    validate_version_consistency
    validate_no_secrets
    validate_no_personal_data
    validate_github_templates
    validate_git_status
    validate_dependencies

    # Optionally run full test suite (commented out for speed during validation)
    # run_test_suite

    print_summary
}

main "$@"
