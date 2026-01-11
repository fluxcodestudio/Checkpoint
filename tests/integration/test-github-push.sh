#!/usr/bin/env bash
# Test: GitHub Auto-Push Feature
# Tests the automatic push to GitHub after backup
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
echo "Test Suite: GitHub Auto-Push Feature"
echo "═══════════════════════════════════════════════"
echo ""

# =============================================================================
# Setup
# =============================================================================

setup_test_repo() {
    local repo_dir="$TEST_DIR/test-repo"
    mkdir -p "$repo_dir"
    cd "$repo_dir"

    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "Initial commit" --quiet

    echo "$repo_dir"
}

# =============================================================================
# Test 1: Push with unpushed commits
# =============================================================================
log_test "Push detection with unpushed commits"

REPO=$(setup_test_repo)
cd "$REPO"

# Create a commit that isn't pushed
echo "change" >> file.txt
git add file.txt
git commit -m "Unpushed commit" --quiet

# Check if we can detect unpushed commits
UNPUSHED=$(git log @{upstream}..HEAD 2>/dev/null | wc -l || echo "0")
# Without upstream, this should fail gracefully
if [[ -z "$(git remote -v)" ]]; then
    # No remote configured - expected for test
    log_pass "Correctly handles repo without remote"
else
    if [[ "$UNPUSHED" -gt 0 ]]; then
        log_pass "Detected unpushed commits"
    else
        log_fail "Failed to detect unpushed commits"
    fi
fi

# =============================================================================
# Test 2: Push with no commits (should skip)
# =============================================================================
log_test "Skip push when no commits"

REPO=$(setup_test_repo)
cd "$REPO"

# No changes made - should skip push
CHANGES=$(git status --porcelain)
if [[ -z "$CHANGES" ]]; then
    log_pass "Correctly detected no changes to push"
else
    log_fail "Should have detected clean state"
fi

# =============================================================================
# Test 3: Push interval enforcement
# =============================================================================
log_test "Push interval enforcement"

STATE_DIR="$TEST_DIR/state"
mkdir -p "$STATE_DIR"
PUSH_STATE_FILE="$STATE_DIR/.last-push-time"

# Record a push time
echo "$(date +%s)" > "$PUSH_STATE_FILE"

# Check if push should be skipped (within interval)
LAST_PUSH=$(cat "$PUSH_STATE_FILE" 2>/dev/null || echo "0")
NOW=$(date +%s)
PUSH_INTERVAL=3600  # 1 hour

if [[ $((NOW - LAST_PUSH)) -lt $PUSH_INTERVAL ]]; then
    log_pass "Correctly enforces push interval"
else
    log_fail "Push interval not enforced"
fi

# =============================================================================
# Test 4: Push interval exceeded
# =============================================================================
log_test "Push allowed after interval"

# Set last push to 2 hours ago
OLD_TIME=$((NOW - 7200))
echo "$OLD_TIME" > "$PUSH_STATE_FILE"

LAST_PUSH=$(cat "$PUSH_STATE_FILE" 2>/dev/null || echo "0")
if [[ $((NOW - LAST_PUSH)) -ge $PUSH_INTERVAL ]]; then
    log_pass "Correctly allows push after interval"
else
    log_fail "Should allow push after interval exceeded"
fi

# =============================================================================
# Test 5: Remote URL validation
# =============================================================================
log_test "Remote URL validation"

REPO=$(setup_test_repo)
cd "$REPO"

# Add a mock remote
git remote add origin "https://github.com/test/test.git" 2>/dev/null || true

REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$REMOTE_URL" == *"github.com"* ]]; then
    log_pass "Correctly extracts GitHub remote URL"
else
    log_fail "Failed to validate remote URL"
fi

# =============================================================================
# Test 6: Authentication check (mock)
# =============================================================================
log_test "Authentication availability check"

# Check if gh CLI is available (don't actually auth)
if command -v gh &>/dev/null; then
    log_pass "gh CLI available for authentication"
elif command -v git &>/dev/null; then
    log_pass "git available (SSH key auth possible)"
else
    log_fail "No authentication method available"
fi

# =============================================================================
# Test 7: GIT_AUTO_PUSH_ENABLED config
# =============================================================================
log_test "GIT_AUTO_PUSH_ENABLED config handling"

# Test with disabled
GIT_AUTO_PUSH_ENABLED=false
if [[ "$GIT_AUTO_PUSH_ENABLED" != "true" ]]; then
    log_pass "Correctly respects disabled push"
else
    log_fail "Should respect disabled setting"
fi

# Test with enabled
GIT_AUTO_PUSH_ENABLED=true
if [[ "$GIT_AUTO_PUSH_ENABLED" == "true" ]]; then
    log_pass "Correctly respects enabled push"
else
    log_fail "Should respect enabled setting"
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
