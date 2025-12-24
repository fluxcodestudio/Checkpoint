# Cloud Backup Guide

Add off-site protection to Checkpoint with automatic cloud uploads via rclone.

## Overview

Cloud backup provides an additional layer of protection by automatically uploading your backups to cloud storage (Dropbox, Google Drive, OneDrive, or iCloud Drive).

**Benefits:**
- Off-site disaster recovery
- Access backups from anywhere
- Protection against hardware failure
- Free tier available on all providers

**Smart Upload Strategy:**
- Databases: Always uploaded (compressed, small ~2MB)
- Critical files: Always uploaded (.env, credentials)
- Project files: Optional (source code already in Git)

---

## Quick Start

### 1. Run Configuration Wizard

```bash
./bin/backup-cloud-config.sh
```

The wizard will guide you through:
1. Choosing backup location (local/cloud/both)
2. Selecting local backup directory
3. Choosing cloud provider
4. Installing/configuring rclone
5. Selecting what to upload

### 2. Manual Configuration

Add to your `.backup-config.sh`:

```bash
# Cloud Backup Configuration
BACKUP_LOCATION="both"              # local | cloud | both
LOCAL_BACKUP_DIR="/Volumes/Backups/MyProject"
CLOUD_ENABLED=true
CLOUD_PROVIDER="dropbox"            # dropbox | gdrive | onedrive | icloud
CLOUD_REMOTE_NAME="mydropbox"       # rclone remote name
CLOUD_BACKUP_PATH="/Backups/MyProject"
CLOUD_SYNC_DATABASES=true           # Upload compressed DBs
CLOUD_SYNC_CRITICAL=true            # Upload .env, credentials
CLOUD_SYNC_FILES=false              # Skip project files
```

---

## Cloud Providers

### Dropbox

**Free Tier:** 2GB
**Cost:** $12/month for 2TB
**Best for:** Small databases, critical files

**Setup:**
```bash
rclone config
# Choose: Dropbox
# Follow browser authentication
```

### Google Drive

**Free Tier:** 15GB
**Cost:** $2/month for 100GB
**Best for:** Larger backups, most generous free tier

**Setup:**
```bash
rclone config
# Choose: Google Drive
# Follow browser authentication
```

### OneDrive

**Free Tier:** 5GB
**Cost:** $2/month for 100GB
**Best for:** Windows users, Microsoft ecosystem

**Setup:**
```bash
rclone config
# Choose: OneDrive
# Follow browser authentication
```

### iCloud Drive

**Free Tier:** 5GB
**Cost:** $1/month for 50GB
**Best for:** macOS users, native integration

**Setup:**
```bash
rclone config
# Choose: iCloud
# Follow browser authentication
```

---

## Storage Estimates

**Example Project:**
- 10MB database → 2MB compressed
- 30 days retention → ~60MB total
- Critical files → ~5MB
- **Total: ~65MB** (fits in all free tiers)

**Recommendations:**
- ✅ Upload databases (small, critical)
- ✅ Upload critical files (.env, credentials)
- ❌ Skip project files (already in Git)
- ✅ Use free tier for most projects

---

## Configuration Options

### Backup Location

```bash
BACKUP_LOCATION="local"    # Local only (fast, no cloud costs)
BACKUP_LOCATION="cloud"    # Cloud only (slower, requires internet)
BACKUP_LOCATION="both"     # Best protection (recommended)
```

### Upload Selection

```bash
# Always upload (recommended)
CLOUD_SYNC_DATABASES=true   # ~2MB per backup
CLOUD_SYNC_CRITICAL=true    # .env, credentials, keys

# Optional (can be large)
CLOUD_SYNC_FILES=false      # All project files
```

### Advanced Options

```bash
# Bandwidth limiting (optional)
export RCLONE_BW_LIMIT=1M   # 1MB/s upload limit

# Encryption (optional)
# Configure encrypted remote in rclone:
rclone config
# Choose: Crypt
# Set password for client-side encryption
```

---

## Usage

### Automatic Uploads

Cloud uploads happen automatically after each backup:

```bash
# Daemon runs hourly, uploads to cloud after backup
./bin/backup-daemon.sh
```

### Manual Upload

```bash
# Trigger backup now (includes cloud upload)
./bin/backup-now.sh

# Local backup only (skip cloud)
./bin/backup-now.sh --local-only

# Cloud upload only (no new backup)
./bin/backup-now.sh --cloud-only
```

### Check Cloud Status

```bash
./bin/backup-status.sh
```

Output includes:
```
🔧 Components
  ✅ Daemon:           Running
  ✅ Cloud:            2 hours ago
```

---

## Troubleshooting

### "rclone not installed"

**Solution:**
```bash
# macOS (Homebrew)
brew install rclone

# macOS/Linux (curl)
curl https://rclone.org/install.sh | bash
```

### "Cloud remote not found"

**Solution:**
```bash
# List configured remotes
rclone listremotes

# Configure new remote
rclone config
```

### "Connection failed"

