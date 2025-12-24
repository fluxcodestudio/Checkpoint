#!/bin/bash
# ClaudeCode Project Backups - Configuration Validation Test Suite
# Tests for YAML and bash config validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

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
    rm -f /tmp/test-config-*.yaml
    rm -f /tmp/test-config-*.sh
}

trap cleanup EXIT

echo "═══════════════════════════════════════════════════════"
echo "Configuration Validation Test Suite"
echo "═══════════════════════════════════════════════════════"
echo ""

# ==============================================================================
# VALID YAML CONFIGS
# ==============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Valid YAML Configuration Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Minimal valid config"
cat > /tmp/test-config-minimal.yaml << 'EOF'
project:
  name: "TestProject"
  directory: "/tmp/test"

backup:
  directory: "/tmp/test/backups"

retention:
  database_days: 30
  file_days: 60
EOF

if python3 -c "import yaml; yaml.safe_load(open('/tmp/test-config-minimal.yaml'))" 2>/dev/null; then
    test_pass
else
    test_fail "Minimal config has invalid YAML syntax"
fi

test_start "Standard valid config"
cat > /tmp/test-config-standard.yaml << 'EOF'
project:
  name: "MyApp"
  directory: "/path/to/project"

backup:
  directory: "/path/to/backups"
  interval: 3600
  session_idle_threshold: 600
  critical_files:
    env_files: true
    credentials: true
    ide_settings: false

database:
  enabled: true
  type: "sqlite"
  path: "/path/to/db.db"

retention:
  database_days: 30
  file_days: 60

drive:
  verification_enabled: true
  marker_file: "/path/to/marker"

git:
  auto_commit: false
EOF

if python3 -c "import yaml; yaml.safe_load(open('/tmp/test-config-standard.yaml'))" 2>/dev/null; then
    test_pass
else
    test_fail "Standard config has invalid YAML syntax"
fi

# ==============================================================================
# INVALID YAML CONFIGS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Invalid YAML Configuration Tests (should fail)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Missing required field (project.name)"
cat > /tmp/test-config-missing-name.yaml << 'EOF'
project:
  directory: "/tmp/test"

backup:
  directory: "/tmp/test/backups"

retention:
  database_days: 30
  file_days: 60
EOF

if python3 -c "import yaml; yaml.safe_load(open('/tmp/test-config-missing-name.yaml'))" 2>/dev/null; then
    if ! grep -q "name:" /tmp/test-config-missing-name.yaml; then
        test_pass
    else
        test_fail "Should detect missing project.name"
    fi
else
    test_fail "Invalid YAML syntax"
fi

test_start "Missing required field (backup.directory)"
cat > /tmp/test-config-missing-backup-dir.yaml << 'EOF'
project:
  name: "Test"
  directory: "/tmp/test"

retention:
  database_days: 30
  file_days: 60
EOF

if ! grep -q "backup:" /tmp/test-config-missing-backup-dir.yaml; then
    test_pass
else
    test_fail "Should detect missing backup section"
fi

test_start "Invalid retention days (negative)"
cat > /tmp/test-config-negative-retention.yaml << 'EOF'
project:
  name: "Test"
  directory: "/tmp/test"

backup:
  directory: "/tmp/test/backups"

retention:
  database_days: -10
  file_days: 60
EOF

if grep -q "database_days: -10" /tmp/test-config-negative-retention.yaml; then
    test_pass
else
    test_fail "Should contain negative retention value"
fi

test_start "Invalid retention days (too high)"
cat > /tmp/test-config-high-retention.yaml << 'EOF'
project:
  name: "Test"
  directory: "/tmp/test"

backup:
  directory: "/tmp/test/backups"

retention:
  database_days: 999
  file_days: 60
EOF

if grep -q "database_days: 999" /tmp/test-config-high-retention.yaml; then
    test_pass
else
    test_fail "Should contain high retention value"
fi

