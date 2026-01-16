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

log_file="${GIT_LOG:-}"

if [[ -n "$log_file" ]]; then
  printf '%s ' "$@" >> "$log_file"
  echo >> "$log_file"
fi


case "${1:-}" in
  -C)
    shift 2
    ;;
 esac

case "${1:-}" in
  init|fetch|switch|pull|push|reset|add|commit|branch)
    exit 0
    ;;
  remote)
    if [[ "${2:-}" == "add" || "${2:-}" == "remove" ]]; then
      exit 0
    fi
    if [[ "${2:-}" == "get-url" ]]; then
      if [[ "${GIT_REMOTE_EXISTS:-}" == "1" ]]; then
        echo "git@github.com:myuser/example.git"
        exit 0
      fi
      if [[ "${GIT_REMOTE_EXISTS:-}" == "0" ]]; then
        exit 2
      fi
      exit 1
    fi
    exit 0
    ;;
  rev-parse)
    if [[ "${GIT_REV_PARSE_FAIL:-}" == "1" ]]; then
      exit 1
    fi
    exit 0
    ;;
  show-ref)
    if [[ "${GIT_SHOW_REF_FAIL:-}" == "1" ]]; then
      exit 1
    fi
    exit 0
    ;;
  merge-base)
    if [[ "${GIT_MERGE_BASE_FAIL:-}" == "1" ]]; then
      exit 1
    fi
    exit 0
    ;;
  for-each-ref)
    if [[ -n "${GIT_REMOTE_REFS_OUT:-}" ]]; then
      printf "%s\n" "${GIT_REMOTE_REFS_OUT}"
    fi
    exit 0
    ;;
  status)
    if [[ -n "${GIT_STATUS_OUT:-}" ]]; then
      printf "%s\n" "${GIT_STATUS_OUT}"
    fi
    exit 0
    ;;
  rev-list)
    if [[ -n "${GIT_REV_LIST_OUT:-}" ]]; then
      printf "%s\n" "${GIT_REV_LIST_OUT}"
    else
      echo "0 0"
    fi
    exit 0
    ;;
esac

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

if [[ "${1:-}" == "auth" && "${2:-}" == "logout" && "${3:-}" == "--help" ]]; then
  if [[ "${GH_LOGOUT_SUPPORTS_YES:-}" == "1" ]]; then
    echo "  --yes"
  else
    echo "  -h, --hostname"
  fi
  exit 0
fi

if [[ "${1:-}" == "auth" && "${2:-}" == "logout" ]]; then
  if [[ "${GH_LOGOUT_SUPPORTS_YES:-}" != "1" ]]; then
    for arg in "$@"; do
      if [[ "$arg" == "--yes" ]]; then
        echo "unsupported --yes" >&2
        exit 2
      fi
    done
  fi

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

if [[ "${1:-}" == "repo" && "${2:-}" == "list" ]]; then
  if [[ -n "${GH_REPO_LIST_OUT:-}" ]]; then
    printf "%s\n" "${GH_REPO_LIST_OUT}"
  fi
  exit 0
fi

if [[ "${1:-}" == "repo" && "${2:-}" == "view" ]]; then
  json_arg=""
  for arg in "$@"; do
    if [[ "$arg" == "sshUrl" || "$arg" == "httpsUrl" || "$arg" == "defaultBranchRef" ]]; then
      json_arg="$arg"
    fi
  done

  case "$json_arg" in
    sshUrl)
      echo "git@github.com:myuser/example.git"
      exit 0
      ;;
    httpsUrl)
      echo "https://github.com/myuser/example.git"
      exit 0
      ;;
    defaultBranchRef)
      echo "main"
      exit 0
      ;;
  esac
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

make_stub_windows_shell() {
  STUB_WIN=$(mktemp -d)
  export STUB_WIN

  cat > "$STUB_WIN/cmd.exe" <<'EOF'
#!/bin/bash
set -euo pipefail

# Simula cmd.exe lo suficiente para que `where winget` funcione.
if [[ "${1:-}" == "/c" ]]; then
  cmd="${2:-}"
  case "$cmd" in
    "where winget"*)
      exit 0
      ;;
  esac
fi

