#!/usr/bin/env bash
# Start the ThinkNodes server, locally or in production.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: server/run.sh [--update] [--debug] [server options]

Starts the ThinkNodes server (server/thinknodes). Every option it does not handle itself
is passed to the binary, so ./thinknodes accepts the same server options.

Run script options:
  --update          Update from GitHub and build first (deploy/build.sh).
  --debug           Use the debug build (.build/debug/thinknodes); with --update, build it.
  --help            Show this help and the server options.

Server options (most used):
  --test            Every connecting browser gets admin rights. Local testing only.
  --http            Plain HTTP instead of HTTPS.
  --port:N          Port (default 443, or 80 with --http).
  --rate:MS         Drag update interval in ms (default 33).
  --project:DIR     Project data folder (default ../projects).

Examples:
  ./run.sh --http --port:8888 --test       local test server
  ./run.sh --update                        update, build, start with HTTPS on port 443
  ./run.sh user admin admin                create an admin account (asks for the password)
EOF
}

cd "$(dirname "$0")"

update=false
configuration=release
server_args=()
while (($#)); do
    case "$1" in
        --update) update=true ;;
        --debug) configuration=debug ;;
        -h|--help)
            usage
            for binary in ./thinknodes .build/debug/thinknodes; do
                if [[ -x "$binary" ]]; then printf '\nAll server options (%s --help):\n\n' "$binary"; "$binary" --help; break; fi
            done
            exit 0 ;;
        --) server_args+=("$@"); break ;;
        *) server_args+=("$1") ;;
    esac
    shift
done

build_args=()
[[ "$configuration" == debug ]] && build_args+=(--debug)
if [[ "$update" == true ]]; then
    ./deploy/build.sh ${build_args[@]+"${build_args[@]}"}
fi

binary=./thinknodes
[[ "$configuration" == debug ]] && binary=.build/debug/thinknodes
if [[ ! -x "$binary" ]]; then
    printf 'Not built yet: %s. Run ./run.sh --update or deploy/build.sh%s.\n' "$binary" \
        "$([[ "$configuration" == debug ]] && echo ' --debug')" >&2
    exit 1
fi

if [[ -t 0 && "${server_args[0]:-}" == user ]]; then
    read -r -s -p 'Password: ' password
    printf '\n' >&2
    printf '%s\n' "$password" | "$binary" "${server_args[@]}"
    exit
fi
exec "$binary" ${server_args[@]+"${server_args[@]}"}
