# Tmux Integration

Status bar and keybinding integration for ClaudeCode Project Backups in tmux.

## Features

- **Status Bar**: Show backup status in tmux status line
- **Auto-Refresh**: Updates every 60 seconds (configurable)
- **Multiple Formats**: Emoji, compact, verbose, time-only
- **Keybindings**: Quick access to backup commands via prefix keys
- **Popup Windows**: Commands run in tmux popups (tmux 3.2+)
- **Non-Intrusive**: Works alongside existing tmux config

## Requirements

- tmux 2.0+ (required)
- tmux 3.2+ (recommended for popup support)

Check version:
```bash
tmux -V
```

## Installation

### Quick Install

```bash
/path/to/CLAUDE_CODE_PROJECT_BACKUP/integrations/tmux/install-tmux.sh
```

The installer will:
1. Check if tmux is installed
2. Backup your `~/.tmux.conf`
3. Add backup integration configuration
4. Reload tmux if running

### Manual Install

1. Copy configuration to `~/.tmux.conf`:
   ```bash
   cat /path/to/integrations/tmux/backup-tmux.conf >> ~/.tmux.conf
   ```

2. Update the status script path in `~/.tmux.conf`:
   ```bash
   set-option -g @backup-status-script "/your/path/to/integrations/tmux/backup-tmux-status.sh"
   ```

3. Reload tmux:
   ```bash
   tmux source-file ~/.tmux.conf
   ```

## Status Bar

### Formats

Set via `@backup-status-format` in `~/.tmux.conf`:

**emoji** (default):
```
✅ | 15:30 24-Dec-24
```
Just the status emoji.

**compact**:
```
✅ 2h | 15:30 24-Dec-24
```
Emoji + time since backup.

**verbose**:
```
✅ All backups current (2 projects, 2h ago) | 15:30 24-Dec-24
```
Full status line.

**time**:
```
2h | 15:30 24-Dec-24
```
Just time since backup.

**icon-only**:
```
✅| 15:30 24-Dec-24
```
Emoji with no space.

### Configuration

Edit `~/.tmux.conf`:

```bash
# Change format
set-option -g @backup-status-format "compact"

# Change refresh interval (default: 60 seconds)
set-option -g status-interval 30

# Position on left instead of right
set-option -g status-left "#(#{@backup-status-script} #{@backup-status-format}) [#S] "
```

Then reload:
```bash
tmux source-file ~/.tmux.conf
```

## Keybindings

Default bindings (prefix is usually `Ctrl-b`):

| Keys | Command | Description |
|------|---------|-------------|
| `prefix` `s` | backup status | Show full status dashboard |
| `prefix` `n` | backup now | Trigger backup immediately |
| `prefix` `c` | backup config | Show configuration |
| `prefix` `l` | backup cleanup | Preview cleanup |
| `prefix` `r` | backup restore | List available backups |

### Usage Example

```
1. Press Ctrl-b (prefix)
2. Release Ctrl-b
3. Press s (status)
4. Popup appears with backup status
5. Press any key to close
```

### Custom Keybindings

Edit `~/.tmux.conf` to change keys:

```bash
# Use different keys
bind-key -T prefix b run-shell "tmux display-popup -E '#{@backup-status-script}/../../../bin/backup-now.sh --force'"

# Add to custom prefix
bind-key B switch-client -T backup-menu
bind-key -T backup-menu s run-shell "tmux display-popup -E -w 80% -h 80% '#{@backup-status-script}/../../../bin/backup-status.sh'"
```

## Popups

Tmux 3.2+ supports popup windows. If you have an older version, commands will run in a split pane instead.

### Popup Options

Customize popup size in `~/.tmux.conf`:

```bash
# Wider popup
bind-key -T prefix s run-shell "tmux display-popup -E -w 90% -h 80% ..."

# Full screen popup
bind-key -T prefix s run-shell "tmux display-popup -E -w 100% -h 100% ..."

# Smaller popup
bind-key -T prefix s run-shell "tmux display-popup -E -w 60% -h 60% ..."
```

## Advanced Features

### Auto-Trigger on Pane Change

Automatically backup when switching panes in git repos:

Add to `~/.tmux.conf`:
```bash
set-hook -g after-select-pane 'run-shell "cd #{pane_current_path} && git rev-parse --git-dir &>/dev/null && #{@backup-status-script}/../../../bin/backup-now.sh --quiet &"'
```

### Status Bar Styling

Customize colors and layout:

```bash
# Status bar colors
set-option -g status-bg colour235
set-option -g status-fg colour136

# Status bar lengths
set-option -g status-left-length 50
set-option -g status-right-length 100

# Custom layout
set-option -g status-right "#(#{@backup-status-script} compact) | #H | %H:%M %d-%b"
set-option -g status-left "[#S] #(#{@backup-status-script} emoji) "
```

