#!/usr/bin/env bash
# Check and install everything needed to develop, build and run ThinkNodes.
set -Eeuo pipefail
# Váratlan kilépésnél a hely kiírása (különben a set -e szó nélkül állna meg).
trap 'printf "install.sh: stopped at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

usage() {
    cat <<'EOF'
Usage: server/deploy/install.sh [--force] [--help]

Checks the development and runtime environment of ThinkNodes and installs what is missing:
  - system tools and libraries (git, curl, unzip, compilers and libraries Swift needs on Linux)
  - Swift, version from server/deploy/swift.env (Linux: the official swift.org toolchain in
    /opt/swift-<version>, signature checked, then tested against the system C++ headers;
    macOS: Xcode Command Line Tools + swiftly). Fedora's own swift-lang may stay installed, it is
    not used.
  - Node.js 22+ (editor tests) and Python 3 (tools/)
  - headless Chromium on Fedora (web presentation previews)
  - the Swift packages of the server (Vapor and its dependencies), resolved into server/.build
Anything already present is left alone.

Options:
  --force     Reinstall everything, even what is already present.
  --help      Show this help.

Environment:
  THINKNODES_SWIFT   Use this Swift executable instead of searching for one (any version: your choice).
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
# A Swift-verziók egy helyen: deploy/swift.env (SWIFT_LINUX, SWIFT_LINUX_PLATFORM, SWIFT_MACOS, SWIFT_RELEASE_KEY).
source deploy/swift.env
if [[ "$(uname -s)" == Linux ]]; then swift_version="$SWIFT_LINUX"; else swift_version="$SWIFT_MACOS"; fi
ok() { printf '  ok       %s\n' "$*"; }
doing() { printf '  install  %s\n' "$*"; }

sudo_cmd=()
[[ $EUID -ne 0 ]] && sudo_cmd=(sudo)

# A deploy/swift.env szerinti Swift (Linuxon a swift.org toolchainje a /opt/swift-<verzió> mappában); THINKNODES_SWIFT-tel
# bármelyik megadható.
linux_swift_dir=/opt/swift-$swift_version
find_swift() {
    local candidate
    if [[ -n "${THINKNODES_SWIFT:-}" ]]; then
        [[ -x "$THINKNODES_SWIFT" ]] && printf '%s\n' "$THINKNODES_SWIFT"
        return
    fi
    for candidate in "$HOME/X-Code/RunTime/Swift/$swift_version/usr/bin/swift" "$linux_swift_dir/usr/bin/swift" \
                     "$HOME/.swiftly/bin/swift" "$HOME/.local/share/swiftly/bin/swift" "$(command -v swift || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]] &&
            "$candidate" --version 2>/dev/null | grep -q "Swift version $swift_version "; then
            printf '%s\n' "$candidate"
            return
        fi
    done
}

install_linux_toolchain() {
    # A swift.org hivatalos csomagja (deploy/swift.env: verzió és platform), aláírás-ellenőrzéssel, rendszerszinten (/opt),
    # hogy a thinknodes szolgáltatás-felhasználó is használhassa.
    local work arch platform name url
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' RETURN
    arch="$(uname -m)"
    platform="$SWIFT_LINUX_PLATFORM"
    [[ "$arch" == aarch64 ]] && platform="$SWIFT_LINUX_PLATFORM-aarch64"
    name="swift-$swift_version-RELEASE-$platform"
    url="https://download.swift.org/swift-$swift_version-release/$platform/swift-$swift_version-RELEASE/$name.tar.gz"
    curl --fail --location --silent --show-error -o "$work/$name.tar.gz" "$url"
    curl --fail --location --silent --show-error -o "$work/$name.tar.gz.sig" "$url.sig"
    # A Swift release kulcsa (deploy/swift.env, https://swift.org/keys/active/): csak az ezzel az ujjlenyomattal aláírt csomag
    # fogadható el. A kulcs a swift.org fájljából, ha onnan nem jön meg, kulcsszerverről; a hitelességet az ujjlenyomat adja.
    local release_key="$SWIFT_RELEASE_KEY" keys_url
    printf '  download https://download.swift.org/…/%s.tar.gz\n' "$name"
    mkdir -m 0700 "$work/gnupg"
    for keys_url in https://www.swift.org/keys/release-key-swift-6.x.asc https://swift.org/keys/release-key-swift-6.x.asc \
                    https://swift.org/keys/all-keys.asc; do
        curl --fail --location --silent -o "$work/keys.asc" "$keys_url" || continue
        GNUPGHOME="$work/gnupg" gpg --batch --import "$work/keys.asc" >>"$work/import.log" 2>&1 || true
        GNUPGHOME="$work/gnupg" gpg --batch --list-keys "$release_key" >/dev/null 2>&1 && break
    done
    if ! GNUPGHOME="$work/gnupg" gpg --batch --list-keys "$release_key" >/dev/null 2>&1; then
        GNUPGHOME="$work/gnupg" gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$release_key" >>"$work/import.log" 2>&1 || true
    fi
    GNUPGHOME="$work/gnupg" gpg --batch --status-fd 1 --verify "$work/$name.tar.gz.sig" "$work/$name.tar.gz" >"$work/verify.log" 2>&1 || true
    if ! grep -q "^\[GNUPG:\] VALIDSIG .*$release_key" "$work/verify.log"; then
        cat "$work/import.log" "$work/verify.log" >&2
        printf 'The signature of %s could not be verified with the Swift 6.x release key %s (%s).\n' "$name.tar.gz" "$release_key" "$url" >&2
        exit 1
    fi
    printf '  ok       signature (Swift release key %s)\n' "$release_key"
    "${sudo_cmd[@]}" rm -rf "$linux_swift_dir"
    "${sudo_cmd[@]}" mkdir -p "$linux_swift_dir"
    "${sudo_cmd[@]}" tar -xzf "$work/$name.tar.gz" -C "$linux_swift_dir" --strip-components=1
}

node_ok() {
    [[ -f "$HOME/X-Code/RunTime/NodeJS/env.sh" ]] && source "$HOME/X-Code/RunTime/NodeJS/env.sh"
    command -v node >/dev/null && [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]]
}

