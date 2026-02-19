## Checkpoint v2.5.2

The backup system that watches your back while you write code.

### What's New

**Encryption & Security**
- File encryption at rest using [age](https://github.com/FiloSottile/age) — cloud backups are encrypted before they leave your machine
- Zero-knowledge cloud storage: your provider sees ciphertext, you hold the key
- One command setup: `checkpoint encrypt setup`

**License Update**
- Migrated to [Polyform Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)
- Free for personal use, side projects, open-source, and education
- Commercial licenses available from Fluxcode Studio

**Marketing Site**
- New website at [checkpoint.fluxcode.studio](https://checkpoint.fluxcode.studio)
- Full documentation, comparison pages, FAQ
- LLM-optimized with llms.txt and structured data

**GitHub Migration**
- Repository moved to [github.com/fluxcodestudio/Checkpoint](https://github.com/fluxcodestudio/Checkpoint)
- 20 discoverable topics tagged
- Full CI workflow with syntax checks and test suite

### Full Feature Set

- Automatic hourly backups via background daemon
- Database support: SQLite, PostgreSQL, MySQL, MongoDB (local, remote, Docker)
- Encrypted cloud sync: Dropbox, Google Drive, OneDrive, iCloud, S3
- Native macOS menu bar dashboard (SwiftUI)
- Version history with search and restore via fzf
- Docker container database backup with auto-start
- Daemon health monitoring with watchdog and staleness alerts
- Full Linux support (systemd, cron fallback)
- 164/164 tests passing (100% coverage)

### Install

```bash
git clone https://github.com/fluxcodestudio/Checkpoint.git
cd Checkpoint && ./bin/install-global.sh
```

Then run `backup-now` in any project directory.

---

*Built by [Fluxcode Studio](https://fluxcode.studio)*
