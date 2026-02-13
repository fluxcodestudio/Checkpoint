#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Credential Provider
# ==============================================================================
# Platform-aware credential storage abstraction.
# Supports macOS Keychain, Linux secret-tool (GNOME Keyring), pass (GPG),
# and environment variable fallback.
#
# @requires: none (standalone security module)
# @provides: credential_store, credential_get, credential_delete, credential_backend_name
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_CREDENTIAL_PROVIDER:-}" ] && return || readonly _CHECKPOINT_CREDENTIAL_PROVIDER=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ==============================================================================
# BACKEND DETECTION
# ==============================================================================

# Detect the best available credential storage backend.
# Caches result in _CHECKPOINT_CRED_BACKEND for the session.
# Returns: backend name on stdout ("keychain", "secret-tool", "pass", "env")
_detect_credential_backend() {
    # Return cached result if available
    if [[ -n "${_CHECKPOINT_CRED_BACKEND:-}" ]]; then
        echo "$_CHECKPOINT_CRED_BACKEND"
        return 0
    fi

    local platform
    platform="$(uname -s)"

    case "$platform" in
        Darwin)
            if command -v security &>/dev/null; then
                _CHECKPOINT_CRED_BACKEND="keychain"
            else
                _CHECKPOINT_CRED_BACKEND="env"
            fi
            ;;
        Linux)
            if command -v secret-tool &>/dev/null; then
                _CHECKPOINT_CRED_BACKEND="secret-tool"
            elif command -v pass &>/dev/null; then
                _CHECKPOINT_CRED_BACKEND="pass"
            else
                _CHECKPOINT_CRED_BACKEND="env"
            fi
            ;;
        *)
            _CHECKPOINT_CRED_BACKEND="env"
            ;;
    esac

    echo "$_CHECKPOINT_CRED_BACKEND"
    return 0
}

# ==============================================================================
# HELPER: ENV VAR NAME CONSTRUCTION
# ==============================================================================

# Convert service/account to an environment variable name.
# Uppercases, replaces hyphens with underscores.
# Args: $1=service, $2=account
# Output: variable name (e.g., "CHECKPOINT_CHECKPOINT_DB_POSTGRES_MYAPP")
_credential_env_var_name() {
    local service="$1"
    local account="$2"

    # Uppercase and replace hyphens with underscores
    local svc="${service^^}"
    svc="${svc//-/_}"
    local acct="${account^^}"
    acct="${acct//-/_}"

    echo "CHECKPOINT_${svc}_${acct}"
}

# ==============================================================================
# CREDENTIAL STORE
# ==============================================================================

# Store a credential in the best available backend.
# Args: $1=service (e.g., "checkpoint-db"), $2=account (e.g., "postgres-myapp"), $3=password
# Returns: 0 on success, 1 on failure
credential_store() {
    local service="$1"
    local account="$2"
    local password="$3"

    if [[ -z "$service" || -z "$account" || -z "$password" ]]; then
        echo "credential_store: usage: credential_store <service> <account> <password>" >&2
        return 1
    fi

    local backend
    backend="$(_detect_credential_backend)"

    case "$backend" in
        keychain)
            if security add-generic-password -s "$service" -a "$account" -w "$password" -U 2>/dev/null; then
                return 0
            else
                echo "credential_store: warning: macOS Keychain store failed, falling back to env var instructions" >&2
                _credential_store_env_instructions "$service" "$account" "$password"
                return 1
            fi
            ;;
        secret-tool)
            if echo -n "$password" | secret-tool store --label="Checkpoint: $account" service "$service" account "$account" 2>/dev/null; then
                return 0
            else
                echo "credential_store: warning: secret-tool store failed, falling back to env var instructions" >&2
                _credential_store_env_instructions "$service" "$account" "$password"
                return 1
            fi
            ;;
        pass)
            if echo -n "$password" | pass insert -f "checkpoint/${service}/${account}" 2>/dev/null; then
                return 0
            else
                echo "credential_store: warning: pass store failed, falling back to env var instructions" >&2
                _credential_store_env_instructions "$service" "$account" "$password"
                return 1
            fi
            ;;
        env)
            _credential_store_env_instructions "$service" "$account" "$password"
            return 0
            ;;
    esac
}

