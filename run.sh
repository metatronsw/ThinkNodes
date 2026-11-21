#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

show_help() {
    cat <<'EOF'
ThinkNodes indítása

Használat:
  ./run.sh [kapcsolók] [-- Vapor-argumentumok]
  ./run.sh user [Vapor-argumentumok]

Kapcsolók:
  -h, --help       Súgó megjelenítése kilépés előtt
  --debug          Debug build használata (alapból release)
  --http           HTTP indítása HTTPS helyett (alap port: 80)
  --local          Helyi/LAN tesztmód: debug build, HTTP, nem biztonságos
                   cookie-k; macOS-en 1024 alatti porthoz sudo-t kérhet
  --port:PORT      Port beállítása (1–65535); pl. --port:8080
  --rate:MS        Mozgásfrissítési időköz milliszekundumban (pozitív egész,
                   alapérték: 33); pl. --rate:50
  --test           Tesztmód: minden csatlakozó adminisztrátori jogot kap
  --https          Elutasítva, mert a HTTPS az alapértelmezett mód
  --               A további argumentumok változtatás nélkül a Vaporhoz kerülnek

Példák:
  ./run.sh
  ./run.sh --debug
  ./run.sh --local --port:8080
  ./run.sh --http --port:8080
  ./run.sh --rate:50 -- --help
  ./run.sh user create

Környezeti változók:
  THINKNODES_CONFIGURATION  Buildkonfiguráció (release vagy debug)
  THINKNODES_PORT           Alapértelmezett port felülírása
  THINKNODES_HOST           Figyelési cím (alapból: 0.0.0.0)
  THINKNODES_SWIFT          Swift futtatható fájl elérési útja
  THINKNODES_EXECUTABLE     Előre lefordított futtatható fájl elérési útja
  THINKNODES_TLS_CERT       Saját TLS tanúsítvány PEM fájlja
  THINKNODES_TLS_KEY        Saját TLS kulcs PEM fájlja
  THINKNODES_TLS_DIR        Automatikus TLS fájlok mappája
  THINKNODES_DATA           Projektadatok mappája (alapból: Projects)

Git checkout esetén indítás előtt megpróbálja gyors előre léptetéssel
frissíteni az aktuális ágat a GitHubról.
EOF
}

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
    show_help
    exit 0
fi

# Run the updated launcher too, preserving the original arguments.
update_checkout() {
    local branch previous
    branch="$(git symbolic-ref --quiet --short HEAD)" || {
        echo 'Frissítés kihagyva: nincs aktív Git-ág.' >&2
        return
    }
    if ! GIT_TERMINAL_PROMPT=0 git fetch --no-tags origin "refs/heads/$branch"; then
        echo 'A frissítés letöltése sikertelen. A helyi verzió indul.' >&2
        return
    fi
    previous="$(git rev-parse HEAD)"
    if ! git -c merge.autoStash=false merge --ff-only FETCH_HEAD; then
        echo 'A frissítés ütközik a helyi állapottal. A helyi verzió indul.' >&2
        return
    fi
    if [[ "$(git rev-parse HEAD)" != "$previous" ]]; then
        THINKNODES_UPDATED_HEAD="$(git rev-parse HEAD)" exec ./run.sh "$@"
    fi
}

checkout_head=""
if [[ -e .git ]]; then
    checkout_head="$(git rev-parse HEAD)"
    if [[ "${THINKNODES_UPDATED_HEAD:-}" != "$checkout_head" ]]; then
        update_checkout "$@"
    fi
    unset THINKNODES_UPDATED_HEAD
fi

command=serve-https
if [[ "${1:-}" == user ]]; then command=user; fi
configuration="${THINKNODES_CONFIGURATION:-release}"
port=""
rate=33
test_mode=0
local_mode=0
server_args=()
while [[ "$command" != user ]] && (( $# )); do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        --debug) configuration=debug ;;
        --test) test_mode=1 ;;
        --http) command=serve ;;
        --local)
            local_mode=1
            command=serve
            configuration=debug
            ;;
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
swift_bin="${THINKNODES_SWIFT:-$HOME/X-Code/Swift/6.0.3/usr/bin/swift}"
if [[ ! -x "$swift_bin" && -z "${THINKNODES_SWIFT:-}" ]]; then
    swift_bin="$(command -v swift || true)"
fi
export THINKNODES_CONFIGURATION="$configuration"
executable="${THINKNODES_EXECUTABLE:-.build/$configuration/ThinkNodes}"

if [[ -n "${THINKNODES_EXECUTABLE:-}" && ! -x "$executable" ]]; then
    printf 'A kiválasztott fájl nem futtatható: %s\n' "$executable" >&2
    exit 1
fi

build_stamp=".build/$configuration/.thinknodes-built-head"
if [[ ! -x "$executable" || ( -z "${THINKNODES_EXECUTABLE:-}" && ( Sources/ThinkNodes/Server.swift -nt "$executable" ||
        ( -n "$checkout_head" && "$(cat "$build_stamp" 2>/dev/null || true)" != "$checkout_head" ) ) ) ]]; then
    if [[ ! -x "$swift_bin" ]]; then
        printf '%s\n' 'A Swift nem található. A THINKNODES_SWIFT változóban megadható a swift futtatható fájl.' >&2
        exit 1
    fi
    build_jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || printf '1')"
    if [[ ! "$build_jobs" =~ ^[1-9][0-9]*$ ]]; then build_jobs=1; fi
    printf 'Párhuzamos buildfeladatok: %s\n' "$build_jobs"
    ./build.sh --disable-automatic-resolution -j "$build_jobs"
    if [[ -n "$checkout_head" && -z "${THINKNODES_EXECUTABLE:-}" ]]; then
        printf '%s\n' "$checkout_head" > "$build_stamp"
    fi
fi

if [[ "$command" == user ]]; then
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

export THINKNODES_MOTION_RATE="$rate" THINKNODES_TEST_MODE="$test_mode"
if [[ "$test_mode" == 1 ]]; then echo "Tesztmód: minden csatlakozó adminisztrátori jogot kap."; fi

bind_host="${THINKNODES_HOST:-0.0.0.0}"
default_port=443
if [[ "$command" == serve ]]; then default_port=80; fi
port="${port:-${THINKNODES_PORT:-$default_port}}"
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

if [[ "$command" == serve ]]; then
    if [[ "$bind_host" != 0.0.0.0 && "$bind_host" != :: ]]; then addresses=("$bind_host"); fi
    for address in "${addresses[@]}"; do
        [[ "$address" != *:* ]] || address="[$address]"
        if [[ "$port" != 80 ]]; then address="$address:$port"; fi
        printf 'HTTP-cím: http://%s/\n' "$address"
    done
    if [[ "$local_mode" == 1 ]]; then
        export THINKNODES_SECURE_COOKIES=0
        if [[ "$(uname -s)" == Darwin && "$EUID" != 0 && "$port" =~ ^[0-9]{1,5}$ ]] &&
            (( 10#$port < 1024 )); then
            exec sudo -- /usr/bin/env \
                THINKNODES_DATA="${THINKNODES_DATA:-Projects}" \
                THINKNODES_MOTION_RATE="$rate" THINKNODES_TEST_MODE="$test_mode" THINKNODES_SECURE_COOKIES=0 \
                "$executable" serve --hostname "$bind_host" --port "$port" ${server_args[@]+"${server_args[@]}"}
        fi
    fi
    exec "$executable" serve --hostname "$bind_host" --port "$port" ${server_args[@]+"${server_args[@]}"}
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
