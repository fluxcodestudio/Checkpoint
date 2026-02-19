# ClaudeCode Project Backups - Library v1.1.0 Quick Start

## 5-Minute Setup

### Step 1: Deploy the Library (30 seconds)

```bash
cd "/path/to/Checkpoint"

# Backup current library
cp lib/backup-lib.sh lib/backup-lib.sh.v1.0.backup

# Deploy new version
cp lib/backup-lib-v1.1.0.sh lib/backup-lib.sh
```

### Step 2: Run Tests (1 minute)

```bash
# Make test script executable
chmod +x lib/test-library.sh

# Run tests
./lib/test-library.sh
```

Expected: All tests pass ✅

### Step 3: Create YAML Config (2 minutes)

```bash
# Copy template to your project
cp templates/backup-config.yaml .backup-config.yaml

# Edit with your settings
vim .backup-config.yaml
```

Minimal config:
```yaml
locations:
  backup_dir: "backups/"

schedule:
  interval: 3600

database:
  path: null
  type: "none"
```

### Step 4: Test It (1 minute)

```bash
# Test config loading
source lib/backup-lib.sh
config_load
echo "✓ Config loaded successfully"

# Run self-test
backup_lib_selftest
```

### Step 5: Use It (30 seconds)

```bash
# In your scripts
#!/bin/bash
source lib/backup-lib.sh

config_load || log_fatal "Config failed"

backup_dir=$(config_get "locations.backup_dir")
echo "Backup dir: $backup_dir"
```

## Common Tasks

### Get a Config Value

```bash
source lib/backup-lib.sh
config_load

# Get value
value=$(config_get "schedule.interval")

# Get with default
value=$(config_get "custom.key" "default_value")
```

### Set a Config Value

```bash
source lib/backup-lib.sh
config_load

# Set and validate
config_set "schedule.interval" 7200
```

### Validate Configuration

```bash
source lib/backup-lib.sh
config_load

if config_validate; then
    echo "Configuration is valid"
else
    echo "Configuration has errors"
fi
```

### Migrate from Bash to YAML

```bash
source lib/backup-lib.sh

# Load old config
config_load_bash ".backup-config.sh"

# Migrate
config_migrate ".backup-config.sh" ".backup-config.yaml"

# Review YAML file
cat .backup-config.yaml
```

### Safe File Operations

```bash
source lib/backup-lib.sh

# Atomic write (with backup)
atomic_write "$config_file" "$new_content"

# Expands: ~, $VAR, relative paths
full_path=$(expand_path "~/backups")
```

### Logging

```bash
source lib/backup-lib.sh

# Control log level
export BACKUP_LOG_LEVEL=DEBUG  # Show all
export BACKUP_LOG_LEVEL=ERROR  # Errors only

# Log messages
log_debug "Debug message"
log_info "Info message"
log_warn "Warning message"
log_error "Error message"
log_success "Success message"
log_fatal "Fatal error (exits)"
```

## Troubleshooting

### Issue: Config not found

```bash
# Check current directory
ls -la .backup-config.*

# Or specify directory
config_load "/path/to/project"
```

### Issue: YAML parse error

```bash
# Enable debug logging
export BACKUP_LOG_LEVEL=DEBUG
source lib/backup-lib.sh
config_load
```

### Issue: Validation fails

```bash
# See which validation failed
export BACKUP_LOG_LEVEL=DEBUG
config_validate
```

### Issue: Command not found

```bash
# Check dependencies
source lib/backup-lib.sh
check_dependencies
```

## Examples

### Example 1: Simple Script

```bash
#!/bin/bash
# simple-backup.sh

set -euo pipefail
source "$(dirname "$0")/lib/backup-lib.sh"

# Load config
config_load || log_fatal "Failed to load config"

# Get settings
backup_dir=$(expand_path "$(config_get 'locations.backup_dir')")
interval=$(config_get "schedule.interval")

# Log info
log_info "Backup directory: $backup_dir"
log_info "Backup interval: ${interval}s"
log_success "Configuration loaded successfully"
```

### Example 2: Config Management

```bash
#!/bin/bash
# manage-config.sh

source lib/backup-lib.sh

# Load config
config_load

# Show all keys
echo "=== Configuration Keys ==="
config_list_keys | while read key; do
    value=$(config_get "$key")
    echo "  $key = $value"
done

# Validate
echo ""
echo "=== Validation ==="
if config_validate; then
    log_success "Configuration is valid"
else
    log_error "Configuration has errors"
    exit 1
fi
```

### Example 3: Migration Tool

```bash
#!/bin/bash
# migrate-to-yaml.sh

source lib/backup-lib.sh

if [ ! -f ".backup-config.sh" ]; then
    log_error "No .backup-config.sh found"
    exit 1
fi

log_info "Migrating bash config to YAML..."

if config_migrate ".backup-config.sh" ".backup-config.yaml"; then
    log_success "Migration successful!"
    log_info "New file: .backup-config.yaml"
    log_info "Old file: .backup-config.sh (preserved)"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review .backup-config.yaml"
    log_info "  2. Test with: source lib/backup-lib.sh && config_load"
    log_info "  3. Rename .backup-config.sh to .backup-config.sh.backup"
else
    log_error "Migration failed"
    exit 1
fi
```

## Reference

Full documentation in:
- **API Reference**: `lib/README_LIBRARY.md`
- **Implementation Guide**: `lib/IMPLEMENTATION_GUIDE.md`
- **Delivery Summary**: `lib/DELIVERY_SUMMARY.md`

## Getting Help

1. Check documentation: `lib/README_LIBRARY.md`
2. Run self-test: `backup_lib_selftest`
3. Run full tests: `./lib/test-library.sh`
4. Enable debug logging: `export BACKUP_LOG_LEVEL=DEBUG`

## Quick Reference Card

```bash
# Load library
source lib/backup-lib.sh

# Load config
config_load [dir]

# Get value
value=$(config_get "key" [default])

# Set value
config_set "key" "value"

# Validate
config_validate

# Check if key exists
config_has "key"

# List all keys
config_list_keys [prefix]

# Expand path
path=$(expand_path "~/path")

# Format bytes
size=$(format_bytes 1048576)  # 1MB

# Check dependencies
check_dependencies

# Safe write
atomic_write "file" "content"

# Logging
log_debug|info|warn|error|success|fatal "message"
```

---

**Ready to use!** The library is production-ready and fully documented.
