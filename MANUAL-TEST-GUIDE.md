# Manual Testing Guide - Checkpoint v2.1.0

Experience the complete user journey for both installation modes.

---

## Prerequisites

Before starting, ensure rclone is NOT installed (to test auto-install):
```bash
# Check if rclone is installed
command -v rclone && echo "rclone IS installed" || echo "rclone NOT installed (good for testing)"

# If installed and you want to test auto-install, temporarily move it
# (Optional - only if you want to test rclone auto-install)
which rclone  # Note the path
sudo mv /usr/local/bin/rclone /usr/local/bin/rclone.backup
```

---

## Test 1: Global Installation (Recommended Flow)

### Step 1: Create Test Project
```bash
# Create a fresh test project
mkdir -p ~/test-checkpoint-global
cd ~/test-checkpoint-global

# Initialize git (required for Checkpoint)
git init
echo "# Test Project" > README.md
git add README.md
git commit -m "Initial commit"

# Create a dummy database (optional, to test database backups)
echo "CREATE TABLE users (id INTEGER, name TEXT);" | sqlite3 test.db
```

### Step 2: Run Global Installation
```bash
# Run installer
/Volumes/WORK\ DRIVE\ -\ 4TB/WEB\ DEV/CLAUDE\ CODE\ PROJECT\ BACKUP/bin/install.sh
```

**What You'll See:**
```
═══════════════════════════════════════════════
Checkpoint - Installation
═══════════════════════════════════════════════

Choose installation mode:
  [1] Global (recommended)
      • Install once, use in all projects
      • Commands available system-wide (backup-now, backup-status, etc.)
      • Easy updates (git pull, reinstall)
      • Requires: write access to /usr/local/bin or ~/.local/bin

  [2] Per-Project
      • Self-contained in this project only
      • No system modifications needed
      • Portable (copy project = copy backup system)
      • Good for: shared systems, containers

Choose mode (1/2) [1]:
```

**Enter:** `1` (Global mode)

### Step 3: Follow Global Installation Prompts
```
Launching global installer...

═══════════════════════════════════════════════
Checkpoint - Global Installation
═══════════════════════════════════════════════

This will install Checkpoint system-wide.
Commands will be available in all projects.

Installing to: ~/.local (user-only, no sudo required)

⚠️  Make sure ~/.local/bin is in your PATH:
    export PATH="$HOME/.local/bin:$PATH"

Continue with installation? (y/n) [y]:
```

**Enter:** `y`

**What Happens:**
- Creates `~/.local/lib/checkpoint/` (all source files)
- Creates symlinks in `~/.local/bin/` (commands)
- Shows installation summary

### Step 4: Add to PATH (if needed)
```bash
# Check if commands are available
command -v backup-now && echo "✓ Commands in PATH" || echo "✗ Add ~/.local/bin to PATH"

# If needed, add to PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc  # or ~/.bashrc
source ~/.zshrc  # Reload

# Verify
backup-now --help  # Should work system-wide!
```

### Step 5: Configure This Project
Now that Checkpoint is installed globally, configure it for this project:

```bash
# Still in ~/test-checkpoint-global
# The global installer doesn't auto-configure projects
# So let's create a minimal config or run backup-now which will prompt

# Option A: Run backup-now (will prompt for config if missing)
backup-now

# Option B: Manually create config
cat > .backup-config.sh << 'EOF'
#!/bin/bash
PROJECT_NAME="TestGlobal"
PROJECT_DIR="$PWD"
BACKUP_DIR="$PWD/backups"
DB_PATH="$PWD/test.db"
DB_TYPE="sqlite"
CLOUD_ENABLED=false
EOF
chmod +x .backup-config.sh
```

### Step 6: Test Global Commands
```bash
# Run backup
backup-now

# Check status
backup-status

# View backups
ls -la backups/
ls -la backups/databases/
ls -la backups/files/
```

### Step 7: Test Cloud Backup (Progressive rclone)
```bash
# Run cloud config wizard
backup-cloud-config
```

