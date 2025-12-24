#!/bin/bash
# Example: Basic Setup Workflow
# Demonstrates initial setup for a new project

set -euo pipefail

echo "═══════════════════════════════════════════════════════"
echo "Checkpoint - Basic Setup Example"
echo "═══════════════════════════════════════════════════════"
echo ""

# Step 1: Run configuration wizard
echo "[1/5] Running configuration wizard..."
echo ""
echo "Run: /backup-config wizard"
echo ""
echo "Answer the prompts:"
echo "  - Project name: MyApp"
echo "  - Project directory: $(pwd)"
echo "  - Database backups: Yes/No (depending on your project)"
echo "  - Retention: 30 days (database), 60 days (files)"
echo ""
read -p "Press Enter to continue..."

# Step 2: Validate configuration
echo ""
echo "[2/5] Validating configuration..."
echo ""
echo "Run: /backup-config --validate"
echo ""
echo "This checks:"
echo "  - All required fields present"
echo "  - Paths exist and are accessible"
echo "  - Retention values are valid"
echo ""
read -p "Press Enter to continue..."

# Step 3: Check status
echo ""
echo "[3/5] Checking system status..."
echo ""
echo "Run: /backup-status"
echo ""
echo "Verify:"
echo "  ✅ Configuration: Valid"
echo "  ✅ LaunchAgent: Running"
echo "  ✅ Backup Directory: Writable"
echo ""
read -p "Press Enter to continue..."

# Step 4: Test with dry-run
echo ""
echo "[4/5] Testing backup with dry-run..."
echo ""
echo "Run: /backup-now --dry-run"
echo ""
echo "Review what will be backed up:"
echo "  - Modified files"
echo "  - Critical files (.env, credentials, etc.)"
echo "  - Database (if enabled)"
echo ""
read -p "Press Enter to continue..."

# Step 5: Run first backup
echo ""
echo "[5/5] Running first backup..."
echo ""
echo "Run: /backup-now --force"
echo ""
echo "This will:"
echo "  - Create backup directory structure"
echo "  - Back up all tracked files"
echo "  - Back up critical gitignored files"
echo "  - Create initial database snapshot (if enabled)"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "Setup Complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Your backups are now configured and running."
echo ""
echo "Next steps:"
echo "  - Verify backups: ls -la backups/"
echo "  - Check status: /backup-status"
echo "  - Monitor logs: tail -f backups/backup.log"
echo ""
echo "Automatic backups will run hourly and on first Claude Code prompt."
echo ""
