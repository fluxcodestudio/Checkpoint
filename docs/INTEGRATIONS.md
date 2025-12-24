# Universal Integrations Guide

**Checkpoint** includes universal integrations that bring backup functionality to any CLI, editor, or development environment.

**Philosophy**: A code guardian that works everywhere.

---

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Available Integrations](#available-integrations)
  - [Shell Integration](#shell-integration)
  - [Git Hooks](#git-hooks)
  - [Direnv](#direnv)
  - [Tmux](#tmux)
  - [VS Code](#vs-code)
  - [Vim/Neovim](#vimneovim)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Examples](#examples)
- [FAQ](#faq)

---

## Overview

### What Are Integrations?

Integrations are platform adapters that connect the core backup system to your development environment:

```
Core Backup System (bin/*.sh)
        ↓
Integration Layer (integrations/lib/)
        ↓
Platform Adapters (shell, git, tmux, vscode, vim)
        ↓
Your Environment (terminal, editor, etc.)
```

### Key Features

- **Auto-Trigger**: Automatic backups on file save, commit, or directory change
- **Status Visibility**: Real-time backup status in prompts, status bars, indicators
- **Quick Commands**: Fast access via aliases, keybindings, command palettes
- **Non-Invasive**: Optional, modular, easy to disable
- **Cross-Platform**: Works on macOS and Linux

### Integration Matrix

| Integration | Auto-Trigger | Visual Status | Commands | Keybindings |
|-------------|--------------|---------------|----------|-------------|
| **Shell** | ✅ On `cd` | ✅ Prompt | ✅ Aliases | - |
| **Git Hooks** | ✅ On commit/push | ✅ Messages | - | - |
| **Direnv** | ✅ On enter | - | ✅ PATH | - |
| **Tmux** | ⏱️ 60s refresh | ✅ Status bar | ✅ popup | ✅ prefix+key |
| **VS Code** | - | - | ✅ Tasks | ✅ Ctrl+Shift+B |
| **Vim** | ✅ On save | ✅ Status line | ✅ Commands | ✅ `<leader>` |

---

## Quick Start

### Install All Recommended Integrations

```bash
# Auto-detect and install (coming soon)
./bin/install-integrations.sh
```

### Install Individual Integrations

**Shell** (works everywhere):
```bash
./integrations/shell/install.sh
source ~/.bashrc  # or ~/.zshrc
```

**Git Hooks** (any git repo):
```bash
cd /your/project
/path/to/integrations/git/install-git-hooks.sh
```

**Tmux** (terminal multiplexer users):
```bash
./integrations/tmux/install-tmux.sh
tmux source-file ~/.tmux.conf
```

**VS Code** (VS Code/Cursor/Windsurf):
```bash
cd /your/project
/path/to/integrations/vscode/install-vscode.sh
```

**Vim** (Vim/Neovim users):
```vim
" Add to ~/.vimrc or ~/.config/nvim/init.vim
Plug '/path/to/integrations/vim'
```

---

## Available Integrations

### Shell Integration

**Works with**: bash 3.2+, zsh 5.0+

**Installation**:
```bash
./integrations/shell/install.sh
```

**Features**:
- **Prompt Status**: Shows `✅/⚠️/❌` in your shell prompt
- **Auto-Trigger**: Backs up when you `cd` into git repos (debounced)
- **Quick Aliases**: `bs`, `bn`, `bc`, `bcl`, `br`
- **Unified Command**: `backup {status|now|config|cleanup|restore}`

**Configuration** (in ~/.bashrc or ~/.zshrc, before sourcing):
```bash
export BACKUP_AUTO_TRIGGER=true           # Auto-backup on cd (default: true)
export BACKUP_SHOW_PROMPT=true            # Show in prompt (default: true)
export BACKUP_TRIGGER_INTERVAL=300        # Debounce seconds (default: 300)
export BACKUP_PROMPT_FORMAT=emoji         # emoji|compact|verbose
export BACKUP_ALIASES_ENABLED=true        # Enable aliases (default: true)

source "/path/to/backup-shell-integration.sh"
```

**Examples**:
```bash
# Prompt shows status
✅ user@host ~/project $

# Quick commands
bs --compact              # Quick status
bn --force                # Force backup now
backup status             # Unified command

# Auto-triggers
cd ~/my-project           # Automatically backs up (if > 5min since last)
```

**Customization**:
```bash
# Compact prompt format
export BACKUP_PROMPT_FORMAT=compact
✅ 2h user@host ~/project $

# Verbose prompt format
export BACKUP_PROMPT_FORMAT=verbose
✅ All backups current (2 projects, 2h ago) user@host ~/project $

# Disable auto-trigger, keep prompt
export BACKUP_AUTO_TRIGGER=false
export BACKUP_SHOW_PROMPT=true
```

**See**: [Shell Integration README](../integrations/shell/README.md)

---

### Git Hooks

**Works with**: Any git repository (git 1.8+)

**Installation**:
```bash
cd /your/git/repo
/path/to/integrations/git/install-git-hooks.sh
```

**Features**:
- **pre-commit**: Auto-backup before each commit
- **post-commit**: Show backup status after commit
- **pre-push**: Verify backups current before push

**Configuration** (environment variables):
```bash
# Disable specific hooks
export BACKUP_GIT_PRE_COMMIT_DISABLED=false
export BACKUP_GIT_POST_COMMIT_DISABLED=false
export BACKUP_GIT_PRE_PUSH_DISABLED=false

# Quiet mode
export BACKUP_GIT_QUIET=false

# Block commits/pushes on failure
export BACKUP_GIT_BLOCK_ON_FAILURE=false
export BACKUP_GIT_BLOCK_PUSH_ON_FAILURE=false

# Pre-push timing (seconds)
export BACKUP_GIT_MAX_BACKUP_AGE=3600
```

**Examples**:
```bash
# Pre-commit
$ git commit -m "Update feature"
🔄 Creating backup before commit...
✅ Backup created successfully
[main abc1234] Update feature
 1 file changed, 10 insertions(+)

📊 Backup Status:
   ✅ All backups current (2 projects, 5m ago)

# Pre-push (backup too old)
$ git push origin main
⚠️  Warning: Last backup was 2h ago
   Creating fresh backup before push...
   ✅ Backup created successfully
```

**Bypass** (when needed):
```bash
git commit --no-verify -m "Skip backup hook"
```

**See**: [Git Hooks README](../integrations/git/README.md)

---

### Direnv

**Works with**: Projects using [direnv](https://direnv.net/)

**Installation**:
```bash
cd /your/project
/path/to/integrations/direnv/install-direnv.sh
direnv allow
```

**Features**:
- **Auto-load**: Backup commands available when you `cd` into project
- **PATH Integration**: Adds `bin/` to PATH automatically
- **Per-Project Config**: Each project can have different settings
- **Team Shareable**: Commit `.envrc` for consistent team setup

**Configuration** (.envrc):
```bash
# Path to backup system (required)
export CLAUDECODE_BACKUP_ROOT="/path/to/backup/system"
export PATH="$CLAUDECODE_BACKUP_ROOT/bin:$PATH"

# Optional: Auto-trigger
export BACKUP_AUTO_TRIGGER=true
export BACKUP_TRIGGER_INTERVAL=300

# Optional: Prompt
export BACKUP_SHOW_PROMPT=true
export BACKUP_PROMPT_FORMAT=emoji

# Optional: Load shell integration
# source "$CLAUDECODE_BACKUP_ROOT/integrations/shell/backup-shell-integration.sh"
```

**Examples**:
```bash
$ cd /my/project
direnv: loading /my/project/.envrc
✅ Checkpoint Backup System loaded for my-project
   Commands: backup status | backup now | backup help

$ backup status
[status dashboard appears]

$ cd ..
direnv: unloading
[commands no longer available]
```

**See**: [Direnv README](../integrations/direnv/README.md)

---

### Tmux

**Works with**: tmux 2.0+ (popup support in 3.2+)

**Installation**:
```bash
./integrations/tmux/install-tmux.sh
tmux source-file ~/.tmux.conf
```

**Features**:
- **Status Bar**: Live backup status in tmux status line
- **Auto-Refresh**: Updates every 60 seconds (configurable)
- **Keybindings**: Quick access via `prefix` + key
- **Popup Windows**: Commands run in popups (tmux 3.2+)

**Configuration** (~/.tmux.conf):
```bash
# Status format
set-option -g @backup-status-format "emoji"  # emoji|compact|verbose

# Refresh interval
set-option -g status-interval 60

# Status position
set-option -g status-right "#(#{@backup-status-script} #{@backup-status-format}) | %H:%M"
```

**Keybindings** (default):
- `prefix` `s` - Show backup status
- `prefix` `n` - Backup now
- `prefix` `c` - Show config
- `prefix` `l` - Cleanup preview
- `prefix` `r` - List backups

**Examples**:
```bash
# Status bar shows
✅ | 15:30 24-Dec-24

# Press Ctrl-b then s
[Popup appears with full status]

# Compact format
✅ 2h | 15:30 24-Dec-24

# Verbose format
✅ All backups current (2 projects, 2h ago) | 15:30 24-Dec-24
```

**See**: [Tmux README](../integrations/tmux/README.md)

---

### VS Code

**Works with**: VS Code, Cursor, Windsurf, Codium

**Installation**:
```bash
cd /your/project
/path/to/integrations/vscode/install-vscode.sh
```

**Features**:
- **Tasks**: Run backup commands from Command Palette
- **Keybindings**: Quick keyboard shortcuts
- **Terminal Integration**: Commands run in integrated terminal
- **Per-Project**: Each project can have custom tasks

**Setup**:
1. Set environment variable (in ~/.bashrc or ~/.zshrc):
   ```bash
   export CLAUDECODE_BACKUP_ROOT="/path/to/backup/system"
   ```

2. Reload VS Code or run: `Developer: Reload Window`

**Tasks** (Ctrl+Shift+P → Tasks: Run Task):
- Backup: Show Status
- Backup: Trigger Now
- Backup: Show Config
- Backup: Cleanup (Preview)
- Backup: List Backups

**Keybindings** (add to keybindings.json):
- `Ctrl+Shift+B S` - Show Status
- `Ctrl+Shift+B N` - Backup Now
- `Ctrl+Shift+B C` - Show Config
- `Ctrl+Shift+B L` - Cleanup
- `Ctrl+Shift+B R` - List Backups

**Examples**:
```bash
# Run from Command Palette
Ctrl+Shift+P → "Tasks: Run Task" → "Backup: Show Status"

# Or use keybinding
Ctrl+Shift+B then S

[Terminal opens with status output]
```

**See**: [VS Code README](../integrations/vscode/README.md)

---

### Vim/Neovim

**Works with**: Vim 8.0+, Neovim 0.5+

**Installation**:
```vim
" Using vim-plug
Plug '/path/to/integrations/vim'

" Using Vundle
Plugin '/path/to/integrations/vim'

" Using native package manager (Vim 8+)
" Copy to ~/.vim/pack/plugins/start/backup/
```

**Features**:
- **Commands**: `:BackupStatus`, `:BackupNow`, `:BackupRestore`, etc.
- **Auto-Trigger**: Backup on file save (BufWritePost)
- **Key Mappings**: `<leader>bs`, `<leader>bn`, etc.
- **Status Line**: Integration with status line plugins
- **Floating Windows**: Neovim popup support

**Configuration** (~/.vimrc or init.vim):
```vim
" Enable/disable auto-trigger
let g:backup_auto_trigger = 1

" Auto-trigger delay (milliseconds)
let g:backup_trigger_delay = 1000

" Key prefix (default: <leader>)
let g:backup_key_prefix = '<leader>'

" Show notifications
let g:backup_notifications = 1

" Path to backup bin directory
let g:backup_bin_path = '/path/to/backup/bin'
```

**Commands**:
- `:BackupStatus` - Show status dashboard
- `:BackupNow` - Trigger backup now
- `:BackupNowForce` - Force backup
- `:BackupRestore` - Restore wizard
- `:BackupCleanup` - Cleanup preview
- `:BackupConfig` - Edit config

**Key Mappings** (default):
- `<leader>bs` - `:BackupStatus`
- `<leader>bn` - `:BackupNow`
- `<leader>bf` - `:BackupNowForce`
- `<leader>br` - `:BackupRestore`
- `<leader>bc` - `:BackupCleanup`

**Examples**:
```vim
" Run command
:BackupStatus

" Use key mapping
<leader>bs

" Auto-trigger on save
:w    " Automatically backs up after 1 second

" Status line integration (with airline/lightline)
" Shows: ✅ 2h
```

**See**: [Vim README](../integrations/vim/README.md)

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────┐
│         Core Backup System (Unchanged)              │
│              bin/*.sh scripts                       │
│  ├── backup-status.sh                               │
│  ├── backup-now.sh                                  │
│  ├── backup-config.sh                               │
│  ├── backup-cleanup.sh                              │
│  └── backup-restore.sh                              │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│        Universal Integration Layer                  │
│           integrations/lib/                         │
│  ├── integration-core.sh    - Common functions      │
│  ├── notification.sh         - Cross-platform       │
│  └── status-formatter.sh     - Output formatting    │
└────────────────────┬────────────────────────────────┘
                     │
           ┌─────────┴─────────┐
           ▼                   ▼
┌──────────────────┐   ┌──────────────────┐
│ Platform Adapters│   │ Editor Adapters  │
│ integrations/    │   │ integrations/    │
│  ├── shell/      │   │  ├── vscode/     │
│  ├── git/        │   │  ├── vim/        │
│  ├── direnv/     │   │  └── (future)    │
│  └── tmux/       │   │                  │
└──────────────────┘   └──────────────────┘
```

### Integration Core Library

**Location**: `integrations/lib/integration-core.sh`

**Key Functions**:
- `integration_init()` - Initialize integration
- `integration_trigger_backup()` - Debounced backup trigger
- `integration_get_status()` - Get formatted status
- `integration_get_status_compact()` - One-line status
- `integration_get_status_emoji()` - Just emoji (✅/⚠️/❌)
- `integration_check_lock()` - Check if backup running
- `integration_debounce()` - Generic debounce utility
- `integration_format_time_ago()` - Format elapsed time

**Example Usage**:
```bash
#!/bin/bash
source /path/to/integration-core.sh

integration_init || exit 1

# Get status
status=$(integration_get_status_compact)
echo "$status"  # ✅ All backups current (2 projects, 2h ago)

# Trigger backup (debounced)
integration_trigger_backup --quiet

# Check if backup running
if integration_check_lock; then
    echo "Backup currently running..."
fi
```

### Design Principles

1. **Non-Invasive**: Integrations don't modify core system
2. **Modular**: Each integration is independent
3. **Debounced**: Prevents backup spam with time-based throttling
4. **Fail-Safe**: Errors don't break user workflow
5. **Performant**: Minimal overhead (<100ms per trigger)

---

## Configuration

### Global Configuration

**File**: `.backup-integrations.conf` (optional, in project root or `~`)

```bash
# Enable/disable integrations globally
BACKUP_SHELL_ENABLED=true
BACKUP_GIT_ENABLED=true
BACKUP_TMUX_ENABLED=true

# Global debounce interval (seconds)
BACKUP_DEBOUNCE_INTERVAL=300

# Notification preferences
BACKUP_NOTIFICATIONS_ENABLED=true

# Quiet mode (suppress most output)
BACKUP_QUIET_MODE=false
```

### Per-Integration Configuration

Each integration respects environment variables:

**Shell**:
- `BACKUP_AUTO_TRIGGER`
- `BACKUP_SHOW_PROMPT`
- `BACKUP_TRIGGER_INTERVAL`
- `BACKUP_PROMPT_FORMAT`
- `BACKUP_ALIASES_ENABLED`

**Git Hooks**:
- `BACKUP_GIT_PRE_COMMIT_DISABLED`
- `BACKUP_GIT_POST_COMMIT_DISABLED`
- `BACKUP_GIT_PRE_PUSH_DISABLED`
- `BACKUP_GIT_QUIET`
- `BACKUP_GIT_BLOCK_ON_FAILURE`
- `BACKUP_GIT_MAX_BACKUP_AGE`

**Tmux**:
- `@backup-status-format`
- `status-interval`

### Precedence Order

1. Environment variables (highest priority)
2. `.backup-integrations.conf` in project
3. `.backup-integrations.conf` in `~`
4. Integration defaults (lowest priority)

---

## Troubleshooting

### Common Issues

**Shell integration not loading**:
```bash
# Check if sourced
grep -r "backup-shell-integration" ~/.bashrc ~/.zshrc

# Reload shell
source ~/.bashrc  # or ~/.zshrc

# Check for errors
bash -x ~/.bashrc 2>&1 | grep backup
```

**Git hooks not running**:
```bash
# Check if hooks exist
ls -la .git/hooks/pre-commit

# Check if executable
chmod +x .git/hooks/pre-commit

# Test hook directly
.git/hooks/pre-commit

# Bypass hook (if needed)
git commit --no-verify
```

**Tmux status not showing**:
```bash
# Check tmux version
tmux -V

# Reload config
tmux source-file ~/.tmux.conf

# Check status-right setting
tmux show-option -g status-right

# Test status script directly
/path/to/backup-tmux-status.sh emoji
```

**VS Code tasks not found**:
```bash
# Check .vscode/tasks.json exists
ls -la .vscode/tasks.json

# Check environment variable
echo $CLAUDECODE_BACKUP_ROOT

# Reload VS Code window
# Ctrl+Shift+P → "Developer: Reload Window"
```

### Debug Mode

Enable debug output:
```bash
export BACKUP_DEBUG=true
export BACKUP_VERBOSE=true

# Run integration
source /path/to/backup-shell-integration.sh
```

### Getting Help

1. Check integration-specific README in `integrations/*/README.md`
2. Run tests: `./tests/integration/test-integrations.sh`
3. Check logs: `cat ~/.claudecode-backups/logs/*.log`
4. File issue: https://github.com/[your-repo]/issues

---

## Examples

### Scenario 1: Developer Workstation

**Goal**: Full integration across terminal, git, and editor

```bash
# Install shell integration
./integrations/shell/install.sh
source ~/.bashrc

# Install git hooks (in each project)
cd ~/projects/my-app
/path/to/integrations/git/install-git-hooks.sh

# Install tmux integration
./integrations/tmux/install-tmux.sh

# Install VS Code tasks
cd ~/projects/my-app
/path/to/integrations/vscode/install-vscode.sh

# Result:
# - Prompt shows backup status
# - Auto-backs up on cd, commit, save
# - Quick commands via bs, bn, etc.
# - Tmux status bar shows status
# - VS Code tasks available
```

### Scenario 2: Minimal Setup (Just Shell)

**Goal**: Lightweight, terminal-only

```bash
# Install shell integration only
./integrations/shell/install.sh
source ~/.bashrc

# Configure for minimal output
export BACKUP_AUTO_TRIGGER=false
export BACKUP_SHOW_PROMPT=true
export BACKUP_PROMPT_FORMAT=emoji

# Result:
# - Prompt shows ✅/⚠️/❌
# - Manual backups via: bs, bn
# - No auto-triggering
```

### Scenario 3: Team Project with Direnv

**Goal**: Consistent setup for team

```bash
# In project root
./integrations/direnv/install-direnv.sh

# Edit .envrc for team
cat > .envrc << EOF
export CLAUDECODE_BACKUP_ROOT="/opt/backup-system"
export PATH="\$CLAUDECODE_BACKUP_ROOT/bin:\$PATH"
export BACKUP_AUTO_TRIGGER=true
EOF

# Commit to git
git add .envrc
git commit -m "Add backup system direnv integration"

# Team members just need:
cd /project
direnv allow

# Result:
# - All team members get backup commands
# - Consistent configuration
# - No manual setup required
```

---

## FAQ

**Q: Do integrations slow down my shell/editor?**
A: No. Overhead is <100ms per trigger, <10ms for status checks. Debouncing prevents excessive operations.

**Q: Can I use multiple integrations together?**
A: Yes. They're designed to work together without conflicts.

**Q: What if I already have git hooks?**
A: The installer detects existing hooks and backs them up. You can manually merge if needed.

**Q: Do I need Claude Code for integrations to work?**
A: No. Integrations work standalone with the core backup system.

**Q: How do I uninstall an integration?**
A: Each integration's README has uninstall instructions. Generally:
- Shell: Remove source line from RC file
- Git: Delete `.git/hooks/pre-commit` etc.
- Tmux: Remove from `~/.tmux.conf`
- VS Code: Delete `.vscode/tasks.json`
- Vim: Remove plugin line

**Q: Can I customize the backup emoji?**
A: Yes, edit `integrations/lib/status-formatter.sh` and change `EMOJI_SUCCESS`, `EMOJI_WARNING`, `EMOJI_ERROR`.

**Q: Do integrations work on Linux?**
A: Yes. Tested on Ubuntu 20.04+, macOS 12+.

**Q: What about Windows/WSL?**
A: WSL should work (uses Linux paths). Native Windows not supported in v1.2.0.

**Q: How do I add a new integration?**
A: See [Integration Development Guide](INTEGRATION-DEVELOPMENT.md).

---

## See Also

- [Main README](../README.md) - Project overview
- [Command Reference](COMMANDS.md) - Backup commands
- [Integration Development](INTEGRATION-DEVELOPMENT.md) - Creating integrations
- [API Reference](API.md) - Library functions

---

**Version**: 1.2.0
**Last Updated**: 2025-12-24
**Status**: Production Ready