exit 0
EOF
  chmod +x "$STUB_WIN/cmd.exe"

  cat > "$STUB_WIN/powershell.exe" <<'EOF'
#!/bin/bash
set -euo pipefail

: "${POWERSHELL_LOG:?POWERSHELL_LOG must be set}"
printf '%s ' "$@" >> "$POWERSHELL_LOG"
echo >> "$POWERSHELL_LOG"
exit 0
EOF
  chmod +x "$STUB_WIN/powershell.exe"
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
  set_fzf_queue "$tmp/fzf.queue" "$tmp/project" ""
  export GH_REPO_CREATE_LOG="$tmp/gh.log"

  (cd "$tmp" && bash "$SCRIPT" "$tmp")

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

  set_fzf_queue "$tmp/fzf.queue1" "$tmp/project" "personal" ""
  (cd "$tmp" && bash "$SCRIPT" "$tmp")

  set_fzf_queue "$tmp/fzf.queue2" "$tmp/project" "organización" "org1" ""
  export GH_REPO_CREATE_LOG="$log2"
  (cd "$tmp" && bash "$SCRIPT" "$tmp")

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

test_windows_install_suggests_winget() {
  local output
  output=$(bash -c 'source tests/../bulk-init.sh; OS_ID=windows; MISSING_TOOLS=(gh fzf); suggest_install' 2>&1)
  echo "$output" | grep -q -- "winget install --id GitHub.cli -e" || fail "expected winget suggestion for GitHub CLI"
  echo "$output" | grep -q -- "winget install --id junegunn.fzf -e" || fail "expected winget suggestion for fzf"
}

