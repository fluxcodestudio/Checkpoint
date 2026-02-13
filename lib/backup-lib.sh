#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Core Library (Module Loader)
# ==============================================================================
# Version: 3.0.0
# Description: Thin loader that sources all Checkpoint library modules in
#              dependency order. Consumers source this single file to get
#              the full library — no changes needed to existing bin/ scripts.
#
# Usage:
#   source "$LIB_DIR/backup-lib.sh"
#
# Module structure:
#   core/     - Error codes, output/color, config management (no dependencies)
#   ops/      - File operations, state tracking, initialization (depend on core)
#   ui/       - Formatting, time/size utilities
#   features/ - Discovery, restore, cleanup, malware, health, detection, cloud, git
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_LIB:-}" ] && return || readonly _CHECKPOINT_LIB=1

set -euo pipefail

_CHECKPOINT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Core (no dependencies) ===
source "$_CHECKPOINT_LIB_DIR/core/error-codes.sh"
source "$_CHECKPOINT_LIB_DIR/core/output.sh"
source "$_CHECKPOINT_LIB_DIR/core/config.sh"

# === Operations (depend on core) ===
source "$_CHECKPOINT_LIB_DIR/ops/file-ops.sh"
source "$_CHECKPOINT_LIB_DIR/ops/state.sh"
source "$_CHECKPOINT_LIB_DIR/ops/init.sh"

# === UI utilities ===
source "$_CHECKPOINT_LIB_DIR/ui/formatting.sh"
source "$_CHECKPOINT_LIB_DIR/ui/time-size-utils.sh"

# === Features (depend on core + ops) ===
source "$_CHECKPOINT_LIB_DIR/features/backup-discovery.sh"
source "$_CHECKPOINT_LIB_DIR/features/restore.sh"
source "$_CHECKPOINT_LIB_DIR/features/cleanup.sh"
source "$_CHECKPOINT_LIB_DIR/features/malware.sh"
source "$_CHECKPOINT_LIB_DIR/features/health-stats.sh"
source "$_CHECKPOINT_LIB_DIR/features/change-detection.sh"
source "$_CHECKPOINT_LIB_DIR/features/cloud-destinations.sh"
source "$_CHECKPOINT_LIB_DIR/features/github-auth.sh"

# Backward compatibility marker
export BACKUP_LIB_LOADED=1