# A toolchain beépített clangja lefordítja-e a rendszer C++ fejléceit (a swift-crypto BoringSSL-je C++): a túl régi clang
# az újabb GCC fejléceinél elakad (Fedora 45 / GCC 16 és Swift 6.0.3). Linuxon fut.
check_cxx_headers() {
    local clang
    clang="$(dirname "$1")/clang++"
    [[ -x "$clang" ]] || return 0
    printf '#include <memory>\n#include <string>\n#include <system_error>\nint main() { return 0; }\n' |
        "$clang" -fsyntax-only -x c++ - 2>"${TMPDIR:-/tmp}/thinknodes-cxx-check.log"
}

install_swiftly_toolchain() {
    # macOS: swiftly és Swift $swift_version a felhasználó saját könyvtárában (Linuxon: install_linux_toolchain).
    local work
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' RETURN
    curl --fail --location --silent --show-error -o "$work/swiftly.pkg" https://download.swift.org/swiftly/darwin/swiftly.pkg
    installer -pkg "$work/swiftly.pkg" -target CurrentUserHomeDirectory
    "$HOME/.swiftly/bin/swiftly" init --quiet-shell-followup --assume-yes --skip-install
    "$HOME/.swiftly/bin/swiftly" install "$swift_version" --use --assume-yes
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
    packages=(git curl unzip tar gzip gnupg2 python3 nodejs
              binutils gcc gcc-c++ glibc-devel glibc-static libstdc++-devel libstdc++-static
              libcurl-devel libxml2-devel libuuid-devel libedit-devel sqlite-devel zlib-devel libicu tzdata
              chromium-headless
              librsvg2-tools libwebp-tools)  # főoldali előnézeti képek: rsvg-convert, cwebp (PreviewRaster.swift)
    missing=()
    for package in "${packages[@]}"; do
        # --whatprovides: a csomagot más is adhatja (pl. zlib-devel → zlib-ng-compat-devel).
        rpm -q --whatprovides "$package" >/dev/null 2>&1 && [[ "$force" == false ]] || missing+=("$package")
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
    if [[ "$(uname -s)" == Linux ]]; then
        doing "Swift $swift_version (swift.org, $linux_swift_dir)"
        install_linux_toolchain
    else
        doing "Swift $swift_version (swiftly)"
        install_swiftly_toolchain
    fi
    swift_bin="$(find_swift)"
    [[ -n "$swift_bin" ]] || { printf 'Swift %s is still not available.\n' "$swift_version" >&2; exit 1; }
    ok "$("$swift_bin" --version 2>&1 | grep -m1 'Swift version') ($swift_bin)"
fi
if [[ "$(uname -s)" == Linux ]]; then
    if check_cxx_headers "$swift_bin"; then
        ok "C++ headers of the system compile with this Swift's clang"
    else
        head -5 "${TMPDIR:-/tmp}/thinknodes-cxx-check.log" >&2
        printf '\nThe clang of Swift %s cannot compile the C++ headers of this system (gcc %s).\n' \
            "$swift_version" "$(gcc -dumpversion 2>/dev/null || echo '?')" >&2
        printf 'Set a newer SWIFT_LINUX (and SWIFT_LINUX_PLATFORM) in server/deploy/swift.env, then run install.sh again.\n' >&2
        printf 'Versions: https://www.swift.org/install/linux/\n' >&2
        exit 1
    fi
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
# Root-ként futtatva a SwiftPM zárfájljai (/tmp/<a .build útvonala, / helyett _>*.lock) a root tulajdonában maradnának,
# és a thinknodes felhasználóként futó build nem férne hozzájuk.
if [[ $EUID -eq 0 && "$(uname -s)" == Linux ]]; then
    rm -f "/tmp/$(printf '%s' "$PWD/.build" | tr '/' '_')"*.lock
fi

printf '\nReady. Next: server/deploy/build.sh, then server/run.sh (see --help of each).\n'
