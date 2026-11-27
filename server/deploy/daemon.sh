#!/usr/bin/env bash
# Set up ThinkNodes as a systemd service on a Fedora server.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: sudo server/deploy/daemon.sh [--dir:PATH] [--help]

Sets up ThinkNodes as a systemd service on Fedora Linux:
  - creates the 'thinknodes' system user
  - creates the data folders /var/lib/thinknodes/Projects and /var/lib/thinknodes/tls
  - creates the settings file /var/lib/thinknodes/thinknodes.env if it is missing (an existing one is kept);
    the Google sign-in is switched on there, see server/deploy/GOOGLE.md
  - clones the repository to the install folder (default /opt/ThinkNodes) if it is not there yet
  - builds the release binary as the thinknodes user (deploy/build.sh)
  - installs, enables and (re)starts thinknodes.service (HTTPS on port 443)
and finally prints how to add an admin account, update and follow the logs.
Run server/deploy/install.sh first. Running it again is safe: it only updates what changed.

Options:
  --dir:PATH  Install folder of the checkout (default /opt/ThinkNodes).
  --help      Show this help.
EOF
}

install_dir=/opt/ThinkNodes
while (($#)); do
    case "$1" in
        --dir:*) install_dir="${1#--dir:}" ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s (see --help)\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

if [[ "$(uname -s)" != Linux || ! -f /etc/fedora-release ]]; then
    printf 'This script is for Fedora Linux.\n' >&2
    exit 1
fi
if [[ $EUID -ne 0 ]]; then
    printf 'Run it as root: sudo %s\n' "$0" >&2
    exit 1
fi

source_dir="$(cd "$(dirname "$0")/../.." && pwd)"
data_dir=/var/lib/thinknodes
unit=/etc/systemd/system/thinknodes.service
env_file="$data_dir/thinknodes.env"

# A Swift a deploy/swift.env szerinti swift.org toolchain (install.sh: /opt/swift-<SWIFT_LINUX>); a Fedora swift-lang
# csomagja nem használható. THINKNODES_SWIFT-tel más is megadható.
source "$(dirname "$0")/swift.env"
swift_version="$SWIFT_LINUX"
swift_bin="${THINKNODES_SWIFT:-}"
for candidate in "/opt/swift-$swift_version/usr/bin/swift" /usr/local/bin/swift "$(command -v swift || true)"; do
    if [[ -z "$swift_bin" && -n "$candidate" && -x "$candidate" ]] &&
        "$candidate" --version 2>/dev/null | grep -q "Swift version $swift_version "; then
        swift_bin="$candidate"
    fi
done
if [[ -z "$swift_bin" ]]; then
    printf 'Swift %s not found for all users. Run server/deploy/install.sh first.\n' "$swift_version" >&2
    exit 1
fi

printf '== User and folders ==\n'
id thinknodes >/dev/null 2>&1 ||
    useradd --system --home-dir "$data_dir" --create-home --shell /sbin/nologin thinknodes
install -d -o thinknodes -g thinknodes -m 0750 "$data_dir" "$data_dir/Projects"
install -d -o thinknodes -g thinknodes -m 0700 "$data_dir/tls"
# Settings of the service (secrets): readable by the thinknodes user only. An existing file is never overwritten.
if [[ ! -e "$env_file" ]]; then
    install -o thinknodes -g thinknodes -m 0600 /dev/null "$env_file"
    cat > "$env_file" <<'EOF'
# ThinkNodes service settings, read by systemd at start (NAME=value lines, no quotes, no spaces around =).
# After a change: sudo systemctl restart thinknodes
#
# Google sign-in (server/deploy/GOOGLE.md). Both values are needed; remove the leading # to switch it on.
#THINKNODES_GOOGLE_CLIENT_ID=
#THINKNODES_GOOGLE_CLIENT_SECRET=
# Only if users reach the server at another address than the server sees (e.g. behind a proxy):
#THINKNODES_GOOGLE_REDIRECT=https://example.com/login/google/callback
EOF
fi
chown thinknodes:thinknodes "$env_file"
chmod 0600 "$env_file"

printf '== Checkout: %s ==\n' "$install_dir"
if [[ ! -d "$install_dir/.git" ]]; then
    git clone "$(git -C "$source_dir" remote get-url origin)" "$install_dir"
fi
chown -R thinknodes:thinknodes "$install_dir"
# SwiftPM zárfájljai a /tmp-ben (a .build útvonalából képzett előtaggal: …_.build.lock, …_.build_Package.resolved.lock,
# …_.build_workspace-state.json.lock stb.): ha egy root-ként futtatott install.sh / build hagyta ott, a thinknodes
# felhasználó nem fér hozzájuk („invalid access to /tmp/…lock”).
rm -f "/tmp/$(printf '%s' "$install_dir/server/.build" | tr '/' '_')"*.lock

printf '== Build ==\n'
runuser -u thinknodes -- env HOME="$data_dir" THINKNODES_SWIFT="$swift_bin" "$install_dir/server/deploy/build.sh"

printf '== Service ==\n'
chromium=""
for candidate in /usr/lib64/chromium-browser/headless_shell /usr/bin/chromium-browser /usr/bin/chromium; do
    [[ -x "$candidate" ]] && { chromium="$candidate"; break; }
done
cat > "$unit" <<EOF
[Unit]
Description=ThinkNodes collaboration server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=thinknodes
Group=thinknodes
WorkingDirectory=$install_dir/server
Environment=HOME=$data_dir
${chromium:+Environment=THINKNODES_CHROMIUM=$chromium}
# Settings and secrets, e.g. the Google sign-in (deploy/GOOGLE.md). Kept when daemon.sh runs again.
EnvironmentFile=-$env_file
ExecStart=$install_dir/server/run.sh --project:$data_dir/Projects --tls-dir:$data_dir/tls
Restart=on-failure
RestartSec=5s
TimeoutStopSec=30s

# Runs without root, but may bind the HTTPS port 443.
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$data_dir
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
# Drop-in of the previous installer (Swift path for builds at startup) is no longer used.
rm -f /etc/systemd/system/thinknodes.service.d/install.conf
rmdir /etc/systemd/system/thinknodes.service.d 2>/dev/null || true
systemctl daemon-reload
systemctl enable thinknodes
systemctl restart thinknodes
systemctl --no-pager --lines=5 status thinknodes || true

google_state="off (to switch it on: $install_dir/server/deploy/GOOGLE.md)"
if grep -Eq '^THINKNODES_GOOGLE_CLIENT_ID=.+' "$env_file" && grep -Eq '^THINKNODES_GOOGLE_CLIENT_SECRET=.+' "$env_file"; then
    google_state="on (the log shows 'Google sign-in: enabled' at start)"
fi

cat <<EOF

ThinkNodes runs as a systemd service (HTTPS, port 443).
  Data:          $data_dir/Projects
  Settings:      $env_file
  Google sign-in: $google_state
  Certificates:  $data_dir/tls (trust ca.crt on client devices, or use your own: --tls-cert:/--tls-key: in $unit)

Admin account:   sudo runuser -u thinknodes -- $install_dir/server/run.sh user admin admin --project:$data_dir/Projects
Update:          sudo runuser -u thinknodes -- env THINKNODES_SWIFT=$swift_bin $install_dir/server/deploy/build.sh
                 sudo systemctl restart thinknodes
Logs:            sudo journalctl -u thinknodes -f
Stop / start:    sudo systemctl stop thinknodes / sudo systemctl start thinknodes
EOF