# Print instructions for setting an environment variable credential.
# Args: $1=service, $2=account, $3=password
_credential_store_env_instructions() {
    local service="$1"
    local account="$2"
    local password="$3"

    local var_name
    var_name="$(_credential_env_var_name "$service" "$account")"

    echo "Set environment variable to store this credential:"
    echo "  export ${var_name}=\"${password}\""
    echo ""
    echo "Add to your shell profile (~/.bashrc, ~/.zshrc) or .env file to persist."
}

# ==============================================================================
# CREDENTIAL GET
# ==============================================================================

# Retrieve a credential from the best available backend.
# Args: $1=service, $2=account
# Output: password to stdout (empty string if not found)
# Returns: 0 if found, 1 if not found
credential_get() {
    local service="$1"
    local account="$2"

    if [[ -z "$service" || -z "$account" ]]; then
        echo "credential_get: usage: credential_get <service> <account>" >&2
        return 1
    fi

    local backend
    backend="$(_detect_credential_backend)"
    local result=""

    case "$backend" in
        keychain)
            result="$(security find-generic-password -s "$service" -a "$account" -w 2>/dev/null)" || true
            if [[ -z "$result" ]]; then
                # Keychain lookup failed or empty — try env var fallback
                result="$(_credential_get_env "$service" "$account")"
            fi
            ;;
        secret-tool)
            result="$(secret-tool lookup service "$service" account "$account" 2>/dev/null)" || true
            if [[ -z "$result" ]]; then
                result="$(_credential_get_env "$service" "$account")"
            fi
            ;;
        pass)
            result="$(pass show "checkpoint/${service}/${account}" 2>/dev/null)" || true
            if [[ -z "$result" ]]; then
                result="$(_credential_get_env "$service" "$account")"
            fi
            ;;
        env)
            result="$(_credential_get_env "$service" "$account")"
            ;;
    esac

    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi

    return 1
}

# Retrieve credential from environment variable.
# Args: $1=service, $2=account
# Output: value to stdout (empty if not set)
_credential_get_env() {
    local service="$1"
    local account="$2"

    local var_name
    var_name="$(_credential_env_var_name "$service" "$account")"

    # Use indirect variable expansion
    echo "${!var_name:-}"
}

# ==============================================================================
# CREDENTIAL DELETE
# ==============================================================================

# Remove a credential from the backend.
# Args: $1=service, $2=account
# Returns: 0 always (best-effort deletion)
credential_delete() {
    local service="$1"
    local account="$2"

    if [[ -z "$service" || -z "$account" ]]; then
        echo "credential_delete: usage: credential_delete <service> <account>" >&2
        return 1
    fi

    local backend
    backend="$(_detect_credential_backend)"

    case "$backend" in
        keychain)
            security delete-generic-password -s "$service" -a "$account" 2>/dev/null || true
            ;;
        secret-tool)
            secret-tool clear service "$service" account "$account" 2>/dev/null || true
            ;;
        pass)
            pass rm -f "checkpoint/${service}/${account}" 2>/dev/null || true
            ;;
        env)
            local var_name
            var_name="$(_credential_env_var_name "$service" "$account")"
            echo "To remove this credential, unset the environment variable:"
            echo "  unset ${var_name}"
            ;;
    esac

    return 0
}

# ==============================================================================
# BACKEND NAME
# ==============================================================================

# Return human-readable name of the current credential backend for UI display.
# Output: backend name string
credential_backend_name() {
    local backend
    backend="$(_detect_credential_backend)"

    case "$backend" in
        keychain)      echo "macOS Keychain" ;;
        secret-tool)   echo "GNOME Keyring (secret-tool)" ;;
        pass)          echo "pass (GPG)" ;;
        env)           echo "Environment variables" ;;
        *)             echo "Unknown" ;;
    esac
}
