#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Global Installation
# ==============================================================================
# Installs Checkpoint system-wide for use across all projects
# Usage: ./bin/install-global.sh
# ==============================================================================

set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Load dependency manager
source "$PACKAGE_DIR/lib/dependency-manager.sh"

# ==============================================================================
# ROLLBACK SUPPORT (v2.3.0)
# ==============================================================================

BACKUP_DIR=""
INSTALL_FAILED=false

# Create backup of existing installation
backup_existing_installation() {
    local lib_dir="$1"
    if [[ -d "$lib_dir" ]]; then
        BACKUP_DIR="$lib_dir.backup.$(date +%Y%m%d_%H%M%S)"
        echo "Backing up existing installation to: $BACKUP_DIR"
        cp -r "$lib_dir" "$BACKUP_DIR"
        return 0
    fi
    return 0
}

# Rollback to previous installation on failure
rollback_installation() {
    if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
        echo ""
        echo "⚠️  Installation failed. Rolling back to previous version..."
        local lib_dir="${BACKUP_DIR%.backup.*}"
        rm -rf "$lib_dir" 2>/dev/null || true
        mv "$BACKUP_DIR" "$lib_dir"
        echo "✅ Rollback complete"
    fi
}

# Cleanup backup on successful installation
cleanup_backup() {
    if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
        rm -rf "$BACKUP_DIR"
    fi
}

# Trap for rollback on error
trap 'if [[ "$INSTALL_FAILED" == "true" ]]; then rollback_installation; fi' EXIT

echo "═══════════════════════════════════════════════"
echo "Checkpoint - Global Installation"
echo "═══════════════════════════════════════════════"
echo ""
echo "This will install Checkpoint system-wide."
echo "Commands will be available in all projects."
echo ""

# ==============================================================================
# CHECK BASH VERSION (for TUI dashboard features)
# ==============================================================================

if ! check_bash_version; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    # Offer to upgrade bash (non-blocking)
    require_bash || true  # Continue even if user declines
    echo ""
fi

# ==============================================================================
# CHECK FOR DIALOG (for best dashboard experience)
# ==============================================================================

if ! check_dialog; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    # Offer to install dialog (non-blocking)
    require_dialog || true  # Continue even if user declines
    echo ""
fi

# Determine installation prefix
if [[ -w "/usr/local/bin" ]]; then
    INSTALL_PREFIX="/usr/local"
    echo "Installing to: /usr/local (system-wide)"
else
    INSTALL_PREFIX="$HOME/.local"
    echo "Installing to: ~/.local (user-only, no sudo required)"
    echo ""
    echo "⚠️  Make sure ~/.local/bin is in your PATH:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
read -p "Continue with installation? (y/n) [y]: " confirm
confirm=${confirm:-y}

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 0
fi

# Create directories
BIN_DIR="$INSTALL_PREFIX/bin"
LIB_DIR="$INSTALL_PREFIX/lib/checkpoint"

echo ""

# Backup existing installation if upgrading
backup_existing_installation "$LIB_DIR"

# Mark installation as in progress (for rollback on failure)
INSTALL_FAILED=true

echo "Creating directories..."
mkdir -p "$BIN_DIR"
mkdir -p "$LIB_DIR/bin"
mkdir -p "$LIB_DIR/lib"
mkdir -p "$LIB_DIR/templates"
mkdir -p "$LIB_DIR/integrations"

# Copy library files
echo "Installing library files..."
cp -r "$PACKAGE_DIR/lib/"* "$LIB_DIR/lib/"
echo "✅ Libraries installed to $LIB_DIR/lib/"

# Copy binary scripts
echo "Installing scripts..."
cp -r "$PACKAGE_DIR/bin/"*.sh "$LIB_DIR/bin/"
chmod +x "$LIB_DIR/bin/"*.sh
echo "✅ Scripts installed to $LIB_DIR/bin/"

# Copy templates
echo "Installing templates..."
cp -r "$PACKAGE_DIR/templates/"* "$LIB_DIR/templates/"
echo "✅ Templates installed to $LIB_DIR/templates/"

# Copy integrations
echo "Installing integrations..."
cp -r "$PACKAGE_DIR/integrations/"* "$LIB_DIR/integrations/"
echo "✅ Integrations installed to $LIB_DIR/integrations/"

# Copy skills
echo "Installing skills..."
mkdir -p "$LIB_DIR/skills"
if [[ -d "$PACKAGE_DIR/skills" ]]; then
    cp -r "$PACKAGE_DIR/skills/"* "$LIB_DIR/skills/" 2>/dev/null || true
    echo "✅ Skills installed to $LIB_DIR/skills/"
fi

