#!/bin/bash

set -euo pipefail

# =========[ FUNCIONES AUXILIARES ]==========

log_info() { echo -e "\e[32m[INFO]\e[0m $1"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $1" >&2; }
require_command() {
  if ! command -v "$1" &> /dev/null; then
    MISSING_TOOLS+=("$1")
  fi
}

is_interactive() {
  [[ -t 0 ]]
}

windows_has_winget() {
  command -v cmd.exe &> /dev/null || return 1
  cmd.exe /c "where winget" > /dev/null 2>&1
}

map_windows_winget_ids() {
  WINDOWS_WINGET_IDS=()
  for tool in "${MISSING_TOOLS[@]}"; do
    case "$tool" in
      gh)
        WINDOWS_WINGET_IDS+=("GitHub.cli")
        ;;
      fzf)
        WINDOWS_WINGET_IDS+=("junegunn.fzf")
        ;;
      git)
        WINDOWS_WINGET_IDS+=("Git.Git")
        ;;
    esac
  done
}

join_by() {
  local IFS="$1"
  shift
  echo "$*"
}

fzf_pick() {
  local prompt
  local items

  prompt="$1"
  items="$2"

  printf "%b" "$items" | fzf --prompt="$prompt"
}

require_gh_auth() {
  if ! gh auth status &> /dev/null; then
    log_error "No estás autenticado con GitHub CLI. Usa: gh auth login"
    exit 1
  fi
}

confirm_or_abort() {
  local prompt
  local reply

  prompt="$1"
  read -r -p "$prompt" reply
  if [[ "${reply:-}" != "y" && "${reply:-}" != "Y" ]]; then
    return 1
  fi

  return 0
}

select_local_non_git_dir() {
  local selected
  selected=$(find_non_git_dirs | fzf --prompt="Selecciona un directorio local (sin .git): ") || true
  if [[ -z "${selected:-}" ]]; then
    return 1
  fi

  echo "$selected"
}

select_remote_url_type() {
  local choice
  choice=$(fzf_pick "Remote URL (SSH/HTTPS): " "SSH\nHTTPS\n") || true
  if [[ -z "${choice:-}" ]]; then
    return 1
  fi

  echo "$choice"
}

