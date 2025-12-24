#!/bin/bash
# Checkpoint - Install Skills
# Sets up /backup-status and /backup-now skills for Claude Code

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

echo "Installing Checkpoint backup skills for Claude Code..."
echo ""

# Create skills directory
mkdir -p "$SKILLS_DIR"

# ==============================================================================
# Install /backup-status skill
# ==============================================================================

echo "📦 Installing /backup-status skill..."

SKILL_DIR="$SKILLS_DIR/backup-status"
mkdir -p "$SKILL_DIR"

# Create skill.json
cat > "$SKILL_DIR/skill.json" <<'EOF'
{
  "name": "backup-status",
  "version": "1.0.0",
  "description": "Show comprehensive backup system health dashboard with statistics, component status, warnings, and retention policies",
  "author": "Checkpoint",
  "category": "backup",
  "tags": ["backup", "status", "monitoring", "health"],
  "command": "./run.sh",
  "arguments": {
    "schema": {
      "type": "object",
      "properties": {
        "format": {
          "type": "string",
          "enum": ["dashboard", "compact", "timeline", "json"],
          "default": "dashboard",
          "description": "Output format (dashboard, compact, timeline, json)"
        },
        "project": {
          "type": "string",
          "description": "Project directory path (optional, defaults to current)"
        }
      }
    }
  },
  "examples": [
    {
      "description": "Show full dashboard",
      "command": "/backup-status"
    },
    {
      "description": "Compact one-line status",
      "command": "/backup-status --compact"
    },
    {
      "description": "Timeline view of backups",
      "command": "/backup-status --timeline"
    },
    {
      "description": "JSON output for scripting",
      "command": "/backup-status --json"
    }
  ]
}
EOF

# Create run.sh
cat > "$SKILL_DIR/run.sh" <<'EOF'
#!/bin/bash
# ClaudeCode Skill: backup-status
# Show backup system health and statistics

set -euo pipefail

# Get the backup scripts directory
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"

# Execute the backup-status script
exec "$BIN_DIR/backup-status.sh" "$@"
EOF

chmod +x "$SKILL_DIR/run.sh"

echo "   ✅ /backup-status skill installed"
echo ""

# ==============================================================================
# Install /backup-now skill
# ==============================================================================

echo "📦 Installing /backup-now skill..."

SKILL_DIR="$SKILLS_DIR/backup-now"
mkdir -p "$SKILL_DIR"

# Create skill.json
cat > "$SKILL_DIR/skill.json" <<'EOF'
{
  "name": "backup-now",
  "version": "1.0.0",
  "description": "Trigger an immediate backup with progress reporting. Supports force mode, selective backups (database/files only), verbose output, and dry-run preview",
  "author": "Checkpoint",
  "category": "backup",
  "tags": ["backup", "trigger", "manual", "force"],
  "command": "./run.sh",
  "arguments": {
    "schema": {
      "type": "object",
      "properties": {
        "force": {
          "type": "boolean",
          "default": false,
          "description": "Force backup even if interval not reached"
        },
        "database-only": {
          "type": "boolean",
          "default": false,
          "description": "Only backup database"
        },
        "files-only": {
          "type": "boolean",
          "default": false,
          "description": "Only backup files"
        },
        "verbose": {
          "type": "boolean",
          "default": false,
          "description": "Show detailed progress"
        },
        "dry-run": {
          "type": "boolean",
          "default": false,
          "description": "Preview what would be backed up"
        },
        "wait": {
          "type": "boolean",
          "default": false,
          "description": "Wait for completion (don't background)"
        },
        "quiet": {
          "type": "boolean",
          "default": false,
          "description": "Suppress non-error output"
        },
        "project": {
          "type": "string",
          "description": "Project directory path (optional, defaults to current)"
        }
      }
    }
  },
  "examples": [
    {
      "description": "Standard backup",
      "command": "/backup-now"
    },
    {
      "description": "Force immediate backup",
      "command": "/backup-now --force"
    },
    {
      "description": "Only backup database",
      "command": "/backup-now --database-only"
    },
    {
      "description": "Preview changes without backing up",
      "command": "/backup-now --dry-run"
    },
    {
      "description": "Verbose backup with details",
      "command": "/backup-now --verbose --force"
    }
  ]
}
EOF

