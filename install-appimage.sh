#!/usr/bin/env bash
#
# install-appimage.sh — register an AppImage with the terminal and start menu
#
# Reads the app Name and version from the AppImage's embedded metadata
# (.desktop / AppStream XML), falling back to the filename. Installs each
# version under a versioned id (e.g. obsidian-1.5.3) so multiple versions of
# the same app coexist without overwriting each other.
#
# Usage:
#   ./install-appimage.sh [--name NAME] [--category CAT] [--dry-run] <target> ...
#
#   <target>      one or more .AppImage files, directories, or shell globs.
#                 A directory installs every *.AppImage directly inside it.
#   --name, -n    override the auto base name (single file only; version is
#                 still appended). Ignored when installing multiple files.
#   --category,-c freedesktop menu category (default: Utility), applied to all.
#                 e.g. Development Graphics AudioVideo Network Office System
#   --dry-run     show what would be done without moving files, creating
#                 symlinks/icons/menu entries, or touching shell rc files.
#
# Examples:
#   ./install-appimage.sh App.AppImage
#   ./install-appimage.sh -n obsidian -c Office Obsidian-1.5.3.AppImage
#   ./install-appimage.sh ~/Downloads/*.AppImage
#   ./install-appimage.sh -c Development ~/Downloads/appimages/
#
# Uninstall:
#   ./install-appimage.sh --remove obsidian-1.5.3   # exact
#   ./install-appimage.sh --remove obsidian         # lists installed versions

set -euo pipefail

APP_DIR="$HOME/.AppImages"
ICON_DIR="$APP_DIR/icons"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

die() { echo "Error: $*" >&2; exit 1; }

