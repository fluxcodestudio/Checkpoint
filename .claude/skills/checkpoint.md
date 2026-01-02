---
name: checkpoint
description: Checkpoint backup system - run backups, check status, restore files
match:
  - /checkpoint
  - /backup
---

Checkpoint backup command center. Run the checkpoint command based on what the user needs:

**Status check:**
```bash
export PATH="$HOME/.local/bin:$PATH" && checkpoint --status
```

**Run backup now:**
```bash
export PATH="$HOME/.local/bin:$PATH" && backup-now
```

**View backup status:**
```bash
export PATH="$HOME/.local/bin:$PATH" && backup-status
```

**Restore files:**
```bash
export PATH="$HOME/.local/bin:$PATH" && backup-restore
```

If no specific action requested, show status. Available commands: backup-now, backup-status, backup-restore, backup-cleanup, checkpoint --dashboard