**Causes:**
- No internet connection
- Remote not configured correctly
- Authentication expired

**Solution:**
```bash
# Test connection
rclone lsd remotename:

# Reconfigure remote
rclone config reconnect remotename:
```

### "Upload too slow"

**Solutions:**
```bash
# Reduce what you upload
CLOUD_SYNC_FILES=false  # Skip project files

# Limit bandwidth (if needed)
export RCLONE_BW_LIMIT=500K

# Upload only databases
CLOUD_SYNC_DATABASES=true
CLOUD_SYNC_CRITICAL=false
CLOUD_SYNC_FILES=false
```

### "Storage quota exceeded"

**Solutions:**
1. Reduce retention period
2. Upload only databases
3. Upgrade to paid tier
4. Switch to provider with larger free tier (Google Drive: 15GB)

---

## Security Best Practices

### Client-Side Encryption

Encrypt files before uploading:

```bash
# Create encrypted remote
rclone config
# Name: mydropbox-encrypted
# Type: crypt
# Remote: mydropbox:/Backups
# Password: (set strong password)

# Use encrypted remote in config
CLOUD_REMOTE_NAME="mydropbox-encrypted"
```

**Benefits:**
- Cloud provider cannot read your data
- Encryption happens locally before upload
- No performance impact on downloads

### Credential Safety

**Never commit:**
- `.backup-config.sh` (contains remote names)
- rclone.conf (contains credentials)

**Safe storage:**
```bash
# rclone stores config at:
~/.config/rclone/rclone.conf

# Secure permissions
chmod 600 ~/.config/rclone/rclone.conf
```

### Access Control

**Recommendations:**
- Use app-specific passwords (not main account)
- Enable 2FA on cloud accounts
- Review connected apps regularly
- Revoke access if compromised

---

## Performance Tips

### Background Uploads

Cloud uploads run in background (don't block backups):

```bash
# In backup-daemon.sh
cloud_upload_background  # Runs in background
```

### Transfer Optimization

```bash
# Increase parallelism
rclone copy source dest --transfers 8

# Enable checksums
rclone copy source dest --checksum

# Resume failed uploads
rclone copy source dest --retries 3
```

### Bandwidth Management

```bash
# Limit upload speed
export RCLONE_BW_LIMIT=1M

# Schedule uploads for off-hours
# (Configure in launchd/cron)
```

---

## Migration Guide

### From Local-Only to Cloud

1. Run cloud configuration wizard:
```bash
./bin/backup-cloud-config.sh
```

2. Existing backups stay local

3. New backups upload to cloud

4. (Optional) Upload existing backups:
```bash
rclone copy /path/to/local/backups remotename:/Backups/Project
```

### From Cloud-Only to Both

Update configuration:
```bash
BACKUP_LOCATION="both"
LOCAL_BACKUP_DIR="/Volumes/Backups/MyProject"
```

### Change Cloud Provider

1. Configure new remote:
```bash
rclone config
```

2. Update configuration:
```bash
CLOUD_REMOTE_NAME="new-remote"
```

3. (Optional) Copy existing backups:
```bash
rclone copy old-remote:/Backups new-remote:/Backups
```

---

## FAQ

**Q: Does cloud backup slow down my backups?**
A: No. Cloud uploads run in background and don't block local backups.

**Q: What if I lose internet connection?**
A: Local backups continue normally. Cloud uploads queue and retry when connection restored.

**Q: Can I use multiple cloud providers?**
A: Not currently. Choose one provider per project.

**Q: Does this work with S3/Backblaze?**
A: Yes! rclone supports 40+ providers. Follow rclone docs for setup.

**Q: How do I restore from cloud?**
A: Download from cloud, then use normal restore:
```bash
rclone copy remotename:/Backups/Project /tmp/restore
./bin/backup-restore.sh --from /tmp/restore
```

**Q: What's uploaded to cloud?**
A: Depends on configuration. Default: compressed databases + critical files (.env, credentials). Project files are optional.

**Q: Is my data encrypted?**
A: Optional. Configure rclone crypt remote for client-side encryption.

**Q: Can I see upload progress?**
A: Yes, for manual uploads:
```bash
./bin/backup-now.sh  # Shows progress
```

---

## Related Commands

```bash
# Configure cloud backup
./bin/backup-cloud-config.sh

# Check cloud status
./bin/backup-status.sh

# Manual cloud upload
./bin/backup-now.sh

# Skip cloud for one backup
./bin/backup-now.sh --local-only

# Test rclone connection
rclone lsd remotename:

# List cloud backups
rclone ls remotename:/Backups/Project

# Download from cloud
rclone copy remotename:/Backups/Project /tmp/restore
```

---

## Support

**Issues:**
- Check rclone version: `rclone version`
- Test connection: `rclone lsd remotename:`
- View logs: Check `backups/backup.log`

**rclone Help:**
- Documentation: https://rclone.org/docs/
- Forum: https://forum.rclone.org/

**Checkpoint Help:**
- GitHub: https://github.com/nizernoj/Checkpoint
