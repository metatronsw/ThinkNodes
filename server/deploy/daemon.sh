#!/usr/bin/env bash
# Set up ThinkNodes as a systemd service on a Fedora server.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: sudo server/deploy/daemon.sh [--dir:PATH] [--help]

Sets up ThinkNodes as a systemd service on Fedora Linux:
  - creates the 'thinknodes' system user
  - creates the data folders /var/lib/thinknodes/Projects and /var/lib/thinknodes/tls
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

swift_bin="${THINKNODES_SWIFT:-}"
for candidate in /usr/local/bin/swift "$(command -v swift || true)"; do
    [[ -z "$swift_bin" && -n "$candidate" && -x "$candidate" ]] && swift_bin="$candidate"
done
if [[ -z "$swift_bin" ]]; then
    printf 'Swift 6 not found for all users. Run server/deploy/install.sh first.\n' >&2
    exit 1
fi

printf '== User and folders ==\n'
id thinknodes >/dev/null 2>&1 ||
    useradd --system --home-dir "$data_dir" --create-home --shell /sbin/nologin thinknodes
install -d -o thinknodes -g thinknodes -m 0750 "$data_dir" "$data_dir/Projects"
install -d -o thinknodes -g thinknodes -m 0700 "$data_dir/tls"

printf '== Checkout: %s ==\n' "$install_dir"
if [[ ! -d "$install_dir/.git" ]]; then
    git clone "$(git -C "$source_dir" remote get-url origin)" "$install_dir"
fi
chown -R thinknodes:thinknodes "$install_dir"

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

cat <<EOF

ThinkNodes runs as a systemd service (HTTPS, port 443).
  Data:          $data_dir/Projects
  Certificates:  $data_dir/tls (trust ca.crt on client devices, or use your own: --tls-cert:/--tls-key: in $unit)

Admin account:   sudo runuser -u thinknodes -- $install_dir/server/run.sh user admin admin --project:$data_dir/Projects
Update:          sudo runuser -u thinknodes -- env THINKNODES_SWIFT=$swift_bin $install_dir/server/deploy/build.sh
                 sudo systemctl restart thinknodes
Logs:            sudo journalctl -u thinknodes -f
Stop / start:    sudo systemctl stop thinknodes / sudo systemctl start thinknodes
EOF
