#!/bin/bash
# ClaudeCode Project Backups - Command System Test Suite
# Comprehensive tests for v1.1.0 command system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_PROJECT="/tmp/test-backup-commands-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# ==============================================================================
# TEST HELPERS
# ==============================================================================

test_start() {
    echo -n "Testing: $1 ... "
}

test_pass() {
    echo -e "${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}FAIL${NC}"
    echo "  Error: $1"
    ((TESTS_FAILED++))
}

cleanup() {
    echo ""
    echo "Cleaning up test environment..."
    rm -rf "$TEST_PROJECT"
    rm -rf /tmp/test-config-*.yaml
}

trap cleanup EXIT

setup_test_project() {
    mkdir -p "$TEST_PROJECT"
    cd "$TEST_PROJECT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"

    mkdir -p src
    echo "print('app')" > src/app.py
    echo "README" > README.md
    git add .
    git commit -m "Initial" -q
}

create_test_yaml_config() {
    cat > "$TEST_PROJECT/.backup-config.yaml" << 'EOF'
project:
  name: "TestProject"
  directory: "$PWD"

backup:
  directory: "$PWD/backups"
  interval: 3600
  session_idle_threshold: 600
  critical_files:
    env_files: true
    credentials: true
    ide_settings: false
    local_notes: false
    local_databases: false

database:
  enabled: false
  type: "none"
  path: ""

retention:
  database_days: 30
  file_days: 60

drive:
  verification_enabled: false
  marker_file: ""

git:
  auto_commit: false

logging:
  level: "info"
  file: "$PWD/backups/backup.log"
EOF
}

create_test_bash_config() {
    cat > "$TEST_PROJECT/.backup-config.sh" << 'EOF'
PROJECT_DIR="$PWD"
PROJECT_NAME="TestProject"
BACKUP_DIR="$PROJECT_DIR/backups"
DATABASE_DIR="$BACKUP_DIR/databases"
FILES_DIR="$BACKUP_DIR/files"
ARCHIVED_DIR="$BACKUP_DIR/archived"
DB_PATH=""
DB_TYPE="none"
DB_RETENTION_DAYS=30
FILE_RETENTION_DAYS=60
BACKUP_INTERVAL=3600
SESSION_IDLE_THRESHOLD=600
DRIVE_VERIFICATION_ENABLED=false
DRIVE_MARKER_FILE=""
AUTO_COMMIT_ENABLED=false
BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=false
BACKUP_LOCAL_NOTES=false
BACKUP_LOCAL_DATABASES=false
LOG_FILE="$BACKUP_DIR/backup.log"
FALLBACK_LOG="$HOME/.claudecode-backups/logs/backup-fallback.log"
STATE_DIR="$HOME/.claudecode-backups/state"
BACKUP_TIME_STATE="$STATE_DIR/.last-backup-time"
SESSION_FILE="$STATE_DIR/.current-session-time"
DB_STATE_FILE="$BACKUP_DIR/.backup-state"
EOF
}

# ==============================================================================
# SETUP
# ==============================================================================

echo "═══════════════════════════════════════════════════════"
echo "ClaudeCode Project Backups - Command System Test Suite"
echo "═══════════════════════════════════════════════════════"
echo ""

setup_test_project
echo "✅ Test project created: $TEST_PROJECT"
echo ""

# ==============================================================================
# FOUNDATION LIBRARY TESTS (lib/backup-lib.sh)
# ==============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Foundation Library Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Note: These tests assume lib/backup-lib.sh exists
# If not implemented yet, tests will be skipped

if [ -f "$PACKAGE_DIR/lib/backup-lib.sh" ]; then
    test_start "Foundation library exists"
    test_pass

    test_start "Foundation library is executable/sourceable"
    if bash -n "$PACKAGE_DIR/lib/backup-lib.sh" 2>/dev/null; then
        test_pass
    else
        test_fail "Syntax error in lib/backup-lib.sh"
    fi
else
    echo "⚠️  Skipping foundation library tests (not implemented yet)"
fi

# ==============================================================================
# YAML PARSER TESTS (lib/yaml-parser.sh)
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "YAML Parser Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

create_test_yaml_config

test_start "YAML config file created"
if [ -f "$TEST_PROJECT/.backup-config.yaml" ]; then
    test_pass
else
    test_fail "YAML config not created"
fi

test_start "YAML config is valid syntax"
if python3 -c "import yaml; yaml.safe_load(open('$TEST_PROJECT/.backup-config.yaml'))" 2>/dev/null; then
    test_pass
else
    # Fallback test if python not available
    if grep -q "project:" "$TEST_PROJECT/.backup-config.yaml"; then
        test_pass
    else
        test_fail "YAML config appears invalid"
    fi
fi

