# Coding Conventions

**Analysis Date:** 2026-01-10

## Naming Patterns

**Files:**
- kebab-case.sh for all scripts (`backup-status.sh`, `backup-restore.sh`)
- test-feature-name.sh for tests (`test-backup-restore-workflow.sh`)
- SCREAMING-KEBAB.md for documentation (`PROJECT-STRUCTURE.md`, `TESTING.md`)

**Functions:**
- snake_case for all functions (`load_backup_config`, `check_drive`, `send_notification`)
- verb_object or object_verb pattern (`acquire_backup_lock`, `copy_with_retry`)
- check_* for validation (`check_drive`, `check_daemon_status`)
- init_* or load_* for setup (`init_backup_state`, `load_backup_config`)

**Variables:**
- SCREAMING_SNAKE_CASE for constants/config (`PROJECT_DIR`, `BACKUP_INTERVAL`, `DB_TYPE`)
- snake_case for local variables (`config_file`, `db_file`, `database`)
- No underscore prefix for private (bash has no private scope)

**Types:**
- N/A (bash has no type system)

## Code Style

**Formatting:**
- 4-space indentation (no tabs)
- No strict line length limit (pragmatic approach)
- Double quotes for strings with variables, single quotes for literals
- Semicolons at end of case statements

**Shebang:**
- `#!/usr/bin/env bash` (preferred)
- `#!/bin/bash` (acceptable)

**Error Handling:**
- `set -euo pipefail` standard in all scripts
- Example from `bin/backup-restore.sh`:
  ```bash
  set -euo pipefail
  ```

**Linting:**
- ShellCheck comments: `# shellcheck source=../file.sh`
- Syntax validation: `bash -n script.sh`
- All scripts must pass `bash -n` check

## Import Organization

**Source Order:**
1. Resolve script location (symlink handling)
2. Define LIB_DIR
3. Source foundation library (backup-lib.sh)
4. Source feature-specific libraries
5. Source configuration

**Pattern from `bin/backup-now.sh`:**
```bash
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/backup-lib.sh"
```

**Path Aliases:**
- None (bash doesn't support path aliases)
- Use variable references: `$LIB_DIR`, `$PROJECT_DIR`, `$BACKUP_DIR`

## Error Handling

**Patterns:**
- Check and exit early with clear message
- Use return codes (0 = success, non-zero = failure)
- Log to stderr for errors

**Example from `bin/backup-now.sh`:**
```bash
if [ -f "$LIB_DIR/backup-lib.sh" ]; then
    source "$LIB_DIR/backup-lib.sh"
else
    echo "Error: Foundation library not found: $LIB_DIR/backup-lib.sh" >&2
    exit 1
fi
```

**Exit Codes:**
- 0: Success
- 1: Configuration/general error
- 2: Operation failure

## Logging

**Framework:**
- Console output via echo
- Color helpers: `color_red`, `color_green`, `color_yellow`
- Log files: `$BACKUP_DIR/backup.log`

**Patterns:**
- Normal output to stdout
- Errors to stderr (`>&2`)
- Structured JSON for machine-readable state
- No console.log (bash uses echo)

## Comments

**Header Comments (required for all scripts):**
```bash
#!/bin/bash
# Checkpoint - [Feature Name]
# [Brief description]
#
# Usage:
#   command [options]
#
# Features:
#   - Feature 1
```

**Section Separators:**
```bash
# ==============================================================================
# SECTION NAME
# ==============================================================================
```

**Function Documentation:**
```bash
# Find all SQLite database files in project
# Returns: Array of absolute paths to .db, .sqlite, .sqlite3 files
detect_sqlite() {
```

**Inline Comments:**
- Sparse, reserved for complex logic
- Explain "why" not "what"

**TODO Comments:**
- Format: `# TODO: description`
- Example from `lib/backup-lib.sh`:
  ```bash
  # TODO: Implement bash 3.2-compatible config schema
  ```

## Function Design

**Size:**
- No strict limit, but extract helpers for complex logic
- One level of abstraction per function

**Parameters:**
- Positional: `$1`, `$2`, etc.
- Named via local variables at start:
  ```bash
  function_name() {
      local message="$1"
      local default="$2"
  }
  ```

**Return Values:**
- Use return codes for success/failure
- Use echo for value output
- Capture with command substitution: `result=$(function_name)`

## Module Design

**Exports:**
- All functions are global once sourced
- No module system (bash limitation)
- Prefix with feature name if needed

**Library Pattern:**
- Libraries contain functions only (no execution)
- Guard against re-sourcing: `[[ -n "${_BACKUP_LIB_LOADED:-}" ]] && return`
- Source other libraries at top

## Bash Compatibility

**Minimum Version:** bash 3.2+ (macOS default)

**Forbidden Patterns (bash 4.0+):**
- `declare -A` (associative arrays)
- `${var,,}`, `${var^^}` (case transformation)
- `[[ -v var ]]` (variable existence check)

**Reference:** `CONTRIBUTING.md` (lines 30-34)

---

*Convention analysis: 2026-01-10*
*Update when patterns change*
