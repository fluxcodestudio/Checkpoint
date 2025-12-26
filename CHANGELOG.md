# Changelog

All notable changes to Checkpoint will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

**Non-Git Repository Support** - Backup ANY directory, git optional

- **Automatic Fallback:** Detects when git is not available and uses filesystem scan instead
- **First Backup:** Uses `find` to copy all files (excluding node_modules, dist, build, .venv, __pycache__)
- **Incremental Backup:** Uses `mtime` to detect files modified in last backup interval
- **Verbose Logging:** Shows "No git repository detected - using file system scan"
- **Zero Configuration:** Works automatically, no setup needed
- **Use Case:** Perfect for non-code projects, legacy codebases, or directories without version control

### Fixed

**Critical set -euo pipefail Bugs** - Script exited prematurely during backup

- **Fixed:** `((var++))` arithmetic expansion returning 0 caused exit when var=0 (lines 539, 541, 549)
  - Changed to `var=$((var + 1))` to always return success
- **Fixed:** `[ condition ] && command` pattern caused exit when condition false (lines 523-525)
  - Changed to `if [ condition ]; then command; fi` for proper `set -e` handling
- **Fixed:** Conditional logging caused exits
  - Changed from `[ "$VERBOSE" = true ] && log_verbose "..."` to proper if statements
- **Impact:** Backup would only process first file then exit, now processes all files correctly

## [2.2.0] - 2025-12-25

### Fixed

**CRITICAL: Database Auto-Detection** - Only detect project-specific databases

- **Fixed:** Database detector was backing up system databases (mysql, postgres user db, mongodb admin) for projects without databases
- **Root Cause:** Automatic fallback detection triggered when PostgreSQL/MySQL/MongoDB servers were running
- **Solution:** Removed automatic fallback detection. Now ONLY detects:
  - SQLite files in project directory
  - Databases explicitly configured in .env files (DATABASE_URL, MYSQL_*, etc.)
- **Impact:** Projects without databases will no longer incorrectly backup system databases

### Added

**Universal Database Support** - Auto-detect and backup PostgreSQL, MySQL, MongoDB

- **Multi-Database Detection:** Auto-detects SQLite, PostgreSQL, MySQL, MongoDB from:
  - File patterns (*.db, *.sqlite, *.sqlite3)
  - Environment variables (DATABASE_URL, POSTGRES_URL, MYSQL_*, MONGODB_URL)
  - Running processes (postgres, mysqld, mongod)
  - Configuration files (.env, .env.local, .env.development)
- **Local vs Remote Detection:** Automatically distinguishes local databases from remote (Neon, Supabase, PlanetScale)
  - Local databases: Backed up automatically
  - Remote databases: Skipped (displayed in detection but not backed up)
- **Progressive Tool Installation:** Database tools installed only when needed:
  - `pg_dump` / `pg_restore` for PostgreSQL
  - `mysqldump` for MySQL/MariaDB
  - `mongodump` / `mongorestore` for MongoDB
  - One consolidated approval for all tools
- **Smart Backup Functions:**
  - SQLite: File copy + gzip compression
  - PostgreSQL: pg_dump with schema + data
  - MySQL: mysqldump with complete schema
  - MongoDB: mongodump with BSON export

**New Files:**
- `lib/database-detector.sh` - Universal database detection (450+ lines)
- `lib/dependency-manager.sh` - Enhanced with database tool installers

**Streamlined Installation UX** - Lightning-fast wizard (~20 seconds)

- **Reduced Questions:** 15+ questions → 5 questions
  - 1/4: Back up detected databases? (Y/n)
  - 2/4: Enable cloud backup? (y/N)
  - 3/4: Install hourly backups? (Y/n)
  - 4/4: Claude Code integration? (Y/n)
  - Final: Run initial backup? (Y/n)
- **Consolidated Dependency Approval:** One approval for all tools instead of multiple interruptions
- **Clear Progress Indicators:** [1/5] [2/5] [3/5] [4/5] [5/5] ✓
- **Silent Installation:** Minimal output, redirected noise to /dev/null
- **Smart Defaults:** No retention prompts, no drive verification prompts (can enable later)

**Per-Project Mode Improvements**

