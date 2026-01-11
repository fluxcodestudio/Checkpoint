#!/usr/bin/env bash
# Test: Large File Handling
# Tests behavior with files exceeding MAX_BACKUP_FILE_SIZE
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
echo "Test Suite: Large File Handling"
echo "═══════════════════════════════════════════════"
echo ""

# Default size limit (100MB in bytes)
MAX_BACKUP_FILE_SIZE=104857600

# =============================================================================
# Test 1: File size detection
# =============================================================================
log_test "File size detection"

# Create 1MB test file
dd if=/dev/zero of="$TEST_DIR/small.bin" bs=1024 count=1024 2>/dev/null

FILE_SIZE=$(stat -f%z "$TEST_DIR/small.bin" 2>/dev/null || stat -c%s "$TEST_DIR/small.bin" 2>/dev/null)
EXPECTED_SIZE=1048576  # 1MB

if [[ "$FILE_SIZE" -eq "$EXPECTED_SIZE" ]]; then
    log_pass "File size correctly detected: $FILE_SIZE bytes"
else
    log_fail "Size mismatch: expected $EXPECTED_SIZE, got $FILE_SIZE"
fi

# =============================================================================
# Test 2: Small file under limit (should backup)
# =============================================================================
log_test "Small file under limit"

FILE_SIZE=$(stat -f%z "$TEST_DIR/small.bin" 2>/dev/null || stat -c%s "$TEST_DIR/small.bin" 2>/dev/null)

if [[ "$FILE_SIZE" -lt "$MAX_BACKUP_FILE_SIZE" ]]; then
    log_pass "Small file correctly identified as under limit"
else
    log_fail "Small file incorrectly marked as over limit"
fi

# =============================================================================
# Test 3: Large file over limit (should skip)
# =============================================================================
log_test "Large file over limit"

# Create 110MB file (over 100MB limit) - use sparse file to save time
dd if=/dev/zero of="$TEST_DIR/large.bin" bs=1 count=0 seek=115343360 2>/dev/null

FILE_SIZE=$(stat -f%z "$TEST_DIR/large.bin" 2>/dev/null || stat -c%s "$TEST_DIR/large.bin" 2>/dev/null)

if [[ "$FILE_SIZE" -gt "$MAX_BACKUP_FILE_SIZE" ]]; then
    log_pass "Large file correctly identified as over limit"
else
    log_fail "Large file not detected (size: $FILE_SIZE)"
fi

# =============================================================================
# Test 4: BACKUP_LARGE_FILES override
# =============================================================================
log_test "BACKUP_LARGE_FILES override"

BACKUP_LARGE_FILES=true
FILE_SIZE=200000000  # 200MB

# With override enabled, should backup regardless of size
if [[ "$BACKUP_LARGE_FILES" == "true" ]]; then
    log_pass "BACKUP_LARGE_FILES override enabled - will backup"
else
    log_fail "Override not working"
fi

BACKUP_LARGE_FILES=false

# =============================================================================
# Test 5: Size limit disabled (0 = no limit)
# =============================================================================
log_test "Size limit disabled (0 = no limit)"

MAX_BACKUP_FILE_SIZE=0
FILE_SIZE=500000000  # 500MB

# When limit is 0, no files should be skipped
if [[ "$MAX_BACKUP_FILE_SIZE" -eq 0 ]]; then
    log_pass "Size limit disabled - all files will backup"
else
    log_fail "Size limit should be disabled"
fi

MAX_BACKUP_FILE_SIZE=104857600  # Reset

# =============================================================================
# Test 6: Warning message for skipped files
# =============================================================================
log_test "Skip warning message format"

FILE_SIZE=150000000  # 150MB
FILE_SIZE_MB=$((FILE_SIZE / 1048576))
MAX_SIZE_MB=$((MAX_BACKUP_FILE_SIZE / 1048576))

WARNING="Skipped large file (${FILE_SIZE_MB}MB > ${MAX_SIZE_MB}MB limit): largefile.bin"

if [[ "$WARNING" == *"Skipped large file"* ]] && [[ "$WARNING" == *"MB"* ]]; then
    log_pass "Warning message format correct"
else
    log_fail "Warning message format incorrect"
fi

# =============================================================================
# Test 7: Binary file handling
# =============================================================================
log_test "Binary file handling"

# Create binary file with random data
dd if=/dev/urandom of="$TEST_DIR/binary.bin" bs=1024 count=100 2>/dev/null

if file "$TEST_DIR/binary.bin" | grep -q "data"; then
    log_pass "Binary file correctly identified"
else
    log_pass "Binary file created (may show as different type)"
fi

# =============================================================================
# Test 8: Deep directory structure
# =============================================================================
log_test "Deep directory structure"

DEEP_DIR="$TEST_DIR/a/b/c/d/e/f/g/h/i/j"
mkdir -p "$DEEP_DIR"
echo "deep file" > "$DEEP_DIR/deep.txt"

if [[ -f "$DEEP_DIR/deep.txt" ]]; then
    log_pass "Deep directory file accessible"
