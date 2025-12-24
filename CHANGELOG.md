# Changelog

All notable changes to ClaudeCode Project Backups will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