- **Complete Command Suite:** All commands now available in `./bin/`
  - `./bin/backup-now.sh`
  - `./bin/backup-status.sh`
  - `./bin/backup-restore.sh`
  - `./bin/backup-cleanup.sh`
  - `./bin/backup-cloud-config.sh`
- **Library Files Included:** All libraries copied to `.claude/lib/`
- **Fully Self-Contained:** No external dependencies after installation

**Expanded .gitignore File Coverage** - Comprehensive local backup of excluded files

- **Cloud Provider Configs:**
  - AWS credentials (`.aws/credentials`, `.aws/config`)
  - GCP service accounts (`*.gcp/*.json`)
- **Infrastructure as Code:**
  - Terraform secrets (`terraform.tfvars`, `*.tfvars`)
  - Firebase configs (`*.firebase/*.json`)
- **Local Configuration Overrides:**
  - All `*.local.*` pattern files
  - `local.settings.json` (Azure Functions)
  - `appsettings.*.json` (ASP.NET)
  - `docker-compose.override.yml`
- **Enhanced IDE Settings:**
  - `.vscode/extensions.json` (recommended extensions)
  - `.idea/codeStyles/*` (code formatting preferences)
- **Consistency:** Same patterns applied to both backup and dry-run modes

### Changed

**Installation Flow** - All questions upfront, uninterrupted installation

- **Phase 1: Configuration** (all questions asked first)
- **Phase 2: Installation** (no more prompts, smooth progress)
- **Transparent Dependency Installation:** Shows what will be installed before approval
- **Better Error Messages:** Clear feedback if installation fails

**Backup Process** - Universal database backup

- `backup-now.sh` now uses `backup_detected_databases()` from database-detector.sh
- Automatic fallback to legacy SQLite backup if detector unavailable
- Database backup section now shows "Auto-detecting..." instead of manual config

### Fixed

**Installation Issues**

- Fixed unbound variable `DRIVE_MARKER_FILE` in install.sh
- Fixed missing `bin/` directory in per-project installations
- Fixed library files not being copied to per-project installations

**Database Detection Regex**

- Fixed regex compilation errors in MongoDB URL parsing
- Fixed `+srv` URL parsing with proper escaping
- Fixed PostgreSQL/MySQL URL pattern matching

**Security & Privacy**

- Sanitized MANUAL-TEST-GUIDE.md (removed personal usernames)
- Added SECURITY.md with vulnerability reporting guidelines
- Created GitHub issue templates (bug report, feature request)
- Created Pull Request template with comprehensive checklist

**Documentation**

- README.md updated for v2.2.0 features
- Added "What's New in v2.2.0" section
- Updated Quick Start with new installation flow
- Updated database support documentation

---

## [2.1.0] - 2025-12-24

### Added

**Cloud Backup Support** - Off-site protection via rclone

- **Cloud Storage Integration:** Automatic uploads to Dropbox, Google Drive, OneDrive, or iCloud Drive
- **Smart Upload Strategy:** Databases + critical files only (fits in free tiers)
- **Background Uploads:** Don't block local backups
- **Interactive Wizard:** `./bin/backup-cloud-config.sh` for easy setup
- **Free Tier Support:** ~65MB for 30 days retention fits all providers

**New Files:**
- `lib/cloud-backup.sh` - Core cloud upload functions
- `bin/backup-cloud-config.sh` - Configuration wizard
- `docs/CLOUD-BACKUP.md` - Complete setup guide
- `tests/integration/test-cloud-backup.sh` - Cloud tests (13 tests)

**Configuration Options:**
```bash
BACKUP_LOCATION="both"         # local | cloud | both
CLOUD_PROVIDER="dropbox"       # dropbox | gdrive | onedrive | icloud
CLOUD_SYNC_DATABASES=true      # Upload compressed DBs (~2MB)
CLOUD_SYNC_CRITICAL=true       # Upload .env, credentials
CLOUD_SYNC_FILES=false         # Skip large project files
```

**Integration:**
- `backup-daemon.sh` - Auto-upload after local backup (background)
- `backup-status.sh` - Show last cloud upload time
- README.md - Cloud backup feature listed

