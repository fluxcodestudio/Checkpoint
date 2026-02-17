# Phase 24: Docker Volume Backup - Research

**Researched:** 2026-02-16
**Domain:** Docker volume export/import for bash-based backup tool
**Confidence:** HIGH

<research_summary>
## Summary

Researched Docker volume backup strategies for integration into Checkpoint's bash-based backup pipeline. The standard approach uses temporary `busybox` containers to tar-export named volumes, with container stopping for data consistency. Docker has NO built-in volume backup commands — the `docker run --rm -v vol:/data busybox tar czf` pattern is the universal standard across all tools and documentation.

Key finding: `docker compose config --volumes` is the most reliable method to discover named volumes from compose files, handling all format variations and variable interpolation automatically. Bind mounts should be skipped (already covered by regular file backup). Database volumes MUST have their containers stopped before backup to avoid corruption.

**Primary recommendation:** Auto-detect compose files, use `docker compose config --volumes` for discovery, stop containers using each volume, tar-export with busybox, optionally encrypt with existing age pipeline, restore via `docker volume create` + tar-extract.
</research_summary>

<standard_stack>
## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| docker CLI | 24.x+ | Volume operations, container management | Required — volumes only accessible via Docker |
| busybox | latest (~1.5MB) | Lightweight container for tar operations | Universal, tiny, available everywhere |
| docker compose v2 | 2.x | Compose file parsing, volume discovery | `docker compose config --volumes` is most reliable parser |
| tar + gzip | system | Archive creation/extraction | Built into busybox, standard compression |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| age | 1.x | Encryption at rest | When ENCRYPTION_ENABLED=true (existing Checkpoint infra) |
| jq | 1.6+ | JSON parsing for volume inspect | Optional — for volume metadata extraction |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| busybox tar | alpine tar | Alpine 5MB vs busybox 1.5MB, no benefit |
| docker compose config | yq YAML parser | yq doesn't resolve variables or merge files |
| grep/awk/sed for YAML | docker compose config | YAML is indentation-sensitive, regex is brittle |
| Full volume drivers | Local driver only | Cloud drivers (s3, etc.) are rare in dev, often unmaintained |
| docker cp | docker run tar | docker cp doesn't support volumes directly, only container paths |

**No installation required** — all tools are either system-provided or already in Checkpoint (age, jq).
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Module Structure
```
lib/features/docker-volumes.sh    # Core library (detection, backup, restore)
bin/checkpoint-docker-volumes.sh   # CLI entry point
```

### Pattern 1: Temporary Container Export
**What:** Use ephemeral busybox container to tar-export volume data
**When to use:** All volume backups
**Example:**
```bash
# Source: Docker official docs + community standard
docker run --rm \
  -v "$volume_name:/data:ro" \
  -v "$backup_dir:/backup" \
  busybox tar czf "/backup/${volume_name}.tar.gz" -C /data .
```
**Critical:** The `-C /data .` flag is mandatory. Without it, tar creates nested directory structures that break restore.

### Pattern 2: Container-Aware Stop/Start
**What:** Stop all containers using a volume before backup, restart after
**When to use:** Always — especially for database volumes
**Example:**
```bash
# Find containers using a specific volume
docker ps --filter "volume=$volume_name" --format "{{.Names}}"

# Stop → backup → restart
docker stop "$container"
# ... backup ...
docker start "$container"
```

### Pattern 3: Compose File Discovery
**What:** Check all 4 compose file name variants in priority order
**When to use:** Detecting whether project uses Docker
**Example:**
```bash
# Precedence per Docker docs (2025):
# compose.yaml > compose.yml > docker-compose.yaml > docker-compose.yml
for filename in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
  if [[ -f "$project_dir/$filename" ]]; then
    COMPOSE_FILE="$filename"
    break
  fi
done
```

### Pattern 4: Volume Discovery via Compose Config
**What:** Use `docker compose config --volumes` for reliable volume name extraction
**When to use:** When compose file detected
**Example:**
```bash
# Returns volume names, one per line, with project prefix resolved
cd "$project_dir"
docker compose config --volumes 2>/dev/null
```

