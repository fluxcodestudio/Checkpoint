#!/bin/bash
# ==============================================================================
# Checkpoint - Real Backup Execution Tests
# ==============================================================================
# Actually runs backup-now.sh against real test projects and verifies output.
# This is the most important test file — it catches what unit tests miss.
# ==============================================================================

source "$(dirname "$0")/../test-framework.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT
export PATH="$PROJECT_ROOT/bin:$PATH"

# ==============================================================================
# HELPER: Create a project with config and run backup
# ==============================================================================

_create_configured_project() {
    local name="${1:-test-proj}"
    local proj="$TEST_TEMP_DIR/$name"
    mkdir -p "$proj"

    # Git init
    git -C "$proj" init -q 2>/dev/null
    git -C "$proj" config user.email "test@test.com" 2>/dev/null
    git -C "$proj" config user.name "Test" 2>/dev/null

    # Sample files
    echo "# README" > "$proj/README.md"
    echo "console.log('hello');" > "$proj/app.js"
    mkdir -p "$proj/src"
    echo "export default 42;" > "$proj/src/index.js"
    echo "body { color: red; }" > "$proj/src/style.css"

    # Initial commit
    git -C "$proj" add . 2>/dev/null
    git -C "$proj" commit -q -m "init" 2>/dev/null

    # Write config
    cat > "$proj/.backup-config.sh" << EOF
#!/usr/bin/env bash
PROJECT_NAME="$name"
PROJECT_DIR="$proj"
BACKUP_DIR="$proj/backups"
DB_TYPE="none"
DB_PATH=""
BACKUP_INTERVAL=3600
BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=true
BACKUP_LOCAL_NOTES=true
BACKUP_LOCAL_DATABASES=true
BACKUP_AI_ARTIFACTS=true
BACKUP_SYMLINK_TARGETS=true
STATE_DIR="$TEST_TEMP_DIR/state"
CLOUD_FOLDER_ENABLED=false
CLOUD_ENABLED=false
NOTIFICATIONS_ENABLED=false
TIERED_RETENTION_ENABLED=false
STORAGE_CHECK_ENABLED=false
EOF

    echo "$proj"
}

_run_backup() {
    local proj="$1"
    local extra_args="${2:-}"
    # Disable storage check — test systems may have full disks
    STORAGE_CHECK_ENABLED=false STORAGE_CRITICAL_PERCENT=100 \
        bash "$PROJECT_ROOT/bin/backup-now.sh" --force --quiet $extra_args 2>&1 <<< "" || true
}

# ==============================================================================
# TEST SUITE 1: REAL BACKUP EXECUTION
# ==============================================================================

test_suite "Real Backup Execution"

test_case "backup-now.sh runs successfully on a real project"
_proj=$(_create_configured_project "real-backup-1")
cd "$_proj"
_output=$(_run_backup "$_proj")
_exit=$?
if [[ -d "$_proj/backups/files" ]]; then
    test_pass
else
    test_fail "Backup dir not created. Output: $_output"
fi

test_case "All tracked git files appear in backup"
_missing=0
for f in README.md app.js src/index.js src/style.css; do
    if [[ ! -f "$_proj/backups/files/$f" ]]; then
        _missing=$((_missing + 1))
        echo "    Missing: $f"
    fi
done
if [[ $_missing -eq 0 ]]; then
    test_pass
else
    test_fail "$_missing files missing from backup"
fi

test_case "Backup files match source content"
_mismatched=0
for f in README.md app.js src/index.js src/style.css; do
    if [[ -f "$_proj/backups/files/$f" ]]; then
        if ! diff -q "$_proj/$f" "$_proj/backups/files/$f" >/dev/null 2>&1; then
            _mismatched=$((_mismatched + 1))
            echo "    Mismatch: $f"
        fi
    fi
done
if [[ $_mismatched -eq 0 ]]; then
    test_pass
else
    test_fail "$_mismatched files have different content"
fi

test_case "Incremental backup detects modified files"
echo "// updated" >> "$_proj/app.js"
git -C "$_proj" add app.js 2>/dev/null
cd "$_proj"
_run_backup "$_proj" >/dev/null 2>&1
if diff -q "$_proj/app.js" "$_proj/backups/files/app.js" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Modified file not updated in backup"
fi

test_case "Archived versions created for modified files"
_archived_count=$(find "$_proj/backups/archived" -name "app.js.*" 2>/dev/null | wc -l | tr -d ' ')
if [[ $_archived_count -ge 1 ]]; then
    test_pass
else
    test_fail "No archived version found (count: $_archived_count)"
