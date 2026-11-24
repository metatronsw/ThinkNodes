#!/usr/bin/env bash
# Témakörönkénti tesztfuttatás: csak azokat a Swift- és JS-teszteket futtatja, amelyeket a módosítás érint.
set -uo pipefail

usage() {
    cat <<'EOF'
Használat: server/test.sh [KAPCSOLÓK] [TÉMA...]

Téma nélkül a git szerinti módosításokból (commitolatlan + új fájlok) választ témát.

Kapcsolók:
  --all        Minden teszt (Swift és JS).
  --swift      Csak a Swift-tesztek (a választott témákból).
  --js         Csak a JS-tesztek (a választott témákból).
  --since REF  A módosítások a REF óta (pl. HEAD~3, main); alapból a commitolatlan változások.
  --list       Csak kiírja, mit futtatna, és miért.
  --help       Ez a súgó.

Témák:
  table      Táblázatmotor (ThinkTable, Public/table, közös tesztesetek)
  markdown   Vászon-markdown és szövegdobozok
  editor     Szerkesztő (Public/*.js) – gestures.mjs
  render     SVG-renderelés és témák
  worksheet  Munkalapformátum, útvonalak, teljes HTTP-körút
  collab     Közös szerkesztés, munkamenetek
  access     Jogosultságok, jelszavak
  files      Csatolmányok, közös fájlok
  web        .web prezentációk
  package    Projektcsomag (ZIP export/import)
  link       Linkelőnézet
  core       Minden Swift-teszt (Model.swift, Server.swift, Package.swift … módosításakor)

Környezet:
  THINKNODES_SWIFT  Swift 6 (alapból ~/X-Code/RunTime/Swift/6.0.3, swiftly vagy a PATH)
  THINKNODES_NODE   Node.js (alapból a PATH, majd ~/X-Code/RunTime/NodeJS)

A Swift-tesztek mindig debug buildet használnak (release build: deploy/build.sh).
EOF
}

cd "$(dirname "$0")"
server_dir="$PWD"

# --- Témák: tesztfájlok és a hozzájuk tartozó forrásútvonalak -------------------------------
# swift_files: Tests/ThinkNodesTests vagy Tests/ThinkTableTests alatti fájlok; js_files: Tests/Editor alatti fájlok.
declare -A swift_files js_files
swift_files[table]="ThinkTableTests/*.swift"
js_files[table]="table-engine.mjs table-fuzz.mjs"
swift_files[markdown]="ThinkNodesTests/CanvasMarkdownTests.swift ThinkNodesTests/TextNoteTests.swift"
js_files[markdown]="canvas-markdown.mjs"
js_files[editor]="gestures.mjs"
swift_files[render]="ThinkNodesTests/RenderingTests.swift ThinkNodesTests/ThemeTests.swift"
swift_files[worksheet]="ThinkNodesTests/WorksheetTests.swift"
swift_files[collab]="ThinkNodesTests/CollaborationTests.swift"
swift_files[access]="ThinkNodesTests/AccessTests.swift"
swift_files[files]="ThinkNodesTests/AttachmentTests.swift ThinkNodesTests/SharedFilesTests.swift"
swift_files[web]="ThinkNodesTests/WebPresentationTests.swift"
swift_files[package]="ThinkNodesTests/ProjectPackageTests.swift"
swift_files[link]="ThinkNodesTests/LinkPreviewTests.swift"
all_topics="table markdown editor render worksheet collab access files web package link core"

# Módosított fájl (a server/ mappához képest) → témák. Üres eredmény: nincs hozzá teszt (dokumentáció, ikonok…).
topics_for() {
    case "$1" in
        Sources/ThinkTable/*|Public/table/*|Tests/TableFixtures/*|Tests/ThinkTableTests/*|Tests/Editor/table-*) echo table ;;
        Sources/ThinkNodes/TableFiles.swift) echo "table files" ;;
        Sources/ThinkNodes/CanvasMarkdown.swift|Public/canvas-markdown.js|Tests/Fixtures/canvas-markdown.json) echo "markdown editor" ;;
        Tests/Editor/canvas-markdown.mjs|Tests/ThinkNodesTests/CanvasMarkdownTests.swift|Tests/ThinkNodesTests/TextNoteTests.swift) echo markdown ;;
        Tests/Editor/*|Public/*.js) echo editor ;;
        Sources/ThinkNodes/Rendering.swift|Sources/ThinkNodes/Theme.swift|Public/themes/*|docs/theme.schema.json) echo render ;;
        Tests/ThinkNodesTests/RenderingTests.swift|Tests/ThinkNodesTests/ThemeTests.swift) echo render ;;
        Sources/ThinkNodes/Collaboration.swift|Sources/ThinkNodes/PageUpdates.swift) echo "collab access" ;;
        Tests/ThinkNodesTests/CollaborationTests.swift) echo collab ;;
        Tests/ThinkNodesTests/AccessTests.swift) echo access ;;
        Sources/ThinkNodes/NodeTypes.swift) echo "files worksheet" ;;
        Tests/ThinkNodesTests/AttachmentTests.swift|Tests/ThinkNodesTests/SharedFilesTests.swift) echo files ;;
        Sources/ThinkNodes/WebPresentation.swift) echo "web files" ;;
        Tests/ThinkNodesTests/WebPresentationTests.swift) echo web ;;
        Sources/ThinkNodes/ProjectPackage.swift|Tests/ThinkNodesTests/ProjectPackageTests.swift) echo package ;;
        Sources/ThinkNodes/LinkPreview.swift|Tests/ThinkNodesTests/LinkPreviewTests.swift) echo link ;;
        Tests/ThinkNodesTests/WorksheetTests.swift) echo worksheet ;;
        # Minden más Swift-forrás (Model, Server, WorksheetFile …), a csomagleírás és a közös tesztsegéd: minden Swift-teszt.
        Sources/*|Tests/*|Package.swift|Package.resolved|Patches/*|test.sh) echo core ;;
        *) ;;
    esac
}

# --- Kapcsolók ---------------------------------------------------------------------------------
want_swift=1 want_js=1 list_only=0 since="" selected=""
while (($#)); do
    case "$1" in
        --all) selected="$all_topics" ;;
        --swift) want_js=0 ;;
        --js) want_swift=0 ;;
        --since) since="${2:?--since: hiányzik a REF}"; shift ;;
        --list) list_only=1 ;;
        --help|-h) usage; exit 0 ;;
        -*) printf 'Ismeretlen kapcsoló: %s\n' "$1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ " $all_topics " != *" $1 "* ]]; then printf 'Ismeretlen téma: %s\n' "$1" >&2; exit 2; fi
            selected+=" $1" ;;
    esac
    shift
done

if [[ -z "${selected// /}" ]]; then
    if [[ -n "$since" ]]; then
        changed="$(git diff --name-only --relative "$since" -- . 2>/dev/null)"
    else
        changed="$(git diff --name-only --relative HEAD -- . 2>/dev/null; git ls-files --others --exclude-standard -- . 2>/dev/null)"
    fi
    if [[ -z "$changed" ]]; then
        echo "Nincs módosítás a server/ alatt. Téma megadása vagy --all: mindent futtat."
        exit 0
    fi
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        found="$(topics_for "$file")"
        if ((list_only)); then printf '  %-60s → %s\n' "$file" "${found:-(nincs teszt)}"; fi
        selected+=" $found"
    done <<<"$changed"
fi
[[ " $selected " == *" core "* ]] && selected+=" $all_topics"
selected="$(tr ' ' '\n' <<<"$selected" | awk 'NF && !seen[$0]++' | tr '\n' ' ')"

# --- Kiválasztott tesztek ----------------------------------------------------------------------
swift_all=0 swift_list=() js_list=()
for topic in $selected; do
    [[ "$topic" == core ]] && { swift_all=1; continue; }
    for pattern in ${swift_files[$topic]:-}; do
        for file in Tests/$pattern; do [[ -f "$file" ]] && swift_list+=("$file"); done
    done
    for name in ${js_files[$topic]:-}; do js_list+=("Tests/Editor/$name"); done
done
((want_swift)) || { swift_all=0; swift_list=(); }
((want_js)) || js_list=()

# A Swift Testing szűrője: a fájlokban lévő @Test függvények neve.
swift_filter=""
if ((!swift_all && ${#swift_list[@]})); then
    names="$(awk '/@Test/ { pending = 1 } pending && match($0, /func [A-Za-z0-9_]+/) {
                 print substr($0, RSTART + 5, RLENGTH - 5); pending = 0 }' "${swift_list[@]}" | sort -u | paste -sd'|' -)"
    [[ -n "$names" ]] && swift_filter="\\.($names)\\("
fi

printf 'Témák: %s\n' "${selected:-(nincs)}"
if ((swift_all)); then echo "Swift: minden teszt"
elif ((${#swift_list[@]})); then printf 'Swift: %s\n' "${swift_list[*]#Tests/}"
else echo "Swift: –"; fi
if ((${#js_list[@]})); then printf 'JS:    %s\n' "${js_list[*]#Tests/Editor/}"; else echo "JS:    –"; fi
((list_only)) && exit 0

failures=()
started=$SECONDS

# --- JS ----------------------------------------------------------------------------------------
if ((${#js_list[@]})); then
    node_bin="${THINKNODES_NODE:-$(command -v node || true)}"
    if [[ -z "$node_bin" && -x "$HOME/X-Code/RunTime/NodeJS/current/bin/node" ]]; then
        node_bin="$HOME/X-Code/RunTime/NodeJS/current/bin/node"
    fi
    if [[ -z "$node_bin" ]]; then
        echo "Node.js nem található (deploy/install.sh, vagy THINKNODES_NODE)." >&2
        failures+=("JS: nincs Node.js")
    else
        for test in "${js_list[@]}"; do
            printf '\n== %s\n' "${test#Tests/Editor/}"
            if ! "$node_bin" "$test"; then failures+=("${test#Tests/Editor/}"); fi
        done
    fi
fi

# --- Swift -------------------------------------------------------------------------------------
if ((swift_all || ${#swift_list[@]})); then
    swift_bin="${THINKNODES_SWIFT:-}"
    if [[ -z "$swift_bin" ]]; then
        for candidate in "$HOME/X-Code/RunTime/Swift/6.0.3/usr/bin/swift" "$HOME/.swiftly/bin/swift" \
                         "$HOME/.local/share/swiftly/bin/swift" "$(command -v swift || true)"; do
            if [[ -n "$candidate" && -x "$candidate" ]] &&
                "$candidate" --version 2>/dev/null | grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then
                swift_bin="$candidate"; break
            fi
        done
    fi
    if [[ -z "$swift_bin" ]]; then
        echo "Swift 6 nem található (deploy/install.sh, vagy THINKNODES_SWIFT)." >&2
        failures+=("Swift: nincs Swift 6")
    else
        # Ugyanazok a cache-útvonalak, mint a deploy/build.sh-ban, különben minden futás újrafordítana.
        if [[ ! -d .build/checkouts ]]; then
            echo "Első build: deploy/build.sh --no-pull --debug (csomagok és javítások)"
            deploy/build.sh --no-pull --debug || exit 1
        fi
        export PATH="$(dirname "$swift_bin"):$PATH"
        export CLANG_MODULE_CACHE_PATH="$server_dir/.build/module-cache"
        export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
        swift_paths=(--cache-path "$server_dir/.build/package-cache" --config-path "$server_dir/.build/package-config"
                     --security-path "$server_dir/.build/package-security" --disable-automatic-resolution)
        printf '\n== Swift build (debug)\n'
        build_started=$SECONDS
        build_log="$(mktemp -t thinknodes-test-build)"
        "$swift_bin" build --build-tests "${swift_paths[@]}" >"$build_log" 2>&1
        build_status=$?
        # Csak a saját modulok fordítása és a hibák látszanak.
        grep -E 'error:|Compiling (ThinkNodes|ThinkTable)|Build complete' "$build_log"
        rm -f "$build_log"
        if ((build_status != 0)); then
            failures+=("Swift build")
        else
            printf 'Build: %d s\n' "$((SECONDS - build_started))"
            printf '\n== Swift tesztek\n'
            filter=()
            [[ -n "$swift_filter" ]] && filter=(--filter "$swift_filter")
            # A Vapor naplóját (kérésenként egy sor, a tesztek szándékos 4xx válaszai is) elrejti;
            # a hibák és az összegzés látszik.
            "$swift_bin" test --skip-build "${swift_paths[@]}" "${filter[@]}" 2>&1 |
                grep -av -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+ [a-z]+ codes\.vapor' |
                grep -aE '✘|failed|error:|Expectation|Test run|recorded an issue'
            [[ ${PIPESTATUS[0]} -ne 0 ]] && failures+=("Swift tesztek")
        fi
    fi
fi

printf '\nIdő: %d s\n' "$((SECONDS - started))"
if ((${#failures[@]})); then
    printf 'HIBA: %s\n' "${failures[*]}"
    exit 1
fi
echo "Rendben."
