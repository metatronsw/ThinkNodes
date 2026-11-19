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

command=serve-https
port=""
rate=100
server_args=()
while (( $# )); do
    case "$1" in
        --http) command=serve ;;
        --port:*)
            port="${1#--port:}"
            if [[ ! "$port" =~ ^[1-9][0-9]{0,4}$ ]] || (( port > 65535 )); then
                printf '%s\n' 'A --port értéke 1 és 65535 közötti egész szám legyen.' >&2
                exit 1
            fi
            ;;
        --rate:*)
            rate="${1#--rate:}"
            if [[ ! "$rate" =~ ^[1-9][0-9]{0,8}$ ]]; then
                printf '%s\n' 'A --rate értéke pozitív egész szám legyen milliszekundumban (legfeljebb 9 számjegy).' >&2
                exit 1
            fi
            ;;
        --https)
            printf '%s\n' 'A HTTPS alapértelmezett. Indítsd a ./run.sh parancsot.' >&2
            exit 1
            ;;
        --)
            shift
            server_args+=("$@")
            break
            ;;
        *) server_args+=("$1") ;;
    esac
    shift
done
export THINKNODES_MOTION_RATE="$rate"

if [[ ! -x "$executable" || ( -z "${THINKNODES_EXECUTABLE:-}" && Sources/ThinkNodes/Server.swift -nt "$executable" ) ]]; then
    if [[ ! -x "$swift_bin" ]]; then
        printf '%s\n' 'A Swift nem található. A THINKNODES_SWIFT változóban megadható a swift futtatható fájl.' >&2
        exit 1
    fi
    ./build.sh --skip-update -j 2
fi

if [[ "$command" == serve ]]; then
    exec "$executable" serve --hostname "${THINKNODES_HOST:-127.0.0.1}" --port "${port:-${THINKNODES_PORT:-8080}}" ${server_args[@]+"${server_args[@]}"}
fi

bind_host="${THINKNODES_HOST:-0.0.0.0}"
port="${port:-${THINKNODES_PORT:-8443}}"
addresses=(localhost 127.0.0.1)
if [[ "$bind_host" == 0.0.0.0 || "$bind_host" == :: ]]; then
    if [[ "$(uname -s)" == Darwin ]]; then
        local_name="$(scutil --get LocalHostName 2>/dev/null || true)"
        [[ -z "$local_name" ]] || addresses+=("$local_name.local")
        lan_ips="$(/sbin/ifconfig | awk '$1 == "inet" && $2 !~ /^(127[.]|169[.]254[.])/ {print $2}')"
    else
        lan_ips="$(hostname -I 2>/dev/null || true)"
    fi
    for ip in $lan_ips; do
        [[ "$ip" == *:* ]] || addresses+=("$ip")
    done
    [[ "$bind_host" != :: ]] || addresses+=("::1")
else
    addresses+=("$bind_host")
fi

# Publish files only after OpenSSL has finished writing them. Parallel starts
# use the same CA and keys, including when both processes run for the first time.
generate_lan_certificate() (
    set -e
    umask 077
    mkdir -p "$tls_dir"
    work="$(mktemp -d "$tls_dir/.issue.XXXXXXXX")"
    trap 'rm -rf -- "$work"' EXIT
    for key in ca server; do
        if [[ ! -f "$tls_dir/$key.key" ]]; then
            openssl genrsa -out "$work/$key.key" 2048
            ln "$work/$key.key" "$tls_dir/$key.key" 2>/dev/null || [[ -f "$tls_dir/$key.key" ]]
        fi
    done
    if [[ ! -f "$tls_dir/ca.crt" ]]; then
        openssl req -new -x509 -sha256 -days 3650 -key "$tls_dir/ca.key" -out "$work/ca.crt" \
            -subj "/CN=ThinkNodes LAN CA" -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
            -addext "keyUsage=critical,keyCertSign,cRLSign"
        ln "$work/ca.crt" "$tls_dir/ca.crt" 2>/dev/null || [[ -f "$tls_dir/ca.crt" ]]
    fi
    openssl req -new -sha256 -key "$tls_dir/server.key" -subj "/CN=ThinkNodes LAN" -out "$work/server.csr"
    printf '%s\n' "basicConstraints=critical,CA:FALSE" "keyUsage=critical,digitalSignature,keyEncipherment" \
        "extendedKeyUsage=serverAuth" "subjectAltName=$san" > "$work/server.ext"
    openssl x509 -req -sha256 -days 90 -in "$work/server.csr" -CA "$tls_dir/ca.crt" -CAkey "$tls_dir/ca.key" \
        -set_serial "0x$(openssl rand -hex 16)" -extfile "$work/server.ext" -out "$work/server.crt"
    mv -f "$work/server.crt" "$THINKNODES_TLS_CERT"
)

if [[ -z "${THINKNODES_TLS_CERT:-}" && -z "${THINKNODES_TLS_KEY:-}" ]]; then
    tls_dir="${THINKNODES_TLS_DIR:-.thinknodes-tls}"
    san=""
    for address in "${addresses[@]}"; do
        if [[ "$address" =~ ^[0-9]+([.][0-9]+){3}$ || "$address" =~ ^[0-9A-Fa-f:]*:[0-9A-Fa-f:]*$ ]]; then
            entry="IP:$address"
        elif [[ "$address" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
            entry="DNS:$address"
        else
            printf 'Érvénytelen TLS-gépnév vagy IP-cím: %s\n' "$address" >&2
            exit 1
        fi
        san="${san:+$san,}$entry"
    done
    # Different bind addresses may be served concurrently from this checkout.
    cert_id="$(printf '%s' "$san" | cksum | awk '{print $1}')"
    export THINKNODES_TLS_CERT="$tls_dir/server-$cert_id.crt" THINKNODES_TLS_KEY="$tls_dir/server.key"
    generate_lan_certificate
    printf 'A klienseszközökön megbízható gyökértanúsítványként telepítendő: %s/ca.crt\n' "$tls_dir"
elif [[ ! -r "${THINKNODES_TLS_CERT:-}" || ! -r "${THINKNODES_TLS_KEY:-}" ]]; then
    printf '%s\n' 'A THINKNODES_TLS_CERT és a THINKNODES_TLS_KEY olvasható PEM-fájlokra mutasson.' >&2
    exit 1
fi

for address in "${addresses[@]}"; do
    if [[ "$bind_host" != 0.0.0.0 && "$bind_host" != :: && "$address" != "$bind_host" ]]; then continue; fi
    [[ "$address" != *:* ]] || address="[$address]"
    printf 'HTTPS-cím: https://%s:%s/\n' "$address" "$port"
done
exec "$executable" serve-https --hostname "$bind_host" --port "$port" ${server_args[@]+"${server_args[@]}"}
