#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - Secure Download Library
# ==============================================================================
# @requires: none (standalone security module)
# @provides: compute_sha256, download_and_verify, download_with_checksums,
#            secure_install_rclone
# ==============================================================================

# Include guard
[ -n "${_CHECKPOINT_SECURE_DOWNLOAD:-}" ] && return || readonly _CHECKPOINT_SECURE_DOWNLOAD=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ==============================================================================
# SHA256 HASH COMPUTATION
# ==============================================================================

# Cross-platform SHA256 hash computation
# Args: $1 = file path
# Output: SHA256 hash (64 hex chars) to stdout
# Returns: 0 on success, 1 on failure
compute_sha256() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "compute_sha256: file not found: $file" >&2
        return 1
    fi

    local hash=""

    # Try shasum -a 256 first (macOS, most systems with perl)
    if command -v shasum &>/dev/null; then
        hash=$(shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1)
    # Fall back to sha256sum (Linux, GNU coreutils)
    elif command -v sha256sum &>/dev/null; then
        hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)
    else
        echo "compute_sha256: no SHA256 tool available (need shasum or sha256sum)" >&2
        return 1
    fi

    # Validate hash looks correct (64 hex chars)
    if [ ${#hash} -ne 64 ]; then
        echo "compute_sha256: failed to compute valid hash for $file" >&2
        return 1
    fi

    echo "$hash"
    return 0
}

# ==============================================================================
# DOWNLOAD WITH VERIFICATION
# ==============================================================================

# Download a file and verify its SHA256 checksum
# Args: $1 = url, $2 = expected_hash, $3 = output_path
# Returns: 0 on success (hash matches), 1 on failure (download error or hash mismatch)
download_and_verify() {
    local url="$1"
    local expected_hash="$2"
    local output_path="$3"

    # Create temp file for download
    local tmp_file
    tmp_file=$(mktemp 2>/dev/null) || {
        echo "download_and_verify: failed to create temp file" >&2
        return 1
    }

    # Ensure cleanup on failure
    trap "rm -f '$tmp_file'" RETURN

    # Download to temp file
    echo "Downloading: $url" >&2
    if ! curl -fsSL -o "$tmp_file" "$url"; then
        echo "download_and_verify: download failed: $url" >&2
        rm -f "$tmp_file"
        return 1
    fi

    # Compute SHA256 of downloaded file
    local actual_hash
    actual_hash=$(compute_sha256 "$tmp_file") || {
        rm -f "$tmp_file"
        return 1
    }

    # Compare hashes
    if [ "$actual_hash" != "$expected_hash" ]; then
        echo "SECURITY: Hash mismatch for download from $url" >&2
        echo "  Expected: $expected_hash" >&2
        echo "  Actual:   $actual_hash" >&2
        rm -f "$tmp_file"
        return 1
    fi

    # Hash matches - move to output path
    mv "$tmp_file" "$output_path" || {
        echo "download_and_verify: failed to move file to $output_path" >&2
        rm -f "$tmp_file"
        return 1
    }

    # Clear the trap since we successfully moved the file
    trap - RETURN

    echo "Verified: SHA256 hash matches" >&2
    return 0
}

# ==============================================================================
# DOWNLOAD WITH CHECKSUMS FILE
# ==============================================================================

# Download a file and verify using a separate checksums file
# Args: $1 = file_url, $2 = checksums_url, $3 = output_path, $4 = filename_in_checksums
# Returns: 0 on success, 1 on failure
download_with_checksums() {
    local file_url="$1"
    local checksums_url="$2"
    local output_path="$3"
    local filename_in_checksums="$4"

    # Create temp directory for working files
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null) || {
        echo "download_with_checksums: failed to create temp directory" >&2
        return 1
    }

    # Ensure cleanup on exit from this function
    trap "rm -rf '$tmp_dir'" RETURN

    local tmp_file="$tmp_dir/download"
    local tmp_checksums="$tmp_dir/checksums"

    # Download the target file
    echo "Downloading file: $file_url" >&2
    if ! curl -fsSL -o "$tmp_file" "$file_url"; then
        echo "download_with_checksums: failed to download file: $file_url" >&2
        return 1
    fi

    # Download the checksums file
    echo "Downloading checksums: $checksums_url" >&2
    if ! curl -fsSL -o "$tmp_checksums" "$checksums_url"; then
        echo "download_with_checksums: failed to download checksums: $checksums_url" >&2
        return 1
    fi

    # Strip GPG clearsigned wrapper if present
    # Removes -----BEGIN PGP SIGNED MESSAGE----- through Hash: line,
    # and -----BEGIN PGP SIGNATURE----- through -----END PGP SIGNATURE-----
    local clean_checksums="$tmp_dir/checksums_clean"
    sed -e '/^-----BEGIN PGP SIGNED MESSAGE-----$/,/^$/d' \
        -e '/^-----BEGIN PGP SIGNATURE-----$/,/^-----END PGP SIGNATURE-----$/d' \
        "$tmp_checksums" > "$clean_checksums"

    # Extract expected hash for our filename
    local expected_hash
    expected_hash=$(grep -F "$filename_in_checksums" "$clean_checksums" | head -1 | awk '{print $1}')

    if [ -z "$expected_hash" ]; then
        echo "download_with_checksums: hash not found for '$filename_in_checksums' in checksums file" >&2
        return 1
    fi

    # Validate the extracted hash looks like a SHA256 hash (64 hex chars)
    if [ ${#expected_hash} -ne 64 ]; then
        echo "download_with_checksums: invalid hash format for '$filename_in_checksums': $expected_hash" >&2
        return 1
    fi

    # Compute SHA256 of downloaded file
    local actual_hash
    actual_hash=$(compute_sha256 "$tmp_file") || return 1

    # Compare hashes
    if [ "$actual_hash" != "$expected_hash" ]; then
        echo "SECURITY: Hash mismatch for download from $file_url" >&2
        echo "  Expected: $expected_hash" >&2
        echo "  Actual:   $actual_hash" >&2
        return 1
    fi

    # Hash matches - move to output path
    mv "$tmp_file" "$output_path" || {
        echo "download_with_checksums: failed to move file to $output_path" >&2
        return 1
    }

    echo "Verified: SHA256 hash matches ($filename_in_checksums)" >&2
    return 0
}

# ==============================================================================
# SECURE RCLONE INSTALLATION
# ==============================================================================

# Securely install rclone by downloading the binary and verifying SHA256 checksum
# Replaces the insecure curl|bash installation pattern
# Returns: 0 on success, 1 on failure
secure_install_rclone() {
    # Detect platform
    local os_name
    os_name=$(uname -s)
    local platform
    case "$os_name" in
        Darwin) platform="osx" ;;
        Linux)  platform="linux" ;;
        *)
            echo "secure_install_rclone: unsupported platform: $os_name" >&2
            return 1
            ;;
    esac

    # Detect architecture
    local raw_arch
    raw_arch=$(uname -m)
    local arch
    case "$raw_arch" in
        x86_64)          arch="amd64" ;;
        aarch64|arm64)   arch="arm64" ;;
        *)
            echo "secure_install_rclone: unsupported architecture: $raw_arch" >&2
            return 1
            ;;
    esac

    # Construct download URLs using rclone's "current" symlink
    local zip_filename="rclone-current-${platform}-${arch}.zip"
    local binary_url="https://downloads.rclone.org/current/${zip_filename}"
    local checksums_url="https://downloads.rclone.org/current/SHA256SUMS"

    # Create temp directory for extraction
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null) || {
        echo "secure_install_rclone: failed to create temp directory" >&2
        return 1
    }

    # Ensure cleanup
    trap "rm -rf '$tmp_dir'" RETURN

    local zip_path="$tmp_dir/$zip_filename"

    echo "Installing rclone securely (download + SHA256 verification)..."
    echo "Platform: ${platform}-${arch}"

    # Download and verify the zip file
    if ! download_with_checksums "$binary_url" "$checksums_url" "$zip_path" "$zip_filename"; then
        echo "secure_install_rclone: download verification failed" >&2
        return 1
    fi

    # Extract zip to temp dir
    echo "Extracting..." >&2
    if ! unzip -q -o "$zip_path" -d "$tmp_dir"; then
        echo "secure_install_rclone: failed to extract zip" >&2
        return 1
    fi

    # Find rclone binary in extracted contents
    local rclone_binary
    rclone_binary=$(find "$tmp_dir" -name "rclone" -type f | head -1)

    if [ -z "$rclone_binary" ]; then
        echo "secure_install_rclone: rclone binary not found in archive" >&2
        return 1
    fi

    # Determine installation location
    local install_path=""

    if [ -d "/usr/local/bin" ] && command -v sudo &>/dev/null; then
        echo "" >&2
        echo "Install rclone to /usr/local/bin? (requires sudo)" >&2
        read -p "[Y/n]: " install_choice </dev/tty
        install_choice=${install_choice:-y}

        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            install_path="/usr/local/bin/rclone"
            sudo cp "$rclone_binary" "$install_path" || {
                echo "secure_install_rclone: sudo cp failed, falling back to user install" >&2
                install_path=""
            }
        fi
    fi

    # Fall back to user-local install
    if [ -z "$install_path" ]; then
        local user_bin="$HOME/.local/bin"
        mkdir -p "$user_bin" 2>/dev/null || {
            echo "secure_install_rclone: failed to create $user_bin" >&2
            return 1
        }
        install_path="$user_bin/rclone"
        cp "$rclone_binary" "$install_path" || {
            echo "secure_install_rclone: failed to copy rclone to $install_path" >&2
            return 1
        }

        # Warn about PATH if needed
        if ! echo "$PATH" | tr ':' '\n' | grep -q "^$user_bin$"; then
            echo "" >&2
            echo "NOTE: $user_bin is not in your PATH" >&2
            echo "Add to your shell profile:" >&2
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
            echo "" >&2
        fi
    fi

    # Make executable
    chmod +x "$install_path"

    # Verify installation
    if "$install_path" version &>/dev/null; then
        echo "rclone installed successfully: $install_path" >&2
        "$install_path" version | head -1 >&2
        return 0
    else
        echo "secure_install_rclone: installation verification failed" >&2
        return 1
    fi
}
