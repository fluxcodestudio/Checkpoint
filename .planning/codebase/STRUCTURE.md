# Codebase Structure

**Analysis Date:** 2026-01-10

## Directory Layout

```
CLAUDE CODE PROJECT BACKUP/
├── .claude/                # Claude Code integration
│   └── skills/            # Skill definitions
├── bin/                   # Primary executables (~9000 LOC)
├── lib/                   # Shared libraries (~5400 LOC)
├── templates/             # Configuration templates
├── integrations/          # Platform integrations
├── tests/                 # Test suite
├── docs/                  # Documentation
├── examples/              # Usage examples
├── website/               # Marketing site
├── .github/               # GitHub metadata
└── README.md              # Main documentation
```

## Directory Purposes

**bin/**
- Purpose: CLI commands and executables
- Contains: `*.sh` scripts for all user-facing commands
- Key files:
  - `backup-now.sh` - Main backup trigger
  - `backup-status.sh` - Status dashboard
  - `backup-daemon.sh` - Background service
  - `backup-restore.sh` - File recovery
  - `backup-cleanup.sh` - Retention cleanup
  - `backup-config.sh` - Configuration wizard
  - `checkpoint.sh` - Command center (TUI)
  - `install.sh` - Per-project setup
  - `install-global.sh` - System-wide installation
  - `install-integrations.sh` - Integration installer
- Subdirectories: None

**lib/**
- Purpose: Shared library functions
- Contains: Core logic sourced by bin scripts
- Key files:
  - `backup-lib.sh` - Foundation library (2485 LOC)
  - `database-detector.sh` - Database auto-detection (1156 LOC)
  - `cloud-backup.sh` - rclone integration (456 LOC)
  - `dependency-manager.sh` - Tool provisioning (487 LOC)
  - `projects-registry.sh` - Multi-project tracking (258 LOC)
  - `dashboard-status.sh` - Status formatting
  - `dashboard-ui.sh` - TUI components
- Subdirectories: `archive/` (legacy versions)

**templates/**
- Purpose: Configuration file templates
- Contains: Template files copied during setup
- Key files:
  - `backup-config.sh` - Shell config template
  - `backup-config.yaml` - YAML config template
  - `global-config-template.sh` - Global settings template
  - `pre-database.sh` - Pre-backup hook template

**integrations/**
- Purpose: Platform-specific integrations
- Contains: Integration installers and hooks
- Key files:
  - `lib/integration-core.sh` - Shared integration code
  - `lib/notification.sh` - Cross-platform notifications
  - `lib/status-formatter.sh` - Status display utilities
- Subdirectories:
  - `shell/` - Bash/Zsh integration
  - `git/` - Git hooks (pre-commit, post-commit, pre-push)
  - `vim/` - Vim/Neovim plugin
  - `vscode/` - VS Code extension (tasks, keybindings)
  - `tmux/` - Tmux status bar
  - `direnv/` - Directory environment
  - `generic/` - Template for custom integrations

**tests/**
- Purpose: Test suite
- Contains: Test scripts and framework
- Key files:
  - `test-framework.sh` - Custom test runner
  - `smoke-test.sh` - Quick validation (22 tests)
  - `run-all-tests.sh` - Full suite runner
- Subdirectories:
  - `unit/` - Unit tests
  - `integration/` - Integration tests
  - `e2e/` - End-to-end tests
  - `stress/` - Load/edge case tests
  - `compatibility/` - Platform compatibility
  - `reports/` - Test output

**docs/**
- Purpose: Documentation
- Contains: Guides and references
- Key files:
  - `COMMANDS.md` - CLI reference
  - `API.md` - Library API
  - `DEVELOPMENT.md` - Developer guide
  - `INTEGRATIONS.md` - Integration guide
  - `TESTING.md` - Test guide
  - `CLOUD-BACKUP.md` - Cloud setup
  - `MIGRATION.md` - Upgrade guide

**examples/**
- Purpose: Usage examples
- Contains: Sample workflows and configs
- Subdirectories:
  - `commands/` - Workflow examples
  - `configs/` - Configuration templates

**.claude/skills/**
- Purpose: Claude Code skill definitions
- Contains: Skill directories with skill.json and run.sh
- Subdirectories:
  - `checkpoint/` - TUI dashboard skill
  - `backup-pause/` - Pause/resume skill
  - `backup-update/` - Update skill
  - `uninstall/` - Uninstall skill

## Key File Locations

**Entry Points:**
- `bin/backup-now.sh` - Main backup command
- `bin/checkpoint.sh` - Command center entry
- `bin/install.sh` - Installation entry

**Configuration:**
- `templates/backup-config.sh` - Configuration template
- `.backup-config.sh` - User config (project root)
- `~/.config/checkpoint/projects.json` - Global project registry

**Core Logic:**
- `lib/backup-lib.sh` - Foundation functions
- `lib/database-detector.sh` - Database detection
- `lib/cloud-backup.sh` - Cloud integration

**Testing:**
- `tests/smoke-test.sh` - Quick validation
- `tests/run-all-tests.sh` - Full suite

**Documentation:**
- `README.md` - Main documentation
- `docs/COMMANDS.md` - CLI reference

## Naming Conventions

**Files:**
- kebab-case.sh: All shell scripts (`backup-status.sh`, `database-detector.sh`)
- kebab-case.md: Documentation (`CLOUD-BACKUP.md`)
- SCREAMING_CASE.md: Important project files (`README.md`, `CHANGELOG.md`)

**Directories:**
- kebab-case: All directories (`backup-pause/`, `cloud-backup/`)
- Plural for collections: `templates/`, `integrations/`, `tests/`

**Special Patterns:**
- `*.sh` for all executable scripts
- `test-*.sh` for test files
- `install-*.sh` for installation scripts

## Where to Add New Code

**New CLI Command:**
- Implementation: `bin/{command-name}.sh`
- Documentation: Update `docs/COMMANDS.md`
- Tests: `tests/unit/test-{command}.sh`

**New Library Function:**
- Implementation: Add to appropriate `lib/*.sh` file
- Documentation: Update `docs/API.md`
- Tests: `tests/unit/test-core-functions.sh`

**New Integration:**
- Implementation: `integrations/{platform}/`
- Installer: `integrations/{platform}/install-{platform}.sh`
- Documentation: Update `docs/INTEGRATIONS.md`

**New Claude Skill:**
- Directory: `.claude/skills/{skill-name}/`
- Metadata: `skill.json`
- Runner: `run.sh`

## Special Directories

**backups/**
- Purpose: Generated backup data
- Source: Created by backup operations
- Committed: No (in .gitignore)
- Structure:
  - `databases/` - Compressed DB snapshots
  - `files/` - Current file versions
  - `archived/` - Old file versions

**lib/archive/**
- Purpose: Legacy library versions
- Source: Historical code for reference
- Committed: Yes

---

*Structure analysis: 2026-01-10*
*Update when directory structure changes*