### Pattern 5: Checkpoint Integration Pattern
**What:** Follow existing feature integration pattern (encryption, storage-monitor)
**When to use:** Adding new lib module
**Example:**
```bash
# Include guard (mandatory for all lib modules)
[ -n "${_CHECKPOINT_DOCKER_VOLUMES:-}" ] && return || readonly _CHECKPOINT_DOCKER_VOLUMES=1

_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
log_set_context "docker-volumes"
```

### Anti-Patterns to Avoid
- **Parsing YAML with grep/awk/sed:** YAML is indentation-sensitive; use `docker compose config` instead
- **Backing up anonymous volumes:** No stable identity, easily lost with `docker volume prune`
- **Backing up bind mounts:** Already on host filesystem, covered by regular file backup
- **Skipping container stop:** Database files mid-transaction = corrupted backup
- **Creating tar with absolute paths:** `tar czf x.tar.gz /data` creates nested dirs; always use `-C /data .`
- **Accessing /var/lib/docker/volumes/ directly:** Doesn't work on macOS Docker Desktop (volumes live inside Linux VM)
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML parsing | grep/awk/sed on docker-compose.yml | `docker compose config --volumes` | YAML is indentation-sensitive, variables need interpolation, multiple files may merge |
| Volume export | Custom file copy from mountpoint | `docker run --rm busybox tar` | Mountpoints not accessible on macOS Docker Desktop; tar preserves permissions |
| Compose version detection | Parse `version:` key from file | `docker compose version` CLI check | Version key is ignored by Compose v2; CLI check is authoritative |
| Container-volume mapping | Parse compose file for service volumes | `docker ps --filter "volume=NAME"` | Runtime state is authoritative; compose file may not reflect running containers |
| Volume metadata | Manual tracking | `docker volume inspect` | Returns driver, mountpoint, labels, creation date |

**Key insight:** Docker CLI commands provide reliable, cross-platform abstractions for everything. Parsing files or accessing filesystem directly is fragile and platform-dependent. Let Docker do the work.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Database Corruption from Hot Backup
**What goes wrong:** Backing up a database volume while PostgreSQL/MySQL is running produces corrupted, non-restorable data
**Why it happens:** Database files are written incrementally across multiple files; mid-transaction state is inconsistent
**How to avoid:** Always stop containers using the volume before tar export. Use `docker ps --filter "volume=NAME"` to find all containers.
**Warning signs:** Restore works but database reports corruption on startup; missing recent data

### Pitfall 2: Tar Directory Structure Mismatch
**What goes wrong:** Restored volume has nested directories (e.g., `/data/data/actual-files`) instead of files at root
**Why it happens:** `tar czf backup.tar.gz /data` embeds the absolute path; restore extracts into `/target/data/...`
**How to avoid:** Always use `-C /data .` to make paths relative: `tar czf backup.tar.gz -C /data .`
**Warning signs:** Application can't find its data after restore; files exist but in wrong subdirectory

### Pitfall 3: Volume Name Prefix Confusion
**What goes wrong:** Volume named `pgdata` in compose file is actually `myproject_pgdata` at runtime
**Why it happens:** Docker Compose prefixes volume names with the project directory name
**How to avoid:** Use `docker compose config --volumes` which returns the actual prefixed names, or use `docker volume ls` to verify
**Warning signs:** `docker volume inspect pgdata` returns "not found" but `docker volume inspect myproject_pgdata` works

### Pitfall 4: macOS Docker Desktop Volume Access
**What goes wrong:** Trying to read `/var/lib/docker/volumes/` on macOS fails or returns nothing
**Why it happens:** On Docker Desktop, volumes live inside a Linux VM, not on the host filesystem
**How to avoid:** Always use `docker run` to access volume data; never attempt direct filesystem access
**Warning signs:** Empty or nonexistent paths; permissions errors on macOS

### Pitfall 5: Compose v1 vs v2 CLI Command
**What goes wrong:** `docker-compose` (hyphenated) command not found, or different behavior than expected
**Why it happens:** Compose v1 (Python, `docker-compose`) reached EOL July 2023; v2 (Go, `docker compose` with space) is current
**How to avoid:** Check for v2 first (`docker compose version`), fall back to v1 (`docker-compose version`), warn if v1 only
**Warning signs:** Different container naming conventions (underscores vs hyphens); command not found errors

