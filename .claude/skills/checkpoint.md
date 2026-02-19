---
name: checkpoint
description: /checkpoint - Automated Backup Command Center
user_invocable: true
match:
  - /checkpoint
  - /backup
---

# Checkpoint v2.5.2 — Command Center

You are the Checkpoint backup command center. When the user invokes `/checkpoint`, present them with an interactive menu using AskUserQuestion so they can choose what they want to do. Do NOT just dump status — ask first.

## On Invocation

Present this menu using AskUserQuestion:

**Question:** "What would you like to do?"
**Options:**
1. **Check Status** — View backup health, project list, storage usage
2. **Run Backup Now** — Trigger an immediate backup of the current project
3. **Settings** — Configure backup settings (global or per-project)
4. **Manage Projects** — Add, remove, or view registered projects

Then execute the chosen action using the bash commands below.

## Commands Reference

All commands require PATH setup: `export PATH="$HOME/.local/bin:$PATH"`

### Status
```bash
export PATH="$HOME/.local/bin:$PATH" && checkpoint --status
```
After running, summarize the key info: version, daemon status, project count, last backup time, cloud sync status, storage usage.

### Run Backup Now
```bash
export PATH="$HOME/.local/bin:$PATH" && backup-now
```

### Settings

Ask the user what they want to configure using AskUserQuestion:
- **Global settings** — Schedule, retention, notifications, cloud sync, encryption
- **Project settings** — Per-project overrides for the current directory
- **Cloud & encryption** — Cloud provider, folder path, encryption toggle

**Global settings:**
```bash
# Read current global config
cat ~/.config/checkpoint/config.sh
```
Then show the user their current settings and ask what they want to change. Write changes back to `~/.config/checkpoint/config.sh`.

**Project settings:**
```bash
# Read current project config
cat .backup-config.sh
```
Then show the user their current settings and ask what they want to change. Write changes back to `.backup-config.sh`.

**Encryption:**
```bash
export PATH="$HOME/.local/bin:$PATH" && checkpoint encrypt status
```
If not set up, offer to run `checkpoint encrypt setup`.

### Manage Projects

```bash
# List all registered projects
cat ~/.config/checkpoint/projects.json
```
Show the user their registered projects. Offer to:
- **Add a project** — Run `backup-now` in a directory to register it
- **Remove a project** — Delete the `.backup-config.sh` from a project directory
- **View project details** — Show config for a specific project

### Additional Commands

These are available if the user asks:
```bash
# Search backup history
export PATH="$HOME/.local/bin:$PATH" && checkpoint search "PATTERN"

# Browse snapshots interactively
export PATH="$HOME/.local/bin:$PATH" && checkpoint browse

# View file version history
export PATH="$HOME/.local/bin:$PATH" && checkpoint history FILE

# Verify backup integrity
export PATH="$HOME/.local/bin:$PATH" && checkpoint verify

# Compare working directory with backup
export PATH="$HOME/.local/bin:$PATH" && checkpoint diff

# Check for updates
export PATH="$HOME/.local/bin:$PATH" && checkpoint --update

# Cleanup old backups
export PATH="$HOME/.local/bin:$PATH" && backup-cleanup

# Restore files
export PATH="$HOME/.local/bin:$PATH" && backup-restore
```

## Behavior Rules

1. Always use AskUserQuestion for navigation — don't assume what the user wants
2. After completing an action, ask if they want to do anything else
3. When showing settings, display current values and ask what to change
4. For config edits, use the Edit tool to modify config files directly — don't make the user copy-paste
5. Summarize command output concisely — don't dump raw terminal output without context
6. If a command fails, explain what went wrong and suggest a fix
