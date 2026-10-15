#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

: "${FORGE_STAGE_DIR:?Forge staging directory is not set}"
: "${FORGE_PREFIX:?Forge installation prefix is not set}"

if [[ ! -f "$ROOT/CMakeLists.txt" ]]; then
    echo "No CMakeLists.txt found in package source." >&2
    echo "Add your application's CMake project before building." >&2
    exit 1
fi

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forge-app-build.XXXXXX")"

cleanup() {
    rm -rf -- "$BUILD_DIR"
}
trap cleanup EXIT

cmake -S "$ROOT" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$FORGE_PREFIX"

cmake --build "$BUILD_DIR" --parallel

DESTDIR="$FORGE_STAGE_DIR" \
    cmake --install "$BUILD_DIR"
