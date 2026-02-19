# Product Hunt Launch Draft

---

## Product Name
Checkpoint

## Tagline
Automated backups for developers -- protects what Git ignores.

## Description

Checkpoint is a free, open-source backup daemon that runs silently in the background, protecting the parts of your dev projects that Git and Time Machine miss.

Your `.env` files, local databases, API keys, credentials, untracked work — all the stuff in `.gitignore` that an AI coding assistant can destroy in an instant. Checkpoint backs it all up automatically, every hour.

It auto-detects SQLite, PostgreSQL, MySQL, and MongoDB databases (including ones running in Docker) and creates proper dumps -- not raw file copies. Cloud sync is optional and encrypted with age before upload, supporting Dropbox, Google Drive, OneDrive, and iCloud via rclone.

Built in bash with zero runtime dependencies. Runs via launchd on macOS and systemd on Linux. Includes a native SwiftUI menu bar dashboard on macOS, interactive fzf-based history browsing, and searchable version history across all your projects.

Install once, run `backup-now` in a project directory, and forget about it. 164 tests passing.

## Key Features

- **Backs up what Git ignores** -- .env files, databases, credentials, untracked work
- **Automatic scheduled backups** -- background daemon via launchd/systemd, hourly by default with cron expressions, work-hours presets, and custom intervals
- **Database support** -- SQLite, PostgreSQL, MySQL, MongoDB (local, remote, and Docker)
- **Encrypted cloud sync** -- age encryption + rclone (Dropbox, Google Drive, OneDrive, iCloud)
- **Version history** -- search across all backups, restore any file from any point in time
- **Interactive browsing** -- fzf-powered snapshot browsing and file preview
- **Native macOS dashboard** -- SwiftUI menu bar app with real-time status and notifications
- **Zero dependencies** -- written in bash, runs anywhere, composes with existing tools
- **Docker-aware** -- auto-detects databases in docker-compose.yml
- **164 tests passing** -- comprehensive test coverage for backup, restore, encryption, and edge cases

## Topics / Categories
- Developer Tools
- Open Source
- Productivity
- macOS

## Links
- Website: https://checkpoint.fluxcode.studio
- GitHub: https://github.com/fluxcodestudio/Checkpoint

## Pricing
Free for personal and noncommercial use. Commercial licenses available.

---

## Maker Comment

Hi Product Hunt! I'm Jon, the builder behind Checkpoint.

I started this project the night an AI coding assistant ate my database for the third time. Not corrupted — deleted. Hundreds of dollars of data, gone in an instant, no recovery. My code was safely in Git, but my `.env` files, local databases, API keys, and weeks of uncommitted work were all gone. I asked the AI to revert. It couldn't. The originals had been overwritten.

That happened across multiple projects. Hundreds of hours and thousands of dollars, lost to a tool that doesn't understand the concept of "I might need that later." So I opened a terminal and started writing a bash script. That script grew into a proper backup system with database detection, encrypted cloud sync, a watchdog daemon, and eventually a native macOS menu bar app.

The core is intentionally written in bash -- no Python, no Node, no Go binary. Just a daemon that uses native OS process management (launchd/systemd) and native database tools (pg_dump, sqlite3, mongodump). It runs on any Mac or Linux machine without installing anything beyond the clone.

I'm especially proud of the interactive history browsing (powered by fzf) and the encrypted cloud sync. You can search across all your backup history, preview old versions, and restore any file from any point in time.

I made Checkpoint free because the open-source community taught me everything I know. Every library I've ever imported, every tutorial that got me unstuck — that was someone else's generosity. I wanted to build something worth giving back to the community I'd received so much from.

Would love your feedback. What's missing? What would make this more useful for your workflow?

-- Jon / Fluxcode Studio