**Provider Comparison:**
- Dropbox: 2GB free
- Google Drive: 15GB free (most generous)
- OneDrive: 5GB free
- iCloud Drive: 5GB free

### Fixed

**Test Suite:** All tests now pass (164/164 = 100%)
- Fixed cloud backup test logic
- Fixed validation checks
- All integration tests passing

---

## [2.0.0] - 2025-12-24

### Changed

**Project Rebrand** - "ClaudeCode Project Backups" → "Checkpoint"

- **New Name:** Checkpoint
- **New Tagline:** "A code guardian for developing projects. A little peace of mind goes a long way."
- **Reasoning:** Project has evolved beyond Claude Code to be a universal backup system for any development environment
- **Impact:** Branding and documentation updated; no breaking changes to functionality

**Updated Branding:**
- README.md - New title and tagline
- All documentation references updated
- User-facing messages updated
- Internal functionality unchanged

**Backward Compatibility:**
- All existing installations continue to work without changes
- Configuration files remain compatible
- No migration required
- Command names and functionality unchanged

### Fixed

**macOS Bash 3.2 Compatibility** - `bin/install-integrations.sh`

- **Issue:** Used associative arrays (`declare -A`) which require bash 4.0+
- **Impact:** Installation wizard failed on macOS default bash 3.2.57
- **Fix:** Refactored to use simple variables instead of associative arrays
  - Replaced `PLATFORM_AVAILABLE[shell]` → `PLATFORM_AVAILABLE_shell`
  - Replaced `PLATFORM_SELECTED[shell]` → `PLATFORM_SELECTED_shell`
  - Replaced `PLATFORM_INSTALLED[shell]` → `PLATFORM_INSTALLED_shell`
  - Updated all array loops to individual variable checks
  - Menu system refactored to use string-based mapping
- **Result:** Fully compatible with bash 3.2+ (macOS default)

---

## [1.2.0] - 2025-12-24

### Added

**Universal Integration System** - Extend backup functionality to any development environment

**Integration Core Libraries** - Shared utilities for all platform integrations
- **`integrations/lib/integration-core.sh`** - Core integration API (300+ lines)
  - `integration_init()` - Initialize integration, verify backup system
  - `integration_trigger_backup([OPTIONS])` - Debounced backup trigger (--force, --quiet, --dry-run)
  - `integration_get_status([OPTIONS])` - Get backup status (--compact, --json, --timeline)
  - `integration_get_status_compact()` - One-line status output
  - `integration_get_status_emoji()` - Just status emoji (✅/⚠️/❌)
  - `integration_check_lock()` - Check if backup currently running
  - `integration_should_trigger([INTERVAL])` - Debounce helper (default: 300s)
  - `integration_debounce(INTERVAL COMMAND)` - Generic debounce wrapper
  - `integration_format_time_ago(SECONDS)` - Human-readable time formatting
  - `integration_time_since_backup()` - Time since last backup

- **`integrations/lib/notification.sh`** - Cross-platform notifications
  - `notify_success()`, `notify_error()`, `notify_warning()`, `notify_info()`
  - macOS native notifications (osascript/terminal-notifier)
  - Linux desktop notifications (notify-send)
  - Terminal fallback for all platforms

- **`integrations/lib/status-formatter.sh`** - Consistent output formatting
  - `format_duration()`, `format_size()` - Human-readable formatting
  - `format_success()`, `format_error()` - Emoji + color output
  - NO_COLOR support, piped output detection

**Shell Integration** (`integrations/shell/`)
- Backup status in shell prompt (PS1/PROMPT)
- Auto-trigger on directory change (debounced, git-aware)
- Quick command aliases: `bs`, `bn`, `bc`, `bcl`, `br`
- Unified `backup` command dispatcher
- Configuration: BACKUP_AUTO_TRIGGER, BACKUP_SHOW_PROMPT, BACKUP_TRIGGER_INTERVAL
- Compatible with bash 3.2+, zsh 5.0+
- Installer: `integrations/shell/install.sh`

**Git Hooks Integration** (`integrations/git/`)
- **pre-commit** - Auto-backup before commits (debounced)
- **post-commit** - Show backup status after commits
- **pre-push** - Verify backups current before pushes
- Smart detection (skip if backup already recent <5min)
- Configuration via environment variables
- Installer: `integrations/git/install-git-hooks.sh`