### Pitfall 6: Large Volume Backup Timeout
**What goes wrong:** Backup of 50GB+ volume takes 30+ minutes, may timeout or appear hung
**Why it happens:** Full tar+gzip of large data volumes is I/O intensive
**How to avoid:** Log progress, set appropriate timeouts, consider size threshold warnings
**Warning signs:** Backup process consuming heavy I/O; no progress output for extended periods
</common_pitfalls>

<code_examples>
## Code Examples

### Volume Export (Standard Pattern)
```bash
# Source: Docker official docs, verified across offen/docker-volume-backup, BretFisher/docker-vackup
backup_single_volume() {
    local volume_name="$1"
    local backup_file="$2"

    docker run --rm \
        -v "${volume_name}:/data:ro" \
        -v "$(dirname "$backup_file"):/backup" \
        busybox tar czf "/backup/$(basename "$backup_file")" -C /data .
}
```

### Volume Restore (Standard Pattern)
```bash
# Source: Docker official docs + community verified
restore_single_volume() {
    local volume_name="$1"
    local backup_file="$2"

    # Create volume if it doesn't exist
    if ! docker volume inspect "$volume_name" &>/dev/null; then
        docker volume create "$volume_name"
    fi

    # Clear existing data to prevent mixed state
    docker run --rm -v "${volume_name}:/data" busybox sh -c "rm -rf /data/* /data/.[!.]* /data/..?*" 2>/dev/null

    # Extract backup
    docker run --rm \
        -v "${volume_name}:/data" \
        -v "$(dirname "$backup_file"):/backup:ro" \
        busybox tar xzf "/backup/$(basename "$backup_file")" -C /data
}
```

### Container Stop/Start Around Backup
```bash
# Source: offen/docker-volume-backup pattern, Docker community standard
backup_volume_safely() {
    local volume_name="$1"
    local backup_file="$2"
    local stopped_containers=()

    # Find and stop containers using this volume
    local containers
    containers=$(docker ps --filter "volume=${volume_name}" --format "{{.Names}}" 2>/dev/null)
    if [[ -n "$containers" ]]; then
        while IFS= read -r container; do
            docker stop "$container" >/dev/null 2>&1 && stopped_containers+=("$container")
        done <<< "$containers"
    fi

    # Backup
    backup_single_volume "$volume_name" "$backup_file"
    local result=$?

    # Restart stopped containers
    for container in "${stopped_containers[@]}"; do
        docker start "$container" >/dev/null 2>&1
    done

    return $result
}
```

### Compose File Detection
```bash
# Source: Docker Compose docs - file naming precedence
detect_compose_file() {
    local project_dir="$1"
    local compose_files=(compose.yaml compose.yml docker-compose.yaml docker-compose.yml)

    for filename in "${compose_files[@]}"; do
        if [[ -f "$project_dir/$filename" ]]; then
            echo "$filename"
            return 0
        fi
    done
    return 1
}
```

### Volume Discovery
```bash
# Source: docker compose config docs
discover_project_volumes() {
    local project_dir="$1"

    # Check Docker availability
    if ! command -v docker &>/dev/null || ! docker info &>/dev/null 2>&1; then
        return 1
    fi

    # Check Compose availability
    local compose_cmd
    if docker compose version &>/dev/null 2>&1; then
        compose_cmd="docker compose"
    elif command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
    else
        return 1
    fi

    # Get volumes from compose config
    cd "$project_dir" && $compose_cmd config --volumes 2>/dev/null
}
```

