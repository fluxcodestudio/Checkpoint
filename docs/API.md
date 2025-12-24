# API Reference

Library function reference for Checkpoint foundation library.

---

## Table of Contents

- [Overview](#overview)
- [lib/backup-lib.sh](#libbackup-libsh)
- [lib/yaml-parser.sh](#libyaml-parsersh)
- [lib/config-validator.sh](#libconfig-validatorsh)
- [lib/ui-helpers.sh](#libui-helperssh)
- [Error Codes](#error-codes)
- [Environment Variables](#environment-variables)
- [Usage Examples](#usage-examples)

---

## Overview

The foundation library provides reusable functions for all backup scripts and commands.

### Loading the Library

```bash
#!/bin/bash
set -euo pipefail

# Source foundation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/backup-lib.sh"

# Library functions now available
load_config
log_info "Configuration loaded"
```

### Library Hierarchy

```
lib/backup-lib.sh          # Core functions (always load this)
├── lib/yaml-parser.sh     # Sourced automatically if needed
├── lib/config-validator.sh # Sourced automatically if needed
└── lib/ui-helpers.sh      # Sourced automatically if needed
```

---

## lib/backup-lib.sh

Core utility functions used across all scripts.

### Configuration Functions

#### `load_config()`

Loads project configuration from YAML or bash config file.

**Signature:**
```bash
load_config [config_file]
```

**Parameters:**
- `config_file` (optional) - Path to config file. Defaults to `.backup-config.yaml` or `.backup-config.sh`

**Returns:**
- `0` - Success
- `1` - Configuration file not found
- `2` - Invalid configuration

**Sets Global Variables:**
```bash
PROJECT_NAME
PROJECT_DIR
BACKUP_DIR
DATABASE_DIR
FILES_DIR
ARCHIVED_DIR
DB_PATH
DB_TYPE
DB_RETENTION_DAYS
FILE_RETENTION_DAYS
# ... and more
```

**Example:**
```bash
load_config
echo "Project: $PROJECT_NAME"
```

**Example with custom path:**
```bash
load_config "/path/to/custom-config.yaml"
```

#### `get_config_value()`

Get a single configuration value.

**Signature:**
```bash
get_config_value <key>
```

**Parameters:**
- `key` - Configuration key in dot notation (e.g., `project.name`)

**Returns:**
- `0` - Success
- `1` - Key not found

**Output:**
- Prints value to stdout

**Example:**
```bash
project_name=$(get_config_value "project.name")
retention=$(get_config_value "retention.database_days")
```

#### `set_config_value()`

Set a configuration value.

**Signature:**
```bash
set_config_value <key> <value>
```

**Parameters:**
- `key` - Configuration key in dot notation
- `value` - New value

**Returns:**
- `0` - Success
- `1` - Invalid key
- `2` - Validation failed

**Example:**
```bash
set_config_value "retention.database_days" "90"
set_config_value "project.name" "NewName"
```

#### `validate_config()`

Validate current configuration.

**Signature:**
```bash
validate_config
```

**Returns:**
- `0` - Configuration valid
- `1` - Validation failed

**Output:**
- Error messages to stderr

**Example:**
```bash
if validate_config; then
    log_success "Configuration valid"
else
    log_error "Configuration invalid"
    exit 1
fi
```

### Logging Functions

#### `log_debug()`

Log debug message (only if debug mode enabled).

**Signature:**
```bash
log_debug <message>
```

**Example:**
```bash
log_debug "Variable value: $var"
```

**Output:**
```
[2025-12-24 14:30:45] [DEBUG] Variable value: test
```

#### `log_info()`

Log informational message.

**Signature:**
```bash
log_info <message>
```

**Example:**
```bash
log_info "Starting backup process"
```

**Output:**
```
[2025-12-24 14:30:45] [INFO] Starting backup process
```

#### `log_warning()`

Log warning message.

**Signature:**
```bash
log_warning <message>
```

**Example:**
```bash
log_warning "Disk space low: $free_space GB"
```

**Output:**
```
[2025-12-24 14:30:45] [WARNING] Disk space low: 5 GB
```

#### `log_error()`

Log error message.

**Signature:**
```bash
log_error <message>
```

**Example:**
```bash
log_error "Database backup failed"
```

**Output:**
```
[2025-12-24 14:30:45] [ERROR] Database backup failed
```

#### `log_success()`

Log success message.

**Signature:**
```bash
log_success <message>
```

**Example:**
```bash
log_success "Backup completed successfully"
```

**Output:**
```
[2025-12-24 14:30:45] [SUCCESS] Backup completed successfully
```

### File System Functions

#### `ensure_directory()`

Create directory if it doesn't exist.

**Signature:**
```bash
ensure_directory <path>
```

**Parameters:**
- `path` - Directory path to create

**Returns:**
- `0` - Success (created or already exists)
- `1` - Failed to create

**Example:**
```bash
ensure_directory "$BACKUP_DIR/databases"
ensure_directory "$BACKUP_DIR/files"
```

#### `safe_copy()`

Copy file with backup of existing file.

**Signature:**
```bash
safe_copy <source> <destination>
```

**Parameters:**
- `source` - Source file path
- `destination` - Destination file path

**Returns:**
- `0` - Success
- `1` - Copy failed

**Behavior:**
- If destination exists, creates backup with timestamp
- Preserves permissions and timestamps

**Example:**
```bash
safe_copy "src/app.py" "backups/files/src/app.py"
# If backups/files/src/app.py exists, it's backed up to:
# backups/archived/src/app.py.20251224_143045
```

#### `calculate_dir_size()`

Calculate total size of directory.

**Signature:**
```bash
calculate_dir_size <directory>
```

**Parameters:**
- `directory` - Directory path

**Returns:**
- `0` - Success
- `1` - Directory doesn't exist

**Output:**
- Size in bytes to stdout

**Example:**
```bash
size_bytes=$(calculate_dir_size "$BACKUP_DIR/databases")
size_mb=$((size_bytes / 1024 / 1024))
echo "Database backups: ${size_mb}MB"
```

#### `format_bytes()`

Format bytes to human-readable size.

**Signature:**
```bash
format_bytes <bytes>
```

**Parameters:**
- `bytes` - Size in bytes

**Output:**
- Human-readable size (e.g., "1.2 GB")

**Example:**
```bash
size=$(calculate_dir_size "$BACKUP_DIR")
formatted=$(format_bytes "$size")
echo "Total backup size: $formatted"
# Output: Total backup size: 2.5 GB
```

### Time Functions

#### `timestamp()`

Get current timestamp in backup format.

**Signature:**
```bash
timestamp
```

**Output:**
- Timestamp in format: `MM.DD.YY - HH:MM`

**Example:**
```bash
ts=$(timestamp)
echo "Backup created: $ts"
# Output: Backup created: 12.24.25 - 14:30
```

#### `timestamp_compact()`

Get compact timestamp for filenames.

**Signature:**
```bash
timestamp_compact
```

**Output:**
- Timestamp in format: `YYYYMMDD_HHMMSS`

**Example:**
```bash
ts=$(timestamp_compact)
backup_file="backup_${ts}.tar.gz"
# backup_20251224_143045.tar.gz
```

#### `time_ago()`

Convert timestamp to "time ago" format.

**Signature:**
```bash
time_ago <unix_timestamp>
```

**Parameters:**
- `unix_timestamp` - Unix timestamp (seconds since epoch)

**Output:**
- Human-readable time ago (e.g., "2 hours ago")

**Example:**
```bash
last_backup=1735059000
ago=$(time_ago "$last_backup")
echo "Last backup: $ago"
# Output: Last backup: 2 hours ago
```

### Lock Functions

#### `acquire_lock()`

Acquire lock for backup operations.

**Signature:**
```bash
acquire_lock <lock_name>
```

**Parameters:**
- `lock_name` - Name of lock (e.g., "backup", "restore")

**Returns:**
- `0` - Lock acquired
- `1` - Lock already held

**Cleanup:**
- Automatically releases lock on script exit (via trap)

**Example:**
```bash
if acquire_lock "backup"; then
    log_info "Lock acquired, starting backup"
    # ... perform backup ...
else
    log_error "Another backup is running"
    exit 1
fi
```

#### `release_lock()`

Release previously acquired lock.

**Signature:**
```bash
release_lock <lock_name>
```

**Parameters:**
- `lock_name` - Name of lock to release

**Example:**
```bash
release_lock "backup"
```

### Validation Functions

#### `is_absolute_path()`

Check if path is absolute.

**Signature:**
```bash
is_absolute_path <path>
```

**Parameters:**
- `path` - Path to check

**Returns:**
- `0` - Path is absolute
- `1` - Path is relative

**Example:**
```bash
if is_absolute_path "$DB_PATH"; then
    log_info "Database path is absolute"
else
    log_error "Database path must be absolute"
    exit 1
fi
```

#### `path_exists()`

Check if path exists.

**Signature:**
```bash
path_exists <path>
```

**Parameters:**
- `path` - Path to check

**Returns:**
- `0` - Path exists
- `1` - Path doesn't exist

**Example:**
```bash
if path_exists "$DB_PATH"; then
    log_info "Database file found"
else
    log_warning "Database file not found"
fi
```

#### `is_writable()`

Check if path is writable.

**Signature:**
```bash
is_writable <path>
```

**Parameters:**
- `path` - Path to check

**Returns:**
- `0` - Path is writable
- `1` - Path is not writable

**Example:**
```bash
if is_writable "$BACKUP_DIR"; then
    log_info "Backup directory writable"
else
    log_error "Cannot write to backup directory"
    exit 1
fi
```

---

## lib/yaml-parser.sh

YAML parsing and manipulation functions.

### `parse_yaml()`

Parse YAML file into shell variables.

**Signature:**
```bash
parse_yaml <yaml_file> [prefix]
```

**Parameters:**
- `yaml_file` - Path to YAML file
- `prefix` (optional) - Variable prefix (default: "yaml_")

**Returns:**
- `0` - Success
- `1` - Parse error

**Sets Variables:**
- Creates variables from YAML structure with prefix

**Example:**

**YAML file:**
```yaml
project:
  name: "MyApp"
  directory: "/path/to/project"
```

**Usage:**
```bash
parse_yaml ".backup-config.yaml" "config_"

echo "$config_project_name"
# Output: MyApp

echo "$config_project_directory"
# Output: /path/to/project
```

### `get_yaml_value()`

Get value from YAML file.

**Signature:**
```bash
get_yaml_value <yaml_file> <key>
```

**Parameters:**
- `yaml_file` - Path to YAML file
- `key` - Key in dot notation (e.g., `project.name`)

**Returns:**
- `0` - Success
- `1` - Key not found

**Output:**
- Value to stdout

**Example:**
```bash
name=$(get_yaml_value ".backup-config.yaml" "project.name")
retention=$(get_yaml_value ".backup-config.yaml" "retention.database_days")
```

### `set_yaml_value()`

Set value in YAML file.

**Signature:**
```bash
set_yaml_value <yaml_file> <key> <value>
```

**Parameters:**
- `yaml_file` - Path to YAML file
- `key` - Key in dot notation
- `value` - New value

**Returns:**
- `0` - Success
- `1` - Update failed

**Example:**
```bash
set_yaml_value ".backup-config.yaml" "retention.database_days" "90"
set_yaml_value ".backup-config.yaml" "project.name" "NewName"
```

### `yaml_to_json()`

Convert YAML to JSON.

**Signature:**
```bash
yaml_to_json <yaml_file>
```

**Parameters:**
- `yaml_file` - Path to YAML file

**Returns:**
- `0` - Success
- `1` - Conversion failed

**Output:**
- JSON to stdout

**Example:**
```bash
yaml_to_json ".backup-config.yaml" > config.json
```

---

## lib/config-validator.sh

Configuration validation functions.

### `validate_required_fields()`

Validate that required fields are present.

**Signature:**
```bash
validate_required_fields
```

**Returns:**
- `0` - All required fields present
- `1` - Missing required fields

**Checks:**
- `project.name`
- `project.directory`
- `backup.directory`

**Example:**
```bash
if validate_required_fields; then
    log_success "Required fields present"
else
    log_error "Missing required fields"
    exit 1
fi
```

### `validate_paths()`

Validate that configured paths exist and are accessible.

**Signature:**
```bash
validate_paths
```

**Returns:**
- `0` - All paths valid
- `1` - Invalid paths found

**Checks:**
- Project directory exists
- Backup directory writable
- Database path exists (if configured)

**Example:**
```bash
if validate_paths; then
    log_success "All paths valid"
else
    log_error "Invalid paths detected"
    exit 1
fi
```

### `validate_retention()`

Validate retention policy values.

**Signature:**
```bash
validate_retention
```

**Returns:**
- `0` - Retention values valid
- `1` - Invalid retention values

**Checks:**
- Database retention: 1-365 days
- File retention: 1-365 days

**Example:**
```bash
if validate_retention; then
    log_success "Retention policy valid"
else
    log_error "Invalid retention values"
    exit 1
fi
```

### `migrate_bash_to_yaml()`

Migrate bash config to YAML.

**Signature:**
```bash
migrate_bash_to_yaml <bash_config> <yaml_config>
```

**Parameters:**
- `bash_config` - Path to `.backup-config.sh`
- `yaml_config` - Path to output `.backup-config.yaml`

**Returns:**
- `0` - Migration successful
- `1` - Migration failed

**Behavior:**
- Backs up original bash config
- Converts values to YAML format
- Validates resulting YAML

**Example:**
```bash
migrate_bash_to_yaml ".backup-config.sh" ".backup-config.yaml"
```

---

## lib/ui-helpers.sh

Terminal UI helper functions.

### `print_header()`

Print formatted header.

**Signature:**
```bash
print_header <title> [subtitle]
```

**Parameters:**
- `title` - Header title
- `subtitle` (optional) - Subtitle

**Example:**
```bash
print_header "Checkpoint" "Status Dashboard"
```

**Output:**
```
┌─────────────────────────────────────────┐
│ Checkpoint              │
│ Status Dashboard                        │
└─────────────────────────────────────────┘
```

### `print_section()`

Print section header.

**Signature:**
```bash
print_section <title>
```

**Parameters:**
- `title` - Section title

**Example:**
```bash
print_section "Backup Statistics"
```

**Output:**
```
Backup Statistics
━━━━━━━━━━━━━━━━━
```

### `print_success()`

Print success message with icon.

**Signature:**
```bash
print_success <message>
```

**Example:**
```bash
print_success "Backup completed"
```

**Output:**
```
✅ Backup completed
```

### `print_error()`

Print error message with icon.

**Signature:**
```bash
print_error <message>
```

**Example:**
```bash
print_error "Database connection failed"
```

**Output:**
```
❌ Database connection failed
```

### `print_warning()`

Print warning message with icon.

**Signature:**
```bash
print_warning <message>
```

**Example:**
```bash
print_warning "Disk space low"
```

**Output:**
```
⚠️  Disk space low
```

### `print_info()`

Print info message with icon.

**Signature:**
```bash
print_info <message>
```

**Example:**
```bash
print_info "Checking for updates..."
```

**Output:**
```
ℹ️  Checking for updates...
```

### `prompt_yes_no()`

Prompt user for yes/no confirmation.

**Signature:**
```bash
prompt_yes_no <question> [default]
```

**Parameters:**
- `question` - Question to ask
- `default` (optional) - Default answer ("y" or "n")

**Returns:**
- `0` - User answered yes
- `1` - User answered no

**Example:**
```bash
if prompt_yes_no "Proceed with cleanup?" "n"; then
    log_info "Proceeding with cleanup"
else
    log_info "Cleanup cancelled"
fi
```

**Output:**
```
Proceed with cleanup? [y/N]:
```

### `select_from_list()`

Interactive list selection.

**Signature:**
```bash
select_from_list <title> <items...>
```

**Parameters:**
- `title` - Selection prompt
- `items` - Array of items to select from

**Returns:**
- `0` - Selection made
- `1` - Cancelled

**Output:**
- Selected item to stdout

**Example:**
```bash
databases=(
    "backup1.db.gz"
    "backup2.db.gz"
    "backup3.db.gz"
)

selected=$(select_from_list "Choose database to restore:" "${databases[@]}")
echo "Restoring: $selected"
```

**Output:**
```
Choose database to restore:
  1) backup1.db.gz
  2) backup2.db.gz
  3) backup3.db.gz

Enter selection [1-3]: 2

Restoring: backup2.db.gz
```

### `progress_bar()`

Display progress bar.

**Signature:**
```bash
progress_bar <current> <total> [message]
```

**Parameters:**
- `current` - Current progress value
- `total` - Total value
- `message` (optional) - Progress message

**Example:**
```bash
total=100
for i in $(seq 1 $total); do
    progress_bar $i $total "Processing files"
    sleep 0.1
done
```

**Output:**
```
[████████████████░░░░░░░░] 75% - Processing files
```

---

## Error Codes

Standard exit codes used across all scripts:

| Code | Constant | Description |
|------|----------|-------------|
| 0 | `EXIT_SUCCESS` | Success |
| 1 | `EXIT_ERROR` | General error |
| 2 | `EXIT_CONFIG_ERROR` | Configuration error |
| 3 | `EXIT_PATH_ERROR` | Path doesn't exist or not accessible |
| 4 | `EXIT_PERMISSION_ERROR` | Permission denied |
| 5 | `EXIT_LOCK_ERROR` | Could not acquire lock |
| 6 | `EXIT_VALIDATION_ERROR` | Validation failed |
| 7 | `EXIT_BACKUP_ERROR` | Backup operation failed |
| 8 | `EXIT_RESTORE_ERROR` | Restore operation failed |
| 9 | `EXIT_DB_ERROR` | Database error |
| 10 | `EXIT_USER_CANCELLED` | User cancelled operation |

**Usage:**
```bash
source lib/backup-lib.sh

if ! validate_config; then
    exit $EXIT_CONFIG_ERROR
fi

if ! acquire_lock "backup"; then
    exit $EXIT_LOCK_ERROR
fi
```

---

## Environment Variables

### Configuration Override

| Variable | Description | Default |
|----------|-------------|---------|
| `BACKUP_CONFIG_FILE` | Path to config file | `.backup-config.yaml` |
| `BACKUP_DEBUG` | Enable debug mode | `false` |
| `BACKUP_LOG_LEVEL` | Logging level | `info` |
| `BACKUP_SUPPRESS_LEGACY_WARNING` | Suppress bash config warning | `false` |

### Runtime Variables

| Variable | Description | Set By |
|----------|-------------|--------|
| `BACKUP_DEV_MODE` | Development mode | Developer |
| `BACKUP_TEST_MODE` | Test mode (skip LaunchAgent) | Test suite |
| `BACKUP_FORCE` | Force backup regardless of changes | User |
| `BACKUP_DRY_RUN` | Preview mode, no changes | User |

**Example:**
```bash
# Enable debug mode
export BACKUP_DEBUG=1
/backup-status

# Use custom config
export BACKUP_CONFIG_FILE=/path/to/custom.yaml
load_config

# Force backup
export BACKUP_FORCE=1
/backup-now
```

---

## Usage Examples

### Example 1: Custom Command with Library

```bash
#!/bin/bash
set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/backup-lib.sh"

# Load configuration
load_config

# Acquire lock
if ! acquire_lock "custom-operation"; then
    log_error "Another operation is running"
    exit $EXIT_LOCK_ERROR
fi

# Validate paths
if ! validate_paths; then
    log_error "Invalid configuration"
    exit $EXIT_CONFIG_ERROR
fi

# Perform operation
log_info "Starting custom operation"

# Check disk space
backup_size=$(calculate_dir_size "$BACKUP_DIR")
formatted_size=$(format_bytes "$backup_size")

log_info "Current backup size: $formatted_size"

# Success
log_success "Operation completed"
exit $EXIT_SUCCESS
```

### Example 2: YAML Configuration Update

```bash
#!/bin/bash
source lib/backup-lib.sh
source lib/yaml-parser.sh

# Update retention policy
set_yaml_value ".backup-config.yaml" "retention.database_days" "90"
set_yaml_value ".backup-config.yaml" "retention.file_days" "180"

# Validate changes
if validate_config; then
    log_success "Configuration updated and validated"
else
    log_error "Invalid configuration"
    exit 1
fi
```

### Example 3: Interactive Script

```bash
#!/bin/bash
source lib/backup-lib.sh
source lib/ui-helpers.sh

print_header "Backup Maintenance"

# Show current status
print_section "Current Status"
backup_size=$(calculate_dir_size "$BACKUP_DIR")
formatted=$(format_bytes "$backup_size")
print_info "Total backup size: $formatted"

# Confirm action
print_section "Cleanup"
if prompt_yes_no "Remove old backups?" "n"; then
    log_info "Starting cleanup..."
    # ... cleanup logic ...
    print_success "Cleanup completed"
else
    print_info "Cleanup cancelled"
fi
```

### Example 4: Error Handling

```bash
#!/bin/bash
set -euo pipefail

source lib/backup-lib.sh

# Cleanup function
cleanup() {
    local exit_code=$?

    release_lock "backup"

    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code: $exit_code"
    fi

    exit $exit_code
}

trap cleanup EXIT

# Main logic
acquire_lock "backup" || exit $EXIT_LOCK_ERROR

load_config || exit $EXIT_CONFIG_ERROR

validate_config || exit $EXIT_VALIDATION_ERROR

# ... perform backup ...

log_success "Backup completed"
exit $EXIT_SUCCESS
```

---

**Version:** 1.1.0
**Last Updated:** 2025-12-24
