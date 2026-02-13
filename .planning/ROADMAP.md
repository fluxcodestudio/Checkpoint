# Roadmap: Checkpoint

## Overview

Transform the existing backup infrastructure into a fully automatic, invisible system. Starting with cloud folder destination (leveraging Dropbox/GDrive desktop sync), add activity-based triggers with debouncing, integrate with Claude Code events, implement fallback chains for reliability, add tiered retention for efficient storage, and finish with dashboard/monitoring for visibility.

## Domain Expertise

None

## Milestones

- ✅ [v1.0 Automated Backup System](milestones/v1.0-ROADMAP.md) (Phases 1-6) — SHIPPED 2026-01-11
- ✅ [v1.1 Polish & Performance](milestones/v1.1-ROADMAP.md) (Phases 7-9) — SHIPPED 2026-01-12
- ✅ [v1.2 Dashboard UX](milestones/v1.2-ROADMAP.md) (Phase 10) — SHIPPED 2026-01-12
- 🚧 **v2.5 Architecture & Independence** — Phases 11-17 (in progress)

## Completed Milestones

<details>
<summary>v1.0 Automated Backup System (Phases 1-6) — SHIPPED 2026-01-11</summary>

**Delivered:** Full automatic backup system with cloud sync, activity triggers, Claude Code integration, fallback reliability, tiered retention, and monitoring dashboard.

- [x] **Phase 1: Cloud Destination Setup** (2/2 plans) — 2026-01-11
- [x] **Phase 2: Activity Triggers** (2/2 plans) — 2026-01-11
- [x] **Phase 3: Claude Code Integration** (2/2 plans) — 2026-01-11
- [x] **Phase 4: Fallback Chain** (2/2 plans) — 2026-01-11
- [x] **Phase 5: Tiered Retention** (2/2 plans) — 2026-01-11
- [x] **Phase 6: Dashboard & Monitoring** (3/3 plans) — 2026-01-11

[Full details](milestones/v1.0-ROADMAP.md)

</details>

<details>
<summary>v1.1 Polish & Performance (Phases 7-9) — SHIPPED 2026-01-12</summary>

**Delivered:** Performance optimizations, enhanced monitoring, and improved configuration UX.

- [x] **Phase 7: Performance Optimization** (3/3 plans) — 2026-01-12
- [x] **Phase 8: Monitoring Enhancements** (3/3 plans) — 2026-01-12
- [x] **Phase 9: Configuration UX** (3/3 plans) — 2026-01-12

[Full details](milestones/v1.1-ROADMAP.md)

</details>

<details>
<summary>v1.2 Dashboard UX (Phase 10) — SHIPPED 2026-01-12</summary>

**Delivered:** Unified configuration experience with settings menu and wizard launcher in dashboard.

- [x] **Phase 10: Dashboard Settings Integration** (2/2 plans) — 2026-01-12

[Full details](milestones/v1.2-ROADMAP.md)

</details>

### 🚧 v2.5 Architecture & Independence (In Progress)

**Milestone Goal:** Decouple backup system from Claude Code, modularize the monolithic codebase, harden security, and expand platform support — making Checkpoint a standalone, editor-agnostic tool.

#### Phase 11: Modularize Foundation Library

**Goal**: Break backup-lib.sh (3,216 lines) into focused modules: config.sh, error-codes.sh, file-ops.sh, state.sh, validation.sh
**Depends on**: Previous milestone complete
**Research**: Unlikely (internal refactoring)
**Plans**: TBD

Plans:
- [ ] 11-01: Extract core + ops modules (error-codes, output, config, file-ops, state, init)
- [ ] 11-02: Extract ui + features modules (formatting, time-size-utils, 8 feature modules)
- [ ] 11-03: Cutover — thin loader + full verification

#### Phase 12: Bootstrap Deduplication

**Goal**: Extract the 7-line symlink resolution pattern from 20+ bin/ scripts into a shared bootstrap file; standardize script initialization
**Depends on**: Phase 11
**Research**: Unlikely (internal patterns)
**Plans**: TBD

