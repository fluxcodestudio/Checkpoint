# Phase 17: Error Logging Overhaul - Research

**Researched:** 2026-02-13
**Domain:** Bash structured logging, log rotation, debug mode for a large shell project (~90 scripts)
**Confidence:** HIGH

<research_summary>
## Summary

Researched bash structured logging patterns for replacing 932 `2>/dev/null` occurrences across 87 shell scripts with structured debug logging. The project already has partial logging infrastructure (`backup_log()` in output.sh, `log_info/error/warn/verbose` in backup-now.sh, `BACKUP_DEBUG` env var) but it's scattered and inconsistent.

The standard approach is a centralized logging module with numeric log levels (ERROR=0 through TRACE=4), threshold-based filtering via integer comparison, and file descriptor-based output for performance. Not all `2>/dev/null` should be replaced — command existence checks and platform fallbacks are idiomatic and should remain. The 932 occurrences fall into ~6 distinct categories requiring different treatment.

**Primary recommendation:** Create `lib/core/logging.sh` as a unified logging module. Use numeric log levels with `(( LOG_LEVEL >= level ))` threshold checks. Categorize all `2>/dev/null` into "keep" (idiomatic) vs "replace" (hiding diagnostic info). Add size-based log rotation. Expose debug toggle via `CHECKPOINT_LOG_LEVEL` env var, `--debug` CLI flag, and `SIGUSR1` runtime toggle.
</research_summary>

<standard_stack>
## Standard Stack

### Core (Build Custom — No External Library)

The project should NOT adopt an external bash logging library. Rationale:
1. Existing output infrastructure (`lib/core/output.sh`) already handles colors, JSON, and basic logging
2. The project has an established module system (`lib/core/`, `lib/ops/`, etc.)
3. External libraries add dependency for what's a ~100-line module
4. Integration with existing `BACKUP_DEBUG`, `VERBOSE`, and config system requires custom code anyway

| Component | Approach | Purpose | Why This Way |
|-----------|----------|---------|-------------|
| `lib/core/logging.sh` | New module | Centralized log levels, rotation, FD management | Integrates with existing module loader |
| Numeric log levels | `ERROR=0, WARN=1, INFO=2, DEBUG=3, TRACE=4` | Threshold filtering | Integer comparison is essentially free |
| FD-based output | `exec N>>$LOG_FILE` at init | Write performance | Open once, write many — avoids reopening file per message |
| Size-based rotation | Custom function | Prevent log bloat | Simple, no external dependency, cross-platform |

### Supporting (Existing Infrastructure to Leverage)

| Component | Location | What It Does | Integration Point |
|-----------|----------|-------------|-------------------|
| `backup_log()` | `lib/core/output.sh:96-119` | Timestamped log to file+stdout | Replace with new logging functions |
| `LOG_FILE` / `FALLBACK_LOG` | `lib/core/config.sh` | Log file paths | Reuse existing config |
| `BACKUP_DEBUG` | Various | Debug flag | Replace with `CHECKPOINT_LOG_LEVEL` |
| `VERBOSE` flag | `bin/backup-now.sh:34` | Verbose output toggle | Map to `LOG_LEVEL_DEBUG` |
| Error codes | `lib/core/error-codes.sh` | Structured error catalog | Log errors with their codes |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom module | bash_logger (D4rth-C0d3r) | Full-featured but adds external dependency; doesn't integrate with existing config |
| Custom module | b-log (idelsink) | Template system is nice but overkill; adds complexity |
| File logging | syslog via `logger` | macOS Unified Log degrades tag support; fork per call; less control |
| Custom rotation | newsyslog (macOS) | Requires root config; not portable to Linux; 30-min granularity |
| Custom rotation | logrotate (Linux) | Not available on macOS without Homebrew |
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Module Structure
```
lib/
└── core/
    ├── output.sh          # Existing: colors, json helpers (KEEP)
    ├── logging.sh         # NEW: log levels, rotation, FD management
    ├── error-codes.sh     # Existing: error catalog (KEEP)
    └── config.sh          # Existing: add CHECKPOINT_LOG_LEVEL config
```

