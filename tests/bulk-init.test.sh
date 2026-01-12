#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$SCRIPT_DIR/../bulk-init.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

make_stub_bin() {
  STUB_BIN=$(mktemp -d)
  export STUB_BIN
  export PATH="$STUB_BIN:$PATH"

  cat > "$STUB_BIN/fzf" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ -n "${FZF_QUEUE_FILE:-}" ]]; then
  next=$(head -n 1 "$FZF_QUEUE_FILE" || true)

  tmpfile=$(mktemp)
  tail -n +2 "$FZF_QUEUE_FILE" > "$tmpfile" || true
  cat "$tmpfile" > "$FZF_QUEUE_FILE"
  rm -f "$tmpfile"

  echo "$next"
  exit 0
fi

: "${FZF_OUT:?FZF_OUT must be set when FZF_QUEUE_FILE is not set}"
echo "$FZF_OUT"
EOF
  chmod +x "$STUB_BIN/fzf"

  cat > "$STUB_BIN/git" <<'EOF'
#!/bin/bash
set -euo pipefail
exit 0
EOF
  chmod +x "$STUB_BIN/git"

  cat > "$STUB_BIN/gh" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "ssh-key" && "${2:-}" == "add" ]]; then
  printf '%s ' "$@" > "${GH_SSH_KEY_ADD_LOG:?GH_SSH_KEY_ADD_LOG must be set}"
  echo >> "${GH_SSH_KEY_ADD_LOG}"
  exit 0
fi

if [[ "${1:-}" == "auth" && "${2:-}" == "logout" ]]; then
  printf '%s ' "$@" > "${GH_LOGOUT_LOG:?GH_LOGOUT_LOG must be set}"
  echo >> "${GH_LOGOUT_LOG}"
  exit 0
fi

if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == "user" ]]; then
  if [[ "${3:-}" == "--jq" && "${4:-}" == ".login" ]]; then
    echo "myuser"
  else
    echo '{"login":"myuser"}'
  fi
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == "user/orgs" ]]; then
  if [[ "${GH_ORGS_MODE:-}" == "none" ]]; then
    exit 0
  fi

  if [[ "${3:-}" == "--jq" ]]; then
    printf "org1\norg2\n"
  else
    echo '[{"login":"org1"},{"login":"org2"}]'
  fi
  exit 0
fi

if [[ "${1:-}" == "repo" && "${2:-}" == "create" ]]; then
  printf '%s ' "$@" > "${GH_REPO_CREATE_LOG:?GH_REPO_CREATE_LOG must be set}"
  echo >> "${GH_REPO_CREATE_LOG}"
  exit 0
fi

exit 0
EOF
  chmod +x "$STUB_BIN/gh"
}

with_temp_dir() {
  local dir
  dir=$(mktemp -d)
  echo "$dir"
}

set_fzf_queue() {
  : "${1:?queue_file path required}"

  local queue_file
  queue_file="$1"

  shift
  printf "%s\n" "$@" > "$queue_file"
  export FZF_QUEUE_FILE="$queue_file"
}

test_owner_defaults_to_user_when_no_orgs() {
  local tmp
  tmp=$(with_temp_dir)
  mkdir -p "$tmp/project"

  make_stub_bin
  export GH_ORGS_MODE=none
  set_fzf_queue "$tmp/fzf.queue" "$tmp/project"
  export GH_REPO_CREATE_LOG="$tmp/gh.log"

  (cd "$tmp" && bash "$SCRIPT")

  grep -q -- "repo create myuser/project" "$GH_REPO_CREATE_LOG" || fail "expected repo to be created under myuser when no orgs"
  if grep -q -- "--default-branch" "$GH_REPO_CREATE_LOG"; then
    fail "did not expect --default-branch flag"
  fi

  if grep -q -- "--push" "$GH_REPO_CREATE_LOG"; then
    fail "did not expect --push flag"
  fi
}

