# Phase 23: Encryption at Rest - Research

**Researched:** 2026-02-16
**Domain:** age encryption CLI integration with bash backup pipelines
**Confidence:** HIGH

<research_summary>
## Summary

Researched the `age` encryption tool for optional encryption of backup files before cloud sync. The tool is a perfect fit: zero configuration, full stdin/stdout streaming support, authenticated encryption (ChaCha20-Poly1305), and clean error codes for bash scripting.

The primary use case is encrypting files that land in cloud-synced folders (Dropbox/Google Drive). Local-only backups don't need encryption since they're under the user's physical control. The implementation should be opt-in per-project via config, encrypting the cloud copy while keeping local backups unencrypted for fast access.

Key architectural insight: age's streaming pipe support means we can chain `gzip | age` for databases without temp files. For the rsync-based file backup, we need a post-rsync encryption pass on the cloud destination copy. The existing three-tier destination system (cloud folder → rclone → local) provides natural encryption boundary — encrypt only what goes to non-local destinations.

**Primary recommendation:** Use age with key-based encryption (not passphrase). Store keypair at `~/.config/checkpoint/age-key.txt`. Encrypt cloud-destined files only. Compress-then-encrypt order. Add `.age` extension to encrypted files.
</research_summary>

<standard_stack>
## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| age | 1.2+ | File encryption/decryption | Zero-config, streaming, authenticated, no keyring |
| age-keygen | (bundled) | Key generation | Comes with age, one command |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| gzip | (system) | Compression | Already in pipeline, compress BEFORE encrypt |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| age | GPG | GPG more complex (keyring, config), overkill for backup encryption |
| age | openssl enc | openssl enc has NO authentication — can't detect corruption/tampering |
| age keypair | age passphrase (-p) | Passphrase requires TTY, can't automate; keypair works unattended |

**Installation:**
```bash
# macOS
brew install age

# Debian/Ubuntu 22.04+
apt install age

# Fedora 33+
dnf install age
```
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Encryption Scope: Cloud-Only

Local backups remain unencrypted for fast access and simple restore. Only files destined for cloud-synced folders get encrypted.

```
backup-now.sh pipeline:
                                    ┌─ LOCAL dest ──→ files/ (unencrypted)
  rsync → files/ ─── copy to ──────┤
                                    └─ CLOUD dest ──→ files/ (encrypted .age)

  sqlite3 → gzip ─── copy to ──────┌─ LOCAL dest ──→ databases/ (unencrypted .db.gz)
                                    └─ CLOUD dest ──→ databases/ (encrypted .db.gz.age)
```

### Key Management Pattern
```
~/.config/checkpoint/
├── age-key.txt          # Private key (chmod 600)
└── age-recipient.txt    # Public key (can share/backup safely)
```

### Config Integration
New config variables in `.checkpoint-config`:
```bash
ENCRYPTION_ENABLED=true          # Master toggle
ENCRYPTION_KEY_PATH="$HOME/.config/checkpoint/age-key.txt"
# Public key extracted automatically from private key via age-keygen -y
```

### Encrypt Pipeline Pattern (databases)
```bash
# Backup: compress then encrypt
gzip -c "$db_backup" | age -r "$AGE_RECIPIENT" -o "$CLOUD_DB_DIR/backup.db.gz.age"

# Restore: decrypt then decompress
age -d -i "$AGE_KEY_FILE" "$CLOUD_DB_DIR/backup.db.gz.age" | gunzip -c > "$restored.db"
```

### Encrypt Pipeline Pattern (files)
```bash
# After rsync to cloud FILES_DIR, encrypt each file in-place
find "$CLOUD_FILES_DIR" -type f ! -name "*.age" | while read -r f; do
    age -r "$AGE_RECIPIENT" "$f" -o "${f}.age"
    rm "$f"
done

# For archived versions (preserve timestamp suffix)
# filename.20260216_043343 → filename.20260216_043343.age
```

### Anti-Patterns to Avoid
- **Encrypt then compress:** Encrypted data has max entropy — gzip after age is useless bytes
- **Passphrase mode for automation:** Requires TTY interaction, can't run unattended
- **Encrypting local backups:** Adds overhead/complexity for no security gain on local drives
- **Hash-based dedup on encrypted files:** age output is nondeterministic (random nonce each time)
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File encryption | openssl enc wrapper | age CLI | openssl enc has no authentication, age has AEAD |
| Key generation | Random bytes + custom format | age-keygen | Proper key derivation, standard format |
| Streaming encryption | Read-encrypt-write loop | age stdin/stdout pipes | age handles 64KiB chunked auth internally |
| Key rotation | Custom re-encryption script | Simple: decrypt old → encrypt new | age has no built-in rotation, but the manual approach is fine for backup files |

