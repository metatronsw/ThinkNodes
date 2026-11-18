#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

swift_bin="${THINKNODES_SWIFT:-$HOME/X-Code/Swift/6.0.3/usr/bin/swift}"
if [[ ! -x "$swift_bin" && -z "${THINKNODES_SWIFT:-}" ]]; then
    swift_bin="$(command -v swift || true)"
fi
configuration="${THINKNODES_CONFIGURATION:-debug}"
executable="${THINKNODES_EXECUTABLE:-.build/$configuration/ThinkNodes}"

if [[ "${1:-}" == "user" ]]; then
    if [[ ! -x "$executable" ]]; then
        printf '%s\n' 'A futtatható fájlhoz indítsd el a ./build.sh szkriptet.' >&2
        exit 1
    fi
    if [[ -t 0 ]]; then
        read -r -s -p 'Jelszó: ' password
        printf '\n' >&2
        printf '%s\n' "$password" | "$executable" "$@"
        exit
    fi
    exec "$executable" "$@"
fi

if [[ ! -x "$executable" ]]; then
    if [[ ! -x "$swift_bin" ]]; then
        printf '%s\n' 'A Swift nem található. A THINKNODES_SWIFT változóban megadható a swift futtatható fájl.' >&2
        exit 1
    fi
    ./build.sh
fi

exec "$executable" serve --hostname "${THINKNODES_HOST:-127.0.0.1}" --port "${THINKNODES_PORT:-8080}" "$@"