test_owner_can_be_org() {
  local tmp
  local log1
  local log2
  tmp=$(with_temp_dir)
  mkdir -p "$tmp/project"

  log1="$tmp/gh.log"
  log2="$tmp/gh.log2"

  make_stub_bin
  export GH_ORGS_MODE=some

  export GH_REPO_CREATE_LOG="$log1"

  set_fzf_queue "$tmp/fzf.queue1" "$tmp/project" "personal"
  (cd "$tmp" && bash "$SCRIPT")

  set_fzf_queue "$tmp/fzf.queue2" "$tmp/project" "organización" "org1"
  export GH_REPO_CREATE_LOG="$log2"
  (cd "$tmp" && bash "$SCRIPT")

  grep -q -- "repo create myuser/project" "$log1" || fail "expected repo to be created under myuser when selecting personal"
  grep -q -- "repo create org" "$log1" && fail "unexpected org selection when selecting personal"

  if ! grep -q -- "repo create org1/project" "$log2" && ! grep -q -- "repo create org2/project" "$log2"; then
    fail "expected --owner org1 or org2 after org selection"
  fi
}

test_arch_install_suggests_github_cli() {
  local tmp
  tmp=$(with_temp_dir)

  unset OS_ID || true
  unset MISSING_TOOLS || true

  output=$(bash -c 'source tests/../bulk-init.sh; OS_ID=arch; MISSING_TOOLS=(gh); suggest_install' 2>&1)
  echo "$output" | grep -q -- "sudo pacman -S github-cli" || fail "expected pacman suggestion to use github-cli"
}

test_logout_flag_calls_gh_auth_logout() {
  local tmp
  tmp=$(with_temp_dir)

  make_stub_bin

  export GH_LOGOUT_LOG="$tmp/gh.logout.log"
  (cd "$tmp" && bash "$SCRIPT" --logout)

  grep -q -- "auth logout" "$GH_LOGOUT_LOG" || fail "expected gh auth logout to be called"
}

test_add_ssh_key_flag_calls_gh_ssh_key_add() {
  local tmp
  tmp=$(with_temp_dir)

  make_stub_bin

  mkdir -p "$tmp/.ssh"
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTest user@test" > "$tmp/.ssh/id_ed25519.pub"

  export HOME="$tmp"
  set_fzf_queue "$tmp/fzf.queue" "$tmp/.ssh/id_ed25519.pub"

  export GH_SSH_KEY_ADD_LOG="$tmp/gh.ssh-key-add.log"
  (cd "$tmp" && bash "$SCRIPT" --add-ssh-key)

  grep -q -- "ssh-key add" "$GH_SSH_KEY_ADD_LOG" || fail "expected gh ssh-key add to be called"
  grep -q -- "--title" "$GH_SSH_KEY_ADD_LOG" || fail "expected gh ssh-key add to be called with --title"
}

test_help_flag_prints_usage() {
  local tmp
  tmp=$(with_temp_dir)

  output=$(cd "$tmp" && bash "$SCRIPT" --help)
  echo "$output" | grep -q -- "Uso:" || fail "expected help output to include 'Uso:'"
}

test_selecting_dot_requires_confirmation() {
  local tmp
  tmp=$(with_temp_dir)

  mkdir -p "$tmp/proj"
  make_stub_bin

  export GH_ORGS_MODE=none
  export FZF_OUT="."
  export GH_REPO_CREATE_LOG="$tmp/gh.log"

  if (cd "$tmp/proj" && printf "n\n" | bash "$SCRIPT" >/dev/null 2>&1); then
    fail "expected selecting '.' with 'n' to abort"
  fi
}

run() {
  test_owner_defaults_to_user_when_no_orgs
  test_owner_can_be_org
  test_arch_install_suggests_github_cli
  test_logout_flag_calls_gh_auth_logout
  test_add_ssh_key_flag_calls_gh_ssh_key_add
  test_help_flag_prints_usage
  test_selecting_dot_requires_confirmation
  echo "OK"
}

run