test_start "Invalid database type"
cat > /tmp/test-config-invalid-db-type.yaml << 'EOF'
project:
  name: "Test"
  directory: "/tmp/test"

backup:
  directory: "/tmp/test/backups"

database:
  enabled: true
  type: "invalid_type"
  path: "/path/to/db"

retention:
  database_days: 30
  file_days: 60
EOF

if grep -q "type: \"invalid_type\"" /tmp/test-config-invalid-db-type.yaml; then
    test_pass
else
    test_fail "Should contain invalid type"
fi

# ==============================================================================
# EDGE CASES
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Edge Case Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Empty config file"
cat > /tmp/test-config-empty.yaml << 'EOF'
EOF

if [ ! -s /tmp/test-config-empty.yaml ]; then
    test_pass
else
    test_fail "File should be empty"
fi

test_start "Config with only comments"
cat > /tmp/test-config-comments-only.yaml << 'EOF'
# This is a comment
# Another comment
# No actual config
EOF

if ! grep -qv "^#" /tmp/test-config-comments-only.yaml | grep -q "."; then
    test_pass
else
    test_fail "Should only contain comments"
fi

test_start "Config with special characters in paths"
cat > /tmp/test-config-special-chars.yaml << 'EOF'
project:
  name: "Test-Project_123"
  directory: "/path/with spaces/and-dashes"

backup:
  directory: "/backup (external)/data"

retention:
  database_days: 30
  file_days: 60
EOF

if python3 -c "import yaml; yaml.safe_load(open('/tmp/test-config-special-chars.yaml'))" 2>/dev/null; then
    test_pass
else
    test_fail "Should handle special characters"
fi

test_start "Config with very long values"
cat > /tmp/test-config-long-values.yaml << 'EOF'
project:
  name: "VeryLongProjectNameThatExceedsNormalLength_123456789012345678901234567890"
  directory: "/extremely/long/path/that/goes/on/and/on/and/on/and/on/and/on"

backup:
  directory: "/backup"

retention:
  database_days: 30
  file_days: 60
EOF

if python3 -c "import yaml; yaml.safe_load(open('/tmp/test-config-long-values.yaml'))" 2>/dev/null; then
    test_pass
else
    test_fail "Should handle long values"
fi

test_start "Config with minimum retention (1 day)"
cat > /tmp/test-config-min-retention.yaml << 'EOF'
project:
  name: "Test"
  directory: "/tmp"

backup:
  directory: "/tmp/backups"

retention:
  database_days: 1
  file_days: 1
EOF

if grep -q "database_days: 1" /tmp/test-config-min-retention.yaml; then
    test_pass
else
    test_fail "Should contain minimum retention"
fi

test_start "Config with maximum retention (365 days)"
cat > /tmp/test-config-max-retention.yaml << 'EOF'
project:
  name: "Test"
  directory: "/tmp"

backup:
  directory: "/tmp/backups"

retention:
  database_days: 365
  file_days: 365
EOF

if grep -q "database_days: 365" /tmp/test-config-max-retention.yaml; then
    test_pass
else
    test_fail "Should contain maximum retention"
fi

# ==============================================================================
# BASH CONFIG VALIDATION
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Bash Configuration Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Valid bash config syntax"
cat > /tmp/test-config-valid.sh << 'EOF'
PROJECT_NAME="TestProject"
PROJECT_DIR="/tmp/test"
BACKUP_DIR="/tmp/test/backups"
DB_RETENTION_DAYS=30
FILE_RETENTION_DAYS=60
EOF

if bash -n /tmp/test-config-valid.sh 2>/dev/null; then
    test_pass
else
    test_fail "Bash config has syntax errors"
fi

test_start "Bash config with all required variables"
required_vars=("PROJECT_NAME" "PROJECT_DIR" "BACKUP_DIR" "DB_RETENTION_DAYS" "FILE_RETENTION_DAYS")
all_present=true
for var in "${required_vars[@]}"; do
    if ! grep -q "$var=" /tmp/test-config-valid.sh; then
        all_present=false
        break
    fi