### Pattern 1: Numeric Log Level with Threshold Check
**What:** Industry-standard log level pattern using integer comparison
**When to use:** Every log message in the project
**Example:**
```bash
# Constants
readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARN=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_DEBUG=3
readonly LOG_LEVEL_TRACE=4

# Current level (from config/env/flag)
CHECKPOINT_LOG_LEVEL="${CHECKPOINT_LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Core log function
_log() {
    local level=$1 level_name=$2
    shift 2
    if (( CHECKPOINT_LOG_LEVEL >= level )); then
        printf '[%s] [%-5s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level_name" "$*" >> "$LOG_FILE"
    fi
}

# Convenience functions
log_error() { _log $LOG_LEVEL_ERROR "ERROR" "$@"; }
log_warn()  { _log $LOG_LEVEL_WARN  "WARN"  "$@"; }
log_info()  { _log $LOG_LEVEL_INFO  "INFO"  "$@"; }
log_debug() { _log $LOG_LEVEL_DEBUG "DEBUG" "$@"; }
log_trace() { _log $LOG_LEVEL_TRACE "TRACE" "$@"; }
```

### Pattern 2: Stderr Capture to Debug Log
**What:** Redirect command stderr to debug log instead of /dev/null
**When to use:** Replacing `command 2>/dev/null` where stderr has diagnostic value
**Example:**
```bash
# BEFORE: silences potentially useful error info
rsync -a "$src" "$dst" 2>/dev/null

# AFTER: captures to debug log (only written if DEBUG level)
if ! output=$(rsync -a "$src" "$dst" 2>&1); then
    log_debug "rsync failed: $output"
fi

# AFTER (simpler for fire-and-forget):
rsync -a "$src" "$dst" 2> >(log_debug_pipe "rsync")
```

### Pattern 3: Debug Mode Toggle
**What:** Multiple ways to enable debug logging
**When to use:** Troubleshooting backup issues
**Example:**
```bash
# Via environment variable
CHECKPOINT_LOG_LEVEL=3 checkpoint backup

# Via CLI flag
checkpoint backup --debug
checkpoint backup --trace

# Via config file (.backup-config.sh)
CHECKPOINT_LOG_LEVEL=3

# Runtime toggle via signal (for daemon)
kill -USR1 $(cat ~/.claudecode-backups/locks/daemon.pid)
```

### Pattern 4: Categorized 2>/dev/null Replacement
**What:** Not all `2>/dev/null` should be replaced — categorize first
**When to use:** During the migration of 932 occurrences

**Category A: KEEP — Idiomatic bash (estimated ~200 occurrences)**
```bash
# Command existence checks — KEEP
command -v rclone 2>/dev/null
type persist_manifest_json &>/dev/null
hash git 2>/dev/null

# Read with fallback — KEEP
lock_pid=$(cat "$file" 2>/dev/null || echo "")

# Platform detection — KEEP
date +%s%3N 2>/dev/null || date +%s
```

**Category B: REPLACE — Hiding diagnostic stderr (~400+ occurrences)**
```bash
# BEFORE: git errors silenced
git diff --name-only 2>/dev/null

# AFTER: errors captured for debugging
git diff --name-only 2> >(log_debug_pipe "git-diff") || true

# BEFORE: rsync errors silenced
rsync -a "$src" "$dst" 2>/dev/null

# AFTER: errors captured
if ! rsync_out=$(rsync -a "$src" "$dst" 2>&1); then
    log_debug "rsync: $rsync_out"
fi
```

**Category C: REPLACE WITH LOG — Silencing expected but useful errors (~300+ occurrences)**
```bash
# BEFORE: launchctl errors silenced
launchctl list "$SERVICE" 2>/dev/null

# AFTER: log the actual status
if ! svc_out=$(launchctl list "$SERVICE" 2>&1); then
    log_debug "Service $SERVICE not loaded: $svc_out"
fi
```

### Anti-Patterns to Avoid
- **Replacing ALL 2>/dev/null blindly:** Command existence checks should keep `2>/dev/null`
- **Using `set -x` as logging:** Generates extreme noise (~400 lines vs ~30 curated); only for deep debugging
- **Per-message `tee`:** Each `tee` invocation forks a subprocess; use FD-based output instead
- **JSON logging without consumer:** Don't add JSON structured logging unless a log aggregator consumes it
- **Spawning `date` in hot loops:** On macOS (bash 3.2), `$(date ...)` forks a subprocess; cache timestamps in tight loops
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Timestamp formatting | Custom date parsing | `date '+%Y-%m-%d %H:%M:%S'` (or `printf '%()T'` on bash 5+) | Edge cases with locales, timezones |
| Log level filtering | if/elif chains | Numeric comparison `(( LEVEL >= threshold ))` | Integer comparison is a bash builtin, essentially free |
| Cross-platform stat | Inline `stat` flags | Existing `lib/platform/compat.sh` `get_file_size()` | Already solved in codebase |
| Concurrent log writes | Custom locking | POSIX atomic writes (< 4096 bytes/PIPE_BUF) | OS guarantees atomicity for short writes |
| Complex log rotation | Multi-feature rotation daemon | Simple size-check + rotate function | Backups run periodically, not continuously; simple rotation suffices |

