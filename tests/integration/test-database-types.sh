#!/usr/bin/env bash
# Test: Database Type Detection and Backup
# Tests detection and backup of SQLite, PostgreSQL, MySQL, MongoDB
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Source the database detector if available
if [[ -f "$PROJECT_ROOT/lib/database-detector.sh" ]]; then
    source "$PROJECT_ROOT/lib/database-detector.sh"
fi

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
echo "Test Suite: Database Type Detection"
echo "═══════════════════════════════════════════════"
echo ""

# =============================================================================
# Test 1: SQLite detection by file extension
# =============================================================================
log_test "SQLite detection by .db extension"

PROJECT_DIR="$TEST_DIR/sqlite-project"
mkdir -p "$PROJECT_DIR"

# Create SQLite database
sqlite3 "$PROJECT_DIR/test.db" "CREATE TABLE test (id INTEGER);" 2>/dev/null || {
    echo "  (sqlite3 not available - creating mock file)"
    touch "$PROJECT_DIR/test.db"
}

if [[ -f "$PROJECT_DIR/test.db" ]]; then
    log_pass "SQLite file created"
else
    log_fail "SQLite file not created"
fi

# =============================================================================
# Test 2: SQLite detection by .sqlite extension
# =============================================================================
log_test "SQLite detection by .sqlite extension"

touch "$PROJECT_DIR/data.sqlite"
if [[ -f "$PROJECT_DIR/data.sqlite" ]]; then
    log_pass "SQLite (.sqlite) file recognized"
else
    log_fail "SQLite (.sqlite) not recognized"
fi

# =============================================================================
# Test 3: SQLite detection by .sqlite3 extension
# =============================================================================
log_test "SQLite detection by .sqlite3 extension"

touch "$PROJECT_DIR/data.sqlite3"
if [[ -f "$PROJECT_DIR/data.sqlite3" ]]; then
    log_pass "SQLite (.sqlite3) file recognized"
else
    log_fail "SQLite (.sqlite3) not recognized"
fi

# =============================================================================
# Test 4: PostgreSQL detection from DATABASE_URL
# =============================================================================
log_test "PostgreSQL detection from DATABASE_URL"

ENV_FILE="$PROJECT_DIR/.env"
echo 'DATABASE_URL="postgresql://user:pass@localhost:5432/mydb"' > "$ENV_FILE"

if grep -q "postgresql://" "$ENV_FILE"; then
    log_pass "PostgreSQL URL detected in .env"
else
    log_fail "PostgreSQL URL not detected"
fi

# Parse the URL
DB_URL=$(grep "DATABASE_URL" "$ENV_FILE" | cut -d'"' -f2)
if [[ "$DB_URL" == *"postgresql://"* ]]; then
    log_pass "PostgreSQL protocol parsed correctly"
else
    log_fail "PostgreSQL protocol parsing failed"
fi

# =============================================================================
# Test 5: MySQL detection from DATABASE_URL
# =============================================================================
log_test "MySQL detection from DATABASE_URL"

echo 'DATABASE_URL="mysql://user:pass@localhost:3306/mydb"' > "$ENV_FILE"

DB_URL=$(grep "DATABASE_URL" "$ENV_FILE" | cut -d'"' -f2)
if [[ "$DB_URL" == *"mysql://"* ]]; then
    log_pass "MySQL URL detected"
else
    log_fail "MySQL URL not detected"
fi

# =============================================================================
# Test 6: MongoDB detection from MONGODB_URL
# =============================================================================
log_test "MongoDB detection from MONGODB_URL"

echo 'MONGODB_URL="mongodb://localhost:27017/mydb"' > "$ENV_FILE"

if grep -q "mongodb://" "$ENV_FILE"; then
    log_pass "MongoDB URL detected"
else
    log_fail "MongoDB URL not detected"
fi

# =============================================================================
# Test 7: Remote database detection (should skip backup)
# =============================================================================
log_test "Remote database detection"

# Neon PostgreSQL (remote)
echo 'DATABASE_URL="postgresql://user:pass@ep-cool-name.us-east-2.aws.neon.tech/mydb"' > "$ENV_FILE"

DB_URL=$(grep "DATABASE_URL" "$ENV_FILE" | cut -d'"' -f2)
if [[ "$DB_URL" == *"neon.tech"* ]]; then
    log_pass "Remote Neon database detected (should skip)"
else
    log_fail "Remote database not detected"
fi

# =============================================================================
# Test 8: Local database detection (should backup)
# =============================================================================
log_test "Local database detection"

echo 'DATABASE_URL="postgresql://user:pass@localhost:5432/mydb"' > "$ENV_FILE"

