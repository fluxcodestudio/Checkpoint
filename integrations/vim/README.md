# Vim/Neovim Plugin

Automated backup integration for Vim and Neovim.

## Features

- **Auto-Backup on Save**: Automatically backs up after file saves (debounced)
- **Commands**: `:BackupStatus`, `:BackupNow`, `:BackupRestore`, etc.
- **Key Mappings**: Quick access via `<leader>bs`, `<leader>bn`, etc.
- **Status Line**: Real-time backup status in status bar
- **Notifications**: Success/failure messages (Neovim floating windows)
- **Async Operations**: Non-blocking backups (Vim 8+/Neovim)
- **Compatible**: Works with Vim 8.0+ and Neovim 0.5+

## Requirements

- Vim 8.0+ or Neovim 0.5+
- Checkpoint core system installed
- Git repository (for auto-trigger)

## Installation

### Using vim-plug

Add to your `~/.vimrc` or `~/.config/nvim/init.vim`:

```vim
Plug '/absolute/path/to/ClaudeCode-Project-Backups/integrations/vim'
```

Then run:
```vim
:PlugInstall
```

### Using Vundle

```vim
Plugin '/absolute/path/to/ClaudeCode-Project-Backups/integrations/vim'
```

Then run:
```vim
:PluginInstall
```

### Using Pathogen

```bash
cd ~/.vim/bundle
ln -s /absolute/path/to/ClaudeCode-Project-Backups/integrations/vim backup
```

### Using Native Package Manager (Vim 8+, Neovim)

```bash
mkdir -p ~/.vim/pack/plugins/start
cp -r /path/to/integrations/vim ~/.vim/pack/plugins/start/backup
```

Or for Neovim:
```bash
mkdir -p ~/.local/share/nvim/site/pack/plugins/start
cp -r /path/to/integrations/vim ~/.local/share/nvim/site/pack/plugins/start/backup
```

### Configuration

Add to your `~/.vimrc` or `~/.config/nvim/init.vim`:

```vim
" Required: Set path to backup bin directory
let g:backup_bin_path = '/path/to/ClaudeCode-Project-Backups/bin'

" Or use environment variable
let g:backup_bin_path = $CLAUDECODE_BACKUP_ROOT . '/bin'
```

## Quick Start

After installation, try these commands:

```vim
:BackupStatus      " Show backup status
:BackupNow         " Trigger backup now
```

Or use key mappings:
```
<leader>bs         " Show status (leader is \ by default)
<leader>bn         " Backup now
```

## Commands

| Command | Description |
|---------|-------------|
| `:BackupStatus` | Show backup status dashboard |
| `:BackupNow` | Trigger backup now (debounced) |
| `:BackupNowForce` | Force backup (bypass debounce) |
| `:BackupRestore` | Launch restore wizard |
| `:BackupCleanup` | Show cleanup preview |
| `:BackupConfig` | Open backup config file |

## Key Mappings

Default mappings (using `<leader>` prefix):

| Keys | Command | Description |
|------|---------|-------------|
| `<leader>bs` | `:BackupStatus` | Show status |
| `<leader>bn` | `:BackupNow` | Backup now |
| `<leader>bf` | `:BackupNowForce` | Force backup |
| `<leader>br` | `:BackupRestore` | Restore wizard |
| `<leader>bc` | `:BackupCleanup` | Cleanup preview |
| `<leader>bC` | `:BackupConfig` | Edit config |

**Note**: `<leader>` is `\` by default in Vim. You can change it:
```vim
let mapleader = ","    " Use comma as leader
```

## Configuration Options

### Enable/Disable Auto-Trigger

```vim
" Enable auto-backup on save (default: 1)
let g:backup_auto_trigger = 1

" Disable auto-backup (manual only)
let g:backup_auto_trigger = 0
```

### Auto-Trigger Delay

```vim
" Delay before backup after save (milliseconds, default: 1000)
let g:backup_trigger_delay = 1000

" Faster trigger (500ms)
let g:backup_trigger_delay = 500

" Slower trigger (2 seconds)
let g:backup_trigger_delay = 2000
```

### Key Mapping Prefix

```vim
" Use different prefix (default: <leader>)
let g:backup_key_prefix = '<localleader>'

" Now use: <localleader>bs, <localleader>bn, etc.
```

### Disable Key Mappings

```vim
" Disable all default mappings
let g:backup_no_mappings = 1

" Create your own mappings
nnoremap <F5> :BackupStatus<CR>
nnoremap <F6> :BackupNow<CR>
```

### Notifications

```vim
" Enable notifications (default: 1)
let g:backup_notifications = 1

" Disable notifications (quiet mode)
let g:backup_notifications = 0
```

### Status Line Format

```vim
" Format options: 'emoji', 'compact', 'verbose'
let g:backup_statusline_format = 'compact'   " ✅ 2h (default)
let g:backup_statusline_format = 'emoji'     " ✅
let g:backup_statusline_format = 'verbose'   " ✅ All backups current...
```

## Status Line Integration

The plugin automatically adds backup status to your status line.

### Manual Status Line Configuration

```vim
" Add backup status to statusline
set statusline+=%{BackupStatusLine()}
```

### Integration with vim-airline

```vim
let g:airline_section_x = airline#section#create_right(['%{BackupStatusLine()}'])
```

### Integration with lightline.vim

```vim
let g:lightline = {
      \ 'component_function': {
      \   'backup': 'BackupStatusLine'
      \ },
      \ 'active': {
      \   'right': [ [ 'backup' ], [ 'lineinfo' ], [ 'filetype' ] ]
      \ }
      \ }