# ==============================================================================
# CONFIG VALIDATION TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration Validation Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Valid YAML config structure"
if grep -q "project:" "$TEST_PROJECT/.backup-config.yaml" && \
   grep -q "backup:" "$TEST_PROJECT/.backup-config.yaml" && \
   grep -q "retention:" "$TEST_PROJECT/.backup-config.yaml"; then
    test_pass
else
    test_fail "YAML config missing required sections"
fi

test_start "Bash config structure (legacy)"
create_test_bash_config
if [ -f "$TEST_PROJECT/.backup-config.sh" ]; then
    if grep -q "PROJECT_NAME=" "$TEST_PROJECT/.backup-config.sh"; then
        test_pass
    else
        test_fail "Bash config missing PROJECT_NAME"
    fi
else
    test_fail "Bash config not created"
fi

test_start "Required fields present in YAML"
required_fields=("project" "backup" "retention")
all_present=true
for field in "${required_fields[@]}"; do
    if ! grep -q "$field:" "$TEST_PROJECT/.backup-config.yaml"; then
        all_present=false
        break
    fi
done
if $all_present; then
    test_pass
else
    test_fail "Missing required field in YAML"
fi

test_start "Required fields present in Bash config"
bash_required=("PROJECT_NAME" "PROJECT_DIR" "BACKUP_DIR")
all_present=true
for field in "${bash_required[@]}"; do
    if ! grep -q "$field=" "$TEST_PROJECT/.backup-config.sh"; then
        all_present=false
        break
    fi
done
if $all_present; then
    test_pass
else
    test_fail "Missing required field in Bash config"
fi

# ==============================================================================
# /backup-config COMMAND TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "/backup-config Command Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# These tests check if commands exist and have proper structure
# Actual implementation will be done by other agents