### Conditional Display

Show status only in git repos:

```bash
# In ~/.tmux.conf
set-option -g status-right "#(cd #{pane_current_path} && git rev-parse --git-dir &>/dev/null && #{@backup-status-script} emoji || echo '') | %H:%M"
```

### Multiple Sessions

Different status formats for different sessions:

```bash
# Session-specific config
if-shell '[ "#{session_name}" = "dev" ]' \
    'set-option -g @backup-status-format "verbose"' \
    'set-option -g @backup-status-format "emoji"'
```

## Troubleshooting

### Status not showing

1. Check if status bar is visible:
   ```bash
   tmux show-option -g status
   # Should be "on"
   ```

2. Check status-right:
   ```bash
   tmux show-option -g status-right
   # Should include @backup-status-script
   ```

3. Test script directly:
   ```bash
   /path/to/backup-tmux-status.sh emoji
   # Should output emoji
   ```

4. Check script permissions:
   ```bash
   ls -la /path/to/backup-tmux-status.sh
   # Should be executable (-rwxr-xr-x)
   ```

### Keybindings not working

1. List current bindings:
   ```bash
   tmux list-keys -T prefix | grep backup
   ```

2. Check if your prefix is different:
   ```bash
   tmux show-option -g prefix
   # Usually "C-b" (Ctrl-b)
   ```

3. Try running command directly:
   ```bash
   # In tmux
   :display-popup -E "backup status"
   ```

### Popup not appearing

1. Check tmux version:
   ```bash
   tmux -V
   # Need 3.2+ for popup support
   ```

2. Upgrade tmux:
   ```bash
   # macOS
   brew upgrade tmux

   # Ubuntu
   apt update && apt install tmux
   ```

3. Or use split-window instead:
   ```bash
   bind-key -T prefix s split-window -h "backup status; read -n 1"
   ```

### Status shows ❌

1. Check if backup system is accessible:
   ```bash
   backup status
   # Should work
   ```

2. Check integration-core.sh exists:
   ```bash
   ls -la /path/to/integrations/lib/integration-core.sh
   ```

3. Run status script with debug:
   ```bash
   bash -x /path/to/backup-tmux-status.sh emoji
   ```

## Performance

The status script is optimized:
- Runs in <100ms
- Caches results when possible
- Uses non-blocking operations
- Minimal resource usage

Refresh interval of 60s is recommended for good balance.

## Integration with Other Tools

### Tmux Plugin Manager (TPM)

If using TPM, wrap in plugin:

`~/.tmux/plugins/backup/backup.tmux`:
```bash
#!/bin/bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmux source-file "$CURRENT_DIR/backup-tmux.conf"
```

Then in `~/.tmux.conf`:
```bash
set -g @plugin 'custom/backup'
run '~/.tmux/plugins/tpm/tpm'
```

### Oh My Tmux

Works with Oh My Tmux themes. Add after theme loading:

```bash
# ~/.tmux.conf.local
source-file /path/to/backup-tmux.conf
```

### iTerm2 + tmux

Status shows in both iTerm2 and tmux status bars.

## Uninstallation

1. Edit `~/.tmux.conf`:
   ```bash
   nano ~/.tmux.conf
   # Delete the ClaudeCode Backup section
   ```

2. Reload:
   ```bash
   tmux source-file ~/.tmux.conf
   ```

3. Or restore backup:
   ```bash
   ls -la ~/.tmux.conf.backup.*
   cp ~/.tmux.conf.backup.YYYYMMDD_HHMMSS ~/.tmux.conf
   tmux source-file ~/.tmux.conf
   ```

## Examples

### Minimal Configuration

```bash
# Just status, no keybindings
set-option -g @backup-status-script "/path/to/backup-tmux-status.sh"
set-option -g @backup-status-format "emoji"
set-option -g status-right "#(#{@backup-status-script} #{@backup-status-format}) | %H:%M"
```

### Full-Featured

```bash
# Verbose status + all keybindings + auto-trigger
set-option -g @backup-status-script "/path/to/backup-tmux-status.sh"
set-option -g @backup-status-format "verbose"
set-option -g status-interval 30
set-option -g status-right "#(#{@backup-status-script} #{@backup-status-format}) | %H:%M"

# All keybindings (as shown in backup-tmux.conf)
bind-key -T prefix s run-shell "..."
bind-key -T prefix n run-shell "..."
# ... etc

# Auto-trigger on pane change
set-hook -g after-select-pane '...'
```

## See Also

- [Shell Integration](../shell/README.md)
- [Git Hooks Integration](../git/README.md)
- [Direnv Integration](../direnv/README.md)
- [Main Backup System](../../README.md)
- [Tmux Manual](https://man.openbsd.org/tmux.1)
