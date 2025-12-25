# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.x.x   | :white_check_mark: |
| < 2.0   | :x:                |

## Reporting a Vulnerability

We take the security of Checkpoint seriously. If you discover a security vulnerability, please follow these steps:

### How to Report

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, please report security vulnerabilities by emailing:
- Create a private security advisory on GitHub
- Or open an issue with `[SECURITY]` prefix (we'll move it to private advisory)

### What to Include

Please include the following information in your report:
- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact
- Suggested fix (if you have one)

### Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity
  - Critical: 1-7 days
  - High: 7-30 days
  - Medium: 30-90 days
  - Low: Best effort

## Security Best Practices

When using Checkpoint:

### 1. Protect Your Backup Configuration
- Never commit `.backup-config.sh` to git (it's in .gitignore by default)
- Keep database credentials secure
- Use environment variables for sensitive data

### 2. Secure Your Backups
- Encrypt cloud backups when possible
- Use strong passwords for cloud storage
- Regularly rotate access credentials
- Review who has access to backup storage

### 3. Verify Backup Integrity
- Regularly test backup restoration
- Verify backup file permissions
- Monitor backup logs for anomalies

### 4. Database Security
- Use read-only database users for backups when possible
- Avoid storing plain-text passwords in config files
- Use connection strings with encryption enabled

### 5. Cloud Backup Security
- Enable 2FA on cloud storage accounts
- Use app-specific passwords (not main account password)
- Review rclone configuration regularly
- Monitor cloud storage access logs

## Known Security Considerations

### Backup File Contents
Backup files may contain:
- Database dumps (potentially including user data)
- Environment variables (.env files)
- Credentials and API keys
- SSH keys and certificates

**Recommendations:**
- Store backups in encrypted storage
- Use .gitignore to prevent committing backups
- Implement retention policies to auto-delete old backups
- Review backup contents before sharing

### File Permissions
- Backup scripts run with user permissions
- Configuration files should be readable only by the user
- Database backups inherit permissions from the database files

### rclone Security
- rclone stores credentials in `~/.config/rclone/rclone.conf`
- This file contains OAuth tokens and API keys
- Protect this file with appropriate permissions (600)

## Disclosure Policy

When a vulnerability is fixed:
1. We'll create a security advisory on GitHub
2. Credit will be given to the reporter (unless they prefer to remain anonymous)
3. A CVE will be requested for significant vulnerabilities
4. The fix will be released in a new version
5. Users will be notified via release notes and security advisory

## Security Updates

Subscribe to security updates:
- Watch this repository for security advisories
- Follow releases for security patches
- Review the CHANGELOG for security-related fixes

Thank you for helping keep Checkpoint secure!
