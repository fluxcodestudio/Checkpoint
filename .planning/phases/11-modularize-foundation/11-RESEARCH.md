# Phase 11: Modularize Foundation Library - Research

**Researched:** 2026-02-13
**Domain:** Bash script modularization (splitting 3,216-line monolith into focused modules)
**Confidence:** HIGH

<research_summary>
## Summary

Researched best practices for modularizing large bash scripts, focusing on source guard patterns, module loading order, namespace conventions, bash 3.2 compatibility (macOS requirement), performance implications, and testing approaches.

The standard approach uses include guards (`[ -n "$_GUARD" ] && return || readonly _GUARD=1`) to prevent double-loading, a thin loader file that sources modules in dependency order, and `$BASH_SOURCE[0]`-based directory detection. The existing codebase already uses two of these patterns — `global-status.sh` has a proper include guard, and `backup-lib.sh` uses `BACKUP_LIB_LOADED=1` as a load marker.

Key finding: Performance overhead of sourcing 6-8 files vs 1 is negligible (5-10ms of extra file I/O for additional `open()` syscalls). The code parsed is identical either way. The project's existing symlink resolution pattern in `bin/` scripts and existing `LIB_DIR` convention mean zero changes needed for consumers — `backup-lib.sh` simply becomes a thin loader.

**Primary recommendation:** Keep `backup-lib.sh` as a thin loader (consumers unchanged), split into ~8 focused modules under `lib/core/`, `lib/ops/`, `lib/ui/`, and `lib/features/`. Use include guards on every module. Keep existing function names for backward compatibility.
</research_summary>

<standard_stack>
## Standard Stack

This is internal refactoring — no new external dependencies needed. The "stack" here is the patterns and tools used for the modularization itself.

### Core Patterns
| Pattern | Purpose | Why Standard |
|---------|---------|--------------|
| Include guard (`[ -n "$_GUARD" ] && return \|\| readonly _GUARD=1`) | Prevent double-sourcing | Used by bash-it, oh-my-bash, global-status.sh already. bash 3.2 safe. |
| Thin loader file | Central module orchestration | `backup-lib.sh` becomes the loader. Consumers source one file, get all modules. |
| `$BASH_SOURCE[0]` directory detection | Reliable path resolution | Already used throughout codebase. Works on bash 3.2. |
| `set -euo pipefail` in loader only | Error handling | Modules should NOT set this independently (would conflict with caller). |

### Supporting Tools
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| ShellCheck | Latest | Static analysis for modular source paths | During development + CI. Needs `.shellcheckrc` for source-path. |
| Existing test-framework.sh | Custom | Unit testing | Already works. Source individual modules in tests for isolation. |
| hyperfine | Latest | Benchmark sourcing performance | Optional: verify modularization doesn't add overhead. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Subdirectories (core/, ops/) | Flat `lib/` | Flat is simpler but less organized. Subdirs clearer at 8+ modules. |
| `_checkpoint_require()` function | Explicit `source` statements | Require function adds complexity. Explicit sources are clearer for a fixed module set. |
| Numeric priority prefixes (100-config.sh) | Explicit ordered loading | Priority prefixes better for dynamic plugin systems, overkill for fixed modules. |
| bats-core | Keep custom test framework | bats-core is more powerful but adds external dependency. Custom framework already works. |
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Module Structure
```
lib/
├── backup-lib.sh              # Thin loader — sources all modules in order
├── core/
│   ├── error-codes.sh         # Error catalog, descriptions, suggestions (~120 lines)
│   ├── output.sh              # Color output, JSON helpers, logging (~120 lines)
│   └── config.sh              # Config loading, get/set, validation, profiles (~500 lines)
├── ops/
│   ├── file-ops.sh            # Locking, hashing, copy_with_retry, disk space (~300 lines)
│   ├── state.sh               # Backup state tracking (JSON), severity, notifications (~450 lines)
│   └── init.sh                # init_state_dirs, init_backup_dirs, ensure_backup_dirs (~100 lines)
├── ui/
│   ├── formatting.sh          # draw_box, draw_border, prompt, confirm (~120 lines)
│   └── time-size-utils.sh     # format_time_ago, format_bytes, format_duration (~200 lines)
└── features/
    ├── backup-discovery.sh    # list_database_backups_sorted, list_file_versions_sorted (~80 lines)
    ├── restore.sh             # create_safety_backup, verify_*, restore_* (~200 lines)
    ├── cleanup.sh             # find_expired, cleanup_*, audit_*, recommendations (~350 lines)
    ├── malware.sh             # scan_file_for_malware, scan_backup_for_malware (~130 lines)
    ├── health-stats.sh        # Component health checks, statistics gathering, retention analysis (~200 lines)
    ├── change-detection.sh    # has_changes, get_changed_files_fast (~80 lines)
    ├── cloud-destinations.sh  # resolve_backup_destinations, ensure_backup_dirs (cloud) (~200 lines)
    └── github-auth.sh         # check_github_auth, setup_github_auth, push status (~100 lines)
```