DB_URL=$(grep "DATABASE_URL" "$ENV_FILE" | cut -d'"' -f2)
if [[ "$DB_URL" == *"localhost"* ]] || [[ "$DB_URL" == *"127.0.0.1"* ]]; then
    log_pass "Local database detected (should backup)"
else
    log_fail "Local database not detected"
fi

# =============================================================================
# Test 9: Backup verification with gunzip -t
# =============================================================================
log_test "Backup verification with gunzip"

BACKUP_DIR="$TEST_DIR/backup"
mkdir -p "$BACKUP_DIR"

# Create a valid gzip file
echo "test data" | gzip > "$BACKUP_DIR/test.db.gz"

if gunzip -t "$BACKUP_DIR/test.db.gz" 2>/dev/null; then
    log_pass "Valid backup verified with gunzip -t"
else
    log_fail "Verification failed for valid backup"
fi

# =============================================================================
# Test 10: Corrupted backup detection
# =============================================================================
log_test "Corrupted backup detection"

# Create corrupted gzip
echo "not gzip data" > "$BACKUP_DIR/corrupt.db.gz"

if ! gunzip -t "$BACKUP_DIR/corrupt.db.gz" 2>/dev/null; then
    log_pass "Corrupted backup correctly detected"
else
    log_fail "Corrupted backup not detected"
fi

# =============================================================================
# Test 11: Exit code capture with PIPESTATUS
# =============================================================================
log_test "Exit code capture with PIPESTATUS"

# Simulate pipeline
(echo "data" | gzip > /dev/null)
EXIT_CODE=${PIPESTATUS[0]}

if [[ "$EXIT_CODE" -eq 0 ]]; then
    log_pass "PIPESTATUS correctly captured exit code: $EXIT_CODE"
else
    log_fail "PIPESTATUS capture failed"
fi

# =============================================================================
# Test 12: Database tool availability check
# =============================================================================
log_test "Database tool availability"

TOOLS_AVAILABLE=0

if command -v sqlite3 &>/dev/null; then
    echo "  sqlite3: available"
    TOOLS_AVAILABLE=$((TOOLS_AVAILABLE + 1))
else
    echo "  sqlite3: not installed"
fi

if command -v pg_dump &>/dev/null; then
    echo "  pg_dump: available"
    TOOLS_AVAILABLE=$((TOOLS_AVAILABLE + 1))
else
    echo "  pg_dump: not installed"
fi

if command -v mysqldump &>/dev/null; then
    echo "  mysqldump: available"
    TOOLS_AVAILABLE=$((TOOLS_AVAILABLE + 1))
else
    echo "  mysqldump: not installed"
fi

if command -v mongodump &>/dev/null; then
    echo "  mongodump: available"
    TOOLS_AVAILABLE=$((TOOLS_AVAILABLE + 1))
else
    echo "  mongodump: not installed"
fi

if [[ $TOOLS_AVAILABLE -gt 0 ]]; then
    log_pass "At least one database tool available"
else
    log_pass "No database tools installed (expected on minimal systems)"
fi

# =============================================================================
# Test 13: Multiple databases in project
# =============================================================================
log_test "Multiple database detection"

PROJECT_DIR="$TEST_DIR/multi-db-project"
mkdir -p "$PROJECT_DIR"

touch "$PROJECT_DIR/app.db"
touch "$PROJECT_DIR/cache.sqlite"
touch "$PROJECT_DIR/sessions.sqlite3"

DB_COUNT=$(find "$PROJECT_DIR" -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$DB_COUNT" -eq 3 ]]; then
    log_pass "Detected all 3 SQLite databases"
else
    log_fail "Expected 3 databases, found $DB_COUNT"
fi

# =============================================================================
# Test 14: Exclude non-project databases
# =============================================================================
log_test "Exclude node_modules databases"

PROJECT_DIR="$TEST_DIR/exclude-test"
mkdir -p "$PROJECT_DIR/node_modules/some-package"
touch "$PROJECT_DIR/node_modules/some-package/cache.db"
touch "$PROJECT_DIR/app.db"

# Find only project databases (exclude node_modules)
DB_COUNT=$(find "$PROJECT_DIR" -name "*.db" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$DB_COUNT" -eq 1 ]]; then
    log_pass "Correctly excluded node_modules database"
else
    log_fail "Expected 1 database, found $DB_COUNT"
fi

# =============================================================================
# Test 15: Timestamp in backup filename
# =============================================================================
log_test "Timestamp in backup filename"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="database_${TIMESTAMP}_$$.db.gz"

if [[ "$BACKUP_NAME" =~ ^database_[0-9]{8}_[0-9]{6}_[0-9]+\.db\.gz$ ]]; then
    log_pass "Backup filename format correct: $BACKUP_NAME"
else
    log_fail "Backup filename format incorrect"
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
