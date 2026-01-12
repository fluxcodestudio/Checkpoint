# Checkpoint

## What This Is

An automatic, redundant backup system for development projects that protects code and databases without manual intervention. Backs up locally and to cloud (Dropbox/GDrive), maintains version history with tiered retention, and integrates seamlessly with Claude Code workflows via event triggers.

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

### Active

<!-- Current scope. Building toward these. -->

(None — v1.0 complete, planning next milestone)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Mobile/remote access — no web interface or mobile app for viewing backups (v1 scope limit)
- Linux/Windows support — macOS only for v1 (constraint)

## Context

**Current state (v1.0 shipped):**
- 58,315 lines of bash code
- Pure bash implementation (lib/*.sh, bin/*.sh)
- Layered architecture: CLI → Orchestration → Service → Integration → Storage
- Cloud sync via desktop apps (Dropbox/GDrive folder)
- API fallback via rclone (40+ providers)
- Tiered retention (hourly/daily/weekly/monthly)
- Claude Code hook integration

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

---
*Last updated: 2026-01-11 after v1.0 milestone*
