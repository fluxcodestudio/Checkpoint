#!/bin/bash
# Unit Tests: Diff Command (backup-diff.sh library functions)

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$SCRIPT_DIR/lib/platform/compat.sh"
source "$SCRIPT_DIR/lib/ui/time-size-utils.sh"
source "$SCRIPT_DIR/lib/core/config.sh"
source "$SCRIPT_DIR/lib/retention-policy.sh"
source "$SCRIPT_DIR/lib/features/backup-diff.sh"

# ==============================================================================
# extract_timestamp TESTS
# ==============================================================================

test_suite "extract_timestamp"

test_case "extract timestamp with PID suffix"
result=$(extract_timestamp "app.js.20260216_043343_72545")
if assert_equals "20260216_043343" "$result" "Should extract timestamp before PID"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "extract timestamp without PID suffix"
result=$(extract_timestamp "app.js.20260216_031101")
if assert_equals "20260216_031101" "$result" "Should extract timestamp without PID"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "extract timestamp with database pattern"
result=$(extract_timestamp "mydb_20260103_120000.db.gz")
if assert_equals "20260103_120000" "$result" "Should extract timestamp from database filename"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "extract timestamp with no timestamp"
result=$(extract_timestamp "README.md")
if assert_equals "" "$result" "Should return empty for no timestamp"; then
    test_pass
else
    test_fail "Got: $result"
fi

# ==============================================================================
# discover_snapshots TESTS
# ==============================================================================

test_suite "discover_snapshots"

test_case "discover snapshots finds timestamps from archived files"
# Create temp dir with mock archived files
snap_dir="$TEST_TEMP_DIR/archived"
mkdir -p "$snap_dir/src"
touch "$snap_dir/app.js.20260216_043343_72545"
touch "$snap_dir/app.js.20260215_192308"
touch "$snap_dir/src/lib.js.20260216_031101_12345"
touch "$snap_dir/src/lib.js.20260215_192308"

result=$(discover_snapshots "$snap_dir")
# Should have 3 unique timestamps sorted descending
first_line=$(echo "$result" | head -1)
line_count=$(echo "$result" | grep -c . || true)

if assert_equals "20260216_043343" "$first_line" "Most recent timestamp first" && \
   assert_equals "3" "$line_count" "Should have 3 unique timestamps"; then
    test_pass
else
    test_fail "Got $line_count lines, first: $first_line"
fi

test_case "discover snapshots empty directory returns nothing"
empty_dir="$TEST_TEMP_DIR/empty_archived"
mkdir -p "$empty_dir"

result=$(discover_snapshots "$empty_dir" 2>/dev/null || true)
if assert_empty "$result" "Should return empty for empty dir"; then
    test_pass
else
    test_fail "Got: $result"
fi

# ==============================================================================
# get_backup_excludes TESTS
# ==============================================================================

test_suite "get_backup_excludes"

test_case "get_backup_excludes returns expected patterns"
result=$(get_backup_excludes)

# Check for expected patterns
has_backups=false
has_git=false
[[ "$result" == *"--exclude=backups/"* ]] && has_backups=true
[[ "$result" == *"--exclude=.git/"* ]] && has_git=true

line_count=$(echo "$result" | grep -c . || true)

if [[ "$has_backups" == "true" ]] && [[ "$has_git" == "true" ]] && \
   assert_equals "34" "$line_count" "Should have 34 exclude patterns"; then
    test_pass
else
    test_fail "backups=$has_backups, git=$has_git, lines=$line_count"
fi

# ==============================================================================
# format_diff_json TESTS
# ==============================================================================

test_suite "format_diff_json"

test_case "format_diff_json produces valid JSON"
# Set up global arrays
DIFF_ADDED=("new-file.js" "src/new.ts")
DIFF_MODIFIED=("app.js")
DIFF_REMOVED=("old-file.js")

result=$(format_diff_json)

# Check it starts with { and contains expected keys
starts_ok=false
has_added=false
has_summary=false
[[ "$result" == "{"* ]] && starts_ok=true
[[ "$result" == *'"added":'* ]] && has_added=true
[[ "$result" == *'"summary":'* ]] && has_summary=true

# Try validating with python3 if available
json_valid=false
if command -v python3 &>/dev/null; then
    if echo "$result" | python3 -m json.tool &>/dev/null; then
        json_valid=true
    fi
else
    # No python3 - just check structure
    json_valid=true
fi

if [[ "$starts_ok" == "true" ]] && [[ "$has_added" == "true" ]] && \
   [[ "$has_summary" == "true" ]] && [[ "$json_valid" == "true" ]]; then
    test_pass
else
    test_fail "starts_ok=$starts_ok, has_added=$has_added, has_summary=$has_summary, json_valid=$json_valid"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

print_test_summary
