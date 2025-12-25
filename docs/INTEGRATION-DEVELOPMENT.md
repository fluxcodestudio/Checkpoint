# Integration Development Guide

Guide for developers creating new integrations or contributing to existing ones.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Integration Core API](#integration-core-api)
- [Creating a New Integration](#creating-a-new-integration)
- [Best Practices](#best-practices)
- [Testing](#testing)
- [Contributing](#contributing)

---

## Overview

### What is an Integration?

An integration is a platform adapter that connects the core backup system to a specific environment (shell, editor, tool, etc.).

**Key Principles**:
1. **Non-invasive**: Don't modify core backup system
2. **Modular**: Self-contained, optional
3. **Consistent**: Use integration-core.sh API
4. **Tested**: Include tests for all functionality
5. **Documented**: README + examples

### Integration Anatomy

```
integrations/
└── myintegration/
    ├── README.md                  # Installation & usage
    ├── install-myintegration.sh   # Installer (optional)
    ├── myintegration-main.sh      # Main integration script
    └── config.template            # Config template (optional)
```

---

## Architecture

### Component Layers

```
┌──────────────────────────────────────┐
│    Your Integration (New)            │
│    integrations/myintegration/       │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│    Integration Core API              │
│    integrations/lib/                 │
│    ├── integration-core.sh           │
│    ├── notification.sh               │
│    └── status-formatter.sh           │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│    Core Backup System                │
│    bin/backup-*.sh                   │
└──────────────────────────────────────┘
```

### Integration Core Libraries

**integration-core.sh**: Common integration utilities
- Initialization
- Debouncing
- Status retrieval
- Lock checking

**notification.sh**: Cross-platform notifications
- Success/error/warning/info
- macOS, Linux, Terminal fallback

**status-formatter.sh**: Output formatting
- Emoji, colors, tables
- Duration, size, time formatting

---

## Getting Started

### Prerequisites

1. Core backup system installed
2. Bash 3.2+ knowledge
3. Understanding of target platform
4. Git for version control

### Development Setup

```bash
# Clone/navigate to project
cd /path/to/Checkpoint

# Create integration directory
mkdir -p integrations/myintegration

# Create basic structure
touch integrations/myintegration/README.md
touch integrations/myintegration/myintegration.sh
chmod +x integrations/myintegration/myintegration.sh
```

### Hello World Integration

Create `integrations/myintegration/hello.sh`:

```bash
#!/bin/bash
# Simple integration example

# Load integration core
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$INTEGRATION_DIR/lib/integration-core.sh"
source "$INTEGRATION_DIR/lib/notification.sh"

# Initialize
integration_init || exit 1

# Get backup status
status=$(integration_get_status_compact)
echo "Current status: $status"

# Trigger backup
integration_trigger_backup --quiet

# Show notification
notify_success "Backup completed!"
```

Run it:
```bash
./integrations/myintegration/hello.sh
```

---

## Integration Core API

### integration-core.sh Functions

#### integration_init()
Initialize integration, verify backup system accessible.

**Usage**:
```bash
integration_init || exit 1
```

**Returns**: 0 on success, 1 on error

---

#### integration_trigger_backup([OPTIONS])
Trigger backup with debouncing.

**Options**:
- `--force` - Bypass debounce
- `--quiet` - Suppress output
- `--dry-run` - Preview only

**Usage**:
```bash
# Normal trigger (respects debounce)
integration_trigger_backup

# Force trigger
integration_trigger_backup --force

# Quiet mode
integration_trigger_backup --quiet
```

**Returns**: 0 on success, 2 if debounced, 1 on error

---

#### integration_get_status([OPTIONS])
Get full backup status.

**Options**:
- `--compact` - One-line output
- `--json` - JSON format
- `--timeline` - Timeline view

**Usage**:
```bash
status=$(integration_get_status --compact)
echo "$status"
# Output: ✅ All backups current (2 projects, 2h ago)
```

---

#### integration_get_status_compact()
Get one-line compact status.

**Usage**:
```bash
status=$(integration_get_status_compact)
# Returns: ✅ All backups current (2 projects, 2h ago)
```

---

#### integration_get_status_emoji()
Get just status emoji.

**Usage**:
```bash
emoji=$(integration_get_status_emoji)
# Returns: ✅ or ⚠️ or ❌
```

---

#### integration_check_lock()
Check if backup currently running.

**Usage**:
```bash
if integration_check_lock; then
    echo "Backup is running..."
else
    echo "No backup running"
fi
```

**Returns**: 0 if backup running, 1 if not

---

#### integration_should_trigger([INTERVAL])
Check if enough time passed since last trigger.

**Parameters**:
- `INTERVAL` - Seconds (default: 300)

**Usage**:
```bash
if integration_should_trigger 600; then
    echo "Should trigger (>10 min since last)"
else
    echo "Too soon, skip"
fi
```

**Returns**: 0 if should trigger, 1 if should skip

---

#### integration_debounce(INTERVAL COMMAND [ARGS])
Generic debounce wrapper.

**Usage**:
```bash
integration_debounce 300 echo "Hello after 5 minutes"
```

**Returns**: 0 if executed, 2 if skipped, 1 on error

---

#### integration_format_time_ago(SECONDS)
Format elapsed time.

**Usage**:
```bash
time=$(integration_format_time_ago 3661)
echo "$time"
# Output: 1h ago
```

---

#### integration_time_since_backup()
Get time since last backup.

**Usage**:
```bash
time=$(integration_time_since_backup)
echo "Last backup: $time"
# Output: Last backup: 2h ago
```

---

### notification.sh Functions

#### notify_success(MESSAGE [TITLE])
Show success notification.

**Usage**:
```bash
notify_success "Backup completed" "Backup System"
```

---

#### notify_error(MESSAGE [TITLE])
Show error notification.

**Usage**:
```bash
notify_error "Backup failed: disk full" "Backup System"
```

---

#### notify_warning(MESSAGE [TITLE])
Show warning notification.

**Usage**:
```bash
notify_warning "Backup incomplete" "Backup System"
```

---

#### notify_info(MESSAGE [TITLE])
Show info notification.

**Usage**:
```bash
notify_info "Backup starting..." "Backup System"
```

---

### status-formatter.sh Functions

#### format_duration(SECONDS)
Format duration.

**Usage**:
```bash
duration=$(format_duration 3661)
echo "$duration"
# Output: 1h 1m
```

---

#### format_size(BYTES)
Format byte size.

**Usage**:
```bash
size=$(format_size 1048576)
echo "$size"
# Output: 1MB
```

---

#### format_success(MESSAGE)
Format success message with emoji.

**Usage**:
```bash
format_success "Backup completed"
# Output: ✅ Backup completed (with color)
```

---

#### format_error(MESSAGE)
Format error message with emoji.

**Usage**:
```bash
format_error "Backup failed"
# Output: ❌ Backup failed (with color)
```

---

## Creating a New Integration

### Step-by-Step Guide

#### 1. Choose Platform

Identify target platform:
- Shell (fish, nushell, etc.)
- Editor (Emacs, Sublime, JetBrains, etc.)
- Tool (Make, Task, Just, etc.)
- System (systemd, cron, launchd, etc.)

#### 2. Create Directory Structure

```bash
mkdir -p integrations/myplatform
cd integrations/myplatform
```

#### 3. Create Main Script

**File**: `integrations/myplatform/myplatform-integration.sh`

```bash
#!/bin/bash
# MyPlatform Integration
# Version: 1.0.0

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load core libraries
BACKUP_INTEGRATION_QUIET_LOAD=true
source "$INTEGRATION_DIR/lib/integration-core.sh" || exit 1
source "$INTEGRATION_DIR/lib/notification.sh"
source "$INTEGRATION_DIR/lib/status-formatter.sh"

# Initialize
integration_init || exit 1

# Configuration variables (user-customizable)
: "${MYPLATFORM_AUTO_TRIGGER:=true}"
: "${MYPLATFORM_TRIGGER_INTERVAL:=300}"
: "${MYPLATFORM_SHOW_STATUS:=true}"

# ==============================================================================
# PLATFORM-SPECIFIC FUNCTIONS
# ==============================================================================

myplatform_trigger_backup() {
    # Your platform-specific trigger logic
    if [[ "$MYPLATFORM_AUTO_TRIGGER" == "true" ]]; then
        integration_trigger_backup --quiet &
    fi
}

myplatform_show_status() {
    # Your platform-specific status display
    if [[ "$MYPLATFORM_SHOW_STATUS" == "true" ]]; then
        local status=$(integration_get_status_compact)
        echo "$status"
    fi
}

# ==============================================================================
# MAIN INTEGRATION LOGIC
# ==============================================================================

# Your integration-specific code here
```

#### 4. Create Installer (Optional)

**File**: `integrations/myplatform/install-myplatform.sh`

```bash
#!/bin/bash
# MyPlatform Integration Installer

set -eo pipefail

echo "Installing MyPlatform integration..."

# Detect platform
if ! command -v myplatform &>/dev/null; then
    echo "Error: MyPlatform not found"
    exit 1
fi

# Installation logic
# - Copy files
# - Update config
# - Verify installation

echo "✅ Installation complete!"
```

#### 5. Create README

**File**: `integrations/myplatform/README.md`

Use this template:

```markdown
# MyPlatform Integration

Description of integration.

## Features

- Feature 1
- Feature 2

## Installation

\`\`\`bash
./integrations/myplatform/install-myplatform.sh
\`\`\`

## Configuration

\`\`\`bash
export MYPLATFORM_AUTO_TRIGGER=true
\`\`\`

## Usage

\`\`\`bash
# Example usage
\`\`\`

## Troubleshooting

Common issues and solutions.

## See Also

- [Integrations Guide](../../docs/INTEGRATIONS.md)
```

#### 6. Add Tests

**File**: `tests/integration/test-myplatform.sh`

```bash
#!/bin/bash
# Tests for MyPlatform integration

test_myplatform_exists() {
    [[ -f "integrations/myplatform/myplatform-integration.sh" ]]
}

test_myplatform_executable() {
    [[ -x "integrations/myplatform/install-myplatform.sh" ]]
}

# Add to main test suite
```

---

## Best Practices

### 1. Use Integration Core API

**Don't** call backup scripts directly:
```bash
# ❌ Bad
/path/to/bin/backup-now.sh
```

**Do** use integration core:
```bash
# ✅ Good
integration_trigger_backup
```

### 2. Respect Debouncing

**Don't** spam backups:
```bash
# ❌ Bad - triggers every time
backup_on_event() {
    /path/to/bin/backup-now.sh --force
}
```

**Do** use debouncing:
```bash
# ✅ Good - respects debounce
backup_on_event() {
    integration_trigger_backup
}
```

### 3. Handle Errors Gracefully

**Don't** crash user workflows:
```bash
# ❌ Bad - exit kills shell
integration_trigger_backup || exit 1
```

**Do** handle errors:
```bash
# ✅ Good - log and continue
integration_trigger_backup || {
    notify_error "Backup failed" >&2
    return 1
}
```

### 4. Be Non-Invasive

**Don't** modify existing configs without permission:
```bash
# ❌ Bad - overwrites user config
echo "source /path/to/integration.sh" >> ~/.bashrc
```

**Do** ask or backup first:
```bash
# ✅ Good - backup first
cp ~/.bashrc ~/.bashrc.backup
echo "source /path/to/integration.sh" >> ~/.bashrc
```

### 5. Provide Configuration Options

```bash
# ✅ Good - configurable via env vars
: "${INTEGRATION_ENABLED:=true}"
: "${INTEGRATION_INTERVAL:=300}"
: "${INTEGRATION_QUIET:=false}"
```

### 6. Document Everything

- Clear README with examples
- Inline code comments
- Help text for scripts
- Troubleshooting section

---

## Testing

### Unit Tests

Test individual functions:

```bash
test_integration_loads() {
    source integrations/myplatform/myplatform.sh
    [[ $? -eq 0 ]]
}

test_functions_exist() {
    type myplatform_trigger_backup &>/dev/null
}
```

### Integration Tests

Test with actual backup system:

```bash
test_trigger_works() {
    integration_trigger_backup --dry-run
    [[ $? -eq 0 ]]
}
```

### Add to Test Suite

Edit `tests/integration/test-integrations.sh`:

```bash
test_myplatform() {
    test_header "Testing MyPlatform Integration"

    run_test "MyPlatform script exists" test -f "integrations/myplatform/myplatform.sh"
    run_test "MyPlatform loads" source "integrations/myplatform/myplatform.sh"
}

# Add to main()
test_myplatform
```

---

## Contributing

### Submission Checklist

Before submitting a new integration:

- [ ] Integration follows directory structure
- [ ] Uses integration-core.sh API
- [ ] Includes installer (if applicable)
- [ ] Has comprehensive README
- [ ] Includes tests
- [ ] Tests pass: `./tests/integration/test-integrations.sh`
- [ ] Code documented with comments
- [ ] Examples provided
- [ ] Troubleshooting section
- [ ] Compatible with bash 3.2+
- [ ] Non-invasive (doesn't break user setup)
- [ ] Handles errors gracefully

### Pull Request Process

1. Fork repository
2. Create feature branch: `git checkout -b integration/myplatform`
3. Implement integration
4. Add tests
5. Update `docs/INTEGRATIONS.md` with new integration
6. Submit PR with description

### Code Style

- Use `bash` not `sh`
- Indent with 2 or 4 spaces (consistent)
- Comment complex logic
- Use `set -eo pipefail` for safety
- Quote variables: `"$VAR"`
- Check undefined: `${VAR:-default}`

---

## Examples

### Example 1: Fish Shell Integration

```bash
#!/bin/bash
# Fish Shell Integration

source integrations/lib/integration-core.sh
integration_init || exit 1

# Generate Fish syntax
cat > ~/.config/fish/conf.d/backup.fish << 'EOF'
# Checkpoint Backup Integration
function backup_prompt_status
    set -l status (integration_get_status_emoji)
    echo "$status"
end

# Add to prompt
function fish_prompt
    echo -n (backup_prompt_status)" "
    # ... rest of prompt
end
EOF
```

### Example 2: Systemd Timer Integration

```bash
#!/bin/bash
# Systemd Timer Integration

# Create timer unit
cat > ~/.config/systemd/user/backup.timer << 'EOF'
[Unit]
Description=Backup Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
EOF

# Create service unit
cat > ~/.config/systemd/user/backup.service << 'EOF'
[Unit]
Description=Trigger Backup

[Service]
Type=oneshot
ExecStart=/path/to/bin/backup-now.sh
EOF

# Enable timer
systemctl --user enable backup.timer
systemctl --user start backup.timer
```

---

## Resources

### Documentation
- [Integrations Guide](INTEGRATIONS.md)
- [Command Reference](COMMANDS.md)
- [API Reference](API.md)

### Example Integrations
- Shell: `integrations/shell/`
- Git: `integrations/git/`
- Tmux: `integrations/tmux/`

### External Resources
- [Bash Guide](https://mywiki.wooledge.org/BashGuide)
- [ShellCheck](https://www.shellcheck.net/)
- [Integration Patterns](https://github.com/alebcay/awesome-shell)

---

**Version**: 1.2.0
**Last Updated**: 2025-12-24
**Maintainer**: Jon Rezin
