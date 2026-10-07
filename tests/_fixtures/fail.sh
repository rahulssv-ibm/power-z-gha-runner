#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"; # shellcheck source=/dev/null
. "$dir/assert.sh"
fail "f1" "always fail"
assert_finish