**Direnv Integration** (`integrations/direnv/`)
- Auto-load backup commands on `cd` into project
- Show backup status on directory entry
- Optional auto-trigger on directory change
- Add bin/ to PATH automatically
- Template: `integrations/direnv/.envrc.template`

**Tmux Integration** (`integrations/tmux/`)
- Backup status in tmux status bar
- Auto-refresh every 60 seconds
- Key bindings for quick access
- Configurable format and position
- Installer: `integrations/tmux/install.sh`

**VS Code Extension** (`integrations/vscode/`)
- Extension skeleton and package.json
- Command palette integration (framework)
- Status bar indicator (framework)
- Auto-trigger on save (framework)
- Configuration settings schema
- README with installation instructions

**Vim/Neovim Plugin** (`integrations/vim/`) - **FULLY IMPLEMENTED**
- **Commands:**
  - `:BackupStatus` - Show status dashboard in split window
  - `:BackupNow` - Trigger backup (debounced)
  - `:BackupNowForce` - Force backup (bypass debounce)
  - `:BackupRestore` - Launch restore wizard in terminal
  - `:BackupCleanup` - Show cleanup preview
  - `:BackupConfig` - Open .backup-config.sh
- **Key Mappings:** `<leader>bs`, `<leader>bn`, `<leader>bf`, `<leader>br`, `<leader>bc`, `<leader>bC`
- **Auto-trigger:** BufWritePost with configurable delay (default: 1000ms)
- **Async Support:** Vim 8+ jobs and Neovim jobstart()
- **Notifications:** Neovim floating windows with auto-close
- **Status Line:** Integration with vim-airline, lightline, lualine (60s cache)
- **Configuration:**
  - `g:backup_auto_trigger` - Enable/disable auto-backup on save
  - `g:backup_trigger_delay` - Debounce delay in milliseconds
  - `g:backup_key_prefix` - Key mapping prefix (default: `<leader>`)
  - `g:backup_notifications` - Enable/disable notifications
  - `g:backup_bin_path` - Path to backup bin directory
  - `g:backup_statusline_format` - emoji/compact/verbose
  - `g:backup_no_mappings` - Disable default key mappings
- **Help Documentation:** Complete `:help backup` documentation
- **Plugin Manager Support:** vim-plug, Vundle, Pathogen, native packages
- **Compatibility:** Vim 8.0+, Neovim 0.5+

**Unified Installer** (`bin/install-integrations.sh`)
- Interactive wizard with beautiful color formatting
- Auto-detects available platforms (shell, git, tmux, direnv, VS Code, Vim)
- Platform detection functions for all 6 integrations
- Individual install functions with progress indicators
- `--auto` mode for non-interactive installation
- `--quiet` mode for minimal output
- `--help` documentation
- Error handling and backup creation
- Comprehensive success summary with next steps

**Documentation**
- **`docs/INTEGRATIONS.md`** (500+ lines) - Complete user guide
  - Overview of all 6 integrations
  - Installation instructions for each platform
  - Configuration reference with examples
  - Integration matrix table showing features
  - Troubleshooting guide
  - FAQ section
  - Architecture diagrams
  - Platform compatibility chart

- **`docs/INTEGRATION-DEVELOPMENT.md`** (600+ lines) - Developer guide
  - Integration architecture overview
  - Complete Integration Core API reference
  - notification.sh and status-formatter.sh APIs
  - Step-by-step guide for creating new integrations
  - Integration template with complete example
  - Best practices and anti-patterns
  - Testing guidelines
  - Contributing guidelines
  - Code style guide
  - Example integrations (Fish shell, systemd timer)

### Improved

- **Modularity** - All integrations are optional and independent
- **Consistency** - Shared APIs provide consistent behavior across platforms
- **Documentation** - 2000+ lines of comprehensive documentation
- **Testing** - Complete integration test suite
- **Portability** - Works on macOS and Linux without modification

### Technical Details