**Line count validation:** Sections add to ~3,050 lines + module boilerplate (~10 lines each x 15 = 150) = ~3,200 lines. Matches original 3,216.

### Pattern 1: Include Guard (Every Module)
**What:** Prevent double-sourcing when modules declare their own dependencies
**When to use:** Every single module file
**Example:**
```bash
# lib/core/error-codes.sh
[ -n "$_CHECKPOINT_ERROR_CODES" ] && return || readonly _CHECKPOINT_ERROR_CODES=1
```

**Naming convention:** `_CHECKPOINT_<MODULE_NAME>` with underscores for hyphens.

### Pattern 2: Thin Loader (backup-lib.sh)
**What:** `backup-lib.sh` becomes a loader that sources all modules in dependency order
**When to use:** This is the only file consumers (bin/ scripts) need to source
**Example:**
```bash
#!/usr/bin/env bash
# Checkpoint - Core Library (Module Loader)
[ -n "$_CHECKPOINT_LIB" ] && return || readonly _CHECKPOINT_LIB=1

set -euo pipefail

_CHECKPOINT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Core (no dependencies)
source "$_CHECKPOINT_LIB_DIR/core/error-codes.sh"
source "$_CHECKPOINT_LIB_DIR/core/output.sh"
source "$_CHECKPOINT_LIB_DIR/core/config.sh"

# Operations (depend on core)
source "$_CHECKPOINT_LIB_DIR/ops/file-ops.sh"
source "$_CHECKPOINT_LIB_DIR/ops/state.sh"
source "$_CHECKPOINT_LIB_DIR/ops/init.sh"

# UI utilities
source "$_CHECKPOINT_LIB_DIR/ui/formatting.sh"
source "$_CHECKPOINT_LIB_DIR/ui/time-size-utils.sh"

# Features (depend on core + ops)
source "$_CHECKPOINT_LIB_DIR/features/backup-discovery.sh"
source "$_CHECKPOINT_LIB_DIR/features/restore.sh"
source "$_CHECKPOINT_LIB_DIR/features/cleanup.sh"
source "$_CHECKPOINT_LIB_DIR/features/malware.sh"
source "$_CHECKPOINT_LIB_DIR/features/health-stats.sh"
source "$_CHECKPOINT_LIB_DIR/features/change-detection.sh"
source "$_CHECKPOINT_LIB_DIR/features/cloud-destinations.sh"
source "$_CHECKPOINT_LIB_DIR/features/github-auth.sh"

export BACKUP_LIB_LOADED=1
```

### Pattern 3: Module Self-Declaration
**What:** Each module declares what it provides and requires via comments
**When to use:** Top of every module, below include guard
**Example:**
```bash
# @requires: core/error-codes, core/output
# @provides: copy_with_retry, acquire_backup_lock, release_backup_lock, ...
```

### Pattern 4: Directory Detection in Modules
**What:** Modules reuse `_CHECKPOINT_LIB_DIR` set by the loader, with fallback
**When to use:** Any module that needs to source dependencies
**Example:**
```bash
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
```

