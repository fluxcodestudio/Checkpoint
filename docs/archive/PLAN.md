# Implementation Plan: Universal Backup Integration System

**Goal:** Extend ClaudeCode Project Backups to work seamlessly with any CLI, editor, or development environment.

**Status:** Planning → Implementation
**Version:** 1.2.0 (Universal Integration Layer)
**Date:** 2025-12-24

---

## Vision & Objectives

### Primary Goal
Create a **universal integration layer** that brings Claude Code-like backup functionality to any development environment:
- **Automatic triggers** (like Claude Code's prompt hooks)
- **Quick access commands** (like Claude Code's `/skills`)
- **Status visibility** (dashboards, indicators, prompts)

### Success Criteria
1. ✅ Backup system works in any terminal (bash/zsh/fish)
2. ✅ VS Code/Cursor/Windsurf users get Claude Code-like experience
3. ✅ Vim/Neovim users get native integration
4. ✅ Git workflow integration (pre-commit backups)
5. ✅ Zero configuration for basic use, customizable for power users

### Non-Goals (v1.2.0)
- ❌ GUI applications (focus on CLI/editor integrations)
- ❌ Windows support (macOS/Linux only for now)
- ❌ Cloud sync (local backups only)

---

## Architecture

### Current System (v1.1.0)

```
┌─────────────────────────────────────────┐
│     Core Backup System (Unchanged)      │
│           bin/*.sh scripts              │
│   ├── backup-status.sh                  │
│   ├── backup-now.sh                     │
│   ├── backup-config.sh                  │
│   ├── backup-cleanup.sh                 │
│   └── backup-restore.sh                 │
├─────────────────────────────────────────┤
│  Optional: Claude Code Integration      │
│   ├── .claude/skills/                   │
│   └── .claude/hooks/                    │
└─────────────────────────────────────────┘
```

### New System (v1.2.0)

```
┌─────────────────────────────────────────────────────┐
│          Core Backup System (Unchanged)             │
│                bin/*.sh scripts                     │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│        Universal Integration Layer (NEW)            │
│              integrations/                          │
├─────────────────────────────────────────────────────┤
│  Platform Adapters:                                 │
│  ├── shell/          - bash/zsh/fish integration    │
│  ├── git/            - Git hooks                    │
│  ├── vscode/         - VS Code extension            │
│  ├── vim/            - Vim/Neovim plugin            │
│  ├── direnv/         - Per-project auto-load        │
│  ├── tmux/           - Terminal multiplexer         │
│  └── generic/        - Generic task runners         │
│                                                      │
│  Common Utilities:                                  │
│  ├── lib/integration-core.sh  - Shared functions    │
│  ├── lib/notification.sh      - Cross-platform      │
│  └── lib/status-formatter.sh  - Output formatting   │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌──────────┬──────────┬──────────┬──────────┬─────────┐
│ VS Code  │  Cursor  │  Neovim  │   Zsh    │   Git   │
│ Windsurf │   Zed    │   Vim    │   Bash   │  Hooks  │
└──────────┴──────────┴──────────┴──────────┴─────────┘
```

### Design Principles

1. **Non-invasive**: Integrations are opt-in, don't break existing workflows
2. **Modular**: Each integration is independent and optional
3. **Lightweight**: Minimal overhead, fast execution
4. **Consistent**: Similar UX across all platforms
5. **Portable**: Works on macOS and Linux without modification

---

## Integration Points

### 1. Shell Integration (Universal Terminal)

**Target:** bash, zsh, fish
**Priority:** 🔥 CRITICAL (works everywhere)
**Complexity:** ⭐⭐ (Medium)

**Features:**
- **Prompt indicator**: Show backup status in shell prompt (✅/⚠️)
- **Auto-trigger**: Backup on directory change (debounced)
- **Quick aliases**: `bs`, `bn`, `bc`, `bcl`, `br`
- **Unified command**: `backup {status|now|config|cleanup|restore}`
- **Git integration**: Optional pre-commit backup

**Files:**
- `integrations/shell/backup-shell-integration.sh` - Main integration script
- `integrations/shell/backup-prompt.sh` - Prompt customization
- `integrations/shell/install.sh` - Installer for ~/.bashrc/~/.zshrc

**Installation:**
```bash
./integrations/shell/install.sh
# Adds: source /path/to/backup-shell-integration.sh to shell RC
```

**Implementation Strategy:**
1. Create integration script with debounced triggers
2. Design prompt integration (PS1/PROMPT customization)
3. Add quick command aliases
4. Test in bash 3.2, bash 5.x, zsh 5.x
5. Document configuration options

---

### 2. Git Hooks Integration

**Target:** Any git repository
**Priority:** 🔥 CRITICAL (universal, high value)
**Complexity:** ⭐ (Easy)

**Features:**
- **pre-commit**: Auto-backup before commit
- **post-commit**: Show backup status after commit
- **pre-push**: Verify backups current before push
- **Optional**: pre-rebase, post-merge hooks

**Files:**
- `integrations/git/hooks/pre-commit`
- `integrations/git/hooks/post-commit`
- `integrations/git/hooks/pre-push`
- `integrations/git/install-git-hooks.sh` - Installer

**Installation:**
```bash
./integrations/git/install-git-hooks.sh
# Installs to .git/hooks/
```

**Implementation Strategy:**
1. Create hook templates
2. Add smart detection (skip if backup already recent)
3. Add user prompts for warnings
4. Make hooks configurable (.backup-git-config)
5. Support global git hooks (git 2.9+)

---

### 3. Direnv Integration (Per-Project)

**Target:** Projects using direnv
**Priority:** 🟡 HIGH (power users)
**Complexity:** ⭐ (Easy)

**Features:**
- **Auto-load**: Backup commands available on `cd` into project
- **Status display**: Show backup status on directory entry
- **Auto-trigger**: Optional backup on directory change
- **PATH addition**: Add bin/ to PATH automatically

**Files:**
- `integrations/direnv/.envrc` - Template
- `integrations/direnv/install.sh` - Installer

**Installation:**
```bash
./integrations/direnv/install.sh
# Creates .envrc, runs: direnv allow
```

**Implementation Strategy:**
1. Create .envrc template with backup integration
2. Add debounced auto-trigger
3. Add status display on entry
4. Document best practices

---

### 4. VS Code Extension

**Target:** VS Code, Cursor, Windsurf (Electron-based)
**Priority:** 🟡 HIGH (broad reach)
**Complexity:** ⭐⭐⭐⭐ (Complex)

**Features:**
- **Command palette**: "Backup: Status/Now/Restore/Cleanup"
- **Status bar**: Live backup health indicator
- **Auto-trigger**: Backup on file save (debounced)
- **Notifications**: Success/failure messages
- **Settings**: Configurable auto-trigger, interval
- **Output panel**: Detailed backup logs
- **Tree view**: Browse backup history

**Files:**
- `integrations/vscode/extension.js` - Main extension
- `integrations/vscode/package.json` - Extension manifest
- `integrations/vscode/README.md` - Extension docs
- `integrations/vscode/CHANGELOG.md` - Extension changelog

**Installation:**
```bash
cd integrations/vscode
npm install
vsce package
code --install-extension backup-guardian-*.vsix
```

**Implementation Strategy:**
1. Create minimal extension skeleton
2. Add command palette commands
3. Implement status bar indicator
4. Add auto-trigger on save (debounced)
5. Add settings/configuration
6. Publish to VS Code marketplace (optional)
7. Test in VS Code, Cursor, Windsurf

---

### 5. Vim/Neovim Plugin

**Target:** Vim 8+, Neovim
**Priority:** 🟢 MEDIUM (power users)
**Complexity:** ⭐⭐⭐ (Medium-Hard)

**Features:**
- **Commands**: `:BackupStatus`, `:BackupNow`, `:BackupRestore`
- **Key mappings**: `<leader>bs`, `<leader>bn`, etc.
- **Auto-trigger**: Backup on BufWritePost (save)
- **Status line**: Integration with status line plugins
- **Popup/Float**: Show status in floating window (Neovim)

**Files:**
- `integrations/vim/plugin/backup.vim` - Main plugin
- `integrations/vim/autoload/backup.vim` - Functions
- `integrations/vim/doc/backup.txt` - Help docs

**Installation:**
```bash
# Via plugin manager (vim-plug)
Plug '/path/to/integrations/vim'

# Manual
cp -r integrations/vim/* ~/.vim/
```

**Implementation Strategy:**
1. Create basic commands
2. Add auto-trigger on save
3. Add key mappings (configurable)
4. Create status line function
5. Add floating window support (Neovim)
6. Write comprehensive help docs

---

### 6. Tmux Integration

**Target:** Tmux users
**Priority:** 🟢 MEDIUM (niche but valuable)
**Complexity:** ⭐⭐ (Medium)

**Features:**
- **Status bar**: Live backup status in tmux status
- **Key bindings**: `prefix+b` for backup, `prefix+B` for status
- **Auto-refresh**: Status updates every 5 minutes
- **Split pane**: Show full status in split

**Files:**
- `integrations/tmux/backup-tmux.conf` - Tmux config
- `integrations/tmux/install.sh` - Installer

**Installation:**
```bash
./integrations/tmux/install.sh
# Appends to ~/.tmux.conf
```

**Implementation Strategy:**
1. Create tmux.conf snippet
2. Add status bar integration
3. Add key bindings
4. Test refresh timing
5. Document customization

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
**Goal:** Core integration infrastructure

**Tasks:**
1. Create integration directory structure
2. Build shared integration library (`lib/integration-core.sh`)
3. Create notification system (`lib/notification.sh`)
4. Create status formatter (`lib/status-formatter.sh`)
5. Write integration testing framework
6. Update installer to offer integration choices

**Deliverables:**
- `integrations/` directory structure
- `integrations/lib/` shared utilities
- `bin/install-integrations.sh` - Integration installer
- `tests/test-integrations.sh` - Integration test suite

---

### Phase 2: Universal Integrations (Week 2)
**Goal:** Integrations that work everywhere

**Priority Order:**
1. **Shell integration** (bash/zsh) - 2 days
2. **Git hooks** - 1 day
3. **Direnv integration** - 0.5 days

**Tasks:**
1. Implement shell integration
   - Prompt customization
   - Auto-trigger system
   - Quick aliases
   - Installation script
2. Implement git hooks
   - pre-commit, post-commit, pre-push
   - Configuration system
   - Global hooks support
3. Implement direnv integration
   - .envrc template
   - Auto-load system
4. Test all integrations together
5. Write user documentation

**Deliverables:**
- Fully working shell integration
- Git hooks installer
- Direnv template
- User guide for each integration

---

### Phase 3: Editor Integrations (Week 3-4)
**Goal:** Editor-specific integrations

**Priority Order:**
1. **VS Code extension** - 5 days
2. **Vim/Neovim plugin** - 3 days
3. **Tmux integration** - 1 day

**Tasks:**
1. VS Code Extension
   - Extension skeleton
   - Command palette commands
   - Status bar indicator
   - Auto-trigger system
   - Settings integration
   - Testing in VS Code/Cursor/Windsurf
   - Package for distribution
2. Vim Plugin
   - Commands and functions
   - Key mappings
   - Auto-trigger
   - Status line integration
   - Help documentation
3. Tmux Integration
   - Config snippet
   - Status bar integration
   - Key bindings

**Deliverables:**
- VS Code extension (.vsix file)
- Vim plugin (installable via plugin managers)
- Tmux integration (installable snippet)
- Documentation for each

---

### Phase 4: Polish & Distribution (Week 5)
**Goal:** Production-ready, documented, easy to install

**Tasks:**
1. Create unified installer with wizard
2. Write comprehensive documentation
3. Create video/gif demos
4. Add integration examples
5. Performance optimization
6. Cross-platform testing (macOS, Linux)
7. Create migration guide from v1.1.0
8. Update README with integration section
9. Tag v1.2.0 release

**Deliverables:**
- `bin/install-integrations.sh` - Wizard installer
- `docs/INTEGRATIONS.md` - Complete integration guide
- `examples/integrations/` - Example configs
- README updates
- v1.2.0 release

---

## Testing Strategy

### Unit Testing
- Each integration script has basic test coverage
- Test in isolation before combined testing
- Automated via `tests/test-integrations.sh`

### Integration Testing
- Test multiple integrations together (shell + git hooks)
- Test in clean environment (Docker containers)
- Test on both macOS and Linux

### Platform Testing

**Shell Integration:**
- bash 3.2 (macOS default)
- bash 5.x (Linux default)
- zsh 5.8+ (macOS default)
- Test on clean shell without customizations

**Git Hooks:**
- git 2.0+
- Test with various git workflows (commit, rebase, merge)
- Test global hooks

**VS Code Extension:**
- VS Code 1.75+
- Cursor latest
- Windsurf latest (if available)

**Vim Plugin:**
- Vim 8.0+
- Neovim 0.5+
- Test with/without plugin managers

### User Acceptance Testing
- Get feedback from 3-5 users per integration
- Iterate based on feedback
- Document common issues

---

## Documentation Strategy

### User Documentation

**Integration Guide** (`docs/INTEGRATIONS.md`)
- Overview of all integrations
- Installation instructions per integration
- Configuration options
- Troubleshooting
- Examples and screenshots

**Quick Start Guides** (per integration)
- `integrations/shell/README.md`
- `integrations/git/README.md`
- `integrations/vscode/README.md`
- `integrations/vim/README.md`

### Developer Documentation

**Integration Development Guide** (`docs/INTEGRATION-DEVELOPMENT.md`)
- How to create new integrations
- API reference for integration-core.sh
- Testing guidelines
- Contribution guidelines

### In-Code Documentation
- Comprehensive comments in all integration scripts
- Function headers with usage examples
- Configuration option explanations

---

## Configuration System

### Integration Configuration File
**File:** `.backup-integrations.yaml`

```yaml
# Which integrations are enabled
integrations:
  shell:
    enabled: true
    prompt_indicator: true
    auto_trigger: true
    trigger_interval: 300  # seconds
    aliases: true

  git:
    enabled: true
    pre_commit: true
    post_commit: true
    pre_push: true
    skip_if_recent: 300  # seconds

  direnv:
    enabled: false
    auto_trigger: true
    show_status: true

  vscode:
    enabled: false
    auto_save_trigger: true
    status_bar: true
    notifications: true

  vim:
    enabled: false
    auto_save_trigger: true
    key_prefix: "<leader>"
    status_line: false

# Global settings for all integrations
global:
  notification_method: "native"  # native, echo, none
  debounce_interval: 300
  quiet_mode: false
```

### Per-Integration Config Files
- `integrations/shell/.shell-integration.conf`
- `integrations/git/.git-integration.conf`
- Each integration can have specific settings

---

## Rollout Strategy

### Phase 1: Internal Testing (Week 1-2)
- Implement shell + git integrations
- Use internally on SUPERSTACK project
- Fix bugs, iterate

### Phase 2: Beta Testing (Week 3-4)
- Add VS Code + Vim integrations
- Invite 5-10 beta testers
- Gather feedback, iterate

### Phase 3: Public Release (Week 5)
- Polish all integrations
- Complete documentation
- Create demo videos
- Release v1.2.0
- Announce on GitHub, social media

---

## Success Metrics

### Quantitative
- ✅ 5 integrations implemented and tested
- ✅ Works on macOS (bash 3.2+, zsh 5.8+)
- ✅ Works on Linux (bash 4.0+, zsh 5.0+)
- ✅ <100ms overhead per trigger
- ✅ 100% backward compatible with v1.1.0

### Qualitative
- ✅ Users can switch editors without losing backup functionality
- ✅ "It just works" - minimal configuration needed
- ✅ Feels natural in each environment
- ✅ Documentation is clear and comprehensive

---

## Risk Mitigation

### Technical Risks

**Risk:** Integration conflicts with user's existing setup
- **Mitigation:** Non-invasive design, easy to disable/remove
- **Mitigation:** Namespace all functions/variables (BACKUP_*)

**Risk:** Performance impact on shell startup
- **Mitigation:** Lazy loading, minimal startup code
- **Mitigation:** Benchmark and optimize

**Risk:** Bash version incompatibility
- **Mitigation:** Test on bash 3.2+ (oldest common version)
- **Mitigation:** Use only POSIX features where possible

### User Adoption Risks

**Risk:** Users don't know integrations exist
- **Mitigation:** Installer offers integration setup
- **Mitigation:** Prominent documentation

**Risk:** Too complex to configure
- **Mitigation:** Sensible defaults, zero-config for basic use
- **Mitigation:** Wizard installer

---

## Future Enhancements (v1.3.0+)

**Beyond v1.2.0 scope, but documented for future:**

1. **GUI Integration**
   - macOS Menu Bar app
   - Linux system tray app

2. **Cloud IDE Support**
   - GitHub Codespaces
   - Gitpod
   - Replit

3. **Additional Editors**
   - Emacs (org-mode integration)
   - Sublime Text
   - JetBrains IDEs (PyCharm, WebStorm, etc.)

4. **Mobile Notifications**
   - iOS/Android push notifications
   - Telegram/Slack bots

5. **Web Dashboard**
   - Local web UI for backup management
   - Backup history visualization
   - Remote access (optional)

6. **Advanced Features**
   - Real-time file watching (fswatch/inotify)
   - Incremental backups
   - Deduplication
   - Encryption

---

## Appendix

### File Structure (v1.2.0)

```
ClaudeCode-Project-Backups/
├── bin/                          # Core backup scripts (unchanged)
│   ├── backup-status.sh
│   ├── backup-now.sh
│   ├── backup-config.sh
│   ├── backup-cleanup.sh
│   ├── backup-restore.sh
│   ├── install.sh
│   └── install-integrations.sh   # NEW: Integration installer
│
├── integrations/                 # NEW: Integration layer
│   ├── lib/                      # Shared utilities
│   │   ├── integration-core.sh   # Core functions
│   │   ├── notification.sh       # Notifications
│   │   └── status-formatter.sh   # Status formatting
│   │
│   ├── shell/                    # Shell integration
│   │   ├── backup-shell-integration.sh
│   │   ├── backup-prompt.sh
│   │   ├── install.sh
│   │   └── README.md
│   │
│   ├── git/                      # Git hooks
│   │   ├── hooks/
│   │   │   ├── pre-commit
│   │   │   ├── post-commit
│   │   │   └── pre-push
│   │   ├── install-git-hooks.sh
│   │   └── README.md
│   │
│   ├── direnv/                   # Direnv integration
│   │   ├── .envrc.template
│   │   ├── install.sh
│   │   └── README.md
│   │
│   ├── vscode/                   # VS Code extension
│   │   ├── extension.js
│   │   ├── package.json
│   │   ├── README.md
│   │   └── CHANGELOG.md
│   │
│   ├── vim/                      # Vim plugin
│   │   ├── plugin/backup.vim
│   │   ├── autoload/backup.vim
│   │   ├── doc/backup.txt
│   │   └── README.md
│   │
│   └── tmux/                     # Tmux integration
│       ├── backup-tmux.conf
│       ├── install.sh
│       └── README.md
│
├── lib/                          # Core library (unchanged)
│   └── backup-lib.sh
│
├── docs/                         # Documentation
│   ├── COMMANDS.md
│   ├── INTEGRATIONS.md           # NEW
│   └── INTEGRATION-DEVELOPMENT.md # NEW
│
├── tests/                        # Testing
│   ├── test-backup-system.sh
│   ├── test-commands.sh
│   └── test-integrations.sh      # NEW
│
├── examples/                     # Examples
│   ├── configs/
│   └── integrations/             # NEW: Integration examples
│
├── PLAN.md                       # This file
├── TODO.md                       # Task tracking
└── README.md                     # Main documentation
```

---

**Document Version:** 1.0
**Last Updated:** 2025-12-24
**Next Review:** After Phase 1 completion
