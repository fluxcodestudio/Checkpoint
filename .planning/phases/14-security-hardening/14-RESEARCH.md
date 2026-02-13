# Phase 14: Security Hardening - Research

**Researched:** 2026-02-13
**Domain:** Bash security — secure binary installation, credential management, integrity verification
**Confidence:** HIGH

<research_summary>
## Summary

Researched the security attack surface of the Checkpoint backup system, focusing on three areas: (1) unsafe `curl|bash` patterns for rclone installation, (2) database credential handling without keychain/secret-store integration, and (3) self-update mechanism with no checksum verification.

The codebase has **3 active `curl|bash` patterns** (all for rclone), one of which uses `sudo bash` — making it the highest-priority security issue. Database credentials are extracted from `.env` files and passed via shell variables, though MySQL already uses the secure `MYSQL_PWD` env var pattern (avoiding `ps aux` exposure). The self-update (`backup-update.sh`) downloads a tar.gz from GitHub and extracts it without any integrity check.

Existing infrastructure to build on: `lib/ops/file-ops.sh` already implements SHA256 hashing via `shasum -a 256` with cross-platform support and hash validation.

**Primary recommendation:** Replace `curl|bash` with download-verify-execute for rclone; add platform-aware credential provider (macOS Keychain, Linux secret-tool/pass, env var fallback); add SHA256 verification to self-update downloads.
</research_summary>

<standard_stack>
## Standard Stack

### Core (System Tools — No New Dependencies)
| Tool | Platform | Purpose | Why Standard |
|------|----------|---------|--------------|
| `shasum -a 256` | macOS | SHA256 checksums | Built-in, no install needed |
| `sha256sum` | Linux | SHA256 checksums | Part of coreutils |
| `security` CLI | macOS | Keychain access | Apple-provided, no install |
| `secret-tool` | Linux (GNOME) | GNOME Keyring access | Part of libsecret-tools |
| `pass` | Linux | GPG-based password store | Standard Unix password manager |
| `gpg` / `gpg2` | Both | GPG signature verification | Standard for binary verification |
| `curl` | Both | HTTP downloads | Already a dependency |

### Supporting (Already Present)
| Tool | Location | Purpose | Relevance |
|------|----------|---------|-----------|
| `shasum -a 256` | `lib/ops/file-ops.sh:215` | File hashing | Reuse for binary verification |
| `mktemp` | `bin/backup-update.sh:162` | Temp file creation | Secure temp for download-verify |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| macOS `security` CLI | `pass` on macOS | `security` is native, zero install |
| `gpg` signature verification | SHA256 only | GPG is stronger but adds complexity |
| secret-tool (GNOME) | kwallet-query (KDE) | secret-tool covers most Linux desktops |

**Installation:** No new dependencies required — all tools are platform-native.
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Module Structure
```
lib/
├── ops/
│   └── file-ops.sh          # Existing SHA256 — extend with verify_checksum()
├── security/
│   ├── credential-provider.sh  # NEW: platform credential abstraction
│   └── secure-download.sh      # NEW: download-verify-execute pattern
```

### Pattern 1: Download-Verify-Execute (for rclone)
**What:** Download binary to temp, verify checksum, then install — never pipe to bash
**When to use:** Any external binary installation (rclone, future tools)
**Example:**
```bash
# Source: Standard secure installation pattern
secure_install_rclone() {
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" RETURN

    local platform arch
    platform=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    [[ "$arch" == "x86_64" ]] && arch="amd64"
    [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && arch="arm64"

    local version="current"
    local base_url="https://downloads.rclone.org/${version}"
    local zip_file="rclone-${version}-${platform}-${arch}.zip"
    local checksums_file="SHA256SUMS"

    # Step 1: Download binary + checksums
    curl -fsSL "${base_url}/${zip_file}" -o "${temp_dir}/${zip_file}"
    curl -fsSL "${base_url}/${checksums_file}" -o "${temp_dir}/${checksums_file}"

    # Step 2: Verify checksum
    local expected_hash
    expected_hash=$(grep "${zip_file}" "${temp_dir}/${checksums_file}" | awk '{print $1}')
    local actual_hash
    actual_hash=$(shasum -a 256 "${temp_dir}/${zip_file}" | cut -d' ' -f1)

    if [[ "$expected_hash" != "$actual_hash" ]]; then
        echo "SECURITY: Checksum mismatch for rclone download" >&2
        return 1
    fi

    # Step 3: Extract and install
    unzip -q "${temp_dir}/${zip_file}" -d "${temp_dir}"
    # ... install binary
}
```

