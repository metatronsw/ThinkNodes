#!/usr/bin/env bash
# Build the ThinkNodes server (macOS or Fedora Linux). Updating from GitHub: deploy/update.sh.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: server/deploy/build.sh [--debug] [--help]

Builds the ThinkNodes server on macOS or Fedora Linux from the local files as they are
(updating from GitHub is deploy/update.sh). The binary stays in the build folder:
server/.build/release/thinknodes (--debug: server/.build/debug/thinknodes). run.sh starts
it from there; deploy/daemon.sh moves it to server/thinknodes for the systemd service.

The pinned package versions (Package.resolved) are kept; packages a newer Swift needs on
top of them (e.g. Swift 6.2+ on Fedora: swift-configuration for async-http-client) are
resolved before the build and written to the local Package.resolved.

On Linux, run as root: stale SwiftPM lock files in /tmp are removed, and if the checkout
belongs to another user (on the server: thinknodes), the build runs as that user
(runuser), so no root-owned file gets into .build.

Options:
  --debug     Build the debug configuration instead of release.
  --help      Show this help.

Environment:
  THINKNODES_SWIFT   Swift executable to use as it is (default: the version in deploy/swift.env – Linux:
                     /opt/swift-<SWIFT_LINUX>; macOS: ~/X-Code/RunTime/Swift/<SWIFT_MACOS>, swiftly or the
                     PATH; another version is not picked up automatically).
EOF
}

script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."
original_args=("$@")

configuration=release
while (($#)); do
    case "$1" in
        --debug) configuration=debug ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s (see --help)\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

case "$(uname -s)" in
    Darwin) platform=macOS ;;
    Linux) platform=Linux; [[ -f /etc/fedora-release ]] && platform=Fedora ;;
    *) printf 'Unsupported system: %s\n' "$(uname -s)" >&2; exit 1 ;;
esac

# --- Linux, run as root --------------------------------------------------------------------
# SwiftPM zárfájljai a /tmp-ben vannak (a .build útvonalából képzett előtaggal: …_.build.lock, …_.build_Package.resolved.lock
# stb.). Ha a thinknodes felhasználó hagyta ott őket, a root a Fedora fs.protected_regular védelme miatt nem nyithatja meg
# őket („invalid access to /tmp/…lock”): ezek törlődnek. Ha a checkout nem a rooté, a fordítás a tulajdonos nevében fut.
if [[ "$platform" != macOS && $EUID -eq 0 ]]; then
    for build_dir in "$PWD/.build" "$(pwd -P)/.build"; do
        rm -f "/tmp/$(printf '%s' "$build_dir" | tr '/' '_')"*.lock
    done
fi
source deploy/as-owner.sh
run_as_checkout_owner "$script" ${original_args[@]+"${original_args[@]}"}
printf 'Platform: %s\n' "$platform"

# --- Swift toolchain ---------------------------------------------------------------------
# A Swift-verzió a deploy/swift.env-ből (Linux: a swift.org toolchainje /opt/swift-<verzió>, install.sh telepíti; macOS:
# a fejlesztőgépé). A Fedora swift-lang csomagját nem veszi fel (a 6.3.2-je egy függőség fordításakor összeomlott).
# THINKNODES_SWIFT-tel más is megadható.
source deploy/swift.env
if [[ "$platform" == macOS ]]; then swift_version="$SWIFT_MACOS"; else swift_version="$SWIFT_LINUX"; fi
swift_bin="${THINKNODES_SWIFT:-}"
if [[ -z "$swift_bin" ]]; then
    for candidate in "$HOME/X-Code/RunTime/Swift/$swift_version/usr/bin/swift" "/opt/swift-$swift_version/usr/bin/swift" \
                     "$HOME/.swiftly/bin/swift" "$HOME/.local/share/swiftly/bin/swift" "$(command -v swift || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" --version 2>/dev/null | grep -q "Swift version $swift_version "; then
            swift_bin="$candidate"; break
        fi
    done
fi
if [[ -z "$swift_bin" ]] || ! "$swift_bin" --version 2>/dev/null | grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then
    printf 'Swift %s not found. Run server/deploy/install.sh, or set THINKNODES_SWIFT.\n' "$swift_version" >&2
    exit 1
