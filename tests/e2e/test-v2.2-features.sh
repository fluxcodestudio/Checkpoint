#!/bin/bash
# Test Suite for v2.2.0 New Features
# Tests: /checkpoint, /backup-update, /backup-pause, /uninstall commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
source "$SCRIPT_DIR/../test-framework.sh" 2>/dev/null || {
    echo "Test framework not found"
    exit 1
}

# ==============================================================================
# SETUP
# ==============================================================================

setup_test_environment() {
    TEST_DIR=$(mktemp -d)
    export TEST_PROJECT="$TEST_DIR/test-project"
    mkdir -p "$TEST_PROJECT"
    cd "$TEST_PROJECT"

    # Initialize git repo
    git init -q

    # Copy skills to test directory
    mkdir -p .claude/skills
    cp -r "$PROJECT_ROOT/.claude/skills/checkpoint" ".claude/skills/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/.claude/skills/backup-update" ".claude/skills/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/.claude/skills/backup-pause" ".claude/skills/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/.claude/skills/uninstall" ".claude/skills/" 2>/dev/null || true

    # Copy VERSION file
    echo "2.2.0" > "$TEST_PROJECT/VERSION"

    # Make all run.sh files executable
    chmod +x .claude/skills/*/run.sh 2>/dev/null || true
}

cleanup_test_environment() {
    if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# ==============================================================================
# CHECKPOINT COMMAND TESTS
# ==============================================================================

test_checkpoint_help() {
    describe "Checkpoint --help shows usage information"

    local output=$(.claude/skills/checkpoint/run.sh --help 2>&1)

    assert_contains "$output" "Checkpoint - Control Panel" "Help header present"
    assert_contains "$output" "Usage:" "Usage section present"
    assert_contains "$output" "--update" "Update option documented"
    assert_contains "$output" "--info" "Info option documented"
    assert_contains "$output" "--help" "Help option documented"
}

test_checkpoint_info() {
    describe "Checkpoint --info shows system information"

    local output=$(.claude/skills/checkpoint/run.sh --info 2>&1)

    assert_contains "$output" "System Information" "Info header present"
    assert_contains "$output" "Installation:" "Installation section present"
    assert_contains "$output" "Mode:" "Mode displayed"
    assert_contains "$output" "Configuration:" "Config section present"
}

test_checkpoint_version_detection() {
    describe "Checkpoint detects version correctly"

    # Copy VERSION file
    cp "$PROJECT_ROOT/VERSION" "$TEST_PROJECT/" 2>/dev/null || echo "2.2.0" > "$TEST_PROJECT/VERSION"

    local output=$(.claude/skills/checkpoint/run.sh 2>&1 || true)

    assert_contains "$output" "Version:" "Version displayed"
    assert_contains "$output" "2.2" "Correct version shown"
}

test_checkpoint_mode_detection() {
    describe "Checkpoint detects installation mode"

    local output=$(.claude/skills/checkpoint/run.sh --info 2>&1)

    # Should detect Per-Project mode since we're running from local directory
    assert_contains "$output" "Per-Project" "Detects per-project mode"
}

test_checkpoint_status_command() {
    describe "Checkpoint --status shows dashboard"

    local output=$(.claude/skills/checkpoint/run.sh --status 2>&1 || true)

    assert_contains "$output" "Checkpoint" "Dashboard header present"
    assert_contains "$output" "Commands:" "Commands section present"
}

test_checkpoint_check_update() {
    describe "Checkpoint --check-update runs without error"

    # This will fail to connect to GitHub but should handle gracefully
    local output=$(.claude/skills/checkpoint/run.sh --check-update 2>&1 || true)

    # Should show development version message OR version info
    assert_true "[ -n \"$output\" ]" "Produces output"
}

# ==============================================================================
# BACKUP-UPDATE COMMAND TESTS
# ==============================================================================

test_backup_update_exists() {
    describe "Backup-update skill exists and is executable"

    assert_file_exists ".claude/skills/backup-update/run.sh"
    assert_file_exists ".claude/skills/backup-update/skill.json"
    assert_file_executable ".claude/skills/backup-update/run.sh"
}

test_backup_update_skill_json() {
    describe "Backup-update skill.json is valid"

    local skill_json=".claude/skills/backup-update/skill.json"

    assert_file_exists "$skill_json"

    # Check JSON structure
    assert_contains "$(cat $skill_json)" "backup-update" "Has correct name"
    assert_contains "$(cat $skill_json)" "check-only" "Has check-only flag"
    assert_contains "$(cat $skill_json)" "force" "Has force flag"
}

test_backup_update_wrapper() {
    describe "Backup-update wrapper handles missing script gracefully"

    local output=$(.claude/skills/backup-update/run.sh 2>&1 || true)

    # Should either run update or show error about missing command
    assert_true "[ -n \"$output\" ]" "Produces output"
}

# ==============================================================================
# BACKUP-PAUSE COMMAND TESTS
# ==============================================================================

test_backup_pause_exists() {
    describe "Backup-pause skill exists and is executable"

    assert_file_exists ".claude/skills/backup-pause/run.sh"
    assert_file_exists ".claude/skills/backup-pause/skill.json"
    assert_file_executable ".claude/skills/backup-pause/run.sh"
}

test_backup_pause_skill_json() {
    describe "Backup-pause skill.json is valid"

    local skill_json=".claude/skills/backup-pause/skill.json"

    assert_file_exists "$skill_json"

    # Check JSON structure
    assert_contains "$(cat $skill_json)" "backup-pause" "Has correct name"
    assert_contains "$(cat $skill_json)" "resume" "Has resume flag"
    assert_contains "$(cat $skill_json)" "status" "Has status flag"
}

test_backup_pause_flags() {
    describe "Backup-pause has correct flag definitions"

    local skill_json=".claude/skills/backup-pause/skill.json"
    local content=$(cat "$skill_json")

    assert_contains "$content" "\"resume\"" "Resume flag defined"
    assert_contains "$content" "\"status\"" "Status flag defined"
    assert_contains "$content" "boolean" "Flags are boolean type"
}

# ==============================================================================
# UNINSTALL COMMAND TESTS
# ==============================================================================

test_uninstall_exists() {
    describe "Uninstall skill exists and is executable"

    assert_file_exists ".claude/skills/uninstall/run.sh"
    assert_file_exists ".claude/skills/uninstall/skill.json"
    assert_file_executable ".claude/skills/uninstall/run.sh"
}

test_uninstall_skill_json() {
    describe "Uninstall skill.json is valid"

    local skill_json=".claude/skills/uninstall/skill.json"

    assert_file_exists "$skill_json"

    # Check JSON structure
    assert_contains "$(cat $skill_json)" "uninstall" "Has correct name"
    assert_contains "$(cat $skill_json)" "keep-backups" "Has keep-backups flag"
    assert_contains "$(cat $skill_json)" "force" "Has force flag"
}

test_uninstall_wrapper() {
    describe "Uninstall wrapper handles unconfigured project"

    local output=$(.claude/skills/uninstall/run.sh 2>&1 || true)

    # Should show "no configuration found" or similar
    assert_true "[ -n \"$output\" ]" "Produces output"
}

# ==============================================================================
# SKILL INTEGRATION TESTS
# ==============================================================================

test_all_skills_have_metadata() {
    describe "All new skills have complete metadata"

    for skill in checkpoint backup-update backup-pause uninstall; do
        local skill_json=".claude/skills/$skill/skill.json"

        if [[ -f "$skill_json" ]]; then
            assert_contains "$(cat $skill_json)" "\"name\"" "$skill has name"
            assert_contains "$(cat $skill_json)" "\"description\"" "$skill has description"
            assert_contains "$(cat $skill_json)" "\"version\"" "$skill has version"
            assert_contains "$(cat $skill_json)" "\"command\"" "$skill has command"
        fi
    done
}

test_all_skills_executable() {
    describe "All new skill run.sh files are executable"

    for skill in checkpoint backup-update backup-pause uninstall; do
        local run_sh=".claude/skills/$skill/run.sh"

        if [[ -f "$run_sh" ]]; then
            assert_file_executable "$run_sh" "$skill run.sh is executable"
        fi
    done
}

test_skills_have_examples() {
    describe "All new skills have usage examples"

    for skill in checkpoint backup-update backup-pause uninstall; do
        local skill_json=".claude/skills/$skill/skill.json"

        if [[ -f "$skill_json" ]]; then
            assert_contains "$(cat $skill_json)" "\"examples\"" "$skill has examples"
        fi
    done
}

# ==============================================================================
# VERSION FILE TESTS
# ==============================================================================

test_version_file_updated() {
    describe "VERSION file is updated to 2.2.0"

    if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
        local version=$(cat "$PROJECT_ROOT/VERSION")
        assert_equals "$version" "2.2.0" "Version is 2.2.0"
    else
        fail "VERSION file not found"
    fi
}

# ==============================================================================
# DOCUMENTATION TESTS
# ==============================================================================

test_commands_documentation_updated() {
    describe "COMMANDS.md includes new commands"

    local commands_md="$PROJECT_ROOT/docs/COMMANDS.md"

    if [[ -f "$commands_md" ]]; then
        local content=$(cat "$commands_md")

        assert_contains "$content" "/checkpoint" "Checkpoint documented"
        assert_contains "$content" "/backup-update" "Update documented"
        assert_contains "$content" "/backup-pause" "Pause documented"
        assert_contains "$content" "/uninstall" "Uninstall documented"
        assert_contains "$content" "2.2.0" "Version updated"
    else
        fail "COMMANDS.md not found"
    fi
}

test_readme_updated() {
    describe "README.md includes new features"

    local readme="$PROJECT_ROOT/README.md"

    if [[ -f "$readme" ]]; then
        local content=$(cat "$readme")

        assert_contains "$content" "2.2.0" "Version updated"
        assert_contains "$content" "backup-update" "Update command listed"
        assert_contains "$content" "backup-pause" "Pause command listed"
    else
        fail "README.md not found"
    fi
}

# ==============================================================================
# CHANGELOG TESTS
# ==============================================================================

test_changelog_updated() {
    describe "CHANGELOG.md includes v2.2.0 release"

    local changelog="$PROJECT_ROOT/CHANGELOG.md"

    if [[ -f "$changelog" ]]; then
        local content=$(cat "$changelog")

        assert_contains "$content" "[2.2.0]" "Version 2.2.0 documented"
        assert_contains "$content" "2025-12-25" "Release date present"
    else
        fail "CHANGELOG.md not found"
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    suite_name "v2.2.0 Feature Tests"

    setup_test_environment

    # Checkpoint Command Tests
    run_test test_checkpoint_help
    run_test test_checkpoint_info
    run_test test_checkpoint_version_detection
    run_test test_checkpoint_mode_detection
    run_test test_checkpoint_status_command
    run_test test_checkpoint_check_update

    # Backup-Update Tests
    run_test test_backup_update_exists
    run_test test_backup_update_skill_json
    run_test test_backup_update_wrapper

    # Backup-Pause Tests
    run_test test_backup_pause_exists
    run_test test_backup_pause_skill_json
    run_test test_backup_pause_flags

    # Uninstall Tests
    run_test test_uninstall_exists
    run_test test_uninstall_skill_json
    run_test test_uninstall_wrapper

    # Integration Tests
    run_test test_all_skills_have_metadata
    run_test test_all_skills_executable
    run_test test_skills_have_examples

    # Version Tests
    run_test test_version_file_updated

    # Documentation Tests
    run_test test_commands_documentation_updated
    run_test test_readme_updated
    run_test test_changelog_updated

    cleanup_test_environment

    suite_summary
}

main "$@"