```

### Integration with lualine (Neovim)

```lua
require('lualine').setup {
  sections = {
    lualine_x = {
      function()
        return vim.fn.BackupStatusLine()
      end
    }
  }
}
```

## Auto-Trigger Behavior

- Triggers after saving any file (`:w`, `:wq`, etc.)
- Only in git repositories
- Debounced (won't spam on rapid saves)
- Runs asynchronously (non-blocking)
- Configurable delay (default: 1 second)

**Example**:
```
1. Edit file
2. :w        → Backup triggers after 1 second
3. :w        → Too soon, skipped
4. Wait 1s
5. :w        → Backup triggers
```

## Examples

### Minimal Configuration

```vim
" ~/.vimrc
let g:backup_bin_path = '/path/to/backup/bin'
```

### Recommended Configuration

```vim
" ~/.vimrc
let g:backup_bin_path = $CLAUDECODE_BACKUP_ROOT . '/bin'
let g:backup_auto_trigger = 1
let g:backup_trigger_delay = 1000
let g:backup_notifications = 1
let g:backup_statusline_format = 'compact'
```

### Aggressive Auto-Backup

```vim
let g:backup_auto_trigger = 1
let g:backup_trigger_delay = 500     " Faster trigger
let g:backup_notifications = 0       " Silent
```

### Manual Only

```vim
let g:backup_auto_trigger = 0        " Disable auto-trigger
let g:backup_notifications = 1       " Keep notifications

" Use key mappings for manual backups
" <leader>bn to backup
```

### Custom Key Mappings

```vim
" Disable defaults
let g:backup_no_mappings = 1

" Create custom mappings
nnoremap <F5> :BackupStatus<CR>
nnoremap <F6> :BackupNow<CR>
nnoremap <F7> :BackupRestore<CR>
```

## Troubleshooting

### Commands not working

1. Check if backup bin directory exists:
   ```vim
   :echo g:backup_bin_path
   ```

2. Verify scripts are executable:
   ```bash
   ls -la /path/to/backup/bin/backup-*.sh
   ```

3. Test script directly:
   ```bash
   /path/to/backup/bin/backup-status.sh
   ```

### Auto-trigger not firing

1. Check if enabled:
   ```vim
   :echo g:backup_auto_trigger
   ```

2. Check if in git repository:
   ```vim
   :!git rev-parse --is-inside-work-tree
   ```

3. Check autocmd:
   ```vim
   :autocmd backup_auto_trigger
   ```

### Status line not showing

1. Check statusline setting:
   ```vim
   :set statusline?
   ```

2. Manually add:
   ```vim
   :set statusline+=%{BackupStatusLine()}
   ```

3. Test function:
   ```vim
   :echo BackupStatusLine()
   ```

### Error: "Backup bin directory not found"

Set `g:backup_bin_path` explicitly:
```vim
let g:backup_bin_path = '/absolute/path/to/backup/bin'
```

Or set environment variable before starting Vim:
```bash
export CLAUDECODE_BACKUP_ROOT="/path/to/backup/system"
vim
```

### Neovim floating windows not showing

Check if Neovim supports floating windows:
```vim
:echo has('nvim') && exists('*nvim_open_win')
```

If not supported, plugin falls back to `:echo` messages.

## Advanced Usage

### Conditional Auto-Trigger

Only auto-trigger for specific file types:

```vim
augroup backup_filetype
  autocmd!
  autocmd FileType python,javascript let b:backup_auto_trigger = 1
  autocmd FileType text,markdown let b:backup_auto_trigger = 0
augroup END
```

### Integration with Other Plugins

**Auto-save plugins**: Disable backup auto-trigger to avoid conflicts:
```vim
let g:backup_auto_trigger = 0
```

**Git plugins (fugitive, etc.)**: Works seamlessly, git hooks and Vim plugin complement each other.

### Remote Editing (via SSH)

Plugin works over SSH if backup system is installed on remote machine.

## Help Documentation

Access full help:
```vim
:help backup
:help backup-commands
:help backup-configuration
```

## Uninstallation

1. Remove plugin line from `~/.vimrc`
2. Remove plugin directory
3. Restart Vim

For vim-plug:
```vim
" Comment out or remove
" Plug '/path/to/integrations/vim'
```

Then run:
```vim
:PlugClean
```

## Compatibility

- **Vim**: 8.0+ (tested on 8.0, 8.1, 8.2, 9.0)
- **Neovim**: 0.5+ (tested on 0.5, 0.6, 0.7, 0.8, 0.9)
- **Platforms**: macOS, Linux
- **Plugin Managers**: vim-plug, Vundle, Pathogen, native

## See Also

- [Main Backup System](../../README.md)
- [Integrations Guide](../../docs/INTEGRATIONS.md)
- [Shell Integration](../shell/README.md)
- [Git Hooks](../git/README.md)

---

**Version**: 1.2.0
**License**: MIT
**Author**: Jon Rezin