fi
export PATH="$(dirname "$swift_bin"):$PATH"
swift_line="$("$swift_bin" --version 2>&1 | grep -m1 'Swift version')"
printf 'Swift: %s (%s)\n' "$swift_line" "$swift_bin"
# Másik (vagy ismeretlen) fordítóval épült modulok és gyorsítótárak nem használhatók tovább: ezek törlődnek, a letöltött
# csomagforrások (checkouts, repositories, package-cache) maradnak.
if [[ -d .build && "$(cat .build/.swift-version 2>/dev/null)" != "$swift_line" ]]; then
    printf 'New Swift version for this .build: compiling everything again\n'
    find .build -mindepth 1 -maxdepth 1 ! -name checkouts ! -name repositories ! -name package-cache \
        ! -name package-config ! -name package-security ! -name artifacts ! -name workspace-state.json -exec rm -rf {} +
fi
mkdir -p .build
printf '%s\n' "$swift_line" > .build/.swift-version

# --- Browser libraries (served from Public/vendor) ----------------------------------------
mkdir -p Public/vendor
download() {
    local destination="Public/vendor/$1" temporary
    [[ -s "$destination" ]] && return
    printf 'Downloading %s\n' "$1"
    temporary="$(mktemp Public/vendor/.download.XXXXXX)"
    if ! curl --fail --silent --show-error --location --connect-timeout 10 --max-time 60 "$2" --output "$temporary"; then
        rm -f "$temporary"
        printf 'Download failed: %s\n' "$2" >&2
        exit 1
    fi
    chmod 0644 "$temporary"
    mv "$temporary" "$destination"
}
cdn=https://cdn.jsdelivr.net/npm
download vue.js "$cdn/vue@3.5.24/dist/vue.runtime.global.prod.js"
# d3: only the zoom and selection modules are used; the bundle is in the repository (Public/lib/d3-zoom.js, deploy/d3-slim.sh).
# Same CommonMark spec as the server's cmark-gfm 0.29.
download commonmark.js "$cdn/commonmark@0.29.3/dist/commonmark.min.js"

# --- Build -------------------------------------------------------------------------------
# Compiler and package-manager caches stay inside the checkout.
mkdir -p .build/module-cache .build/package-cache .build/package-config .build/package-security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift_paths=(
    --cache-path "$PWD/.build/package-cache"
    --config-path "$PWD/.build/package-config"
    --security-path "$PWD/.build/package-security"
)

# Swift 6.0.3 with a macOS SDK older than 15 needs two concurrency annotations (Patches/).
if [[ "$platform" == macOS && "$(xcrun --sdk macosx --show-sdk-version | cut -d. -f1)" -lt 15 ]]; then
    "$swift_bin" package "${swift_paths[@]}" --disable-automatic-resolution resolve
    for patch in Patches/*.patch; do
        name="${patch##*/}"
        checkout=".build/checkouts/${name%.patch}"
        if ! git -C "$checkout" apply --reverse --check "$PWD/$patch" 2>/dev/null; then
            git -C "$checkout" apply "$PWD/$patch"
        fi
    done
fi

# The pinned versions are kept; a Swift version whose manifests need more packages than the pins list (e.g. Swift
# 6.2+: async-http-client needs swift-configuration) gets them resolved here. Then the build itself may not
# resolve anything further (--disable-automatic-resolution).
"$swift_bin" package "${swift_paths[@]}" resolve
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
"$swift_bin" build "${swift_paths[@]}" --disable-automatic-resolution -c "$configuration" -j "$jobs" --product thinknodes

built=".build/$configuration/thinknodes"
[[ -x "$built" ]] || { printf 'Build finished, but %s is missing.\n' "$built" >&2; exit 1; }
if [[ "$platform" != macOS ]] && command -v ldd >/dev/null && ldd "$built" | grep -q 'not found'; then
    printf 'Missing shared libraries:\n' >&2
    ldd "$built" | grep 'not found' >&2
    exit 1
fi
printf '\nBuilt: %s/%s\n' "$PWD" "$built"
