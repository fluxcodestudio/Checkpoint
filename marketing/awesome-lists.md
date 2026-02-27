# Awesome-List Submissions — Checkpoint

> **When to submit:** After HN launch, once you have 50+ GitHub stars
> **Status:** Draft entries ready, not yet submitted

---

## Summary

| List | Stars | Min Requirement | Section | Status |
|------|-------|----------------|---------|--------|
| **awesome-mac** | 99K | None | Developer Tools | Ready to submit |
| **awesome-sysadmin** | 33K | Free software, active | Backups | Ready to submit |
| **awesome-cli-apps** | 19K | 20+ stars, 90+ days old | Files and Directories | Ready after 90 days |
| **awesome-shell** | 36K | 50+ stars | Applications | Ready after 50 stars |
| ~~awesome-selfhosted~~ | 275K | — | — | **Skip — CLI tools don't qualify** (requires self-hosted web services) |

---

## 1. awesome-mac (jaywcjlove/awesome-mac)

**Stars:** 99K
**Min requirements:** None
**Section:** Developer Tools > Command Line Tools
**Format:** Uses `*` (asterisk), badge icons for OSS and Freeware
**PR title:** `Add Checkpoint to Developer Tools`
**Repo:** https://github.com/jaywcjlove/awesome-mac

### Entry

```markdown
* [Checkpoint](https://checkpoint.fluxcode.studio/) - Automated backup for developers. Databases (SQLite, PostgreSQL, MySQL, MongoDB), .env files, credentials, encrypted cloud sync, native macOS dashboard. [![Open-Source Software][OSS Icon]](https://github.com/fluxcodestudio/Checkpoint) ![Freeware][Freeware Icon]
```

### Notes
- Alphabetical ordering within the section — find where "C" falls
- Badge icons `[OSS Icon]` and `[Freeware Icon]` are defined at the bottom of their README
- Link the OSS badge to the GitHub repo
- Main link goes to the website, not GitHub

---

## 2. awesome-sysadmin (awesome-foss/awesome-sysadmin)

**Stars:** 33K
**Min requirements:** Free software, actively maintained, healthy ecosystem
**Section:** Backups
**Format:** Uses `-` (dash), includes `License` and `Language` tags
**PR title:** `Add Checkpoint to Backups`
**Repo:** https://github.com/awesome-foss/awesome-sysadmin

### Entry

```markdown
- [Checkpoint](https://checkpoint.fluxcode.studio/) - Automated backup for developers with database support (SQLite, PostgreSQL, MySQL, MongoDB), encrypted cloud sync, and native macOS dashboard. ([Source Code](https://github.com/fluxcodestudio/Checkpoint)) `Polyform-Noncommercial-1.0.0` `Shell`
```

### Notes
- Description must be under 250 characters, sentence case
- Alphabetical ordering — goes between "BorgBackup" and "Duplicati"
- PR must answer: why it's awesome, how long you've used it, pros/cons
- Self-submissions discouraged — consider asking someone else to submit, or note in the PR that you're the author and explain why it belongs
- **License concern:** Polyform Noncommercial is not FSF-approved "Free software." This list requires Free software. They may reject on license grounds. Worth trying — worst case they say no.

### PR Description Template

```
## Why is this awesome?

Checkpoint solves a problem most backup tools ignore: developer project files
that Git doesn't protect (.env, databases, credentials, untracked work). It
auto-detects databases (SQLite, PostgreSQL, MySQL, MongoDB — including Docker
containers), creates proper dumps (not file copies), and runs as a background
daemon via launchd/systemd.

## How long have you used it?

I'm the author — it's been in daily use across 20+ projects for 3 months.

## Pros
- Zero runtime dependencies (pure bash)
- Proper database dumps via native tools (pg_dump, sqlite3, mongodump)
- Encrypted cloud sync (age + rclone)
- Native macOS SwiftUI dashboard
- 164 tests passing

## Cons
- Polyform Noncommercial license (free for personal use, commercial license required for companies)
- macOS dashboard is macOS-only (CLI works on Linux)
```

---

## 3. awesome-cli-apps (agarrharr/awesome-cli-apps)

**Stars:** 19K
**Min requirements:** 20+ GitHub stars, 90+ days old, free and open source
**Section:** Files and Directories > File Sync/Sharing
**Format:** Uses `-` (dash), terse descriptions, no badges
**PR title:** `Add Checkpoint`
**Repo:** https://github.com/agarrharr/awesome-cli-apps

### Entry

```markdown
- [Checkpoint](https://github.com/fluxcodestudio/Checkpoint) - Automated backup for developers with database detection, encrypted cloud sync, and version history.
```

### Notes
- Added at the **bottom** of the section (not alphabetical)
- Description starts with capital, ends with period
- No redundant words like "CLI" or "terminal"
- Must be older than 90 days from first release — check before submitting
- **License concern:** Same as awesome-sysadmin — Polyform NC may not qualify as "free and open source." Worth trying.

---

## 4. awesome-shell (alebcay/awesome-shell)

**Stars:** 36K
**Min requirements:** 50+ GitHub stars
**Section:** Applications (or System Utilities)
**Format:** Uses `*` (asterisk), simple format, no badges
**PR title:** `Add Checkpoint`
**Repo:** https://github.com/alebcay/awesome-shell

### Entry

```markdown
* [Checkpoint](https://github.com/fluxcodestudio/Checkpoint) - Automated backup for developers with database detection, encrypted cloud sync, and native macOS dashboard
```

### Notes
- No trailing period on descriptions
- Very simple format — name, link, description
- **Requires 50+ stars** — wait until you have them before submitting
- Self-promotion is explicitly allowed

---

## 5. awesome-selfhosted — SKIP

**Why:** awesome-selfhosted explicitly excludes "Desktop/mobile/CLI apps" and "mere CLI tools." They want self-hosted web services with a web interface. Checkpoint doesn't qualify unless a web dashboard is added in the future.

---

## Submission Checklist

### Ready Now (submit after HN launch regardless of star count)
- [ ] **awesome-mac** — no minimum star requirement
- [ ] **awesome-sysadmin** — no minimum star requirement (but license may be an issue)

### Ready After 20+ Stars
- [ ] **awesome-cli-apps** — requires 20+ stars and 90+ days

### Ready After 50+ Stars
- [ ] **awesome-shell** — requires 50+ stars

### Submission Steps (same for all)
1. Fork the repo
2. Add the entry in the correct section
3. Submit PR with clear title and description
4. Be patient — some take weeks to review
5. If rejected, read feedback and resubmit if appropriate

---

*Last updated: February 26, 2026*