### Pattern 2: Platform Credential Provider
**What:** Abstraction over macOS Keychain, Linux secret-tool/pass, and env var fallback
**When to use:** Any stored credential (database passwords, API tokens)
**Example:**
```bash
# macOS Keychain
credential_store() {
    local service="$1" account="$2" password="$3"
    security add-generic-password \
        -s "$service" -a "$account" -w "$password" \
        -U  # Update if exists
}

credential_get() {
    local service="$1" account="$2"
    security find-generic-password \
        -s "$service" -a "$account" -w 2>/dev/null
}

# Linux secret-tool
credential_store() {
    local service="$1" account="$2" password="$3"
    echo -n "$password" | secret-tool store \
        --label="Checkpoint: $service" \
        service "$service" account "$account"
}

credential_get() {
    local service="$1" account="$2"
    secret-tool lookup service "$service" account "$account" 2>/dev/null
}

# Env var fallback (always available)
credential_get() {
    local service="$1" account="$2"
    local env_var="CHECKPOINT_${service}_${account}"
    env_var=$(echo "$env_var" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    echo "${!env_var:-}"
}
```

### Pattern 3: Self-Update with Integrity Check
**What:** Download release tar.gz, compute SHA256, verify against published hash
**When to use:** backup-update.sh
**Example:**
```bash
# Download and verify
curl -fsSL "$download_url" -o "$temp_dir/checkpoint.tar.gz"
local actual_hash
actual_hash=$(shasum -a 256 "$temp_dir/checkpoint.tar.gz" | cut -d' ' -f1)

# Verify against published checksum (from GitHub release assets)
local expected_hash
expected_hash=$(curl -fsSL "$checksums_url" | grep "checkpoint.tar.gz" | awk '{print $1}')

if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "SECURITY: Download integrity check failed" >&2
    exit 1
fi
```

### Anti-Patterns to Avoid
- **`curl URL | bash`:** Never pipe untrusted remote scripts to shell — MITM, truncation, mutation attacks
- **`curl URL | sudo bash`:** Even worse — arbitrary code with root privileges
- **Passwords in command-line args:** Visible via `ps aux` — use env vars or temp files with 0600 perms
- **Storing credentials in config files:** `.backup-config.sh` with passwords is readable by any process
- **Skipping verification because "it's just an update":** Supply chain attacks target update mechanisms
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| macOS credential storage | Custom encrypted file | `security` CLI (Keychain) | OS-level encryption, biometric unlock, ACL |
| Linux credential storage | Custom encrypted file | `secret-tool` / `pass` | Integrates with desktop session unlock |
| SHA256 computation | Custom hashing | `shasum -a 256` / `sha256sum` | Already in file-ops.sh, battle-tested |
| GPG verification | Custom signature parsing | `gpg --verify` | Handles key management, trust model |
| Secure temp files | Manual `rm` cleanup | `mktemp -d` + trap | Handles signals, ensures cleanup |
| Platform detection | Custom uname parsing | Existing `uname -s` patterns | Already used throughout codebase |

**Key insight:** Security is the one domain where "good enough" custom solutions are worse than using platform-native tools. macOS Keychain and Linux secret-tool provide hardware-backed, OS-integrated credential storage that no shell script can match. The existing `shasum` infrastructure in `file-ops.sh` already handles the cross-platform SHA256 problem.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Breaking Existing Installations on Upgrade
**What goes wrong:** Removing `curl|bash` install path breaks users who don't have the new secure installer yet
**Why it happens:** Existing `.backup-config.sh` files reference old install methods
**How to avoid:** Keep the old function signature (`install_rclone`) — replace internals only
**Warning signs:** Users report "rclone not found" after updating Checkpoint

