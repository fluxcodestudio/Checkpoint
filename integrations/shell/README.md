# Shell Integration

Universal shell integration for Checkpoint Project Backups. Works with bash, zsh, and compatible shells.

## Features

- **Prompt Integration**: Show backup status in your shell prompt
- **Auto-Trigger**: Automatically backup when you `cd` into git repositories
- **Quick Aliases**: Short commands (`bs`, `bn`, etc.)
- **Unified Command**: Single `backup` command with subcommands
- **Debouncing**: Intelligent throttling prevents backup spam
- **Configurable**: Customize behavior via environment variables

## Quick Start

### Install

```bash
/path/to/CLAUDE_CODE_PROJECT_BACKUP/integrations/shell/install.sh
```

This will:
1. Detect your shell (bash/zsh)
2. Backup your RC file
3. Add source line to load integration
4. Show configuration options

### Reload

```bash
# Bash
source ~/.bashrc

# Zsh
source ~/.zshrc

# Or restart terminal
```

### Verify

```bash
backup help
bs --compact
```

## What Gets Installed

The installer adds this to your `~/.bashrc` or `~/.zshrc`:

```bash
# Checkpoint Backup System - Shell Integration
source "/path/to/backup-shell-integration.sh"
```

When loaded, you get:

1. **Prompt status**: `✅` or `⚠️` or `❌` in your prompt
2. **Auto-trigger**: Backups on `cd` into git repos
3. **Commands**: `backup` command and quick aliases
4. **Functions**: Helper functions exported to environment

## Commands

### Unified Command

```bash
backup <subcommand> [options]
```

Subcommands:
- `status`, `s` - Show backup status dashboard
- `now`, `n` - Trigger backup now
- `config`, `c` - Manage configuration
- `cleanup`, `cl` - Clean up old backups
- `restore`, `r` - Restore from backup
- `help`, `h` - Show help

Examples:
```bash
backup status
backup s              # Short form
backup now --force
backup cleanup --preview
```

### Quick Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `bs` | `backup-status.sh` | Show status |
| `bn` | `backup-now.sh` | Backup now |
| `bc` | `backup-config.sh` | Manage config |
| `bcl` | `backup-cleanup.sh` | Clean up |
| `br` | `backup-restore.sh` | Restore |

Examples:
```bash
bs --compact          # Quick status
bn --dry-run          # Preview backup
bc show               # Show config
bcl --keep 5          # Keep 5 backups
br --list             # List backups
```

## Prompt Integration

### Default (Emoji)

```
✅ user@host ~/project $
```

Shows just the status emoji:
- ✅ All backups current
- ⚠️ Backups need attention
- ❌ Backup errors

### Compact Format

```bash
export BACKUP_PROMPT_FORMAT=compact
```

```
✅ 2h user@host ~/project $
```

Shows emoji + time since last backup.

### Verbose Format

```bash
export BACKUP_PROMPT_FORMAT=verbose
```

```
✅ All backups current (2 projects, 2h ago) user@host ~/project $
```

Shows full compact status.

### Disable Prompt

```bash
export BACKUP_SHOW_PROMPT=false
```

## Auto-Trigger

### How It Works

When you `cd` into a git repository, the shell integration automatically:
1. Detects you're in a git repo
2. Checks debounce interval (5 minutes default)
3. Triggers backup in background if enough time passed
4. Runs silently (no output unless error)

### Example

```bash
$ cd ~/my-project
# Auto-backup happens silently in background

$ bs --compact
✅ All backups current (1 project, 30s ago)
```

### Disable Auto-Trigger

```bash
export BACKUP_AUTO_TRIGGER=false
source ~/.bashrc
```

### Adjust Debounce Interval

```bash
# 10 minutes
export BACKUP_TRIGGER_INTERVAL=600

# 30 seconds (for testing)
export BACKUP_TRIGGER_INTERVAL=30
```

## Configuration

Set these **before** sourcing `backup-shell-integration.sh` in your RC file:

```bash
# ~/.bashrc or ~/.zshrc

# Auto-trigger on cd (default: true)
export BACKUP_AUTO_TRIGGER=true

# Show status in prompt (default: true)
export BACKUP_SHOW_PROMPT=true

# Debounce interval in seconds (default: 300 = 5 min)
export BACKUP_TRIGGER_INTERVAL=300

# Prompt format: emoji|compact|verbose (default: emoji)
export BACKUP_PROMPT_FORMAT=emoji

# Enable quick aliases (default: true)
export BACKUP_ALIASES_ENABLED=true

# Load integration
source "/path/to/backup-shell-integration.sh"
```

### Example Configurations

**Minimal (status only)**:
```bash
export BACKUP_AUTO_TRIGGER=false
export BACKUP_PROMPT_FORMAT=emoji
export BACKUP_ALIASES_ENABLED=false
source "/path/to/backup-shell-integration.sh"
```

**Aggressive (frequent backups)**:
```bash
export BACKUP_AUTO_TRIGGER=true
export BACKUP_TRIGGER_INTERVAL=60        # 1 minute
export BACKUP_PROMPT_FORMAT=compact
source "/path/to/backup-shell-integration.sh"
```

**Quiet (manual only)**:
```bash
export BACKUP_AUTO_TRIGGER=false
export BACKUP_SHOW_PROMPT=false
export BACKUP_ALIASES_ENABLED=true
source "/path/to/backup-shell-integration.sh"
```

## Shell Compatibility

### Bash