# Copy helper app source (for menu bar app)
echo "Installing helper app source..."
if [[ -d "$PACKAGE_DIR/helper" ]]; then
    mkdir -p "$LIB_DIR/helper"
    cp -r "$PACKAGE_DIR/helper/"* "$LIB_DIR/helper/"
    echo "✅ Helper source installed to $LIB_DIR/helper/"
fi

# Copy VERSION file
cp "$PACKAGE_DIR/VERSION" "$LIB_DIR/VERSION"

# Create command symlinks
echo ""
echo "Creating command symlinks..."

create_symlink() {
    local script="$1"
    local command="$2"
    local target="$BIN_DIR/$command"

    # Remove existing symlink/file
    rm -f "$target"

    # Create symlink
    ln -s "$LIB_DIR/bin/$script" "$target"

    echo "  ✅ $command → $LIB_DIR/bin/$script"
}

create_symlink "checkpoint.sh" "checkpoint"
create_symlink "backup-now.sh" "backup-now"
create_symlink "backup-status.sh" "backup-status"
create_symlink "backup-restore.sh" "backup-restore"
create_symlink "backup-cleanup.sh" "backup-cleanup"
create_symlink "backup-cloud-config.sh" "backup-cloud-config"
create_symlink "backup-daemon.sh" "backup-daemon"
create_symlink "backup-all-projects.sh" "backup-all"
create_symlink "backup-update.sh" "backup-update"
create_symlink "backup-pause.sh" "backup-pause"
create_symlink "configure-project.sh" "configure-project"
create_symlink "uninstall-global.sh" "backup-uninstall"
create_symlink "install-helper.sh" "install-helper"
create_symlink "uninstall-helper.sh" "uninstall-helper"

# Bootstrap file (sourced by all bin/ scripts for path resolution)
ln -s "$LIB_DIR/bin/bootstrap.sh" "$BIN_DIR/bootstrap.sh"
echo "  ✅ bootstrap.sh → $LIB_DIR/bin/bootstrap.sh"

# ==============================================================================
# INSTALL CLAUDE CODE SKILL
# ==============================================================================

echo ""
echo "Installing Claude Code skill..."

# Install /checkpoint skill to user's skills directory (new single-file format)
USER_SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$USER_SKILLS_DIR"

if [[ -f "$LIB_DIR/skills/checkpoint.md" ]]; then
    cp "$LIB_DIR/skills/checkpoint.md" "$USER_SKILLS_DIR/checkpoint.md"
    echo "  ✅ /checkpoint skill installed to ~/.claude/skills/"
elif [[ -f "$PACKAGE_DIR/skills/checkpoint.md" ]]; then
    cp "$PACKAGE_DIR/skills/checkpoint.md" "$USER_SKILLS_DIR/checkpoint.md"
    echo "  ✅ /checkpoint skill installed to ~/.claude/skills/"
else
    echo "  ⚠️  Checkpoint skill not found in package"
fi

# ==============================================================================
# INSTALL GLOBAL LAUNCHAGENT (macOS)
# ==============================================================================

if [[ "$OSTYPE" == "darwin"* ]]; then
    echo ""
    echo "Installing global backup daemon..."

    PLIST_FILE="$HOME/Library/LaunchAgents/com.checkpoint.global-daemon.plist"
    DAEMON_PATH="$BIN_DIR/backup-all"

    # Create global config directory
    mkdir -p "$HOME/.config/checkpoint"

    # Initialize projects registry if not exists
    if [[ ! -f "$HOME/.config/checkpoint/projects.json" ]]; then
        echo '{"version": 1, "projects": []}' > "$HOME/.config/checkpoint/projects.json"
    fi

    cat > "$PLIST_FILE" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.checkpoint.global-daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DAEMON_PATH}</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/checkpoint-global.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/checkpoint-global.err</string>
</dict>
</plist>
PLIST

    # Load the LaunchAgent
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    launchctl load "$PLIST_FILE" 2>/dev/null && echo "  ✅ Global daemon installed (hourly backups for all projects)"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Global Installation Complete!"
echo "═══════════════════════════════════════════════"
echo ""
echo "Installation details:"
echo "  Binaries: $BIN_DIR"
echo "  Libraries: $LIB_DIR"
echo ""
echo "Available commands (system-wide):"
echo "  checkpoint              Interactive command center"
echo "  backup-now              Run backup (auto-creates config for new projects)"
echo "  backup-all              Backup all registered projects"
echo "  backup-status           View backup status"
echo "  backup-restore          Restore from backup"
echo "  backup-cleanup          Clean old backups"
echo "  backup-update           Update to latest version"
echo "  backup-uninstall        Uninstall Checkpoint globally"
echo ""
echo "How it works:"
echo "  1. Run 'backup-now' in any project directory"
echo "  2. Config is auto-created, project is registered"
echo "  3. Global daemon backs up all projects hourly"
echo ""

