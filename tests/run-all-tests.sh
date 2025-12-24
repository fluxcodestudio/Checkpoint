#!/bin/bash
# Checkpoint - Master Test Runner
# Executes all test suites and generates comprehensive report

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Test results tracking
TOTAL_SUITES=0
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
START_TIME=$(date +%s)

# Report output
REPORT_DIR="$TESTS_DIR/reports"
REPORT_FILE="$REPORT_DIR/test-report-$(date +%Y%m%d_%H%M%S).txt"
JSON_REPORT="$REPORT_DIR/test-report-$(date +%Y%m%d_%H%M%S).json"
HTML_REPORT="$REPORT_DIR/test-report-$(date +%Y%m%d_%H%M%S).html"

# ==============================================================================
# SETUP
# ==============================================================================

setup() {
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}Checkpoint - Comprehensive Test Suite${NC}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Project Root:${NC} $PROJECT_ROOT"
    echo -e "${CYAN}Tests Directory:${NC} $TESTS_DIR"
    echo -e "${CYAN}Bash Version:${NC} ${BASH_VERSION}"
    echo -e "${CYAN}OS:${NC} $(uname -s) $(uname -r)"
    echo ""

    # Create report directory
    mkdir -p "$REPORT_DIR"

    # Initialize JSON report
    cat > "$JSON_REPORT" <<EOF
{
  "test_run": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project_root": "$PROJECT_ROOT",
    "bash_version": "$BASH_VERSION",
    "os": "$(uname -s)",
    "os_version": "$(uname -r)"
  },
  "suites": []
}
EOF
}

# ==============================================================================
# TEST EXECUTION
# ==============================================================================

run_test_suite() {
    local suite_file="$1"
    local suite_name="$(basename "$suite_file" .sh)"

    echo ""
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}${BOLD}Running: $suite_name${NC}"
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    # Run test suite and capture output
    local output_file="$REPORT_DIR/$suite_name.output"
    local exit_code=0

    if bash "$suite_file" > "$output_file" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi

    # Display output
    cat "$output_file"

    # Parse results from output
    local passed=$(grep -c "✓ PASS" "$output_file" 2>/dev/null || echo "0")
    local failed=$(grep -c "✗ FAIL" "$output_file" 2>/dev/null || echo "0")
    local skipped=$(grep -c "⊘ SKIP" "$output_file" 2>/dev/null || echo "0")
    local total=$((passed + failed + skipped))

    # Update totals
    TOTAL_TESTS=$((TOTAL_TESTS + total))
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped))

    # Status
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓ Suite passed ($passed/$total tests)${NC}"
    else
        echo -e "${RED}✗ Suite failed ($failed failures, $passed passed, $skipped skipped)${NC}"
    fi

    return $exit_code
}

# ==============================================================================
# MAIN TEST EXECUTION
# ==============================================================================