### Docker Availability Check
```bash
# Source: Checkpoint database-detector.sh existing pattern
is_docker_available() {
    command -v docker &>/dev/null && timeout 5 docker info &>/dev/null 2>&1
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `docker-compose` (Python, hyphenated) | `docker compose` (Go, space) | Compose v1 EOL July 2023 | Must detect and prefer v2 CLI |
| `version:` key required in compose files | `version:` key ignored | Compose Specification 2021+ | Don't parse version key; all formats work |
| `docker-compose.yml` filename | `compose.yaml` preferred | Docker docs 2023+ | Check all 4 variants in priority order |
| Manual YAML parsing for volumes | `docker compose config --volumes` | Compose v2 | Reliable, handles interpolation + merges |
| cannon-style full backups | Incremental with Restic | 2024+ | For 50GB+ volumes, incremental is better |

**New tools/patterns to consider:**
- **offen/docker-volume-backup (2.4k stars):** Most popular open-source solution. Uses label-based container stop/restart. Good reference implementation.
- **BretFisher/docker-vackup (800+ stars):** Clean bash reference. Two modes: tar archives or container images.
- **Docker Desktop Volumes Backup & Share Extension:** Official Docker Inc. GUI solution. Creates gzip tarballs. Limited to 10GB for registry push.

**Deprecated/outdated:**
- **docker-compose v1 (Python):** EOL July 2023. Still works but no updates. Warn users.
- **jareware/docker-volume-backup:** Archived. Superseded by offen fork.
- **Direct /var/lib/docker/volumes/ access:** Never reliable on Docker Desktop; use Docker CLI always.
</sota_updates>

<open_questions>
## Open Questions

1. **Should Checkpoint auto-detect vs require explicit config?**
   - What we know: `docker compose config --volumes` reliably discovers volumes; detection can be automatic
   - What's unclear: Users may not want ALL volumes backed up (some may be cache/temp)
   - Recommendation: Auto-detect volumes from compose file, but allow `DOCKER_VOLUMES_EXCLUDE_PATTERN` regex and explicit `DOCKER_VOLUMES_TO_BACKUP` list in config. Default: backup all named volumes.

2. **Should backup happen during regular backup pipeline or separately?**
   - What we know: Database backup is already integrated into backup-now.sh pipeline
   - What's unclear: Docker volume backup involves stopping containers (potentially disruptive)
   - Recommendation: Integrate into backup-now.sh pipeline after database backup, following the same pattern. Container stop/restart is brief (~seconds). Add `--skip-docker-volumes` flag for users who want to skip.

3. **How to handle volumes for projects where Docker is not running?**
   - What we know: Docker Desktop may not be running during scheduled backups
   - What's unclear: Should Checkpoint try to start Docker?
   - Recommendation: Skip gracefully with log message. Don't auto-start Docker (too disruptive). Existing `is_docker_running()` pattern in database-detector.sh handles this.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Docker official docs: Volumes, Compose file reference, `docker compose config`
- Docker official docs: Backup and restore, volume drivers
- offen/docker-volume-backup GitHub (2.4k stars): Architecture patterns, label-based container management
- BretFisher/docker-vackup GitHub (800+ stars): Clean bash implementation reference

### Secondary (MEDIUM confidence)
- Docker blog: "Back Up and Share Docker Volumes with This Extension" — verified against CLI behavior
- Community patterns (augmentedmind.de, eastondev.com) — verified against official docs
- Docker forums: Best practices threads — cross-referenced with official docs

### Tertiary (LOW confidence - needs validation)
- None — all critical findings verified against Docker official documentation
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Docker CLI, Docker Compose v2
- Ecosystem: busybox containers, tar/gzip, age encryption (existing)
- Patterns: Volume export/import, container stop/start, compose file parsing
- Pitfalls: Database corruption, tar paths, volume naming, cross-platform

**Confidence breakdown:**
- Standard stack: HIGH - Docker CLI is the only option; well-documented
- Architecture: HIGH - Universal pattern across all tools (temporary container + tar)
- Pitfalls: HIGH - Documented in Docker forums, verified in official docs
- Code examples: HIGH - Based on Docker official docs and established open-source tools

**Codebase integration:**
- Module pattern: Follow encryption.sh include guard + log_set_context
- Config pattern: Follow ENCRYPTION_* naming → DOCKER_VOLUME_*
- CLI pattern: Follow checkpoint-encrypt.sh → checkpoint-docker-volumes.sh
- Pipeline: Insert after database backup in backup-now.sh
- Existing Docker detection: database-detector.sh has `is_docker_running()`, `detect_docker_databases()`

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days - Docker ecosystem stable)
</metadata>

---

*Phase: 24-docker-volume-backup*
*Research completed: 2026-02-16*
*Ready for planning: yes*