usage() {
    cat <<'EOF'
install-appimage.sh — register AppImages with the terminal and start menu

Moves each AppImage into ~/Applications, makes it executable, creates a short
terminal command (symlink in ~/.local/bin), extracts its icon, and writes a
start-menu entry (~/.local/share/applications). The app Name and version are
read from the AppImage's embedded metadata (.desktop / AppStream XML), falling
back to the filename. Each version installs under a versioned id (e.g.
obsidian-1.5.3) so multiple versions of one app coexist without overwriting.

USAGE
  install-appimage.sh [OPTIONS] <target> ...
  install-appimage.sh --remove <name>
  install-appimage.sh -h | --help

TARGETS
  One or more of:
    - a path to an .AppImage file
    - a directory (installs every *.AppImage directly inside it, non-recursive)
    - a shell glob, e.g. ~/Downloads/*.AppImage

OPTIONS
  -n, --name NAME       Override the auto-detected base name. Single file only;
                        the detected version is still appended. Ignored (with a
                        warning) when more than one AppImage is installed.
  -c, --category CAT    freedesktop menu category applied to all installs.
                        Default: Utility. Common values: Development, Graphics,
                        AudioVideo, Network, Office, System, Utility.
  --dry-run             Show what would be installed/updated/skipped without
                        moving files, creating symlinks/icons/menu entries,
                        or touching shell rc files.
  --remove NAME         Uninstall. Give the exact id (obsidian-1.5.3) to remove
                        one version; give the base (obsidian) to list installed
                        versions. Leaves the AppImage file in ~/Applications.
  -h, --help            Show this help and exit.

EXAMPLES
  install-appimage.sh App.AppImage
  install-appimage.sh -n obsidian -c Office Obsidian-1.5.3.AppImage
  install-appimage.sh ~/Downloads/*.AppImage
  install-appimage.sh -c Development ~/Downloads/appimages/
  install-appimage.sh --dry-run ~/Downloads/*.AppImage
  install-appimage.sh --remove obsidian-1.5.3
  install-appimage.sh --remove obsidian

NOTES
  - ~/.local/bin is added to your shell's rc file (bash/zsh/fish) if missing;
    open a new terminal or re-login for a new command to be found.
  - Installing moves the source file, so re-running the same glob finds nothing
    the second time — that's expected.
  - Directory mode is one level deep and does not recurse into subfolders.
EOF
}

# Ensure BIN_DIR is on PATH, adding it to the correct rc file for the user's
# login shell (zsh, fish, or bash). Detects the shell from $SHELL.
ensure_path() {
    # already active in this session? then only warn if the rc file lacks it
    local shell_name rc line already_active=0
    [[ ":$PATH:" == *":$BIN_DIR:"* ]] && already_active=1

    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh)
            rc="${ZDOTDIR:-$HOME}/.zshrc"
            line="export PATH=\"\$HOME/.local/bin:\$PATH\""
            ;;
        fish)
            rc="$HOME/.config/fish/config.fish"
            line="fish_add_path \$HOME/.local/bin"
            mkdir -p "$(dirname "$rc")"
            ;;
        bash|"")
            # prefer .bashrc; fall back handled by touching it
            rc="$HOME/.bashrc"
            line="export PATH=\"\$HOME/.local/bin:\$PATH\""
            shell_name="bash"
            ;;
        *)
            echo "Note: unrecognized shell '$shell_name'. Add $BIN_DIR to your PATH manually."
            return
            ;;
    esac

    touch "$rc"
    if grep -Fq "/.local/bin" "$rc" 2>/dev/null; then
        echo "PATH: $BIN_DIR already configured in $rc ($shell_name)."
    else
        printf '\n# added by install-appimage.sh\n%s\n' "$line" >> "$rc"
        echo "PATH: added $BIN_DIR to $rc ($shell_name)."
    fi

    if [[ $already_active -eq 0 ]]; then
        echo "      Open a new terminal (or re-login) for the command to be found."
    fi
}

# ---- help -----------------------------------------------------------------
for a in "$@"; do
    case "$a" in
        -h|--help) usage; exit 0 ;;
    esac
done

# ---- uninstall mode -------------------------------------------------------
if [[ "${1:-}" == "--remove" ]]; then
    name="${2:-}"
    [[ -n "$name" ]] || die "give the command-name to remove (e.g. foo-1.2.3, or 'foo' to list versions)"
    # exact match?
    if [[ -e "$BIN_DIR/$name" || -e "$DESKTOP_DIR/$name.desktop" ]]; then
        rm -f "$BIN_DIR/$name"
        rm -f "$DESKTOP_DIR/$name.desktop"
        rm -f "$ICON_DIR/$name."*
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
        echo "Removed '$name' (the AppImage file in $APP_DIR was left in place)."
        exit 0
    fi
    # no exact match: list versioned installs that start with the given base
    matches="$(find "$DESKTOP_DIR" -maxdepth 1 -name "$name-*.desktop" -printf '%f\n' 2>/dev/null \
        | sed -E 's/\.desktop$//' || true)"
    if [[ -n "$matches" ]]; then
        echo "No exact match for '$name'. Installed versions:"
        echo "$matches" | sed 's/^/  /'
        echo "Re-run with the full name, e.g.: $0 --remove $(echo "$matches" | head -n1)"
    else
        echo "Nothing found matching '$name'."
    fi
    exit 0
fi

# ---- install one AppImage -------------------------------------------------
# install_one <src> <argname-or-empty> <category>
install_one() {
    local src="$1" argname="$2" category="$3"
    local base tmp extracted meta_name meta_version version vslug
    local basename_slug name dest icon_path found ext desk appdata display
    local existing_matches installed_versions max_installed ans

    [[ -f "$src" ]]      || { echo "Skip: file not found: $src" >&2; return 1; }
    [[ "$src" == *.AppImage || "$src" == *.appimage ]] || { echo "Skip: not an .AppImage: $src" >&2; return 1; }

    base="$(basename "$src")"

    # Extract the AppImage ONCE up front; reuse for metadata + icon.
    tmp="$(mktemp -d)"
    extracted=""
    if ( cd "$tmp" && "$src" --appimage-extract >/dev/null 2>&1 ); then
        extracted="$tmp/squashfs-root"
    fi

    # --- read Name and version from embedded metadata ----------------------
    meta_name=""
    meta_version=""
    if [[ -n "$extracted" ]]; then
        # 1) the bundled .desktop file: Name= and (sometimes) X-AppImage-Version=
        desk="$(find "$extracted" -maxdepth 2 -name '*.desktop' 2>/dev/null | head -n1 || true)"
        if [[ -n "$desk" && -f "$desk" ]]; then
            meta_name="$(sed -nE 's/^Name=(.+)$/\1/p' "$desk" | head -n1)"
            meta_version="$(sed -nE 's/^X-AppImage-Version=(.+)$/\1/p' "$desk" | head -n1)"
        fi
        # 2) AppStream metainfo XML: <release version="..."> is most reliable
        if [[ -z "$meta_version" ]]; then
            appdata="$(find "$extracted" -path '*/metainfo/*.xml' -o -path '*/appdata/*.xml' 2>/dev/null | head -n1 || true)"
            if [[ -n "$appdata" && -f "$appdata" ]]; then
                meta_version="$(grep -oE '<release[^>]+version="[^"]+"' "$appdata" \
                    | head -n1 | sed -E 's/.*version="([^"]+)".*/\1/')"
            fi
        fi
    fi

    # --- version: metadata, else parsed from filename ----------------------
    version="$meta_version"
    if [[ -z "$version" ]]; then
        version="$(echo "${base%.AppImage}" \
            | grep -oiE '[-_.]v?[0-9]+(\.[0-9]+)+' | head -n1 \
            | sed -E 's/^[-_.]//; s/^v//I')"
    fi
    vslug="$(echo "$version" | sed -E 's/[^A-Za-z0-9.]+/-/g; s/^-+|-+$//g')"

    # --- base command name: override, else metadata Name, else filename ----
    if [[ -n "$argname" ]]; then
        basename_slug="$argname"
    elif [[ -n "$meta_name" ]]; then
        basename_slug="$(echo "$meta_name" | tr '[:upper:]' '[:lower:]' \
            | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
    else
        basename_slug="$(echo "${base%.AppImage}" \
            | sed -E 's/[-_.]?v?[0-9][0-9.]*//g; s/[-_.]?x86_64//Ig; s/[-_.]?amd64//Ig' \
            | tr '[:upper:]' '[:lower:]' \
            | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
    fi
    if [[ -z "$basename_slug" ]]; then
        echo "Skip: could not derive a command name for $base; pass one explicitly." >&2
        rm -rf "$tmp"; return 1
    fi

    # --- versioned identifiers so multiple versions coexist ----------------
    if [[ -n "$vslug" ]]; then
        name="$basename_slug-$vslug"          # e.g. obsidian-1.5.3
    else
        name="$basename_slug"
        echo "Note: no version detected for $base; installing as '$name' (a new install will overwrite it)."
    fi

    # --- check for existing installs of this app; skip or offer update -----
    existing_matches="$(find "$DESKTOP_DIR" -maxdepth 1 -name "$basename_slug-*.desktop" -printf '%f\n' 2>/dev/null \
        | sed -E 's/\.desktop$//' || true)"
    if [[ -e "$DESKTOP_DIR/$basename_slug.desktop" ]]; then
        existing_matches="$basename_slug"$'\n'"$existing_matches"
    fi
    existing_matches="$(echo "$existing_matches" | sed '/^$/d')"

    if [[ -n "$existing_matches" ]]; then
        if echo "$existing_matches" | grep -qxF "$name"; then
            echo "Skip: '$name' is already installed."
            rm -rf "$tmp"; return 1
        fi

        # installed version slugs for this app (strip "basename-" prefix)
        installed_versions="$(echo "$existing_matches" | sed -E "s/^${basename_slug}-?//" | sed '/^$/d')"

        if [[ -z "$vslug" || -z "$installed_versions" ]]; then
            # can't compare versions (unknown new or installed version); ask
            read -rp "'$basename_slug' is already installed. Install '$name' anyway? [y/N] " ans
            [[ "$ans" =~ ^[Yy]$ ]] || { echo "Skip: leaving existing install of '$basename_slug' in place."; rm -rf "$tmp"; return 1; }
        else
            max_installed="$(printf '%s\n' "$installed_versions" | sort -V | tail -n1)"
            if [[ "$vslug" == "$max_installed" ]]; then
                echo "Skip: '$basename_slug' $vslug is already installed."
                rm -rf "$tmp"; return 1
            elif [[ "$(printf '%s\n%s\n' "$vslug" "$max_installed" | sort -V | tail -n1)" == "$vslug" ]]; then
                read -rp "Newer version found for '$basename_slug' ($max_installed -> $vslug). Update? [y/N] " ans
                [[ "$ans" =~ ^[Yy]$ ]] || { echo "Skip: keeping installed version(s) of '$basename_slug' ($installed_versions)."; rm -rf "$tmp"; return 1; }
            else
                echo "Skip: '$basename_slug' $vslug is not newer than installed ($max_installed)."
                rm -rf "$tmp"; return 1
            fi
        fi
    fi

    # move into ~/Applications unless it's already there
    dest="$APP_DIR/$base"
    if [[ $dry_run -eq 1 ]]; then
        echo "[dry-run] Would install AppImage -> $dest"
        echo "[dry-run] Would create terminal command -> $name  (symlink in $BIN_DIR)"
    else
        if [[ "$(readlink -f "$src")" != "$(readlink -f "$dest" 2>/dev/null || echo)" ]]; then
            mv -i "$src" "$dest"
        fi
        chmod +x "$dest"
        echo "Installed AppImage -> $dest"

        # short terminal command via symlink in ~/.local/bin
        ln -sfn "$dest" "$BIN_DIR/$name"
        echo "Terminal command  -> $name  (symlink in $BIN_DIR)"
    fi

    # icon from the already-extracted tree
    icon_path="$basename_slug"   # fallback: bare name, lets the theme resolve it
    if [[ -n "$extracted" ]]; then
        found=""
        if [[ -f "$extracted/.DirIcon" ]]; then
            found="$extracted/.DirIcon"
        else
            found="$(find "$extracted" -maxdepth 2 \( -name '*.png' -o -name '*.svg' \) 2>/dev/null | head -n1 || true)"
        fi
        if [[ -n "$found" && -f "$found" ]]; then
            ext="png"; [[ "$found" == *.svg ]] && ext="svg"
            if [[ $dry_run -eq 1 ]]; then
                icon_path="$ICON_DIR/$name.$ext"
                echo "[dry-run] Would extract icon -> $icon_path"
            else
                cp -f "$found" "$ICON_DIR/$name.$ext"
                icon_path="$ICON_DIR/$name.$ext"
                echo "Icon extracted    -> $icon_path"
            fi
        fi
    fi
    rm -rf "$tmp"

    # pretty display name: metadata Name if we have one, else derived; + version
    if [[ -n "$meta_name" ]]; then
        display="$meta_name"
    else
        display="$(echo "$basename_slug" | sed -E 's/(^|-)([a-z])/\1\u\2/g; s/-/ /g')"
    fi
    [[ -n "$version" ]] && display="$display $version"

    # .desktop entry (absolute paths; ~ does not expand here)
    local desktop_file="$DESKTOP_DIR/$name.desktop"
    if [[ $dry_run -eq 1 ]]; then
        echo "[dry-run] Would write menu entry -> $desktop_file"
        echo "[dry-run] Done: '$name' (nothing written)"
    else
        cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=$display
Exec="$dest" %U
Icon=$icon_path
Categories=$category;
Terminal=false
StartupNotify=true
EOF
        echo "Menu entry        -> $desktop_file"
        echo "Done: '$name'  (launch in a new terminal, or find '$display' in the menu)."
    fi
    echo
    return 0
}

