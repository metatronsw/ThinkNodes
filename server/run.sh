#!/usr/bin/env bash
# Start the ThinkNodes server, locally or in production.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: server/run.sh [--update] [--debug] [server options]

Starts the ThinkNodes server (server/thinknodes). Every option it does not handle itself
is passed to the binary, so ./thinknodes accepts the same server options.

Before starting it lists the ThinkNodes servers already running on this machine (any user,
e.g. the systemd service), and stops if the port is taken or another server uses the same
data folder. A test server can run next to the service on another port and data folder.
Relative paths (--project:, --tls-*) are relative to the folder you start from.

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

# Relative paths in the options are meant relative to the caller's folder, but the server starts in server/.
caller_dir="$PWD"
absolute_option() {
    local argument=$1 name value
    case "$argument" in
        --project[:=]*|--tls-dir[:=]*|--tls-cert[:=]*|--tls-key[:=]*) ;;
        *) printf '%s\n' "$argument"; return ;;
    esac
    name="${argument%%[:=]*}"
    value="${argument#"$name"?}"
    case "$value" in
        "~") value="$HOME" ;;
        "~/"*) value="$HOME/${value#"~/"}" ;;
        /*|"") ;;
        *) value="$caller_dir/$value" ;;
    esac
    printf '%s:%s\n' "$name" "$value"
}

cd "$(dirname "$0")"

update=false
configuration=release
server_args=()
while (($#)); do
    case "$1" in
        --update) update=true ;;
        --debug) configuration=debug ;;
        --project[:=]*|--tls-dir[:=]*|--tls-cert[:=]*|--tls-key[:=]*) server_args+=("$(absolute_option "$1")") ;;
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
[[ "${server_args[0]:-}" == user ]] && exec "$binary" "${server_args[@]}"

# --- Running instances ---------------------------------------------------------------------
# Every ThinkNodes server on this machine is listed, whoever runs it (e.g. the systemd service
# as user thinknodes next to a local test server). Starting stops if the port is taken or
# another instance uses the same data folder (one server per data folder).

# Value of --NAME:VALUE / --NAME=VALUE in the given arguments (Vapor arguments after -- are ignored).
option_value() {
    local name=$1 argument; shift
    for argument in "$@"; do
        case "$argument" in
            --) return ;;
            "$name":*|"$name"=*) printf '%s\n' "${argument#"$name"?}"; return ;;
        esac
    done
}
has_flag() {
    local name=$1 argument; shift
    for argument in "$@"; do
        [[ "$argument" == -- ]] && return 1
        [[ "$argument" == "$name" ]] && return 0
    done
    return 1
}
effective_port() {
    local port
    port="$(option_value --port "$@")"
    if [[ -n "$port" ]]; then printf '%s\n' "$port"
    elif has_flag --http "$@"; then echo 80
    else echo 443; fi
}
# Existing folder → physical path; otherwise the path as given.
normalized() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"; }
# Working folder of a process (needs the same user or root; empty if unknown).
process_dir() {
    if [[ -e "/proc/$1/cwd" ]]; then readlink "/proc/$1/cwd" 2>/dev/null
    elif command -v lsof >/dev/null; then lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
    fi
}
# Data folder of a server: --project (made absolute by run.sh), or ../projects next to the server folder.
data_folder() {
    local working=$1 executable=$2 project folder; shift 2
    project="$(option_value --project "$@")"
    case "$project" in
        /*) normalized "$project"; return ;;
        "") ;;
        *) [[ -n "$working" ]] && normalized "$working/$project" || printf '%s (relative)\n' "$project"; return ;;
    esac
    [[ "$executable" == /* ]] || { [[ -n "$working" ]] || { echo "?"; return; }; executable="$working/$executable"; }
    folder="$(dirname "$executable")"
    [[ "$folder" == */.build/* ]] && folder="${folder%%/.build/*}"
    normalized "$folder/../projects"
}

service_pid=""
command -v systemctl >/dev/null && service_pid="$(systemctl show -p MainPID --value thinknodes 2>/dev/null || true)"

my_port="$(effective_port ${server_args[@]+"${server_args[@]}"})"
my_data="$(data_folder "$PWD" "$binary" ${server_args[@]+"${server_args[@]}"})"
port_owner="" data_owner="" listed=0
while read -r pid user args; do
    [[ -z "$pid" ]] && continue
    read -r -a words <<<"$args"
    # ${…##*/} a basename helyett: a "-bash"-hez hasonló (kötőjellel kezdődő) folyamatnevet a basename kapcsolónak venné.
    [[ "${words[0]##*/}" == thinknodes ]] || continue
    [[ "${words[1]:-}" == user || "${words[1]:-}" == --help || "${words[1]:-}" == -h ]] && continue
    port="$(effective_port "${words[@]:1}")"
    data="$(data_folder "$(process_dir "$pid")" "${words[0]}" "${words[@]:1}")"
    if ((listed == 0)); then echo "Running ThinkNodes servers:"; listed=1; fi
    printf '  PID %-7s %-12s port %-6s data %s%s\n' "$pid" "$user" "$port" "$data" \
        "$([[ "$pid" == "$service_pid" ]] && echo '  [systemd: thinknodes.service]')"
    [[ "$port" == "$my_port" && -z "$port_owner" ]] && port_owner="$pid ($user)"
    [[ "$data" == "$my_data" && -z "$data_owner" ]] && data_owner="$pid ($user)"
done < <(ps -eo pid=,user=,args= 2>/dev/null)

host="$(option_value --host ${server_args[@]+"${server_args[@]}"})"
[[ -z "$host" || "$host" == 0.0.0.0 || "$host" == "::" ]] && host=127.0.0.1
if [[ -n "$port_owner" ]] || (exec 3<>"/dev/tcp/$host/$my_port") 2>/dev/null; then
    if [[ -n "$port_owner" ]]; then
        printf 'Port %s is already used by ThinkNodes PID %s.\n' "$my_port" "$port_owner" >&2
    else
        printf 'Port %s is already in use by another program.\n' "$my_port" >&2
        command -v lsof >/dev/null && lsof -nP -iTCP:"$my_port" -sTCP:LISTEN 2>/dev/null | sed 's/^/  /' >&2
    fi
    printf 'Stop it, or start this server on another port, e.g. --port:%s.\n' "$((my_port == 443 ? 8443 : my_port + 1))" >&2
    exit 1
fi
if [[ -n "$data_owner" ]]; then
    printf 'Data folder %s is already used by ThinkNodes PID %s; one server per data folder.\n' "$my_data" "$data_owner" >&2
    printf 'Use another folder with --project:DIR (e.g. a copy for testing).\n' >&2
    exit 1
fi
exec "$binary" ${server_args[@]+"${server_args[@]}"}