fi

# ==============================================================================
# TEST SUITE 2: SPECIAL FILES
# ==============================================================================

test_suite "Special File Backup"

test_case ".env files are backed up"
_proj2=$(_create_configured_project "env-test")
echo "SECRET=abc123" > "$_proj2/.env"
echo "DB_HOST=localhost" > "$_proj2/.env.local"
cd "$_proj2"
_run_backup "$_proj2" >/dev/null 2>&1
if [[ -f "$_proj2/backups/files/.env" ]] && [[ -f "$_proj2/backups/files/.env.local" ]]; then
    test_pass
else
    test_fail ".env files missing from backup"
fi

test_case ".env.example not double-backed-up by critical files scan"
# .env.example in git SHOULD be backed up as a tracked file.
# But the .env critical files scanner should NOT add it again (it's excluded).
# This test verifies the exclusion filter works — create an UNTRACKED .env.example
# that's also gitignored. It should NOT appear in backup.
_proj_envex=$(_create_configured_project "envex-test")
echo ".env.example" >> "$_proj_envex/.gitignore"
git -C "$_proj_envex" add .gitignore 2>/dev/null
git -C "$_proj_envex" commit -q -m "gitignore" 2>/dev/null
echo "EXAMPLE=true" > "$_proj_envex/.env.example"
cd "$_proj_envex"
_run_backup "$_proj_envex" >/dev/null 2>&1
if [[ ! -f "$_proj_envex/backups/files/.env.example" ]]; then
    test_pass
else
    test_fail ".env.example (gitignored) should not be backed up by critical files scan"
fi

test_case "Credential files are backed up"
_proj3=$(_create_configured_project "cred-test")
echo "-----BEGIN RSA PRIVATE KEY-----" > "$_proj3/server.pem"
echo '{"type":"service_account"}' > "$_proj3/credentials.json"
cd "$_proj3"
_run_backup "$_proj3" >/dev/null 2>&1
if [[ -f "$_proj3/backups/files/server.pem" ]] && [[ -f "$_proj3/backups/files/credentials.json" ]]; then
    test_pass
else
    test_fail "Credential files missing from backup"
fi

test_case "terraform.tfstate is backed up"
_proj_tf=$(_create_configured_project "tf-test")
echo '{"version":4,"terraform_version":"1.5.0"}' > "$_proj_tf/terraform.tfstate"
echo '{"version":3}' > "$_proj_tf/terraform.tfstate.backup"
cd "$_proj_tf"
_run_backup "$_proj_tf" >/dev/null 2>&1
if [[ -f "$_proj_tf/backups/files/terraform.tfstate" ]]; then
    test_pass
else
    test_fail "terraform.tfstate missing from backup"
fi

test_case ".htpasswd is backed up"
echo "admin:\$apr1\$xyz" > "$_proj_tf/.htpasswd"
cd "$_proj_tf"
_run_backup "$_proj_tf" >/dev/null 2>&1
if [[ -f "$_proj_tf/backups/files/.htpasswd" ]]; then
    test_pass
else
    test_fail ".htpasswd missing from backup"
fi

test_case "AI artifacts (CLAUDE.md) are backed up"
_proj_ai=$(_create_configured_project "ai-test")
echo "# Project instructions" > "$_proj_ai/CLAUDE.md"
mkdir -p "$_proj_ai/.claude"
echo "settings" > "$_proj_ai/.claude/settings.json"
cd "$_proj_ai"
_run_backup "$_proj_ai" >/dev/null 2>&1
if [[ -f "$_proj_ai/backups/files/CLAUDE.md" ]]; then
    test_pass
else
    test_fail "CLAUDE.md missing from backup"
fi

# ==============================================================================
# TEST SUITE 3: SYMLINKS
# ==============================================================================

test_suite "Symlink Handling"

test_case "Valid symlink target is backed up"
_proj_sym=$(_create_configured_project "sym-test")
echo "REAL_SECRET=yes" > "$TEST_TEMP_DIR/real-env"
ln -sf "$TEST_TEMP_DIR/real-env" "$_proj_sym/.env"
cd "$_proj_sym"
_run_backup "$_proj_sym" >/dev/null 2>&1
if [[ -f "$_proj_sym/backups/files/.env" ]]; then
    _content=$(cat "$_proj_sym/backups/files/.env")
    if [[ "$_content" == "REAL_SECRET=yes" ]]; then
        test_pass
    else
        test_fail "Symlink target content wrong: $_content"
    fi
else
    test_fail "Symlinked .env not backed up"
fi

