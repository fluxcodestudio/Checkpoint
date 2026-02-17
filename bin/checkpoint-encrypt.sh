#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Encryption Management CLI
# Manage backup encryption: key generation, status, round-trip testing
# Usage: checkpoint encrypt [setup|status|test] [OPTIONS]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Bootstrap: resolve symlinks, set SCRIPT_DIR/LIB_DIR/PROJECT_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Source foundation library (loads core, ops, ui, platform, features)
source "$LIB_DIR/backup-lib.sh"

# Source encryption library
source "$LIB_DIR/features/encryption.sh"

# ==============================================================================
# HELP TEXT
# ==============================================================================

show_help() {
    cat <<EOF
Checkpoint - Encryption Management

USAGE
    checkpoint encrypt                   Show encryption status (default)
    checkpoint encrypt setup             Generate encryption key
    checkpoint encrypt setup --force     Regenerate key (WARNING: loses access to old backups!)
    checkpoint encrypt status            Show encryption status
    checkpoint encrypt test              Test encrypt/decrypt round-trip

OPTIONS
    --help, -h          Show this help

EXAMPLES
    checkpoint encrypt setup             Generate a new age encryption key
    checkpoint encrypt status            Check if encryption is configured
    checkpoint encrypt test              Verify encryption works end-to-end

SETUP GUIDE
    1. checkpoint encrypt setup          Generate key
    2. Back up your key file!            Copy to secure location
    3. Set ENCRYPTION_ENABLED=true       In your .backup-config.sh
    4. checkpoint encrypt test           Verify it works

EOF
}

# ==============================================================================
# MODES
# ==============================================================================

# Setup: generate encryption key
mode_setup() {
    local force_flag=""
    if [ "${1:-}" = "--force" ]; then
        force_flag="--force"
    fi

    generate_encryption_key $force_flag
}

# Status: show encryption state
mode_status() {
    # Load project config if available
    if [ -f "$PWD/.backup-config.sh" ]; then
        source "$PWD/.backup-config.sh" 2>/dev/null || true
    fi

    show_encryption_status
}

# Test: encrypt/decrypt round-trip verification
mode_test() {
    echo "Encryption Round-Trip Test"
    echo "─────────────────────────────"

    # Check prerequisites
    if ! check_age_installed; then
        echo ""
        echo "❌ Test failed: age not installed"
        return 1
    fi

    local key_path="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"
    if [ ! -f "$key_path" ]; then
        echo ""
        echo "❌ Test failed: No encryption key found at $key_path"
        echo "   Run: checkpoint encrypt setup"
        return 1
    fi

    # Create temp files
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local original="$tmp_dir/test-original.txt"
    local encrypted="$tmp_dir/test-encrypted.age"
    local decrypted="$tmp_dir/test-decrypted.txt"

    # Generate test content
    echo "Checkpoint encryption test - $(date)" > "$original"
    echo "If you can read this, decryption worked!" >> "$original"

    echo "  1. Creating test file..."
    echo "     Content: $(wc -c < "$original") bytes"

    echo "  2. Encrypting..."
    if ! encrypt_file "$original" "$encrypted"; then
        echo ""
        echo "❌ Test failed: Encryption error"
        rm -rf "$tmp_dir"
        return 1
    fi
    echo "     Encrypted: $(wc -c < "$encrypted") bytes"

    echo "  3. Decrypting..."
    if ! decrypt_file "$encrypted" "$decrypted"; then
        echo ""
        echo "❌ Test failed: Decryption error"
        rm -rf "$tmp_dir"
        return 1
    fi
    echo "     Decrypted: $(wc -c < "$decrypted") bytes"

    echo "  4. Comparing..."
    if diff -q "$original" "$decrypted" &>/dev/null; then
        echo ""
        echo "✅ Round-trip test passed! Encryption is working correctly."
    else
        echo ""
        echo "❌ Test failed: Decrypted content doesn't match original"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Cleanup
    rm -rf "$tmp_dir"
    return 0
}

# ==============================================================================
# ARGUMENT PARSING & DISPATCH
# ==============================================================================

MODE="${1:-status}"

case "$MODE" in
    setup)
        shift
        mode_setup "${1:-}"
        ;;
    status)
        mode_status
        ;;
    test)
        mode_test
        ;;
    --help|-h)
        show_help
        ;;
    *)
        echo "Unknown mode: $MODE" >&2
        echo "Use --help for usage information" >&2
        exit 1
        ;;
esac