Plans:
- [ ] 12-01: TBD (run /gsd:plan-phase 12 to break down)

#### Phase 13: Native File Watcher Daemon

**Goal**: Replace Claude Code hooks with native file watching (fswatch on macOS, inotifywait on Linux) with debouncing; remove .claude/hooks/backup-on-*.sh; make backups fully editor-agnostic
**Depends on**: Phase 12
**Research**: Likely (fswatch/inotifywait APIs, debounce strategies, event filtering)
**Research topics**: fswatch macOS integration, inotifywait Linux patterns, debounce timing strategies, ignore patterns for build dirs
**Plans**: TBD

Plans:
- [ ] 13-01: TBD (run /gsd:plan-phase 13 to break down)

#### Phase 14: Security Hardening

**Goal**: Eliminate curl|bash for rclone installation (download → verify checksum → execute); use system keychain or env vars for database credentials; add integrity verification for downloaded dependencies
**Depends on**: Phase 13
**Research**: Likely (macOS keychain API via `security` command, checksum verification workflows)
**Research topics**: macOS `security` CLI for keychain access, Linux secret-tool/pass, GPG signature verification for rclone binaries
**Plans**: TBD

Plans:
- [ ] 14-01: TBD (run /gsd:plan-phase 14 to break down)

#### Phase 15: Linux Systemd Support

**Goal**: Create systemd unit file template alongside existing macOS plist; platform-aware daemon installer that detects launchd vs systemd vs cron
**Depends on**: Phase 14
**Research**: Likely (systemd unit file patterns, cross-platform daemon management)
**Research topics**: systemd user service files, ExecStart/Restart directives, journalctl integration, platform detection
**Plans**: TBD

Plans:
- [ ] 15-01: TBD (run /gsd:plan-phase 15 to break down)

#### Phase 16: Backup Verification

**Goal**: Implement the "Coming soon!" dashboard feature — verify file counts, database integrity, archive completeness; build on existing verify_sqlite_integrity()
**Depends on**: Phase 15
**Research**: Unlikely (building on existing internal patterns)
**Plans**: TBD

Plans:
- [ ] 16-01: TBD (run /gsd:plan-phase 16 to break down)

#### Phase 17: Error Logging Overhaul

**Goal**: Replace 77+ occurrences of 2>/dev/null with structured debug logging; add log rotation; debug mode toggle for troubleshooting
**Depends on**: Phase 16
**Research**: Unlikely (internal logging patterns)
**Plans**: TBD

Plans:
- [ ] 17-01: TBD (run /gsd:plan-phase 17 to break down)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Cloud Destination Setup | v1.0 | 2/2 | Complete | 2026-01-11 |
| 2. Activity Triggers | v1.0 | 2/2 | Complete | 2026-01-11 |
| 3. Claude Code Integration | v1.0 | 2/2 | Complete | 2026-01-11 |
| 4. Fallback Chain | v1.0 | 2/2 | Complete | 2026-01-11 |
| 5. Tiered Retention | v1.0 | 2/2 | Complete | 2026-01-11 |
| 6. Dashboard & Monitoring | v1.0 | 3/3 | Complete | 2026-01-11 |
| 7. Performance Optimization | v1.1 | 3/3 | Complete | 2026-01-12 |
| 8. Monitoring Enhancements | v1.1 | 3/3 | Complete | 2026-01-12 |
| 9. Configuration UX | v1.1 | 3/3 | Complete | 2026-01-12 |
| 10. Dashboard Settings Integration | v1.2 | 2/2 | Complete | 2026-01-12 |
| 11. Modularize Foundation Library | v2.5 | 0/? | Not started | - |
| 12. Bootstrap Deduplication | v2.5 | 0/? | Not started | - |
| 13. Native File Watcher Daemon | v2.5 | 0/? | Not started | - |
| 14. Security Hardening | v2.5 | 0/? | Not started | - |
| 15. Linux Systemd Support | v2.5 | 0/? | Not started | - |
| 16. Backup Verification | v2.5 | 0/? | Not started | - |
| 17. Error Logging Overhaul | v2.5 | 0/? | Not started | - |
