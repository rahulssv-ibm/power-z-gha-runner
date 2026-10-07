#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"; # shellcheck source=/dev/null
. "$dir/assert.sh"
expect_ok "c1" false
assert_finish