select_repo_owner_with_any() {
  local user_login
  local choice
  local org

  user_login=$(gh api user --jq .login)

  mapfile -t ORGS < <(gh api user/orgs --jq '.[].login' 2>/dev/null || true)
  choice=$(printf "personal\norganización\ncualquiera\n" | fzf --prompt="¿Dónde buscar repositorios?: ") || true
  if [[ -z "${choice:-}" ]]; then
    return 1
  fi

  if [[ "$choice" == "personal" ]]; then
    echo "$user_login"
    return 0
  fi

  if [[ "$choice" == "cualquiera" ]]; then
    echo ""
    return 0
  fi

  if (( ${#ORGS[@]} == 0 )); then
    log_error "No se encontraron organizaciones."
    return 1
  fi

  org=$(printf "%s\n" "${ORGS[@]}" | fzf --prompt="Selecciona una organización: ") || true
  if [[ -z "$org" ]]; then
    return 1
  fi

  echo "$org"
}

select_github_repo() {
  local owner
  local repo
  local -a query

  owner=$(select_repo_owner_with_any) || return 1

  if [[ -n "${owner:-}" ]]; then
    query=("gh" "repo" "list" "$owner" "--limit" "300" "--json" "nameWithOwner" "--jq" ".[].nameWithOwner")
  else
    query=("gh" "repo" "list" "--limit" "300" "--json" "nameWithOwner" "--jq" ".[].nameWithOwner")
  fi

  repo=$("${query[@]}" 2>/dev/null | fzf --prompt="Selecciona repo remoto (GitHub): ") || true
  if [[ -z "${repo:-}" ]]; then
    return 1
  fi

  echo "$repo"
}

get_remote_url_for_repo() {
  local repo
  local url_type

  repo="$1"
  url_type="$2"

  case "$url_type" in
    SSH)
      gh repo view "$repo" --json sshUrl --jq .sshUrl
      ;;
    HTTPS)
      gh repo view "$repo" --json httpsUrl --jq .httpsUrl
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_not_git_repo() {
  local dir
  dir="$1"

  if [[ -d "$dir/.git" ]]; then
    log_error "El directorio ya es un repositorio Git: $dir"
    return 1
  fi

  return 0
}

ensure_dir_confirmation_if_dot() {
  local dir
  dir="$1"

  if [[ "$dir" == "." ]]; then
    if ! confirm_or_abort "Vas a conectar el repo en el directorio actual ($PWD). ¿Continuar? [y/N]: "; then
      return 1
    fi
  fi

  return 0
}

ensure_origin_remote_free() {
  local dir
  dir="$1"

  if git -C "$dir" remote get-url origin &>/dev/null; then
    if ! confirm_or_abort "El remote 'origin' ya existe en $dir. ¿Reemplazarlo? [y/N]: "; then
      return 1
    fi

    git -C "$dir" remote remove origin
  fi

  return 0
}

init_and_set_remote() {
  local dir
  local remote_url

  dir="$1"
  remote_url="$2"

  git -C "$dir" init
  ensure_origin_remote_free "$dir" || return 1
  git -C "$dir" remote add origin "$remote_url"
}

fetch_remote() {
  local dir
  dir="$1"

  git -C "$dir" fetch --prune origin
}

select_remote_branch() {
  local dir
  local repo
  local default_branch
  local remotes
  local prompt

  dir="$1"
  repo="$2"

  default_branch=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)

  if ! remotes=$(git -C "$dir" for-each-ref refs/remotes/origin --format='%(refname:short)'); then
    log_error "No se pudieron listar ramas remotas."
    return 1
  fi

  if [[ -z "${remotes:-}" ]]; then
    return 2
  fi

  prompt="Selecciona rama remota (default: ${default_branch:-desconocida}): "
  if [[ -n "${default_branch:-}" ]]; then
    echo "$remotes" | fzf --prompt="$prompt" --select-1 --query="origin/${default_branch}"
    return 0
  fi

  echo "$remotes" | fzf --prompt="$prompt"
}

has_local_commits() {
  local dir
  dir="$1"

  git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1
}

has_remote_branch() {
  local dir
  local remote_ref
  dir="$1"
  remote_ref="$2"

  git -C "$dir" show-ref --verify --quiet "refs/remotes/$remote_ref"
}

is_worktree_dirty() {
  local dir
  dir="$1"

  [[ -n "$(git -C "$dir" status --porcelain)" ]]
}

analyze_sync_state() {
  local dir
  local remote_ref

  dir="$1"
  remote_ref="$2"

  local local_has_commits=1
  local remote_has_branch=1

  if ! has_local_commits "$dir"; then
    local_has_commits=0
  fi

  if ! has_remote_branch "$dir" "$remote_ref"; then
    remote_has_branch=0
  fi

  local dirty=0
  if is_worktree_dirty "$dir"; then
    dirty=1
  fi

  if (( local_has_commits == 0 && remote_has_branch == 0 )); then
    printf "BOTH_EMPTY|dirty=%s\n" "$dirty"
    return 0
  fi

  if (( local_has_commits == 0 && remote_has_branch == 1 )); then
    printf "LOCAL_EMPTY_REMOTE_HAS|dirty=%s\n" "$dirty"
    return 0
  fi

  if (( local_has_commits == 1 && remote_has_branch == 0 )); then
    printf "REMOTE_EMPTY_LOCAL_HAS|dirty=%s\n" "$dirty"
    return 0
  fi

  if ! git -C "$dir" merge-base HEAD "$remote_ref" >/dev/null 2>&1; then
    printf "UNRELATED|dirty=%s\n" "$dirty"
    return 0
  fi

  local ahead
  local behind
  read -r ahead behind < <(git -C "$dir" rev-list --left-right --count "HEAD...$remote_ref")

  if (( ahead == 0 && behind == 0 )); then
    printf "UP_TO_DATE|ahead=0|behind=0|dirty=%s\n" "$dirty"
    return 0
  fi

  if (( ahead > 0 && behind == 0 )); then
    printf "AHEAD|ahead=%s|behind=0|dirty=%s\n" "$ahead" "$dirty"
    return 0
  fi

  if (( ahead == 0 && behind > 0 )); then
    printf "BEHIND|ahead=0|behind=%s|dirty=%s\n" "$behind" "$dirty"
    return 0
  fi

  printf "DIVERGED|ahead=%s|behind=%s|dirty=%s\n" "$ahead" "$behind" "$dirty"
}

print_sync_summary() {
  local state
  local remote_ref

  state="$1"
  remote_ref="$2"

  local status
  status="${state%%|*}"

  case "$status" in
    BOTH_EMPTY)
      log_info "Local y remoto sin commits detectables."
      log_info "Sugerencia: realiza un commit inicial y luego push."
      ;;
    LOCAL_EMPTY_REMOTE_HAS)
      log_info "El remoto tiene historial y el local no tiene commits."
      log_info "Sugerencia: checkout con tracking de $remote_ref."
      ;;
    REMOTE_EMPTY_LOCAL_HAS)
      log_info "El local tiene commits y el remoto no tiene ramas."
      log_info "Sugerencia: push inicial a $remote_ref."
      ;;
    UNRELATED)
      log_error "Historias sin ancestro común (unrelated histories)."
      ;;
    AHEAD)
      log_info "El local está adelante de $remote_ref."
      ;;
    BEHIND)
      log_info "El local está detrás de $remote_ref."
      ;;
    DIVERGED)
      log_error "Historial divergido entre local y $remote_ref."
      ;;
    UP_TO_DATE)
      log_info "Local al día con $remote_ref."
      ;;
  esac

  local dirty_flag
  dirty_flag="${state##*dirty=}"
  dirty_flag="${dirty_flag%%|*}"
  if [[ "${dirty_flag:-0}" == "1" ]]; then
    log_info "Hay cambios sin guardar en el working tree."
  fi
}

