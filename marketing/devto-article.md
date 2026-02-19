---
title: An AI Ate My Database. So I Built a Backup System.
published: false
description: I lost months of work and thousands of dollars when an AI coding assistant destroyed my database and couldn't recover it. Here's the tool I built so it never happens again.
tags: opensource, devtools, backup, ai
cover_image:
---

# An AI Ate My Database. So I Built a Backup System.

I code like I'm running out of time. Big ideas come rapid-fire — SaaS tools, client projects, side hustles — and I chase them hard. Late nights bleed into early mornings. Months of work stack up across a dozen project folders. It's the kind of pace where you don't think about backups because you're too busy building.

Then one night, my AI coding assistant ate my database.

Not corrupted it. Not partially overwrote it. *Ate* it. Hundreds of dollars worth of data — gone in an instant. No recovery. No undo. The AI had made changes deep in the project, and the original was simply no longer there.

I asked it to revert. It couldn't. The data was gone.

This didn't happen once. It happened *multiple* times across different projects. Changes I wanted rolled back, but the originals had been overwritten or deleted by an AI that doesn't understand the concept of "I might need that later." Hundreds of hours of work. Thousands of dollars. Vanished because I trusted a tool that was never designed to protect my files.

That was the night I said *no more*.

I made Checkpoint free because the open-source community taught me how to code. Every stack trace I Googled, every library I imported, every tutorial that walked me through something I didn't understand — that was other people's work, given freely. I wanted to build something worth giving back to the community I'd gotten so much from.

## The Problem Nobody Talks About

Here's the uncomfortable truth about modern development: we're building faster than ever with AI assistants, but our safety net hasn't kept up. Git tracks committed code. It was never designed to protect the rest — and "the rest" is where the real damage happens.

**Your databases.** That SQLite file with months of seed data and real records? Not in Git. Your local Postgres with customer test accounts and carefully tuned schemas? Not in Git. An AI assistant can torch any of it with a single bad command.

**Your `.env` files.** API keys, Stripe secrets, database URLs, OAuth credentials. They're in `.gitignore` for good reason — but that means they're in *nothing*. When they're gone, they're gone. Try recreating 15 API keys across 8 services from memory.

**Your uncommitted work.** That half-finished feature you've been grinding on for a week? The experimental branch you haven't pushed? Git only knows what you've told it about. Everything else is living on a prayer.

**Your credentials and configs.** The invisible plumbing that makes your entire dev environment work. SSH keys, registry tokens, local tooling configs. All unprotected.

## "Just Use Time Machine"

I hear this one a lot. And sure — Time Machine technically captures everything on your disk. But:

- It backs up 500GB of system files alongside the 2GB you actually care about
- Restoring a single project file is an archaeological expedition
- It doesn't understand databases — copying a running Postgres data directory is a recipe for corruption
- No encryption, no cloud sync, no search
- And it sure as hell can't protect you from an AI assistant rewriting files in real time

Time Machine is great for "my laptop died." It's useless for "an AI just overwrote my database and I need the version from two hours ago."

## So I Built Checkpoint

That night — the one where I lost the database for the third time — I opened a terminal and started writing a bash script. Something simple: just copy my project files and database dumps somewhere safe, on a schedule, without me having to think about it.

That script turned into a weekend project. The weekend project turned into a month. The month turned into [Checkpoint](https://github.com/fluxcodestudio/Checkpoint).

Checkpoint is a free, open-source backup system built specifically for developers. It runs as a background daemon and backs up your projects hourly -- including everything Git misses.

### Here's what it looks like in practice:

```bash
# First time? Just cd into your project and run:
$ cd my-saas-app
$ backup-now

# That's it. Project is registered and backed up hourly from now on.
# Checkpoint auto-detects databases, .env files, credentials -- all of it.
```

The first backup scans your project, finds databases (SQLite, PostgreSQL, MySQL, MongoDB -- even ones running in Docker containers), identifies sensitive files, and creates a complete snapshot. Every hour after that, it does it again automatically.

### Searching and restoring

```bash
# Find a file across all your backup history
$ checkpoint search ".env"
  Found in 4 files across 3 projects

# Restore a specific file from 3 days ago
$ checkpoint restore .env --from "3 days ago"
  Restored .env (v2026-02-14_10:30)

# Browse backup history interactively with fzf
$ checkpoint history --interactive
```

### Encrypted cloud sync

Local backups are great until your drive dies (ask me how I know). Checkpoint can sync encrypted backups to Dropbox, Google Drive, OneDrive, or iCloud via rclone:

```bash
$ checkpoint encrypt setup
# Generates your encryption key, enables age encryption
# Cloud backups are encrypted before upload -- zero-knowledge storage
```

Your local backups stay unencrypted for fast access. Only the cloud copies get encrypted. Your keys never leave your machine.

### Native macOS dashboard

I built a SwiftUI menu bar app that shows backup status for all your projects at a glance. Click the icon, see which projects backed up, which ones failed, and trigger manual backups. Native macOS notifications alert you if something goes wrong.

But the dashboard is completely optional. Everything works from the terminal.

## The Architecture

Checkpoint is built almost entirely in bash. I know -- "a backup system in bash?" But hear me out:

- Bash runs everywhere. macOS, Linux, any server. No runtime dependencies.
- `launchd` on macOS and `systemd` on Linux handle the daemon lifecycle. Battle-tested process managers, not some Node.js process hoping it stays alive.
- Database dumps use native tools (`sqlite3`, `pg_dump`, `mongodump`). No ORM, no abstraction layer, just the tools the database vendors provide.
- Encryption uses [age](https://github.com/FiloSottile/age) -- modern, auditable, no-config encryption.
- Cloud sync uses [rclone](https://rclone.org/) -- supports 40+ cloud providers.

The test suite has 164 tests covering backup workflows, database types, encryption, cloud sync, error recovery, and edge cases. All passing.

## What Checkpoint Backs Up (That Git Doesn't)

| What | Git | Checkpoint |
|------|-----|------------|
| Source code | Yes | Yes |
| `.env` files | No (.gitignore) | Yes |
| SQLite databases | No (.gitignore) | Yes (proper dump) |
| PostgreSQL/MySQL | No | Yes (pg_dump/mysqldump) |
| MongoDB | No | Yes (mongodump) |
| Docker databases | No | Yes (auto-detect) |
| Untracked files | No | Yes |
| Credentials/keys | No (.gitignore) | Yes |
| Version history | Committed only | Everything |

## Try It

```bash
git clone https://github.com/fluxcodestudio/Checkpoint.git
cd Checkpoint && ./bin/install-global.sh
```

Then go to any project directory and run `backup-now`. That's it.

Checkpoint is free for personal and noncommercial use under the [Polyform Noncommercial License](https://polyformproject.org/licenses/noncommercial/1.0.0/). Commercial licenses are available for teams and companies.

The full docs, source code, and issue tracker are on GitHub: [github.com/fluxcodestudio/Checkpoint](https://github.com/fluxcodestudio/Checkpoint)

Website: [checkpoint.fluxcode.studio](https://checkpoint.fluxcode.studio)

---

Honest question for the room: are you backing up your `.env` files? Your local databases? Or are you out there running on vibes and prayers like I was?