**Key insight:** Bash logging is a solved problem at the pattern level. The complexity here is in the *migration* (categorizing 932 occurrences) not in the *implementation* (which is ~100-150 lines). Don't over-engineer the logging module — spend the effort on correct categorization of what to replace.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Replacing ALL 2>/dev/null Blindly
**What goes wrong:** Breaking command existence checks, platform detection, and intentional fallbacks
**Why it happens:** Treating all 932 occurrences as the same pattern
**How to avoid:** Categorize into KEEP (idiomatic) vs REPLACE (hiding diagnostics) vs REDIRECT (capture to log) before making changes
**Warning signs:** Tests failing on commands like `command -v`, `type`, `hash`, platform fallback `|| fallback`

### Pitfall 2: Performance Regression from Excessive Logging
**What goes wrong:** Backup operations slow down from subprocess spawning per log message
**Why it happens:** Using `$(date ...)` in every log call, or `tee` for dual output, or subshell captures in hot paths
**How to avoid:** Use `>> "$LOG_FILE"` direct append (not tee); avoid date in tight loops; integer comparison for level checks is free
**Warning signs:** Backup duration increases noticeably; `time` shows user+sys time increase

### Pitfall 3: macOS Bash 3.2 Compatibility
**What goes wrong:** Script fails on macOS default `/bin/bash` (3.2.57)
**Why it happens:** Using bash 4.2+ features like `printf '%(%Y-%m-%d)T'`, associative arrays, `${var,,}` lowercase
**How to avoid:** Check the project's shebang lines — if `#!/bin/bash`, stick to bash 3.2 features; if `#!/usr/bin/env bash` with Homebrew bash available, document the requirement
**Warning signs:** Syntax errors on macOS; `bad substitution` errors

### Pitfall 4: Log File Bloat from Debug Mode Left On
**What goes wrong:** Log files grow to gigabytes, fill disk
**Why it happens:** User enables `--debug` for troubleshooting, forgets to disable; daemon runs indefinitely in debug mode
**How to avoid:** Size-based log rotation (e.g., 10MB max, 5 rotated files = 50MB cap); auto-revert debug mode after configurable timeout; log rotation runs at backup start
**Warning signs:** Disk space warnings; slow `cat` on log files

### Pitfall 5: Breaking Existing Logging Integration
**What goes wrong:** Dashboard, status commands, or error display stops working
**Why it happens:** Changing `backup_log()` signature or behavior that other modules depend on
**How to avoid:** Keep backward compatibility during migration — new module supplements, doesn't immediately replace; deprecate old functions gradually
**Warning signs:** Dashboard shows no recent activity; `checkpoint status` shows stale data

### Pitfall 6: Interleaved Log Lines from Concurrent Backups
**What goes wrong:** Log entries from multiple simultaneous backup operations interleave, making logs unreadable
**Why it happens:** Multiple backup-now.sh processes writing to the same log file
**How to avoid:** Include backup ID or PID in log prefix; keep PIPE_BUF-sized writes (< 4096 bytes) for atomic append; consider per-operation log files
**Warning signs:** Log entries with mixed project names; timestamps out of order
</common_pitfalls>

<code_examples>
## Code Examples

