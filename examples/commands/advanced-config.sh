#!/bin/bash
# Example: Advanced Configuration
# Demonstrates advanced configuration options

set -euo pipefail

echo "═══════════════════════════════════════════════════════"
echo "Checkpoint - Advanced Configuration"
echo "═══════════════════════════════════════════════════════"
echo ""

# Configuration Examples

echo "[Advanced Configuration Examples]"
echo ""

echo "1. Extended Retention for Critical Project"
echo "   /backup-config --set retention.database_days=90"
echo "   /backup-config --set retention.file_days=180"
echo ""

echo "2. Enable Automatic Git Commits"
echo "   /backup-config --set git.auto_commit=true"
echo "   /backup-config --set git.auto_push=false"
echo ""

echo "3. External Drive Setup"
echo "   /backup-config --set drive.verification_enabled=true"
echo "   /backup-config --set drive.marker_file=/Volumes/MyDrive/.backup-marker"
echo ""

echo "4. Custom Backup Interval (2 hours)"
echo "   /backup-config --set backup.interval=7200"
echo ""

echo "5. Enable Debug Logging"
echo "   /backup-config --set logging.level=debug"
echo ""

echo "6. Configure Database Backup"
echo "   /backup-config --set database.enabled=true"
echo "   /backup-config --set database.type=sqlite"
echo "   /backup-config --set database.path=/path/to/db.db"
echo ""

echo "7. Disable Specific Critical Files"
echo "   /backup-config --set backup.critical_files.ide_settings=false"
echo "   /backup-config --set backup.critical_files.local_notes=false"
echo ""

echo "8. View All Configuration"
echo "   /backup-config --get"
echo ""

echo "9. View Specific Section"
echo "   /backup-config --get retention"
echo "   /backup-config --get database"
echo ""

echo "10. JSON Output for Scripting"
echo "    /backup-config --get --json > config.json"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "Advanced Workflows"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "Multi-Computer Setup:"
echo "  1. Configure on Computer A:"
echo "     /backup-config --set drive.verification_enabled=true"
echo "     /backup-config --set drive.marker_file=/Volumes/SharedDrive/.marker"
echo ""
echo "  2. Configure on Computer B:"
echo "     (Same settings as Computer A)"
echo ""
echo "  3. Drive verification ensures only one computer backs up at a time"
echo ""

echo "Paranoid Retention:"
echo "  /backup-config --set retention.database_days=365"
echo "  /backup-config --set retention.file_days=365"
echo "  /backup-config --set retention.keep_minimum=10"
echo ""

echo "Database-Only Backups:"
echo "  /backup-now --db-only"
echo "  (Useful for frequent database snapshots)"
echo ""

echo "Custom Cleanup Schedule:"
echo "  # Weekly aggressive cleanup"
echo "  /backup-cleanup --execute --age 30"
echo ""
echo "  # Emergency space recovery"
echo "  /backup-cleanup --execute --size 1GB"
echo ""
