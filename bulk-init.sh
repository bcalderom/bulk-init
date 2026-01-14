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
  bulk-init.sh -h|--help

Descripción:
  Inicializa un repositorio Git en un directorio existente y lo publica en GitHub.

Opciones:
  --logout        Cierra sesión de GitHub CLI (elimina el token guardado).
  --add-ssh-key   Agrega una llave SSH pública existente (~/.ssh/*.pub) a GitHub.
  -h, --help      Muestra esta ayuda.

Ejemplos:
  bash bulk-init.sh
  bash bulk-init.sh --logout
  bash bulk-init.sh --add-ssh-key
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

    if ! gh auth status &> /dev/null; then
      log_error "No estás autenticado con GitHub CLI. Usa: gh auth login"
      exit 1
    fi

    KEY_FILE=$(select_ssh_public_key)
    KEY_TITLE="$(basename "$KEY_FILE")@$(hostname 2>/dev/null || echo local)"

    gh ssh-key add "$KEY_FILE" --title "$KEY_TITLE"
    log_info "Llave SSH agregada correctamente a tu cuenta de GitHub."
    return 0
  fi

  check_dependencies git fzf gh

  # Verifica autenticación con GitHub CLI
  if ! gh auth status &> /dev/null; then
    log_error "No estás autenticado con GitHub CLI. Usa: gh auth login"
    exit 1
  fi

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
