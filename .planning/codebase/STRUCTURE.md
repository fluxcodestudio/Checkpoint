# Codebase Structure

**Analysis Date:** 2026-02-12

## Directory Layout

```
Checkpoint/
├── bin/                    # CLI entry points (31 scripts, ~13,695 lines)
├── lib/                    # Core service libraries (13 modules, ~9,671 lines)
│   └── archive/            # Archived/deprecated library code
├── integrations/           # Editor and tool integrations
│   ├── direnv/             # direnv auto-load
│   ├── generic/            # Generic integration utilities
│   ├── git/                # Git hooks integration
│   ├── lib/                # Shared integration libraries
│   ├── shell/              # Bash/Zsh prompt integration
│   ├── tmux/               # tmux status bar
│   ├── vim/                # Vim/Neovim plugin
│   └── vscode/             # VS Code tasks and keybindings
├── templates/              # Configuration and plist templates
├── tests/                  # Test suite (290+ tests)
│   ├── compatibility/      # Bash version compatibility tests
│   ├── e2e/                # End-to-end user journey tests
│   ├── integration/        # Multi-module integration tests
│   ├── legacy/             # Legacy system compatibility
│   ├── manual/             # Manual test procedures
│   ├── stress/             # Edge cases and stress tests
│   └── reports/            # Test result reports (txt, json, html)
├── docs/                   # Documentation
│   └── archive/            # Archived docs
├── examples/               # Example configurations
│   ├── commands/           # Example CLI commands
│   └── configs/            # Example config files
├── helper/                 # macOS helper app
│   └── CheckpointHelper/  # Login item helper
├── images/                 # README images/screenshots
├── skills/                 # Claude Code skill definitions
├── .claude/                # Claude Code integration
│   ├── commands/           # Slash commands
│   ├── hooks/              # Event hooks
│   └── skills/             # Skill manifests
├── .planning/              # GSD project planning
├── backups/                # Backup data (gitignored in production)
│   ├── files/              # Current file versions
│   ├── archived/           # Timestamped old versions
│   └── databases/          # Compressed database dumps
├── CLAUDE.md               # Claude Code project instructions
├── CONTRIBUTING.md         # Coding standards and guidelines
├── README.md               # User documentation
└── CODING.md               # Additional coding notes
```

## Directory Purposes

