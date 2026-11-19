#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

usage() {
    cat <<'EOF'
Usage: ./build-fedora.sh [--server-only] [--skip-update] [--] [SwiftPM build options]

Builds the ThinkNodes release executable on Fedora Linux.
Environment:
  THINKNODES_SWIFT       Swift executable (default: swift from PATH)
  THINKNODES_CONFIGURATION  SwiftPM configuration (default: release)
EOF
}

server_only=false
args=()
while (($#)); do
    case "$1" in
        --server-only) server_only=true ;;
        --skip-update) args+=(--skip-update) ;;
        -h|--help) usage; exit 0 ;;
        --) shift; args+=("$@"); break ;;
        *) args+=("$1") ;;
    esac
    shift
done

if [[ "$(uname -s)" != Linux ]]; then
    printf '%s\n' 'Ezt a szkriptet Fedora Linuxon futtasd.' >&2
    exit 1
fi

swift_bin="${THINKNODES_SWIFT:-$(command -v swift || true)}"
if [[ -z "$swift_bin" || ! -x "$swift_bin" ]]; then
    printf '%s\n' 'Swift 6 toolchain nem található. Telepítsd, majd add a swift parancsot a PATH-hoz vagy állítsd be a THINKNODES_SWIFT változót.' >&2
    exit 1
fi

swift_version="$($swift_bin --version | sed -n '1p')"
printf 'Swift: %s\n' "$swift_version"

if [[ "$server_only" == false ]]; then
    mkdir -p Public/vendor
    download() {
        local name="$1" url="$2" destination="Public/vendor/$1" temporary
        if [[ ! -s "$destination" ]]; then
            printf 'Letöltés: %s\n' "$name"
            temporary="$(mktemp "Public/vendor/.download.XXXXXX")"
            if ! curl --fail --silent --show-error --location --connect-timeout 10 --max-time 60 "$url" --output "$temporary"; then
                rm -f "$temporary"
                printf '%s\n' 'A kliensfüggőségek letöltése sikertelen. Használd a --server-only kapcsolót, vagy ellenőrizd a hálózatot.' >&2
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

mkdir -p .build/module-cache .build/package-cache .build/package-config .build/package-security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"

swift_args=(
    --cache-path "$PWD/.build/package-cache"
    --config-path "$PWD/.build/package-config"
    --security-path "$PWD/.build/package-security"
)
if [[ "${THINKNODES_SWIFTPM_NO_SANDBOX:-0}" == 1 ]]; then
    swift_args+=(--disable-sandbox)
fi

configuration="${THINKNODES_CONFIGURATION:-release}"
"$swift_bin" build "${swift_args[@]}" -c "$configuration" "${args[@]}"

executable=".build/$configuration/ThinkNodes"
if [[ ! -x "$executable" ]]; then
    printf 'A build lefutott, de a várt bináris nem található: %s\n' "$executable" >&2
    exit 1
fi
printf '\nKész: %s/%s\n' "$PWD" "$executable"
if command -v ldd >/dev/null 2>&1; then
    printf '\nDinamikus függőségek ("not found" sort nem szabad látnod):\n'
    ldd "$executable"
fi
