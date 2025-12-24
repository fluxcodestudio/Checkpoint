# ClaudeCode Project Backups - Core Library Documentation

## Overview

`lib/backup-lib.sh` is the foundation library that provides configuration management, YAML parsing, validation, and utilities for the entire backup system.

## Version

- **Current Version**: 1.1.0
- **Compatibility**: 1.0.0+

## Key Features

### 1. YAML Configuration System

The library implements a pure bash YAML parser with no external dependencies:

- Parses nested YAML structures (objects, arrays, scalars)
- Converts YAML to bash associative arrays
- Handles boolean values (`true`/`false`, `yes`/`no`, `on`/`off`)
- Handles null values
- Supports comments and empty lines

### 2. Configuration Schema

Complete schema definition with:
- **locations**: backup directories, drive markers
- **schedule**: intervals, daemon/hook settings
- **retention**: time/count/size-based policies for databases and files
- **database**: path and type configuration
- **patterns**: include/exclude file patterns
- **git**: auto-commit settings
- **advanced**: compression, symlink handling, permissions

### 3. Configuration Functions

#### config_load([search_dir])
Loads configuration from project directory. Auto-detects YAML or bash format.

```bash
config_load "/path/to/project"
```

#### config_get(key, [default])
Retrieves configuration value with fallback to defaults.

```bash
backup_dir=$(config_get "locations.backup_dir")
interval=$(config_get "schedule.interval" 3600)
```

#### config_set(key, value)
Sets configuration value with validation.

```bash
config_set "schedule.interval" 7200
```

#### config_validate()
Validates entire configuration against schema.

```bash
if config_validate; then
    echo "Configuration is valid"
fi
```

#### config_migrate([bash_file], [yaml_file])
Migrates legacy .backup-config.sh to YAML format.

```bash
config_migrate ".backup-config.sh" ".backup-config.yaml"
```

### 4. Validation Functions

Type-safe validation for all configuration values:

- `validate_path(path, [must_exist])` - Path validation
- `validate_number(value, [min], [max])` - Numeric range validation
- `validate_boolean(value)` - Boolean validation
- `validate_enum(value, valid_values...)` - Enum validation

### 5. Logging System

Structured logging with color support:

- `log_debug(message)` - Debug messages (hidden by default)
- `log_info(message)` - Informational messages
- `log_warn(message)` - Warnings
- `log_error(message)` - Errors
- `log_success(message)` - Success messages (green checkmark)
- `log_fatal(message)` - Fatal errors (exits)

Control logging:
```bash
export BACKUP_LOG_LEVEL=DEBUG    # Show all logs
export BACKUP_LOG_COLORS=false   # Disable colors
```

### 6. Safe File Operations

Atomic operations with automatic rollback:

- `atomic_write(file, content)` - Atomic file writes with backup
- `backup_file(file, [suffix])` - Create file backup
- `rollback_file(file)` - Restore from backup

### 7. Utility Functions

Cross-platform helpers:

- `is_macos()` / `is_linux()` - Platform detection
- `format_bytes(bytes)` - Human-readable file sizes
- `expand_path(path)` - Expand variables and relative paths
- `command_exists(cmd)` - Check if command available
- `check_dependencies()` - Verify required commands
- `find_project_root([dir])` - Locate project root

## Usage Examples

### Basic Usage

```bash
#!/bin/bash
# Source the library
source "$(dirname "$0")/../lib/backup-lib.sh"

# Load configuration
if ! config_load; then
    log_fatal "Failed to load configuration"
fi

# Get configuration values
backup_dir=$(config_get "locations.backup_dir")
db_path=$(config_get "database.path")
interval=$(config_get "schedule.interval")

log_info "Backup directory: $backup_dir"
log_info "Backup interval: ${interval}s"
```

### YAML Configuration Example

```yaml
# .backup-config.yaml
locations:
  backup_dir: "backups/"
  database_dir: "backups/databases"
  files_dir: "backups/files"
  archived_dir: "backups/archived"
  drive_marker: null

schedule:
  interval: 3600
  daemon_enabled: true
  hooks_enabled: true
  session_idle_threshold: 600

retention:
  database:
    time_based: 30
    count_based: null
    size_based: null
    never_delete: false
  files:
    time_based: 60
    count_based: null
    size_based: null
    never_delete: false

database:
  path: "$HOME/.myapp/data.db"
  type: "sqlite"

patterns:
  include:
    env_files: true
    credentials: true
    ide_settings: true
    local_notes: true
    local_databases: true
  exclude: []

git:
  auto_commit: false
  commit_message: "Auto-backup: $(date '+%Y-%m-%d %H:%M')"

advanced:
  parallel_compression: true
  compression_level: 6
  symlink_handling: "follow"
  permissions_preserve: true
```

### Migration Example

```bash
#!/bin/bash
source lib/backup-lib.sh

# Load old bash config
config_load_bash ".backup-config.sh"

# Migrate to YAML
if config_migrate ".backup-config.sh" ".backup-config.yaml"; then
    log_success "Migration complete!"
    log_info "Review .backup-config.yaml"
    log_info "Old config preserved as .backup-config.sh"
fi
```

### Custom Command Example