**What You'll See:**
```
═══════════════════════════════════════════════
Checkpoint - Cloud Backup Configuration
═══════════════════════════════════════════════


═══════════════════════════════════════════════
rclone Installation Required
═══════════════════════════════════════════════

Cloud backup requires rclone:
  • Free, open-source tool (MIT license)
  • Supports 40+ cloud providers
  • Size: ~50MB
  • Homepage: https://rclone.org

Install rclone now? (y/n) [y]:
```

**Testing Options:**

**Option A: Test Auto-Install (requires Homebrew)**
- Enter: `y`
- Watch it install rclone via Homebrew
- Proceeds to cloud configuration wizard

**Option B: Decline Installation**
- Enter: `n`
- See: "⊘ rclone installation skipped"
- Wizard exits
- Can run again later after manual install

---

## Test 2: Per-Project Installation

### Step 1: Create New Test Project
```bash
# Create different test project
mkdir -p ~/test-checkpoint-project
cd ~/test-checkpoint-project

# Initialize git
git init
echo "# Per-Project Test" > README.md
git add README.md
git commit -m "Initial commit"
```

### Step 2: Run Per-Project Installation
```bash
# Run installer
/Volumes/WORK\ DRIVE\ -\ 4TB/WEB\ DEV/CLAUDE\ CODE\ PROJECT\ BACKUP/bin/install.sh
```

**Enter:** `2` (Per-project mode)

### Step 3: Follow Installation Wizard
```
═══════════════════════════════════════════════
Per-Project Installation
═══════════════════════════════════════════════

Package location: /Volumes/WORK DRIVE - 4TB/WEB DEV/CLAUDE CODE PROJECT BACKUP
Project location: /Users/yourname/test-checkpoint-project

Checking dependencies...

✅ All required dependencies found

Let's configure backups for your project...

Project name (for backup filenames): TestPerProject
```

**Continue through wizard:**
- Project name: `TestPerProject`
- Database path: Skip (press Enter) or provide path
- Database type: `none` or `sqlite`
- Retention: Accept defaults or customize
- Auto-commit: `n`
- Critical files: `y` for all
- **Cloud backup question:** `y` to test rclone auto-install

**Cloud Backup Prompt:**
```
Do you want cloud backup? (Dropbox, Google Drive, etc.) (y/n) [n]: y

Cloud backup will be configured...

═══════════════════════════════════════════════
rclone Installation Required
═══════════════════════════════════════════════

Cloud backup requires rclone:
  • Free, open-source tool (MIT license)
  • Supports 40+ cloud providers
  • Size: ~50MB
  • Homepage: https://rclone.org

Install rclone now? (y/n) [y]:
```

**Enter:** `y` or `n` depending on what you want to test

### Step 4: Test Per-Project Commands
```bash
# Commands are in .claude/ and bin/ directories
./bin/backup-now.sh

# Check status
./bin/backup-status.sh

# View backups
ls -la backups/
ls -la .claude/
```

### Step 5: Test Cloud Config (if skipped during install)
```bash
# Run cloud config wizard
./bin/backup-cloud-config.sh

# Will auto-prompt for rclone if missing
# Then proceed to provider selection
```

---

## Test 3: Cloud Configuration Wizard (Full Flow)

**Prerequisites:** rclone must be installed (manually or auto-installed above)

### Step 1: Run Cloud Wizard
```bash
# Global mode:
backup-cloud-config

# Per-project mode:
./bin/backup-cloud-config.sh
```

### Step 2: Follow Wizard Prompts
```
═══════════════════════════════════════════════
Checkpoint - Cloud Backup Configuration
═══════════════════════════════════════════════

✅ rclone ready

1. Where do you want to store backups?

   [1] Local only (recommended for speed)
   [2] Cloud only (requires internet)
   [3] Both local + cloud (best protection)

Choice [1-3]: 3
```

**Enter:** `3` (Both local + cloud)

```
2. Choose local backup directory:

   [1] Project folder: ./backups
   [2] External drive: /Volumes/Backups
   [3] Custom path

Choice [1-3]: 1
```