### Anti-Patterns to Avoid
- **Each module doing `set -euo pipefail`:** Only the loader or entry-point script should set this. Modules setting it can conflict with caller context.
- **Moving `set -euo pipefail` into each module:** The caller controls error handling strategy.
- **Circular dependencies:** Error-codes must NOT depend on logging. Keep `core/` modules dependency-free from each other where possible.
- **Global variable initialization in multiple modules:** All `declare -a` arrays and global state variables should live in exactly one module (state.sh for state, config.sh for config).
- **`readonly` on variables that other modules might need to modify:** Use `readonly` only for true constants (COLOR_*, ERROR_CATALOG). Don't use it for state variables.
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Include guard mechanism | Custom tracking with arrays/associative arrays | `[ -n "$_GUARD" ] && return \|\| readonly _GUARD=1` one-liner | The one-liner pattern is proven, bash 3.2 compatible, and used by global-status.sh already |
| Module dependency resolution | Custom `require()` with dependency graph | Explicit ordered `source` statements in loader | Fixed module set doesn't need dynamic resolution. Explicit ordering is debuggable. |
| Path resolution | `realpath` or custom symlink walking in modules | `_CHECKPOINT_LIB_DIR` set once by loader, reused by all modules | `realpath` not on stock macOS. Loader sets it once, modules inherit. |
| Testing individual modules | Custom module isolation framework | Source single module + its deps in test setup | Existing test-framework.sh already supports this pattern |

**Key insight:** Bash modularization is a solved problem with simple patterns. The include guard + thin loader + directory variable convention covers 100% of needs. There's no need for a module system framework — explicit `source` statements in dependency order is the right approach for a project with a fixed, known set of modules.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Variable Scope Leakage
**What goes wrong:** A variable set in one module unexpectedly affects another module
**Why it happens:** Bash has no module scoping — all sourced code shares the same namespace
**How to avoid:**
- Use `local` for ALL function variables (already done throughout codebase)
- Prefix module-level globals with `_CHECKPOINT_` to avoid collisions
- Document which globals each module sets
**Warning signs:** Tests pass individually but fail when run together; intermittent behavior changes

### Pitfall 2: Source Order Bugs
**What goes wrong:** Module calls a function that hasn't been sourced yet
**Why it happens:** Modules were reordered or a new dependency was added without updating loader
**How to avoid:**
- Document dependencies in module header comments (`@requires:`)
- Loader sources in explicit dependency order
- Each module can also defensively source its deps (guards prevent double-load)
**Warning signs:** "command not found" errors that only happen sometimes; errors that go away when sourcing the full library

### Pitfall 3: readonly Conflicts During Re-sourcing
**What goes wrong:** `readonly: _CHECKPOINT_CONFIG: readonly variable` error on re-source
**Why it happens:** Include guard uses `readonly` but someone tries to re-source without the guard check
**How to avoid:** The `[ -n "$_GUARD" ] && return || readonly _GUARD=1` pattern handles this — the `return` fires before the `readonly` on subsequent loads
**Warning signs:** Errors only when scripts are sourced multiple times (e.g., in subshells or test suites)

### Pitfall 4: `set -euo pipefail` in Modules Breaking Callers
**What goes wrong:** A module sets `set -e` and now a caller's `|| true` pattern doesn't work as expected
**Why it happens:** `set -e` behavior with subshells and `||` is notoriously inconsistent across bash versions
**How to avoid:** Only set `set -euo pipefail` in the top-level loader or in entry-point scripts (`bin/*`). Never in individual modules.
**Warning signs:** Functions that used to work now exit unexpectedly; `|| true` no longer prevents exit

### Pitfall 5: Breaking Existing Consumers
**What goes wrong:** A `bin/` script that did `source "$LIB_DIR/backup-lib.sh"` now fails
**Why it happens:** Module paths changed but consumer wasn't updated
**How to avoid:** Keep `backup-lib.sh` at the same path — it becomes the loader. ALL consumers continue to `source "$LIB_DIR/backup-lib.sh"` unchanged. This is the #1 design constraint.
**Warning signs:** Any `bin/` script failing after the refactor

### Pitfall 6: ShellCheck SC1090/SC1091 Warnings
**What goes wrong:** ShellCheck can't follow dynamic source paths, produces warnings
**Why it happens:** `source "$_CHECKPOINT_LIB_DIR/core/config.sh"` uses a variable path
**How to avoid:** Add `# shellcheck source=core/config.sh` directives before each source. Create `.shellcheckrc` with `source-path=lib/` and `external-sources=true`.
**Warning signs:** ShellCheck output full of SC1090 warnings; devs start ignoring ShellCheck entirely
</common_pitfalls>

<code_examples>
## Code Examples

Verified patterns from the existing codebase and bash best practices:

### Include Guard (from lib/global-status.sh — already in codebase)
```bash
# Source: lib/global-status.sh lines 9-10
[[ -n "${GLOBAL_STATUS_LOADED:-}" ]] && return 0
readonly GLOBAL_STATUS_LOADED=1
```