- **Architecture:** Universal integration layer on top of core backup system
- **Compatibility:** Backward compatible with v1.1.0 and v1.0.x
- **Platform Support:** macOS 12+, Linux (Ubuntu 20.04+)
- **Shell Compatibility:** bash 3.2+, zsh 5.0+
- **New Files:**
  - Integration core: 3 library files (~800 lines)
  - Shell integration: 3 files (~400 lines)
  - Git integration: 4 files (~300 lines)
  - Direnv integration: 2 files (~100 lines)
  - Tmux integration: 2 files (~200 lines)
  - VS Code extension: 3 files (~500 lines framework)
  - Vim plugin: 4 files (~600 lines)
  - Unified installer: 1 file (~600 lines)
  - Documentation: 3 files (~2000 lines)
  - Tests: Integration test suite (~400 lines)
- **Total Lines of Code:** ~3000 (integration system)
- **Total Documentation:** ~2000 lines
- **Deliverables:** 34/34 (100% complete)

### Migration Notes

- All integrations are opt-in and non-invasive
- Existing v1.1.0 installations continue to work unchanged
- Run `./bin/install-integrations.sh` to add platform integrations
- No breaking changes to core backup system
- All backup data remains fully compatible

### Known Limitations

- VS Code extension is framework/documentation only (requires packaging)
- Windows support not included (macOS/Linux only)
- Cloud IDE support planned for future release

---

## [1.1.0] - 2025-12-24

### Added

**Command System** - 5 new commands for backup management

- **`/backup-status`** - Health monitoring dashboard (v1.0.0)
  - Multiple output modes (dashboard, compact, timeline, JSON)
  - Component health checks
  - Backup statistics
  - Smart warnings and recommendations

- **`/backup-now`** - Manual backup trigger (v1.0.0)
  - Force mode to bypass interval checks
  - Dry-run preview mode
  - Selective backup (database-only, files-only)
  - Verbose progress output
  - Pre-flight validation checks

- **`/backup-config`** - Configuration management (v1.1.0 - NEW)
  - Help text and command structure
  - Get/set mode framework
  - Wizard and validation modes (planned)

- **`/backup-cleanup`** - Smart space management (v1.1.0 - NEW)
  - Preview mode for safe cleanup
  - Recommendations for optimization
  - Selective cleanup options
  - Help text and command structure

- **`/backup-restore`** - Restore wizard (v1.1.0 - NEW)
  - Interactive restore framework
  - List, database, and file restore modes
  - Help text and command structure

**Foundation Library** - Shared utilities (`lib/backup-lib.sh`)
- 70+ shared functions
- Configuration loading
- File locking (atomic, with stale detection)
- Time utilities (format_time_ago, format_duration)
- Size utilities (format_bytes, get_dir_size_bytes)
- Health check functions
- Statistics gathering
- Color output (bash 3.2 compatible)
- JSON utilities
- Logging functions

**Claude Code Skills Integration**
- Skills installer for all 5 commands
- All commands available as `/backup-*` skills
- Standalone script execution also supported

**Documentation**
- [docs/COMMANDS.md](docs/COMMANDS.md) - Complete command reference with usage examples
- [docs/BACKUP-COMMANDS-IMPLEMENTATION.md](docs/BACKUP-COMMANDS-IMPLEMENTATION.md) - Implementation guide
- IMPLEMENTATION-SUMMARY.md - Full implementation summary

**Testing**
- Updated test suite to cover all 5 commands
- Script existence and executability tests
- Help text validation
- Integration tests (shebang, strict mode, library sourcing)

### Fixed

- **macOS Compatibility** - Fixed bash 3.2 compatibility issues
  - Removed bash 4.0+ associative arrays (commented out config schema)
  - Removed bash 4.3+ `-v` test operator
  - Removed bash 4.2+ `-g` flag from declare
  - Fixed color variable initialization to avoid readonly conflicts

- **Variable Naming** - Fixed backup-config.sh library path variable (LIB_PATH → LIBBACKUP_PATH)

- **Help System** - Fixed --help handling in backup-cleanup.sh and backup-restore.sh
  - Commands now handle --help before trying to load project configuration

### Improved

- **Color Handling** - Improved color output for piped commands and NO_COLOR support
- **Help Text** - All 5 commands now have comprehensive --help output
- **Error Handling** - Better error messages when configuration not found

### Technical Details

