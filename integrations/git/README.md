# Git Hooks Integration

Automatic backup integration for Git repositories using hooks.

## Features

- **Pre-Commit Hook**: Automatically creates a backup before each commit
- **Post-Commit Hook**: Displays backup status after commit completes
- **Pre-Push Hook**: Verifies backup is current before pushing to remote

## Installation

From within your git repository:

```bash
cd /path/to/your/git/repo
/path/to/CLAUDE_CODE_PROJECT_BACKUP/integrations/git/install-git-hooks.sh
```

The installer will:
1. Detect your git hooks directory
2. Backup any existing hooks
3. Install the three backup hooks
4. Make them executable

## How It Works

### Pre-Commit Hook
- Runs before `git commit`
- Creates a forced backup (bypasses debounce)
- Shows progress message (unless quiet mode)
- Can optionally block commits if backup fails

### Post-Commit Hook
- Runs after `git commit` completes
- Shows compact backup status
- Displays time since last backup
- Informational only (doesn't block)

### Pre-Push Hook
- Runs before `git push`
- Checks age of last backup
- Auto-creates fresh backup if too old (default: 1 hour)
- Can optionally block pushes if backup fails

## Configuration

Set these environment variables in your `~/.bashrc` or `~/.zshrc`:

```bash
# Disable specific hooks
export BACKUP_GIT_PRE_COMMIT_DISABLED=false
export BACKUP_GIT_POST_COMMIT_DISABLED=false
export BACKUP_GIT_PRE_PUSH_DISABLED=false

# Quiet mode (suppress all messages)
export BACKUP_GIT_QUIET=false

# Block commits/pushes on backup failure
export BACKUP_GIT_BLOCK_ON_FAILURE=false           # Block commits
export BACKUP_GIT_BLOCK_PUSH_ON_FAILURE=false      # Block pushes

# Pre-push backup age threshold (seconds)
export BACKUP_GIT_MAX_BACKUP_AGE=3600              # Default: 1 hour
```

## Examples

### Default Behavior

```bash
$ git commit -m "Update feature"
🔄 Creating backup before commit...
✅ Backup created successfully
[main abc1234] Update feature
 1 file changed, 10 insertions(+)

📊 Backup Status:
   ✅ All backups current (2 projects, 5m ago)
   Last backup: 5m ago
```

### Quiet Mode

```bash
export BACKUP_GIT_QUIET=true

$ git commit -m "Update feature"
[main abc1234] Update feature
 1 file changed, 10 insertions(+)
```

### Block on Failure

```bash
export BACKUP_GIT_BLOCK_ON_FAILURE=true

$ git commit -m "Update feature"
🔄 Creating backup before commit...
❌ Backup failed - commit blocked
   Set BACKUP_GIT_BLOCK_ON_FAILURE=false to allow commits anyway
```

### Pre-Push Verification

```bash
$ git push origin main
⚠️  Warning: Last backup was 2h ago
   Creating fresh backup before push...
   ✅ Backup created successfully
Enumerating objects: 5, done.
...
```

## Uninstallation

Remove the hooks:

```bash
rm .git/hooks/pre-commit
rm .git/hooks/post-commit
rm .git/hooks/pre-push
```

Restore backups if you had existing hooks:

```bash
ls -la .git/hooks/*.backup.*
# Manually restore the ones you need
```

## Compatibility

- Works with all git versions
- Compatible with other git hooks (backs up existing)
- Uses integration-core.sh for consistency
- Respects all debounce and lock mechanisms

## Troubleshooting

### Hook not running

1. Check if hook is executable:
   ```bash
   ls -la .git/hooks/pre-commit
   ```

2. Re-run installer:
   ```bash
   ./install-git-hooks.sh
   ```

### Integration-core.sh not found

The hooks expect this directory structure:
```
integrations/
├── lib/
│   └── integration-core.sh
└── git/
    └── hooks/
        └── pre-commit
```

Make sure you installed from the correct backup system directory.

### Backup fails silently

Check the backup system directly:

```bash
backup status
backup now --force
```

If those commands don't work, the core backup system may not be configured correctly.

## Advanced Usage

### Per-Repository Configuration

Create `.git/hooks/pre-commit-custom.conf`:

```bash
#!/bin/bash
# Override settings for this repo only
export BACKUP_GIT_QUIET=true
export BACKUP_GIT_MAX_BACKUP_AGE=7200  # 2 hours for this repo
```

Then source it in the hook (edit `.git/hooks/pre-commit`):

```bash
# Add before the main hook logic
[[ -f "$GIT_DIR/hooks/pre-commit-custom.conf" ]] && source "$GIT_DIR/hooks/pre-commit-custom.conf"
```

### Conditional Backups

Only backup on specific branches:

```bash
# Add to hook
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$current_branch" != "main" && "$current_branch" != "develop" ]]; then
    export BACKUP_GIT_PRE_COMMIT_DISABLED=true
fi
```

### Integration with Pre-Commit Framework

If using the [pre-commit](https://pre-commit.com/) framework, add:

`.pre-commit-config.yaml`:
```yaml
repos:
  - repo: local
    hooks:
      - id: checkpoint-backup
        name: Checkpoint Backup
        entry: /path/to/integrations/git/hooks/pre-commit
        language: script
        stages: [commit]
```

## See Also

- [Shell Integration](../shell/README.md)
- [Integration Core Library](../lib/integration-core.sh)
- [Main Backup System](../../README.md)