test_case "Broken symlink is skipped (no crash)"
_proj_broken=$(_create_configured_project "broken-sym")
ln -sf "/nonexistent/file.txt" "$_proj_broken/broken-link.txt"
git -C "$_proj_broken" add broken-link.txt 2>/dev/null || true
cd "$_proj_broken"
_output=$(_run_backup "$_proj_broken" 2>&1)
# Should not crash
if [[ ! -f "$_proj_broken/backups/files/broken-link.txt" ]]; then
    test_pass
else
    test_fail "Broken symlink should not be in backup"
fi

test_case "Symlink chain (A->B->C) resolves correctly"
_proj_chain=$(_create_configured_project "chain-sym")
echo "CHAIN_VALUE=deep" > "$TEST_TEMP_DIR/chain-target"
ln -sf "$TEST_TEMP_DIR/chain-target" "$TEST_TEMP_DIR/chain-mid"
ln -sf "$TEST_TEMP_DIR/chain-mid" "$_proj_chain/.env"
cd "$_proj_chain"
_run_backup "$_proj_chain" >/dev/null 2>&1
if [[ -f "$_proj_chain/backups/files/.env" ]]; then
    _content=$(cat "$_proj_chain/backups/files/.env")
    if [[ "$_content" == "CHAIN_VALUE=deep" ]]; then
        test_pass
    else
        test_fail "Chain resolved to wrong content: $_content"
    fi
else
    test_fail "Chained symlink not backed up"
fi

# ==============================================================================
# TEST SUITE 4: PATH EDGE CASES
# ==============================================================================

test_suite "Path Edge Cases"

test_case "Project with spaces in path"
_proj_sp=$(_create_configured_project "my project with spaces")
cd "$_proj_sp"
_run_backup "$_proj_sp" >/dev/null 2>&1
if [[ -f "$_proj_sp/backups/files/README.md" ]]; then
    test_pass
else
    test_fail "Backup failed for project with spaces in path"
fi

test_case "Files with special characters in names"
_proj_special=$(_create_configured_project "special-chars")
echo "data" > "$_proj_special/file with spaces.txt"
echo "data" > "$_proj_special/file#hash.txt"
echo "data" > "$_proj_special/file&amp.txt"
echo "data" > "$_proj_special/file@at.txt"
git -C "$_proj_special" add . 2>/dev/null
git -C "$_proj_special" commit -q -m "special chars" 2>/dev/null
cd "$_proj_special"
_run_backup "$_proj_special" >/dev/null 2>&1
_found=0
[[ -f "$_proj_special/backups/files/file with spaces.txt" ]] && _found=$((_found + 1))
[[ -f "$_proj_special/backups/files/file#hash.txt" ]] && _found=$((_found + 1))
[[ -f "$_proj_special/backups/files/file&amp.txt" ]] && _found=$((_found + 1))
[[ -f "$_proj_special/backups/files/file@at.txt" ]] && _found=$((_found + 1))
if [[ $_found -eq 4 ]]; then
    test_pass
else
    test_fail "Only $_found/4 special-char files backed up"
fi

test_case "Empty file is backed up"
_proj_empty=$(_create_configured_project "empty-file")
touch "$_proj_empty/empty.txt"
git -C "$_proj_empty" add empty.txt 2>/dev/null
git -C "$_proj_empty" commit -q -m "empty" 2>/dev/null
cd "$_proj_empty"
_run_backup "$_proj_empty" >/dev/null 2>&1
if [[ -f "$_proj_empty/backups/files/empty.txt" ]]; then
    test_pass
else
    test_fail "Empty file not backed up"
fi

# ==============================================================================
# TEST SUITE 5: GIT EDGE CASES
# ==============================================================================

test_suite "Git Edge Cases"

test_case "Detached HEAD state does not crash backup"
_proj_dh=$(_create_configured_project "detached-head")
_commit=$(git -C "$_proj_dh" rev-parse HEAD)
git -C "$_proj_dh" checkout "$_commit" --quiet 2>/dev/null
cd "$_proj_dh"
_run_backup "$_proj_dh" >/dev/null 2>&1
if [[ -f "$_proj_dh/backups/files/README.md" ]]; then
    test_pass
else
    test_fail "Backup failed in detached HEAD state"
fi

test_case "Untracked files are backed up"
_proj_ut=$(_create_configured_project "untracked")
echo "not tracked" > "$_proj_ut/untracked.txt"
cd "$_proj_ut"
_run_backup "$_proj_ut" >/dev/null 2>&1
if [[ -f "$_proj_ut/backups/files/untracked.txt" ]]; then
    test_pass
