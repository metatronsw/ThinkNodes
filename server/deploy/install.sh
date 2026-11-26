#!/usr/bin/env bash
# Check and install everything needed to develop, build and run ThinkNodes.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: server/deploy/install.sh [--force] [--help]

Checks the development and runtime environment of ThinkNodes and installs what is missing:
  - system tools and libraries (git, curl, unzip, compilers and libraries Swift needs on Linux)
  - Swift 6 toolchain (Fedora: swift-lang package or swiftly; macOS: Xcode Command Line Tools + swiftly)
  - Node.js 22+ (editor tests) and Python 3 (tools/)
  - headless Chromium on Fedora (web presentation previews)
  - the Swift packages of the server (Vapor and its dependencies), resolved into server/.build
Anything already present is left alone.

Options:
  --force     Reinstall everything, even what is already present.
  --help      Show this help.

Environment:
  THINKNODES_SWIFT   Use this Swift 6 executable instead of searching for one.
EOF
}

force=false
while (($#)); do
    case "$1" in
        --force) force=true ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s (see --help)\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

cd "$(dirname "$0")/.."
swift_version=6.0.3
ok() { printf '  ok       %s\n' "$*"; }
doing() { printf '  install  %s\n' "$*"; }

sudo_cmd=()
[[ $EUID -ne 0 ]] && sudo_cmd=(sudo)

find_swift() {
    local candidate
    for candidate in "${THINKNODES_SWIFT:-}" "$HOME/X-Code/RunTime/Swift/$swift_version/usr/bin/swift" "$HOME/.swiftly/bin/swift" \
                     "$HOME/.local/share/swiftly/bin/swift" /usr/local/bin/swift "$(command -v swift || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]] &&
            "$candidate" --version 2>/dev/null | grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then
            printf '%s\n' "$candidate"
            return
        fi
    done
}

node_ok() {
    [[ -f "$HOME/X-Code/RunTime/NodeJS/env.sh" ]] && source "$HOME/X-Code/RunTime/NodeJS/env.sh"
    command -v node >/dev/null && [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]]
}

install_swiftly_toolchain() {
    # Installs swiftly and Swift $swift_version. On Linux system-wide (/opt/swiftly, /usr/local/bin),
    # so the thinknodes service user can build too.
    local work
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' RETURN
    if [[ "$(uname -s)" == Darwin ]]; then
        curl --fail --location --silent --show-error -o "$work/swiftly.pkg" https://download.swift.org/swiftly/darwin/swiftly.pkg
        installer -pkg "$work/swiftly.pkg" -target CurrentUserHomeDirectory
        "$HOME/.swiftly/bin/swiftly" init --quiet-shell-followup --assume-yes --skip-install
        "$HOME/.swiftly/bin/swiftly" install "$swift_version" --use --assume-yes
    else
        curl --fail --location --silent --show-error -o "$work/swiftly.tar.gz" \
            "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
        tar -xzf "$work/swiftly.tar.gz" -C "$work"
        "${sudo_cmd[@]}" env SWIFTLY_HOME_DIR=/opt/swiftly SWIFTLY_BIN_DIR=/usr/local/bin \
            "$work/swiftly" init --quiet-shell-followup --assume-yes --skip-install
        "${sudo_cmd[@]}" env SWIFTLY_HOME_DIR=/opt/swiftly SWIFTLY_BIN_DIR=/usr/local/bin \
            /usr/local/bin/swiftly install "$swift_version" --use --assume-yes
    fi
}

printf '== System (%s) ==\n' "$(uname -s)"
if [[ "$(uname -s)" == Darwin ]]; then
    if xcode-select -p >/dev/null 2>&1 && [[ "$force" == false ]]; then
        ok "Xcode Command Line Tools ($(xcode-select -p))"
    else
        doing "Xcode Command Line Tools: a system dialog opens; run this script again when it has finished."
        xcode-select --install || true
        exit 1
    fi
    for tool in git curl unzip python3; do
        command -v "$tool" >/dev/null && ok "$tool" || { printf '  missing  %s (comes with the Command Line Tools)\n' "$tool"; exit 1; }
    done
