#!/usr/bin/env bash
# Update the checkout from GitHub and build the ThinkNodes server (macOS or Fedora Linux).
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: server/deploy/build.sh [--debug] [--no-pull] [--help]

Updates the checkout from GitHub and builds the ThinkNodes server on macOS or Fedora Linux.
The release binary is moved to server/thinknodes; a --debug build stays in
server/.build/debug/thinknodes.

Before building it runs git pull (fast-forward only). If that fails, or the checkout has
local changes, it offers to reset the checkout to an exact copy of the GitHub branch:
local changes and untracked files are discarded, ignored data (projects/, .build/) is kept.

Options:
  --debug     Build the debug configuration instead of release.
  --no-pull   Skip the git update and build the local files as they are.
  --help      Show this help.

Environment:
  THINKNODES_SWIFT   Swift 6 executable (default: ~/X-Code/Swift/6.0.3, swiftly, or swift in PATH).
EOF
}

script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."
original_args=("$@")

configuration=release
pull=true
while (($#)); do
    case "$1" in
        --debug) configuration=debug ;;
        --no-pull) pull=false ;;
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
printf 'Platform: %s\n' "$platform"

# --- Update from GitHub ------------------------------------------------------------------
reset_to_remote() {
    local branch="$1"
    printf '\nThe checkout differs from origin/%s:\n' "$branch"
    git status --short | sed 's/^/  /'
    git log --oneline FETCH_HEAD..HEAD 2>/dev/null | sed 's/^/  local commit: /'
    if [[ ! -t 0 ]]; then
        printf 'Not interactive: run it in a terminal to reset, or use --no-pull.\n' >&2
        exit 1
    fi
    read -r -p "Discard all of the above and make an exact copy of origin/$branch? [y/N] " answer
    if [[ "$answer" != [yY]* ]]; then
        printf 'Stopped. Use --no-pull to build the local files.\n' >&2
        exit 1
    fi
    git reset --hard FETCH_HEAD
    git clean -fd -- "$(git rev-parse --show-toplevel)"
}

if [[ "$pull" == true ]] && git rev-parse --git-dir >/dev/null 2>&1; then
    branch="$(git symbolic-ref --quiet --short HEAD)" || { printf 'No active git branch; use --no-pull.\n' >&2; exit 1; }
    printf 'Updating from origin/%s...\n' "$branch"
    GIT_TERMINAL_PROMPT=0 git fetch --no-tags origin "refs/heads/$branch"
    before="$(git rev-parse HEAD)"
    if [[ -n "$(git status --porcelain)" ]] || ! git merge --ff-only --quiet FETCH_HEAD; then
        reset_to_remote "$branch"
    fi
    if [[ "$(git rev-parse HEAD)" != "$before" ]]; then
        # This script may have changed as well: continue with the updated version.
        exec "$script" --no-pull ${original_args[@]+"${original_args[@]}"}
    fi
fi

# --- Swift toolchain ---------------------------------------------------------------------
swift_bin="${THINKNODES_SWIFT:-}"
if [[ -z "$swift_bin" ]]; then
    for candidate in "$HOME/X-Code/Swift/6.0.3/usr/bin/swift" "$HOME/.swiftly/bin/swift" \
                     "$HOME/.local/share/swiftly/bin/swift" "$(command -v swift || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then swift_bin="$candidate"; break; fi
    done
fi
if [[ -z "$swift_bin" ]] || ! "$swift_bin" --version 2>/dev/null | grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then
    printf 'Swift 6 not found. Run server/deploy/install.sh, or set THINKNODES_SWIFT.\n' >&2
    exit 1
fi
export PATH="$(dirname "$swift_bin"):$PATH"
printf 'Swift: %s\n' "$("$swift_bin" --version 2>&1 | grep -m1 'Swift version')"

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
download d3.js "$cdn/d3@7.9.0/dist/d3.min.js"
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

jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
"$swift_bin" build "${swift_paths[@]}" --disable-automatic-resolution -c "$configuration" -j "$jobs" --product thinknodes

built=".build/$configuration/thinknodes"
[[ -x "$built" ]] || { printf 'Build finished, but %s is missing.\n' "$built" >&2; exit 1; }
if [[ "$configuration" == release ]]; then
    # Replacing the file keeps an already running server intact; it picks up the new binary on restart.
    mv -f "$built" thinknodes
    built=thinknodes
fi
if [[ "$platform" != macOS ]] && command -v ldd >/dev/null && ldd "$built" | grep -q 'not found'; then
    printf 'Missing shared libraries:\n' >&2
    ldd "$built" | grep 'not found' >&2
    exit 1
fi
printf '\nBuilt: %s/%s\n' "$PWD" "$built"
