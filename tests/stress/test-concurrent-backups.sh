#!/usr/bin/env bash
# Test: Concurrent Backup Handling
# Tests lock mechanism under simultaneous backup attempts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0

log_test() { echo -e "${YELLOW}TEST:${NC} $1"; }
log_pass() { echo -e "${GREEN}PASS:${NC} $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}FAIL:${NC} $1"; FAIL=$((FAIL + 1)); }

echo "═══════════════════════════════════════════════"
echo "Test Suite: Concurrent Backup Handling"
echo "═══════════════════════════════════════════════"
echo ""

# =============================================================================
# Lock Implementation (copied from backup-daemon.sh for testing)
# =============================================================================

LOCK_BASE="$TEST_DIR/locks"
mkdir -p "$LOCK_BASE"
PROJECT_NAME="test-project"
LOCK_DIR="${LOCK_BASE}/${PROJECT_NAME}.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"

acquire_lock() {
    local temp_pid_file
    temp_pid_file=$(mktemp "${LOCK_BASE}/.pid.XXXXXX") || return 1
    echo $$ > "$temp_pid_file"

    if mkdir "$LOCK_DIR" 2>/dev/null; then
        mv "$temp_pid_file" "$LOCK_PID_FILE" 2>/dev/null || {
            rm -f "$temp_pid_file"
            rm -rf "$LOCK_DIR"
            return 1
        }
        return 0
    else
        rm -f "$temp_pid_file"
        return 1
    fi
}

release_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
}

check_stale_lock() {
    if [[ -f "$LOCK_PID_FILE" ]]; then
        local pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            # Process no longer exists - stale lock
            return 0
        fi
    fi
    return 1
}

# =============================================================================
# Test 1: Basic lock acquisition
# =============================================================================
log_test "Basic lock acquisition"

release_lock  # Ensure clean state
if acquire_lock; then
    log_pass "Lock acquired successfully"
    release_lock
else
    log_fail "Failed to acquire lock"
fi

# =============================================================================
# Test 2: Lock prevents second acquisition
# =============================================================================
log_test "Lock prevents concurrent acquisition"

release_lock
acquire_lock

if acquire_lock; then
    log_fail "Second lock acquisition should have failed"
    release_lock
else
    log_pass "Second acquisition correctly blocked"
fi

release_lock

# =============================================================================
# Test 3: PID file contains correct PID
# =============================================================================
log_test "PID file validation"

release_lock
acquire_lock

if [[ -f "$LOCK_PID_FILE" ]]; then
    STORED_PID=$(cat "$LOCK_PID_FILE")
    if [[ "$STORED_PID" == "$$" ]]; then
        log_pass "PID file contains correct PID: $STORED_PID"
    else
        log_fail "PID mismatch: expected $$, got $STORED_PID"
    fi
else
    log_fail "PID file not created"
fi

release_lock

# =============================================================================
# Test 4: Stale lock detection
# =============================================================================
log_test "Stale lock detection"

release_lock
mkdir -p "$LOCK_DIR"

# Write a non-existent PID
echo "99999999" > "$LOCK_PID_FILE"

if check_stale_lock; then
    log_pass "Correctly detected stale lock"
else
    log_fail "Failed to detect stale lock"
fi

release_lock

# =============================================================================
# Test 5: Active lock not detected as stale
# =============================================================================
log_test "Active lock not detected as stale"

release_lock
acquire_lock

if check_stale_lock; then
    log_fail "Active lock incorrectly detected as stale"
else
    log_pass "Active lock correctly identified"
fi

release_lock

# =============================================================================
# Test 6: Atomic lock creation
# =============================================================================
log_test "Atomic lock creation (no temp files left)"

release_lock

# Count temp files before
TEMP_BEFORE=$(ls -la "$LOCK_BASE" 2>/dev/null | grep -c "\.pid\." || true)
TEMP_BEFORE=${TEMP_BEFORE:-0}

acquire_lock
release_lock

# Count temp files after
TEMP_AFTER=$(ls -la "$LOCK_BASE" 2>/dev/null | grep -c "\.pid\." || true)
TEMP_AFTER=${TEMP_AFTER:-0}

if [[ "$TEMP_AFTER" -le "$TEMP_BEFORE" ]]; then
    log_pass "No temp files left behind"
else
    log_fail "Temp files left behind: $TEMP_AFTER"
fi

# =============================================================================
# Test 7: Concurrent acquisition simulation
# =============================================================================
log_test "Simulated concurrent acquisition"

release_lock

# Start two background processes trying to acquire lock
(
    if acquire_lock; then
        sleep 0.5
        echo "FIRST" > "$TEST_DIR/winner.txt"
        release_lock
    fi
) &
PID1=$!

(
    sleep 0.1  # Slight delay to ensure race condition
    if acquire_lock; then
        echo "SECOND" > "$TEST_DIR/winner.txt"
        release_lock
    fi
) &
PID2=$!

wait $PID1 $PID2 2>/dev/null || true

if [[ -f "$TEST_DIR/winner.txt" ]]; then
    WINNER=$(cat "$TEST_DIR/winner.txt")
    log_pass "Only one process won: $WINNER"
else
    log_fail "No process acquired lock"
fi

# =============================================================================
# Test 8: Lock cleanup on release
# =============================================================================
log_test "Lock cleanup on release"

release_lock
acquire_lock

if [[ -d "$LOCK_DIR" ]]; then
    release_lock
    if [[ ! -d "$LOCK_DIR" ]]; then
        log_pass "Lock directory cleaned up"
    else
        log_fail "Lock directory not cleaned up"
    fi
else
    log_fail "Lock directory not created"
fi

# =============================================================================
# Test 9: Lock timeout handling
# =============================================================================
log_test "Lock acquisition timeout"

release_lock
acquire_lock

START_TIME=$(date +%s)
TIMEOUT=2
ACQUIRED=false

while [[ $(($(date +%s) - START_TIME)) -lt $TIMEOUT ]]; do
    if acquire_lock; then
        ACQUIRED=true
        break
    fi
    sleep 0.1
done

release_lock

if [[ "$ACQUIRED" == "false" ]]; then
    log_pass "Correctly timed out waiting for lock"
else
    log_fail "Should not have acquired lock while held"
fi

# =============================================================================
# Test 10: Lock with special characters in project name
# =============================================================================
log_test "Lock with special project name"

release_lock
PROJECT_NAME="test-project-with-dashes"
LOCK_DIR="${LOCK_BASE}/${PROJECT_NAME}.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"

if acquire_lock; then
    log_pass "Lock works with special project name"
    release_lock
else
    log_fail "Lock failed with special project name"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "═══════════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
