# Checkpoint

## What This Is

An automatic, redundant backup system for development projects that protects code and databases without manual intervention. Backs up locally and to cloud (Dropbox/GDrive), maintains version history, and integrates seamlessly with Claude Code workflows.

## Core Value

Backups happen automatically and invisibly — developer never loses work and never thinks about backups.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. Inferred from existing codebase. -->

- ✓ Core backup engine (backup-now, status, restore) — existing
- ✓ Background daemon with hourly backups (launchd/cron) — existing
- ✓ Database detection and backup (SQLite, PostgreSQL, MySQL, MongoDB) — existing
- ✓ Cloud backup via rclone (40+ providers) — existing
- ✓ File version archiving — existing
- ✓ State tracking with JSON — existing
- ✓ Native macOS/Linux notifications — existing
- ✓ Claude Code skills (/checkpoint, pause, update) — existing
- ✓ Per-project and global installation modes — existing
- ✓ Platform integrations (git, shell, vim, vscode, tmux) — existing

### Active

<!-- Current scope. Building toward these. -->

- [ ] Activity-based backup triggers (debounced file watching)
- [ ] Claude Code event triggers (conversation end, file changes, commits)
- [ ] Master backup folder in cloud-synced directory (Dropbox/GDrive folder)
- [ ] Offline fallback chain: cloud folder → direct API → local queue
- [ ] Tiered snapshot retention (hourly/daily/weekly/monthly)
- [ ] Status bar indicator for backup health
- [ ] All-projects dashboard view
- [ ] Sub-minute restore capability from any point in last week
- [ ] Non-interference guarantee (never impacts Claude Code operation)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Mobile/remote access — no web interface or mobile app for viewing backups (v1 scope limit)
- Linux/Windows support — macOS only for v1 (constraint)

## Context

**Existing codebase state:**
- Pure bash implementation (lib/*.sh, bin/*.sh)
- Layered architecture: CLI → Orchestration → Service → Integration → Storage
- Already has cloud backup infrastructure via rclone
- Already has daemon support and notification systems
- Claude Code skills already integrated

**Backup architecture (existing):**
```
PROJECT/backups/
├── files/           # Current file versions (UNCOMPRESSED mirror)
│   └── src/main.js  # Direct copy, readable, browsable
├── archived/        # Previous file versions (UNCOMPRESSED + TIMESTAMP)
│   └── src/main.js.20260102_150000_5678
└── databases/       # Database dumps (COMPRESSED .db.gz)
    └── mydb_20260103_120000.db.gz
```
- Files: Uncompressed copies, directory structure preserved
- When file changes: current → archived with timestamp, new version → files/
- Databases: Always compressed (gzip) — full dumps, not incremental
- Retention: files=60 days, databases=30 days

**Key insight from user:**
Cloud sync services (Dropbox, GDrive) have local folders that auto-sync. Writing to these folders = automatic cloud backup without API calls. Direct API (rclone) is fallback only.

**Smart batching approach:**
Professional backup services use debouncing (wait N seconds after last change) rather than backing up on every file write. This captures natural "pause points" in development without creating excessive snapshots.

## Constraints

- **Platform**: macOS only — simplifies launchd integration, notification APIs
- **Non-interference**: Backup system must never impact Claude Code operation — runs independently, no file locking, no git conflicts
- **Architecture**: Stay within pure bash paradigm — no Python/Node dependencies for core functionality

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Cloud folder as primary destination | User's Dropbox/GDrive folder auto-syncs via desktop app — simpler than API calls | — Pending |
| Debounce-based triggers (60s) | Captures natural pause points without excessive snapshots | — Pending |
| Tiered retention | Granular recent history, compressed older history — like Time Machine | — Pending |
| Fallback chain priority | Cloud folder → rclone API → local queue — maximize reliability | — Pending |
| macOS only for v1 | Reduces complexity, user's primary platform | — Pending |

---
*Last updated: 2026-01-10 after initialization*
