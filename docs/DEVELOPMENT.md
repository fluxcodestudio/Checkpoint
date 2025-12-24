# Development Guide

Developer documentation for Checkpoint.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Development Setup](#development-setup)
- [Adding New Commands](#adding-new-commands)
- [Testing Guidelines](#testing-guidelines)
- [Code Style](#code-style)
- [Release Process](#release-process)
- [Contributing](#contributing)

---

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                    User Interface                        │
│  (/backup-config, /backup-status, /backup-now, etc.)   │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
┌────────▼─────────┐    ┌───────▼────────┐
│  Command Layer   │    │  Foundation    │
│  (bin/*.sh)      │◄───┤  Library       │
│                  │    │  (lib/*.sh)    │
└────────┬─────────┘    └───────┬────────┘
         │                      │
         │   ┌──────────────────┘
         │   │
┌────────▼───▼─────────────────────────────┐
│         Configuration Layer               │
│  (.backup-config.yaml / .backup-config.sh)│
└────────┬──────────────────────────────────┘
         │
         │
┌────────▼──────────────────────────────────┐
│          Core Backup Engine               │
│         (backup-daemon.sh)                │
└────────┬──────────────────────────────────┘
         │
         │
┌────────▼──────────────────────────────────┐
│        Scheduling & Triggers              │
│  (LaunchAgent, Claude Code Hooks)         │
└───────────────────────────────────────────┘
```

### Data Flow

```
┌──────────┐     ┌──────────┐     ┌──────────┐
│ User     │────►│ Command  │────►│ Config   │
│ Input    │     │ Parse    │     │ Load     │
└──────────┘     └──────────┘     └────┬─────┘
                                       │
                                       ▼
┌──────────┐     ┌──────────┐     ┌──────────┐
│ Backup   │◄────│ Validate │◄────│ Execute  │
│ Complete │     │ Result   │     │ Action   │
└──────────┘     └──────────┘     └──────────┘
```

### Design Principles

1. **Modularity** - Each component has single responsibility
2. **Reusability** - Shared logic in foundation library
3. **Backward Compatibility** - Support both config formats
4. **Graceful Degradation** - Work even when external drive disconnected
5. **Idempotency** - Safe to run commands multiple times
6. **Testability** - Every component has unit and integration tests

---

## Project Structure

```
ClaudeCode-Project-Backups/
├── bin/                           # Executable scripts
│   ├── backup-daemon.sh           # Core backup engine
│   ├── smart-backup-trigger.sh    # Claude Code hook
│   ├── install.sh                 # Installation wizard
│   ├── uninstall.sh               # Uninstaller
│   ├── status.sh                  # Status checker (legacy)
│   └── restore.sh                 # Restore utility (legacy)
│
├── lib/                           # Foundation library (v1.1.0+)
│   ├── backup-lib.sh              # Core functions
│   ├── yaml-parser.sh             # YAML parsing
│   ├── config-validator.sh        # Configuration validation
│   └── ui-helpers.sh              # TUI components
│
├── commands/                      # Command implementations (v1.1.0+)
│   ├── backup-config.sh           # /backup-config
│   ├── backup-status.sh           # /backup-status
│   ├── backup-now.sh              # /backup-now
│   ├── backup-restore.sh          # /backup-restore
│   └── backup-cleanup.sh          # /backup-cleanup
│
├── templates/                     # Configuration templates
│   ├── backup-config.sh           # Bash config template
│   ├── backup-config.yaml         # YAML config template
│   ├── pre-database.sh            # Database safety hook
│   └── launchagent.plist          # macOS LaunchAgent
│
├── docs/                          # Documentation
│   ├── COMMANDS.md                # Command reference
│   ├── MIGRATION.md               # Migration guide
│   ├── INTEGRATION.md             # Integration guide
│   ├── DEVELOPMENT.md             # This file
│   └── API.md                     # Library reference
│
├── examples/                      # Example configs and scripts
│   ├── configs/                   # YAML templates
│   │   ├── minimal.yaml
│   │   ├── standard.yaml
│   │   ├── paranoid.yaml
│   │   ├── external-drive.yaml
│   │   └── no-database.yaml
│   └── commands/                  # Usage examples
│       ├── basic-setup.sh
│       ├── advanced-config.sh
│       ├── disaster-recovery.sh
│       └── maintenance.sh
│
├── tests/                         # Test suite
│   ├── test-backup-system.sh      # Core system tests
│   ├── test-command-system.sh     # Command tests
│   ├── test-config-validation.sh  # Config validation tests
│   └── integration/               # Integration tests
│       ├── test-fresh-install.sh
│       ├── test-migration-v1-to-v11.sh
│       ├── test-command-workflow.sh
│       └── test-error-recovery.sh
│
├── README.md                      # Main documentation
├── CHANGELOG.md                   # Version history
├── LICENSE                        # MIT license
└── VERSION                        # Current version number
```

### File Responsibilities

| File | Purpose | Key Functions |
|------|---------|---------------|
| `bin/backup-daemon.sh` | Core backup logic | `backup_database()`, `backup_changed_files()` |
| `lib/backup-lib.sh` | Shared utilities | `load_config()`, `log_message()`, `validate_paths()` |
| `lib/yaml-parser.sh` | YAML parsing | `parse_yaml()`, `get_yaml_value()`, `set_yaml_value()` |
| `lib/config-validator.sh` | Config validation | `validate_config()`, `check_required_fields()` |
| `commands/backup-config.sh` | Config management | `wizard_mode()`, `tui_editor()`, `migrate_config()` |
| `commands/backup-status.sh` | Health monitoring | `check_components()`, `generate_dashboard()` |

---

## Development Setup

### Prerequisites

```bash
# Install dependencies
brew install bash git sqlite3 shellcheck shfmt

# Clone repository
git clone https://github.com/your-org/ClaudeCode-Project-Backups.git
cd ClaudeCode-Project-Backups

# Install pre-commit hooks
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### Environment Setup

```bash
# Set development environment
export BACKUP_DEV_MODE=1
export BACKUP_LOG_LEVEL=debug

# Use test project
export TEST_PROJECT=/tmp/test-backup-project
```

### Running Tests

```bash
# All tests
./tests/test-backup-system.sh

# Command tests only
./tests/test-command-system.sh

# Config validation tests
./tests/test-config-validation.sh

# Integration tests
./tests/integration/test-fresh-install.sh
./tests/integration/test-migration-v1-to-v11.sh
```

### Linting and Formatting

```bash
# Lint all shell scripts
find . -name "*.sh" -exec shellcheck {} \;

# Format scripts
find . -name "*.sh" -exec shfmt -w -i 4 {} \;

# Check bash syntax
find . -name "*.sh" -exec bash -n {} \;
```

---

## Adding New Commands

### Step 1: Create Command Script

**Template:** `commands/backup-mycommand.sh`

```bash
#!/bin/bash
# /backup-mycommand - Description of what this command does
set -euo pipefail

# Source foundation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/backup-lib.sh"

# Command metadata
COMMAND_NAME="backup-mycommand"
COMMAND_VERSION="1.1.0"
COMMAND_DESCRIPTION="Description of command"

# Parse arguments
show_help() {
    cat << EOF
Usage: $COMMAND_NAME [OPTIONS]

Description of what this command does.

Options:
  --option1 VALUE    Description of option1
  --option2          Description of option2
  --help             Show this help message

Examples:
  $COMMAND_NAME --option1 value
  $COMMAND_NAME --option2

EOF
}

# Main function
main() {
    # Load configuration
    load_config

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --option1)
                OPTION1="$2"
                shift 2
                ;;
            --option2)
                OPTION2=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done

    # Validate configuration
    validate_config

    # Execute command logic
    execute_command
}

# Command implementation
execute_command() {
    log_info "Executing $COMMAND_NAME..."

    # Your command logic here

    log_success "Command completed"
}

# Run main
main "$@"
```

### Step 2: Install Command

```bash
# Symlink to /usr/local/bin
sudo ln -sf "$PWD/commands/backup-mycommand.sh" /usr/local/bin/backup-mycommand

# Make executable
chmod +x commands/backup-mycommand.sh
```

### Step 3: Add Tests

**Create:** `tests/test-mycommand.sh`

```bash
#!/bin/bash
set -euo pipefail

test_mycommand_basic() {
    /backup-mycommand --option1 value
    # Assert expected outcome
}

test_mycommand_validation() {
    # Test invalid input
    ! /backup-mycommand --invalid-option
}

# Run tests
test_mycommand_basic
test_mycommand_validation
```

### Step 4: Document Command

Update `docs/COMMANDS.md` with:
- Synopsis
- Description
- Options table
- Examples
- Integration with other commands

### Step 5: Update Installer

Add to `bin/install.sh`:

```bash
# Install new command
if [ -f "$PACKAGE_DIR/commands/backup-mycommand.sh" ]; then
    ln -sf "$PACKAGE_DIR/commands/backup-mycommand.sh" /usr/local/bin/backup-mycommand
    chmod +x /usr/local/bin/backup-mycommand
fi
```

---

## Testing Guidelines

### Test Pyramid

```
           ┌─────────────┐
           │ Integration │  (Few, slow, comprehensive)
           │    Tests    │
           └─────────────┘
          ┌───────────────┐
          │  Command      │  (Some, medium speed)
          │  Tests        │
          └───────────────┘
        ┌───────────────────┐
        │   Unit Tests      │  (Many, fast, focused)
        │  (lib functions)  │
        └───────────────────┘
```

### Test Structure

**Unit Tests:** Test individual functions

```bash
test_yaml_parser() {
    # Setup
    cat > /tmp/test.yaml << EOF
key: value
nested:
  subkey: subvalue
EOF

    # Execute
    result=$(get_yaml_value /tmp/test.yaml "nested.subkey")

    # Assert
    [[ "$result" == "subvalue" ]] || fail "Expected 'subvalue', got '$result'"

    # Cleanup
    rm /tmp/test.yaml
}
```

**Command Tests:** Test command interfaces

```bash
test_backup_config_get() {
    # Setup project
    setup_test_project

    # Execute
    result=$(/backup-config --get project.name)

    # Assert
    [[ "$result" == "TestProject" ]] || fail "Unexpected project name"

    # Cleanup
    cleanup_test_project
}
```

**Integration Tests:** Test complete workflows

```bash
test_fresh_install_workflow() {
    # Setup clean environment
    rm -rf /tmp/test-project
    mkdir -p /tmp/test-project
    cd /tmp/test-project
    git init

    # Execute installation
    /path/to/install.sh <<< "TestProject\n$(pwd)\n..."

    # Verify installation
    [[ -f .backup-config.yaml ]] || fail "Config not created"
    [[ -x .claude/backup-daemon.sh ]] || fail "Daemon not installed"

    # Execute backup
    /backup-now

    # Verify backup
    [[ -d backups/files ]] || fail "Backup not created"

    # Cleanup
    rm -rf /tmp/test-project
}
```

### Test Helpers

**Available in `tests/test-helpers.sh`:**

```bash
# Setup/teardown
setup_test_project()
cleanup_test_project()

# Assertions
assert_equals "expected" "actual"
assert_file_exists "/path/to/file"
assert_dir_exists "/path/to/dir"
assert_command_succeeds "command"
assert_command_fails "command"

# Mocking
mock_config() { ... }
mock_git_status() { ... }
```

### Running Specific Tests

```bash
# Single test
bash tests/test-command-system.sh -t test_backup_config_get

# Test category
bash tests/test-command-system.sh -c config

# Verbose mode
bash tests/test-command-system.sh -v

# Skip integration tests
bash tests/test-command-system.sh --skip-integration
```

### Code Coverage

```bash
# Install coverage tool
brew install bashcov

# Run with coverage
bashcov ./tests/test-backup-system.sh

# View report
open coverage/index.html
```

---

## Code Style

### Shell Script Style

**Based on:**
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [ShellCheck](https://www.shellcheck.net/) recommendations

### Formatting Rules

```bash
# Indentation: 4 spaces (no tabs)
if [ condition ]; then
    echo "Indented with 4 spaces"
fi

# Line length: 100 characters max
long_command \
    --option1 value1 \
    --option2 value2

# Function definitions
function_name() {
    local var="value"
    echo "Function body"
}

# Variables
GLOBAL_VAR="uppercase"
local_var="lowercase"

# Constants
readonly CONSTANT_VALUE="immutable"

# Arrays
declare -a array_name=(
    "item1"
    "item2"
    "item3"
)
```

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Global variables | UPPER_SNAKE_CASE | `PROJECT_NAME` |
| Local variables | lower_snake_case | `backup_count` |
| Functions | lower_snake_case | `load_config()` |
| Constants | UPPER_SNAKE_CASE | `readonly VERSION="1.1.0"` |
| Files | kebab-case | `backup-config.sh` |

### Error Handling

```bash
# Always use set -euo pipefail
set -euo pipefail

# Check command success
if ! command_that_might_fail; then
    log_error "Command failed"
    exit 1
fi

# Validate inputs
validate_input() {
    local input="$1"

    if [[ -z "$input" ]]; then
        log_error "Input required"
        return 1
    fi

    return 0
}

# Use trap for cleanup
cleanup() {
    rm -f /tmp/tempfile
}
trap cleanup EXIT
```

### Logging

```bash
# Use standard logging functions
log_debug "Debug message (only in dev mode)"
log_info "Informational message"
log_warning "Warning message"
log_error "Error message"
log_success "Success message"

# Format
# [2025-12-24 14:30:45] [INFO] Message here
# [2025-12-24 14:30:46] [ERROR] Error here
```

### Comments

```bash
# Single-line comment for brief explanation

# Multi-line comment for complex logic:
# - First point
# - Second point
# - Third point

#==============================================================================
# SECTION HEADER
#==============================================================================

# Function documentation
# @description: What the function does
# @param $1: Description of first parameter
# @param $2: Description of second parameter
# @return: What the function returns
# @example: function_name "arg1" "arg2"
function_name() {
    # Implementation
}
```

### shellcheck Compliance

```bash
# Suppress specific warnings (use sparingly)
# shellcheck disable=SC2034  # Unused variable
UNUSED_VAR="value"

# Prefer array over word splitting
files=( $(find . -name "*.sh") )  # Bad
mapfile -t files < <(find . -name "*.sh")  # Good

# Quote variables
echo $var  # Bad
echo "$var"  # Good
```

---

## Release Process

### Version Numbering

**Semantic Versioning:** MAJOR.MINOR.PATCH

- **MAJOR:** Breaking changes
- **MINOR:** New features (backward compatible)
- **PATCH:** Bug fixes

### Release Checklist

**1. Pre-Release**

- [ ] All tests passing
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] VERSION file updated
- [ ] No shellcheck warnings
- [ ] Code formatted with shfmt

**2. Testing**

- [ ] Run full test suite
- [ ] Test fresh installation
- [ ] Test migration from previous version
- [ ] Test on clean macOS install
- [ ] Test all commands manually

**3. Create Release**

```bash
# Update version
echo "1.1.0" > VERSION

# Update CHANGELOG.md
# Add release date and notes

# Commit changes
git add VERSION CHANGELOG.md
git commit -m "Release v1.1.0"

# Tag release
git tag -a v1.1.0 -m "Version 1.1.0"

# Push
git push origin main
git push origin v1.1.0
```

**4. Post-Release**

- [ ] Create GitHub release
- [ ] Update documentation site
- [ ] Announce in relevant channels
- [ ] Monitor for issues

### Hotfix Process

```bash
# Create hotfix branch from tag
git checkout -b hotfix/1.1.1 v1.1.0

# Fix issue
# ... make changes ...

# Test
./tests/test-backup-system.sh

# Update version
echo "1.1.1" > VERSION

# Update CHANGELOG.md
# Add hotfix notes

# Commit
git commit -am "Hotfix v1.1.1: Fix critical issue"

# Tag
git tag -a v1.1.1 -m "Hotfix 1.1.1"

# Merge back to main
git checkout main
git merge hotfix/1.1.1

# Push
git push origin main v1.1.1
```

---

## Contributing

### Contribution Workflow

1. **Fork** the repository
2. **Create** feature branch: `git checkout -b feature/my-feature`
3. **Implement** changes with tests
4. **Test** thoroughly
5. **Format** code: `shfmt -w -i 4 *.sh`
6. **Lint** code: `shellcheck *.sh`
7. **Commit** with clear messages
8. **Push** to your fork
9. **Create** pull request

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style (formatting)
- `refactor`: Code restructuring
- `test`: Adding tests
- `chore`: Maintenance

**Example:**

```
feat(commands): Add /backup-verify command

Implements database integrity verification and file checksum validation.

- Add verify_database() function
- Add verify_files() function
- Add comprehensive tests
- Update documentation

Closes #123
```

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] All tests passing
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guide
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] No shellcheck warnings
```

### Code Review Guidelines

**Reviewers should check:**
- Code style compliance
- Test coverage
- Error handling
- Documentation quality
- Backward compatibility
- Performance implications

---

## Debugging

### Debug Mode

```bash
# Enable debug mode
export BACKUP_DEBUG=1

# Run command with debug output
/backup-config --validate

# Debug output includes:
# - Function entry/exit
# - Variable values
# - Execution time
# - Stack traces
```

### Logging Levels

```bash
# Set log level
export BACKUP_LOG_LEVEL=debug

# Levels (in order):
# - debug: Detailed debugging info
# - info: General information
# - warning: Warning messages
# - error: Error messages only
```

### Common Issues

**Issue: Tests failing locally**

```bash
# Clean test environment
rm -rf /tmp/test-backup-*
rm -rf ~/.claudecode-backups/state/.test-*

# Run with fresh state
./tests/test-backup-system.sh
```

**Issue: Command not found after installation**

```bash
# Check symlinks
ls -la /usr/local/bin/backup-*

# Reinstall commands
sudo rm /usr/local/bin/backup-*
./bin/install.sh
```

**Issue: YAML parsing errors**

```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('.backup-config.yaml'))"

# Or use yq
yq eval '.' .backup-config.yaml
```

---

## Resources

### Bash References

- [Bash Reference Manual](https://www.gnu.org/software/bash/manual/)
- [Advanced Bash-Scripting Guide](https://tldp.org/LDP/abs/html/)
- [Bash Hackers Wiki](https://wiki.bash-hackers.org/)

### Tools

- [ShellCheck](https://www.shellcheck.net/) - Linting
- [shfmt](https://github.com/mvdan/sh) - Formatting
- [bashcov](https://github.com/infertux/bashcov) - Coverage
- [bats](https://github.com/bats-core/bats-core) - Testing framework

### Style Guides

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Bash Style Guide](https://github.com/bahamas10/bash-style-guide)

---

**Version:** 1.1.0
**Last Updated:** 2025-12-24