confirm_risky_action() {
  local message
  message="$1"

  log_error "$message"
  confirm_or_abort "¿Confirmas esta acción peligrosa? [y/N]: "
}

require_clean_worktree() {
  local dir
  dir="$1"

  if is_worktree_dirty "$dir"; then
    return 1
  fi

  return 0
}

present_actions_menu() {
  local dir
  local remote_ref
  local state

  dir="$1"
  remote_ref="$2"
  state="$3"

  local status
  status="${state%%|*}"

  local -a actions
  actions=()

  case "$status" in
    BOTH_EMPTY)
      actions+=("commit_initial|Crear README y commit inicial")
      ;;
    LOCAL_EMPTY_REMOTE_HAS)
      actions+=("checkout_track|Checkout con tracking")
      ;;
    REMOTE_EMPTY_LOCAL_HAS)
      actions+=("push|Push inicial a remoto")
      ;;
    BEHIND)
      actions+=("pull_ff|Pull (ff-only)")
      actions+=("pull_rebase|Pull (rebase)")
      ;;
    AHEAD)
      actions+=("push|Push")
      ;;
    DIVERGED)
      actions+=("pull_rebase|Pull (rebase)")
      actions+=("pull_merge|Pull (merge)")
      actions+=("reset_hard|Reset --hard a remoto (Peligroso)")
      actions+=("force_push|Force push a remoto (Peligroso)")
      ;;
    UNRELATED)
      actions+=("pull_unrelated|Pull allow-unrelated-histories")
      actions+=("reset_hard|Reset --hard a remoto (Peligroso)")
      ;;
    UP_TO_DATE)
      actions+=("status|Mostrar status")
      ;;
  esac

  actions+=("abort|Salir")

  local selected
  selected=$(printf "%s\n" "${actions[@]}" | fzf --prompt="Acción: " --with-nth=2 --delimiter='|') || true
  if [[ -z "${selected:-}" ]]; then
    return 1
  fi

  local key
  key="${selected%%|*}"

  case "$key" in
    commit_initial)
      if [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.git' -print -quit 2>/dev/null)" ]]; then
        echo "# $(basename "$dir")" > "$dir/README.md"
      fi
      git -C "$dir" add .
      git -C "$dir" commit -m "Initial commit"
      ;;
    checkout_track)
      git -C "$dir" switch -c "${remote_ref#origin/}" --track "$remote_ref"
      ;;
    pull_ff)
      git -C "$dir" pull --ff-only
      ;;
    pull_rebase)
      if ! require_clean_worktree "$dir"; then
        log_error "Hay cambios sin guardar. Guarda o descarta antes de rebase."
        return 1
      fi
      git -C "$dir" pull --rebase
      ;;
    pull_merge)
      git -C "$dir" pull
      ;;
    pull_unrelated)
      git -C "$dir" pull --allow-unrelated-histories
      ;;
    push)
      git -C "$dir" push -u origin HEAD
      ;;
    reset_hard)
      if ! confirm_risky_action "Esto descartará cambios locales y resets a $remote_ref."; then
        return 1
      fi
      git -C "$dir" reset --hard "$remote_ref"
      ;;
    force_push)
      if ! confirm_risky_action "Esto sobrescribirá el remoto en $remote_ref."; then
        return 1
      fi
      git -C "$dir" push --force-with-lease -u origin HEAD:"${remote_ref#origin/}"
      ;;
    status)
      git -C "$dir" status -sb
      ;;
    abort)
      return 1
      ;;
  esac
}