### Core Logging Module (Recommended Implementation)
```bash
# lib/core/logging.sh — Structured logging with levels and rotation
# Source: Synthesized from community best practices

# Log levels (numeric for fast comparison)
readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARN=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_DEBUG=3
readonly LOG_LEVEL_TRACE=4

# Level names for output
readonly LOG_LEVEL_NAMES=("ERROR" "WARN " "INFO " "DEBUG" "TRACE")

# Default: INFO level
CHECKPOINT_LOG_LEVEL="${CHECKPOINT_LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Initialize logging — call once at script start
init_logging() {
    local log_file="${1:-${LOG_FILE:-/tmp/checkpoint.log}}"
    local max_size="${2:-10485760}"  # 10MB default

    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

    # Rotate if needed before opening
    _rotate_log "$log_file" "$max_size"

    # Store for module use
    _CHECKPOINT_LOG_FILE="$log_file"
}

# Core log function — fast path with integer comparison
_log() {
    local level=$1 level_name=$2
    shift 2
    if (( CHECKPOINT_LOG_LEVEL >= level )); then
        printf '[%s] [%s] [%s] %s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$level_name" \
            "${_CHECKPOINT_LOG_CONTEXT:-main}" \
            "$*" >> "${_CHECKPOINT_LOG_FILE:-/dev/null}" 2>/dev/null || true
    fi
}

# Convenience functions
log_error() { _log $LOG_LEVEL_ERROR "ERROR" "$@"; }
log_warn()  { _log $LOG_LEVEL_WARN  "WARN " "$@"; }
log_info()  { _log $LOG_LEVEL_INFO  "INFO " "$@"; }
log_debug() { _log $LOG_LEVEL_DEBUG "DEBUG" "$@"; }
log_trace() { _log $LOG_LEVEL_TRACE "TRACE" "$@"; }

# Set context label (e.g., "backup-now", "daemon", "restore")
log_set_context() { _CHECKPOINT_LOG_CONTEXT="$1"; }

# Size-based log rotation
_rotate_log() {
    local log_file="$1" max_size="$2" max_files=5
    [[ -f "$log_file" ]] || return 0

    local size
    size=$(get_file_size "$log_file" 2>/dev/null) || return 0

    if (( size > max_size )); then
        local i
        for ((i=max_files-1; i>=1; i--)); do
            [[ -f "${log_file}.$i" ]] && mv "${log_file}.$i" "${log_file}.$((i+1))"
        done
        mv "$log_file" "${log_file}.1"
        : > "$log_file"
    fi
}
```

### Debug Mode CLI Integration
```bash
# In bin/ scripts — parse debug flags
parse_log_flags() {
    for arg in "$@"; do
        case "$arg" in
            --debug) CHECKPOINT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
            --trace) CHECKPOINT_LOG_LEVEL=$LOG_LEVEL_TRACE ;;
            --quiet) CHECKPOINT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        esac
    done
}
```

### Stderr Capture Pattern
```bash
# Replace: command 2>/dev/null
# With: capture stderr to debug log

# Pattern for commands where failure is handled
if ! cmd_output=$(some_command 2>&1); then
    log_debug "some_command failed: $cmd_output"
    # ... handle failure ...
fi

# Pattern for commands where failure is ignored but info is useful
some_command 2>&1 | while IFS= read -r line; do
    log_debug "some_command: $line"
done || true
```

### Runtime Debug Toggle for Daemon
```bash
# In backup-daemon.sh
trap '_toggle_debug_level' USR1

_toggle_debug_level() {
    if (( CHECKPOINT_LOG_LEVEL >= LOG_LEVEL_DEBUG )); then
        CHECKPOINT_LOG_LEVEL=$LOG_LEVEL_INFO
        log_info "Debug logging disabled via SIGUSR1"
    else
        CHECKPOINT_LOG_LEVEL=$LOG_LEVEL_DEBUG
        log_info "Debug logging enabled via SIGUSR1"
    fi
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `echo` for logging | `printf` with format strings | Long-standing | Better portability, no escape sequence issues |
| `2>/dev/null` everywhere | Conditional debug logging | Best practice | Diagnostic info preserved when needed |
| `$(date ...)` per message | `printf '%(%Y-%m-%d)T'` (bash 5+) | bash 4.2+ | No subprocess per timestamp |
| `tee -a` for dual output | FD-based writing | Best practice | No fork per message |
| Global `set -x` debugging | `BASH_XTRACEFD` to separate FD | bash 4.1+ | Trace output isolated from normal output |
| Manual log management | Size-based rotation in-script | Common pattern | Prevents log bloat without external tools |

**New tools/patterns to consider:**
- **`printf '%()T'` builtin:** Eliminates subprocess for timestamps, but requires bash 4.2+ (not available on macOS default bash 3.2)
- **`BASH_XTRACEFD`:** Direct execution trace to a separate file descriptor (bash 4.1+), useful for deep debugging mode
- **`$EPOCHSECONDS`:** Bash 5.0+ provides epoch seconds as a variable — no subprocess needed for Unix timestamps

**Deprecated/outdated:**
- **log4bash (fredpalmer):** Original bash logging library, now superseded by newer alternatives with better features
- **Relying on syslog on macOS:** Apple's Unified Logging system degrades `logger` tag support; file-based logging preferred
- **Global `set -x`:** Too noisy for production; use targeted `BASH_XTRACEFD` instead
</sota_updates>

<open_questions>
## Open Questions

1. **macOS bash version policy**
   - What we know: macOS default `/bin/bash` is 3.2.57; Homebrew provides bash 5.2+; `printf '%()T'` requires bash 4.2+
   - What's unclear: Does the project target `/bin/bash` 3.2 compatibility or can it require newer bash?
   - Recommendation: Check project shebangs; if `#!/bin/bash`, stick to 3.2 features and use `$(date ...)` for timestamps. The performance difference is negligible for a backup tool (not a hot loop).