Tested with:
- Bash 3.2+ (macOS default)
- Bash 4.x+
- Bash 5.x+

Uses `PROMPT_COMMAND` for auto-trigger and `PS1` for prompt.

### Zsh

Tested with:
- Zsh 5.x+

Uses `chpwd` hook for auto-trigger and `PROMPT` for prompt status.

### Other Shells

The integration uses POSIX-compatible patterns where possible. Other shells may work but are untested.

## Advanced Usage

### Git Pre-Commit Integration

```bash
# ~/.bashrc or ~/.zshrc

# Auto-backup before git commits
alias git-safe-commit='backup_git_pre_commit && git commit'
```

Function `backup_git_pre_commit` is provided by the integration.

Usage:
```bash
git add .
git-safe-commit -m "My changes"
# Creates backup before committing
```

### Custom Prompt Position

**Bash** - Move to right side:
```bash
# Don't let integration modify PS1 automatically
BACKUP_SHOW_PROMPT=false

# Manually add to PS1 where you want
PS1="[\u@\h \W]\$(backup_prompt_status)$ "
```

**Zsh** - Use RPROMPT:
```bash
# Disable auto-prompt
BACKUP_SHOW_PROMPT=false

# Add to right prompt
RPROMPT='$(backup_prompt_status)'
```

### Conditional Loading

Load integration only for specific directories:

```bash
# ~/.bashrc or ~/.zshrc

# Only load for ~/projects/*
if [[ "$PWD" == ~/projects/* ]]; then
    source "/path/to/backup-shell-integration.sh"
fi
```

### Per-Session Toggle

```bash
# Disable for this session
export BACKUP_AUTO_TRIGGER=false
export BACKUP_SHOW_PROMPT=false

# Re-enable
export BACKUP_AUTO_TRIGGER=true
export BACKUP_SHOW_PROMPT=true
```

## Troubleshooting

### Prompt not showing

1. Check if enabled:
   ```bash
   echo $BACKUP_SHOW_PROMPT
   # Should output: true
   ```

2. Test function directly:
   ```bash
   backup_prompt_status
   # Should output emoji or status
   ```

3. Verify prompt variable:
   ```bash
   # Bash
   echo $PS1 | grep backup_prompt_status

   # Zsh
   echo $PROMPT | grep backup_prompt_status
   ```

### Auto-trigger not working

1. Check if enabled:
   ```bash
   echo $BACKUP_AUTO_TRIGGER
   # Should output: true
   ```

2. Verify git repo:
   ```bash
   git rev-parse --is-inside-work-tree
   # Should output: true
   ```

3. Check debounce:
   ```bash
   # Force trigger
   backup now --force
   ```

4. Test hook:
   ```bash
   # Bash
   echo $PROMPT_COMMAND | grep backup_auto_trigger

   # Zsh
   echo $chpwd_functions | grep backup_auto_trigger
   ```

### Aliases not available

1. Check if enabled:
   ```bash
   echo $BACKUP_ALIASES_ENABLED
   # Should output: true
   ```

2. List aliases:
   ```bash
   alias | grep backup
   ```

3. Reload shell:
   ```bash
   source ~/.bashrc  # or ~/.zshrc
   ```

### Integration loads but commands fail

Check integration-core.sh exists:
```bash
ls -la /path/to/integrations/lib/integration-core.sh
```

Check backup bin directory:
```bash
ls -la /path/to/bin/backup-*.sh
```

### Duplicate prompt status

If you see `✅ ✅ user@host`, the integration loaded twice.

Check RC file for duplicate source lines:
```bash
grep -n "backup-shell-integration" ~/.bashrc  # or ~/.zshrc
```

Remove duplicates and reload.

## Uninstallation

1. Remove source line from RC file:
   ```bash
   # Edit ~/.bashrc or ~/.zshrc
   # Delete or comment out:
   # source "/path/to/backup-shell-integration.sh"
   ```

2. Reload shell:
   ```bash
   source ~/.bashrc  # or ~/.zshrc
   ```

3. Verify:
   ```bash
   backup status
   # Should output: command not found
   ```

## Integration with Other Tools

### Starship Prompt

Add custom module in `~/.config/starship.toml`:

```toml
[custom.backup]
command = "backup_prompt_status"
when = "command -v backup_prompt_status"
shell = ["bash", "-c"]
```

### Oh My Zsh

Works with any theme. Add before theme loads:

```bash
# ~/.zshrc
export BACKUP_AUTO_TRIGGER=true
source "/path/to/backup-shell-integration.sh"

# Then load theme
ZSH_THEME="robbyrussell"
source $ZSH/oh-my-zsh.sh
```

### Tmux

Display in tmux status bar (see [Tmux Integration](../tmux/README.md)):

```bash
# ~/.tmux.conf
set -g status-right "#(backup_prompt_status) %H:%M"
```

## Performance

The integration is designed to be fast:

- **Prompt function**: <10ms (caches status)
- **Auto-trigger**: Background process (non-blocking)
- **Debouncing**: Prevents excessive operations
- **Lock detection**: Skips if backup already running

## Security

The integration:
- Never modifies files outside state directory
- Uses read-only operations for status
- Respects all backup system permissions
- Runs in user context (no sudo)

## See Also

- [Integration Core Library](../lib/integration-core.sh)
- [Direnv Integration](../direnv/README.md)
- [Git Hooks Integration](../git/README.md)
- [Main Backup System](../../README.md)
