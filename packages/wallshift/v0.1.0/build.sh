#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

: "${FORGE_STAGE_DIR:?Forge staging directory is not set}"
: "${FORGE_PREFIX:?Forge installation prefix is not set}"

APP="wallshift"
log() { printf '[%s] %s\n' "$APP" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$APP" "$*" >&2; exit 1; }

# Validate source files.
[[ -f "$ROOT/CMakeLists.txt" ]] || die "CMakeLists.txt is missing."
[[ -f "$ROOT/src/main.cpp" ]] || die "src/main.cpp is missing."
LUA_MODULE="$ROOT/modules/wallshift.lua"
[[ -f "$LUA_MODULE" ]] || die "modules/wallshift.lua is missing."
WALLPAPER_DIR="$ROOT/wallpapers"
[[ -d "$WALLPAPER_DIR" ]] || die "wallpapers/ directory is missing."

# This package is designed for Arch Linux.
command -v pacman >/dev/null 2>&1 ||
    die "This build script requires Arch Linux and pacman."

# Check build/runtime dependencies, offering installation if needed.
packages=(base-devel cmake awww)
missing=()
for package in "${packages[@]}"; do
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
done

if ((${#missing[@]})); then
    printf '\nWallshift requires these additional Arch Linux packages:\n'
    printf '  - %s\n' "${missing[@]}"
    printf '\nPacman will install these packages and any required dependencies.\n'
    printf 'This requires sudo privileges and may download packages.\n\n'
    read -r -p "Proceed with sudo pacman installation? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES|Yes)
            log "Installing approved dependencies..."
            sudo pacman -S --needed -- "${missing[@]}" ||
                die "Dependency installation failed."
            ;;
        *) die "Dependency installation declined. Nothing was installed." ;;
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
cleanup() { rm -rf -- "$BUILD_DIR"; }
trap cleanup EXIT

log "Configuring CMake..."
cmake -S "$ROOT" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$FORGE_PREFIX"

log "Compiling Wallshift..."
cmake --build "$BUILD_DIR" --parallel

# Stage the executable using CMake, just like Snapix. Do not install the
# executable directly into ~/.local/bin here: Forge owns the final commit.
log "Staging application..."
DESTDIR="$FORGE_STAGE_DIR" cmake --install "$BUILD_DIR"

# Stage the Lua module and bundled wallpapers as package-owned data.
STAGED_DATA="$FORGE_STAGE_DIR$FORGE_PREFIX/share/wallshift"
install -Dm644 "$LUA_MODULE" "$STAGED_DATA/modules/wallshift.lua"

mkdir -p "$STAGED_DATA/wallpapers"
while IFS= read -r -d '' image_file; do
    install -m644 "$image_file" "$STAGED_DATA/wallpapers/$(basename -- "$image_file")"
done < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \
       -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.avif' \) \
    -print0)

log "Forge staging completed."
log "Staged Lua module: $STAGED_DATA/modules/wallshift.lua"
log "Staged bundled wallpapers: $STAGED_DATA/wallpapers"

# Match Snapix's behavior: allow staging/building without changing live config.
if [[ "${WALLSHIFT_CONFIGURE_HYPRLAND:-1}" != "1" ]]; then
    log "Skipping live Hyprland configuration by request."
    exit 0
fi

[[ -n "${HOME:-}" && -d "$HOME" ]] || die "HOME is not set or does not exist."

# If Hyprland control tools are unavailable, leave the package staged and exit.
if ! command -v hyprctl >/dev/null 2>&1; then
    log "Hyprland was not detected; skipping configuration."
    exit 0
fi

CONFIG_DIR="${HYPRLAND_CONFIG_DIR:-$HOME/.config/hypr}"
MAIN_CONFIG="$CONFIG_DIR/hyprland.lua"
MODULE_DIR="$CONFIG_DIR/modules"
MODULE_FILE="$MODULE_DIR/wallshift.lua"
mkdir -p "$MODULE_DIR"

# Back up the main config before editing it.
if [[ -f "$MAIN_CONFIG" ]]; then
    if [[ ! -f "$MAIN_CONFIG.bak" ]]; then
        cp -a -- "$MAIN_CONFIG" "$MAIN_CONFIG.bak"
        log "Backup created: $MAIN_CONFIG.bak"
    else
        log "Preserving existing backup: $MAIN_CONFIG.bak"
    fi
else
    mkdir -p "$CONFIG_DIR"
    touch "$MAIN_CONFIG"
    cp -a -- "$MAIN_CONFIG" "$MAIN_CONFIG.bak"
    log "Created Hyprland Lua config and backup."
fi

install -m644 "$LUA_MODULE" "$MODULE_FILE"
log "Installed Lua module: $MODULE_FILE"

IMPORT='local wallshift = require("modules.wallshift")\nwallshift.setup(hl)'
if ! grep -Fqx -- "$IMPORT" "$MAIN_CONFIG"; then
    printf '\n-- Wallshift wallpaper rotation\n%s\n' "$IMPORT" >> "$MAIN_CONFIG"
    log "Added Wallshift module import to $MAIN_CONFIG"
else
    log "Wallshift module import already exists."
fi

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    if hyprctl reload; then
        log "Hyprland configuration reloaded."
    else
        log "WARNING: Hyprland reload failed; changes apply after a restart."
    fi
else
    log "No active Hyprland session detected; changes apply next session."
fi

log "Wallshift build and staging completed."

