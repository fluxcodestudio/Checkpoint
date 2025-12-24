# Project Reorganization Plan

## Issues Identified

### 1. Root Directory Clutter
- ❌ IMPLEMENTATION-SUMMARY.md (development doc)
- ❌ PLAN.md / PLAN.md.delta (development files)
- ❌ TODO.md / TODO.md.delta (development files)
- ❌ .DS_Store files throughout project

### 2. bin/ Directory
- ❌ restore.sh (duplicate of backup-restore.sh?)
- ❌ status.sh (duplicate of backup-status.sh?)
- ❌ test-commands.sh (belongs in /tests)

### 3. docs/ Directory
- ⚠️ INTEGRATION.md vs INTEGRATIONS.md (potential duplicate)
- ✅ Otherwise well organized

### 4. examples/ Directory
- ❌ .DS_Store file
- ⚠️ examples/integrations/ exists but empty

### 5. lib/ Directory
- ❌ Multiple README/guide files that belong in /docs:
  - DELIVERY_SUMMARY.md
  - IMPLEMENTATION_GUIDE.md
  - QUICKSTART.md
  - README_LIBRARY.md
- ❌ Old library version: backup-lib-v1.1.0.sh
- ❌ test-library.sh (belongs in /tests)

### 6. tests/ Directory
- ❌ .DS_Store file
- ⚠️ Mix of old and new test files
- ✅ Good categorization (unit, integration, e2e, etc.)

### 7. Missing Files
- ❌ .gitignore needs updating
- ❌ No CONTRIBUTING.md
- ❌ No project structure documentation

## Reorganization Actions

### Phase 1: Clean .DS_Store files
```bash
find . -name ".DS_Store" -delete
echo ".DS_Store" >> .gitignore
```

### Phase 2: Consolidate Documentation

**Move to docs/archive/**:
- IMPLEMENTATION-SUMMARY.md → docs/archive/
- PLAN.md → docs/archive/
- PLAN.md.delta → docs/archive/
- TODO.md → docs/archive/
- TODO.md.delta → docs/archive/
- lib/DELIVERY_SUMMARY.md → docs/archive/
- lib/IMPLEMENTATION_GUIDE.md → docs/archive/
- lib/QUICKSTART.md → docs/archive/

**Clean up duplicates**:
- Check if docs/INTEGRATION.md is different from INTEGRATIONS.md
- If same, delete INTEGRATION.md
- If different, rename to clarify purpose

### Phase 3: Clean bin/ Directory

**Remove duplicates/old files**:
- bin/restore.sh → DELETE (backup-restore.sh is canonical)
- bin/status.sh → DELETE (backup-status.sh is canonical)
- bin/test-commands.sh → MOVE to tests/manual/

### Phase 4: Clean lib/ Directory

**Move documentation**:
- lib/README_LIBRARY.md → docs/LIBRARY.md

**Archive old versions**:
- lib/backup-lib-v1.1.0.sh → lib/archive/

**Move test files**:
- lib/test-library.sh → tests/unit/

### Phase 5: Clean examples/ Directory

**Remove empty directories**:
- examples/integrations/ → DELETE if empty

### Phase 6: Organize tests/ Directory

**Create subdirectories**:
- tests/manual/ (for manual test scripts)
- tests/legacy/ (for old test files)

**Move files**:
- test-backup-system.sh → tests/legacy/
- test-command-system.sh → tests/legacy/
- test-config-validation.sh → tests/legacy/
- test-integrations.sh already in integration/

### Phase 7: Add Missing Documentation

**Create**:
- docs/PROJECT-STRUCTURE.md
- CONTRIBUTING.md (in root)
- Update .gitignore

### Phase 8: Final Validation

**Test all commands**:
- bin/backup-status.sh --help
- bin/backup-now.sh --help
- bin/backup-config.sh --help
- bin/backup-restore.sh --help
- bin/backup-cleanup.sh --help
- bin/install-integrations.sh --help

**Test integrations**:
- Source integration-core.sh
- Check all integration installers

**Run smoke tests**:
- ./tests/smoke-test.sh

## Final Structure

```
checkpoint/
├── .claude/                    # Claude Code skills
│   └── skills/
├── bin/                        # Executable scripts (clean, no duplicates)
│   ├── backup-status.sh
│   ├── backup-now.sh
│   ├── backup-config.sh
│   ├── backup-restore.sh
│   ├── backup-cleanup.sh
│   ├── backup-daemon.sh
│   ├── install.sh
│   ├── install-skills.sh
│   ├── install-integrations.sh
│   ├── uninstall.sh
│   └── smart-backup-trigger.sh
├── docs/                       # All documentation
│   ├── API.md
│   ├── COMMANDS.md
│   ├── DEVELOPMENT.md
│   ├── INTEGRATION-DEVELOPMENT.md
│   ├── INTEGRATIONS.md
│   ├── LIBRARY.md             # (from lib/README_LIBRARY.md)
│   ├── MIGRATION.md
│   ├── TESTING.md
│   ├── PROJECT-STRUCTURE.md   # (new)
│   └── archive/               # (new - for old dev docs)
│       ├── IMPLEMENTATION-SUMMARY.md
│       ├── PLAN.md
│       ├── TODO.md
│       └── ...
├── examples/                   # Usage examples
│   ├── commands/
│   │   ├── basic-setup.sh
│   │   ├── disaster-recovery.sh
│   │   ├── maintenance.sh
│   │   └── advanced-config.sh
│   ├── configs/
│   │   ├── minimal.yaml
│   │   ├── standard.yaml
│   │   ├── external-drive.yaml
│   │   ├── no-database.yaml
│   │   └── paranoid.yaml
│   └── sample-config.sh
├── integrations/               # Platform integrations
│   ├── lib/
│   │   ├── integration-core.sh
│   │   ├── notification.sh
│   │   └── status-formatter.sh
│   ├── shell/
│   ├── git/
│   ├── tmux/
│   ├── direnv/
│   ├── vim/
│   ├── vscode/
│   └── generic/
├── lib/                        # Core libraries (clean)
│   ├── backup-lib.sh
│   └── archive/               # (new)
│       └── backup-lib-v1.1.0.sh
├── templates/                  # Configuration templates
│   ├── backup-config.sh
│   ├── backup-config.yaml
│   └── pre-database.sh
├── tests/                      # Test suite
│   ├── unit/
│   ├── integration/
│   ├── e2e/
│   ├── compatibility/
│   ├── stress/
│   ├── legacy/                # (new - for old tests)
│   ├── manual/                # (new - for manual tests)
│   ├── reports/
│   ├── test-framework.sh
│   ├── smoke-test.sh
│   └── run-all-tests.sh
├── .gitignore                  # Updated
├── CHANGELOG.md
├── CONTRIBUTING.md             # (new)
├── LICENSE
├── README.md
└── VERSION
```

## Success Criteria

- ✅ No duplicate files
- ✅ No .DS_Store files
- ✅ All docs in /docs
- ✅ All tests in /tests
- ✅ Clear, logical structure
- ✅ All scripts still work (zero regressions)
- ✅ Smoke tests pass
- ✅ Project looks professional
