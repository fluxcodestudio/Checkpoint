# Reddit r/devops Post

---

**Title:** Checkpoint: automated backup daemon for dev environments -- launchd/systemd, health monitoring, watchdog, encrypted cloud sync

---

I built this after an AI coding assistant destroyed my database — multiple times, across different projects. CI/CD protects deployed code, Git protects committed code, but nothing was protecting my local dev environment — `.env` files, databases, untracked work, credentials. The AI overwrote files it couldn't recover, and hundreds of hours of work vanished. With open-source AI models running without guardrails becoming the norm, the risk to local dev environments is only going up.

**Checkpoint** is an open-source backup daemon that runs on macOS (launchd) and Linux (systemd). It backs up developer projects hourly, including everything `.gitignore` excludes.

**Automation and reliability:**

- **Daemon-based:** Runs via `launchd` (macOS) or `systemd` (Linux). Built-in scheduler with cron expressions, presets (`@workhours`, `@every-5min`, `@daily`), and custom intervals. The OS handles lifecycle and restart-on-crash.
- **Watchdog:** Built-in health monitoring detects stale backups (nothing in 24h), daemon failures, disk space issues. Triggers alerts via macOS notifications or configurable hooks.
- **Idempotent operations:** Backups are safe to re-run. Interrupted backups don't leave corrupt state. Atomic writes with temp directories and mv.
- **Proper database dumps:** Uses `pg_dump`, `mysqldump`, `sqlite3 .dump`, `mongodump` -- not file copies. Handles remote databases (Neon, Supabase, RDS connection strings from `.env`).
- **Docker-aware:** Auto-detects databases in `docker-compose.yml`, runs `docker exec` dumps, auto-starts Docker Desktop if needed on macOS.

**Encrypted cloud sync:**

- Uses [rclone](https://rclone.org/) for cloud transport -- Dropbox, Google Drive, OneDrive, S3, any rclone-compatible backend
- Files encrypted with [age](https://github.com/FiloSottile/age) before upload
- Local backups stay unencrypted for fast access
- Zero-knowledge: keys never leave the machine
- One command setup: `checkpoint encrypt setup`

**Observability:**

```bash
$ checkpoint --status
  Daemon: running (PID 4821)
  Projects: 8 registered
  Last backup: 12 min ago
  Cloud sync: enabled (encrypted)
  Storage: 1.4 GB local / 890 MB cloud
  Health: all projects backed up within 1h
```

- Per-project backup logs with timestamps
- Structured output for scripting and monitoring integration
- macOS menu bar dashboard (SwiftUI) for visual monitoring
- Configurable notification thresholds

**Architecture:**

- Written in bash. Controversial, but intentional: zero runtime dependencies, runs on any POSIX system, composes with existing tooling.
- Backup structure is plain files in a predictable directory layout -- easy to inspect, rsync, or integrate with existing backup infrastructure.
- Config is a simple `.checkpoint.conf` per project. No database, no service dependency.
- 164 tests covering backup workflows, database types, encryption, cloud sync, error recovery, concurrent backups, and edge cases.

**Install:**

```bash
git clone https://github.com/fluxcodestudio/Checkpoint.git
cd Checkpoint && ./bin/install-global.sh
```

Then `backup-now` in any project directory. Auto-detects databases, registers the project, starts hourly backups.

Free for personal/noncommercial use (Polyform Noncommercial) — the open-source community is the reason I know how to do any of this, and I wanted to build something worth giving back. Commercial licenses available.

GitHub: https://github.com/fluxcodestudio/Checkpoint
Website: https://checkpoint.fluxcode.studio

Curious how others in r/devops handle local dev environment backups — especially now that AI coding assistants have full filesystem access. Is anyone else automating this, or is it mostly "hope Git is enough"?
