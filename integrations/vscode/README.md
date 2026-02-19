# VS Code Integration

Task and keybinding integration for ClaudeCode Project Backups in Visual Studio Code.

## Features

- **Tasks**: Run backup commands from VS Code Command Palette
- **Keybindings**: Quick keyboard shortcuts for backup operations
- **Terminal Integration**: Commands run in VS Code integrated terminal
- **Per-Project**: Each project can have its own tasks.json
- **No Extension Required**: Uses native VS Code features

## Installation

### Quick Install

From your project directory:

```bash
/path/to/CLAUDE_CODE_PROJECT_BACKUP/integrations/vscode/install-vscode.sh
```

This creates `.vscode/tasks.json` in your project.

### Manual Install

1. Create `.vscode/tasks.json` in your project:
   ```bash
   mkdir -p .vscode
   cp /path/to/integrations/vscode/tasks.json .vscode/
   ```

2. Set environment variable in your shell RC:
   ```bash
   # ~/.bashrc or ~/.zshrc
   export CLAUDECODE_BACKUP_ROOT="/path/to/CLAUDE_CODE_PROJECT_BACKUP"
   ```

3. Restart VS Code or reload window

## Tasks

### Available Tasks

Access via: `Ctrl+Shift+P` → `Tasks: Run Task`

- **Backup: Show Status** - Display backup status dashboard
- **Backup: Trigger Now** - Create backup immediately
- **Backup: Show Config** - View configuration
- **Backup: Cleanup (Preview)** - Preview cleanup operations
- **Backup: List Backups** - List available backups
- **Backup: Auto (Status + Trigger)** - Combined task

### Running Tasks

**Command Palette**:
```
1. Press Ctrl+Shift+P (or Cmd+Shift+P on macOS)
2. Type "Tasks: Run Task"
3. Select "Backup: Show Status" (or other task)
4. View output in terminal panel
```

**Keyboard Shortcut**:
```
1. Set up keybinding (see below)
2. Press Ctrl+Shift+B S (for status)
3. Terminal opens with output
```

**Task Runner**:
```
Terminal → Run Task... → Select backup task
```

## Keybindings

### Setup

Keybindings are user-global (not per-project).

1. Open Command Palette: `Ctrl+Shift+P`
2. Type: `Preferences: Open Keyboard Shortcuts (JSON)`
3. Add contents from `keybindings.json`:

```json
[
  {
    "key": "ctrl+shift+b s",
    "command": "workbench.action.tasks.runTask",
    "args": "Backup: Show Status"
  },
  {
    "key": "ctrl+shift+b n",
    "command": "workbench.action.tasks.runTask",
    "args": "Backup: Trigger Now"
  },
  // ... etc
]
```

### Default Keybindings

| Keys | Task | Description |
|------|------|-------------|
| `Ctrl+Shift+B S` | Show Status | Display status dashboard |
| `Ctrl+Shift+B N` | Backup Now | Trigger backup |
| `Ctrl+Shift+B C` | Show Config | View configuration |
| `Ctrl+Shift+B L` | Cleanup | Preview cleanup |
| `Ctrl+Shift+B R` | List Backups | Show available backups |

**Note**: On macOS, use `Cmd` instead of `Ctrl`.

### Custom Keybindings

Change keys in your keybindings.json:

```json
{
  "key": "ctrl+alt+b",  // Your preferred key
  "command": "workbench.action.tasks.runTask",
  "args": "Backup: Show Status"
}
```

## Configuration

### Environment Variable Method

Set `CLAUDECODE_BACKUP_ROOT` in shell RC:

```bash
# ~/.bashrc or ~/.zshrc
export CLAUDECODE_BACKUP_ROOT="$HOME/.local/lib/checkpoint"
```

Restart VS Code after adding.

### Absolute Path Method

Edit `.vscode/tasks.json`, replace:
```json
"command": "${env:CLAUDECODE_BACKUP_ROOT}/bin/backup-status.sh"
```

With:
```json
"command": "/absolute/path/to/CLAUDE_CODE_PROJECT_BACKUP/bin/backup-status.sh"
```

### Workspace Settings

Add to `.vscode/settings.json`:

```json
{
  "terminal.integrated.env.osx": {
    "CLAUDECODE_BACKUP_ROOT": "/path/to/backup/system"
  },
  "terminal.integrated.env.linux": {
    "CLAUDECODE_BACKUP_ROOT": "/path/to/backup/system"
  },
  "terminal.integrated.env.windows": {
    "CLAUDECODE_BACKUP_ROOT": "C:\\path\\to\\backup\\system"
  }
}
```

## Advanced Usage

### Task Customization

Edit `.vscode/tasks.json`:

```json
{
  "label": "Backup: Show Status",
  "type": "shell",
  "command": "${env:CLAUDECODE_BACKUP_ROOT}/bin/backup-status.sh",
  "presentation": {
    "reveal": "always",       // always, silent, never
    "panel": "new",           // new, shared, dedicated
    "clear": false,           // Clear before running
    "focus": true             // Focus terminal after
  }
}
```

### Problem Matchers

Add error detection:

```json
{
  "label": "Backup: Trigger Now",
  "type": "shell",
  "command": "...",
  "problemMatcher": {
    "owner": "backup",
    "fileLocation": ["relative", "${workspaceFolder}"],
    "pattern": {
      "regexp": "^(ERROR|WARN):\\s+(.*)$",
      "severity": 1,
      "message": 2
    }
  }
}
```