2. **Log file location strategy**
   - What we know: Current `LOG_FILE` is `${BACKUP_DIR}/backup.log` (per-project); `FALLBACK_LOG` is in `~/.claudecode-backups/logs/`
   - What's unclear: Should debug logs go to the same file or a separate debug log? Should daemon logs be separate from backup-now logs?
   - Recommendation: Single log file per project with level prefix (simple, grepable). Daemon gets its own log file. This matches the existing pattern.

3. **Migration scope per plan**
   - What we know: 932 occurrences across 87 files; needs categorization before replacement
   - What's unclear: How many plans should this be split into?
   - Recommendation: Plan 1 = logging module + migration of core scripts (backup-now, daemon). Plan 2 = migrate remaining lib/ files. Plan 3 = migrate bin/ scripts + tests. This keeps each plan focused.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Codebase exploration — Read `lib/core/output.sh`, `lib/core/config.sh`, `lib/core/error-codes.sh`, `bin/backup-now.sh`, `lib/platform/daemon-manager.sh`, `lib/database-detector.sh`, `lib/features/verification.sh`
- Grep analysis — 932 `2>/dev/null` occurrences across 87 `.sh` files with context analysis

### Secondary (MEDIUM confidence)
- [Bash logging levels pattern — Ludovico Caldara](https://www.ludovicocaldara.net/dba/bash-tips-4-use-logging-levels/) — Numeric log level pattern verified against multiple sources
- [Bash logging best practices — Tratif](https://blog.tratif.com/2023/01/09/bash-tips-1-logging-in-shell-scripts/) — FD-based output pattern
- [Bash performance tips — MoldStud](https://moldstud.com/articles/p-how-to-avoid-common-bash-scripting-performance-issues-essential-tips-and-best-practices) — Subshell overhead benchmarks
- [macOS newsyslog — Richard Purves](https://richard-purves.com/2017/11/08/log-rotation-mac-admin-cheats-guide/) — macOS log rotation options
- [macOS Unified Logging from scripts — Eclectic Light](https://eclecticlight.co/2023/01/14/how-to-write-to-the-log-from-a-script/) — syslog limitations on macOS
- [JSON logging from shell — Stegard](https://stegard.net/2021/07/how-to-make-a-shell-script-log-json-messages/) — JSON structured logging pattern
- [Improving bash script logs — CyberArk](https://developer.cyberark.com/blog/improving-logs-in-bash-scripts/) — set -x vs structured logging comparison
- [BASH_XTRACEFD — linuxbash.sh](https://www.linuxbash.sh/post/xtracefd) — Execution trace to separate FD

### Bash Logging Libraries (evaluated, not adopted)
- [bash_logger — D4rth-C0d3r](https://github.com/D4rth-C0d3r/bash_logger) — Most feature-complete; good reference for rotation pattern
- [b-log — idelsink](https://github.com/idelsink/b-log) — Template system reference
- [bashlog — klhochhalter](https://github.com/klhochhalter/bashlog) — RFC 5424 alignment reference
- [log4bash — fredpalmer](https://github.com/fredpalmer/log4bash) — Original bash logging lib
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Bash structured logging patterns
- Ecosystem: Logging libraries (bash_logger, b-log, bashlog, log4bash), log rotation approaches
- Patterns: Numeric log levels, FD-based output, stderr capture, debug toggle, categorized 2>/dev/null replacement
- Pitfalls: Blind replacement, performance regression, bash 3.2 compat, log bloat, concurrent writes

**Confidence breakdown:**
- Standard stack: HIGH — Custom module is clearly correct given existing infrastructure; verified against library capabilities
- Architecture: HIGH — Numeric log level pattern is industry consensus across all sources
- Pitfalls: HIGH — Performance data verified from multiple benchmarks; bash version issue is well-documented
- Code examples: HIGH — Patterns synthesized from multiple authoritative sources and verified against bash documentation
- Migration categorization: MEDIUM — Category breakdown based on codebase analysis, exact counts need validation during planning

**Research date:** 2026-02-13
**Valid until:** 2026-06-13 (120 days — bash logging patterns are very stable)
</metadata>

---

*Phase: 17-error-logging*
*Research completed: 2026-02-13*
*Ready for planning: yes*
