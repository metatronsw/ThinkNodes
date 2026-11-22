#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Keep user creation local and deterministic; run.sh otherwise checks for updates.
export THINKNODES_UPDATED_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"

create_user() {
    local name="$1" role="$2" password="$3"
    printf '%s\n' "$password" | ./run.sh user "$name" "$role"
}

create_user admin admin admin12345
create_user fnd editor fnd12345
create_user laking editor laking12345
create_user jenci editor jenci12345