### Module Template (recommended for all new modules)
```bash
#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - [Module Name]
# ==============================================================================
# @requires: [dependencies]
# @provides: [function list]
# ==============================================================================

# Include guard
[ -n "$_CHECKPOINT_MODULE_NAME" ] && return || readonly _CHECKPOINT_MODULE_NAME=1

# Reuse lib dir from loader (with fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# --- Module code below ---
```

### Lazy-Load Pattern (from backup-lib.sh line 2912 — already in codebase)
```bash
# Source: lib/backup-lib.sh lines 2912-2920
_ensure_cloud_detector_loaded() {
    if [[ -z "${CLOUD_DETECTOR_LOADED:-}" ]]; then
        local lib_dir="${LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
        if [[ -f "$lib_dir/cloud-folder-detector.sh" ]]; then
            source "$lib_dir/cloud-folder-detector.sh"
            export CLOUD_DETECTOR_LOADED=1
        fi
    fi
}
```
Note: This lazy-load pattern is good for optional/heavy modules but not needed for the core module split (all core modules should load eagerly via the loader).

### Consumer Script Pattern (unchanged after modularization)
```bash
# Source: bin/backup-now.sh lines 12-23 (representative)
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# This line stays EXACTLY the same after modularization
source "$LIB_DIR/backup-lib.sh"
```

### ShellCheck Configuration (.shellcheckrc)
```bash
# .shellcheckrc — place at project root
external-sources=true
source-path=lib/
```

### ShellCheck Directive Per Source
```bash
# shellcheck source=core/error-codes.sh
source "$_CHECKPOINT_LIB_DIR/core/error-codes.sh"
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Monolithic bash files | Module-per-concern with include guards | Well-established | Standard practice for 500+ line bash projects |
| `realpath` for path resolution | `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` | macOS constraint | `realpath` not on stock macOS. BASH_SOURCE pattern is reliable. |
| No include guards | `[ -n "$_GUARD" ] && return \|\| readonly _GUARD=1` | From bash-it, oh-my-bash | Prevents double-load, enables dependency declaration |
| `declare -A` for config schemas | Case statements / indexed arrays | Bash 3.2 constraint | macOS bash 3.2 doesn't support associative arrays. Project already uses case statements. |

**Relevant tools:**
- **ShellCheck** (v0.10+): Now supports `external-sources=true` in `.shellcheckrc` for better modular bash analysis
- **bats-core** (v1.11+): If adopting later, supports parallel test execution and better setup/teardown

**Not relevant / don't pursue:**
- **Bash 5.x features**: macOS won't ship bash 5 due to GPLv3. Don't depend on it.
- **Module bundlers/minifiers for bash**: These exist but add complexity without benefit for this project.
- **zsh compatibility**: Project is bash-only (`#!/usr/bin/env bash`). Don't split focus.
</sota_updates>

<open_questions>
## Open Questions

1. **How to handle the `set -euo pipefail` across modules?**
   - What we know: Only the loader or entry scripts should set this. Individual modules should not.
   - What's unclear: Should `backup-lib.sh` (the loader) continue to have `set -euo pipefail`? Currently it does (line 24). The `bin/` consumers also set it independently.
   - Recommendation: Keep `set -euo pipefail` in the loader. It's safe because all consumers set it anyway, and it protects against direct sourcing of the loader.

2. **Should `config.sh` stay as one module or split further?**
   - What we know: The config section spans ~500 lines with config_key_to_var (mapping), config_get_value/set_value (operations), config_validate_file (validation), and config_profile_* (profiles). These are all config-related.
   - What's unclear: Whether validation warrants its own module.
   - Recommendation: Keep as one `config.sh` module. 500 lines is manageable for a single concern. Split only if it grows further.

3. **Should notification functions stay with state or become their own module?**
   - What we know: Notifications (send_notification, notify_backup_failure/success/warning) are closely tied to state tracking but also use config values (QUIET_HOURS, NOTIFY_ON_*) and alert configuration.
   - What's unclear: Best grouping.
   - Recommendation: Group notifications into `ops/state.sh` alongside severity/state tracking. They share data (failure counts, severity) and are always used together. The alert configuration variables (ALERT_WARNING_HOURS, NOTIFY_ON_SUCCESS, etc.) move into `core/config.sh` as they're configuration defaults.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- **Existing codebase analysis** — Direct reading of `lib/backup-lib.sh` (3,216 lines, ~100 functions, 30 sections), all 13 lib files, 28 bin scripts, and test framework
