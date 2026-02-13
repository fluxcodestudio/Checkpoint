#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Script Bootstrap
# ==============================================================================
# Shared initialization for bin/ scripts. Resolves the calling script's
# real path through symlinks and sets standard path variables.
#
# Usage (from any bin/ script):
#   source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"
#
# Provides:
#   SCRIPT_DIR   - Real directory of the calling script (symlinks resolved)
#   LIB_DIR      - Path to lib/ directory
#   PROJECT_ROOT - Path to project root (parent of bin/)
#
# Works with both per-project installs and global symlinked installs.
# Must be sourced directly from bin/ scripts (not transitively).
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_BOOTSTRAP:-}" ] && return || readonly _CHECKPOINT_BOOTSTRAP=1

# Resolve the CALLING script's real path through symlinks.
# BASH_SOURCE[1] is the script that sourced this file.
_bootstrap_path="${BASH_SOURCE[1]}"
while [ -L "$_bootstrap_path" ]; do
    _bootstrap_dir="$(cd "$(dirname "$_bootstrap_path")" && pwd)"
    _bootstrap_path="$(readlink "$_bootstrap_path")"
    [[ $_bootstrap_path != /* ]] && _bootstrap_path="$_bootstrap_dir/$_bootstrap_path"
done

SCRIPT_DIR="$(cd "$(dirname "$_bootstrap_path")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset _bootstrap_path _bootstrap_dir
