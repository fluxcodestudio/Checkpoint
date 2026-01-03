---
name: checkpoint
description: Checkpoint backup system - run backups, check status, restore files (user)
match:
  - /checkpoint
  - /backup
---

# Checkpoint Command Center

Use AskUserQuestion to present an interactive menu. This is a global backup system that works across all projects.

## Step 1: Show All Projects Status

First, get overview of all registered projects:
```bash
export PATH="$HOME/.local/bin:$PATH"
source ~/.local/lib/checkpoint/lib/projects-registry.sh 2>/dev/null

echo "=== Checkpoint Status ==="
echo ""

# Check global daemon
if launchctl list 2>/dev/null | grep -q "com.checkpoint.global-daemon"; then
    echo "Global Daemon: Running (hourly backups enabled)"
else
    echo "Global Daemon: Not running"
fi
echo ""

# List projects
echo "Registered Projects:"
for p in $(list_projects 2>/dev/null); do
    name=$(basename "$p")
    if [[ -f "$p/.backup-config.sh" ]]; then
        echo "  - $name"
    fi
done 2>/dev/null || echo "  (none - run backup-now in a project to register)"
echo ""
```

Then show current project status if in a project directory:
```bash
export PATH="$HOME/.local/bin:$PATH" && backup-status 2>/dev/null || echo "Not in a configured project"
```

## Step 2: Present Main Menu

Use AskUserQuestion with ONE question:

**Question:** "What would you like to do?"
**Header:** "Action"
**multiSelect:** false

**Options:**
1. **Run Backup Now** - "Backup current project immediately"
2. **Backup All Projects** - "Run backup on all registered projects"
3. **View Status** - "Show detailed status for current project"
4. **Manage Projects** - "View, add, or remove projects"
5. **Settings** - "Configure backup settings"

## Actions Based on Selection

### If "Run Backup Now":
```bash
export PATH="$HOME/.local/bin:$PATH" && backup-now --force
```
This will auto-create config if first time in this project.

### If "Backup All Projects":
```bash
export PATH="$HOME/.local/bin:$PATH" && backup-all
```
Shows progress for each registered project.

### If "View Status":
```bash
export PATH="$HOME/.local/bin:$PATH" && backup-status
```

### If "Manage Projects":
Use AskUserQuestion for submenu:

**Question:** "Project management:"
**Header:** "Projects"

**Options:**
1. **List All** - "Show all registered projects with status"
2. **Add Current** - "Register current directory as a project"
3. **Remove Project** - "Unregister a project from backups"

Commands:
- List All:
```bash
source ~/.local/lib/checkpoint/lib/projects-registry.sh
echo "Registered Projects:"
for p in $(list_projects); do
    name=$(basename "$p")
    if [[ -d "$p" ]]; then
        echo "  ✓ $name - $p"
    else
        echo "  ✗ $name - $p (not found)"
    fi
done
```

- Add Current: Run `backup-now` which auto-registers
- Remove Project: Ask which project, then run `unregister_project "$path"`

### If "Settings":
Use AskUserQuestion for settings submenu:

**Question:** "Which setting?"
**Header:** "Settings"

**Options:**
1. **View Config** - "Show current project configuration"
2. **Edit Global** - "Edit settings for all projects"
3. **Edit Project** - "Edit settings for this project only"
4. **Cleanup** - "Remove old backups based on retention"

Settings commands:
- View Config: `cat .backup-config.sh 2>/dev/null || echo "No project config"`
- Edit Global: Open `~/.config/checkpoint/config.sh`
- Edit Project: Open `.backup-config.sh`
- Cleanup: `backup-cleanup`

## Key Behaviors

1. **Auto-registration**: Running `backup-now` in any directory auto-creates config and registers project
2. **Global daemon**: Single daemon backs up all projects hourly
3. **Per-project config**: Each project can have custom settings in `.backup-config.sh`
4. **Smart defaults**: New projects get sensible defaults automatically

## After Each Action

Offer relevant follow-up actions via another AskUserQuestion when appropriate.