# Create run.sh
cat > "$SKILL_DIR/run.sh" <<'EOF'
#!/bin/bash
# ClaudeCode Skill: backup-now
# Trigger immediate backup

set -euo pipefail

# Get the backup scripts directory
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"

# Execute the backup-now script
exec "$BIN_DIR/backup-now.sh" "$@"
EOF

chmod +x "$SKILL_DIR/run.sh"

echo "   ✅ /backup-now skill installed"
echo ""

# ==============================================================================
# Install /backup-config skill
# ==============================================================================

echo "📦 Installing /backup-config skill..."

SKILL_DIR="$SKILLS_DIR/backup-config"
mkdir -p "$SKILL_DIR"

cat > "$SKILL_DIR/skill.json" <<'EOF'
{
  "name": "backup-config",
  "version": "1.1.0",
  "description": "Manage backup configuration with interactive wizard, get/set values, validation, and templates",
  "author": "Checkpoint",
  "category": "backup",
  "tags": ["backup", "config", "settings", "configuration"],
  "command": "./run.sh"
}
EOF

cat > "$SKILL_DIR/run.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
exec "$PROJECT_ROOT/bin/backup-config.sh" "$@"
EOF

chmod +x "$SKILL_DIR/run.sh"
echo "   ✅ /backup-config skill installed"
echo ""

# ==============================================================================
# Install /backup-cleanup skill
# ==============================================================================

echo "📦 Installing /backup-cleanup skill..."

SKILL_DIR="$SKILLS_DIR/backup-cleanup"
mkdir -p "$SKILL_DIR"

cat > "$SKILL_DIR/skill.json" <<'EOF'
{
  "name": "backup-cleanup",
  "version": "1.1.0",
  "description": "Smart cleanup utility with preview mode, recommendations, and safety features for managing backup disk space",
  "author": "Checkpoint",
  "category": "backup",
  "tags": ["backup", "cleanup", "maintenance", "disk-space"],
  "command": "./run.sh"
}
EOF

cat > "$SKILL_DIR/run.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
exec "$PROJECT_ROOT/bin/backup-cleanup.sh" "$@"
EOF

chmod +x "$SKILL_DIR/run.sh"
echo "   ✅ /backup-cleanup skill installed"
echo ""

# ==============================================================================
# Install /backup-restore skill
# ==============================================================================

echo "📦 Installing /backup-restore skill..."

SKILL_DIR="$SKILLS_DIR/backup-restore"
mkdir -p "$SKILL_DIR"

cat > "$SKILL_DIR/skill.json" <<'EOF'
{
  "name": "backup-restore",
  "version": "1.1.0",
  "description": "Interactive restore wizard for recovering databases and files from backups with safety features",
  "author": "Checkpoint",
  "category": "backup",
  "tags": ["backup", "restore", "recovery", "wizard"],
  "command": "./run.sh"
}
EOF

cat > "$SKILL_DIR/run.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
exec "$PROJECT_ROOT/bin/backup-restore.sh" "$@"
EOF

chmod +x "$SKILL_DIR/run.sh"
echo "   ✅ /backup-restore skill installed"
echo ""

# ==============================================================================
# Summary
# ==============================================================================

echo "═══════════════════════════════════════════════════════════"
echo "✅ Skills installation complete!"
echo ""
echo "Available skills:"
echo "  • /backup-status  - Show backup system health dashboard"
echo "  • /backup-now     - Trigger immediate backup"
echo "  • /backup-config  - Manage configuration settings"
echo "  • /backup-cleanup - Clean up old backups to free space"
echo "  • /backup-restore - Restore files or database from backups"
echo ""
echo "You can also use the standalone scripts:"
echo "  • $PROJECT_ROOT/bin/backup-status.sh"
echo "  • $PROJECT_ROOT/bin/backup-now.sh"
echo "  • $PROJECT_ROOT/bin/backup-config.sh"
echo "  • $PROJECT_ROOT/bin/backup-cleanup.sh"
echo "  • $PROJECT_ROOT/bin/backup-restore.sh"
echo ""
echo "Try it now:"
echo "  /backup-status"
echo "  /backup-config --help"
echo "═══════════════════════════════════════════════════════════"