# ---- argument parsing (single or batch) -----------------------------------
category="Utility"
argname=""
dry_run=0
targets=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --category|-c)
            category="${2:-}"; [[ -n "$category" ]] || die "--category needs a value"; shift 2 ;;
        --name|-n)
            argname="${2:-}"; [[ -n "$argname" ]] || die "--name needs a value"; shift 2 ;;
        --dry-run)
            dry_run=1; shift ;;
        --*)
            die "unknown option: $1" ;;
        *)
            targets+=("$1"); shift ;;
    esac
done

[[ ${#targets[@]} -gt 0 ]] || die "no targets given. Run '$0 --help' for usage."

# Expand any directories in the target list into the AppImages they contain.
expanded=()
for t in "${targets[@]}"; do
    if [[ -d "$t" ]]; then
        while IFS= read -r f; do expanded+=("$f"); done \
            < <(find "$t" -maxdepth 1 -type f \( -iname '*.AppImage' \) 2>/dev/null | sort)
    else
        expanded+=("$t")
    fi
done
[[ ${#expanded[@]} -gt 0 ]] || die "no AppImages found in the given path(s)"

# --name only makes sense for a single file; ignore it (with a warning) for batches.
if [[ -n "$argname" && ${#expanded[@]} -gt 1 ]]; then
    echo "Note: --name is ignored when installing multiple AppImages (each is auto-named)."
    argname=""
fi

[[ $dry_run -eq 1 ]] || mkdir -p "$APP_DIR" "$ICON_DIR" "$BIN_DIR" "$DESKTOP_DIR"

ok=0; fail=0
for f in "${expanded[@]}"; do
    if install_one "$f" "$argname" "$category"; then
        ok=$((ok+1))
    else
        fail=$((fail+1))
    fi
done

# Refresh the menu DB once, and ensure PATH once, after all installs.
if [[ $dry_run -eq 0 ]]; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

if [[ $dry_run -eq 1 ]]; then
    echo "Summary (dry-run): $ok would be installed, $fail would be skipped."
else
    echo "Summary: $ok installed, $fail skipped."
fi
echo
[[ $dry_run -eq 1 ]] || ensure_path