# ==============================================================================
# AUTO-CONFIGURE ALL PROJECTS
# ==============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Checkpoint can automatically discover and configure all your projects."
echo ""
read -p "Auto-configure all projects? (Y/n): " auto_configure
auto_configure=${auto_configure:-y}
echo ""

if [[ "$auto_configure" =~ ^[Yy]$ ]]; then
    # Load auto-configure library
    source "$LIB_DIR/lib/auto-configure.sh"

    echo "Where are your projects located?"
    echo ""
    echo "  Examples:"
    echo "    /Volumes/WORK DRIVE/WEB DEV"
    echo "    ~/Developer"
    echo "    ~/Projects"
    echo ""
    echo "  Press Enter to scan default locations (~/{Developer,Projects,Code,...})"
    echo ""

    PROJECT_SCAN_DIRS=()

    while true; do
        read -p "Project directory (or Enter when done): " custom_dir

        # Empty input = done adding directories
        if [[ -z "$custom_dir" ]]; then
            break
        fi

        # Expand ~ to home
        expanded_dir="${custom_dir/#\~/$HOME}"

        if [[ -d "$expanded_dir" ]]; then
            PROJECT_SCAN_DIRS+=("$expanded_dir")
            echo "  ✓ Added: $expanded_dir"
        else
            echo "  ⚠ Not found: $expanded_dir"
        fi

        # If we have at least one dir, ask if they want to add more
        if [[ ${#PROJECT_SCAN_DIRS[@]} -gt 0 ]]; then
            read -p "Add another directory? (y/N): " add_more
            if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
                break
            fi
        fi
    done
    echo ""

    # Run auto-configure with custom dirs or defaults
    if [[ ${#PROJECT_SCAN_DIRS[@]} -gt 0 ]]; then
        auto_configure_all "${PROJECT_SCAN_DIRS[@]}"
    else
        auto_configure_all
    fi

    # Install daemons for all configured projects
    if [[ "${AUTO_CONFIG_CONFIGURED:-0}" -gt 0 ]]; then
        echo ""
        echo "Installing backup daemons for configured projects..."

        registry="$HOME/.config/checkpoint/projects.json"
        if [[ -f "$registry" ]] && command -v python3 &>/dev/null; then
            python3 << 'PYEOF'
import json
import os

registry_path = os.path.expanduser("~/.config/checkpoint/projects.json")
with open(registry_path, 'r') as f:
    data = json.load(f)

for project in data.get('projects', []):
    if project.get('enabled', True):
        print(project['path'])
PYEOF
        fi | while read -r project_path; do
            install_project_daemon "$project_path" 2>/dev/null && \
                echo "  ✓ Daemon installed: $(basename "$project_path")" || true
        done

        echo ""
        echo "✅ All projects configured and daemons installed!"
        echo ""
        echo "Backups will run automatically every hour."
        echo ""

        # ==============================================================================
        # OPTIONAL: SESSION-START HOOKS FOR HIGH-ACTIVITY PROJECTS
        # ==============================================================================
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "SESSION-START BACKUPS (Optional)"
        echo ""
        echo "Heavy-use projects can also trigger a backup when you start"
        echo "a new Claude Code session. This ensures you have a restore"
        echo "point BEFORE making changes (in addition to hourly backups)."
        echo ""
        read -p "Enable session-start backups for specific projects? (y/N): " enable_session_hooks
        enable_session_hooks=${enable_session_hooks:-n}
        echo ""

        if [[ "$enable_session_hooks" =~ ^[Yy]$ ]]; then
            # Get list of configured projects
            registry="$HOME/.config/checkpoint/projects.json"
            if [[ -f "$registry" ]] && command -v python3 &>/dev/null; then
                # Build project list
                echo "Select projects for session-start backups:"
                echo "(Enter numbers separated by commas, or 'none' to skip)"
                echo ""

                project_list=()
                index=1
                while IFS= read -r project_path; do
                    project_name=$(basename "$project_path")
                    project_list+=("$project_path")
                    echo "  [$index] $project_name"
                    index=$((index + 1))
                done < <(python3 << 'PYEOF'
import json
import os

registry_path = os.path.expanduser("~/.config/checkpoint/projects.json")
with open(registry_path, 'r') as f:
    data = json.load(f)

for project in data.get('projects', []):
    if project.get('enabled', True):
        print(project['path'])
PYEOF
)

                echo ""
                read -p "Enter project numbers (e.g., 1,3,5) or 'none': " selected_projects

                if [[ "$selected_projects" != "none" ]] && [[ -n "$selected_projects" ]]; then
                    echo ""
                    # Parse comma-separated numbers
                    IFS=',' read -ra selections <<< "$selected_projects"
                    for sel in "${selections[@]}"; do
                        # Trim whitespace
                        sel=$(echo "$sel" | tr -d ' ')
                        # Validate it's a number
                        if [[ "$sel" =~ ^[0-9]+$ ]] && [[ $sel -ge 1 ]] && [[ $sel -le ${#project_list[@]} ]]; then
                            project_path="${project_list[$((sel-1))]}"
                            project_name=$(basename "$project_path")

                            # Install session-start hook for this project
                            hook_dir="$project_path/.claude/hooks"
                            settings_file="$project_path/.claude/settings.local.json"

                            mkdir -p "$hook_dir"

                            # Copy the backup trigger script
                            if [[ -f "$LIB_DIR/bin/smart-backup-trigger.sh" ]]; then
                                cp "$LIB_DIR/bin/smart-backup-trigger.sh" "$hook_dir/backup-trigger.sh"
                                chmod +x "$hook_dir/backup-trigger.sh"

                                # Update the trigger to use this project's path
                                sed -i.bak "s|PROJECT_BACKUP_SCRIPT=.*|PROJECT_BACKUP_SCRIPT=\"$project_path/.claude/backup-daemon.sh\"|" "$hook_dir/backup-trigger.sh"
                                rm -f "$hook_dir/backup-trigger.sh.bak"
                            fi

                            # Create/update project-local settings with hook
                            if [[ -f "$settings_file" ]]; then
                                # Check if hook already exists
                                if ! grep -q "backup-trigger.sh" "$settings_file" 2>/dev/null; then
                                    echo "  ⚠ $project_name has existing settings.local.json"
                                    echo "    Add hook manually: $hook_dir/backup-trigger.sh"
                                else
                                    echo "  ✓ $project_name (hook already configured)"
                                fi
                            else
                                cat > "$settings_file" << HOOKEOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$hook_dir/backup-trigger.sh",
            "timeout": 1
          }
        ]
      }
    ]
  }
}
HOOKEOF
                                echo "  ✓ $project_name (session-start hook installed)"
                            fi
                        fi
                    done
                    echo ""
                fi
            fi
        fi

        echo "Use 'checkpoint dashboard' to view status and change settings."
    fi
else
    # Manual mode - just configure current directory if it's a project
    if [[ -f "$PWD/package.json" ]] || [[ -f "$PWD/Cargo.toml" ]] || \
       [[ -f "$PWD/go.mod" ]] || [[ -f "$PWD/requirements.txt" ]] || \
       [[ -d "$PWD/.git" ]]; then
        echo "Detected project in current directory: $(basename "$PWD")"
        read -p "Configure this project? (Y/n): " configure_current
        configure_current=${configure_current:-y}

        if [[ "$configure_current" =~ ^[Yy]$ ]]; then
            source "$LIB_DIR/lib/auto-configure.sh"
            generate_config "$PWD" >/dev/null
            register_project "$PWD"
            install_project_daemon "$PWD" 2>/dev/null || true
            echo "✅ Project configured: $(basename "$PWD")"
        fi
    fi

    echo ""
    echo "To configure projects later:"
    echo "  • Run 'backup-now' in any project directory"
    echo "  • Or run 'checkpoint' and select 'Configure Project'"
    echo ""
fi

# ==============================================================================
# INSTALLATION SUCCESS
# ==============================================================================

# Mark installation as successful (prevents rollback)
INSTALL_FAILED=false

# Clean up backup of previous installation
cleanup_backup

# ==============================================================================
# PATH VALIDATION
# ==============================================================================

if [[ "$INSTALL_PREFIX" == "$HOME/.local" ]]; then
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo ""
        echo "⚠️  WARNING: ~/.local/bin is not in your PATH"
        echo ""
        echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo ""
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        echo "Then reload your shell:"
        echo "    source ~/.bashrc  # or ~/.zshrc"
        echo ""
    fi
fi

# ==============================================================================
# OPTIONAL: INSTALL MENU BAR HELPER APP
# ==============================================================================

if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Checkpoint Helper is a menu bar app that:"
    echo "  • Shows backup status at a glance"
    echo "  • Alerts you if the daemon stops"
    echo "  • Provides quick backup controls"
    echo ""
    read -p "Install Checkpoint Helper menu bar app? (Y/n): " install_helper
    install_helper=${install_helper:-y}
    echo ""

    if [[ "$install_helper" =~ ^[Yy]$ ]]; then
        "$LIB_DIR/bin/install-helper.sh" || {
            echo "⚠️  Helper app installation failed (non-critical)"
            echo "   You can install it later with: install-helper"
        }
    fi
fi

echo "To uninstall:"
echo "  backup-uninstall"
echo ""
echo "Or manually:"
echo "  rm -rf $LIB_DIR"
echo "  rm -f $BIN_DIR/{backup-*,checkpoint,configure-project}"
echo ""
echo "═══════════════════════════════════════════════"