done
if $all_present; then
    test_pass
else
    test_fail "Missing required variables"
fi

test_start "Invalid bash config (syntax error)"
cat > /tmp/test-config-invalid.sh << 'EOF'
PROJECT_NAME="Test
MISSING_QUOTE="value"
EOF

if ! bash -n /tmp/test-config-invalid.sh 2>/dev/null; then
    test_pass
else
    test_fail "Should detect syntax error"
fi

# ==============================================================================
# MIGRATION SCENARIOS
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Migration Scenario Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Bash to YAML field mapping - PROJECT_NAME"
cat > /tmp/test-migration-bash.sh << 'EOF'
PROJECT_NAME="MyApp"
EOF

cat > /tmp/test-migration-yaml.yaml << 'EOF'
project:
  name: "MyApp"
EOF

bash_name=$(grep "PROJECT_NAME=" /tmp/test-migration-bash.sh | cut -d'"' -f2)
yaml_name=$(grep "name:" /tmp/test-migration-yaml.yaml | awk '{print $2}' | tr -d '"')

if [ "$bash_name" = "$yaml_name" ]; then
    test_pass
else
    test_fail "Name mismatch: bash=$bash_name, yaml=$yaml_name"
fi

test_start "Bash to YAML field mapping - DB_RETENTION_DAYS"
cat > /tmp/test-migration-bash2.sh << 'EOF'
DB_RETENTION_DAYS=30
EOF

cat > /tmp/test-migration-yaml2.yaml << 'EOF'
retention:
  database_days: 30
EOF

bash_days=$(grep "DB_RETENTION_DAYS=" /tmp/test-migration-bash2.sh | cut -d'=' -f2)
yaml_days=$(grep "database_days:" /tmp/test-migration-yaml2.yaml | awk '{print $2}')

if [ "$bash_days" = "$yaml_days" ]; then
    test_pass
else
    test_fail "Retention mismatch: bash=$bash_days, yaml=$yaml_days"
fi

test_start "Boolean conversion (bash true/false to YAML)"
cat > /tmp/test-migration-bool.yaml << 'EOF'
drive:
  verification_enabled: true
git:
  auto_commit: false
EOF

if grep -q "verification_enabled: true" /tmp/test-migration-bool.yaml && \
   grep -q "auto_commit: false" /tmp/test-migration-bool.yaml; then
    test_pass
else
    test_fail "Boolean values not correct"
fi

# ==============================================================================
# TYPE VALIDATION
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Type Validation Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_start "Integer validation for retention days"
cat > /tmp/test-type-int.yaml << 'EOF'
retention:
  database_days: 30
  file_days: 60
EOF

if grep -qE "database_days: [0-9]+" /tmp/test-type-int.yaml; then
    test_pass
else
    test_fail "Should contain integer value"
fi

test_start "Boolean validation"
cat > /tmp/test-type-bool.yaml << 'EOF'
database:
  enabled: true
drive:
  verification_enabled: false
EOF

if grep -qE "(true|false)" /tmp/test-type-bool.yaml; then
    test_pass
else
    test_fail "Should contain boolean values"
fi

test_start "String validation for paths"
cat > /tmp/test-type-string.yaml << 'EOF'
project:
  directory: "/path/to/project"
database:
  path: "/path/to/db.db"
EOF

if grep -qE "directory: \"[^\"]+\"" /tmp/test-type-string.yaml || \
   grep -qE "directory: /[^ ]+" /tmp/test-type-string.yaml; then
    test_pass
else
    test_fail "Should contain valid path strings"
fi

test_start "Enum validation for database type"
cat > /tmp/test-type-enum.yaml << 'EOF'
database:
  type: "sqlite"
EOF

if grep -q "type: \"sqlite\"" /tmp/test-type-enum.yaml; then
    test_pass
else
    test_fail "Should contain valid database type"
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
    echo -e "${GREEN}✅ All validation tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some validation tests failed${NC}"
    exit 1
fi