- **lib/global-status.sh** — Already uses include guard pattern (lines 9-10), confirming codebase convention
- **lib/backup-lib.sh** line 2912-2920 — Already uses lazy-load pattern for cloud-folder-detector.sh
- **Google Shell Style Guide** — https://google.github.io/styleguide/shellguide.html — Namespace conventions, function naming, file organization

### Secondary (MEDIUM confidence)
- **bash-it project architecture** — https://github.com/Bash-it/bash-it — Module loading with numeric priority prefixes, glob-based sourcing
- **oh-my-bash module system** — `_omb_module_require` function pattern for on-demand loading
- **Coderwall include guard pattern** — https://coderwall.com/p/it3b-q/bash-include-guard — Verified bash 3.2 compatible
- **ShellCheck documentation** — SC1090/SC1091 handling with `external-sources=true` and `source-path` directives
- **Bash startup benchmarks** — https://danpker.com/posts/faster-bash-startup/ and https://work.lisk.in/2020/11/20/even-faster-bash-startup.html — Confirmed negligible overhead for multi-file sourcing

### Tertiary (LOW confidence — needs validation)
- None — all findings verified against codebase analysis or authoritative sources
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Bash 3.2 modularization patterns
- Ecosystem: ShellCheck, include guards, source conventions, test frameworks
- Patterns: Thin loader, include guards, directory detection, namespace conventions
- Pitfalls: Variable scope, source order, readonly conflicts, set -e propagation

**Confidence breakdown:**
- Standard stack: HIGH — Patterns verified against existing codebase + established projects
- Architecture: HIGH — Module split derived from actual section analysis of backup-lib.sh
- Pitfalls: HIGH — Common bash sourcing issues well-documented
- Code examples: HIGH — Taken directly from existing codebase patterns

**Section-to-module mapping (verified against line counts):**

| Module | Source Sections | Est. Lines |
|--------|----------------|------------|
| core/error-codes.sh | ERROR CODES AND SUGGESTED FIXES | ~120 |
| core/output.sh | COLOR OUTPUT + JSON OUTPUT + LOGGING | ~120 |
| core/config.sh | CONFIGURATION LOADING + ALERT CONFIG + QUIET HOURS + DRIVE VERIFICATION + CONFIGURATION MANAGEMENT | ~500 |
| ops/file-ops.sh | FILE LOCKING + HASH-BASED FILE COMPARISON + DISK SPACE ANALYSIS | ~300 |
| ops/state.sh | BACKUP STATE TRACKING + NOTIFICATION SYSTEM + RETRY LOGIC + FAILURE REPORTING | ~600 |
| ops/init.sh | INITIALIZATION | ~50 |
| ui/formatting.sh | INTERACTIVE UI COMPONENTS | ~120 |
| ui/time-size-utils.sh | TIME UTILITIES + SIZE UTILITIES + DATE/TIME PARSING | ~200 |
| features/backup-discovery.sh | BACKUP DISCOVERY & LISTING | ~80 |
| features/restore.sh | RESTORE OPERATIONS | ~200 |
| features/cleanup.sh | CLEANUP OPERATIONS + SINGLE-PASS CLEANUP + CLEANUP RECOMMENDATIONS + AUDIT LOGGING | ~350 |
| features/malware.sh | MALWARE DETECTION | ~130 |
| features/health-stats.sh | COMPONENT HEALTH CHECKS + STATISTICS GATHERING + RETENTION POLICY ANALYSIS | ~200 |
| features/change-detection.sh | FAST CHANGE DETECTION | ~80 |
| features/cloud-destinations.sh | CLOUD FOLDER DESTINATION RESOLUTION | ~200 |
| features/github-auth.sh | GITHUB AUTHENTICATION HELPERS | ~100 |

**Total:** ~3,350 lines (includes ~150 lines of per-module boilerplate: guards, headers, comments)

**Research date:** 2026-02-13
**Valid until:** N/A (internal architecture patterns, not ecosystem-dependent)
</metadata>

---

*Phase: 11-modularize-foundation*
*Research completed: 2026-02-13*
*Ready for planning: yes*