### Pitfall 2: Keychain Access Prompts Blocking Daemon
**What goes wrong:** macOS Keychain shows UI prompt "allow access?" when daemon runs in background
**Why it happens:** LaunchAgent runs non-interactively, can't show Keychain dialog
**How to avoid:** Pre-authorize during `install.sh` (interactive), use `-T` flag to set ACL on keychain item
**Warning signs:** Daemon hangs silently, backups stop working

### Pitfall 3: rclone SHA256SUMS Format Changes
**What goes wrong:** Checksum file format differs between rclone versions
**Why it happens:** rclone SHA256SUMS is GPG clearsigned — raw `grep` may fail on signature block
**How to avoid:** Strip GPG signature before parsing, or verify GPG signature first then parse plaintext
**Warning signs:** Checksum extraction returns empty string, all installs fail

### Pitfall 4: Credential Provider Falls Through Silently
**What goes wrong:** No credential store available, backup proceeds without credentials, fails at database connect
**Why it happens:** Linux server with no desktop environment has no secret-tool or pass
**How to avoid:** Explicit fallback chain with clear error messages at each level; env var always works
**Warning signs:** "credential not found" errors only in CI/server environments

### Pitfall 5: Self-Update Checksum URL Depends on GitHub API
**What goes wrong:** GitHub API rate limit or format change breaks checksum download
**Why it happens:** Using dynamic API endpoint instead of predictable release asset URL
**How to avoid:** Use deterministic URL pattern: `releases/download/vX.Y.Z/SHA256SUMS`
**Warning signs:** Update fails intermittently, works fine for some users
</common_pitfalls>

<code_examples>
## Code Examples

Verified patterns from platform documentation and existing codebase:

### Cross-Platform SHA256 (Already in Codebase)
```bash
# Source: lib/ops/file-ops.sh:214-215
# Compute new hash (macOS uses shasum, not sha256sum)
file_hash=$(shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1) || return 1
```

### macOS Keychain Store/Retrieve
```bash
# Source: macOS `man security` — add-generic-password
# Store a credential
security add-generic-password \
    -s "checkpoint-db" \        # Service name
    -a "postgres-myapp" \       # Account name
    -w "secretpassword123" \    # Password
    -U                          # Update if exists

# Retrieve a credential (returns password to stdout)
security find-generic-password \
    -s "checkpoint-db" \
    -a "postgres-myapp" \
    -w                          # Output password only

# Pre-authorize an application (for daemon use)
security add-generic-password \
    -s "checkpoint-db" \
    -a "postgres-myapp" \
    -w "secretpassword123" \
    -T "/usr/local/bin/backup-daemon" \  # Allow this binary
    -U
```

### Linux secret-tool Store/Retrieve
```bash
# Source: `man secret-tool` — GNOME Keyring CLI
# Store
echo -n "secretpassword123" | secret-tool store \
    --label="Checkpoint: postgres-myapp" \
    service "checkpoint-db" \
    account "postgres-myapp"

# Retrieve
secret-tool lookup \
    service "checkpoint-db" \
    account "postgres-myapp"
```

### rclone Download URL Pattern
```bash
# Source: https://rclone.org/downloads/
# Binary downloads — predictable URL structure:
# https://downloads.rclone.org/v{VERSION}/rclone-v{VERSION}-{OS}-{ARCH}.zip
# Checksums (GPG clearsigned):
# https://downloads.rclone.org/v{VERSION}/SHA256SUMS

# Example for macOS ARM:
# https://downloads.rclone.org/v1.65.2/rclone-v1.65.2-osx-arm64.zip
# https://downloads.rclone.org/v1.65.2/SHA256SUMS

# "current" symlink always points to latest:
# https://downloads.rclone.org/current/rclone-current-osx-arm64.zip
# https://downloads.rclone.org/current/SHA256SUMS
```

