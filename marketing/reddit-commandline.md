# Reddit r/commandline Post

---

**Title:** Checkpoint: bash-native automated backup daemon with fzf history browsing -- backs up what .gitignore excludes

---

Built this for myself after an AI coding assistant ate my database — not once, but multiple times across different projects. Hundreds of hours of work gone because the AI overwrote originals it couldn't recover. Figured some of you might find it useful.

**What it is:** A backup daemon written in bash that runs hourly via launchd/systemd. It backs up your dev projects -- including the stuff Git ignores: `.env` files, SQLite/PostgreSQL/MySQL/MongoDB databases, credentials, untracked files.

**CLI-first, no GUI required:**

```bash
# Register and back up a project (one command)
$ backup-now

# Check status across all projects
$ checkpoint --status
  Daemon: running (PID 4821)
  Projects: 8 registered
  Last backup: 12 min ago

# Search across all backup history
$ checkpoint search "DATABASE_URL"
  Found in 3 files across 2 projects

# Restore a file from a specific point in time
$ checkpoint restore src/config.js --from "3 days ago"

# Browse backup history interactively with fzf
$ checkpoint history --interactive
```

**Why bash:**

- No runtime dependencies. No Python, no Node, no Go binary to install.
- Pipes and composes with everything you already use.
- Database dumps use native tools (`pg_dump`, `sqlite3`, `mongodump`) -- no abstraction layer.
- Process management handled by launchd/systemd -- not some userspace process manager hoping it stays alive.

**fzf integration:**

The `checkpoint history --interactive` command opens an fzf session where you can browse all snapshots, preview file contents, and restore directly. It's the fastest way to find "what did my `.env` look like on Tuesday?"

**Other CLI features:**

- `checkpoint search <pattern>` -- ripgrep-style search across all backup versions
- `checkpoint list` -- show all registered projects and their backup status
- `checkpoint encrypt setup` -- enable age encryption for cloud backups
- `checkpoint cloud sync` -- push encrypted backups to any rclone destination
- Exit codes and structured output for scripting

There is a macOS menu bar dashboard (SwiftUI) if you want it, but it's completely optional. Everything works from the terminal.

**Install:**

```bash
git clone https://github.com/fluxcodestudio/Checkpoint.git
cd Checkpoint && ./bin/install-global.sh
```

164 tests passing. Free for personal use — the open-source community taught me everything I know, and I wanted to give something back.

GitHub: https://github.com/fluxcodestudio/Checkpoint