```bash
#!/bin/bash
# Custom backup command using the library
source "$(dirname "$0")/../lib/backup-lib.sh"

# Load config
config_load

# Check dependencies
if ! check_dependencies; then
    log_fatal "Missing required dependencies"
fi

# Get config values
backup_dir=$(expand_path "$(config_get 'locations.backup_dir')")
db_type=$(config_get "database.type")

# Perform backup
log_info "Starting backup..."
# ... backup logic ...
log_success "Backup complete!"
```

## Configuration Schema Reference

### locations.*
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `locations.backup_dir` | path | `backups/` | Main backup directory |
| `locations.database_dir` | path | `backups/databases` | Database backups |
| `locations.files_dir` | path | `backups/files` | Current file backups |
| `locations.archived_dir` | path | `backups/archived` | Archived versions |
| `locations.drive_marker` | path | `""` | Drive verification file |

### schedule.*
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `schedule.interval` | number | `3600` | Backup interval (seconds) |
| `schedule.daemon_enabled` | boolean | `true` | Enable daemon backups |
| `schedule.hooks_enabled` | boolean | `true` | Enable hook backups |
| `schedule.session_idle_threshold` | number | `600` | Session idle time (seconds) |

### retention.database.*
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `retention.database.time_based` | number | `30` | Delete after N days |
| `retention.database.count_based` | number | `null` | Keep N most recent |
| `retention.database.size_based` | number | `null` | Delete when > N MB |
| `retention.database.never_delete` | boolean | `false` | Never delete backups |

### retention.files.*
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `retention.files.time_based` | number | `60` | Delete after N days |
| `retention.files.count_based` | number | `null` | Keep N most recent |
| `retention.files.size_based` | number | `null` | Delete when > N MB |
| `retention.files.never_delete` | boolean | `false` | Never delete archives |

### database.*
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `database.path` | path | `""` | Database file path |
| `database.type` | enum | `none` | Type: `none`, `sqlite` |

### patterns.include.*
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `patterns.include.env_files` | boolean | `true` | Backup .env files |
| `patterns.include.credentials` | boolean | `true` | Backup credentials |
| `patterns.include.ide_settings` | boolean | `true` | Backup IDE settings |
| `patterns.include.local_notes` | boolean | `true` | Backup local notes |
| `patterns.include.local_databases` | boolean | `true` | Backup local databases |

### git.*
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `git.auto_commit` | boolean | `false` | Auto-commit after backup |
| `git.commit_message` | string | Auto-backup: ... | Commit message template |

### advanced.*
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `advanced.parallel_compression` | boolean | `true` | Use parallel compression |
| `advanced.compression_level` | number | `6` | Compression level (1-9) |
| `advanced.symlink_handling` | enum | `follow` | `follow`, `preserve`, `skip` |
| `advanced.permissions_preserve` | boolean | `true` | Preserve permissions |

## Testing

Run the library self-test:

```bash
source lib/backup-lib.sh
backup_lib_selftest
```

Expected output:
```
=== Backup Library Self-Test ===
Version: 1.1.0

Test 1: Schema initialization... PASS (40 defaults loaded)
Test 2: Validation functions... PASS
Test 3: Path expansion... PASS
Test 4: File size formatting... PASS
Test 5: Platform detection... PASS (Darwin)

Results: 5 passed, 0 failed
All tests passed!
```

## Error Handling

The library uses bash strict mode (`set -euo pipefail`) and comprehensive error handling:

- All functions return proper exit codes (0 = success, 1 = failure)
- Errors are logged with context and suggestions
- Atomic operations automatically rollback on failure
- Configuration validation provides specific error messages

Example error handling:
```bash
if ! config_load "$project_dir"; then
    log_error "Configuration load failed"
    exit 1
fi

backup_dir=$(config_get "locations.backup_dir") || {
    log_fatal "Backup directory not configured"
}
```

## Backward Compatibility

The library maintains full backward compatibility with the existing bash configuration format:

- Automatically detects and loads `.backup-config.sh`
- Maps old variable names to new YAML structure
- Provides migration path to YAML
- All existing scripts continue to work

## Dependencies

Required commands (checked automatically):
- `git` - Version control
- `sqlite3` - Database backups
- `gzip` - Compression

Platform support:
- macOS (darwin)
- Linux (all distributions)

## Best Practices

1. **Always validate after loading**:
   ```bash
   config_load && config_validate
   ```

2. **Use expand_path for file paths**:
   ```bash
   backup_dir=$(expand_path "$(config_get 'locations.backup_dir')")
   ```

3. **Check dependencies early**:
   ```bash
   check_dependencies || log_fatal "Missing dependencies"
   ```

4. **Use atomic operations for critical files**:
   ```bash
   atomic_write "$config_file" "$new_content"
   ```

5. **Enable debug logging for troubleshooting**:
   ```bash
   export BACKUP_LOG_LEVEL=DEBUG
   ```

## Future Enhancements

Planned features for v1.2.0:
- JSON configuration support
- Configuration encryption
- Remote configuration sources
- Schema versioning and migrations
- Configuration templates
- Interactive configuration wizard

## Support

For issues, questions, or contributions, see the project README.