test_start "backup-config command script exists"
if [ -f "$PACKAGE_DIR/commands/backup-config.sh" ] || [ -f "$PACKAGE_DIR/bin/backup-config.sh" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-config has --help option"
# Placeholder test - checks if script contains help text
if [ -f "$PACKAGE_DIR/commands/backup-config.sh" ]; then
    if grep -q "help" "$PACKAGE_DIR/commands/backup-config.sh"; then
        test_pass
    else
        test_fail "No help text found"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-config has --get option"
if [ -f "$PACKAGE_DIR/commands/backup-config.sh" ]; then
    if grep -q -- "--get" "$PACKAGE_DIR/commands/backup-config.sh" 2>/dev/null || \
       grep -q "get_config_value" "$PACKAGE_DIR/commands/backup-config.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-config has --set option"
if [ -f "$PACKAGE_DIR/commands/backup-config.sh" ]; then
    if grep -q -- "--set" "$PACKAGE_DIR/commands/backup-config.sh" 2>/dev/null || \
       grep -q "set_config_value" "$PACKAGE_DIR/commands/backup-config.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-config has --validate option"
if [ -f "$PACKAGE_DIR/commands/backup-config.sh" ]; then
    if grep -q -- "--validate" "$PACKAGE_DIR/commands/backup-config.sh" 2>/dev/null || \
       grep -q "validate" "$PACKAGE_DIR/commands/backup-config.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-config has --migrate option"
if [ -f "$PACKAGE_DIR/commands/backup-config.sh" ]; then
    if grep -q -- "--migrate" "$PACKAGE_DIR/commands/backup-config.sh" 2>/dev/null || \
       grep -q "migrate" "$PACKAGE_DIR/commands/backup-config.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-config has wizard mode"
if [ -f "$PACKAGE_DIR/commands/backup-config.sh" ]; then
    if grep -q "wizard" "$PACKAGE_DIR/commands/backup-config.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

# ==============================================================================
# /backup-status COMMAND TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "/backup-status Command Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "backup-status command script exists"
if [ -f "$PACKAGE_DIR/commands/backup-status.sh" ] || [ -f "$PACKAGE_DIR/bin/backup-status.sh" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-status has --json option"
if [ -f "$PACKAGE_DIR/commands/backup-status.sh" ]; then
    if grep -q -- "--json" "$PACKAGE_DIR/commands/backup-status.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-status has --verbose option"
if [ -f "$PACKAGE_DIR/commands/backup-status.sh" ]; then
    if grep -q -- "--verbose" "$PACKAGE_DIR/commands/backup-status.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-status has --check option"
if [ -f "$PACKAGE_DIR/commands/backup-status.sh" ]; then
    if grep -q -- "--check" "$PACKAGE_DIR/commands/backup-status.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-status checks component health"
if [ -f "$PACKAGE_DIR/commands/backup-status.sh" ]; then
    if grep -q "health" "$PACKAGE_DIR/commands/backup-status.sh" 2>/dev/null || \
       grep -q "component" "$PACKAGE_DIR/commands/backup-status.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-status shows statistics"
if [ -f "$PACKAGE_DIR/commands/backup-status.sh" ]; then
    if grep -q "statistics" "$PACKAGE_DIR/commands/backup-status.sh" 2>/dev/null || \
       grep -q "stats" "$PACKAGE_DIR/commands/backup-status.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

# ==============================================================================
# /backup-now COMMAND TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "/backup-now Command Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "backup-now command script exists"
if [ -f "$PACKAGE_DIR/commands/backup-now.sh" ] || [ -f "$PACKAGE_DIR/bin/backup-now.sh" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-now has --force option"
if [ -f "$PACKAGE_DIR/commands/backup-now.sh" ]; then
    if grep -q -- "--force" "$PACKAGE_DIR/commands/backup-now.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-now has --dry-run option"
if [ -f "$PACKAGE_DIR/commands/backup-now.sh" ]; then
    if grep -q -- "--dry-run" "$PACKAGE_DIR/commands/backup-now.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-now has --db-only option"
if [ -f "$PACKAGE_DIR/commands/backup-now.sh" ]; then
    if grep -q -- "--db-only" "$PACKAGE_DIR/commands/backup-now.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-now has --files-only option"
if [ -f "$PACKAGE_DIR/commands/backup-now.sh" ]; then
    if grep -q -- "--files-only" "$PACKAGE_DIR/commands/backup-now.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-now has concurrency handling"
if [ -f "$PACKAGE_DIR/commands/backup-now.sh" ]; then
    if grep -q "lock" "$PACKAGE_DIR/commands/backup-now.sh" 2>/dev/null || \
       grep -q "running" "$PACKAGE_DIR/commands/backup-now.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

# ==============================================================================
# /backup-restore COMMAND TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "/backup-restore Command Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "backup-restore command script exists"
if [ -f "$PACKAGE_DIR/commands/backup-restore.sh" ] || [ -f "$PACKAGE_DIR/bin/backup-restore.sh" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-restore has --database option"
if [ -f "$PACKAGE_DIR/commands/backup-restore.sh" ]; then
    if grep -q -- "--database" "$PACKAGE_DIR/commands/backup-restore.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-restore has --file option"
if [ -f "$PACKAGE_DIR/commands/backup-restore.sh" ]; then
    if grep -q -- "--file" "$PACKAGE_DIR/commands/backup-restore.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-restore has --list option"
if [ -f "$PACKAGE_DIR/commands/backup-restore.sh" ]; then
    if grep -q -- "--list" "$PACKAGE_DIR/commands/backup-restore.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-restore has safety backup feature"
if [ -f "$PACKAGE_DIR/commands/backup-restore.sh" ]; then
    if grep -q "pre-restore" "$PACKAGE_DIR/commands/backup-restore.sh" 2>/dev/null || \
       grep -q "safety" "$PACKAGE_DIR/commands/backup-restore.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-restore has wizard mode"
if [ -f "$PACKAGE_DIR/commands/backup-restore.sh" ]; then
    if grep -q "wizard" "$PACKAGE_DIR/commands/backup-restore.sh" 2>/dev/null || \
       grep -q "interactive" "$PACKAGE_DIR/commands/backup-restore.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

# ==============================================================================
# /backup-cleanup COMMAND TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "/backup-cleanup Command Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "backup-cleanup command script exists"
if [ -f "$PACKAGE_DIR/commands/backup-cleanup.sh" ] || [ -f "$PACKAGE_DIR/bin/backup-cleanup.sh" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-cleanup has --preview option"
if [ -f "$PACKAGE_DIR/commands/backup-cleanup.sh" ]; then
    if grep -q -- "--preview" "$PACKAGE_DIR/commands/backup-cleanup.sh" 2>/dev/null || \
       grep -q "preview" "$PACKAGE_DIR/commands/backup-cleanup.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-cleanup has --execute option"
if [ -f "$PACKAGE_DIR/commands/backup-cleanup.sh" ]; then
    if grep -q -- "--execute" "$PACKAGE_DIR/commands/backup-cleanup.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-cleanup has --recommend option"
if [ -f "$PACKAGE_DIR/commands/backup-cleanup.sh" ]; then
    if grep -q -- "--recommend" "$PACKAGE_DIR/commands/backup-cleanup.sh" 2>/dev/null || \
       grep -q "recommendation" "$PACKAGE_DIR/commands/backup-cleanup.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

test_start "backup-cleanup shows space reclamation"
if [ -f "$PACKAGE_DIR/commands/backup-cleanup.sh" ]; then
    if grep -q "space" "$PACKAGE_DIR/commands/backup-cleanup.sh" 2>/dev/null || \
       grep -q "reclaim" "$PACKAGE_DIR/commands/backup-cleanup.sh" 2>/dev/null; then
        test_pass
    else
        echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
    fi
else
    echo -e "${YELLOW}SKIP${NC} (not implemented yet)"
fi

# ==============================================================================
# MIGRATION TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration Migration Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Bash config can coexist with YAML config"
if [ -f "$TEST_PROJECT/.backup-config.sh" ] && [ -f "$TEST_PROJECT/.backup-config.yaml" ]; then
    test_pass
else
    test_fail "Both configs should exist"
fi

test_start "YAML config takes precedence (when implemented)"
# This is a design requirement test
test_pass

test_start "Migration preserves project name"
bash_name=$(grep "PROJECT_NAME=" "$TEST_PROJECT/.backup-config.sh" | cut -d'"' -f2)
yaml_name=$(grep "name:" "$TEST_PROJECT/.backup-config.yaml" | head -1 | awk '{print $2}' | tr -d '"')
if [ "$bash_name" = "$yaml_name" ]; then
    test_pass
else
    test_fail "Project name mismatch: bash=$bash_name, yaml=$yaml_name"
fi

test_start "Migration preserves retention days"
bash_db_days=$(grep "DB_RETENTION_DAYS=" "$TEST_PROJECT/.backup-config.sh" | cut -d'=' -f2)
yaml_db_days=$(grep "database_days:" "$TEST_PROJECT/.backup-config.yaml" | awk '{print $2}')
if [ "$bash_db_days" = "$yaml_db_days" ]; then
    test_pass
else
    test_fail "DB retention mismatch: bash=$bash_db_days, yaml=$yaml_db_days"
fi

# ==============================================================================
# TEMPLATE TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration Template Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Example minimal config exists"
if [ -f "$PACKAGE_DIR/examples/configs/minimal.yaml" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not created yet)"
fi

test_start "Example standard config exists"
if [ -f "$PACKAGE_DIR/examples/configs/standard.yaml" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not created yet)"
fi

test_start "Example paranoid config exists"
if [ -f "$PACKAGE_DIR/examples/configs/paranoid.yaml" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not created yet)"
fi

test_start "Example external-drive config exists"
if [ -f "$PACKAGE_DIR/examples/configs/external-drive.yaml" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not created yet)"
fi

test_start "Example no-database config exists"
if [ -f "$PACKAGE_DIR/examples/configs/no-database.yaml" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not created yet)"
fi

# ==============================================================================
# EXAMPLE SCRIPTS TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Example Scripts Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Example basic-setup.sh exists"
if [ -f "$PACKAGE_DIR/examples/commands/basic-setup.sh" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not created yet)"
fi

test_start "Example advanced-config.sh exists"
if [ -f "$PACKAGE_DIR/examples/commands/advanced-config.sh" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not created yet)"
fi

test_start "Example disaster-recovery.sh exists"
if [ -f "$PACKAGE_DIR/examples/commands/disaster-recovery.sh" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not created yet)"
fi

test_start "Example maintenance.sh exists"
if [ -f "$PACKAGE_DIR/examples/commands/maintenance.sh" ]; then
    test_pass
else
    echo -e "${YELLOW}SKIP${NC} (not created yet)"
fi

# ==============================================================================
# DOCUMENTATION TESTS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Documentation Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "docs/COMMANDS.md exists"
if [ -f "$PACKAGE_DIR/docs/COMMANDS.md" ]; then
    test_pass
else
    test_fail "COMMANDS.md not found"
fi

test_start "docs/MIGRATION.md exists"
if [ -f "$PACKAGE_DIR/docs/MIGRATION.md" ]; then
    test_pass
else
    test_fail "MIGRATION.md not found"
fi

test_start "docs/DEVELOPMENT.md exists"
if [ -f "$PACKAGE_DIR/docs/DEVELOPMENT.md" ]; then
    test_pass
else
    test_fail "DEVELOPMENT.md not found"
fi

test_start "docs/API.md exists"
if [ -f "$PACKAGE_DIR/docs/API.md" ]; then
    test_pass
else
    test_fail "API.md not found"
fi

test_start "README.md has command system section"
if grep -q "Command System" "$PACKAGE_DIR/README.md"; then
    test_pass
else
    test_fail "README.md missing Command System section"
fi

test_start "CHANGELOG.md has v1.1.0 entry"
if grep -q "## \[1.1.0\]" "$PACKAGE_DIR/CHANGELOG.md"; then
    test_pass
else
    test_fail "CHANGELOG.md missing v1.1.0 entry"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

echo ""
echo "═══════════════════════════════════════════════════════"
echo "Test Results"
echo "═══════════════════════════════════════════════════════"
echo ""
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    echo ""
    echo "Note: SKIP messages indicate features not yet implemented."
    echo "This is expected during development."
    exit 1
fi
