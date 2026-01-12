# Checkpoint

## What This Is

An automatic, redundant backup system for development projects that protects code and databases without manual intervention. Backs up locally and to cloud (Dropbox/GDrive), maintains version history with tiered retention, and integrates seamlessly with Claude Code workflows via event triggers. Optimized for performance with parallel change detection, hash-based comparison, and single-pass cleanup. Configurable alerts, quiet hours, and topic-based help for easy setup.

## Core Value

Backups happen automatically and invisibly — developer never loses work and never thinks about backups.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- Core backup engine (backup-now, status, restore) — existing
- Background daemon with hourly backups (launchd/cron) — existing
- Database detection and backup (SQLite, PostgreSQL, MySQL, MongoDB) — existing
- Cloud backup via rclone (40+ providers) — existing
- File version archiving — existing
- State tracking with JSON — existing
- Native macOS/Linux notifications — existing
- Claude Code skills (/checkpoint, pause, update) — existing
- Per-project and global installation modes — existing
- Platform integrations (git, shell, vim, vscode, tmux) — existing
- Cloud folder as primary backup destination (Dropbox/GDrive) — v1.0
- Activity-based backup triggers with 60s debouncing — v1.0
- Claude Code event triggers (conversation end, file changes, commits) — v1.0
- Offline fallback chain: cloud folder → rclone API → local queue — v1.0
- Tiered snapshot retention (hourly/daily/weekly/monthly) — v1.0
- Status bar indicator for backup health — v1.0
- All-projects dashboard view — v1.0
- Sub-minute restore capability from any point in last week — v1.0
- Parallel git change detection with early-exit optimization — v1.1
- Hash-based file comparison with mtime caching — v1.1
- Single-pass cleanup consolidation — v1.1
- Structured error codes with fix suggestions — v1.1
- Dashboard error panel with health trends — v1.1
- Configurable alert thresholds and quiet hours — v1.1
- Extended configuration validation — v1.1
- Topic-based help command — v1.1

### Active

<!-- Current scope. Building toward these. -->

- [ ] Settings menu in dashboard for unified configuration UX
- [ ] Launch config wizard option from dashboard

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Mobile/remote access — no web interface or mobile app for viewing backups (v1 scope limit)
- Linux/Windows support — macOS only for v1 (constraint)

## Context

**Current state (v1.1 shipped):**
- 59,630 lines of bash code
- Pure bash implementation (lib/*.sh, bin/*.sh)
- Layered architecture: CLI → Orchestration → Service → Integration → Storage
- Cloud sync via desktop apps (Dropbox/GDrive folder)
- API fallback via rclone (40+ providers)
- Tiered retention (hourly/daily/weekly/monthly)
- Claude Code hook integration
- Performance optimizations: ~3x change detection, O(1) file comparison, 10x cleanup
- Enhanced monitoring: 15 error codes, health trends, configurable alerts
- Improved UX: validation, wizard, topic-based help

**Backup architecture:**
```
PROJECT/backups/
├── files/           # Current file versions (UNCOMPRESSED mirror)
│   └── src/main.js  # Direct copy, readable, browsable
├── archived/        # Previous file versions (UNCOMPRESSED + TIMESTAMP)
│   └── src/main.js.20260102_150000_5678
└── databases/       # Database dumps (COMPRESSED .db.gz)
    └── mydb_20260103_120000.db.gz
```

## Constraints

- **Platform**: macOS only — simplifies launchd integration, notification APIs
- **Non-interference**: Backup system must never impact Claude Code operation
- **Architecture**: Pure bash, no Python/Node dependencies for core functionality

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Cloud folder as primary destination | User's Dropbox/GDrive folder auto-syncs via desktop app | ✓ Good — zero API calls, instant sync |
| Debounce-based triggers (60s) | Captures natural pause points without excessive snapshots | ✓ Good — balances granularity and efficiency |
| Tiered retention | Granular recent history, compressed older history — like Time Machine | ✓ Good — efficient storage use |
| Fallback chain priority | Cloud folder → rclone API → local queue — maximize reliability | ✓ Good — no backup ever lost |
| macOS only for v1 | Reduces complexity, user's primary platform | ✓ Good — faster delivery |
| Health thresholds: >24h warning, >72h error | Balance between alerting and noise | ✓ Good — reasonable defaults |
| Use $((var + 1)) not ((var++)) | set -e compatibility (0++ returns exit 1) | ✓ Good — bash portability |
| Derive FILES_DIR from BACKUP_DIR | Config order independence | ✓ Good — simpler config |
| BSD stat -f for mtime retrieval | macOS compatibility (no GNU find -printf) | ✓ Good — portable |
| Global arrays for scan results | Bash functions can't return arrays | ✓ Good — works with set -e |
| All v1.1 config via env vars | Backwards compatibility with v1.0 configs | ✓ Good — no breaking changes |
| Quiet hours overnight format (22-07) | Natural representation of overnight ranges | ✓ Good — intuitive |
| Critical errors bypass quiet hours | Safety first — don't miss real problems | ✓ Good — sensible default |

---
*Last updated: 2026-01-12 after v1.1 milestone*
