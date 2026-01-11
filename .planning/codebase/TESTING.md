# Testing Patterns

**Analysis Date:** 2026-01-10

## Test Framework

**Runner:**
- Custom bash test framework (zero external dependencies)
- Config: `tests/test-framework.sh`

**Assertion Library:**
- Built-in functions in test-framework.sh
- Assertions: `assert_equals`, `assert_contains`, `assert_file_exists`, `assert_dir_exists`, `assert_success`, `assert_failure`, `assert_exit_code`, `assert_empty`, `assert_not_empty`, `assert_matches`

**Run Commands:**
```bash
./tests/smoke-test.sh                    # Quick validation (~5 seconds, 22 tests)
./tests/run-all-tests.sh                 # Full suite (3-5 minutes, 300+ tests)
bash tests/unit/test-core-functions.sh   # Single test file
bash tests/integration/test-backup-restore-workflow.sh  # Specific integration test
```

## Test File Organization

**Location:**
- All tests in `tests/` directory (separate from source)
- Organized by test type in subdirectories

**Naming:**
- test-feature-name.sh for all tests
- No distinction in filename between unit/integration/e2e

**Structure:**
```
tests/
├── test-framework.sh           # Core testing utilities
├── smoke-test.sh               # Quick 22-test validation
├── run-all-tests.sh            # Full suite runner
├── unit/                       # Unit tests (~50 tests)
│   └── test-core-functions.sh
├── integration/                # Workflow tests (~60 tests)
│   ├── test-backup-restore-workflow.sh
│   ├── test-database-types.sh
│   └── test-cloud-backup.sh
├── e2e/                        # End-to-end journeys (80+ tests)
│   ├── test-user-journeys.sh
│   └── test-v2.2-features.sh
├── compatibility/              # Platform tests (~40 tests)
│   └── test-bash-compatibility.sh
├── stress/                     # Edge cases (~60 tests)
│   ├── test-concurrent-backups.sh
│   └── test-large-files.sh
└── reports/                    # Test output (JSON, text)
```

## Test Structure

**Suite Organization:**
```bash
#!/bin/bash
# Integration Tests: [Feature Name]

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT
export PATH="$PROJECT_ROOT/bin:$PATH"

# ==============================================================================
# TEST SUITE: [Name]
# ==============================================================================

test_suite "Suite Name"

test_case "Description of what is being tested"
if [condition]; then
    test_pass
else
    test_fail "Reason for failure"
fi
```

**Patterns:**
- Use `test_suite` to group related tests
- Use `test_case` for individual tests
- Use `test_pass` or `test_fail "reason"` to mark results
- Export PROJECT_ROOT and extend PATH for command access

## Mocking

**Framework:**
- No dedicated mocking framework
- Use temporary directories for isolation
- Override commands via PATH manipulation

**Patterns:**
```bash
# Create isolated test environment
TEST_TEMP_DIR=$(mktemp -d)
cd "$TEST_TEMP_DIR"

# Mock file system state
mkdir -p "$TEST_TEMP_DIR/backups"
echo "test content" > "$TEST_TEMP_DIR/test.txt"

# Cleanup
rm -rf "$TEST_TEMP_DIR"
```

**What to Mock:**
- File system operations (use temp directories)
- External commands (via PATH override)
- User input (redirect stdin)

**What NOT to Mock:**
- Core bash functions
- Simple file operations (test them for real)

## Fixtures and Factories

**Test Data:**
```bash
# Create test project structure
setup_test_project() {
    mkdir -p "$TEST_TEMP_DIR"
    mkdir -p "$TEST_TEMP_DIR/backups/databases"
    mkdir -p "$TEST_TEMP_DIR/backups/files"
    mkdir -p "$TEST_TEMP_DIR/backups/archived"

    # Copy template config
    cp "$PROJECT_ROOT/templates/backup-config.sh" "$TEST_TEMP_DIR/.backup-config.sh"
}
```

**Location:**
- Factory functions defined at top of test file
- Shared fixtures in `tests/fixtures/` (if needed)

## Coverage

**Requirements:**
- Target: 100% user journey coverage
- ~85% line coverage (core), ~75% (integrations)
- No automated coverage enforcement

**Configuration:**
- No coverage tool (pure bash)
- Manual tracking via test categories

**View Coverage:**
```bash
# Test results summary
./tests/run-all-tests.sh
# Outputs to tests/reports/
```

## Test Types

**Unit Tests (`tests/unit/`):**
- Test single functions in isolation
- Mock external dependencies
- Fast: each test <100ms
- Example: `test-core-functions.sh`

**Integration Tests (`tests/integration/`):**
- Test multiple modules together
- Real file system operations
- Example: `test-backup-restore-workflow.sh`

**E2E Tests (`tests/e2e/`):**
- Complete user journeys
- Real command execution
- Example: `test-user-journeys.sh`

**Compatibility Tests (`tests/compatibility/`):**
- Platform-specific validation
- Bash version checks
- Example: `test-bash-compatibility.sh`

**Stress Tests (`tests/stress/`):**
- Edge cases and limits
- Concurrent execution
- Large file handling
- Example: `test-edge-cases.sh`

## Common Patterns

**Async Testing:**
```bash
# Not applicable (bash is synchronous)
# For background processes, use wait:
background_command &
wait $!
test_case "Background command completed"
```

**Error Testing:**
```bash
test_case "Should fail on invalid input"
if ! bash -n "$PROJECT_ROOT/bin/invalid-script.sh" 2>/dev/null; then
    test_pass
else
    test_fail "Expected syntax error"
fi
```

**File System Testing:**
```bash
test_case "Directory structure created"
if assert_dir_exists "$PROJECT_DIR/backups" && \
   assert_dir_exists "$PROJECT_DIR/backups/databases" && \
   assert_dir_exists "$PROJECT_DIR/backups/files"; then
    test_pass
else
    test_fail "Failed to create directories"
fi
```

**Command Output Testing:**
```bash
test_case "Help command shows usage"
if run_command bash "$PROJECT_ROOT/bin/backup-status.sh" --help; then
    assert_success $TEST_EXIT_CODE && \
    assert_contains "$TEST_OUTPUT" "USAGE" && \
    test_pass
else
    test_fail "Help command failed"
fi
```

**Snapshot Testing:**
- Not used in this codebase
- Prefer explicit assertions

## Validation Checklist

Before committing:
- [ ] All scripts pass `bash -n` syntax check
- [ ] Smoke tests pass: `./tests/smoke-test.sh`
- [ ] Full suite passes: `./tests/run-all-tests.sh`
- [ ] New code has corresponding tests

---

*Testing analysis: 2026-01-10*
*Update when test patterns change*