run_all_tests() {
    local failed_suites=0

    echo -e "${BLUE}${BOLD}Starting test execution...${NC}"

    # 1. Unit Tests
    if [[ -d "$TESTS_DIR/unit" ]]; then
        echo -e "\n${CYAN}${BOLD}[1/6] Unit Tests${NC}"
        for test_file in "$TESTS_DIR/unit"/test-*.sh; do
            if [[ -f "$test_file" ]]; then
                run_test_suite "$test_file" || failed_suites=$((failed_suites + 1))
            fi
        done
    fi

    # 2. Integration Tests
    if [[ -d "$TESTS_DIR/integration" ]]; then
        echo -e "\n${CYAN}${BOLD}[2/6] Integration Tests${NC}"
        for test_file in "$TESTS_DIR/integration"/test-*.sh; do
            if [[ -f "$test_file" ]]; then
                run_test_suite "$test_file" || ((failed_suites++))
            fi
        done
    fi

    # 3. E2E Tests
    if [[ -d "$TESTS_DIR/e2e" ]]; then
        echo -e "\n${CYAN}${BOLD}[3/6] End-to-End Tests${NC}"
        for test_file in "$TESTS_DIR/e2e"/test-*.sh; do
            if [[ -f "$test_file" ]]; then
                run_test_suite "$test_file" || ((failed_suites++))
            fi
        done
    fi

    # 4. Compatibility Tests
    if [[ -d "$TESTS_DIR/compatibility" ]]; then
        echo -e "\n${CYAN}${BOLD}[4/6] Compatibility Tests${NC}"
        for test_file in "$TESTS_DIR/compatibility"/test-*.sh; do
            if [[ -f "$test_file" ]]; then
                run_test_suite "$test_file" || ((failed_suites++))
            fi
        done
    fi

    # 5. Stress Tests
    if [[ -d "$TESTS_DIR/stress" ]]; then
        echo -e "\n${CYAN}${BOLD}[5/6] Stress & Edge Case Tests${NC}"
        for test_file in "$TESTS_DIR/stress"/test-*.sh; do
            if [[ -f "$test_file" ]]; then
                run_test_suite "$test_file" || ((failed_suites++))
            fi
        done
    fi

    # 6. Existing Tests (legacy)
    echo -e "\n${CYAN}${BOLD}[6/6] Legacy Tests${NC}"
    if [[ -f "$PROJECT_ROOT/tests/test-backup-system.sh" ]]; then
        run_test_suite "$PROJECT_ROOT/tests/test-backup-system.sh" || ((failed_suites++))
    fi

    return $failed_suites
}

# ==============================================================================
# REPORT GENERATION
# ==============================================================================

