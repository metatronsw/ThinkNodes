#!/usr/bin/env bash
# Rebuild the two d3 bundles in server/Public/lib:
#   d3-zoom.js   the part of d3 the editor canvas uses (zoom, zoomIdentity, select, pointer); classic script, global d3.
#   d3-chart.js  scales and shape generators for the chart boxes (Public/chart.js); ES module, loaded only when a sheet has a chart.
# The results are committed to the repository; run this only to change the d3 version or the exported functions.
# Needs Node.js and network access to the npm registry (the modules and esbuild are fetched into a temporary folder).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v npm >/dev/null || { [[ -f "$HOME/X-Code/RunTime/NodeJS/env.sh" ]] && source "$HOME/X-Code/RunTime/NodeJS/env.sh"; }
command -v npm >/dev/null || { echo "Node.js (npm) not found." >&2; exit 1; }

work="$(mktemp -d -t d3-slim)"
trap 'rm -rf "$work"' EXIT
destination="$PWD/Public/lib/d3-zoom.js"
chart="$PWD/Public/lib/d3-chart.js"
(
    cd "$work"
    printf '{"name": "d3-slim-build", "private": true, "version": "1.0.0"}\n' >package.json
    npm install --no-audit --no-fund --save-exact d3-zoom@3.0.0 d3-selection@3.0.0 d3-scale@4.0.2 d3-shape@3.2.0 esbuild@0.24.0 >/dev/null
    printf 'export {zoom, zoomIdentity} from "d3-zoom";\nexport {select, pointer} from "d3-selection";\n' >entry.js
    npx esbuild entry.js --bundle --minify --format=iife --global-name=d3 --target=es2019 --outfile=out.js >/dev/null
    version() { node -e "console.log(require('./node_modules/$1/package.json').version)"; }
    {
        printf '// d3-zoom %s + d3-selection %s (zoom, zoomIdentity, select, pointer) and their dependencies:\n' "$(version d3-zoom)" "$(version d3-selection)"
        printf '// d3-transition %s, d3-interpolate %s, d3-drag %s, d3-dispatch %s, d3-color %s, d3-timer %s (ISC),\n' \
            "$(version d3-transition)" "$(version d3-interpolate)" "$(version d3-drag)" "$(version d3-dispatch)" "$(version d3-color)" "$(version d3-timer)"
        printf '// d3-ease %s (BSD-3-Clause). Copyright 2010-2023 Mike Bostock. https://d3js.org\n' "$(version d3-ease)"
        printf '// Built by server/deploy/d3-slim.sh (esbuild); global name: d3. The editor uses only these four entry points.\n'
        cat out.js
    } >"$destination"

    printf 'export {scaleLinear, scaleBand, scalePoint} from "d3-scale";\nexport {line, arc, pie} from "d3-shape";\n' >chart.js
    npx esbuild chart.js --bundle --minify --format=esm --target=es2019 --outfile=chart-out.js >/dev/null
    {
        printf '// d3-scale %s + d3-shape %s (scaleLinear, scaleBand, scalePoint, line, arc, pie) and their dependencies:\n' "$(version d3-scale)" "$(version d3-shape)"
        printf '// d3-array %s, d3-interpolate %s, d3-format %s, d3-color %s, d3-path %s (ISC).\n' \
            "$(version d3-array)" "$(version d3-interpolate)" "$(version d3-format)" "$(version d3-color)" "$(version d3-path)"
        printf '// Copyright 2010-2023 Mike Bostock. https://d3js.org\n'
        printf '// Built by server/deploy/d3-slim.sh (esbuild); ES module, imported by Public/chart.js.\n'
        cat chart-out.js
    } >"$chart"
)
for file in "$destination" "$chart"; do printf 'Written: %s (%s bytes)\n' "$file" "$(wc -c <"$file" | tr -d ' ')"; done
