# Email Outreach Templates

---

## Template A: Developer Newsletter Editors

**Subject:** Story idea: The stuff Git doesn't back up (and a new open-source tool that does)

---

Hi [Name],

I'm a reader of [Newsletter Name] and wanted to share something your audience might find useful.

I built an open-source tool called **Checkpoint** after an AI coding assistant destroyed my database — not once, but multiple times across different projects. My code was in Git, but everything in `.gitignore` — `.env` files, local databases, API keys, credentials — was gone. The AI overwrote the originals and couldn't recover them.

Checkpoint is a free backup daemon for developers that protects exactly the files Git and Time Machine miss. It runs hourly in the background (launchd/systemd), auto-detects databases (SQLite, PostgreSQL, MySQL, MongoDB -- including Docker), and optionally syncs encrypted backups to cloud storage.

A few things that might make it interesting for your readers:

- It's written entirely in bash -- no runtime dependencies, runs anywhere
- Includes a native SwiftUI macOS menu bar dashboard
- Interactive fzf-based history browsing and search
- 164 tests passing, actively maintained
- Free for personal use (Polyform Noncommercial) — giving back to the community that taught me everything

**GitHub:** https://github.com/fluxcodestudio/Checkpoint
**Website:** https://checkpoint.fluxcode.studio

With AI coding assistants getting full filesystem access — and open-source models running without guardrails — this problem is only getting worse. Happy to provide a demo, answer technical questions, or write a guest post if that's something you do. No pressure either way — just thought it might resonate with devs who've had the same "wait, that wasn't backed up?" moment.

Thanks for your time,
Jon Rezin
Fluxcode Studio LLC

---

## Template B: Dev Tool Bloggers

**Subject:** Open-source backup tool that fills the gap between Git and Time Machine

---

Hi [Name],

I've been following your writing on [Blog/Site] and really enjoyed your piece on [relevant recent article]. Thought you might be interested in a tool I built after an AI coding assistant destroyed my database — multiple times, across different projects.

**Checkpoint** is a free, open-source automated backup system for developer projects. The pitch is simple: Git protects committed code, but it doesn't protect `.env` files, local databases, credentials, or untracked work — the exact files an AI assistant can overwrite in an instant. Checkpoint does.

Here's what makes it different from "just use rsync" or "just use Time Machine":

- **Database-aware:** Auto-detects SQLite, PostgreSQL, MySQL, MongoDB and creates proper dumps (pg_dump, not file copies). Works with Docker containers too.
- **Encrypted cloud sync:** Files encrypted with age before upload to Dropbox, Google Drive, OneDrive, or iCloud via rclone. Zero-knowledge.
- **Daemon-based:** Runs via launchd (macOS) or systemd (Linux). Built-in scheduler with cron expressions, work-hours presets, and custom intervals.
- **Searchable history:** `checkpoint search "API_KEY"` finds matches across all backup versions. Interactive fzf browsing for snapshots.
- **Native macOS dashboard:** SwiftUI menu bar app with live status, notifications, one-click actions.
- **Written in bash:** Zero dependencies. 164 tests. Runs on any Mac or Linux box.

If you'd be interested in reviewing it, doing a walkthrough, or just taking a look, I'd be happy to answer any questions or jump on a call. I can also provide early access to any upcoming features.

**GitHub:** https://github.com/fluxcodestudio/Checkpoint
**Website:** https://checkpoint.fluxcode.studio

Best,
Jon Rezin
Fluxcode Studio LLC

---

## Template C: Podcast Hosts

**Subject:** Podcast topic idea: Why every developer has a backup blind spot

---

Hi [Name],

I'm a listener of [Podcast Name] and wanted to pitch a topic that I think would spark a good conversation with your audience.

**The idea:** Most developers think they're backed up because they use Git. But Git doesn't protect `.env` files, local databases, credentials, or uncommitted work. An AI coding assistant can destroy any of it in an instant — and with open-source models running without guardrails, this risk is exploding.

I built an open-source tool called **Checkpoint** after an AI assistant ate my database — multiple times, across different projects. Hundreds of hours and thousands of dollars, gone. It's a backup daemon that runs in the background and protects exactly the stuff `.gitignore` excludes — including proper database dumps for SQLite, PostgreSQL, MySQL, and MongoDB (even in Docker containers).

Some angles that might be interesting to discuss:

- **AI coding assistants are a data loss vector** — they have full filesystem access and no concept of "I might need that later." With open-source models running without guardrails, this risk is only growing
- **The "backup blind spot"** — why developers who are meticulous about version control are often completely unprotected for their most sensitive files
- **Building developer tools in bash** — Checkpoint is written entirely in bash (controversial choice, strong opinions welcome)
- **The local-first vs. cloud debate** — Checkpoint is local-first with optional encrypted cloud sync, which touches on data sovereignty
- **Open-source business models** — using Polyform Noncommercial (free for personal use, commercial license available)

I'm Jon Rezin from Fluxcode Studio. Happy to be a guest, or just provide context for a segment if the topic interests you. Either way, keep up the great work on the show.

**Project links:**
- GitHub: https://github.com/fluxcodestudio/Checkpoint
- Website: https://checkpoint.fluxcode.studio

Thanks,
Jon Rezin
Fluxcode Studio LLC