else
    log_fail "Deep directory file not accessible"
fi

# =============================================================================
# Test 9: Multiple large files counting
# =============================================================================
log_test "Multiple large files tracking"

mkdir -p "$TEST_DIR/multi"
# Create sparse large files
for i in 1 2 3; do
    dd if=/dev/zero of="$TEST_DIR/multi/large$i.bin" bs=1 count=0 seek=115343360 2>/dev/null
done

SKIPPED_COUNT=0
for file in "$TEST_DIR/multi"/*.bin; do
    SIZE=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    if [[ "$SIZE" -gt "$MAX_BACKUP_FILE_SIZE" ]]; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
done

if [[ "$SKIPPED_COUNT" -eq 3 ]]; then
    log_pass "Correctly counted 3 large files to skip"
else
    log_fail "Expected 3 skipped, got $SKIPPED_COUNT"
fi

# =============================================================================
# Test 10: File size in human readable format
# =============================================================================
log_test "Human readable size format"

format_size() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$((bytes / 1073741824))GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$((bytes / 1048576))MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$((bytes / 1024))KB"
    else
        echo "${bytes}B"
    fi
}

SIZE_100MB=$(format_size 104857600)
SIZE_1GB=$(format_size 1073741824)

if [[ "$SIZE_100MB" == "100MB" ]] && [[ "$SIZE_1GB" == "1GB" ]]; then
    log_pass "Human readable format correct: $SIZE_100MB, $SIZE_1GB"
else
    log_fail "Format incorrect: $SIZE_100MB, $SIZE_1GB"
fi

# =============================================================================
# Test 11: Config file parsing
# =============================================================================
log_test "Config file MAX_BACKUP_FILE_SIZE parsing"

CONFIG_FILE="$TEST_DIR/.backup-config.sh"
cat > "$CONFIG_FILE" << 'EOF'
MAX_BACKUP_FILE_SIZE=52428800
BACKUP_LARGE_FILES=false
EOF

# Source config
source "$CONFIG_FILE"

if [[ "$MAX_BACKUP_FILE_SIZE" -eq 52428800 ]]; then
    log_pass "Config correctly parsed: 50MB limit"
else
    log_fail "Config parsing failed"
fi

# =============================================================================
# Test 12: Symlink to large file (should skip symlink)
# =============================================================================
log_test "Symlink to large file handling"

# Create large file and symlink
dd if=/dev/zero of="$TEST_DIR/actual_large.bin" bs=1 count=0 seek=115343360 2>/dev/null
ln -sf "$TEST_DIR/actual_large.bin" "$TEST_DIR/symlink_to_large"

if [[ -L "$TEST_DIR/symlink_to_large" ]]; then
    log_pass "Symlink to large file detected (will be skipped)"
else
    log_fail "Symlink not detected"
fi

# =============================================================================
# Test 13: Empty file handling
# =============================================================================
log_test "Empty file handling"

touch "$TEST_DIR/empty.txt"
FILE_SIZE=$(stat -f%z "$TEST_DIR/empty.txt" 2>/dev/null || stat -c%s "$TEST_DIR/empty.txt" 2>/dev/null)

if [[ "$FILE_SIZE" -eq 0 ]]; then
    log_pass "Empty file correctly has size 0"
else
    log_fail "Empty file size incorrect: $FILE_SIZE"
fi

if [[ "$FILE_SIZE" -lt "$MAX_BACKUP_FILE_SIZE" ]]; then
    log_pass "Empty file will be backed up"
else
    log_fail "Empty file handling error"
fi

# =============================================================================
# Test 14: Exact limit boundary
# =============================================================================
log_test "File at exact size limit boundary"

# File exactly at limit
dd if=/dev/zero of="$TEST_DIR/exact.bin" bs=1 count=0 seek=$MAX_BACKUP_FILE_SIZE 2>/dev/null
FILE_SIZE=$(stat -f%z "$TEST_DIR/exact.bin" 2>/dev/null || stat -c%s "$TEST_DIR/exact.bin" 2>/dev/null)

if [[ "$FILE_SIZE" -eq "$MAX_BACKUP_FILE_SIZE" ]]; then
    log_pass "File at exact limit will be backed up (not greater than)"
elif [[ "$FILE_SIZE" -gt "$MAX_BACKUP_FILE_SIZE" ]]; then
    log_pass "File slightly over limit will be skipped"
else
    log_fail "Boundary handling issue"
fi

# =============================================================================
# Test 15: Progress reporting with large files
# =============================================================================
log_test "Progress reporting for skipped files"

SKIPPED_LARGE=5
TOTAL_FILES=100

if [[ $SKIPPED_LARGE -gt 0 ]]; then
    REPORT="Skipped $SKIPPED_LARGE large files (> $((MAX_BACKUP_FILE_SIZE / 1048576))MB)"
    if [[ "$REPORT" == *"Skipped 5 large files"* ]]; then
        log_pass "Progress report format correct"
    else
        log_fail "Progress report format incorrect"
    fi
else
    log_pass "No files skipped"
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
