# bulk-init

Script para inicializar un repositorio Git en un directorio existente y publicarlo en GitHub usando GitHub CLI.

## Requisitos

- `git`
- `fzf`
- `gh` (GitHub CLI)
- Autenticación previa en GitHub CLI (`gh auth login`)

### Windows (Git Bash)

Este proyecto es un script Bash. En Windows se ejecuta vía Git Bash (Git for Windows) y puede sugerir (y opcionalmente intentar) instalar dependencias con `winget`.

## Uso

Ejecuta el script desde el directorio raíz donde querés buscar carpetas para inicializar. También podés pasar un directorio como argumento para fijar la raíz de trabajo.

### Linux/macOS

```bash
bash bulk-init.sh
```

### Windows (PowerShell)

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" ./bulk-init.sh
```

### Windows (CMD)

```bat
"%ProgramFiles%\Git\bin\bash.exe" bulk-init.sh
```

Para desloguearte de GitHub CLI (eliminar el token almacenado), podés usar:

```bash
bash bulk-init.sh --logout
```

Para agregar una llave SSH existente a tu cuenta de GitHub (seleccionando un archivo `~/.ssh/*.pub` con `fzf`):

```bash
bash bulk-init.sh --add-ssh-key
```

Para conectar un directorio local a un repositorio GitHub ya existente (elige directorio, repo remoto y tipo de URL con `fzf`):

```bash
bash bulk-init.sh --connect-remote
```

Para ver la ayuda:

```bash
bash bulk-init.sh --help
```

### Instalación rápida de dependencias (Windows)

Si estás en Windows (Git Bash) y falta `gh` y/o `fzf`, el script imprime el comando recomendado para PowerShell o CMD:

```bat
winget install --id GitHub.cli -e
winget install --id junegunn.fzf -e
```

Si `winget` no está disponible, también muestra alternativas:

```bat
choco install gh fzf -y
scoop install gh fzf
```

Además, si hay consola interactiva, te ofrece intentar la instalación automáticamente abriendo `cmd.exe` como administrador.

Para desactivar prompts (por ejemplo en CI):

```bash
BULK_INIT_NO_PROMPT=1 bash bulk-init.sh
```

El flujo interactivo:

1. Seleccionás un directorio (se excluyen los que ya son repos Git).
   - Si seleccionás el directorio actual (`.`), el script pedirá confirmación.
2. Elegís dónde crear el repositorio en GitHub:
   - personal
   - organización (si tenés organizaciones disponibles)
3. Se crea el repositorio en GitHub y se agrega `origin`.
4. Se hace el commit inicial y push a `main`.

Al finalizar, el script vuelve a mostrar el selector de directorios para continuar con otro repositorio. Para salir, cancelá la selección (ESC/Ctrl-C) o no selecciones ningún directorio.

## Tests

```bash
bash tests/bulk-init.test.sh
```
