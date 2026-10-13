#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

: "${FORGE_STAGE_DIR:?Forge staging directory is not set}"
: "${FORGE_PREFIX:?Forge installation prefix is not set}"

APP="wallshift"
log() { printf '[%s] %s\n' "$APP" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$APP" "$*" >&2; exit 1; }

# Source layout validation.
[[ -f "$ROOT/CMakeLists.txt" ]] || die "CMakeLists.txt is missing."
[[ -f "$ROOT/src/main.cpp" ]] || die "src/main.cpp is missing."
[[ -f "$ROOT/modules/wallshift.lua" ]] || die "modules/wallshift.lua is missing."

WALLPAPER_DIR="$ROOT/wallpapers"
[[ -d "$WALLPAPER_DIR" ]] || die "wallpapers/ directory is missing."

# This package is designed for Arch Linux.
command -v pacman >/dev/null 2>&1 ||
    die "This build script requires Arch Linux and pacman."

packages=(base-devel cmake awww)
missing=()
for package in "${packages[@]}"; do
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
done

if ((${#missing[@]})); then
    printf '\nWallshift requires these additional Arch Linux packages:\n'
    printf '  - %s\n' "${missing[@]}"
    printf '\n'
    read -r -p "Proceed with sudo pacman installation? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES|Yes)
            sudo pacman -S --needed -- "${missing[@]}" ||
                die "Dependency installation failed."
            ;;
        *)
            die "Dependency installation declined. Nothing was installed."
            ;;
    esac
else
    log "All declared system dependencies are installed."
fi

for command_name in cmake c++; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "Required command not found: $command_name"
done

# Build in a temporary directory so the source tree stays clean.
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wallshift-build.XXXXXX")"
trap 'rm -rf -- "$BUILD_DIR"' EXIT

log "Configuring CMake..."
cmake -S "$ROOT" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$FORGE_PREFIX"

log "Compiling Wallshift..."
cmake --build "$BUILD_DIR" --parallel

# Stage the compiled application under the Forge stage root.
log "Staging executable and package data..."
DESTDIR="$FORGE_STAGE_DIR" cmake --install "$BUILD_DIR"

# Stage Lua module and sample wallpapers as package-owned data.
STAGED_DATA="$FORGE_STAGE_DIR$FORGE_PREFIX/share/wallshift"
install -Dm644 "$ROOT/modules/wallshift.lua" \
    "$STAGED_DATA/modules/wallshift.lua"

mkdir -p "$STAGED_DATA/wallpapers"
while IFS= read -r -d '' image_file; do
    install -m644 "$image_file" "$STAGED_DATA/wallpapers/$(basename "$image_file")"
done < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \
       -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.avif' \) \
    -print0)

# Stage the executable in the conventional user-local bin location within the
# package stage, as requested. The live install below copies it to ~/.local/bin.
STAGED_LOCAL_BIN="$FORGE_STAGE_DIR$HOME/.local/bin"
mkdir -p "$STAGED_LOCAL_BIN"
install -m755 "$BUILD_DIR/wallshift" "$STAGED_LOCAL_BIN/wallshift"

log "Forge staging completed."
log "Staged executable: $STAGED_LOCAL_BIN/wallshift"
log "Staged Lua module: $STAGED_HYPR_MODULE"
log "Staged wallpapers: $STAGED_USER_WALLPAPERS"

# Install into the live user's Hyprland setup, matching this package's requested
# behavior. Set WALLSHIFT_CONFIGURE_HYPRLAND=0 to build/stage without live changes.
if [[ "${WALLSHIFT_CONFIGURE_HYPRLAND:-1}" != "1" ]]; then
    log "Skipping live Hyprland configuration by request."
    exit 0
fi

[[ -n "${HOME:-}" && -d "$HOME" ]] || die "HOME is not set or does not exist."

CONFIG_DIR="${HYPRLAND_CONFIG_DIR:-$HOME/.config/hypr}"
MODULE_DIR="$CONFIG_DIR/modules"
MAIN_CONFIG="$CONFIG_DIR/hyprland.lua"
MODULE_FILE="$MODULE_DIR/wallshift.lua"

mkdir -p "$MODULE_DIR"

# Back up an existing config before changing it.
if [[ -f "$MAIN_CONFIG" ]]; then
    if [[ ! -f "$MAIN_CONFIG.bak" ]]; then
        cp -a -- "$MAIN_CONFIG" "$MAIN_CONFIG.bak"
        log "Backup created: $MAIN_CONFIG.bak"
    else
        log "Preserving existing backup: $MAIN_CONFIG.bak"
    fi
else
    touch "$MAIN_CONFIG"
    cp -a -- "$MAIN_CONFIG" "$MAIN_CONFIG.bak"
    log "Created Hyprland Lua config and backup."
fi

install -m644 "$ROOT/modules/wallshift.lua" "$MODULE_FILE"
log "Installed Lua module: $MODULE_FILE"

# Add a module require exactly once. This assumes your Lua framework loads
# hyprland.lua and makes the `hl` object available to this file.
IMPORT='require("modules.wallshift")'
if ! grep -Fqx -- "$IMPORT" "$MAIN_CONFIG"; then
    printf '\n-- Wallshift wallpaper rotation\n%s\n' "$IMPORT" >> "$MAIN_CONFIG"
    log "Added Wallshift module import to $MAIN_CONFIG"
else
    log "Wallshift module import already exists."
fi

# Install the executable directly into the live user's ~/.local/bin as requested.
install -Dm755 "$BUILD_DIR/wallshift" "$HOME/.local/bin/wallshift"
log "Installed executable: $HOME/.local/bin/wallshift"

# Install the bundled images into the live user's wallpaper directory without
# overwriting same-named existing images.
LIVE_WALLPAPERS="$HOME/Pictures/wallpapers"
mkdir -p "$LIVE_WALLPAPERS"
while IFS= read -r -d '' image_file; do
    destination="$LIVE_WALLPAPERS/$(basename "$image_file")"
    if [[ -e "$destination" ]]; then
        log "Keeping existing wallpaper: $destination"
    else
        install -m644 "$image_file" "$destination"
    fi
done < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \
       -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.avif' \) \
    -print0)

# Reload only if this is an active Hyprland session.
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1; then
    if hyprctl reload; then
        log "Hyprland configuration reloaded."
    else
        log "WARNING: Hyprland reload failed; changes apply after a restart."
    fi
else
    log "No active Hyprland session detected; changes apply next session."
fi

log "Wallshift build and installation completed."
