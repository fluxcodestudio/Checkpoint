#!/usr/bin/env bash
# ==============================================================================
# Checkpoint - GitHub Authentication Helpers
# Check, setup, and report GitHub authentication status
# ==============================================================================
# @requires: core/output (for color functions)
# @provides: check_github_auth, setup_github_auth, get_github_push_status
# ==============================================================================

# Include guard
[ -n "$_CHECKPOINT_GITHUB_AUTH" ] && return || readonly _CHECKPOINT_GITHUB_AUTH=1

# Lib directory (set by loader, fallback for standalone sourcing)
_CHECKPOINT_LIB_DIR="${_CHECKPOINT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ==============================================================================
# GITHUB AUTHENTICATION HELPERS
# ==============================================================================

# Check if GitHub authentication is configured
# Returns: 0 if authenticated, 1 if not
check_github_auth() {
    # Method 1: Check gh CLI
    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null; then
            return 0
        fi
    fi

    # Method 2: Check if git push would work (test with dry-run concept)
    # We check if credentials are cached
    if git config --get credential.helper &>/dev/null; then
        return 0
    fi

    # Method 3: Check for SSH keys that might work
    if [ -f "$HOME/.ssh/id_rsa" ] || [ -f "$HOME/.ssh/id_ed25519" ]; then
        # Check if remote uses SSH
        local remote_url
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ "$remote_url" == git@* ]]; then
            return 0
        fi
    fi

    return 1
}

# Setup GitHub authentication interactively
# Returns: 0 on success, 1 on failure
setup_github_auth() {
    echo ""
    echo "━━━ GitHub Authentication Setup ━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if command -v gh &>/dev/null; then
        echo "GitHub CLI (gh) detected. This is the easiest way to authenticate."
        echo ""
        echo "Running: gh auth login"
        echo ""

        if gh auth login; then
            echo ""
            echo "✅ GitHub authentication successful!"
            return 0
        else
            echo ""
            echo "❌ GitHub authentication failed or was cancelled."
            return 1
        fi
    else
        echo "GitHub CLI (gh) not found."
        echo ""
        echo "Install it with:"
        echo "  brew install gh"
        echo ""
        echo "Then run:"
        echo "  gh auth login"
        echo ""
        return 1
    fi
}

# Get GitHub push status summary
get_github_push_status() {
    local remote="${1:-origin}"
    local branch="${2:-$(git branch --show-current 2>/dev/null)}"

    if ! git remote get-url "$remote" &>/dev/null; then
        echo "no_remote"
        return
    fi

    if ! check_github_auth; then
        echo "not_authenticated"
        return
    fi

    local ahead
    ahead=$(git rev-list --count "$remote/$branch..HEAD" 2>/dev/null || echo "0")

    if [ "$ahead" -gt 0 ]; then
        echo "ahead_$ahead"
    else
        echo "up_to_date"
    fi
}
