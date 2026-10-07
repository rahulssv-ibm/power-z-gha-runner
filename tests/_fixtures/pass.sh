#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"; # shellcheck source=/dev/null
. "$dir/assert.sh"
ok "p1" "always ok"
assert_finish