### Task Dependencies

Run multiple tasks in sequence:

```json
{
  "label": "Backup: Full Workflow",
  "dependsOn": [
    "Backup: Show Status",
    "Backup: Trigger Now",
    "Backup: Show Status"
  ],
  "dependsOrder": "sequence"
}
```

### Build Task

Make backup the default build task:

```json
{
  "label": "Backup: Trigger Now",
  "group": {
    "kind": "build",
    "isDefault": true
  }
}
```

Then use: `Ctrl+Shift+B` (standard build shortcut)

### Auto-Run on Save

Install "Trigger Task on Save" extension, then:

`.vscode/settings.json`:
```json
{
  "triggerTaskOnSave.tasks": {
    "Backup: Trigger Now": [
      "**/*.ts",
      "**/*.js"
    ]
  }
}
```

### Terminal Customization

Change terminal appearance in tasks.json:

```json
{
  "presentation": {
    "echo": true,              // Show command being run
    "reveal": "always",        // When to show terminal
    "focus": false,            // Don't steal focus
    "panel": "dedicated",      // Own terminal panel
    "showReuseMessage": false, // Hide reuse message
    "clear": true              // Clear before run
  }
}
```

## Troubleshooting

### Environment variable not found

1. Check if set in shell:
   ```bash
   echo $CLAUDECODE_BACKUP_ROOT
   ```

2. Restart VS Code completely (close all windows)

3. Or use absolute paths instead (see Configuration)

### Tasks not showing

1. Check `.vscode/tasks.json` exists:
   ```bash
   ls -la .vscode/tasks.json
   ```

2. Validate JSON syntax:
   - Open file in VS Code
   - Look for syntax errors highlighted

3. Reload window:
   `Ctrl+Shift+P` → `Developer: Reload Window`

### Keybindings not working

1. Check for conflicts:
   `Ctrl+Shift+P` → `Preferences: Open Keyboard Shortcuts`
   Search for `ctrl+shift+b`

2. Verify keybindings.json syntax

3. Try different key combination

### Command not found

1. Verify backup scripts exist:
   ```bash
   ls -la $CLAUDECODE_BACKUP_ROOT/bin/backup-*.sh
   ```

2. Test script directly:
   ```bash
   $CLAUDECODE_BACKUP_ROOT/bin/backup-status.sh
   ```

3. Check permissions:
   ```bash
   chmod +x $CLAUDECODE_BACKUP_ROOT/bin/backup-*.sh
   ```

### Terminal opens but nothing happens

1. Check shell integration:
   - VS Code uses your default shell
   - Ensure backup scripts work in that shell

2. Test in VS Code terminal:
   ```bash
   backup status
   ```

3. Check terminal.integrated.shell settings

## Multi-Root Workspaces

Each folder can have its own tasks.json:

```
workspace.code-workspace:
{
  "folders": [
    { "path": "project-a" },  // Has .vscode/tasks.json
    { "path": "project-b" }   // Has .vscode/tasks.json
  ]
}
```

Tasks will be scoped to their folder.

## Remote Development

### SSH

Tasks work over SSH. Ensure:
1. Backup system installed on remote
2. PATH set in remote shell RC
3. SSH connection has environment variables

### WSL

Set Windows path in tasks.json:
```json
{
  "command": "/mnt/c/path/to/backup/system/bin/backup-status.sh"
}
```

Or use WSL path if installed there.

### Containers

Mount backup system in devcontainer.json:

```json
{
  "mounts": [
    "source=/path/to/backup/system,target=/backup,type=bind"
  ],
  "remoteEnv": {
    "CLAUDECODE_BACKUP_ROOT": "/backup"
  }
}
```

## Uninstallation

1. Remove tasks:
   ```bash
   rm .vscode/tasks.json
   ```

2. Remove keybindings:
   - Open keybindings.json
   - Delete backup-related entries

3. Unset environment variable:
   - Edit ~/.bashrc or ~/.zshrc
   - Remove CLAUDECODE_BACKUP_ROOT line

## Integration with Extensions

### Tasks Shell Input

Prompt for input before backup:

```json
{
  "label": "Backup: Custom Message",
  "command": "${env:CLAUDECODE_BACKUP_ROOT}/bin/backup-now.sh",
  "args": ["--message", "${input:backupMessage}"],
  "inputs": [
    {
      "id": "backupMessage",
      "type": "promptString",
      "description": "Backup message"
    }
  ]
}
```

### CodeLens

Create a CodeLens provider extension to show backup status in editor.

### Status Bar

Create extension with status bar item:
```typescript
const statusBarItem = vscode.window.createStatusBarItem();
statusBarItem.text = "$(check) Backup OK";
statusBarItem.command = "backup.showStatus";
```

## Examples

### Minimal Setup

`.vscode/tasks.json`:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Backup Status",
      "type": "shell",
      "command": "/absolute/path/to/backup-status.sh"
    }
  ]
}
```

### Full-Featured

See `tasks.json` template for complete example with all tasks.

## See Also

- [Shell Integration](../shell/README.md)
- [Git Hooks Integration](../git/README.md)
- [Direnv Integration](../direnv/README.md)
- [Main Backup System](../../README.md)
- [VS Code Tasks Documentation](https://code.visualstudio.com/docs/editor/tasks)
