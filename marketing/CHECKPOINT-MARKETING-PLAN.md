# Checkpoint — Comprehensive Marketing Plan

> **Product:** Checkpoint v2.7.0 — Automated backup for developers
> **Status:** Shipped, free, open source (Polyform Noncommercial)
> **Budget:** $0 (time-only investment)
> **Strategy:** Product-first promotion — Checkpoint drives awareness for Fluxcode Studio
> **GitHub:** https://github.com/fluxcodestudio/Checkpoint
> **Website:** https://checkpoint.fluxcode.studio
> **Parent brand:** https://fluxcode.studio

---

## Table of Contents

1. [Strategic Overview](#1-strategic-overview)
2. [The Narrative](#2-the-narrative)
3. [Pre-Launch Checklist](#3-pre-launch-checklist)
4. [Phase 1: Hacker News Launch (Day 1)](#4-phase-1-hacker-news-launch-day-1)
5. [Phase 2: Reddit Blitz (Days 2–7)](#5-phase-2-reddit-blitz-days-27)
6. [Phase 3: Dev.to Article (Days 3–5)](#6-phase-3-devto-article-days-35)
7. [Phase 4: Claude/AI Ecosystem (Days 1–14)](#7-phase-4-claudeai-ecosystem-days-114)
8. [Phase 5: GitHub Discovery (Days 1–14)](#8-phase-5-github-discovery-days-114)
9. [Phase 6: Email Outreach (Weeks 2–4)](#9-phase-6-email-outreach-weeks-24)
10. [Phase 7: Product Hunt (Week 4–6)](#10-phase-7-product-hunt-week-46)
11. [Phase 8: Ongoing Growth (Month 2+)](#11-phase-8-ongoing-growth-month-2)
12. [Content Calendar — First 30 Days](#12-content-calendar--first-30-days)
13. [Article Inventory & Status](#13-article-inventory--status)
14. [Metrics & Goals](#14-metrics--goals)
15. [Anti-Patterns](#15-anti-patterns)
16. [Fluxcode Studio Brand Integration](#16-fluxcode-studio-brand-integration)

---

## 1. Strategic Overview

### Why Checkpoint First

Checkpoint is the perfect lead product for Fluxcode Studio:

| Factor | Why it works |
|--------|-------------|
| **Free & open source** | Zero friction — anyone can try it immediately |
| **Solves a universal problem** | Every developer has lost files, .env configs, or database state |
| **AI angle is timely** | "AI ate my database" resonates RIGHT NOW — AI coding assistants are everywhere |
| **Technically impressive** | 83 shell scripts, 164 tests, native macOS app, encrypted cloud sync — this is serious software |
| **Builds trust** | Shipping a polished free tool proves you can build, which builds credibility for paid products |
| **SEO & backlinks** | Every mention of Checkpoint links back to fluxcode.studio |

### The Funnel

```
Checkpoint (free, open source)
  → GitHub stars, installs, community
    → Visitors discover Fluxcode Studio
      → Brand awareness, newsletter signups
        → Future product launches (Superstack, etc.)
```

### Maximum Exposure, Minimum Effort — Priority Order

| Priority | Channel | Effort | Reach | ROI |
|----------|---------|--------|-------|-----|
| 1 | **Hacker News** (Show HN) | 1 hour + comment replies | Massive if it hits front page | Highest |
| 2 | **Reddit** (4 targeted subreddits) | 30 min each (articles written) | High, targeted audiences | Very High |
| 3 | **Dev.to** (long-form article) | 30 min (article written) | Medium, long tail SEO | High |
| 4 | **Claude/AI ecosystem** | 1–2 hours total | Highly targeted | Very High |
| 5 | **GitHub awesome-lists** | 30 min total | Slow but permanent | High (passive) |
| 6 | **Email outreach** | 2–3 hours over 2 weeks | Variable, high-quality | Medium |
| 7 | **Product Hunt** | 2–3 hours prep + launch day | High if timed right | High |
| 8 | **Twitter/X thread** | 1 hour | Depends on following | Medium |

**Total time investment for full launch: ~15–20 hours spread over 4–6 weeks.**

---

## 2. The Narrative

### The Core Story

**An AI coding assistant kept destroying my databases and overwriting files I couldn't recover. I lost thousands of dollars and hundreds of hours across multiple projects. Git only protects committed code — everything in .gitignore was unprotected. So I built Checkpoint: a background daemon that automatically backs up everything Git misses, including proper database dumps, encrypted cloud sync, and a native macOS dashboard. I made it free because the open-source community taught me everything I know.**

### Story Angles by Audience

| Audience | Lead with | Article |
|----------|-----------|---------|
| **Hacker News** | Technical architecture (bash, launchd/systemd, no dependencies) + AI safety angle | `show-hn.md` |
| **r/commandline** | CLI-first design, fzf integration, bash philosophy | `reddit-commandline.md` |
| **r/devops** | Daemon architecture, health monitoring, encrypted cloud sync | `reddit-devops.md` |
| **r/macos** | Native SwiftUI dashboard, launchd integration, macOS notifications | `reddit-macos.md` |
| **r/selfhosted** | Local-first, no cloud required, data sovereignty, zero dependencies | `reddit-selfhosted.md` |
| **Dev.to** | Personal story (AI ate my database), detailed walkthrough | `devto-article.md` |
| **Product Hunt** | Visual product showcase, maker story | `product-hunt.md` |
| **Newsletter editors** | Novel angle (Grammy engineer's tool) + AI safety trend | `email-outreach.md` Template A |
| **Bloggers** | Technical deep-dive opportunity | `email-outreach.md` Template B |
| **Podcasts** | Grammy-to-code career story + backup blind spot topic | `email-outreach.md` Template C |

### Key Talking Points (use consistently across all channels)

1. **"Backs up what Git ignores"** — the one-line pitch
2. **"AI ate my database"** — the origin story hook
3. **"Proper database dumps, not file copies"** — technical credibility
4. **"Install once, forget about it"** — ease of use
5. **"164 tests passing"** — quality signal. **Verify this number before launch** — the count is from v2.6.0 README; v2.7.0 features (compression, cloud restore, mutual watchdog) may have added more tests. Run the test suite and update all articles with the actual count.
6. **"Free because the open-source community taught me everything"** — authenticity
7. **"Built by Fluxcode Studio"** — brand threading (subtle, not forced)

---

## 3. Pre-Launch Checklist

Complete these BEFORE posting anywhere. Every link in every article will get clicked — everything must work.

### GitHub Repo

- [ ] **BLOCKER: Add dashboard screenshot to README** — Dashboard.png exists in `/website/` but is NOT embedded in the README. HN and GitHub traffic lands on the README first. A visual showing the native macOS dashboard is critical for first impressions.
- [ ] **BLOCKER: Set custom social preview image** — Currently using GitHub's auto-generated card (`usesCustomOpenGraphImage: false`). Upload Dashboard.png or a branded image via Settings → Social preview. This is what appears when the GitHub link is shared on Twitter, Slack, Discord.
- [ ] **BLOCKER: Update README version from 2.6.0 to 2.7.0** — README still says 2.6.0 but VERSION file and GitHub release both say 2.7.0. Reviewers will notice the inconsistency.
- [ ] README has logo + badges header (build passing, tests, license, version)
- [ ] Description matches marketing copy: "Automated backup tool for developers — protects what Git ignores"
- [ ] Topics/tags set — **DONE:** 20 topics already configured (automation, backup, bash, cli, cloud-backup, database-backup, developer-tools, devops, disaster-recovery, encryption, linux, macos, mongodb, mysql, postgresql, rclone, sqlite, swiftui, version-control)
- [ ] License file present (Polyform Noncommercial) — **DONE**
- [ ] CONTRIBUTING.md exists — **DONE**
- [ ] Issues tab has a few labeled issues (good-first-issue, enhancement) for community engagement
- [ ] Releases page has v2.7.0 with release notes — **DONE** (published 2026-02-22)
- [ ] GitHub Discussions enabled — **DONE**

### Cold-Start Problem: 0 GitHub Stars

The repo currently has **0 stars**. This is a credibility issue for Reddit and Product Hunt, where users check star count before engaging.

**Mitigation strategy:**
- Launch on HN first — even a modest HN showing (page 2) can generate 10–50 stars
- Post to r/ClaudeAI same day as HN (Claude community is forgiving of new projects)
- Do NOT post to r/selfhosted or r/devops until you have at least 10–20 stars
- If HN doesn't generate traction, consider posting to r/ClaudeAI and Anthropic Discord first (they care about the tool, not the star count), then Reddit after stars accumulate
- Star the repo from any personal/alt accounts (small seed, better than zero)

### Website

- [ ] https://checkpoint.fluxcode.studio loads correctly
- [ ] Download/install instructions are prominent
- [ ] "Built by Fluxcode Studio" link in footer points to https://fluxcode.studio
- [ ] Open Graph image works (test: paste URL into Twitter, LinkedIn, Slack)
- [ ] Mobile responsive
- [ ] Contact form works

### Content Review

- [ ] **DONE: Command syntax fixed** — `checkpoint restore --from` corrected to `backup-restore file <path> --at` in 4 articles + website
- [ ] All 8 marketing articles reviewed for accuracy against v2.7.0 features
- [ ] All links in articles tested (GitHub, website, install command)
- [ ] **Run test suite and update count** — articles say "164 tests" (from v2.6.0). Run `./tests/run-tests.sh` and update all articles with the actual count
- [ ] Update version references from 2.6.0 to 2.7.0 in any articles that mention it
- [ ] **BLOCKER: Create terminal demo** — record asciinema session or GIF showing backup-now + search + history (see Section 11 for details). Embed in GitHub README.

### Accounts Ready

- [ ] Hacker News account exists with some karma (comment on posts for a few days first if new)
- [ ] Reddit accounts exist for target subreddits (lurk/comment first if new)
- [ ] Dev.to account created with profile filled out
- [ ] Product Hunt account created (save for later)
- [ ] Twitter/X profile mentions Fluxcode Studio
- [ ] Bluesky account claimed (https://bsky.app) — growing dev community, less noisy than Twitter
- [ ] Mastodon account on fosstodon.org — the largest FOSS-focused instance, ideal for open-source tool launches
- [ ] asciinema account created (https://asciinema.org) for hosting terminal recordings

---

## 4. Phase 1: Hacker News Launch (Day 1)

**Article:** `show-hn.md`
**Priority:** HIGHEST — this is the single highest-ROI action

### Why HN First

- Hacker News drives massive, concentrated traffic in 24 hours
- "Show HN" posts are judged on technical merit — Checkpoint is genuinely impressive
- HN audience = developers who will actually install and use it
- A front-page HN post generates secondary press coverage (bloggers, newsletters pick up HN hits)
- GitHub stars from HN are the social proof seed for everything else

### Posting Instructions

1. **When:** Tuesday, Wednesday, or Thursday — **6:00–8:00am ET** (HN front page turnover is lowest, your post has more time to gain traction)
2. **Title:** `Show HN: Checkpoint – Automated backups for everything Git ignores`
   - Alternatives if that feels too long:
     - `Show HN: Checkpoint – Backup daemon for .env files, databases, and credentials`
     - `Show HN: Checkpoint – I built a backup system after an AI ate my database`
3. **URL:** `https://github.com/fluxcodestudio/Checkpoint` (HN prefers GitHub links for Show HN)
4. **Text:** Post the content from `show-hn.md` as the first comment (the Show HN text field)

### Comment Strategy (CRITICAL)

HN success depends on being in the comments for the first 2–4 hours.

- [ ] Reply to every question within 15 minutes
- [ ] Be technical and honest — HN punishes marketing-speak
- [ ] When asked "why bash?", give the real answer (no dependencies, native OS tools, composes with everything)
- [ ] When asked about alternatives, acknowledge them honestly ("rsync + cron handles the file part, but Checkpoint adds database detection, encryption, versioning, and the macOS dashboard")
- [ ] Don't be defensive about the Polyform license — explain the reasoning
- [ ] Upvote quality questions (don't ask friends to upvote your post — HN detects vote rings)

### Revisions to `show-hn.md`

The existing article is strong. Minor updates needed:

- [ ] Update test count if it's changed from 164
- [ ] Add mention of v2.7.0 features (compression pipeline, cloud restore, mutual watchdog)
- [ ] Add "Built by Fluxcode Studio" at the bottom with link
- [ ] Consider adding a one-line mention of the Grammy angle in the closing ("I'm Jon, a Grammy-winning audio engineer who learned to code and built the tool I wished existed") — HN loves unusual background stories

### Expected Outcomes

| Scenario | What happens |
|----------|-------------|
| **Front page** (top 30) | 5,000–50,000 visits, 50–500 GitHub stars, secondary press coverage |
| **Page 2** | 500–2,000 visits, 10–50 stars |
| **Doesn't gain traction** | 50–200 visits. That's fine — HN has a "second chance pool" where moderators resurface posts that deserved more attention. You can also repost in 3–6 months with a different angle (e.g., lead with the Grammy story instead of the technical pitch) |

### HN Second-Chance Pool

HN moderators maintain a "second chance" system that re-surfaces posts that got buried by timing or bad luck but had quality content. You can't request this — it happens automatically. But knowing it exists means:
- Don't panic if the post sinks in the first hour
- Focus on writing quality comments that demonstrate depth
- Even if the post doesn't hit the front page, moderators may push it later

### After HN

- [ ] Screenshot the HN post for social proof (even if modest)
- [ ] Tweet the HN link: "Just posted Checkpoint on Hacker News — automated backups for everything Git ignores. Built this after an AI ate my database. [link]"
- [ ] If front page: write a "What I learned from our HN launch" Dev.to follow-up (great engagement)

---

## 5. Phase 2: Reddit Blitz (Days 2–7)

**Articles:** `reddit-commandline.md`, `reddit-devops.md`, `reddit-macos.md`, `reddit-selfhosted.md`

### Why Reddit Second (Not Same Day as HN)

- Reddit and HN have different peak times and attention cycles
- Posting on Reddit 1–3 days after HN means your GitHub star count is already seeded (social proof)
- Each subreddit is a different audience — the articles are already tailored

### Posting Schedule

**Space posts 1–2 days apart.** Posting all four on the same day looks spammy and splits your attention for comment replies.

| Day | Subreddit | Article | Best Time |
|-----|-----------|---------|-----------|
| Day 2 (Wed/Thu) | **r/ClaudeAI** (~527K members) | New post (see Section 7) | 9–11am ET |
| Day 3 (Thu/Fri) | **r/selfhosted** (~553K members) | `reddit-selfhosted.md` | 9–11am ET |
| Day 4 (Fri/Sat) | **r/commandline** | `reddit-commandline.md` | 9–11am ET |
| Day 5 (Sat/Sun) | **r/macos** | `reddit-macos.md` | 10am–12pm ET |
| Day 7 (Mon) | **r/devops** (~436K members) | `reddit-devops.md` | 8–10am ET |

> **Note on subscriber counts:** Reddit removed public member counts in September 2025, replacing them with "Visitors" and "Contributions" metrics. The numbers above are from third-party trackers and may be approximate. Check each subreddit directly before posting.

### Additional Subreddits (not yet written — use adapted versions)

| Subreddit | Angle | Adapt from |
|-----------|-------|-----------|
| **r/learnprogramming** (~4.2M members) | "I taught myself to code and built this" | Origin story + Checkpoint as example of what a beginner can build |
| **r/webdev** (~2.4M members) | .env protection, database backup | `reddit-commandline.md` (tweak angle) |
| **r/opensource** (~204K members) | Free tool, community contribution | `reddit-selfhosted.md` (tweak angle) |
| **r/sysadmin** (~900K+ members) | Backup automation, daemon reliability | `reddit-devops.md` (tweak angle) |
| **r/cursor** (~77K members) | Same AI file-destruction risk | `show-hn.md` (shorter, Cursor-focused) |
| **r/aider** | Same angle for Aider users | Adapt from r/ClaudeAI post |

### Reddit Rules (IMPORTANT)

- [ ] **Read each subreddit's rules before posting** — some require specific flair, formatting, or have self-promotion limits
- [ ] Don't crosspost — write native posts for each subreddit
- [ ] Be in the comments to reply (Reddit rewards engagement)
- [ ] If a post gets removed by mods, don't repost — message the mods politely
- [ ] Never ask for upvotes or share links in other channels saying "go upvote this"

### Revisions to Reddit Articles

All four articles are well-written and subreddit-appropriate. Updates needed:

- [ ] Update version to 2.7.0 and test count if changed
- [ ] Add mention of compression pipeline, cloud restore, mutual watchdog (new features since articles were written)
- [ ] Add "Built by Fluxcode Studio — https://fluxcode.studio" as a subtle footer
- [ ] In `reddit-macos.md`: mention the dashboard screenshot is on the website (link to it)
- [ ] In `reddit-selfhosted.md`: mention that backups are plain files in a predictable structure — no proprietary format, easy to verify and migrate

---

## 6. Phase 3: Dev.to Article (Days 3–5)

**Article:** `devto-article.md`
**Title:** "An AI Ate My Database. So I Built a Backup System."

### Why Dev.to

- Articles rank well on Google (long-tail SEO for months/years)
- Dev.to has a large, engaged developer audience
- Articles can be cross-posted to daily.dev (automated aggregation)
- The personal narrative format performs extremely well on Dev.to
- Evergreen content — keeps driving traffic long after posting

### Publishing Instructions

1. **When:** 2–3 days after HN launch (traffic from HN has peaked, now you need the next wave)
2. **Tags:** `opensource`, `devtools`, `backup`, `ai` (max 4 tags)
3. **Cover image:** Dashboard screenshot or a compelling visual (Canva or Figma, free)
4. **Canonical URL:** Leave blank (let Dev.to own the SEO)
5. **Series:** If you plan to write follow-ups ("Building a backup daemon in bash", "How I added encrypted cloud sync"), start a series

### Revisions to `devto-article.md`

The article is excellent — long, personal, detailed, with the right tone for Dev.to. Updates:

- [ ] Update version and test count
- [ ] Add new v2.7.0 features to the feature table (compression pipeline, cloud restore)
- [ ] Add a **"Built by Fluxcode Studio"** section at the bottom:
  ```
  ---

  *Checkpoint is built by [Fluxcode Studio](https://fluxcode.studio) — a small software
  studio building tools for developers. If you find Checkpoint useful,
  [star it on GitHub](https://github.com/fluxcodestudio/Checkpoint) — it helps others
  discover the project.*
  ```
- [ ] Add the Grammy angle somewhere natural (bio, or in the opening: "I'm a Grammy-winning audio engineer who taught himself to code. This is the first tool I built.")
- [ ] Consider adding a GIF or screenshot inline (Dev.to articles with images get significantly more engagement)

### Follow-Up Articles (Optional, write if the first does well)

| Article | Angle | When |
|---------|-------|------|
| "Building a Backup Daemon in Pure Bash" | Technical deep-dive into the architecture | Week 3 |
| "How I Added Encrypted Cloud Sync to My Bash Tool" | Technical: age + rclone integration | Week 5 |
| "What I Learned Launching on Hacker News" | Meta/startup — always performs well on Dev.to | Week 2 |
| "The Backup Blind Spot Every Developer Has" | Problem-awareness piece (drives installs) | Week 4 |

---

## 7. Phase 4: Claude/AI Ecosystem (Days 1–14)

### Why This Is Uniquely High-ROI for Checkpoint

Checkpoint was built because of Claude. The Claude ecosystem is the most targeted audience possible — these are people actively using AI coding assistants who face the exact problem Checkpoint solves.

### Channels

| Channel | Action | Priority |
|---------|--------|----------|
| **r/ClaudeAI** | Post: "Built a free backup tool after Claude ate my database — protects .env, databases, credentials" | High |
| **Anthropic Discord** (#showcase) | Share Checkpoint with install instructions | High |
| **Anthropic Discord** (#claude-code) | Help people, mention Checkpoint when relevant backup questions come up | Medium (ongoing) |
| **r/cursor** | Same angle — Cursor users have the same file-destruction risk | Medium |
| **r/aider** | Same angle for Aider users | Medium |
| **awesome-claude / awesome-mcp-servers** | Submit PR to add Checkpoint to relevant lists | Medium |

### r/ClaudeAI Post (Write New)

```markdown
Title: Built a free backup tool after Claude ate my database — backs up .env files,
databases, and everything Git ignores

I built Checkpoint after Claude destroyed my database. Not corrupted — deleted.
This happened multiple times across different projects. .env files overwritten,
SQLite databases gone, uncommitted work lost. Git only protects committed code —
everything in .gitignore was unprotected.

Checkpoint is a free, open-source backup daemon that runs in the background and
backs up your projects hourly — including everything .gitignore excludes:

- .env files, API keys, credentials
- SQLite, PostgreSQL, MySQL, MongoDB (proper dumps via pg_dump/sqlite3/mongodump)
- Docker container databases
- Untracked and uncommitted files

It runs via launchd (macOS) or systemd (Linux), includes a native SwiftUI menu bar
dashboard, encrypted cloud sync (age + rclone), and searchable version history.

Install:
git clone https://github.com/fluxcodestudio/Checkpoint.git
cd Checkpoint && ./bin/install-global.sh

Then run `backup-now` in any project directory. Free for personal use.

GitHub: https://github.com/fluxcodestudio/Checkpoint
Website: https://checkpoint.fluxcode.studio

Built by Fluxcode Studio. Happy to answer questions.
```

### Timing

- Post to r/ClaudeAI on Day 1 or 2 (same day as HN is fine — different audience)
- Post to Anthropic Discord on Day 1
- Post to r/cursor and r/aider in Week 2

---

## 8. Phase 5: GitHub Discovery (Days 1–14)

### GitHub Awesome Lists

Submit PRs to add Checkpoint to relevant curated lists. Each accepted PR = permanent discovery channel.

| List | Relevance | Link |
|------|-----------|------|
| **awesome-cli-apps** | CLI-first backup tool | Search GitHub for "awesome-cli-apps" |
| **awesome-macos** | Native macOS app with launchd integration | Search GitHub for "awesome-macos" |
| **awesome-shell** | Written in bash, CLI tool | Search GitHub for "awesome-shell" |
| **awesome-selfhosted** | Local-first backup system | Search GitHub for "awesome-selfhosted" |
| **awesome-sysadmin** | Backup/automation category | Search GitHub for "awesome-sysadmin" |
| **awesome-devops** | Backup tooling | Search GitHub for "awesome-devops" |
| **awesome-backup** (if exists) | Direct category match | Search GitHub |
| **awesome-sqlite** | SQLite backup support | Search GitHub |
| **awesome-postgres** | PostgreSQL backup support | Search GitHub |

### How to Submit

1. Fork the awesome-list repo
2. Add Checkpoint in the appropriate category with a one-line description
3. Submit a PR with a clear title: "Add Checkpoint — automated backup for developers"
4. Follow the list's contribution guidelines exactly
5. Be patient — some lists take weeks to review PRs

### GitHub Repo Optimization

- [ ] Add a compelling README header with logo and badges (build passing, tests, license, version)
- [ ] Add a GIF showing a backup running in terminal (asciinema or similar)
- [ ] Add dashboard screenshot in README
- [ ] Create 3–5 "good first issue" labels for community contributors
- [ ] Add GitHub Discussions or Issues templates
- [ ] Pin a "Welcome" issue or discussion for newcomers

---

## 9. Phase 6: Email Outreach (Weeks 2–4)

**Article:** `email-outreach.md` (3 templates: newsletter editors, bloggers, podcasts)

### Why Outreach Works for Checkpoint

- Dev tool newsletters actively look for new tools to feature
- The Grammy angle makes every pitch memorable
- Checkpoint is free — no "is this an ad?" friction
- A single newsletter feature can drive 500–5,000 visits

### Target Newsletters (Prioritized)

| Newsletter | Audience | Why | How to Pitch |
|------------|----------|-----|-------------|
| **TLDR** | 1M+ devs | Massive reach, features dev tools daily | No public submission form — editorially curated. Email editors directly or get picked up via HN/Reddit traction |
| **Bytes** (ui.dev) | 200K+ frontend devs | Casual tone, loves interesting tools | DM on Twitter or email via bytes.dev |
| **Console.dev** | Curated dev tools | Literally reviews dev tools | No public submission form — email via their contact page. Review their [selection criteria](https://console.dev/selection-criteria) first |
| **Changelog News** | 50K+ devs | Open source focus | https://changelog.com/news/submit (confirmed working — requires account) |
| **Hacker Newsletter** | 60K+ (HN digest) | If you hit HN front page, they may feature you anyway | Automatic if HN success |
| **DevOps Weekly** | 40K+ devops | Backup/automation focus | Email editor directly — search for current contact |
| **Awesome CLI** (newsletter) | CLI enthusiasts | Perfect audience match | Search for submission method |
| **macOS Weekly** / **iOS Dev Weekly** | macOS devs | SwiftUI dashboard angle | Search for submission |

### Outreach Cadence

- [ ] Week 2: Submit to Changelog News (only confirmed self-serve directory). Email TLDR and Console.dev editors directly
- [ ] Week 2–3: Send Template A (newsletter editors) to 5–10 newsletters
- [ ] Week 3: Send Template B (bloggers) to 3–5 dev tool bloggers
- [ ] Week 3–4: Send Template C (podcasts) to 3–5 shows (see FluxCode marketing plan for podcast list)
- [ ] Follow up once after 7 days if no response
- [ ] Track everything in a spreadsheet: Name, Date, Channel, Response, Status

### Revisions to `email-outreach.md`

The templates are strong. Updates:

- [ ] Add the Grammy angle to the opening line of every template (it's the hook that gets emails opened)
- [ ] Update version number and feature list
- [ ] Template A: Add "Checkpoint is getting traction — [X] GitHub stars, featured on [HN/Dev.to]" (add after those launches happen)
- [ ] Template C (podcast): Lead with "I'm a Grammy-winning engineer who taught himself to code in a year" — this is the strongest podcast hook
- [ ] Add "Built by Fluxcode Studio (https://fluxcode.studio)" to signature in all templates

---

## 10. Phase 7: Product Hunt (Week 4–6)

**Article:** `product-hunt.md`

### Why Wait for Product Hunt

- You get ONE launch on Product Hunt per product. Make it count.
- Launch AFTER you have social proof: GitHub stars, HN mention, newsletter features
- PH success depends on first-day momentum — you need people ready to upvote

### Pre-Launch Prep (2 weeks before)

- [ ] Build a "hunter" network: engage on PH for 2+ weeks before launch (comment, upvote others)
- [ ] Find a well-known "hunter" to submit your product (higher visibility than self-submitting)
- [ ] Prepare all PH assets: logo, screenshots (5–6), GIF/video, tagline, description, maker comment
- [ ] Email your newsletter/waitlist: "We're launching on Product Hunt on [date] — your support means everything"
- [ ] Prepare tweets for launch day

### Launch Day (Tuesday 12:01am PT)

1. **Product goes live at 12:01am PT** (that's when the PH day starts). You must **schedule the launch in advance** through PH's launch dashboard — you don't manually post at midnight. Submit and schedule it at least 24 hours before launch day.
2. **Immediately post your Maker Comment** (from `product-hunt.md`) — have it pre-written and ready to paste the moment the listing goes live
3. **Tweet:** "We just launched Checkpoint on @ProductHunt — automated backups for everything Git ignores. Built this after an AI ate my database. [PH link]"
4. **Email waitlist/newsletter:** Send at 8am ET with PH link and ask for support
5. **Be in PH comments ALL DAY** replying to every question
6. **Post on LinkedIn, Indie Hackers, Twitter** throughout the day

### Revisions to `product-hunt.md`

- [ ] Update tagline: consider "Backs up what Git ignores — .env files, databases, credentials" (more specific)
- [ ] Update feature list to include v2.7.0 features
- [ ] Add Grammy angle to Maker Comment opening: "Hi Product Hunt! I'm Jon — a Grammy-winning engineer who taught himself to code..."
- [ ] Update test count and version
- [ ] Add "Built by Fluxcode Studio" to links section
- [ ] Add screenshots/GIF descriptions (PH is visual — you need 5–6 images showing the dashboard, CLI, backup process)

### Expected Outcomes

| Scenario | What happens |
|----------|-------------|
| **Top 5 of the day** | 3,000–10,000 visits, 100–500 stars, secondary press |
| **Top 10** | 1,000–3,000 visits, 50–100 stars |
| **Below top 10** | 200–500 visits, still permanent PH listing |

---

## 11. Phase 8: Ongoing Growth (Month 2+)

### Sustained Channels (Low Effort, Ongoing)

| Channel | Effort | Action |
|---------|--------|--------|
| **Twitter/X** | 15 min/week | Share milestones (star count, features, user stories) |
| **Bluesky** | 5 min/week | Cross-post key Twitter content — dev community is growing fast and less noisy |
| **Mastodon (fosstodon.org)** | 5 min/week | Cross-post open-source milestones — fosstodon.org is the largest FOSS-focused instance and highly receptive to open-source dev tools |
| **GitHub** | 10 min/week | Respond to issues, engage contributors, release updates |
| **Dev.to** | 1 article/month | Technical deep-dives, build logs |
| **Anthropic Discord** | 10 min/week | Help Claude users, mention Checkpoint when relevant |
| **Reddit** | Only for milestones | Major version releases, 100-star milestone, etc. |

### Terminal Demo Video (High Impact, One-Time Effort)

Create a 60-second terminal recording showing Checkpoint in action. This single asset can be used across HN, Reddit, GitHub README, Dev.to, Twitter, and Product Hunt.

**What to record:**
1. `cd` into a project with a database
2. Run `backup-now` — show database auto-detection, file scanning, backup complete
3. Run `checkpoint search "API_KEY"` — show cross-backup search
4. Run `checkpoint history src/app.js --interactive` — show fzf browser
5. Quick flash of the macOS dashboard (screen recording, not terminal)

**Tools (free):**
- **asciinema** (https://asciinema.org) — records terminal sessions, renders as embeddable player or GIF
- **agg** (asciinema GIF generator) — converts asciinema recordings to GIFs for GitHub README
- **OBS** (https://obsproject.com) — for the macOS dashboard screen recording portion
- **Gifski** (Mac App Store, free) — convert screen recording to high-quality GIF

**Where to use it:**
- GitHub README (GIF embed — this alone can dramatically increase star conversion)
- HN Show HN text (link to asciinema recording)
- Dev.to article (inline GIF)
- Twitter thread (video attachment)
- Product Hunt (video/GIF in media gallery)

### Milestone-Based Posts

Post on Twitter + relevant channel when you hit:

- [ ] 50 GitHub stars
- [ ] 100 GitHub stars
- [ ] 500 GitHub stars
- [ ] First external contributor
- [ ] First user testimonial / "Checkpoint saved my project" story
- [ ] Windows version ships (when ready)
- [ ] Major version release (v3.0, etc.)

### Community Building

- [ ] Add a "Users" or "Who Uses Checkpoint" section to README when you get testimonials
- [ ] Create a `#checkpoint` channel in Fluxcode Studio Discord (when you have one)
- [ ] Encourage users to file issues and feature requests (engagement = ownership)
- [ ] Highlight contributors in release notes
- [ ] Consider a simple "Checkpoint saved my work" testimonial form on the website

### SEO (Low-Effort, Long-Term)

These take months to work but are permanent traffic sources:

- [ ] The Dev.to article will rank for "AI deleted my database", "backup for developers", etc.
- [ ] GitHub README ranks for "automated backup developer tool"
- [ ] Website ranks for "checkpoint backup developer" (already has good SEO structure)
- [ ] Consider writing a comparison page: "Checkpoint vs Time Machine vs rsync" (ranks for comparison searches)

---

## 12. Content Calendar — First 30 Days

### Week 0: Pre-Launch (Before Day 1)

| Task | Time |
|------|------|
| Complete pre-launch checklist (Section 3) | 2–3 hours |
| Review and revise all 8 marketing articles | 2 hours |
| Prepare screenshots/GIFs | 1 hour |
| Seed HN karma (comment on posts for a few days) | 15 min/day |

### Week 1: Launch Week

| Day | Action | Article | Time |
|-----|--------|---------|------|
| **Mon** | Pre-launch: final review of show-hn.md, test all links | — | 30 min |
| **Tue** | **LAUNCH: Post Show HN** (6–8am ET). Reply to all comments. | `show-hn.md` | 3–4 hours |
| **Tue** | Post to Anthropic Discord #showcase | — | 15 min |
| **Wed** | Post to r/ClaudeAI (~527K members — highest-signal audience) | New post (see Section 7) | 30 min + replies |
| **Thu** | Post to r/selfhosted | `reddit-selfhosted.md` | 30 min + replies |
| **Thu** | Publish Dev.to article | `devto-article.md` | 30 min |
| **Fri** | Post to r/commandline | `reddit-commandline.md` | 30 min + replies |
| **Fri** | Post to r/macos | `reddit-macos.md` | 30 min + replies |
| **Sat** | Rest / reply to comments across all channels | — | 30 min |
| **Sun** | Review Week 1 metrics. What worked? What didn't? | — | 30 min |

### Week 2: Expand

| Day | Action | Time |
|-----|--------|------|
| **Mon** | Post to r/devops | 30 min + replies |
| **Mon** | Submit to awesome-lists (3–5 PRs) | 1 hour |
| **Tue** | Submit to Changelog News. Email TLDR and Console.dev editors directly | 45 min |
| **Wed** | Send outreach emails (Template A) to 5 newsletters | 1 hour |
| **Thu** | Post to r/cursor or r/aider | 30 min |
| **Fri** | Tweet thread: "I built a backup system after an AI ate my database. Here's what I learned." | 45 min |
| **Sun** | Review Week 2 metrics | 30 min |

### Week 3: Outreach

| Day | Action | Time |
|-----|--------|------|
| **Mon** | Send outreach emails (Template B) to 3–5 bloggers | 45 min |
| **Tue** | Follow up on Week 2 newsletter submissions | 30 min |
| **Wed** | Post to r/opensource or r/webdev | 30 min |
| **Thu** | Send podcast pitches (Template C) to 3–5 shows | 1 hour |
| **Fri** | Write Dev.to follow-up article (optional) | 1 hour |
| **Sun** | Review Week 3 metrics | 30 min |

### Week 4–6: Product Hunt + Sustain

| Task | Time |
|------|------|
| Prep Product Hunt launch assets | 2 hours |
| Find a hunter or build PH engagement | 30 min/day for 2 weeks |
| **Launch on Product Hunt** (Tuesday) | 4–5 hours (launch day) |
| Continue replying to comments/issues on all channels | 15 min/day |
| LinkedIn article: origin story (repurposed from Dev.to) | 30 min |

---

## 13. Article Inventory & Status

### Ready to Publish (8 articles)

> **Command syntax fixed:** The `checkpoint restore --from "3 days ago"` syntax was incorrect in 4 articles. The actual CLI syntax is `backup-restore file <path> --at "TIME"`. This has been corrected in `show-hn.md`, `reddit-selfhosted.md`, `reddit-commandline.md`, and `devto-article.md`. Also fixed on `website/index.html`.

| File | Platform | Status | Revisions Still Needed |
|------|----------|--------|-----------------|
| `show-hn.md` | Hacker News | Command syntax fixed | Update version/features, add Grammy angle, add Fluxcode mention |
| `reddit-selfhosted.md` | r/selfhosted | Command syntax fixed | Update version/features, add Fluxcode footer |
| `reddit-commandline.md` | r/commandline | Command syntax fixed | Update version/features, add Fluxcode footer |
| `reddit-macos.md` | r/macos | Ready | Update version/features, add screenshot link, add Fluxcode footer |
| `reddit-devops.md` | r/devops | Ready | Update version/features, add Fluxcode footer |
| `devto-article.md` | Dev.to | Command syntax fixed | Update version/features, add Grammy angle, add Fluxcode CTA section |
| `product-hunt.md` | Product Hunt | Ready (hold) | Update tagline, version, features, add Grammy angle, prepare screenshots |
| `email-outreach.md` | Direct email | Ready | Add Grammy hook to opening, update version, add Fluxcode to signature |

### Needs Writing (8 new pieces)

| Piece | Platform | Priority | Est. Time |
|-------|----------|----------|-----------|
| r/ClaudeAI post | Reddit | **High** | 20 min (draft in Section 7) |
| Terminal demo recording | asciinema/GIF | **High** | 30 min (see Section 11 for details) |
| r/cursor post | Reddit | Medium | 15 min (adapt from r/ClaudeAI) |
| r/aider post | Reddit | Medium | 15 min (adapt from r/ClaudeAI) |
| Twitter/X origin story thread | Twitter | Medium | 45 min |
| Bluesky profile + launch post | Bluesky | Medium | 15 min (cross-post from Twitter) |
| fosstodon.org profile + launch post | Mastodon | Medium | 15 min (open-source angle) |
| LinkedIn article | LinkedIn | Low | 30 min (repurpose Dev.to) |

### Optional Follow-Up Articles

| Article | Platform | When | Priority |
|---------|----------|------|----------|
| "Building a Backup Daemon in Pure Bash" | Dev.to | Week 3+ | Low |
| "What I Learned Launching on Hacker News" | Dev.to | After HN launch | Low |
| "Checkpoint vs Time Machine vs rsync" | Website/Dev.to | Month 2 | Medium (SEO) |
| "The Backup Blind Spot Every Developer Has" | Dev.to | Month 2 | Medium |

---

## 14. Metrics & Goals

### 30-Day Goals

| Metric | Target | Tracking |
|--------|--------|----------|
| GitHub stars | 100+ | GitHub repo page |
| Website visits | 5,000+ | Vercel Analytics |
| GitHub clones/downloads | 200+ | GitHub Insights → Traffic |
| Dev.to article views | 2,000+ | Dev.to dashboard |
| HN upvotes | 50+ | Hacker News |
| Reddit upvotes (total across posts) | 200+ | Reddit |
| Newsletter features | 1–2 | Track outreach responses |
| GitHub issues opened by users | 5+ | GitHub Issues |

### 90-Day Goals

| Metric | Target | Tracking |
|--------|--------|----------|
| GitHub stars | 500+ | GitHub |
| Cumulative website visits | 15,000+ | Vercel Analytics |
| Product Hunt ranking | Top 10 of the day | Product Hunt |
| Podcast appearances | 1–2 | Outreach spreadsheet |
| Newsletter features | 3–5 | Outreach spreadsheet |
| User testimonials | 3+ | GitHub issues/discussions, Twitter mentions |
| Fluxcode Studio newsletter signups (from Checkpoint traffic) | 50+ | Sendy |

### Tracking Tools (Free)

| Tool | What |
|------|------|
| Vercel Analytics | Website traffic, referrers |
| GitHub Insights → Traffic | Clones, unique visitors, referring sites |
| GitHub Insights → Popular Content | Which pages get views |
| Dev.to Dashboard | Article views, reactions, comments |
| Twitter Analytics | Impressions, profile visits |
| Google Sheets | Outreach tracker, metrics log |

---

## 15. Anti-Patterns

| Don't | Why |
|-------|-----|
| Post all Reddit articles on the same day | Looks spammy, splits your comment attention, mods may flag |
| Launch on PH before you have social proof | You get one shot — wait until stars/mentions exist |
| Write "we" when it's just you | Be authentic — "I built this" is stronger than corporate "we" |
| Spam the same link in unrelated threads | Reddit/HN will flag your account. Only post in relevant contexts. |
| Buy GitHub stars or upvotes | Platforms detect this. It destroys credibility permanently. |
| Undersell the technical depth | 83 shell scripts, 164 tests, native macOS app — this is serious software. Say so. |
| Forget the Fluxcode Studio connection | Every post should mention "Built by Fluxcode Studio" — but as a footer, not the headline |
| Respond defensively to criticism | HN/Reddit will nitpick. Acknowledge valid points. Ignore trolls. |
| Write "AI is dangerous" or fearmongering | The story is "AI is powerful but has this specific risk, here's how I solved it" — constructive, not alarmist |
| Neglect GitHub after launch | Reply to every issue within 24 hours. A responsive maintainer = more stars. |
| Wait for everything to be perfect | The articles are written. The product is shipped. Launch. |

---

## 16. Fluxcode Studio Brand Integration

### Product-First, Brand-Second Strategy

Every piece of content leads with Checkpoint (the product people care about) and threads Fluxcode Studio (the brand) naturally.

### How to Thread the Brand

| Channel | Checkpoint (Primary) | Fluxcode Studio (Secondary) |
|---------|---------------------|---------------------------|
| **HN post** | Title + all content | "— Jon / Fluxcode Studio" in closing |
| **Reddit posts** | Title + all content | "Built by Fluxcode Studio — https://fluxcode.studio" as footer |
| **Dev.to article** | Title + all content | "Checkpoint is built by Fluxcode Studio" section at bottom |
| **Product Hunt** | Product name + listing | Maker profile links to Fluxcode Studio |
| **Email outreach** | Subject line + body | Signature: "Jon Rezin, Fluxcode Studio LLC" |
| **GitHub README** | Everything | "Maintained by Fluxcode Studio" with logo/link |
| **Website** | checkpoint.fluxcode.studio (subdomain = brand) | Footer link to fluxcode.studio |

### Why This Works

- People discover Checkpoint → install it → visit fluxcode.studio → see other products
- Every GitHub star, HN upvote, and newsletter mention builds Fluxcode Studio's reputation
- When you launch the next product, you're not starting from zero — "from the makers of Checkpoint" carries weight

### Brand Consistency Checklist

- [ ] Fluxcode Studio logo/name appears on: GitHub README, website footer, all marketing copy signatures
- [ ] All products use `*.fluxcode.studio` subdomains (already done)
- [ ] Twitter bio mentions both: "Building @Checkpoint + more at @FluxCodeStudio"
- [ ] LinkedIn shows Fluxcode Studio as current company

---

## Quick Start — If You Only Have 2 Hours

If you want to start immediately with minimum prep:

1. **Review `show-hn.md`** — update version number, test the install command (15 min)
2. **Post Show HN** on Tuesday/Wednesday 6–8am ET (15 min)
3. **Reply to every HN comment** for 2–4 hours
4. **Post to r/ClaudeAI** same day (15 min)
5. **Done.** Schedule Reddit posts for the rest of the week.

That's it. Everything else is amplification on top of those two highest-ROI actions.

---

*Last updated: February 26, 2026*
*Built by Fluxcode Studio — https://fluxcode.studio*
