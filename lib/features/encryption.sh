#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Encryption at Rest
# Optional encryption of backup files using age (modern, simple alternative to GPG)
# ==============================================================================
# @requires: core/config (for ENCRYPTION_ENABLED, ENCRYPTION_KEY_PATH)
# @provides: check_age_installed, encryption_enabled, get_age_recipient,
#            encrypt_file, decrypt_file, encrypt_stream, decrypt_stream,
#            generate_encryption_key, show_encryption_status
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_ENCRYPTION:-}" ] && return || readonly _CHECKPOINT_ENCRYPTION=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Set logging context
if type log_set_context &>/dev/null; then
    log_set_context "encryption"
fi

# Cached recipient (public key) to avoid repeated subprocess calls
_ENCRYPTION_RECIPIENT=""

# ==============================================================================
# DEPENDENCY CHECK
# ==============================================================================

# Check if age encryption tool is installed
# Returns: 0 if installed, 1 if not (with install instructions on stderr)
check_age_installed() {
    if command -v age &>/dev/null; then
        return 0
    fi

    echo "age encryption tool is not installed." >&2
    echo "" >&2
    echo "Install with:" >&2
    echo "  macOS:  brew install age" >&2
    echo "  Linux:  apt install age  (or your package manager)" >&2
    echo "" >&2
    echo "More info: https://github.com/FiloSottile/age" >&2
    return 1
}

# ==============================================================================
# STATUS CHECKS
# ==============================================================================

# Check if encryption is fully enabled and ready
# Returns: 0 if enabled + age installed + key exists, 1 otherwise
encryption_enabled() {
    if [ "${ENCRYPTION_ENABLED:-false}" != "true" ]; then
        return 1
    fi

    if ! command -v age &>/dev/null; then
        return 1
    fi

    local key_path="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"
    if [ ! -f "$key_path" ]; then
        return 1
    fi

    return 0
}

# Extract public key (recipient) from private key file
# Caches result to avoid repeated subprocess calls
# Output: age public key string
get_age_recipient() {
    # Return cached value if available
    if [ -n "$_ENCRYPTION_RECIPIENT" ]; then
        echo "$_ENCRYPTION_RECIPIENT"
        return 0
    fi

    local key_path="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"

    if [ ! -f "$key_path" ]; then
        echo "Error: Encryption key not found at $key_path" >&2
        return 1
    fi

    if ! command -v age-keygen &>/dev/null; then
        echo "Error: age-keygen not found. Install age first." >&2
        return 1
    fi

    _ENCRYPTION_RECIPIENT=$(age-keygen -y "$key_path" 2>/dev/null)

    if [ -z "$_ENCRYPTION_RECIPIENT" ]; then
        echo "Error: Failed to extract public key from $key_path" >&2
        return 1
    fi

    echo "$_ENCRYPTION_RECIPIENT"
}

# ==============================================================================
# ENCRYPT / DECRYPT FILES
# ==============================================================================

# Encrypt a file using age
# Args: $1 = source path, $2 = destination path (should end in .age)
# Returns: 0 on success, 1 on failure
encrypt_file() {
    local src="$1"
    local dest="$2"

    if [ ! -f "$src" ]; then
        echo "Error: Source file not found: $src" >&2
        return 1
    fi

    local recipient
    recipient=$(get_age_recipient) || return 1

    if ! age -r "$recipient" -o "$dest" "$src" 2>&1; then
        echo "Error: Failed to encrypt $src" >&2
        return 1
    fi

    return 0
}

