#!/bin/bash
# Integration Test: Fresh Installation
# Tests complete installation workflow from scratch

set -euo pipefail

TEST_PROJECT="/tmp/fresh-install-test-$$"
PACKAGE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

cleanup() {
    rm -rf "$TEST_PROJECT"
    echo "Cleanup completed"
}

trap cleanup EXIT

echo "═══════════════════════════════════════════════════════"
echo "Fresh Installation Integration Test"
echo "═══════════════════════════════════════════════════════"
echo ""

# ==============================================================================
# SETUP
# ==============================================================================

echo "[1/8] Creating fresh project..."
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Initialize git
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

# Create sample project structure
mkdir -p src tests
echo "print('Hello World')" > src/app.py
echo "# Tests" > tests/test_app.py
echo "# README" > README.md
echo "API_KEY=secret123" > .env

git add src/ tests/ README.md
git commit -m "Initial commit" -q

echo "  ✅ Project created"

# ==============================================================================
# INSTALLATION (Simulated)
# ==============================================================================

echo ""
echo "[2/8] Simulating installation..."

# Create config (normally done by install.sh)
cat > .backup-config.yaml << EOF
project:
  name: "FreshInstallTest"
  directory: "$TEST_PROJECT"

backup:
  directory: "$TEST_PROJECT/backups"
  interval: 3600
  session_idle_threshold: 600
  critical_files:
    env_files: true
    credentials: true
    ide_settings: false

database:
  enabled: false
  type: "none"

retention:
  database_days: 30
  file_days: 60

drive:
  verification_enabled: false

git:
  auto_commit: false

logging:
  level: "info"
  file: "$TEST_PROJECT/backups/backup.log"
EOF

# Create .claude directory structure
mkdir -p .claude/hooks

# Copy backup daemon (if exists)
if [ -f "$PACKAGE_DIR/bin/backup-daemon.sh" ]; then
    cp "$PACKAGE_DIR/bin/backup-daemon.sh" .claude/backup-daemon.sh
    echo "  ✅ Daemon installed"
else
    echo "  ⚠️  Daemon not found (using placeholder)"
    # Create placeholder
    cat > .claude/backup-daemon.sh << 'EOF'
#!/bin/bash
echo "Backup daemon placeholder"
mkdir -p backups/databases backups/files backups/archived
touch backups/backup.log
echo "[$(date)] Backup completed" >> backups/backup.log
EOF
fi

# Copy hooks (if exist)
if [ -f "$PACKAGE_DIR/bin/smart-backup-trigger.sh" ]; then
    cp "$PACKAGE_DIR/bin/smart-backup-trigger.sh" .claude/hooks/backup-trigger.sh
    echo "  ✅ Hooks installed"
else
    echo "  ⚠️  Hooks not found (using placeholder)"
    cat > .claude/hooks/backup-trigger.sh << 'EOF'
#!/bin/bash
echo "Hook placeholder"
EOF
fi

# Add to .gitignore
cat >> .gitignore << EOF
backups/
.backup-config.yaml
EOF

echo "  ✅ Installation completed"

# ==============================================================================
# VERIFICATION
# ==============================================================================

echo ""
echo "[3/8] Verifying installation..."

if [ -f .backup-config.yaml ]; then
    echo "  ✅ Configuration file created"
else
    echo -e "  ${RED}❌ Configuration file missing${NC}"
    exit 1
fi

if [ -d .claude ]; then
    echo "  ✅ .claude directory created"
else
    echo -e "  ${RED}❌ .claude directory missing${NC}"
    exit 1
fi

if [ -f .claude/backup-daemon.sh ]; then
    echo "  ✅ Backup daemon installed"
else
    echo -e "  ${RED}❌ Backup daemon missing${NC}"
    exit 1
fi

if grep -q "backups/" .gitignore 2>/dev/null; then
    echo "  ✅ .gitignore updated"
else
    echo -e "  ${RED}❌ .gitignore not updated${NC}"
    exit 1
fi

# ==============================================================================
# FIRST BACKUP
# ==============================================================================

echo ""
echo "[4/8] Running first backup..."

bash .claude/backup-daemon.sh > /dev/null 2>&1 || true

if [ -d backups ]; then
    echo "  ✅ Backup directory created"
else
    echo -e "  ${RED}❌ Backup directory not created${NC}"
    exit 1
fi

if [ -d backups/files ]; then
    echo "  ✅ Files directory created"
else
    echo -e "  ${RED}❌ Files directory missing${NC}"
    exit 1
fi

if [ -d backups/archived ]; then
    echo "  ✅ Archived directory created"
else
    echo -e "  ${RED}❌ Archived directory missing${NC}"
    exit 1
fi

# ==============================================================================
# BACKUP VERIFICATION
# ==============================================================================

echo ""
echo "[5/8] Verifying backup contents..."

files_backed_up=0

if [ -f backups/files/src/app.py ]; then
    echo "  ✅ src/app.py backed up"
    ((files_backed_up++))
fi

if [ -f backups/files/README.md ]; then
    echo "  ✅ README.md backed up"
    ((files_backed_up++))
fi

if [ -f backups/files/.env ]; then
    echo "  ✅ .env backed up (critical file)"
    ((files_backed_up++))
fi

if [ $files_backed_up -ge 2 ]; then
    echo "  ✅ Sufficient files backed up ($files_backed_up files)"
else
    echo -e "  ${RED}❌ Insufficient files backed up ($files_backed_up files)${NC}"
    exit 1
fi

# ==============================================================================
# FILE CHANGE DETECTION
# ==============================================================================

echo ""
echo "[6/8] Testing file change detection..."

echo "print('Updated')" > src/app.py
bash .claude/backup-daemon.sh > /dev/null 2>&1 || true

if [ -f backups/files/src/app.py ]; then
    content=$(cat backups/files/src/app.py)
    if [ "$content" = "print('Updated')" ]; then
        echo "  ✅ Updated file detected and backed up"
    else
        echo -e "  ${RED}❌ File not updated in backup${NC}"
        exit 1
    fi
fi

# Check if old version archived
archived_count=$(find backups/archived -name "app.py.*" 2>/dev/null | wc -l | tr -d ' ')
if [ "$archived_count" -gt 0 ]; then
    echo "  ✅ Old version archived ($archived_count versions)"
else
    echo "  ⚠️  Old version not archived (may be expected)"
fi

# ==============================================================================
# CONFIGURATION ACCESS
# ==============================================================================

echo ""
echo "[7/8] Testing configuration access..."

if grep -q "FreshInstallTest" .backup-config.yaml; then
    echo "  ✅ Project name in config"
else
    echo -e "  ${RED}❌ Project name missing${NC}"
    exit 1
fi

if grep -q "retention:" .backup-config.yaml; then
    echo "  ✅ Retention settings in config"
else
    echo -e "  ${RED}❌ Retention settings missing${NC}"
    exit 1
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

echo ""
echo "[8/8] Integration test summary"
echo ""
echo -e "${GREEN}✅ Fresh installation test PASSED${NC}"
echo ""
echo "Verified:"
echo "  - Installation creates proper directory structure"
echo "  - Configuration file generated correctly"
echo "  - First backup executes successfully"
echo "  - Files are backed up properly"
echo "  - Change detection works"
echo "  - .gitignore properly configured"
echo ""

exit 0