**Key insight:** age was specifically designed for the "encrypt files in scripts" use case. Its pipe support and clean exit codes make bash integration trivial. Don't wrap openssl or attempt custom crypto.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Compress-Then-Encrypt Order
**What goes wrong:** Encrypting then compressing produces larger files than uncompressed originals
**Why it happens:** Encrypted data has maximum entropy, gzip can't compress it
**How to avoid:** Always `gzip | age` (compress first, encrypt second)
**Warning signs:** Encrypted .gz files are larger than original uncompressed files

### Pitfall 2: Nondeterministic Encrypted Output
**What goes wrong:** Same file encrypted twice produces different ciphertext, breaking rsync delta sync
**Why it happens:** age uses random nonce per encryption — by design for security
**How to avoid:** Don't rely on file hashes for change detection on encrypted files. rsync will always see encrypted files as "changed" even if source didn't change
**Warning signs:** Cloud sync transfers entire file every backup cycle instead of deltas
**Mitigation:** Only encrypt files that actually changed (check source, not encrypted output)

### Pitfall 3: Key Loss = Data Loss
**What goes wrong:** Lost private key means all encrypted backups are permanently unrecoverable
**Why it happens:** age has no key recovery, no master key, no backdoor
**How to avoid:** Store key backup in separate location (password manager, USB drive, printed). Warn user loudly during key generation
**Warning signs:** User has only one copy of key in ~/.config/checkpoint/

### Pitfall 4: Encrypted Files Break Verification
**What goes wrong:** Existing verification.sh can't check encrypted file contents
**Why it happens:** Can't run SQLite PRAGMA integrity_check on encrypted .db.gz.age
**How to avoid:** Verify BEFORE encryption (on local unencrypted copy), or decrypt-then-verify
**Warning signs:** Verification silently passes because it skips encrypted files

### Pitfall 5: File Extensions in Discovery
**What goes wrong:** backup-diff.sh and backup-discovery.sh don't recognize .age extension
**Why it happens:** Pattern matching looks for .db.gz, not .db.gz.age
**How to avoid:** Update discovery patterns to handle both encrypted and unencrypted files
**Warning signs:** `checkpoint history` shows no versions for encrypted files
</common_pitfalls>

<code_examples>
## Code Examples

### Key Generation
```bash
# Source: age GitHub README
mkdir -p ~/.config/checkpoint
age-keygen -o ~/.config/checkpoint/age-key.txt
chmod 600 ~/.config/checkpoint/age-key.txt

# Extract public key for config
AGE_RECIPIENT=$(age-keygen -y ~/.config/checkpoint/age-key.txt)
echo "ENCRYPTION_KEY=$AGE_RECIPIENT" >> .checkpoint-config
```

### Database Backup with Encryption
```bash
# Source: age pipe support documentation
# Compress then encrypt — no temp files needed
gzip -"${COMPRESSION_LEVEL:-6}" -c "$db_backup" \
    | age -r "$AGE_RECIPIENT" \
    -o "$CLOUD_DATABASE_DIR/${PROJECT_NAME}_${TIMESTAMP}.db.gz.age"
```

### Database Restore with Decryption
```bash
# Source: age pipe support documentation
age -d -i "$ENCRYPTION_KEY_PATH" "$encrypted_backup" \
    | gunzip -c > "$restored_db"
```

### File Encryption (post-rsync)
```bash
# Encrypt a single file, preserving original name with .age suffix
encrypt_file() {
    local src="$1" recipient="$2"
    if age -r "$recipient" "$src" -o "${src}.age"; then
        rm "$src"
        return 0
    else
        echo "Encryption failed for: $src" >&2
        return 1
    fi
}
```

### File Decryption
```bash
# Decrypt a single .age file, removing .age suffix
decrypt_file() {
    local src="$1" key_file="$2"
    local dest="${src%.age}"
    if age -d -i "$key_file" "$src" -o "$dest"; then
        return 0
    else
        echo "Decryption failed for: $src" >&2
        return 1
    fi
}
```

### Check if age is installed
```bash
check_age_installed() {
    if ! command -v age >/dev/null 2>&1; then
        echo "Error: 'age' encryption tool not installed." >&2
        echo "Install: brew install age (macOS) or apt install age (Linux)" >&2
        return 1
    fi
}
```
</code_examples>

<sota_updates>
## State of the Art (2025-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| GPG for file encryption | age for simple file encryption | 2019+ (mature 2022+) | Dramatically simpler, no keyring |
| openssl enc (unauthenticated) | age (AEAD per chunk) | 2019+ | Detects corruption, not just wrong key |
| Encrypt-then-compress | Compress-then-encrypt | Always true | age made this explicit in docs |

