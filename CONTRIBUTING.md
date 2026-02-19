# Contributing to Checkpoint

Thank you for considering contributing to Checkpoint! This document provides guidelines for contributing.

## Quick Start

1. **Fork** the repository
2. **Clone** your fork
3. **Create a branch** for your feature/fix
4. **Make changes** following our standards
5. **Test thoroughly** (smoke tests + affected areas)
6. **Submit a pull request**

## Development Setup

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/checkpoint.git
cd checkpoint

# Make scripts executable
chmod +x bin/*.sh tests/*.sh

# Run smoke tests to verify setup
./tests/smoke-test.sh
```

## Code Standards

### Bash Compatibility
- **Must** be bash 3.2+ compatible (macOS default)
- **Never** use `declare -A` (associative arrays require bash 4+)
- **Never** use bash 4+ parameter expansion (`${var,,}`, `${var^^}`)
- Test on macOS bash 3.2.57 before submitting

### Script Requirements
- All scripts **must** have `#!/bin/bash` shebang
- All scripts **must** have `set -e` or `set -eo pipefail`
- All scripts **must** support `--help` flag
- All scripts **must** pass `bash -n script.sh` syntax check

### Code Style
- Use 4-space indentation (no tabs)
- Use `snake_case` for function names
- Use `SCREAMING_SNAKE_CASE` for constants
- Add comments for complex logic
- Keep functions under 50 lines when possible

### Documentation
- Update `CHANGELOG.md` for all user-facing changes
- Update relevant docs in `docs/`
- Add examples to `examples/` if applicable
- Document all new flags and options

## Testing Requirements

### Before Submitting
```bash
# 1. Run smoke tests (required)
./tests/smoke-test.sh

# 2. Run affected test suites
bash tests/unit/test-core-functions.sh           # If you changed core logic
bash tests/integration/test-backup-restore-workflow.sh  # If you changed workflows
bash tests/e2e/test-user-journeys.sh             # If you changed UX

# 3. Test manually
bin/backup-status.sh --help
bin/backup-now.sh --dry-run
# etc.
```

### Test Coverage
- New features **must** include tests
- Bug fixes **should** include regression tests
- Tests **must** use the test framework: `source tests/test-framework.sh`

### Writing Tests
```bash
#!/bin/bash
source "$(dirname "$0")/../test-framework.sh"

test_suite "My Feature"

test_case "feature works correctly"
if [[ "expected" == "actual" ]]; then
    test_pass
else
    test_fail "reason why it failed"
fi

print_test_summary
```

## Pull Request Process

### PR Title Format
```
type(scope): description

Examples:
feat(backup): add compression support
fix(restore): handle missing files gracefully
docs(readme): update installation instructions
test(unit): add tests for config validation
```

### PR Description Template
```markdown
## What
Brief description of changes

## Why
Motivation and context

## Testing
- [ ] Smoke tests pass (22/22)
- [ ] Unit tests pass (if applicable)
- [ ] Manual testing performed
- [ ] Documentation updated
- [ ] CHANGELOG.md updated

## Checklist
- [ ] Bash 3.2 compatible
- [ ] All scripts have --help
- [ ] Syntax validated (bash -n)
- [ ] No regressions introduced
```

## Commit Guidelines

### Commit Message Format
```
type(scope): brief description

Longer explanation if needed.
Can span multiple lines.

Fixes #123
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `test`: Tests
- `refactor`: Code restructuring
- `chore`: Maintenance

## Project Structure

```
checkpoint/
├── bin/            # Executable scripts
├── .claude/skills/ # Claude Code slash commands (v2.2.0)
├── docs/           # Documentation
├── examples/       # Usage examples
├── integrations/   # Platform integrations
├── lib/            # Core libraries
├── templates/      # Config templates
└── tests/          # Test suite (164 + 115 v2.2.0 tests)
```

See [docs/PROJECT-STRUCTURE.md](docs/PROJECT-STRUCTURE.md) for details.

## Common Tasks

### Adding a New Command
1. Create `bin/my-command.sh`
2. Add `--help` flag
3. Make executable: `chmod +x bin/my-command.sh`
4. Add tests: `tests/unit/test-my-command.sh`
5. Document in `docs/COMMANDS.md`
6. Update `CHANGELOG.md`

### Adding an Integration
1. Create `integrations/platform/`
2. Add `README.md` and `install.sh`
3. Source `integrations/lib/integration-core.sh`
4. Add tests: `tests/integration/test-platform-integrations.sh`
5. Document in `docs/INTEGRATIONS.md`

### Adding a Claude Code Skill (v2.2.0+)
1. Create `.claude/skills/my-skill/`
2. Add `skill.json` with metadata and argument schema
3. Create `run.sh` wrapper script
4. Make executable: `chmod +x .claude/skills/my-skill/run.sh`
5. Test with `/my-skill` in Claude Code
6. Document in `docs/COMMANDS.md`

### Fixing a Bug
1. Write a failing test that reproduces the bug
2. Fix the bug
3. Verify test now passes
4. Add regression test if needed
5. Update CHANGELOG.md

## Release Process

Only maintainers can create releases:

1. Update `VERSION` file
2. Update `CHANGELOG.md` with release notes
3. Run pre-release validation: `./tests/pre-release-validation.sh`
4. Run full test suite: `./tests/run-all-tests.sh`
5. Review test report: `TESTING-REPORT.md`
6. Create git tag: `git tag v1.X.Y`
7. Push with tags: `git push origin main --tags`
8. Create GitHub release with changelog

## Getting Help

- **Documentation**: See `docs/` directory
- **Issues**: Open a GitHub issue
- **Questions**: Start a discussion

## Code Review

All submissions require review. We look for:
- ✅ Bash 3.2 compatibility
- ✅ Tests included
- ✅ Documentation updated
- ✅ No regressions
- ✅ Follows code style
- ✅ Clear commit messages

## License

By contributing, you agree that your contributions will be licensed under the Polyform Noncommercial License 1.0.0, the same license as the project.

## Recognition

Contributors are recognized in:
- CHANGELOG.md (for significant contributions)
- Git history (all contributors)

Thank you for contributing to Checkpoint!
