#!/usr/bin/env bash
# ThinkNodes telepítése / frissítése Fedora szerverre.
#
# Futtatás a checkoutból (rootként vagy sudo-val):
#   sudo ./deploy/install.sh            # függőségek, felhasználó, build, systemd szolgáltatás
#   sudo ./deploy/install.sh --no-service   # csak függőségek és build
#
# Környezet:
#   THINKNODES_SWIFT   Swift 6 futtatható fájl (alapértelmezés: swift a PATH-ból)
#   THINKNODES_DIR     telepítési mappa (alapértelmezés: /opt/ThinkNodes)
set -euo pipefail

source_dir="$(cd "$(dirname "$0")/.." && pwd)"
install_dir="${THINKNODES_DIR:-/opt/ThinkNodes}"
data_dir=/var/lib/thinknodes
service=true
[[ "${1:-}" == "--no-service" ]] && service=false

if [[ "$(uname -s)" != Linux || ! -f /etc/fedora-release ]]; then
    printf '%s\n' 'Ez a szkript Fedora Linuxra készült.' >&2
    exit 1
fi
if [[ $EUID -ne 0 ]]; then
    printf '%s\n' 'Rootként futtasd: sudo ./deploy/install.sh' >&2
    exit 1
fi

printf '\n== Rendszercsomagok ==\n'
# Swift build- és futási függőségek, a .web ZIP-feltöltéshez az unzip,
# az előnézeti képek generálásához a headless Chromium.
dnf install -y \
    git curl unzip tar gzip openssl \
    binutils gcc gcc-c++ glibc-devel glibc-static libstdc++-devel libstdc++-static \
    libcurl-devel libxml2-devel libuuid-devel libedit-devel sqlite-devel zlib-devel libicu tzdata \
    chromium-headless

swift_bin="${THINKNODES_SWIFT:-$(command -v swift || true)}"
if [[ -z "$swift_bin" ]] && dnf list --available swift-lang >/dev/null 2>&1; then
    dnf install -y swift-lang
    swift_bin="$(command -v swift || true)"
fi
if [[ -z "$swift_bin" ]] || ! "$swift_bin" --version 2>/dev/null | grep -Eq 'Swift version (6|[7-9])\.'; then
    cat >&2 <<'EOF'
Swift 6 toolchain nem található (a Fedora swift-lang csomag lehet régebbi).
Telepítsd a swiftly-vel, majd futtasd újra a THINKNODES_SWIFT változóval:
  curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
  tar zxf swiftly-$(uname -m).tar.gz && ./swiftly init --quiet-shell-followup
  swiftly install 6.0.3
  sudo THINKNODES_SWIFT=$(swiftly use --print-location)/usr/bin/swift ./deploy/install.sh
EOF
    exit 1
fi
printf 'Swift: %s\n' "$("$swift_bin" --version | head -1)"

chromium=""
for candidate in /usr/lib64/chromium-browser/headless_shell /usr/bin/chromium-browser /usr/bin/chromium; do
    [[ -x "$candidate" ]] && { chromium="$candidate"; break; }
done
printf 'Chromium (előnézet): %s\n' "${chromium:-nem található – helyettes képek lesznek}"

printf '\n== Felhasználó és mappák ==\n'
id thinknodes >/dev/null 2>&1 ||
    useradd --system --home-dir "$data_dir" --create-home --shell /sbin/nologin thinknodes
install -d -o thinknodes -g thinknodes "$data_dir" "$data_dir/Projects" "$data_dir/tls"
if [[ "$source_dir" != "$install_dir" ]]; then
    if [[ ! -d "$install_dir/.git" ]]; then
        git clone "$source_dir" "$install_dir"
        git -C "$install_dir" remote set-url origin "$(git -C "$source_dir" remote get-url origin)"
    fi
fi
chown -R thinknodes:thinknodes "$install_dir"

printf '\n== Build ==\n'
runuser -u thinknodes -- env HOME="$data_dir" THINKNODES_SWIFT="$swift_bin" "$install_dir/build-fedora.sh"

if [[ "$service" == true ]]; then
    printf '\n== Szolgáltatás ==\n'
    install -m 0644 "$install_dir/deploy/thinknodes.service" /etc/systemd/system/thinknodes.service
    mkdir -p /etc/systemd/system/thinknodes.service.d
    {
        printf '[Service]\n'
        printf 'Environment=THINKNODES_SWIFT=%s\n' "$swift_bin"
        [[ -n "$chromium" ]] && printf 'Environment=THINKNODES_CHROMIUM=%s\n' "$chromium"
    } > /etc/systemd/system/thinknodes.service.d/install.conf
    systemctl daemon-reload
    systemctl enable thinknodes
    systemctl restart thinknodes
    systemctl --no-pager status thinknodes || true
    printf '\nNapló: sudo journalctl -u thinknodes -f\n'
fi
printf '\nKész.\n'
