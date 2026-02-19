# Show HN: Checkpoint -- Automated backup for developers (encrypted cloud, database support)

**Link:** https://github.com/fluxcodestudio/Checkpoint

**Website:** https://checkpoint.fluxcode.studio

---

Hi HN,

I built Checkpoint after an AI coding assistant destroyed my database. Not corrupted it — deleted it. Hundreds of dollars of data, gone in an instant, no recovery. My code was in Git. The database wasn't. Neither were my `.env` files, API keys, or the uncommitted work I'd been grinding on for weeks.

This happened multiple times across different projects. The AI would make changes I wanted reverted, but the originals were already overwritten. Hundreds of hours of work. Thousands of dollars. Gone because I trusted a tool that doesn't understand "I might need that later."

Checkpoint is a free, open-source backup daemon for developers. It runs in the background on macOS (launchd) and Linux (systemd), backing up your projects hourly — including everything `.gitignore` excludes.

**What it backs up that Git doesn't:**
- `.env` files, credentials, API keys
- SQLite, PostgreSQL, MySQL, MongoDB (proper dumps, not file copies)
- Databases running in Docker containers
- Untracked and uncommitted files

**Key features:**
- Written in bash -- no runtime dependencies, runs anywhere
- Encrypted cloud sync via rclone (Dropbox, Google Drive, OneDrive, iCloud) using age encryption
- Version history with search and restore (`checkpoint search`, `checkpoint restore --from "3 days ago"`)
- Interactive fzf-based history browsing
- Native SwiftUI macOS menu bar dashboard (optional -- everything works from CLI)
- Watchdog health monitoring
- 164/164 tests passing

**Install:**
```
git clone https://github.com/fluxcodestudio/Checkpoint.git
cd Checkpoint && ./bin/install-global.sh
```

Then run `backup-now` in any project directory. It auto-detects databases, registers the project, and backs up hourly from then on.

Free for personal/noncommercial use (Polyform Noncommercial). Commercial licenses available.

I made Checkpoint free because the open-source community is the reason I know how to code at all. Every library, every tutorial, every Stack Overflow answer — that was other people giving their work away. I wanted to build something worth giving back.

With open-source AI models running without guardrails becoming the norm, the risk of an AI assistant torching your local files is only going up. Happy to answer questions about the architecture, the bash-as-a-framework decision, or anything else.
