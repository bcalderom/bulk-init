## [Unreleased] - 2026-01-12

### Added
- Selector interactivo para elegir el owner del repositorio (personal u organización) al crear repos en GitHub.
- Tests bash para validar la selección de owner y el llamado a `gh repo create`.
- Flag `--logout` para cerrar sesión de GitHub CLI.
- Flag `--add-ssh-key` para subir una llave SSH pública existente a GitHub.
- Flag `-h`/`--help` para mostrar ayuda de uso.

### Changed
- La creación del repositorio en GitHub ahora usa `OWNER/REPO` según la selección del usuario (compatibilidad con versiones de `gh` sin `--owner`).
- La creación del repositorio con `gh repo create` ya no usa flags no soportados por versiones antiguas (`--default-branch`, `--push`).
- El modo interactivo vuelve a mostrar el selector de directorios al finalizar cada repositorio, permitiendo procesar varios en una sola ejecución.

### Fixed
- En Arch Linux (y derivados), la sugerencia de instalación para el comando `gh` ahora usa el paquete correcto `github-cli`.
- Seleccionar `.` (directorio actual) requiere confirmación explícita para evitar inicializar un repo dentro del directorio actual por accidente.
- La creación del `README.md` inicial ahora detecta correctamente directorios vacíos (ignorando `.git`).
### Deprecated

### Removed

### Security

### Performance

### Technical Debt
