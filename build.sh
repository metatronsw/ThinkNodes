#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

swift_bin="${THINKNODES_SWIFT:-$HOME/X-Code/Swift/6.0.3/usr/bin/swift}"
if [[ ! -x "$swift_bin" && -z "${THINKNODES_SWIFT:-}" ]]; then
    swift_bin="$(command -v swift || true)"
fi
if [[ ! -x "$swift_bin" ]]; then
    printf '%s\n' 'A Swift nem található. A THINKNODES_SWIFT változóban megadható a swift futtatható fájl.' >&2
    exit 1
fi
export PATH="$(dirname "$swift_bin"):$PATH"

server_only=false
if [[ "${1:-}" == "--server-only" ]]; then
    server_only=true
    shift
fi
configuration="${THINKNODES_CONFIGURATION:-debug}"

if [[ "$server_only" == false ]]; then
    mkdir -p Public/vendor
    download() {
        local destination="Public/vendor/$1"
        local source="$2"
        if [[ ! -s "$destination" ]]; then
            printf 'Letöltés: %s\n' "$1"
            local temporary
            temporary="$(mktemp Public/vendor/.download.XXXXXX)"
            if ! curl --fail --silent --show-error --location --connect-timeout 10 --max-time 60 "$source" --output "$temporary"; then
                rm -f "$temporary"
                printf '%s\n' 'A kliensfüggőségek első letöltéséhez internetkapcsolat szükséges. A passzív nézethez használható a --server-only kapcsoló.' >&2
                exit 1
            fi
            chmod 0644 "$temporary"
            mv "$temporary" "$destination"
        fi
    }
    cdn=https://cdn.jsdelivr.net/npm
    download vue.js "$cdn/vue@3.5.24/dist/vue.runtime.global.prod.js"
    download d3.js "$cdn/d3@7.9.0/dist/d3.min.js"
fi

# Keep compiler and package-manager caches within the checkout.
mkdir -p .build/module-cache .build/package-cache .build/package-config .build/package-security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift_paths=(
    --cache-path "$PWD/.build/package-cache"
    --config-path "$PWD/.build/package-config"
    --security-path "$PWD/.build/package-security"
)

if [[ "${THINKNODES_SWIFTPM_NO_SANDBOX:-0}" == 1 ]]; then
    swift_paths+=(--disable-sandbox)
fi

# Swift 6.0.3 with the macOS 14 SDK needs two concurrency annotations.
if [[ "$(uname -s)" == "Darwin" ]]; then
    sdk_major="$(xcrun --sdk macosx --show-sdk-version | cut -d. -f1)"
    if [[ "$sdk_major" -lt 15 ]]; then
        if [[ ! -d .build/checkouts/swift-nio || ! -d .build/checkouts/async-http-client ]]; then
            "$swift_bin" package "${swift_paths[@]}" --skip-update resolve
        fi
        for patch in Patches/*.patch; do
            name="${patch##*/}"
            checkout=".build/checkouts/${name%.patch}"
            if ! git -C "$checkout" apply --reverse --check "$PWD/$patch" 2>/dev/null; then
                git -C "$checkout" apply "$PWD/$patch"
            fi
        done
    fi
fi

exec "$swift_bin" build "${swift_paths[@]}" -c "$configuration" "$@"
