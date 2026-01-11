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
- [ ] **Phase 3: Claude Code Integration** - Event triggers for conversation end, file changes, commits
- [ ] **Phase 4: Fallback Chain** - Cloud folder → rclone API → local queue reliability
- [ ] **Phase 5: Tiered Retention** - Hourly/daily/weekly/monthly snapshot management
- [ ] **Phase 6: Dashboard & Monitoring** - Status bar indicator, all-projects view, restore capability

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
**Research**: Likely (fswatch/inotify patterns for pure bash)
**Research topics**: fswatch usage on macOS, efficient debouncing in bash, excluding patterns (node_modules, .git)
**Plans**: TBD

Plans:
- [ ] 02-01: File watcher implementation with debouncing
- [ ] 02-02: Integration with backup engine

### Phase 3: Claude Code Integration
**Goal**: Trigger backups on Claude Code events (conversation end, file changes, commits)
**Depends on**: Phase 2
**Research**: Likely (Claude Code hooks mechanism)
**Research topics**: Claude Code hooks API, event types available, hook configuration
**Plans**: TBD

Plans:
- [ ] 03-01: Research and implement Claude Code hooks
- [ ] 03-02: Event-triggered backup orchestration

### Phase 4: Fallback Chain
**Goal**: Implement reliability chain: cloud folder → rclone API → local queue
**Depends on**: Phase 1
**Research**: Unlikely (rclone already exists in codebase)
**Plans**: TBD

Plans:
- [ ] 04-01: Fallback detection and switching logic
- [ ] 04-02: Local queue for offline scenarios

### Phase 5: Tiered Retention
**Goal**: Manage snapshot lifecycle with hourly/daily/weekly/monthly tiers (like Time Machine)
**Depends on**: Phase 1
**Research**: Unlikely (internal patterns, date math in bash)
**Plans**: TBD

Plans:
- [ ] 05-01: Retention policy engine
- [ ] 05-02: Cleanup and pruning automation

### Phase 6: Dashboard & Monitoring
**Goal**: Status bar indicator, all-projects dashboard, sub-minute restore capability
**Depends on**: Phases 1-5
**Research**: Unlikely (existing notification infrastructure)
**Plans**: TBD

Plans:
- [ ] 06-01: Status bar indicator implementation
- [ ] 06-02: All-projects dashboard view
- [ ] 06-03: Restore interface and capability

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Cloud Destination Setup | 2/2 | Complete | 2026-01-11 |
| 2. Activity Triggers | 0/2 | Not started | - |
| 3. Claude Code Integration | 0/2 | Not started | - |
| 4. Fallback Chain | 0/2 | Not started | - |
| 5. Tiered Retention | 0/2 | Not started | - |
| 6. Dashboard & Monitoring | 0/3 | Not started | - |