test_windows_pipeline_offers_and_runs_autoinstall() {
  local tmp
  local output
  tmp=$(with_temp_dir)

  make_stub_windows_shell

  export POWERSHELL_LOG="$tmp/powershell.log"

  output=$(PATH="$STUB_WIN" POWERSHELL_LOG="$POWERSHELL_LOG" /bin/bash -c '
    source tests/../bulk-init.sh
    set +e
    detect_os() { OS_ID=windows; }
    is_interactive() { return 0; }

    (check_dependencies gh fzf)
    echo "__EXIT__$?"
  ' <<<"y" 2>&1)

  echo "$output" | grep -q -- "winget install --id GitHub.cli -e" || fail "expected winget suggestion for GitHub CLI in pipeline"
  echo "$output" | grep -q -- "winget install --id junegunn.fzf -e" || fail "expected winget suggestion for fzf in pipeline"
  echo "$output" | grep -q -- "__EXIT__1" || fail "expected check_dependencies to exit non-zero when tools are still missing"

  [[ -f "$POWERSHELL_LOG" ]] || fail "expected powershell.exe to be invoked for elevated install"
  grep -q -- "Start-Process cmd.exe -Verb RunAs" "$POWERSHELL_LOG" || fail "expected elevated cmd.exe invocation"
  grep -q -- "winget install --id GitHub.cli -e" "$POWERSHELL_LOG" || fail "expected winget GitHub.cli command"
  grep -q -- "winget install --id junegunn.fzf -e" "$POWERSHELL_LOG" || fail "expected winget junegunn.fzf command"
}

test_windows_pipeline_skips_autoinstall_when_no_prompt() {
  local tmp
  local output
  tmp=$(with_temp_dir)

  make_stub_windows_shell

  export POWERSHELL_LOG="$tmp/powershell.log"

  output=$(PATH="$STUB_WIN" POWERSHELL_LOG="$POWERSHELL_LOG" BULK_INIT_NO_PROMPT=1 /bin/bash -c '
    source tests/../bulk-init.sh
    set +e
    detect_os() { OS_ID=windows; }
    is_interactive() { return 0; }

    (check_dependencies gh fzf)
    echo "__EXIT__$?"
  ' <<<"y" 2>&1)

  echo "$output" | grep -q -- "winget install --id GitHub.cli -e" || fail "expected winget suggestion for GitHub CLI when no-prompt"
  echo "$output" | grep -q -- "winget install --id junegunn.fzf -e" || fail "expected winget suggestion for fzf when no-prompt"
  echo "$output" | grep -q -- "__EXIT__1" || fail "expected check_dependencies to exit non-zero when tools are missing"

  if [[ -s "$POWERSHELL_LOG" ]]; then
    fail "did not expect powershell.exe to be invoked when BULK_INIT_NO_PROMPT=1"
  fi
}

test_logout_flag_calls_gh_auth_logout() {
  local tmp
  local output
  tmp=$(with_temp_dir)

  make_stub_bin

  output=$(GH_LOGOUT_LOG="$tmp/gh.logout.log" GH_LOGOUT_SUPPORTS_YES=0 /bin/bash -c '
    source tests/../bulk-init.sh
    set +e
    is_interactive() { return 0; }
    main --logout
  ' 2>&1)

  echo "$output" | grep -q -- "no soporta '--yes'" || fail "expected update warning for old gh"
  grep -q -- "auth logout" "$tmp/gh.logout.log" || fail "expected gh auth logout to be called"
  if grep -q -- "--yes" "$tmp/gh.logout.log"; then
    fail "did not expect --yes with old gh"
  fi
}

test_logout_flag_uses_yes_when_supported() {
  local tmp
  tmp=$(with_temp_dir)

  make_stub_bin

  GH_LOGOUT_LOG="$tmp/gh.logout.log" GH_LOGOUT_SUPPORTS_YES=1 /bin/bash -c '
    source tests/../bulk-init.sh
    set +e
    is_interactive() { return 0; }
    main --logout
  ' >/dev/null 2>&1

  grep -q -- "auth logout" "$tmp/gh.logout.log" || fail "expected gh auth logout to be called"
  grep -q -- "--yes" "$tmp/gh.logout.log" || fail "expected --yes to be used when supported"
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
  (cd "$tmp" && bash "$SCRIPT" --add-ssh-key "$tmp")

  grep -q -- "ssh-key add" "$GH_SSH_KEY_ADD_LOG" || fail "expected gh ssh-key add to be called"
  grep -q -- "--title" "$GH_SSH_KEY_ADD_LOG" || fail "expected gh ssh-key add to be called with --title"
}

test_help_flag_prints_usage() {
  local tmp
  local output
  tmp=$(with_temp_dir)

  output=$(cd "$tmp" && bash "$SCRIPT" --help "$tmp")
  echo "$output" | grep -q -- "Uso:" || fail "expected help output to include 'Uso:'"
}

test_selecting_dot_requires_confirmation() {
  local tmp
  tmp=$(with_temp_dir)

  mkdir -p "$tmp/proj"
  make_stub_bin

  export GH_ORGS_MODE=none
  export GH_REPO_CREATE_LOG="$tmp/gh.log"

  set_fzf_queue "$tmp/fzf.queue" "." ""

  (cd "$tmp/proj" && printf "n\n" | bash "$SCRIPT" "$tmp/proj" >/dev/null 2>&1)

  if [[ -s "$GH_REPO_CREATE_LOG" ]]; then
    fail "expected declining '.' to not create repo"
  fi
}

test_connect_remote_flow() {
  local tmp
  local git_log
  tmp=$(with_temp_dir)

  mkdir -p "$tmp/project"
  make_stub_bin

  git_log="$tmp/git.log"
  export GIT_LOG="$git_log"
  export GH_REPO_LIST_OUT="myuser/example"
  export GIT_REMOTE_REFS_OUT="origin/main"

  set_fzf_queue "$tmp/fzf.queue" "." "$tmp/project" "personal" "myuser/example" "SSH" "origin/main" "status|Mostrar status"

  (cd "$tmp" && bash "$SCRIPT" --connect-remote >/dev/null 2>&1)

  grep -q -- "init" "$git_log" || fail "expected git init to be called"
  grep -q -- "remote add origin" "$git_log" || fail "expected git remote add origin"
  grep -q -- "fetch --prune origin" "$git_log" || fail "expected git fetch"
  grep -q -- "status -sb" "$git_log" || fail "expected git status to be called"
}

test_connect_remote_existing_git_without_origin_prompts() {
  local tmp
  local git_log
  local output
  tmp=$(with_temp_dir)

  mkdir -p "$tmp/project/.git"
  make_stub_bin

  git_log="$tmp/git.log"
  export GIT_LOG="$git_log"
  export GH_REPO_LIST_OUT="myuser/example"
  export GIT_REMOTE_REFS_OUT="origin/main"
  export GIT_REMOTE_EXISTS=0

  set_fzf_queue "$tmp/fzf.queue" "$tmp/project" "personal" "myuser/example" "SSH" "origin/main" "status|Mostrar status"

  output=$(cd "$tmp" && bash "$SCRIPT" --connect-remote "$tmp" <<<"y" 2>&1 || true)

  echo "$output" | grep -q -- "no tiene 'origin'" || fail "expected git repo warning"
  grep -q -- "remote add origin" "$git_log" || fail "expected git remote add origin"
}

test_connect_remote_existing_git_with_origin_repompts() {
  local tmp
  local git_log
  local output
  tmp=$(with_temp_dir)

  mkdir -p "$tmp/project/.git"
  mkdir -p "$tmp/alt/.git"
  make_stub_bin

  git_log="$tmp/git.log"
  export GIT_LOG="$git_log"
  export GH_REPO_LIST_OUT="myuser/example"
  export GIT_REMOTE_REFS_OUT="origin/main"
  export GIT_REMOTE_EXISTS=1

  set_fzf_queue "$tmp/fzf.queue" "$tmp/project" ".." "$tmp/alt" "personal" "myuser/example" "SSH" "origin/main" "status|Mostrar status"

  output=$(cd "$tmp" && bash "$SCRIPT" --connect-remote "$tmp" 2>&1 || true)

  echo "$output" | grep -q -- "ya tiene 'origin'" || fail "expected origin warning"
  grep -q -- "-C $tmp/alt" "$git_log" || fail "expected selection after reprompt"
}


test_connect_remote_uses_root_arg() {
  local tmp
  local git_log
  tmp=$(with_temp_dir)

  mkdir -p "$tmp/project"
  make_stub_bin

  git_log="$tmp/git.log"
  export GIT_LOG="$git_log"
  export GH_REPO_LIST_OUT="myuser/example"
  export GIT_REMOTE_REFS_OUT="origin/main"

  set_fzf_queue "$tmp/fzf.queue" "$tmp/project" "personal" "myuser/example" "SSH" "origin/main" "status|Mostrar status"

  (cd "$tmp" && bash "$SCRIPT" --connect-remote "$tmp" >/dev/null 2>&1)

  grep -q -- "-C $tmp/project" "$git_log" || fail "expected git to run in root arg"
}

run() {
  local -a tests
  tests=(
    test_owner_defaults_to_user_when_no_orgs
    test_owner_can_be_org
    test_arch_install_suggests_github_cli
    test_windows_install_suggests_winget
    test_windows_pipeline_offers_and_runs_autoinstall
    test_windows_pipeline_skips_autoinstall_when_no_prompt
    test_logout_flag_calls_gh_auth_logout
    test_logout_flag_uses_yes_when_supported
    test_add_ssh_key_flag_calls_gh_ssh_key_add
    test_help_flag_prints_usage
    test_selecting_dot_requires_confirmation
    test_connect_remote_flow
    test_connect_remote_uses_root_arg
    test_connect_remote_existing_git_without_origin_prompts
    test_connect_remote_existing_git_with_origin_repompts
  )

  local -a selected
  selected=()

  # Usage:
  #   bash tests/bulk-init.test.sh                 # all
  #   bash tests/bulk-init.test.sh test_name       # one
  #   TEST=test_name bash tests/bulk-init.test.sh  # one (env)
  #   bash tests/bulk-init.test.sh test_connect_remote_flow
  if (( $# > 0 )); then
    selected=("$@")
  elif [[ -n "${TEST:-}" ]]; then
    selected=("$TEST")
  else
    selected=("${tests[@]}")
  fi

  local test_name
  for test_name in "${selected[@]}"; do
    if ! declare -F "$test_name" >/dev/null; then
      echo "Unknown test: $test_name" >&2
      echo "Available tests:" >&2
      printf '  %s\n' "${tests[@]}" >&2
      exit 2
    fi

    "$test_name"
  done

  echo "OK"
}

run "$@"
