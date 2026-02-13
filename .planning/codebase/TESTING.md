# Testing Patterns

**Analysis Date:** 2026-02-12

## Test Framework

**Runner:**
- Custom bash test framework — `tests/test-framework.sh`
- Zero external dependencies, Bash 3.2+ compatible
- Color-coded output with pass/fail tracking

**Assertion Library:**
- Built-in assertions in `tests/test-framework.sh`:
  - `assert_equals "expected" "actual" [message]`
  - `assert_not_equals "expected" "actual" [message]`
  - `assert_contains "haystack" "needle" [message]`
  - `assert_not_contains "haystack" "needle" [message]`
  - `assert_file_exists "file" [message]`
  - `assert_file_not_exists "file" [message]`
  - `assert_dir_exists "dir" [message]`
  - `assert_success [exit_code] [message]`
  - `assert_failure [exit_code] [message]`
  - `assert_exit_code expected actual [message]`

**Run Commands:**
```bash
./tests/smoke-test.sh                          # Quick smoke test (22 tests, ~5 seconds)
./tests/run-all-tests.sh                       # Full suite (290+ tests, 3-5 minutes)
bash tests/unit/test-core-functions.sh          # Single test file
bash tests/integration/test-backup-restore-workflow.sh  # Integration tests
```

## Test File Organization

**Location:**
- Separate `tests/` directory with category subdirectories
- Not co-located with source

**Naming:**
- `test-*.sh` for all test files
- `smoke-test.sh` for quick validation
- `run-all-tests.sh` for master test runner

**Structure:**
```
tests/
├── test-framework.sh                          # Core framework (assertions, fixtures)
├── smoke-test.sh                              # Quick validation (22 tests)
├── run-all-tests.sh                           # Master test runner
├── unit/                                      # Unit tests (~50 tests)
│   ├── test-core-functions.sh                 # Config validation, state management
│   └── test-library.sh                        # Library function tests
├── integration/                               # Integration tests (~60 tests)
│   ├── test-backup-restore-workflow.sh        # Full backup/restore cycle
│   ├── test-cloud-backup.sh                   # Cloud integration
│   ├── test-command-workflow.sh               # CLI command workflows
│   ├── test-error-recovery.sh                 # Error recovery paths
│   ├── test-fresh-install.sh                  # Clean install validation
│   └── test-integrations.sh                   # Platform integrations
├── e2e/                                       # End-to-end tests (80+ tests)
│   ├── test-user-journeys.sh                  # Complete user workflows
│   └── test-v2.2-features.sh                  # Feature-specific E2E
├── compatibility/                             # Platform tests (~40 tests)
│   └── test-bash-compatibility.sh             # Bash 3.2 vs 4+ compatibility
├── stress/                                    # Edge cases (~60 tests)
│   ├── test-edge-cases.sh                     # Boundary conditions
│   ├── test-concurrent-backups.sh             # Race conditions
│   ├── test-interrupted-backup.sh             # Interruption recovery
│   └── test-large-files.sh                    # Large file handling
├── legacy/                                    # Legacy compatibility
│   └── test-backup-system.sh                  # v1 compatibility
├── manual/                                    # Manual test procedures
└── reports/                                   # Test results
    ├── test-report-*.txt                      # Text reports
    ├── test-report-*.json                     # JSON reports
    └── test-report-*.html                     # HTML reports
```

## Test Structure

**Suite Organization:**
```bash
#!/bin/bash
# Unit Tests: Core Backup Functions

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT

test_suite "Configuration Validation"

test_case "validate_config_basic - should accept valid minimal config"
if TEST_CONFIG="$TEST_TEMP_DIR/test-config.sh" && \
   cat > "$TEST_CONFIG" <<'EOF'
PROJECT_DIR="/tmp/test-project"
PROJECT_NAME="TestProject"
BACKUP_DIR="/tmp/test-project/backups"
EOF
   mkdir -p "/tmp/test-project" && \
   [[ -f "$TEST_CONFIG" ]]; then
    test_pass
else
    test_fail "Failed to create valid config"
fi
```

**Patterns:**
- `test_suite "Name"` for logical grouping
- `test_case "Description"` for individual tests
- `test_pass` / `test_fail "Reason"` for results
- `print_test_summary` at end for totals
- Temporary directory for test isolation (`$TEST_TEMP_DIR`)

## Mocking

**Framework:**
- No formal mocking framework
- Test isolation via temporary directories
- Function override for stubbing (source replacement)

**Patterns:**
```bash
# Create test fixtures
TEST_TEMP_DIR=$(mktemp -d)
mkdir -p "$TEST_TEMP_DIR/project/backups"

# Create test config
cat > "$TEST_TEMP_DIR/project/.backup-config.sh" <<'EOF'
PROJECT_DIR="$TEST_TEMP_DIR/project"
BACKUP_DIR="$TEST_TEMP_DIR/project/backups"
EOF

# Cleanup
rm -rf "$TEST_TEMP_DIR"
```

**What to Mock:**
- File system state (create temp directories with test fixtures)
- Config files (generate in temp directory)
- Database files (create minimal SQLite/test files)

## Fixtures and Factories

**Test Data:**
- Created inline or via temp directory setup
- No shared fixture files (each test creates its own)
- Temporary directories cleaned up after test

**Location:**
- Factory code: Inline in test files
- Temp directories: System `mktemp -d`

## Coverage

**Requirements:**
- 290+ tests with 100% pass rate (22/22 smoke tests verified)
- No formal coverage measurement tool (bash limitation)
- Coverage tracked by test categories: unit, integration, E2E, compatibility, stress

**Test Categories:**
1. Smoke (22 tests) — Syntax validation, basic functionality, file existence
2. Unit (~50 tests) — Core functions, config validation, state management
3. Integration (~60 tests) — Complete workflows, database ops, file archiving
4. E2E (80+ tests) — User journeys, fresh install, disaster recovery
5. Compatibility (~40 tests) — Bash 3.2 vs 4+, macOS vs Linux
6. Stress (~60 tests) — Large files, permissions, edge cases, race conditions

**View Results:**
```bash
# Reports generated in tests/reports/
ls tests/reports/test-report-*
```

## Test Types

**Unit Tests:**
- Scope: Single function in isolation
- Location: `tests/unit/`
- Speed: Fast (<1s per test)
- Examples: `test-core-functions.sh`, `test-library.sh`

**Integration Tests:**
- Scope: Multiple modules working together
- Location: `tests/integration/`
- Setup: Temp directories with fixtures
- Examples: `test-backup-restore-workflow.sh`, `test-cloud-backup.sh`

**E2E Tests:**
- Scope: Full user workflows end-to-end
- Location: `tests/e2e/`
- Setup: Fresh project simulation
- Examples: `test-user-journeys.sh`, `test-v2.2-features.sh`

**Compatibility Tests:**
- Scope: Cross-platform and cross-version
- Location: `tests/compatibility/`
- Focus: Bash 3.2 vs 4+, macOS vs Linux patterns

**Stress Tests:**
- Scope: Edge cases, concurrency, large files
- Location: `tests/stress/`
- Focus: Race conditions, interrupted backups, permission errors

## Common Patterns

**ShellCheck Directives:**
```bash
# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"
```

**Test Case Pattern:**
```bash
test_case "WORKFLOW 1: Fresh installation and first backup"
if [some_condition]; then
    test_pass
else
    test_fail "Expected X but got Y"
fi
```

**Snapshot Testing:**
- Not used — explicit assertions preferred

---

*Testing analysis: 2026-02-12*
*Update when test patterns change*
