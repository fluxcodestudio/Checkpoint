# Reddit r/selfhosted Post

---

**Title:** Checkpoint: local-first automated backup system for dev projects -- encrypted cloud sync optional, your data stays yours

---

Hey r/selfhosted,

I built an open-source backup tool after an AI coding assistant destroyed my database — multiple times, across different projects. Hundreds of hours of work gone because the AI overwrote files it couldn't recover. My code was in Git. Everything else wasn't.

**The problem:** Git doesn't back up `.env` files, databases, credentials, or untracked work. Time Machine backs up everything but doesn't understand databases (copying a running PostgreSQL data directory = corruption risk). And neither can protect you from an AI assistant rewriting your files in real time. With open-source AI models running without guardrails, this risk is only growing.

**What Checkpoint does:**

- Runs as a background daemon (launchd on macOS, systemd on Linux) -- fully self-hosted, no cloud account required
- Backs up source code, `.env` files, credentials, and databases (SQLite, PostgreSQL, MySQL, MongoDB)
- Auto-detects databases in Docker containers and dumps them properly
- All backups stored locally on your machine by default -- you own everything
- Cloud sync is 100% optional -- if you enable it, files are encrypted with [age](https://github.com/FiloSottile/age) before upload
- Supports Dropbox, Google Drive, OneDrive, iCloud via rclone -- or any rclone-compatible storage
- Zero-knowledge cloud storage: your keys never leave your machine
- Searchable version history with restore (`checkpoint restore .env --from "3 days ago"`)

**Self-hosting details:**

- Written entirely in bash -- no external runtime, no containers needed, no phone-home
- Backups stored in a plain directory structure you can inspect, copy, or rsync anywhere
- No database or service to maintain -- it's a daemon + flat files
- Config is a simple `.checkpoint.conf` per project
- Works on any Mac or Linux box, including headless servers

**Install:**

```bash
git clone https://github.com/fluxcodestudio/Checkpoint.git
cd Checkpoint && ./bin/install-global.sh
```

Then `backup-now` in any project directory. Done.

Free for personal use under Polyform Noncommercial. 164 tests passing. Native macOS menu bar dashboard available but completely optional.

GitHub: https://github.com/fluxcodestudio/Checkpoint
Website: https://checkpoint.fluxcode.studio

It's free because the open-source community is the reason I know how to code. I wanted to build something worth giving back.

Would love feedback from the self-hosting community. Especially interested in hearing about storage backends people would want beyond what rclone supports.