connect_remote_flow() {
  local dir
  local repo
  local url_type
  local remote_url
  local remote_branch
  local state

  dir=$(select_local_non_git_dir) || return 0
  ensure_dir_confirmation_if_dot "$dir" || return 0
  ensure_not_git_repo "$dir" || return 1

  repo=$(select_github_repo) || return 0
  url_type=$(select_remote_url_type) || return 0
  remote_url=$(get_remote_url_for_repo "$repo" "$url_type") || {
    log_error "No se pudo resolver la URL del repo remoto."
    return 1
  }

  log_info "Inicializando Git y configurando remote..."
  init_and_set_remote "$dir" "$remote_url"

  log_info "Obteniendo refs del remoto..."
  if ! fetch_remote "$dir"; then
    log_error "Falló git fetch. Revisa conectividad o permisos."
    return 1
  fi

  local select_status
  if remote_branch=$(select_remote_branch "$dir" "$repo"); then
    select_status=0
  else
    select_status=$?
  fi

  if [[ $select_status -eq 2 ]]; then
    log_info "No hay ramas remotas."
    remote_branch="origin/main"
  elif [[ -z "${remote_branch:-}" ]]; then
    log_info "No se seleccionó ninguna rama."
    return 0
  fi

  state=$(analyze_sync_state "$dir" "$remote_branch")
  print_sync_summary "$state" "$remote_branch"

  if ! present_actions_menu "$dir" "$remote_branch" "$state"; then
    return 0
  fi

  log_info "Actualizando estado..."
  fetch_remote "$dir" || true
  state=$(analyze_sync_state "$dir" "$remote_branch")
  print_sync_summary "$state" "$remote_branch"
}

gh_logout_supports_yes() {
  gh auth logout --help 2>/dev/null | grep -q -- "--yes"
}

