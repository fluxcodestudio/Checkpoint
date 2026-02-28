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
- ✅ **v3.0 Smart Features & Developer Intelligence** — Phases 19-25 (shipped 2026-02-17)
- 🚧 **v3.1 Database Snapshots** — Phases 26-31 (in progress)

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

<details>
<summary>v3.0 Smart Features & Developer Intelligence (Phases 19-25) — SHIPPED 2026-02-17</summary>

**Delivered:** AI coding tool awareness, smart scheduling, proactive storage management, backup diffing, encryption, container support, and search/browse CLI.

- [x] **Phase 19: AI Tool Artifact Backup** (1/1 plans) — 2026-02-16
- [x] **Phase 20: Cron-Style Scheduling** (2/2 plans) — 2026-02-16
- [x] **Phase 21: Storage Usage Warnings** (2/2 plans) — 2026-02-16
- [x] **Phase 22: Checkpoint Diff Command** (2/2 plans) — 2026-02-16
- [x] **Phase 23: Encryption at Rest** (3/3 plans) — 2026-02-16
- [x] **Phase 24: Docker Volume Backup** (2/2 plans) — 2026-02-17
- [x] **Phase 25: Backup Search & Browse CLI** (2/2 plans) — 2026-02-17

</details>

### 🚧 v3.1 Database Snapshots (In Progress)

**Milestone Goal:** Named, per-table database snapshots with schema-aware restore. Camera button on dashboard for one-click capture, selective table restore with schema compatibility checking, and download bundle with LLM prompt for schema mismatches.

#### Phase 26: Snapshot Core Library

**Goal**: Per-table dump and schema extraction for all 4 DB types (SQLite, PostgreSQL, MySQL, MongoDB); manifest.json generation; storage layout in `snapshots/` directory under project backups
**Depends on**: Previous milestone complete
**Research**: Unlikely (extends existing database-detector.sh patterns with per-table flags)
**Plans**: TBD

Plans:
- [ ] 26-01: TBD (run /gsd:plan-phase 26 to break down)

#### Phase 27: Snapshot CLI Commands

**Goal**: `checkpoint snapshot save "name"`, `checkpoint snapshot list`, `checkpoint snapshot delete "name"` bash commands with interactive name prompt and table enumeration
**Depends on**: Phase 26
**Research**: Unlikely (follows existing CLI patterns in checkpoint.sh)
**Plans**: TBD

Plans:
- [ ] 27-01: TBD

#### Phase 28: Schema Comparison Engine

**Goal**: Compare snapshot schema vs live database; detect added/removed/changed columns per table; generate human-readable diff report; produce LLM prompt bundle with old schema, new schema, and sample data for AI-assisted migration
**Depends on**: Phase 27
**Research**: Unlikely (SQL schema extraction already used in Phase 26; diff logic is string comparison)
**Plans**: TBD

Plans:
- [ ] 28-01: TBD

#### Phase 29: Selective Table Restore

**Goal**: Per-table restore with safety pre-dump; schema-match path restores directly with confirmation modal; schema-mismatch path generates download bundle (SQL dumps + schema diff + llm-prompt.md); handles all 4 DB types
**Depends on**: Phase 28
**Research**: Unlikely (extends existing restore.sh with per-table restore commands)
**Plans**: TBD

Plans:
- [ ] 29-01: TBD

#### Phase 30: Dashboard Snapshot UI

**Goal**: SwiftUI camera button in toolbar; name input modal; snapshot list view with dates and table counts; table picker checklist for selective restore; confirmation modal ("will overwrite, safety backup created first"); schema warning modal with download bundle option
**Depends on**: Phase 29
**Research**: Unlikely (extends existing SwiftUI dashboard patterns)
**Plans**: TBD

Plans:
- [ ] 30-01: TBD

#### Phase 31: Cloud Sync & Integration

**Goal**: Verify snapshots sync via existing rclone/cloud folder pipeline; encryption support for snapshot files via age; `checkpoint snapshot` routing in main CLI; update `checkpoint status` to show snapshot count
**Depends on**: Phase 30
**Research**: Unlikely (existing cloud sync and encryption infrastructure)
**Plans**: TBD

Plans:
- [ ] 31-01: TBD

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
| 24. Docker Volume Backup | v3.0 | 2/2 | Complete | 2026-02-17 |
| 25. Backup Search & Browse CLI | v3.0 | 2/2 | Complete | 2026-02-17 |
| 26. Snapshot Core Library | v3.1 | 0/? | Not started | - |
| 27. Snapshot CLI Commands | v3.1 | 0/? | Not started | - |
| 28. Schema Comparison Engine | v3.1 | 0/? | Not started | - |
| 29. Selective Table Restore | v3.1 | 0/? | Not started | - |
| 30. Dashboard Snapshot UI | v3.1 | 0/? | Not started | - |
| 31. Cloud Sync & Integration | v3.1 | 0/? | Not started | - |