- **Architecture:** Modular design with foundation library
- **Compatibility:** Bash 3.2+ (macOS default), fully backward compatible with v1.0.x
- **New Files:**
  - `lib/backup-lib.sh` - Core library (1560+ lines, updated from v1.0.0)
  - `bin/backup-status.sh` - Status command (400+ lines)
  - `bin/backup-now.sh` - Manual backup command (500+ lines)
  - `bin/backup-config.sh` - Configuration command (729 lines)
  - `bin/backup-cleanup.sh` - Cleanup command (595 lines)
  - `bin/backup-restore.sh` - Restore command (592 lines)
  - `bin/install-skills.sh` - Skills installer (updated for all 5 commands)
  - `bin/test-commands.sh` - Test suite (updated for all 5 commands)
- **Skills:** 5 Claude Code skills installed to `.claude/skills/`
- **Testing:** Comprehensive test suite validates all commands
- **Total Lines of Code:** ~4000

### Known Limitations

- **Config Schema**: Advanced config management functions relying on associative arrays (bash 4.0+) are commented out for bash 3.2 compatibility
- **Interactive TUI**: Some interactive modes mentioned in documentation are planned features for future releases
- **Templates**: Config template system is framework only in v1.1.0

### Migration Notes

- Existing v1.0.x installations continue to work without modification
- All backup data remains compatible (no format changes)
- LaunchAgent and hooks unchanged
- New commands are additive - no breaking changes

---

## [1.0.1] - 2025-12-24

### Added
- **File Locking System** - Prevents duplicate backups when daemon and hook run simultaneously
  - Cross-platform implementation using atomic `mkdir` (works on macOS + Linux without dependencies)
  - Automatic stale lock detection and cleanup using PID verification
  - Graceful skipping with clear logging when another backup is running
  - Lock stored in `~/.claudecode-backups/locks/` (user-specific, persistent)
  - Automatic lock cleanup via trap on script exit (even on crash/kill)

### Improved
- **Installer UX** - Better guidance for users without Homebrew
  - Added Homebrew installation link (https://brew.sh) to dependency error message
  - Clearer messaging that Homebrew is recommended but not required

### Technical Details
- Lock implementation uses atomic `mkdir` operation (POSIX-guaranteed atomicity)
- PID-based stale lock detection prevents indefinite lock persistence
- No external dependencies (flock not available on macOS by default)
- Backwards compatible with existing installations

---

## [1.0.0] - 2025-12-24

### Initial Release

#### Added
- **Core Backup System**
  - Automated hourly backup daemon via LaunchAgent
  - Smart change detection (only backs up modified files)
  - Database snapshots with gzip compression (SQLite support)
  - Version archiving (old versions preserved when files change)
  - Dual-trigger system (hourly daemon + Claude Code prompt hooks)

- **Critical File Coverage**
  - Environment files (.env, .env.*)
  - Credentials (*.pem, *.key, credentials.json, secrets.*)
  - IDE settings (.vscode, .idea workspace)
  - Local notes (NOTES.md, *.private.md)
  - Local databases (*.db, *.sqlite)

- **Features**
  - External drive verification for multi-computer workflows
  - Graceful degradation when drive disconnected
  - Configurable retention policies (separate for DB and files)
  - Pre-restore backup safety
  - Database safety hook (blocks destructive SQL operations)
  - Optional auto-commit to git after backups

- **Utilities**
  - Interactive installer (install.sh)
  - Restore utility with version selection (restore.sh)
  - Status checker with health warnings (status.sh)
  - Clean uninstaller (uninstall.sh)
  - Comprehensive test suite

- **Documentation**
  - Complete README with usage examples
  - Advanced integration guide (INTEGRATION.md)
  - Sample configurations
  - MIT License

#### Technical Details
- Platform: macOS (primary), Linux (partial support)
- Language: Bash with strict error handling (set -euo pipefail)
- Dependencies: bash, git, sqlite3, gzip, launchctl (macOS)
- Lines of Code: ~2,900 (scripts + docs)
- Battle-tested: 150+ files, production usage on SUPERSTACK project

---

## [Unreleased]

### Planned
- GitHub Actions CI/CD
- Extended Linux support
- PostgreSQL/MySQL backup support
- Cloud backup integration options
