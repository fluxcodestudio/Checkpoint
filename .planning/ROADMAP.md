# Roadmap: Checkpoint

## Overview

Transform the existing backup infrastructure into a fully automatic, invisible system. Starting with cloud folder destination (leveraging Dropbox/GDrive desktop sync), add activity-based triggers with debouncing, integrate with Claude Code events, implement fallback chains for reliability, add tiered retention for efficient storage, and finish with dashboard/monitoring for visibility.

## Domain Expertise

None

## Milestones

- ✅ [v1.0 Automated Backup System](milestones/v1.0-ROADMAP.md) (Phases 1-6) — SHIPPED 2026-01-11
- ✅ [v1.1 Polish & Performance](milestones/v1.1-ROADMAP.md) (Phases 7-9) — SHIPPED 2026-01-12
- ✅ [v1.2 Dashboard UX](milestones/v1.2-ROADMAP.md) (Phase 10) — SHIPPED 2026-01-12
- ✅ **v2.5 Architecture & Independence** — Phases 11-18 (shipped 2026-02-14)
- 🚧 **v3.0 Smart Features & Developer Intelligence** — Phases 19-25 (in progress)

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

<details>
<summary>v2.5 Architecture & Independence (Phases 11-18) — SHIPPED 2026-02-14</summary>

**Delivered:** Decoupled from Claude Code, modularized codebase, hardened security, Linux systemd support, backup verification, structured logging, daemon health monitoring.

- [x] **Phase 11: Modularize Foundation Library** (3/3 plans) — 2026-02-13
- [x] **Phase 12: Bootstrap Deduplication** (1/1 plans) — 2026-02-13
- [x] **Phase 13: Native File Watcher Daemon** (4/4 plans) — 2026-02-13
- [x] **Phase 14: Security Hardening** (3/3 plans) — 2026-02-13
- [x] **Phase 15: Linux Systemd Support** (5/5 plans) — 2026-02-13
- [x] **Phase 16: Backup Verification** (2/2 plans) — 2026-02-14
- [x] **Phase 17: Error Logging Overhaul** (4/4 plans) — 2026-02-14
- [x] **Phase 18: Daemon Lifecycle & Health Monitoring** (3/3 plans) — 2026-02-14

</details>

### 🚧 v3.0 Smart Features & Developer Intelligence (In Progress)

**Milestone Goal:** Add intelligent features that differentiate Checkpoint from generic backup tools — AI coding tool awareness, smart scheduling, proactive storage management, backup diffing, encryption, container support, and a powerful search/browse CLI.

#### Phase 19: AI Tool Artifact Backup

**Goal**: Automatically detect and include AI coding tool directories (.claude/, .cursor/, .aider*, .windsurf/) in backups, even when gitignored; preserve session transcripts, project memory, and tool configs across sessions
**Depends on**: Previous milestone complete
**Research**: Likely (AI tool directory structures, which files are ephemeral vs persistent, gitignore override patterns in rsync)
**Research topics**: Claude Code .claude/ structure, Cursor .cursor/ contents, Aider file patterns, Windsurf .windsurf/ layout, rsync --include override for gitignored paths
**Plans**: TBD

Plans:
- [x] 19-01: AI Tool Artifact Backup — config, detection, status display

#### Phase 20: Cron-Style Scheduling

**Goal**: Replace flat BACKUP_INTERVAL seconds with cron-like expressions supporting work-hours-only, weekday/weekend differentiation, and time-of-day awareness
**Depends on**: Phase 19
**Research**: Unlikely (cron expression parsing is well-documented; internal daemon scheduling logic)
**Plans**: TBD

Plans:
- [x] 20-01: Scheduling Library (TDD) — cron parser, matcher, presets, validation, next-match
- [x] 20-02: Config & Integration — config wiring, daemon/watcher integration, status display

#### Phase 21: Storage Usage Warnings

**Goal**: Pre-backup disk space checks on destination volume; warn via notification when approaching capacity; show per-project storage consumption; suggest cleanup actions
**Depends on**: Phase 20
**Research**: Unlikely (df command, existing notification infrastructure)
**Plans**: TBD

Plans:
- [x] 21-01: Storage Monitoring Library & Config — storage-monitor.sh, STORAGE_* config wiring
- [x] 21-02: Pipeline Integration & Status Display — pre-backup gate check, checkpoint status

#### Phase 22: Checkpoint Diff Command

**Goal**: New `checkpoint diff` CLI command to compare backup snapshots — show files added/modified/deleted between any two points in time; support current-vs-backup and backup-vs-backup comparisons
**Depends on**: Phase 21
**Research**: Unlikely (diff/rsync dry-run patterns, existing archived file structure)
**Plans**: TBD

Plans:
- [x] 22-01: Core Diff Library — extract_timestamp fix, centralized excludes, backup-diff.sh
- [x] 22-02: CLI Commands & Tests — checkpoint-diff.sh, checkpoint.sh routing, unit tests

#### Phase 23: Encryption at Rest

**Goal**: Optional encryption of backup files using age (modern, simple alternative to GPG); encrypt after compression, decrypt on restore; single keypair per user stored in ~/.config/checkpoint/; works transparently with cloud sync
**Depends on**: Phase 22
**Research**: Likely (age CLI integration, key management patterns, encrypt-then-compress vs compress-then-encrypt)
**Research topics**: age encryption CLI, key generation and storage, streaming encryption for large files, integration with existing gzip pipeline
**Plans**: TBD

Plans:
- [x] 23-01: Encryption Library & Config — encryption.sh, config wiring, checkpoint encrypt CLI
- [x] 23-02: Backup Pipeline Encryption — cloud folder post-sync encryption in backup-now.sh
- [x] 23-03: Restore & Discovery Adaptation — .age handling in restore, discovery, verification, diff

#### Phase 24: Docker Volume Backup

**Goal**: Detect docker-compose.yml in projects; identify named volumes; export volume data alongside regular file backups; restore volumes on demand
**Depends on**: Phase 23
**Research**: Likely (docker volume export methods, compose file parsing in bash, volume mount strategies)
**Research topics**: docker run --rm volume export patterns, docker-compose.yml parsing for volume names, handling running vs stopped containers
**Plans**: TBD

Plans:
- [ ] 24-01: TBD (run /gsd:plan-phase 24 to break down)

#### Phase 25: Backup Search & Browse CLI

**Goal**: New CLI commands: `checkpoint browse` for interactive backup file browser, `checkpoint search` to grep across backup snapshots, `checkpoint history <file>` to show all versions of a specific file with timestamps
**Depends on**: Phase 24
**Research**: Unlikely (existing backup directory structure, fzf/select patterns for interactive browsing)
**Plans**: TBD

Plans:
- [ ] 25-01: TBD (run /gsd:plan-phase 25 to break down)

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
| 18. Daemon Lifecycle & Health Monitoring | v2.5 | 3/3 | Complete | 2026-02-14 |
| 19. AI Tool Artifact Backup | v3.0 | 1/1 | Complete | 2026-02-16 |
| 20. Cron-Style Scheduling | v3.0 | 2/2 | Complete | 2026-02-16 |
| 21. Storage Usage Warnings | v3.0 | 2/2 | Complete | 2026-02-16 |
| 22. Checkpoint Diff Command | v3.0 | 2/2 | Complete | 2026-02-16 |
| 23. Encryption at Rest | v3.0 | 3/3 | Complete | 2026-02-16 |
| 24. Docker Volume Backup | v3.0 | 0/? | Not started | - |
| 25. Backup Search & Browse CLI | v3.0 | 0/? | Not started | - |
