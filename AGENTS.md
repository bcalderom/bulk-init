# AGENTS.md (bulk-init)

This repository is a small Bash project:
- `bulk-init.sh`: interactive script to init/publish repos via GitHub CLI.
- `tests/bulk-init.test.sh`: pure-Bash test suite (no external framework).

There are no Cursor/Copilot rule files in this repo (no `.cursor/rules/`, no `.cursorrules`, no `.github/copilot-instructions.md`).

---

## Quick Start

### Requirements
- Bash (Linux/macOS, or Git Bash on Windows)
- Runtime deps: `git`, `gh` (GitHub CLI), `fzf`

### Run
- Run the tool: `bash bulk-init.sh`
- Show help: `bash bulk-init.sh --help`
- Logout from `gh`: `bash bulk-init.sh --logout`
- Add SSH key to GitHub: `bash bulk-init.sh --add-ssh-key`
- Connect local dir to remote: `bash bulk-init.sh --connect-remote`

---

## Build / Lint / Test

This repo has no build step and no configured linter. Tests are Bash.

### Tests (all)
- Run full test suite:
  - `bash tests/bulk-init.test.sh`

### Tests (single)
The test runner supports selecting one (or more) test functions.

- Run a single test by argument:
  - `bash tests/bulk-init.test.sh test_help_flag_prints_usage`

- Run a single test via env var:
  - `TEST=test_help_flag_prints_usage bash tests/bulk-init.test.sh`

- Run multiple specific tests:
  - `bash tests/bulk-init.test.sh test_help_flag_prints_usage test_logout_flag_uses_yes_when_supported`
  - `bash tests/bulk-init.test.sh test_connect_remote_flow`

### Suggested lint (optional)
Not enforced by the repo, but recommended if available locally:
- ShellCheck (static analysis): `shellcheck bulk-init.sh tests/bulk-init.test.sh`
- shfmt (formatting): `shfmt -w bulk-init.sh tests/bulk-init.test.sh`

If you introduce these tools in CI or as a dependency, coordinate with maintainers first.

---

## Code Style (Bash)

### Shell safety defaults
Follow the existing safety baseline:
- Always start scripts with:
  - `#!/bin/bash`
  - `set -euo pipefail`

### Prefer Bash idioms already used
This codebase consistently uses:
- `[[ ... ]]` for conditionals (avoid `[`)
- `${var:-}` when a variable may be unset under `set -u`
- Arrays for lists, with length checks via `(( ${#arr[@]} > 0 ))`
- `local` variables inside functions
- `mapfile -t` for capturing command output into arrays
- `printf` over `echo` for data output (use `echo` mainly for user-facing messages)

### Function style
- Use small, single-purpose functions (this repo is a single script; keep helpers near the top).
- Function naming:
  - `snake_case` for functions and variables
  - Prefix log helpers with `log_...` (already present: `log_info`, `log_error`)
- Keep globals minimal; if global mutation is needed, do it in `main`.

### Error handling and exits
- For fatal problems in the CLI path:
  - Print a clear message to stderr (`log_error ...`), then `exit 1`.
- For non-fatal / user-cancel paths:
  - Return non-zero from helper functions and let `main` decide whether to retry.
- When probing commands that may fail, explicitly guard them:
  - `cmd ... || true` (used for fzf cancellations and optional API calls)

### Logging
- Prefer the existing helpers:
  - `log_info "..."` for normal status
  - `log_error "..."` for problems
- Keep messages user-facing and concise.

### Portability notes
- Target environments:
  - Linux/macOS (Bash)
  - Windows via Git Bash (with optional `cmd.exe`, `powershell.exe` integration)
- Avoid adding dependencies beyond `git`, `gh`, `fzf` unless necessary.
- Be careful with:
  - GNU vs BSD tool differences (e.g., `find`, `sed`), though current usage is minimal.

### Security and secrets
- Never print tokens or auth material.
- Avoid persisting secrets to disk.
- When adding new `gh` invocations, do not echo raw API responses unless needed.

---

## Tests Style (Bash)

### How tests are written
- Tests are just Bash functions named `test_...`.
- The runner calls each test and exits on first failure.
- Stubbing is done by creating temp `PATH` entries (`make_stub_bin`)—keep this pattern.

### Guidelines
- Keep tests hermetic:
  - Use `mktemp -d` and do all work in that directory.
  - Never rely on the developer’s real `gh` auth state or `~/.ssh`.
- Prefer behavioral assertions:
  - Verify outputs/logs and invoked commands, not internal function structure.
- If you add a new feature/flag, add at least one test covering the expected behavior and one test covering cancellation/error paths.

---

## Repository-specific constraints

- `bulk-init.sh` is currently >300 lines; avoid further growth.
  - Single-file constraint was requested for `--connect-remote`, so additional refactors should consider extracting new helpers into `lib/*.sh` to reduce size when feasible.

---

## Common workflows

- Validate quickly while developing:
  - `bash tests/bulk-init.test.sh test_help_flag_prints_usage`

- Validate everything before opening a PR:
  - `bash tests/bulk-init.test.sh`

- Manual smoke test (requires `gh auth login` and `fzf`):
  - `bash bulk-init.sh`
