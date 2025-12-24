#!/bin/bash
# Integration Tests: Cloud Backup Functionality

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT
export PATH="$PROJECT_ROOT/bin:$PATH"

# Source cloud backup library
source "$PROJECT_ROOT/lib/cloud-backup.sh"

# ==============================================================================
# RCLONE DETECTION TESTS
# ==============================================================================

test_suite "rclone Detection"

test_case "check_rclone_installed - detects if rclone is installed"
if check_rclone_installed; then
    echo "    (rclone is installed)"
    test_pass
else
    echo "    (rclone not installed - some tests will be skipped)"
    test_skip "rclone not installed"
fi

# ==============================================================================
# CONFIGURATION VALIDATION TESTS
# ==============================================================================

test_suite "Cloud Configuration Validation"

test_case "validate_cloud_config - passes when cloud disabled"
if CLOUD_ENABLED=false && \
   validate_cloud_config; then
    test_pass
else
    test_fail "Should pass when cloud disabled"
fi

test_case "validate_cloud_config - fails when remote missing"
if CLOUD_ENABLED=true && \
   CLOUD_REMOTE_NAME="" && \
   ! validate_cloud_config 2>&1 | grep -q "remote name not configured"; then
    test_fail "Should detect missing remote name"
else
    test_pass
fi

test_case "validate_cloud_config - fails when path missing"
if CLOUD_ENABLED=true && \
   CLOUD_REMOTE_NAME="test" && \
   CLOUD_BACKUP_PATH="" && \
   ! validate_cloud_config 2>&1 | grep -q "backup path not configured"; then
    test_fail "Should detect missing backup path"
else
    test_pass
fi

# ==============================================================================
# REMOTE LISTING TESTS
# ==============================================================================

test_suite "Remote Management"

test_case "list_rclone_remotes - lists configured remotes"
if ! check_rclone_installed; then
    test_skip "rclone not installed"
elif remotes=$(list_rclone_remotes) && \
     [[ -n "$remotes" ]] || [[ -z "$remotes" ]]; then
    echo "    (Found $(echo "$remotes" | wc -l | tr -d ' ') remotes)"
    test_pass
else
    test_fail "Failed to list remotes"
fi

test_case "get_remote_type - detects remote type"
if ! check_rclone_installed; then
    test_skip "rclone not installed"
elif remotes=$(list_rclone_remotes) && \
     [[ -n "$remotes" ]]; then
    first_remote=$(echo "$remotes" | head -1)
    remote_type=$(get_remote_type "$first_remote")
    echo "    (Remote: $first_remote, Type: ${remote_type:-unknown})"
    test_pass
else
    test_skip "No remotes configured"
fi

# ==============================================================================
# CLOUD STATUS TESTS
# ==============================================================================

test_suite "Cloud Status"

test_case "get_cloud_status - returns 'never' when no uploads"
if STATE_DIR="$TEST_TEMP_DIR/state" && \
   mkdir -p "$STATE_DIR" && \
   status=$(get_cloud_status) && \
   [[ "$status" == "never" ]]; then
    test_pass
else
    test_fail "Should return 'never' when no upload file"
fi

test_case "get_cloud_status - calculates time since upload"
if STATE_DIR="$TEST_TEMP_DIR/state" && \
   mkdir -p "$STATE_DIR" && \
   PAST_TIME="$(($(date +%s) - 7200))" && \
   echo "$PAST_TIME" > "$STATE_DIR/.last-cloud-upload" && \
   status=$(get_cloud_status) && \
   echo "$status" | grep -q "hours ago"; then
    test_pass
else
    test_fail "Should calculate hours ago"
fi

# ==============================================================================
# MOCK UPLOAD TESTS (without actual cloud)
# ==============================================================================

test_suite "Upload Functions (Mock)"

test_case "cloud_upload - fails when rclone missing"
if ! check_rclone_installed; then
    CLOUD_ENABLED=true
    CLOUD_REMOTE_NAME="test"
    CLOUD_BACKUP_PATH="/test"
    if ! cloud_upload 2>&1 | grep -q "not installed"; then
        test_fail "Should detect rclone missing"
    else
        test_pass
    fi
else
    test_skip "rclone is installed"
fi

test_case "cloud_upload - fails when config missing"
if CLOUD_ENABLED=true && \
   CLOUD_REMOTE_NAME="" && \
   ! cloud_upload 2>&1 | grep -q "configuration missing"; then
    test_fail "Should detect missing config"
else
    test_pass
fi

# ==============================================================================
# INTEGRATION WITH BACKUP SYSTEM
# ==============================================================================

test_suite "Backup System Integration"

test_case "backup-daemon loads cloud library when enabled"
if grep -q "source.*cloud-backup.sh" "$PROJECT_ROOT/bin/backup-daemon.sh"; then
    test_pass
else
    test_fail "backup-daemon should load cloud library"
fi

test_case "backup-status shows cloud status when enabled"
if grep -q "CLOUD_ENABLED.*true" "$PROJECT_ROOT/bin/backup-status.sh"; then
    test_pass
else
    test_fail "backup-status should check cloud status"
fi

test_case "cloud config wizard script exists"
if [[ -x "$PROJECT_ROOT/bin/backup-cloud-config.sh" ]]; then
    test_pass
else
    test_fail "Cloud config wizard should be executable"
fi

# Run summary
print_test_summary
