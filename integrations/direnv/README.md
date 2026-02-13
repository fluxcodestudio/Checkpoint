# Direnv Integration

Automatic per-project backup configuration using [direnv](https://direnv.net/).

## What is Direnv?

Direnv is a shell extension that loads/unloads environment variables based on the current directory. When you `cd` into a directory with a `.envrc` file, direnv automatically loads the environment variables defined in it.

## Why Use Direnv with Backups?

- **Per-project settings**: Each project can have different backup configurations
- **Automatic loading**: No manual sourcing required
- **Team sharing**: Commit `.envrc` to git for consistent team settings
- **Zero friction**: Works with any shell (bash, zsh, fish, etc.)

## Prerequisites

Install direnv:

```bash
# macOS
brew install direnv

# Ubuntu/Debian
apt install direnv

# Or see: https://direnv.net/docs/installation.html
```

Configure your shell (add to `~/.bashrc` or `~/.zshrc`):

```bash
# Bash
eval "$(direnv hook bash)"

# Zsh
eval "$(direnv hook zsh)"

# Fish
direnv hook fish | source
```

## Installation

### Quick Install

From your project directory:

```bash
/path/to/CLAUDE_CODE_PROJECT_BACKUP/integrations/direnv/install-direnv.sh
```

The installer will:
1. Check if direnv is installed
2. Copy the `.envrc` template to your project
3. Update the backup root path automatically
4. Run `direnv allow` to enable it

### Manual Install

1. Copy the template:
   ```bash
   cp /path/to/integrations/direnv/.envrc /your/project/.envrc
   ```

2. Edit the backup root path:
   ```bash
   nano /your/project/.envrc
   # Update: export CLAUDECODE_BACKUP_ROOT="/path/to/backup/system"
   ```

3. Allow direnv:
   ```bash
   cd /your/project
   direnv allow
   ```

## Configuration

The `.envrc` file provides these settings:

### Required

```bash
# Path to backup system (update this)
export CLAUDECODE_BACKUP_ROOT="/path/to/backup/system"
```

### Optional

```bash
# Auto-trigger settings
export BACKUP_AUTO_TRIGGER=true                # Auto-backup on cd
export BACKUP_TRIGGER_INTERVAL=300             # Debounce (seconds)

# Prompt settings
export BACKUP_SHOW_PROMPT=true                 # Show in prompt
export BACKUP_PROMPT_FORMAT=emoji              # emoji|compact|verbose

# Aliases
export BACKUP_ALIASES_ENABLED=true             # Enable bs, bn, etc.

# Git hooks
export BACKUP_GIT_QUIET=false                  # Suppress hook messages
export BACKUP_GIT_BLOCK_ON_FAILURE=false       # Block commits on failure
```

## Usage

### Automatic Loading

Simply `cd` into the project directory:

```bash
$ cd /your/project
direnv: loading /your/project/.envrc
✅ Checkpoint Backup System loaded for my-project
   Commands: backup status | backup now | backup help
   Quick: bs | bn | bc | bcl | br
```

### Commands Available

Once loaded, all backup commands are in PATH:

```bash
backup status       # Show status
backup now          # Trigger backup
bs                  # Quick alias for status
bn                  # Quick alias for now
```

### Exiting Directory

When you leave the directory, direnv unloads:

```bash
$ cd ..
direnv: unloading
```

## Examples

### Per-Project Customization

**Project A** (needs frequent backups):
```bash
# /project-a/.envrc
export BACKUP_TRIGGER_INTERVAL=60        # 1 minute
export BACKUP_PROMPT_FORMAT=verbose      # Show detailed status
```

**Project B** (large, infrequent backups):
```bash
# /project-b/.envrc
export BACKUP_TRIGGER_INTERVAL=3600      # 1 hour
export BACKUP_AUTO_TRIGGER=false         # Manual only
```

### Team Configuration

Commit `.envrc` to your repository:

```bash
git add .envrc
git commit -m "Add direnv backup integration"
```

Team members just need to:
1. Install direnv
2. Clone the repo
3. Run `direnv allow`

### Shell Integration

For full shell features (prompt, auto-trigger), uncomment in `.envrc`:

```bash
# Uncomment this line:
source "$CLAUDECODE_BACKUP_ROOT/integrations/shell/backup-shell-integration.sh"
```

Then:
```bash
direnv allow
# Reload shell or cd away and back
```

## Troubleshooting

### direnv: error .envrc is blocked

Run `direnv allow` in the directory:

```bash
cd /your/project
direnv allow
```

### Commands not found

Check if PATH was updated:

```bash
echo $PATH | grep -o "CLAUDE.*BACKUP"
```

If not, verify `CLAUDECODE_BACKUP_ROOT` is set correctly in `.envrc`.

### Changes not taking effect

Reload direnv after editing `.envrc`:

```bash
direnv allow
# Or force reload:
direnv reload
```

### Shell integration not working

Make sure you uncommented the source line in `.envrc`:

```bash
grep "source.*backup-shell-integration" .envrc
```

## Advanced

### Global Direnv Configuration

Create `~/.config/direnv/direnvrc` for global helpers:

```bash
# Load Checkpoint backups for any git repo
layout_claudecode_backup() {
    local backup_root="/path/to/backup/system"
    export PATH="$backup_root/bin:$PATH"
}
```

Then in project `.envrc`:
```bash
layout_claudecode_backup
```

### Conditional Loading

Load backup system only for specific conditions:

```bash
# Only in git repositories
if git rev-parse --git-dir &>/dev/null; then
    export CLAUDECODE_BACKUP_ROOT="/path/to/backup/system"
    export PATH="$CLAUDECODE_BACKUP_ROOT/bin:$PATH"
fi
```

### Environment-Specific Settings

```bash
# Development
if [[ "$(hostname)" == "dev-machine" ]]; then
    export BACKUP_TRIGGER_INTERVAL=60
fi

# Production
if [[ "$(hostname)" == "prod-server" ]]; then
    export BACKUP_TRIGGER_INTERVAL=3600
    export BACKUP_GIT_BLOCK_ON_FAILURE=true
fi
```

## Integration with Other Tools

### With Git Hooks

Direnv + Git hooks work perfectly together:
- Direnv sets environment variables
- Git hooks read those variables

Install both:
```bash
./integrations/direnv/install-direnv.sh
./integrations/git/install-git-hooks.sh
```

### With Docker

Add to `.envrc`:
```bash
# Mount backup system in Docker
export DOCKER_BACKUP_MOUNT="$CLAUDECODE_BACKUP_ROOT:/backup:ro"
```

Then in `docker-compose.yml`:
```yaml
volumes:
  - ${DOCKER_BACKUP_MOUNT}
```

## Uninstallation

Remove `.envrc`:

```bash
rm /your/project/.envrc
direnv reload  # Unload environment
```

## Security Notes

- **.envrc is code**: Direnv executes it, so review carefully
- **Commit safely**: Don't put secrets in `.envrc` (use `.envrc.local`)
- **Allow explicitly**: direnv blocks by default until you run `direnv allow`

## See Also

- [Direnv Documentation](https://direnv.net/)
- [Shell Integration](../shell/README.md)
- [Git Hooks Integration](../git/README.md)
- [Main Backup System](../../README.md)
