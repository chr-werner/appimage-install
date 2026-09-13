# appimage-install
install appimages

## Usage

```
./install-appimage.sh [--name NAME] [--category CAT] [--dry-run] <target> ...
./install-appimage.sh --remove NAME
```

Run `./install-appimage.sh --help` for full details.

## Menu category

Without `--category`/`-c`, each AppImage's own embedded category (read from
its bundled `.desktop` `Categories=` line, or AppStream `<category>` tags) is
used for its start-menu entry when present, else `DEFAULT_CATEGORY` (see
below). Pass `--category CAT` to force one category for every install in the
batch, overriding embedded categories.

Multiple categories are fine either way — freedesktop's own
semicolon-separated format is used as-is, e.g. `--category "Development;Office"`
or an AppImage embedding `Categories=Utility;Development;`.

## Config file

No need to edit the script to change defaults. Copy `config.example` to
`~/.config/install-appimage/config` (shell-sourced) and set any of:

- `APP_DIR` — install location (default: `~/.AppImages`)
- `BIN_DIR` — terminal command symlinks (default: `~/.local/bin`)
- `DESKTOP_DIR` — `.desktop` entries (default: `~/.local/share/applications`)
- `DEFAULT_CATEGORY` — default `--category` value (default: `Utility`)
- `LOG_FILE` — log file path (default: `~/.local/state/install-appimage/install.log`)

CLI flags always override the config file. Use `--config PATH` to load a
config file from a different location.

## Logging

Every run's output is printed to the terminal as before, and appended to
`LOG_FILE` by default (timestamped run header per invocation). If the log
file can't be written, the script warns and continues normally — logging
never blocks an install.

## CI

`.github/workflows/shellcheck.yml` runs ShellCheck on every push/PR.
