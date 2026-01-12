# bulk-init

Script para inicializar un repositorio Git en un directorio existente y publicarlo en GitHub usando GitHub CLI.

## Requisitos

- `git`
- `fzf`
- `gh` (GitHub CLI)
- Autenticación previa en GitHub CLI (`gh auth login`)

## Uso

Ejecuta el script desde el directorio raíz donde querés buscar carpetas para inicializar.

```bash
bash bulk-init.sh
```

Para desloguearte de GitHub CLI (eliminar el token almacenado), podés usar:

```bash
bash bulk-init.sh --logout
```

Para agregar una llave SSH existente a tu cuenta de GitHub (seleccionando un archivo `~/.ssh/*.pub` con `fzf`):

```bash
bash bulk-init.sh --add-ssh-key
```

Para ver la ayuda:

```bash
bash bulk-init.sh --help
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