maybe_auto_install_windows() {
  if ! windows_has_winget; then
    return 1
  fi

  if [[ -n "${BULK_INIT_NO_PROMPT:-}" ]] || ! is_interactive; then
    return 1
  fi

  map_windows_winget_ids
  if (( ${#WINDOWS_WINGET_IDS[@]} == 0 )); then
    return 1
  fi

  local winget_commands=()
  for winget_id in "${WINDOWS_WINGET_IDS[@]}"; do
    winget_commands+=("winget install --id ${winget_id} -e")
  done

  local winget_cmd
  winget_cmd=$(join_by " && " "${winget_commands[@]}")

  read -r -p "¿Quieres intentar instalarlas ahora (se abrirá CMD como admin)? [y/N]: " CONFIRM_INSTALL
  if [[ "${CONFIRM_INSTALL:-}" != "y" && "${CONFIRM_INSTALL:-}" != "Y" ]]; then
    return 1
  fi

  log_info "Abriendo CMD como administrador para instalar dependencias..."
  powershell.exe -NoProfile -Command "Start-Process cmd.exe -Verb RunAs -ArgumentList '/c', '${winget_cmd}'"
  return 0
}

print_help() {
  cat <<'EOF'
Uso:
  bulk-init.sh
  bulk-init.sh --logout
  bulk-init.sh --add-ssh-key
  bulk-init.sh --connect-remote
  bulk-init.sh -h|--help

Descripción:
  Inicializa un repositorio Git en un directorio existente y lo publica en GitHub.

Opciones:
  --logout          Cierra sesión de GitHub CLI (elimina el token guardado).
  --add-ssh-key     Agrega una llave SSH pública existente (~/.ssh/*.pub) a GitHub.
  --connect-remote  Conecta un directorio local a un repo existente en GitHub.
  -h, --help        Muestra esta ayuda.

Ejemplos:
  bash bulk-init.sh
  bash bulk-init.sh --logout
  bash bulk-init.sh --add-ssh-key
  bash bulk-init.sh --connect-remote
EOF
}

# =========[ DETECCIÓN DE SISTEMA OPERATIVO ]==========

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID=$ID
    return 0
  fi

  local uname_out
  uname_out=$(uname -s 2>/dev/null || true)
  case "$uname_out" in
    MINGW*|MSYS*|CYGWIN*)
      OS_ID=windows
      return 0
      ;;
    *)
      log_error "No se pudo detectar el sistema operativo."
      exit 1
      ;;
  esac
}

suggest_install() {
  case "$OS_ID" in
    ubuntu|debian)
      log_info "Puedes instalar las herramientas faltantes con:"
      echo "  sudo apt update && sudo apt install ${MISSING_TOOLS[*]}"
      ;;
    arch|manjaro|endeavouros)
      log_info "Puedes instalar las herramientas faltantes con:"
      INSTALL_PACKAGES=()
      for tool in "${MISSING_TOOLS[@]}"; do
        case "$tool" in
          gh)
            INSTALL_PACKAGES+=(github-cli)
            ;;
          *)
            INSTALL_PACKAGES+=("$tool")
            ;;
        esac
      done

      echo "  sudo pacman -S ${INSTALL_PACKAGES[*]}"
      ;;
    windows)
      log_info "Puedes instalar las herramientas faltantes en PowerShell o CMD con:"
      map_windows_winget_ids
      if (( ${#WINDOWS_WINGET_IDS[@]} > 0 )); then
        for winget_id in "${WINDOWS_WINGET_IDS[@]}"; do
          echo "  winget install --id ${winget_id} -e"
        done
      fi

      if ! windows_has_winget; then
        log_info "No se detectó winget. Alternativas:"
        echo "  choco install gh fzf -y"
        echo "  scoop install gh fzf"
      fi
      ;;
    *)
      log_info "Sistema operativo no reconocido para sugerir instalación automática."
      ;;
  esac
}

# =========[ VERIFICACIÓN DE DEPENDENCIAS ]==========

check_dependencies() {
  MISSING_TOOLS=()
  for cmd in "$@"; do
    require_command "$cmd"
  done

  if (( ${#MISSING_TOOLS[@]} > 0 )); then
    log_error "Faltan herramientas necesarias: ${MISSING_TOOLS[*]}"
    detect_os
    suggest_install

    if [[ "${OS_ID:-}" == "windows" ]]; then
      if maybe_auto_install_windows; then
        MISSING_TOOLS=()
        for cmd in "$@"; do
          require_command "$cmd"
        done

        if (( ${#MISSING_TOOLS[@]} == 0 )); then
          return 0
        fi

        log_error "Las herramientas siguen faltando después de la instalación."
        log_info "Puede que necesites abrir una nueva terminal para actualizar el PATH."
      fi
    fi

    exit 1
  fi
}

# =========[ LISTAR DIRECTORIOS VÁLIDOS ]==========

find_non_git_dirs() {
  find . -type d -name ".git" -prune -o -type d -print | while read -r dir; do
    [[ -d "$dir/.git" ]] && continue
    echo "$dir"
  done
}

select_repo_owner() {
  local user_login
  local choice
  local org

  user_login=$(gh api user --jq .login)

  mapfile -t ORGS < <(gh api user/orgs --jq '.[].login' 2>/dev/null || true)
  if (( ${#ORGS[@]} == 0 )); then
    echo "$user_login"
    return 0
  fi

  choice=$(printf "personal\norganización\n" | fzf --prompt="¿Dónde crear el repositorio?: ") || true
  if [[ -z "$choice" ]]; then
    return 1
  fi

  if [[ "$choice" == "personal" ]]; then
    echo "$user_login"
    return 0
  fi

  org=$(printf "%s\n" "${ORGS[@]}" | fzf --prompt="Selecciona una organización: ") || true
  if [[ -z "$org" ]]; then
    return 1
  fi

  echo "$org"
}

select_ssh_public_key() {
  local ssh_dir
  ssh_dir="${HOME}/.ssh"

  if [[ ! -d "$ssh_dir" ]]; then
    log_error "No existe el directorio $ssh_dir"
    exit 1
  fi

  mapfile -t SSH_KEYS < <(find "$ssh_dir" -maxdepth 1 -type f -name "*.pub" 2>/dev/null | sort)
  if (( ${#SSH_KEYS[@]} == 0 )); then
    log_error "No se encontraron llaves SSH públicas (*.pub) en $ssh_dir"
    exit 1
  fi

  KEY_FILE=$(printf "%s\n" "${SSH_KEYS[@]}" | fzf --prompt="Selecciona una llave SSH pública: ")
  if [[ -z "${KEY_FILE:-}" ]]; then
    log_error "No se seleccionó ninguna llave SSH. Abortando."
    exit 1
  fi

  echo "$KEY_FILE"
}

# =========[ INICIO DEL SCRIPT ]==========

main() {
  if (( $# > 0 )) && { [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; }; then
    print_help
    return 0
  fi

  if (( $# > 0 )) && [[ "${1:-}" == "--logout" ]]; then
    check_dependencies gh

    if gh_logout_supports_yes; then
      gh auth logout --hostname "${GH_HOST:-github.com}" --yes
      log_info "Sesión de GitHub CLI cerrada correctamente."
      return 0
    fi

    log_info "Tu versión de GitHub CLI no soporta '--yes' en 'gh auth logout'."
    log_info "Recomendamos actualizar GitHub CLI para evitar prompts interactivos."

    if [[ -n "${BULK_INIT_NO_PROMPT:-}" ]] || ! is_interactive; then
      log_error "No se puede cerrar sesión sin interacción en esta versión de GitHub CLI."
      exit 1
    fi

    gh auth logout --hostname "${GH_HOST:-github.com}"
    log_info "Sesión de GitHub CLI cerrada correctamente."
    return 0
  fi

  if (( $# > 0 )) && [[ "${1:-}" == "--add-ssh-key" ]]; then
    check_dependencies fzf gh

    require_gh_auth

    KEY_FILE=$(select_ssh_public_key)
    KEY_TITLE="$(basename "$KEY_FILE")@$(hostname 2>/dev/null || echo local)"

    gh ssh-key add "$KEY_FILE" --title "$KEY_TITLE"
    log_info "Llave SSH agregada correctamente a tu cuenta de GitHub."
    return 0
  fi

  if (( $# > 0 )) && [[ "${1:-}" == "--connect-remote" ]]; then
    check_dependencies git fzf gh

    require_gh_auth
    connect_remote_flow
    return 0
  fi

  check_dependencies git fzf gh

  require_gh_auth

  while true; do
    log_info "Buscando directorios disponibles (excluyendo repositorios Git)..."
    TARGET_DIR=$(find_non_git_dirs | fzf --prompt="Selecciona un directorio: ") || true

    if [[ -z "${TARGET_DIR:-}" ]]; then
      log_info "No se seleccionó ningún directorio. Saliendo."
      return 0
    fi

    if [[ "$TARGET_DIR" == "." ]]; then
      read -r -p "Vas a inicializar y publicar el repositorio en el directorio actual ($PWD). ¿Continuar? [y/N]: " CONFIRM
      if [[ "${CONFIRM:-}" != "y" && "${CONFIRM:-}" != "Y" ]]; then
        log_error "Abortado por el usuario."
        continue
      fi
    fi

    if [[ "$TARGET_DIR" == "." ]]; then
      REPO_NAME=$(basename "$PWD")
    else
      REPO_NAME=$(basename "$TARGET_DIR")
    fi

    OWNER=$(select_repo_owner) || true
    if [[ -z "${OWNER:-}" ]]; then
      log_error "No se seleccionó ningún owner. Abortando."
      continue
    fi

    log_info "Inicializando repositorio Git en: $TARGET_DIR"
    git -C "$TARGET_DIR" init

    log_info "Creando repositorio en GitHub: $REPO_NAME"
    gh repo create "$OWNER/$REPO_NAME" --source="$TARGET_DIR" --private --remote=origin

    # Verifica si no hay archivos, crea README para commit inicial
    if [[ -z "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' -print -quit 2>/dev/null)" ]]; then
      echo "# $REPO_NAME" > "$TARGET_DIR/README.md"
    fi

    log_info "Realizando commit inicial..."
    git -C "$TARGET_DIR" add .
    git -C "$TARGET_DIR" commit -m "Initial commit"

    log_info "Haciendo push a 'main'..."
    git -C "$TARGET_DIR" branch -M main
    git -C "$TARGET_DIR" push -u origin main

    log_info "Repositorio creado y publicado correctamente."
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
