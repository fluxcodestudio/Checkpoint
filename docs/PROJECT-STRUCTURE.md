# Project Structure

Checkpoint is organized into clear, logical directories for professional development and maintenance.

## Root Directory

```
checkpoint/
├── .claude/              # Claude Code skills integration
├── bin/                  # Executable scripts
├── docs/                 # All documentation
├── examples/             # Usage examples
├── integrations/         # Platform integrations
├── lib/                  # Core libraries
├── templates/            # Configuration templates
├── tests/                # Test suite
├── CHANGELOG.md          # Version history
├── CONTRIBUTING.md       # Contribution guidelines
├── LICENSE               # MIT License
├── README.md             # Main documentation
└── VERSION               # Current version (1.3.0)
```

## Directory Details

### `.claude/skills/`
Claude Code skills for backup operations:
- `backup-status/` - View backup status
- `backup-now/` - Trigger immediate backup
- `backup-config/` - Configure backups
- `backup-restore/` - Restore from backups
- `backup-cleanup/` - Clean up old backups

### `bin/`
Executable scripts (all core functionality):
- `backup-status.sh` - Display backup status
- `backup-now.sh` - Manual backup trigger
- `backup-config.sh` - Configuration wizard
- `backup-restore.sh` - Restore wizard
- `backup-cleanup.sh` - Cleanup utility
- `backup-daemon.sh` - Background daemon
- `install.sh` - Installation script
- `install-skills.sh` - Install Claude skills
- `install-integrations.sh` - Integration installer
- `uninstall.sh` - Uninstaller
- `smart-backup-trigger.sh` - Intelligent backup logic

### `docs/`
Complete project documentation:
- `API.md` - Library API reference
- `COMMANDS.md` - Command-line interface guide
- `DEVELOPMENT.md` - Developer guide
- `INTEGRATION-DEVELOPMENT.md` - Creating integrations
- `INTEGRATIONS.md` - User guide for integrations
- `LIBRARY.md` - Core library documentation
- `MIGRATION.md` - Upgrade guide
- `PROJECT-STRUCTURE.md` - This file
- `TESTING.md` - Test suite documentation
- `archive/` - Historical development docs

### `examples/`
Real-world usage examples:

**commands/** - Workflow examples:
- `basic-setup.sh` - Initial setup walkthrough
- `disaster-recovery.sh` - Recovery workflow
- `maintenance.sh` - Routine maintenance
- `advanced-config.sh` - Advanced configuration

**configs/** - Configuration templates:
- `minimal.yaml` - Minimal setup
- `standard.yaml` - Standard setup
- `external-drive.yaml` - External drive setup
- `no-database.yaml` - Files-only backup
- `paranoid.yaml` - Maximum protection

### `integrations/`
Platform-specific integrations:

**lib/** - Shared integration code:
- `integration-core.sh` - Core integration API
- `notification.sh` - Cross-platform notifications
- `status-formatter.sh` - Status formatting

**Platforms:**
- `shell/` - Bash/Zsh integration
- `git/` - Git hooks
- `tmux/` - Tmux status bar
- `direnv/` - Directory environment
- `vim/` - Vim/Neovim plugin
- `vscode/` - VS Code extension
- `generic/` - Generic platform template

### `lib/`
Core backup libraries:
- `backup-lib.sh` - Main backup library
- `archive/` - Old library versions (for reference)

### `templates/`
Configuration templates:
- `backup-config.sh` - Shell config template
- `backup-config.yaml` - YAML config template
- `pre-database.sh` - Pre-backup hook template

### `tests/`
Comprehensive test suite:

**Test Categories:**
- `unit/` - Unit tests for core functions
- `integration/` - Integration/workflow tests
- `e2e/` - End-to-end user journey tests
- `compatibility/` - Platform compatibility tests
- `stress/` - Edge case/stress tests
- `legacy/` - Old tests (for reference)
- `manual/` - Manual testing utilities

**Test Utilities:**
- `test-framework.sh` - Custom test framework
- `smoke-test.sh` - Quick validation (22 tests)
- `run-all-tests.sh` - Full test suite runner
- `reports/` - Test execution reports

## File Naming Conventions

- **Scripts**: `kebab-case.sh` (e.g., `backup-status.sh`)
- **Documentation**: `SCREAMING-KEBAB.md` (e.g., `PROJECT-STRUCTURE.md`)
- **Examples**: `kebab-case.sh` or `.yaml`
- **Tests**: `test-feature-name.sh`

## Development Workflow

1. **Make changes** to bin/ or lib/
2. **Update tests** in tests/
3. **Run smoke test**: `./tests/smoke-test.sh`
4. **Update docs** in docs/
5. **Update CHANGELOG.md**
6. **Update VERSION** if needed
7. **Commit changes**

## Adding New Features

### New Script
1. Add to `bin/`
2. Make executable: `chmod +x bin/new-script.sh`
3. Add tests to `tests/unit/` or `tests/integration/`
4. Document in `docs/COMMANDS.md`

### New Integration
1. Create directory in `integrations/`
2. Add README.md
3. Create installer script
4. Add tests to `tests/integration/test-platform-integrations.sh`
5. Document in `docs/INTEGRATIONS.md`

### New Test
1. Add to appropriate `tests/` subdirectory
2. Use test framework: `source ../test-framework.sh`
3. Update `docs/TESTING.md`

## Quality Standards

- ✅ All scripts must be bash 3.2 compatible
- ✅ All scripts must have syntax validation (`bash -n`)
- ✅ All scripts must have `--help` flag
- ✅ All features must have tests
- ✅ All changes must update CHANGELOG.md
- ✅ Smoke tests must pass (22/22)

## See Also

- [CONTRIBUTING.md](../CONTRIBUTING.md) - Contribution guidelines
- [DEVELOPMENT.md](DEVELOPMENT.md) - Developer guide
- [TESTING.md](TESTING.md) - Testing documentation