**bin/**
- Purpose: All user-facing CLI commands
- Contains: 31 executable `.sh` scripts
- Key files: `backup-now.sh`, `backup-daemon.sh`, `checkpoint-dashboard.sh`, `backup-config.sh`, `backup-restore.sh`, `install.sh`, `install-global.sh`
- Pattern: Each script is a standalone command with `--help` support

**lib/**
- Purpose: Shared service libraries sourced by CLI scripts
- Contains: 13 library modules
- Key files:
  - `backup-lib.sh` (3,216 lines) — Foundation: config, validation, file ops, error codes
  - `database-detector.sh` (1,163 lines) — DB detection and backup (SQLite, PostgreSQL, MySQL, MongoDB)
  - `auto-configure.sh` (1,290 lines) — Smart project setup and detection
  - `cloud-backup.sh` (516 lines) — rclone-based cloud sync
  - `cloud-folder-detector.sh` (335 lines) — Cloud storage folder detection
  - `restore-lib.sh` (404 lines) — Point-in-time restore operations
  - `retention-policy.sh` (258 lines) — Tiered retention management
  - `dependency-manager.sh` (532 lines) — Progressive dependency installation
  - `dashboard-status.sh` — Dashboard data provider
  - `dashboard-ui.sh` — TUI rendering (dialog/text fallback)
  - `projects-registry.sh` — Multi-project registry management
  - `global-status.sh` — Cross-project health monitoring
  - `backup-queue.sh` — Offline backup queue for failed cloud uploads

**integrations/**
- Purpose: External tool integration scripts
- Pattern: Each subdirectory has an `install-*.sh` script + runtime integration script
- Key files: `lib/notification.sh` (cross-platform notifications), `lib/integration-core.sh` (shared utilities), `shell/backup-shell-integration.sh` (prompt integration)

**templates/**
- Purpose: Configuration templates copied during installation
- Key files: `backup-config.sh`, `backup-config.yaml`, `global-config-template.sh`, `com.checkpoint.watchdog.plist`

**tests/**
- Purpose: Comprehensive test suite
- Key files: `test-framework.sh` (custom framework), `run-all-tests.sh` (master runner), `smoke-test.sh` (quick validation)

## Key File Locations

**Entry Points:**
- `bin/backup-now.sh` — Primary backup command
- `bin/checkpoint.sh` — Command center
- `bin/checkpoint-dashboard.sh` — Interactive dashboard
- `bin/checkpoint-watchdog.sh` — LaunchAgent daemon

**Configuration:**
- `templates/backup-config.sh` — Bash config template
- `templates/backup-config.yaml` — YAML config template
- `templates/global-config-template.sh` — Global defaults
- `templates/com.checkpoint.watchdog.plist` — macOS LaunchAgent

**Core Logic:**
- `lib/backup-lib.sh` — Foundation library
- `lib/database-detector.sh` — Database operations
- `lib/cloud-backup.sh` — Cloud sync
- `lib/retention-policy.sh` — Retention management

**Testing:**
- `tests/test-framework.sh` — Test framework
- `tests/run-all-tests.sh` — Test runner
- `tests/smoke-test.sh` — Quick smoke tests

**Documentation:**
- `README.md` — User guide
- `CONTRIBUTING.md` — Coding standards
- `CLAUDE.md` — Claude Code instructions
- `docs/TESTING.md` — Testing strategy

## Naming Conventions

**Files:**
- `kebab-case.sh` — All shell scripts (`backup-now.sh`, `cloud-backup.sh`)
- `UPPERCASE.md` — Important project files (`README.md`, `CONTRIBUTING.md`, `CLAUDE.md`)
- `test-*.sh` — Test files (`test-core-functions.sh`, `test-edge-cases.sh`)
- `install-*.sh` — Installer scripts (`install-global.sh`, `install-integrations.sh`)

**Directories:**
- `kebab-case` — All directories (`cloud-folder-detector`, `e2e`)
- Descriptive names — `bin/`, `lib/`, `tests/`, `templates/`, `integrations/`

**Special Patterns:**
- `.backup-config.sh` — Per-project config (dotfile)
- `com.checkpoint.watchdog.plist` — Reverse-DNS for macOS

## Where to Add New Code

**New CLI Command:**
- Script: `bin/{command-name}.sh`
- Source: `lib/backup-lib.sh` + relevant service libraries
- Help: Include `--help` flag support
- Tests: `tests/integration/test-{feature}.sh` or `tests/unit/test-{feature}.sh`

**New Service Library:**
- Implementation: `lib/{service-name}.sh`
- Header: Standard `# ===` block with version, description, usage, features
- Functions: `lowercase_snake_case()` with `# Args:` / `# Returns:` docs
- Tests: `tests/unit/test-{service}.sh`

**New Integration:**
- Directory: `integrations/{tool-name}/`
- Installer: `integrations/{tool-name}/install-{tool-name}.sh`
- Runtime: `integrations/{tool-name}/{tool-name}-integration.sh`

**New Test:**
- Unit: `tests/unit/test-{subject}.sh`
- Integration: `tests/integration/test-{workflow}.sh`
- E2E: `tests/e2e/test-{journey}.sh`

## Special Directories

**backups/**
- Purpose: Backup data storage (files, archives, databases)
- Source: Generated by backup operations
- Committed: Only in this repo for testing; gitignored in production installs

**lib/archive/**
- Purpose: Deprecated library code preserved for reference
- Source: Moved here during refactoring
- Committed: Yes (historical reference)

**.planning/**
- Purpose: GSD project planning documents
- Source: Generated by GSD framework
- Committed: Yes

---

*Structure analysis: 2026-02-12*
*Update when directory structure changes*