**Enter:** `1` (Project folder)

```
✓ Local backup directory: /Users/jonrezin/test-checkpoint-project/backups

3. Choose cloud storage provider:

   [1] Dropbox (2GB free)
   [2] Google Drive (15GB free)
   [3] OneDrive (5GB free)
   [4] iCloud Drive (5GB free)

Choice [1-4]:
```

**For Testing Without Real OAuth:**
- Enter: `1` (Dropbox)
- When prompted for rclone config, press `Ctrl+C` to exit
- This tests the wizard flow without actual cloud setup

**For Full Integration Test:**
- Choose a provider you have access to
- Complete OAuth flow
- Configure backup path
- Test actual upload

---

## Test 4: Verify Installation

### Global Mode Verification
```bash
# Commands should work from anywhere
cd ~
backup-now --help  # Should work
backup-status --help  # Should work

# Check installation
ls -la ~/.local/bin/backup-*
ls -la ~/.local/lib/checkpoint/
```

### Per-Project Mode Verification
```bash
cd ~/test-checkpoint-project

# Commands are local
./bin/backup-now.sh --help
./bin/backup-status.sh --help

# Check installation
ls -la .claude/
ls -la .backup-config.sh
ls -la backups/
```

---

## Test 5: Edge Cases

### Test: Declining rclone Installation
```bash
# Run cloud config
backup-cloud-config  # or ./bin/backup-cloud-config.sh

# When prompted: "Install rclone now?"
# Enter: n

# Expected: Graceful exit with manual install instructions
```

### Test: rclone Already Installed
```bash
# If you backed up rclone earlier, restore it:
sudo mv /usr/local/bin/rclone.backup /usr/local/bin/rclone

# Run cloud config again
backup-cloud-config

# Expected: Skips rclone install, goes straight to provider selection
```

### Test: Running Installer Twice
```bash
# Try installing global mode again
/Volumes/WORK\ DRIVE\ -\ 4TB/WEB\ DEV/CLAUDE\ CODE\ PROJECT\ BACKUP/bin/install.sh

# Choose: 1 (Global)
# Expected: Overwrites existing installation, updates files
```

---

## Cleanup After Testing

### Remove Global Installation
```bash
# Remove binaries
rm -f ~/.local/bin/backup-*

# Remove libraries
rm -rf ~/.local/lib/checkpoint

# Remove from PATH (edit ~/.zshrc or ~/.bashrc)
# Remove line: export PATH="$HOME/.local/bin:$PATH"
```

### Remove Per-Project Installation
```bash
# Remove test projects
rm -rf ~/test-checkpoint-global
rm -rf ~/test-checkpoint-project
```

### Restore rclone (if backed up)
```bash
# If you moved rclone, restore it
sudo mv /usr/local/bin/rclone.backup /usr/local/bin/rclone
```

---

## What to Look For

### ✅ Good Signs:
- Clear installation prompts
- Transparent dependency installation
- Commands work as expected
- Helpful error messages
- Configuration files created correctly
- Backups actually created

### 🚩 Red Flags:
- Confusing prompts
- Silent failures
- Missing error messages
- Commands not found after global install
- rclone installs without permission
- Broken wizard flows

---

## Quick Test Script

Want to test everything quickly?

```bash
cd /Volumes/WORK\ DRIVE\ -\ 4TB/WEB\ DEV/CLAUDE\ CODE\ PROJECT\ BACKUP

# Create quick test
mkdir -p /tmp/quick-test && cd /tmp/quick-test
git init
echo "test" > file.txt
git add . && git commit -m "test"

# Run installer (will prompt for input)
/Volumes/WORK\ DRIVE\ -\ 4TB/WEB\ DEV/CLAUDE\ CODE\ PROJECT\ BACKUP/bin/install.sh

# Follow prompts, test features
# When done: rm -rf /tmp/quick-test
```

---

## Report Issues

If you find bugs or UX problems during testing:
1. Note the exact steps to reproduce
2. Copy error messages
3. Check if it's installation mode specific
4. Test if it's rclone related

Ready to test! 🚀
