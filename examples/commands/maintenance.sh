#!/bin/bash
# Example: Regular Maintenance Workflow
# Demonstrates weekly/monthly maintenance tasks

set -euo pipefail

echo "═══════════════════════════════════════════════════════"
echo "Checkpoint - Maintenance Workflow"
echo "═══════════════════════════════════════════════════════"
echo ""

# Weekly Maintenance
echo "[WEEKLY MAINTENANCE]"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "1. Health Check"
echo "   /backup-status --verbose"
echo ""
echo "   Review:"
echo "   - All components healthy"
echo "   - No warnings"
echo "   - Backups running on schedule"
echo ""

echo "2. Check Disk Usage"
echo "   /backup-status | grep 'Total Size'"
echo "   df -h \$(pwd)/backups"
echo ""
echo "   Alert if:"
echo "   - Backup size growing unusually fast"
echo "   - Less than 20% disk space remaining"
echo ""

echo "3. Preview Cleanup"
echo "   /backup-cleanup --preview"
echo ""
echo "   Review what can be cleaned up:"
echo "   - Old database snapshots"
echo "   - Archived files past retention"
echo "   - Empty directories"
echo ""

echo "4. Review Recent Activity"
echo "   tail -100 backups/backup.log"
echo ""
echo "   Look for:"
echo "   - Any error messages"
echo "   - Unusual patterns"
echo "   - Missing backups"
echo ""

read -p "Press Enter for Monthly Maintenance..."
echo ""

# Monthly Maintenance
echo "[MONTHLY MAINTENANCE]"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "1. Execute Cleanup"
echo "   /backup-cleanup --execute"
echo ""
echo "   This removes:"
echo "   - Database backups older than retention"
echo "   - Archived files older than retention"
echo "   - Pre-restore backups (if successful)"
echo ""

echo "2. Review Retention Policies"
echo "   /backup-config --get retention"
echo ""
echo "   Consider adjusting if:"
echo "   - Disk space consistently tight"
echo "   - Need longer history"
echo "   - Project requirements changed"
echo ""

echo "3. Test Restore Process"
echo "   # Restore to temporary location"
echo "   mkdir /tmp/restore-test"
echo "   /backup-restore --database latest --no-backup"
echo "   # Verify database integrity"
echo "   # Clean up test"
echo "   rm -rf /tmp/restore-test"
echo ""

echo "4. Verify LaunchAgent"
echo "   launchctl list | grep com.claudecode.backup"
echo "   # Should show loaded and running"
echo ""

echo "5. Check Configuration"
echo "   /backup-config --validate"
echo ""
echo "   Ensure:"
echo "   - All paths still valid"
echo "   - Drive verification working (if enabled)"
echo "   - No deprecated settings"
echo ""

read -p "Press Enter for Quarterly Tasks..."
echo ""

# Quarterly Maintenance
echo "[QUARTERLY MAINTENANCE]"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "1. Full System Test"
echo "   /backup-status --check configuration"
echo "   /backup-status --check daemon"
echo "   /backup-status --check drive"
echo "   /backup-status --check backup_dir"
echo ""

echo "2. Review & Optimize"
echo "   /backup-cleanup --recommend"
echo ""
echo "   Act on recommendations:"
echo "   - Adjust retention"
echo "   - Exclude large files"
echo "   - Enable compression options"
echo ""

echo "3. Backup Statistics"
echo "   /backup-status --json > backup-stats-\$(date +%Y%m).json"
echo ""
echo "   Track over time:"
echo "   - Backup growth rate"
echo "   - Average backup size"
echo "   - File count trends"
echo ""

echo "4. External Backup"
echo "   # Backup your backups"
echo "   rsync -avz backups/ /external/backup/location/"
echo "   # or"
echo "   tar -czf backups-\$(date +%Y%m%d).tar.gz backups/"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "Automated Maintenance Script"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "Create: ~/bin/backup-maintenance.sh"
echo ""
cat << 'SCRIPT'
#!/bin/bash
# Automated weekly maintenance

echo "Running weekly backup maintenance..."

# Health check
/backup-status --warnings-only

# Cleanup preview
/backup-cleanup --preview

# Disk space check
backup_size=$(du -sh backups | awk '{print $1}')
echo "Backup size: $backup_size"

# Check last backup
last_backup=$(grep "Backup completed" backups/backup.log | tail -1)
echo "Last backup: $last_backup"

# Email report (optional)
# mail -s "Backup Maintenance Report" you@email.com << EOF
# ... report content ...
# EOF
SCRIPT

echo ""
echo "Make it executable:"
echo "  chmod +x ~/bin/backup-maintenance.sh"
echo ""
echo "Add to crontab (weekly on Sunday at 8am):"
echo "  0 8 * * 0 ~/bin/backup-maintenance.sh"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "Maintenance Checklist"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Weekly:"
echo "  ☐ Run health check"
echo "  ☐ Review disk usage"
echo "  ☐ Preview cleanup"
echo "  ☐ Check logs for errors"
echo ""
echo "Monthly:"
echo "  ☐ Execute cleanup"
echo "  ☐ Review retention policies"
echo "  ☐ Test restore process"
echo "  ☐ Verify LaunchAgent"
echo "  ☐ Validate configuration"
echo ""
echo "Quarterly:"
echo "  ☐ Full system test"
echo "  ☐ Review and optimize"
echo "  ☐ Generate statistics"
echo "  ☐ External backup"
echo ""