else
    test_fail "Untracked file not backed up"
fi

test_case "Binary file in git is backed up"
_proj_bin=$(_create_configured_project "binary-file")
# Create a small binary file
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' > "$_proj_bin/image.png"
git -C "$_proj_bin" add image.png 2>/dev/null
git -C "$_proj_bin" commit -q -m "binary" 2>/dev/null
cd "$_proj_bin"
_run_backup "$_proj_bin" >/dev/null 2>&1
if [[ -f "$_proj_bin/backups/files/image.png" ]]; then
    if diff -q "$_proj_bin/image.png" "$_proj_bin/backups/files/image.png" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Binary file content differs"
    fi
else
    test_fail "Binary file not backed up"
fi

# ==============================================================================
# TEST SUITE 6: NON-GIT PROJECT
# ==============================================================================

test_suite "Non-Git Project Backup"

test_case "Non-git project backup works (first run)"
_proj_ng="$TEST_TEMP_DIR/non-git-proj"
mkdir -p "$_proj_ng/src"
echo "# No Git" > "$_proj_ng/README.md"
echo "code" > "$_proj_ng/src/main.py"
cat > "$_proj_ng/.backup-config.sh" << EOF
#!/usr/bin/env bash
PROJECT_NAME="non-git-proj"
PROJECT_DIR="$_proj_ng"
BACKUP_DIR="$_proj_ng/backups"
DB_TYPE="none"
BACKUP_INTERVAL=3600
BACKUP_ENV_FILES=true
BACKUP_CREDENTIALS=true
BACKUP_IDE_SETTINGS=true
BACKUP_LOCAL_NOTES=true
BACKUP_LOCAL_DATABASES=true
BACKUP_AI_ARTIFACTS=true
BACKUP_SYMLINK_TARGETS=true
STATE_DIR="$TEST_TEMP_DIR/state"
CLOUD_FOLDER_ENABLED=false
CLOUD_ENABLED=false
NOTIFICATIONS_ENABLED=false
TIERED_RETENTION_ENABLED=false
STORAGE_CHECK_ENABLED=false
EOF
cd "$_proj_ng"
_run_backup "$_proj_ng" >/dev/null 2>&1
if [[ -f "$_proj_ng/backups/files/README.md" ]] && [[ -f "$_proj_ng/backups/files/src/main.py" ]]; then
    test_pass
else
    test_fail "Non-git first backup missing files"
fi

test_case "Non-git project creates file manifest"
if [[ -f "$_proj_ng/backups/.file-manifest" ]]; then
    test_pass
else
    test_fail "File manifest not created for non-git project"
fi

test_case "Non-git incremental backup detects changes via manifest"
echo "# Updated" >> "$_proj_ng/README.md"
echo "new file" > "$_proj_ng/new.txt"
cd "$_proj_ng"
_run_backup "$_proj_ng" >/dev/null 2>&1
if [[ -f "$_proj_ng/backups/files/new.txt" ]]; then
    test_pass
else
    test_fail "Non-git incremental backup missed new file"
fi

# ==============================================================================
# TEST SUITE 7: DATABASE BACKUP
# ==============================================================================

test_suite "SQLite Database Backup"

test_case "SQLite database is safely backed up"
if ! command -v sqlite3 &>/dev/null; then
    test_skip "sqlite3 not available"
else
    _proj_db=$(_create_configured_project "db-test")
    _db_path="$_proj_db/data/app.db"
    mkdir -p "$_proj_db/data"
    sqlite3 "$_db_path" "CREATE TABLE t(id INTEGER PRIMARY KEY, val TEXT); INSERT INTO t VALUES(1,'hello');"

    # Update config with DB
    cat >> "$_proj_db/.backup-config.sh" << EOF
DB_TYPE="sqlite"
DB_PATH="$_db_path"
EOF
    cd "$_proj_db"
    _run_backup "$_proj_db" >/dev/null 2>&1

    # Check database backup exists
    _db_backed_up=$(find "$_proj_db/backups/databases" -name "*.db" -o -name "*.gz" 2>/dev/null | head -1)
    if [[ -n "$_db_backed_up" ]]; then
        test_pass
    else
        test_fail "Database backup not found"
    fi
fi

test_case "Secondary .db files use safe sqlite3 .backup"
if ! command -v sqlite3 &>/dev/null; then
    test_skip "sqlite3 not available"
