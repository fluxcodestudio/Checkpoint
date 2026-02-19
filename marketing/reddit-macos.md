# Reddit r/macos Post

---

**Title:** Built a native SwiftUI menu bar app for automated developer backups -- launchd daemon, macOS notifications, zero config

---

Hey r/macos,

I built Checkpoint after an AI coding assistant destroyed my database — multiple times, across different projects. Hundreds of hours of work gone because the AI overwrote files it couldn't recover. That was the night I said "no more." I wanted to share the macOS-native side of it since it leans heavily into platform-specific features.

**Native SwiftUI Menu Bar Dashboard:**

The dashboard lives in your menu bar and shows real-time backup status for all your dev projects at a glance:

- Per-project status: last backup time, file count, backup size
- Live progress indicator when a backup is running
- One-click "Backup All" to trigger immediate backups
- Pause/Resume controls
- In-app settings panel (press Cmd+, to open)
- Project context menus for per-project actions

It's built in SwiftUI and feels like a native macOS citizen -- not an Electron wrapper, not a web view.

**launchd Integration:**

Checkpoint runs as a proper launchd daemon. This means:

- It starts automatically at login
- macOS manages the process lifecycle (restarts on crash, respects system sleep)
- No login items hack, no background Node process
- Proper `~/Library/LaunchAgents/` plist
- Low resource usage -- it only wakes up hourly

**macOS Desktop Notifications:**

- Notifies you when a backup fails
- Alerts if no backup has run in 24+ hours
- Configurable: all notifications, failure-only, or silent
- Uses native `NSUserNotification` -- shows up in Notification Center like any other macOS notification

**What it backs up:**

Checkpoint is designed to protect what Time Machine and Git both miss — especially from AI coding assistants that can torch your files in a single bad command:

- `.env` files, API keys, credentials (things in `.gitignore`)
- Databases: SQLite, PostgreSQL, MySQL, MongoDB (proper dumps, not raw file copies)
- Docker container databases
- Untracked and uncommitted work
- Encrypted cloud sync (Dropbox, Google Drive, OneDrive, iCloud) via rclone

**Install:**

```bash
git clone https://github.com/fluxcodestudio/Checkpoint.git
cd Checkpoint && ./bin/install-global.sh
```

The installer sets up the launchd daemon, installs the menu bar app, and registers the CLI tools. Then just run `backup-now` in any project directory.

Free and open source for personal use — the open-source community taught me how to code, and I wanted to give something back. 164 tests passing.

GitHub: https://github.com/fluxcodestudio/Checkpoint
Website: https://checkpoint.fluxcode.studio

The dashboard screenshot is on the website if you want to see what it looks like. Would love to hear feedback from other macOS devs.
