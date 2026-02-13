# Coding Conventions

**Analysis Date:** 2026-02-12

## Naming Patterns

**Files:**
- `kebab-case.sh` for all shell scripts (`backup-now.sh`, `cloud-backup.sh`, `database-detector.sh`)
- `test-*.sh` for test files (`test-core-functions.sh`, `test-edge-cases.sh`)
- `install-*.sh` for installers (`install-global.sh`, `install-integrations.sh`)
- `UPPERCASE.md` for project files (`README.md`, `CONTRIBUTING.md`)

**Functions:**
- `lowercase_snake_case` for all functions (`load_backup_config`, `detect_sqlite`, `check_rclone_installed`)
- No module prefix — descriptive verb-based names (`check_drive`, `list_rclone_remotes`, `parse_time_to_epoch`)
- Action verbs: `load_`, `check_`, `detect_`, `list_`, `find_`, `format_`, `parse_`, `init_`, `install_`, `register_`

**Variables:**
- `SCREAMING_SNAKE_CASE` for globals/constants (`FORCE_BACKUP`, `DATABASE_ONLY`, `PROJECT_DIR`, `BACKUP_DIR`)
- `lowercase_snake_case` for locals (`local project_dir`, `local config_file`, `local remote_name`)
- `local` keyword required for all function-scoped variables

**Environment Variables:**
- `SCREAMING_SNAKE_CASE` with descriptive names (`CLAUDECODE_BACKUP_ROOT`, `BACKUP_INTERVAL`, `DRIVE_VERIFICATION_ENABLED`)
- Default values via parameter expansion: `${VAR:-default}`

## Code Style

**Shebang:**
- Standard: `#!/usr/bin/env bash` (preferred for portability)
- Alternative: `#!/bin/bash` (acceptable in test files)

**Error Handling:**
- Required: `set -euo pipefail` in all production scripts
- `-e`: Exit on error
- `-u`: Error on undefined variables
- `-o pipefail`: Propagate pipe errors

**Formatting:**
- 4 spaces indentation (no tabs) — per `CONTRIBUTING.md`
- No enforced line length limit
- Single quotes for literal strings, double quotes for variable expansion

**Bash Version:**
- Minimum: Bash 3.2+ (macOS default)
- No associative arrays (`declare -A`) — Bash 4+ only
- No Bash 4+ parameter expansion (`${var,,}`, `${var^^}`)
- Use `$((var + 1))` not `((var++))` — `set -e` compatibility

## Section Headers

**Major sections:** Decorative equals-sign separators
```bash
# ==============================================================================
# SECTION NAME
# ==============================================================================
```

Found in all major files — provides visual scanning hierarchy in long files.

## File Header Format

**Standard header block** in all library and CLI files:
```bash
#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - [Module Name]
# ==============================================================================
# Version: 2.3.0
# Description: [Multi-line description of purpose]
#
# Usage:
#   source "$(dirname "$0")/../lib/module-name.sh"
#   function_name
#
# Features:
#   - [Feature 1]
#   - [Feature 2]
# ==============================================================================
```

## Function Documentation

**Standard pattern** above each function:
```bash
# Brief description of what function does
# Args: $1 = description (optional, defaults to X)
# Returns: 0 on success, 1 on failure
# Sets: GLOBAL_VAR (if applicable)
function_name() {
    local arg="${1:-default}"
    ...
}
```

## Import/Source Patterns

**Keyword:** `source` (not dot notation `.`)
**Always quoted:** `source "$LIB_DIR/backup-lib.sh"`
**Always validated:**
```bash
if [ -f "$LIB_DIR/backup-lib.sh" ]; then
    source "$LIB_DIR/backup-lib.sh"
else
    echo "Error: Foundation library not found: $LIB_DIR/backup-lib.sh" >&2
    exit 1
fi
```

**Optional libraries** use conditional sourcing without error:
```bash
if [ -f "$LIB_DIR/database-detector.sh" ]; then
    source "$LIB_DIR/database-detector.sh"
fi
```

## Symlink Resolution

**Standard pattern** at top of all CLI scripts:
```bash
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
```

## Error Handling

**Patterns:**
- Exit codes: `return 0` (success), `return 1` (failure)
- Informative stderr: `echo "Error: description" >&2; exit 1`
- Lock-based concurrency: Atomic `mkdir` for lock acquisition
- Stale lock detection: Check if PID in lock file is still running
- Structured error codes: `map_error_to_code()`, `get_error_suggestion()`

## CLI Conventions

**Required flags:** `--help` and `-h` on all scripts (per `CONTRIBUTING.md`)

**Argument parsing:** While loop with case statement:
```bash
while [[ $# -gt 0 ]]; do
    case $1 in
        --flag) VAR=true; shift ;;
        --help|-h) SHOW_HELP=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done
```

**Help format:** `cat <<EOF` with USAGE, OPTIONS, EXAMPLES, EXIT CODES sections.

## Comments

**When to comment:**
- File headers with version, description, usage, features
- Function documentation with args, returns, sets
- Non-obvious logic or workarounds
- Section separators for visual scanning

**ShellCheck directives:**
- `# shellcheck source=../test-framework.sh` to suppress false positives
- Found in test files

**Avoid:**
- Obvious comments (`# increment counter`)
- Commented-out code (delete it)

## Logging

**CLI scripts define local logging functions:**
```bash
log_info()    { [ "$QUIET" = true ] && return; echo "$@"; }
log_success() { [ "$QUIET" = true ] && return; echo -e "${COLOR_GREEN}$@${COLOR_RESET}"; }
log_error()   { echo -e "${COLOR_RED}$@${COLOR_RESET}" >&2; }
log_warn()    { [ "$QUIET" = true ] && return; echo -e "${COLOR_YELLOW}$@${COLOR_RESET}"; }
log_verbose() { [ "$VERBOSE" = false ] && return; echo -e "${COLOR_GRAY}$@${COLOR_RESET}"; }
```

**Pattern:** Errors always go to stderr, info/success respect `--quiet` flag.

## Variable Quoting

- **Always** quote variable expansions: `"$VAR"` (never `$VAR`)
- **Always** quote command substitutions: `"$(command)"`
- Modern syntax preferred: `$(...)` over backticks

---

*Convention analysis: 2026-02-12*
*Update when patterns change*