else
    _proj_sec=$(_create_configured_project "sec-db-test")
    mkdir -p "$_proj_sec/data"
    sqlite3 "$_proj_sec/data/cache.db" "CREATE TABLE c(k TEXT, v TEXT); INSERT INTO c VALUES('a','1');"
    cd "$_proj_sec"
    _run_backup "$_proj_sec" >/dev/null 2>&1

    if [[ -f "$_proj_sec/backups/files/data/cache.db" ]]; then
        # Verify the backup is a valid SQLite file
        if sqlite3 "$_proj_sec/backups/files/data/cache.db" "SELECT count(*) FROM c;" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Secondary DB backup is corrupt"
        fi
    else
        test_fail "Secondary DB file not backed up"
    fi
fi

# ==============================================================================
# TEST SUITE 8: STATE ISOLATION
# ==============================================================================

test_suite "State Directory Isolation"

test_case "Two projects with same name get different state dirs"
_proj_a="$TEST_TEMP_DIR/dir-a/myapp"
_proj_b="$TEST_TEMP_DIR/dir-b/myapp"
mkdir -p "$_proj_a" "$_proj_b"

# Give them different checkpoint IDs
echo "aaaa1111-2222-3333-4444-555566667777" > "$_proj_a/.checkpoint-id"
echo "bbbb1111-2222-3333-4444-555566667777" > "$_proj_b/.checkpoint-id"

# Source state module to test get_project_state_id
export _CHECKPOINT_LIB_DIR="$PROJECT_ROOT/lib"
source "$PROJECT_ROOT/lib/core/logging.sh" 2>/dev/null || true
source "$PROJECT_ROOT/lib/core/error-codes.sh" 2>/dev/null || true
source "$PROJECT_ROOT/lib/core/output.sh" 2>/dev/null || true
source "$PROJECT_ROOT/lib/core/config.sh" 2>/dev/null || true
# Reset include guard to re-source
unset _CHECKPOINT_STATE 2>/dev/null || true
source "$PROJECT_ROOT/lib/ops/state.sh" 2>/dev/null || true

_id_a=$(get_project_state_id "$_proj_a" "myapp" 2>/dev/null)
_id_b=$(get_project_state_id "$_proj_b" "myapp" 2>/dev/null)

if [[ "$_id_a" != "$_id_b" ]] && [[ -n "$_id_a" ]] && [[ -n "$_id_b" ]]; then
    test_pass
else
    test_fail "State IDs should differ: '$_id_a' vs '$_id_b'"
fi

# ==============================================================================
# TEST SUITE 9: CONFIG EDGE CASES
# ==============================================================================

test_suite "Config Edge Cases"

test_case "Missing config triggers auto-generation"
_proj_noconf="$TEST_TEMP_DIR/no-config"
mkdir -p "$_proj_noconf"
git -C "$_proj_noconf" init -q 2>/dev/null
git -C "$_proj_noconf" config user.email "t@t.com" 2>/dev/null
git -C "$_proj_noconf" config user.name "T" 2>/dev/null
echo "hi" > "$_proj_noconf/file.txt"
git -C "$_proj_noconf" add . 2>/dev/null
git -C "$_proj_noconf" commit -q -m "init" 2>/dev/null
cd "$_proj_noconf"
# backup-now.sh should auto-generate config
_output=$(STORAGE_CHECK_ENABLED=false STORAGE_CRITICAL_PERCENT=100 \
    bash "$PROJECT_ROOT/bin/backup-now.sh" --force --quiet 2>&1 || true)
if [[ -f "$_proj_noconf/.backup-config.sh" ]]; then
    test_pass
else
    test_fail "Config not auto-generated"
fi

test_case "Backup works with auto-generated config"
if [[ -d "$_proj_noconf/backups/files" ]]; then
    _count=$(find "$_proj_noconf/backups/files" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ $_count -gt 0 ]]; then
        test_pass
    else
        test_fail "No files backed up with auto-generated config"
    fi
else
    test_fail "Backup directory not created"
fi

# ==============================================================================
# TEST SUITE 10: DRY RUN
# ==============================================================================

test_suite "Dry Run Mode"

test_case "--dry-run does not create backup files"
_proj_dry=$(_create_configured_project "dry-run-test")
cd "$_proj_dry"
bash "$PROJECT_ROOT/bin/backup-now.sh" --force --dry-run --quiet 2>&1 || true
_backup_files=$(find "$_proj_dry/backups/files" -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "${_backup_files:-0}" -eq 0 ]]; then
    test_pass
else
    test_fail "Dry run created $_backup_files files"
fi

# ==============================================================================
# CLEANUP
# ==============================================================================

cd "$PROJECT_ROOT"

print_test_summary
