# Közös rész a deploy szkriptekhez (build.sh, update.sh); source-szal töltődik be, magában nem fut.
#
# run_as_checkout_owner SCRIPT [ARGS...]
#   Linuxon root-ként hívva, ha a checkout nem a rooté (szerveren: thinknodes), a root által korábban ott hagyott
#   fájlokat a tulajdonosnak adja, és a szkriptet a tulajdonos nevében indítja újra (runuser, exec). Így a git és a
#   SwiftPM fájljai (.git, .build) nem kerülnek root tulajdonba. Más esetben nem csinál semmit.

run_as_checkout_owner() {
    [[ "$(uname -s)" == Linux && $EUID -eq 0 ]] || return 0
    local checkout owner group home
    checkout="$(cd "$(dirname "$1")/../.." && pwd)"
    owner="$(stat -c %U "$checkout")"
    [[ "$owner" != root ]] || return 0
    command -v runuser >/dev/null || { printf 'runuser not found: run it as %s.\n' "$owner" >&2; exit 1; }
    group="$(stat -c %G "$checkout")"
    home="$(getent passwd "$owner" | cut -d: -f6)"
    chown -R "$owner:$group" "$checkout"
    printf 'Running as %s (owner of %s)\n' "$owner" "$checkout"
    exec runuser -u "$owner" -- env HOME="${home:-/tmp}" ${THINKNODES_SWIFT:+THINKNODES_SWIFT="$THINKNODES_SWIFT"} "$@"
}
