## [Unreleased] - 2026-01-12

### Added
- Selector interactivo para elegir el owner del repositorio (personal u organización) al crear repos en GitHub.
- Tests bash para validar la selección de owner y el llamado a `gh repo create`.
- Flag `--logout` para cerrar sesión de GitHub CLI.
- Flag `--add-ssh-key` para subir una llave SSH pública existente a GitHub.
- Flag `--connect-remote` para conectar un directorio local con un repo remoto existente.
- Selector interactivo de repo remoto (GitHub CLI) y tipo de URL (SSH/HTTPS).
- Menú de acciones (pull/rebase/reset/push) según el estado local/remoto.
- Resolución de raíz con prioridad: argumento, valor por defecto, FZF (profundidad 2).
- Aviso y confirmación al seleccionar repos ya inicializados al conectar remote.
- Tests para el flujo `--connect-remote` con stubs de `git`/`gh`.
- Flag `-h`/`--help` para mostrar ayuda de uso.
- Soporte de instalación en Windows (Git Bash): sugerencias de instalación con `winget` y alternativas (`choco`, `scoop`).
- Instalación opcional automática en Windows: abre `cmd.exe` como admin y ejecuta `winget`.
- Tests para simular el pipeline de instalación en Windows (stubs de `cmd.exe`/`powershell.exe`).

### Changed
- La creación del repositorio en GitHub ahora usa `OWNER/REPO` según la selección del usuario (compatibilidad con versiones de `gh` sin `--owner`).
- La creación del repositorio con `gh repo create` ya no usa flags no soportados por versiones antiguas (`--default-branch`, `--push`).
- El modo interactivo vuelve a mostrar el selector de directorios al finalizar cada repositorio, permitiendo procesar varios en una sola ejecución.

### Fixed
- En Arch Linux (y derivados), la sugerencia de instalación para el comando `gh` ahora usa el paquete correcto `github-cli`.
- En Windows (Git Bash), la detección de sistema ya no falla al no existir `/etc/os-release`.
- `--logout` ahora funciona con versiones de `gh` sin el flag `--yes` y sugiere actualizar GitHub CLI.
- Seleccionar `.` (directorio actual) requiere confirmación explícita para evitar inicializar un repo dentro del directorio actual por accidente.
- La creación del `README.md` inicial ahora detecta correctamente directorios vacíos (ignorando `.git`).

### Deprecated

### Removed

### Security

### Performance

### Technical Debt