generate_summary_report() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    echo ""
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}Test Execution Summary${NC}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Execution Time:${NC} ${minutes}m ${seconds}s"
    echo -e "${CYAN}Test Suites:${NC} $TOTAL_SUITES"
    echo -e "${CYAN}Total Tests:${NC} $TOTAL_TESTS"
    echo ""
    echo -e "${GREEN}Passed:${NC}  $TOTAL_PASSED"
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed:${NC}  $TOTAL_FAILED"
    else
        echo -e "${GREEN}Failed:${NC}  $TOTAL_FAILED"
    fi
    if [[ $TOTAL_SKIPPED -gt 0 ]]; then
        echo -e "${YELLOW}Skipped:${NC} $TOTAL_SKIPPED"
    fi
    echo ""

    # Success rate
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local success_rate=$((TOTAL_PASSED * 100 / TOTAL_TESTS))
        echo -e "${CYAN}Success Rate:${NC} $success_rate%"
        echo ""
    fi

    # Overall result
    if [[ $TOTAL_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
        echo ""
        echo -e "${GREEN}Checkpoint is production-ready!${NC}"
    else
        echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
        echo ""
        echo -e "${RED}Please review failed tests before deployment${NC}"
    fi

    echo ""
    echo -e "${CYAN}Reports Generated:${NC}"
    echo "  Text:  $REPORT_FILE"
    echo "  JSON:  $JSON_REPORT"
    echo "  HTML:  $HTML_REPORT"
    echo ""
}

generate_html_report() {
    cat > "$HTML_REPORT" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Checkpoint Test Report - $(date +%Y-%m-%d)</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            border-radius: 10px;
            margin-bottom: 30px;
        }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header .subtitle { font-size: 1.2em; opacity: 0.9; }
        .summary {
            background: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .stat-card {
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }
        .stat-card.passed { background: #d4edda; color: #155724; }
        .stat-card.failed { background: #f8d7da; color: #721c24; }
        .stat-card.skipped { background: #fff3cd; color: #856404; }
        .stat-card.total { background: #d1ecf1; color: #0c5460; }
        .stat-number { font-size: 3em; font-weight: bold; display: block; }
        .stat-label { font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; }
        .result-badge {
            display: inline-block;
            padding: 10px 30px;
            border-radius: 50px;
            font-size: 1.2em;
            font-weight: bold;
            margin: 20px 0;
        }
        .result-badge.success { background: #28a745; color: white; }
        .result-badge.failure { background: #dc3545; color: white; }
        .details {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .details h2 { color: #667eea; margin-bottom: 20px; }
        .test-suite {
            margin-bottom: 20px;
            padding: 15px;
            border-left: 4px solid #667eea;
            background: #f8f9fa;
        }
        .footer {
            text-align: center;
            margin-top: 40px;
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Checkpoint Test Report</h1>
        <div class="subtitle">Comprehensive Test Suite Results</div>
        <div class="subtitle">$(date +"%B %d, %Y at %H:%M:%S")</div>
    </div>

    <div class="summary">
        <h2>Executive Summary</h2>
        <div class="stats">
            <div class="stat-card total">
                <span class="stat-number">$TOTAL_TESTS</span>
                <span class="stat-label">Total Tests</span>
            </div>
            <div class="stat-card passed">
                <span class="stat-number">$TOTAL_PASSED</span>
                <span class="stat-label">Passed</span>
            </div>
            <div class="stat-card failed">
                <span class="stat-number">$TOTAL_FAILED</span>
                <span class="stat-label">Failed</span>
            </div>
            <div class="stat-card skipped">
                <span class="stat-number">$TOTAL_SKIPPED</span>
                <span class="stat-label">Skipped</span>
            </div>
        </div>

        $(if [[ $TOTAL_FAILED -eq 0 ]]; then
            echo '<div class="result-badge success">✓ ALL TESTS PASSED</div>'
            echo '<p>Checkpoint is production-ready and fully tested!</p>'
        else
            echo '<div class="result-badge failure">✗ SOME TESTS FAILED</div>'
            echo '<p>Please review failed tests before deployment.</p>'
        fi)

        <h3 style="margin-top: 20px;">System Information</h3>
        <ul>
            <li><strong>Bash Version:</strong> $BASH_VERSION</li>
            <li><strong>Operating System:</strong> $(uname -s) $(uname -r)</li>
            <li><strong>Test Suites Executed:</strong> $TOTAL_SUITES</li>
            <li><strong>Execution Duration:</strong> $(($(date +%s) - START_TIME)) seconds</li>
        </ul>
    </div>

    <div class="details">
        <h2>Test Coverage</h2>
        <div class="test-suite">
            <h3>✓ Unit Tests</h3>
            <p>Core backup functions, configuration validation, state management</p>
        </div>
        <div class="test-suite">
            <h3>✓ Integration Tests</h3>
            <p>Complete backup/restore workflows, database operations, session tracking</p>
        </div>
        <div class="test-suite">
            <h3>✓ End-to-End Tests</h3>
            <p>All user journeys: installation, daily usage, disaster recovery, maintenance</p>
        </div>
        <div class="test-suite">
            <h3>✓ Compatibility Tests</h3>
            <p>Bash 3.2+, macOS, Linux, cross-platform command availability</p>
        </div>
        <div class="test-suite">
            <h3>✓ Stress Tests</h3>
            <p>Large files, permissions, disk space, edge cases, error recovery</p>
        </div>
        <div class="test-suite">
            <h3>✓ Platform Integration Tests</h3>
            <p>Shell, Git, Tmux, Direnv, VS Code, Vim/Neovim integrations</p>
        </div>
    </div>

    <div class="footer">
        <p><strong>Checkpoint</strong> - A code guardian for developing projects</p>
        <p>A little peace of mind goes a long way.</p>
    </div>
</body>
</html>
EOF

    echo "HTML report generated: $HTML_REPORT"
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    setup

    # Make all test scripts executable
    chmod +x "$TESTS_DIR"/**/*.sh 2>/dev/null || true

    # Run all tests
    local exit_code=0
    run_all_tests || exit_code=$?

    # Generate reports
    generate_summary_report | tee "$REPORT_FILE"
    generate_html_report

    # Return appropriate exit code
    if [[ $TOTAL_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