### Secure Download-Verify Pattern
```bash
# Source: Standard security practice for bash binary installation
download_and_verify() {
    local url="$1" expected_hash="$2" output="$3"
    local temp_file
    temp_file=$(mktemp)

    # Download with fail-on-error
    if ! curl -fsSL "$url" -o "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi

    # Verify
    local actual_hash
    actual_hash=$(shasum -a 256 "$temp_file" | cut -d' ' -f1)
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        echo "SECURITY: Hash mismatch" >&2
        echo "  Expected: $expected_hash" >&2
        echo "  Got:      $actual_hash" >&2
        rm -f "$temp_file"
        return 1
    fi

    mv "$temp_file" "$output"
    return 0
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `curl URL \| bash` | Download → verify → execute | Always (just wasn't done) | Eliminates MITM, truncation, supply chain attacks |
| Passwords in config files | OS keychain / secret store | 2020+ (best practice) | Hardware-backed encryption, session-locked |
| No update verification | SHA256 checksums on releases | Standard practice | Prevents tampered updates |
| `MYSQL_PWD` env var | Same (already correct) | Current | Already using secure pattern |

**New tools/patterns to consider:**
- **macOS `security` CLI improvements:** Recent macOS versions support better ACL management for daemon access
- **`pass` with `passage`:** New age-encrypted alternative to GPG-based pass (lighter weight)
- **Sigstore/cosign:** Container-world signing coming to binary releases, but overkill for this project

**Deprecated/outdated:**
- **`curl|bash` for any installation:** Industry consensus considers this an anti-pattern
- **MD5 for integrity checks:** SHA256 minimum (already using SHA256 in codebase)
- **Storing passwords in `.env` without encryption:** Acceptable for dev but not production
</sota_updates>

<open_questions>
## Open Questions

1. **Should we verify rclone's GPG signature or just SHA256?**
   - What we know: rclone SHA256SUMS file is GPG clearsigned by the rclone team
   - What's unclear: Whether `gpg` is reliably available on target systems
   - Recommendation: SHA256 only for v1. GPG verification as optional enhancement later. SHA256 alone prevents MITM/corruption; GPG adds supply-chain protection but requires key management.

2. **Should credential provider be opt-in or opt-out?**
   - What we know: Keychain prompts can be disruptive; env vars always work
   - What's unclear: User preference for security vs. convenience
   - Recommendation: Opt-in during install (interactive prompt: "Store credentials in keychain?"). Default to env var fallback for non-interactive/daemon use.

3. **How to handle self-update checksums for a private repo?**
   - What we know: `backup-update.sh` already handles private repo gracefully (shows manual instructions)
   - What's unclear: How to publish checksums for private repo releases
   - Recommendation: Generate `SHA256SUMS` file as part of release process. Include it as release asset. If not available, warn but allow update (don't block on missing checksum for private repos).
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- **macOS `security` CLI:** `man security` on macOS — keychain operations verified
- **rclone downloads page:** https://rclone.org/downloads/ — URL patterns, SHA256SUMS availability
- **Codebase analysis:** 4 parallel agents analyzed full codebase (stack, architecture, conventions, concerns)
- **Existing SHA256:** `lib/ops/file-ops.sh:183-218` — cross-platform `shasum` pattern already implemented

### Secondary (MEDIUM confidence)
- **`secret-tool` man page:** Linux GNOME Keyring CLI — verified against libsecret docs
- **`pass` password store:** https://www.passwordstore.org/ — standard Unix credential manager
- **rclone SHA256SUMS format:** GPG clearsigned with rclone release key

### Tertiary (LOW confidence - needs validation)
- **LaunchAgent keychain ACL behavior:** Needs testing during implementation — daemon access to keychain items may require explicit `-T` authorization during setup
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Bash security patterns (download verification, credential management)
- Ecosystem: macOS Keychain, Linux secret-tool/pass, SHA256/GPG verification
- Patterns: Download-verify-execute, platform credential abstraction, self-update integrity
- Pitfalls: Daemon keychain access, SHA256SUMS format, fallback chains

**Confidence breakdown:**
- Standard stack: HIGH — all platform-native tools, no external dependencies
- Architecture: HIGH — patterns are well-established security best practices
- Pitfalls: HIGH — derived from codebase analysis + known bash security issues
- Code examples: HIGH — from man pages and existing codebase patterns

**Research date:** 2026-02-13
**Valid until:** 2026-03-15 (30 days — security tools are stable)
</metadata>

---

*Phase: 14-security-hardening*
*Research completed: 2026-02-13*
*Ready for planning: yes*
