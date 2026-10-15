
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

: "${FORGE_STAGE_DIR:?Forge staging directory is not set}"
: "${FORGE_PREFIX:?Forge installation prefix is not set}"

APP="qylock-setup"
SOURCE="$ROOT/qylock-setup.sh"
DEST="$FORGE_STAGE_DIR$FORGE_PREFIX/bin/$APP"

if [[ ! -f "$SOURCE" ]]; then
    echo "Error: $SOURCE not found." >&2
    exit 1
fi

if [[ ! -r "$SOURCE" ]]; then
    echo "Error: cannot read $SOURCE." >&2
    exit 1
fi

install -Dm755 "$SOURCE" "$DEST"

echo "Staged $APP successfully:"
echo "  $DEST"