**New patterns:**
- age SSH key support: Can encrypt to existing `~/.ssh/id_ed25519.pub` — avoids generating separate keys
- age plugins: YubiKey support via `age-plugin-yubikey` (niche, not needed for v1)

**Not yet ready:**
- age post-quantum keys (`-pq` flag): Available but produces ~2000-char recipients, not practical yet
</sota_updates>

<implementation_scope>
## Implementation Scope for Checkpoint

### What to Encrypt
- Files copied to cloud-synced backup destinations (Dropbox/GDrive folders)
- Database backups (.db.gz) going to cloud destinations
- Archived file versions going to cloud destinations

### What NOT to Encrypt
- Local backup copies (PRIMARY_BACKUP_DIR when it's a local path)
- Local archived versions
- Config files, logs, metadata

### Integration Points in Codebase

| Component | File | What Changes |
|-----------|------|-------------|
| Config | lib/core/config.sh | Add ENCRYPTION_ENABLED, ENCRYPTION_KEY_PATH vars |
| Key setup | bin/checkpoint-diff.sh or new script | Key generation wizard |
| Database backup | bin/backup-now.sh ~line 673 | Chain `gzip \| age` for cloud dest |
| File backup | bin/backup-now.sh ~line 1055 | Post-rsync encrypt for cloud dest |
| Cloud sync | bin/backup-now.sh ~line 1557 | Files already encrypted before sync |
| Restore | lib/features/restore.sh | Decrypt before gunzip/copy |
| Discovery | lib/features/backup-discovery.sh | Handle .age extension in patterns |
| Verification | lib/features/verification.sh | Decrypt-then-verify flow |
| Status display | checkpoint status | Show encryption status |
| Diff command | bin/checkpoint-diff.sh | Handle encrypted files |

### File Naming Convention
```
Unencrypted:  project_20260216_120000.db.gz
Encrypted:    project_20260216_120000.db.gz.age

Unencrypted:  app.js.20260216_120000
Encrypted:    app.js.20260216_120000.age
```
</implementation_scope>

<open_questions>
## Open Questions

1. **rsync delta efficiency with encrypted files**
   - What we know: age output is nondeterministic, same input → different ciphertext
   - What's unclear: Will rsync/cloud sync re-upload entire files every time even if source unchanged?
   - Recommendation: Only encrypt files that actually changed in the current backup cycle (compare source modification times). Don't re-encrypt unchanged files.

2. **SSH key reuse vs dedicated age key**
   - What we know: age can encrypt to ~/.ssh/id_ed25519.pub natively
   - What's unclear: Whether users would prefer reusing SSH keys vs generating a dedicated backup key
   - Recommendation: Default to dedicated age key for clarity. Mention SSH key option in docs/help.

3. **Encrypted file cleanup/retention**
   - What we know: Current retention policy uses find with mtime
   - What's unclear: Whether encrypted files should have different retention than unencrypted
   - Recommendation: Same retention policy — encrypted files still have valid mtime for age-based cleanup.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- [age GitHub README](https://github.com/FiloSottile/age) — CLI usage, key generation, pipe support
- [age(1) man page](https://man.archlinux.org/man/extra/age/age.1.en) — Complete command reference
- Checkpoint codebase analysis — backup-now.sh, cloud-destinations.sh, restore.sh, verification.sh

### Secondary (MEDIUM confidence)
- [age encryption cookbook (sandipb.net)](https://blog.sandipb.net/2023/07/06/age-encryption-cookbook/) — Pipeline patterns verified against official docs
- [age vs GPG discussion (#432)](https://github.com/FiloSottile/age/discussions/432) — Comparison verified against both tools' docs
- [Switching from GPG to age (luke.hsiao.dev)](https://luke.hsiao.dev/blog/gpg-to-age/) — Migration patterns

### Tertiary (LOW confidence - needs validation)
- None — all findings verified against official sources
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: age encryption CLI
- Ecosystem: age, age-keygen, gzip pipeline integration
- Patterns: Compress-then-encrypt, cloud-only encryption, key management
- Pitfalls: Nondeterministic output, key loss, extension handling

**Confidence breakdown:**
- Standard stack: HIGH — age is the clear choice, verified against alternatives
- Architecture: HIGH — streaming pipe support confirmed, integration points mapped in codebase
- Pitfalls: HIGH — documented in official sources and community discussions
- Code examples: HIGH — from official age documentation and man pages

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days — age ecosystem is stable)
</metadata>

---

*Phase: 23-encryption-at-rest*
*Research completed: 2026-02-16*
*Ready for planning: yes*
