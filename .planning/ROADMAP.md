# Roadmap: Checkpoint

## Overview

Transform the existing backup infrastructure into a fully automatic, invisible system. Starting with cloud folder destination (leveraging Dropbox/GDrive desktop sync), add activity-based triggers with debouncing, integrate with Claude Code events, implement fallback chains for reliability, add tiered retention for efficient storage, and finish with dashboard/monitoring for visibility.

## Domain Expertise

None

## Milestones

- ✅ [v1.0 Automated Backup System](milestones/v1.0-ROADMAP.md) (Phases 1-6) — SHIPPED 2026-01-11
- ✅ [v1.1 Polish & Performance](milestones/v1.1-ROADMAP.md) (Phases 7-9) — SHIPPED 2026-01-12
- ✅ [v1.2 Dashboard UX](milestones/v1.2-ROADMAP.md) (Phase 10) — SHIPPED 2026-01-12
- 🚧 **v2.5 Architecture & Independence** — Phases 11-18 (in progress)

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
- [x] 11-01: Extract core + ops modules (error-codes, output, config, file-ops, state, init)
- [x] 11-02: Extract ui + features modules (formatting, time-size-utils, 8 feature modules)
- [x] 11-03: Cutover — thin loader + full verification

#### Phase 12: Bootstrap Deduplication

**Goal**: Extract the 7-line symlink resolution pattern from 20+ bin/ scripts into a shared bootstrap file; standardize script initialization
**Depends on**: Phase 11
**Research**: Unlikely (internal patterns)
**Plans**: TBD

Plans:
- [x] 12-01: Create shared bootstrap.sh and migrate 17 bin/ scripts

#### Phase 13: Native File Watcher Daemon

**Goal**: Replace Claude Code hooks with native file watching (fswatch on macOS, inotifywait on Linux) with debouncing; remove .claude/hooks/backup-on-*.sh; make backups fully editor-agnostic
**Depends on**: Phase 12
**Research**: Likely (fswatch/inotifywait APIs, debounce strategies, event filtering)
**Research topics**: fswatch macOS integration, inotifywait Linux patterns, debounce timing strategies, ignore patterns for build dirs
**Plans**: 4

Plans:
- [x] 13-01: Create platform file watcher abstraction + integrate into backup-watcher.sh
- [x] 13-02: Migrate session detection + fix 8 watcher bugs
- [x] 13-03: Update watcher management CLI + config template
- [x] 13-04: Remove Claude Code hooks + update install scripts

#### Phase 14: Security Hardening

**Goal**: Eliminate curl|bash for rclone installation (download → verify checksum → execute); use system keychain or env vars for database credentials; add integrity verification for downloaded dependencies
**Depends on**: Phase 13
**Research**: Likely (macOS keychain API via `security` command, checksum verification workflows)
**Research topics**: macOS `security` CLI for keychain access, Linux secret-tool/pass, GPG signature verification for rclone binaries
**Plans**: 3

Plans:
- [x] 14-01: Secure download library + rclone migration (replace curl|bash with download-verify-execute)
- [x] 14-02: Credential provider abstraction (macOS Keychain, Linux secret-tool/pass, env var fallback)
- [x] 14-03: Self-update integrity + install messaging (SHA256 verification for backup-update.sh)

#### Phase 15: Linux Systemd Support

**Goal**: Create systemd unit file template alongside existing macOS plist; platform-aware daemon installer that detects launchd vs systemd vs cron
**Depends on**: Phase 14
**Research**: Complete (15-RESEARCH.md — systemd user services, init detection, stat portability, cron fallback)
**Plans**: 5

Plans:
- [x] 15-01: Platform compatibility layer (stat portability + notifications for core scripts)
- [x] 15-02: stat portability across all backup operation scripts
- [x] 15-03: Daemon manager abstraction + systemd/cron templates
- [x] 15-04: Core daemon script migration (watchdog, pause, install-global, uninstall-global)
- [x] 15-05: Complete daemon migration (install, configure, uninstall, helper, auto-configure)

#### Phase 16: Backup Verification

**Goal**: Implement the "Coming soon!" dashboard feature — verify file counts, database integrity, archive completeness; build on existing verify_sqlite_integrity()
**Depends on**: Phase 15
**Research**: Unlikely (building on existing internal patterns)
**Plans**: TBD

Plans:
- [x] 16-01: Core verification library + error codes + persistent manifest
- [x] 16-02: CLI command + dashboard integration

#### Phase 17: Error Logging Overhaul

**Goal**: Replace 932 occurrences of 2>/dev/null with structured debug logging; add log rotation; debug mode toggle for troubleshooting
**Depends on**: Phase 16
**Research**: Complete (17-RESEARCH.md — bash structured logging, log rotation, debug mode patterns)
**Plans**: 4

Plans:
- [x] 17-01: Logging foundation (lib/core/logging.sh module + config/output integration)
- [x] 17-02: Core script migration (backup-now, backup-daemon, checkpoint-watchdog)
- [x] 17-03: Library module migration (database-detector, cloud-backup, daemon-manager, features/, ops/)
- [x] 17-04: CLI & integration migration + end-to-end verification

#### Phase 18: Daemon Lifecycle & Health Monitoring

**Goal**: Auto-start daemon on install; implement heartbeat monitoring with periodic health checks; auto-restart if daemon fails or dies (cross-platform: launchd KeepAlive + systemd Restart=on-failure); present warning notification if backups cease (no successful backup within configurable threshold)
**Depends on**: Phase 13 (daemon), Phase 15 (platform service support)
**Research**: Likely (launchd KeepAlive patterns, heartbeat file strategies, backup cessation detection)
**Research topics**: launchd KeepAlive vs watchdog patterns, systemd watchdog integration, heartbeat file vs PID-based health checks, configurable staleness thresholds
**Plans**: TBD

Plans:
- [ ] 18-01: TBD (run /gsd:plan-phase 18 to break down)

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
| 11. Modularize Foundation Library | v2.5 | 3/3 | Complete | 2026-02-13 |
| 12. Bootstrap Deduplication | v2.5 | 1/1 | Complete | 2026-02-13 |
| 13. Native File Watcher Daemon | v2.5 | 4/4 | Complete | 2026-02-13 |
| 14. Security Hardening | v2.5 | 3/3 | Complete | 2026-02-13 |
| 15. Linux Systemd Support | v2.5 | 5/5 | Complete | 2026-02-13 |
| 16. Backup Verification | v2.5 | 2/2 | Complete | 2026-02-14 |
| 17. Error Logging Overhaul | v2.5 | 4/4 | Complete | 2026-02-14 |
| 18. Daemon Lifecycle & Health Monitoring | v2.5 | 0/? | Not started | - |