# Decrypt a file using age
# Args: $1 = encrypted path (.age file), $2 = destination path
# Returns: 0 on success, 1 on failure
decrypt_file() {
    local src="$1"
    local dest="$2"

    if [ ! -f "$src" ]; then
        echo "Error: Encrypted file not found: $src" >&2
        return 1
    fi

    local key_path="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"

    if [ ! -f "$key_path" ]; then
        echo "Error: Encryption key not found at $key_path" >&2
        return 1
    fi

    if ! age -d -i "$key_path" -o "$dest" "$src" 2>&1; then
        echo "Error: Failed to decrypt $src" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# STREAM ENCRYPT / DECRYPT (for piping)
# ==============================================================================

# Encrypt stdin to stdout (for pipeline use)
# Usage: gzip | encrypt_stream > file.db.gz.age
encrypt_stream() {
    local recipient
    recipient=$(get_age_recipient) || return 1

    age -r "$recipient"
}

# Decrypt stdin to stdout (for pipeline use)
# Usage: decrypt_stream < file.db.gz.age | gunzip
decrypt_stream() {
    local key_path="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"

    if [ ! -f "$key_path" ]; then
        echo "Error: Encryption key not found at $key_path" >&2
        return 1
    fi

    age -d -i "$key_path"
}

# ==============================================================================
# KEY MANAGEMENT
# ==============================================================================

# Generate a new age encryption keypair
# Creates key at ENCRYPTION_KEY_PATH with chmod 600
# Args: $1 = "--force" to overwrite existing key (optional)
# Returns: 0 on success, 1 on failure
generate_encryption_key() {
    local force=false
    if [ "${1:-}" = "--force" ]; then
        force=true
    fi

    if ! check_age_installed; then
        return 1
    fi

    local key_path="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"

    # Check if key already exists
    if [ -f "$key_path" ] && [ "$force" != "true" ]; then
        echo "Error: Encryption key already exists at $key_path" >&2
        echo "Use --force to overwrite (WARNING: you will lose access to previously encrypted backups!)" >&2
        return 1
    fi

    # Create parent directory
    local key_dir
    key_dir=$(dirname "$key_path")
    mkdir -p "$key_dir"

    # Generate key
    if ! age-keygen -o "$key_path" 2>&1; then
        echo "Error: Failed to generate encryption key" >&2
        return 1
    fi

    # Restrict permissions
    chmod 600 "$key_path"

    # Extract and display public key
    local public_key
    public_key=$(age-keygen -y "$key_path" 2>/dev/null)

    echo ""
    echo "Encryption key generated successfully!"
    echo ""
    echo "  Key file:   $key_path"
    echo "  Public key: $public_key"
    echo ""
    echo "  ⚠️  IMPORTANT: Back up your key file!"
    echo "  Without it, encrypted backups cannot be restored."
    echo "  Copy to a secure location: cp \"$key_path\" /safe/backup/location/"
    echo ""
    echo "  To enable encryption, set in your config:"
    echo "    ENCRYPTION_ENABLED=true"
    echo ""

    # Clear cached recipient so it gets refreshed
    _ENCRYPTION_RECIPIENT=""

    return 0
}

# ==============================================================================
# STATUS DISPLAY
# ==============================================================================

# Display encryption status information
show_encryption_status() {
    local enabled="${ENCRYPTION_ENABLED:-false}"
    local key_path="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"
    local age_installed=false
    local key_exists=false

    if command -v age &>/dev/null; then
        age_installed=true
    fi

    if [ -f "$key_path" ]; then
        key_exists=true
    fi

    echo "Encryption Status"
    echo "─────────────────────────────"

    if [ "$enabled" = "true" ]; then
        echo "  Enabled:     ✅ Yes"
    else
        echo "  Enabled:     ❌ No"
    fi

    if [ "$age_installed" = "true" ]; then
        local age_version
        age_version=$(age --version 2>/dev/null || echo "unknown")
        echo "  age CLI:     ✅ Installed ($age_version)"
    else
        echo "  age CLI:     ❌ Not installed (brew install age)"
    fi

    if [ "$key_exists" = "true" ]; then
        echo "  Key file:    ✅ $key_path"
        # Show truncated public key
        if command -v age-keygen &>/dev/null; then
            local pubkey
            pubkey=$(age-keygen -y "$key_path" 2>/dev/null)
            if [ -n "$pubkey" ]; then
                local truncated="${pubkey:0:20}..."
                echo "  Public key:  $truncated"
            fi
        fi
    else
        echo "  Key file:    ❌ Not found ($key_path)"
    fi

    # Overall readiness
    echo ""
    if [ "$enabled" = "true" ] && [ "$age_installed" = "true" ] && [ "$key_exists" = "true" ]; then
        echo "  Status:      🔐 Ready — backups will be encrypted"
    elif [ "$enabled" = "true" ]; then
        echo "  Status:      ⚠️  Enabled but not ready"
        [ "$age_installed" != "true" ] && echo "               → Install age: brew install age"
        [ "$key_exists" != "true" ] && echo "               → Generate key: checkpoint encrypt setup"
    else
        echo "  Status:      🔓 Disabled — backups are unencrypted"
        echo "               → To enable: checkpoint encrypt setup"
    fi
}
