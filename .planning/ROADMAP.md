# Roadmap: Checkpoint

## Overview

Transform the existing backup infrastructure into a fully automatic, invisible system. Starting with cloud folder destination (leveraging Dropbox/GDrive desktop sync), add activity-based triggers with debouncing, integrate with Claude Code events, implement fallback chains for reliability, add tiered retention for efficient storage, and finish with dashboard/monitoring for visibility.

## Domain Expertise

None

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Cloud Destination Setup** - Configure master backup folder in Dropbox/GDrive local folder
- [ ] **Phase 2: Activity Triggers** - Debounced file watching with 60s threshold
- [x] **Phase 3: Claude Code Integration** - Event triggers for conversation end, file changes, commits
- [x] **Phase 4: Fallback Chain** - Cloud folder → rclone API → local queue reliability
- [x] **Phase 5: Tiered Retention** - Hourly/daily/weekly/monthly snapshot management
- [ ] **Phase 6: Dashboard & Monitoring** - Status bar indicator, all-projects view, restore capability (In progress)

## Phase Details

### Phase 1: Cloud Destination Setup
**Goal**: Configure master backup folder in user's cloud-synced directory (Dropbox/GDrive) so backups auto-sync to cloud without API calls
**Depends on**: Nothing (first phase)
**Research**: Unlikely (using user's existing cloud folder, no API integration)
**Plans**: 2 plans

Plans:
- [x] 01-01: Cloud folder detection and configuration
- [x] 01-02: Backup destination routing to cloud folder

### Phase 2: Activity Triggers
**Goal**: Watch for file changes and trigger backups after 60s of inactivity (debouncing)
**Depends on**: Phase 1
**Research**: Complete
**Plans**: 2 plans

Plans:
- [x] 02-01: File watcher implementation with debouncing
- [x] 02-02: Integration with backup engine

### Phase 3: Claude Code Integration
**Goal**: Trigger backups on Claude Code events (conversation end, file changes, commits)
**Depends on**: Phase 2
**Research**: Complete
**Plans**: 2 plans

Plans:
- [x] 03-01: Create hook scripts and settings template
- [x] 03-02: Event-triggered backup orchestration

### Phase 4: Fallback Chain
**Goal**: Implement reliability chain: cloud folder → rclone API → local queue
**Depends on**: Phase 1
**Research**: Unlikely (rclone already exists in codebase)
**Plans**: 2 plans

Plans:
- [x] 04-01: Fallback detection and switching logic
- [x] 04-02: Local queue for offline scenarios

### Phase 5: Tiered Retention
**Goal**: Manage snapshot lifecycle with hourly/daily/weekly/monthly tiers (like Time Machine)
**Depends on**: Phase 1
**Research**: Unlikely (internal patterns, date math in bash)
**Plans**: TBD

Plans:
- [x] 05-01: Retention policy engine
- [x] 05-02: Cleanup and pruning automation

### Phase 6: Dashboard & Monitoring
**Goal**: Status bar indicator, all-projects dashboard, sub-minute restore capability
**Depends on**: Phases 1-5
**Research**: Unlikely (existing notification infrastructure)
**Plans**: TBD

Plans:
- [x] 06-01: Status bar indicator implementation
- [x] 06-02: All-projects dashboard view
- [ ] 06-03: Restore interface and capability

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Cloud Destination Setup | 2/2 | Complete | 2026-01-11 |
| 2. Activity Triggers | 2/2 | Complete | 2026-01-11 |
| 3. Claude Code Integration | 2/2 | Complete | 2026-01-11 |
| 4. Fallback Chain | 2/2 | Complete | 2026-01-11 |
| 5. Tiered Retention | 2/2 | Complete | 2026-01-11 |
| 6. Dashboard & Monitoring | 2/3 | In progress | - |