elif [[ -f /etc/fedora-release ]]; then
    packages=(git curl unzip tar gzip python3 nodejs
              binutils gcc gcc-c++ glibc-devel glibc-static libstdc++-devel libstdc++-static
              libcurl-devel libxml2-devel libuuid-devel libedit-devel sqlite-devel zlib-devel libicu tzdata
              chromium-headless
              librsvg2-tools libwebp-tools)  # főoldali előnézeti képek: rsvg-convert, cwebp (PreviewRaster.swift)
    missing=()
    for package in "${packages[@]}"; do
        rpm -q "$package" >/dev/null 2>&1 && [[ "$force" == false ]] || missing+=("$package")
    done
    if ((${#missing[@]} == 0)); then
        ok "system packages (${#packages[@]})"
    elif [[ "$force" == true ]]; then
        doing "reinstalling ${#packages[@]} system packages"
        "${sudo_cmd[@]}" dnf install -y "${packages[@]}"
        "${sudo_cmd[@]}" dnf reinstall -y "${packages[@]}"
    else
        doing "${missing[*]}"
        "${sudo_cmd[@]}" dnf install -y "${missing[@]}"
    fi
else
    printf 'Unsupported system: only macOS and Fedora Linux are handled.\n' >&2
    exit 1
fi

printf '== Swift ==\n'
swift_bin="$(find_swift)"
if [[ -n "$swift_bin" && "$force" == false ]]; then
    ok "$("$swift_bin" --version 2>&1 | grep -m1 'Swift version') ($swift_bin)"
else
    if [[ -f /etc/fedora-release ]] && dnf -q list --available swift-lang 2>/dev/null | grep -Eq 'swift-lang[^ ]* +([6-9]|[1-9][0-9])\.'; then
        doing "swift-lang (dnf)"
        "${sudo_cmd[@]}" dnf install -y swift-lang
        [[ "$force" == true ]] && "${sudo_cmd[@]}" dnf reinstall -y swift-lang
    else
        doing "Swift $swift_version (swiftly)"
        install_swiftly_toolchain
    fi
    swift_bin="$(find_swift)"
    [[ -n "$swift_bin" ]] || { printf 'Swift 6 is still not available.\n' >&2; exit 1; }
    ok "$("$swift_bin" --version 2>&1 | grep -m1 'Swift version') ($swift_bin)"
fi

printf '== Preview images (rsvg-convert, cwebp) ==\n'
# A főoldali projektkártyák elmosott .webp háttérképe (Sources/ThinkCore/PreviewRaster.swift). Nélkülük a szerver
# az SVG-előnézetet adja (lassabb főoldal), ezért csak figyelmeztetünk.
if command -v rsvg-convert >/dev/null && command -v cwebp >/dev/null; then
    ok "rsvg-convert, cwebp"
elif [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null; then
    doing "librsvg, webp (Homebrew)"
    brew install librsvg webp
else
    printf '  missing  rsvg-convert / cwebp (Fedora: librsvg2-tools libwebp-tools; MacPorts: librsvg webp)\n'
fi

printf '== Node.js and Python ==\n'
if node_ok; then
    ok "node $(node --version)"
elif [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null; then
    doing "node (Homebrew)"
    brew install node
else
    printf '  missing  Node.js 22+ (editor tests). Install it from https://nodejs.org and run this again.\n'
fi
command -v python3 >/dev/null && ok "$(python3 --version)"

printf '== Swift packages (Vapor) ==\n'
if [[ "$force" == true ]]; then
    rm -rf .build
fi
if [[ -d .build/checkouts/vapor ]]; then
    ok "already resolved in server/.build"
else
    # The pins of Package.resolved are kept; a newer Swift (e.g. 6.2+) may add packages its manifests need.
    doing "resolving Package.resolved"
    mkdir -p .build/module-cache .build/package-cache .build/package-config .build/package-security
    CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" "$swift_bin" package \
        --cache-path "$PWD/.build/package-cache" --config-path "$PWD/.build/package-config" \
        --security-path "$PWD/.build/package-security" resolve
fi

printf '\nReady. Next: server/deploy/build.sh, then server/run.sh (see --help of each).\n'
