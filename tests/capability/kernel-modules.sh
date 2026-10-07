#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #43: container runners report no /lib/modules and cannot load modules.
lsmod | head -20 || true
expect_ok "modprobe-loop" sudo modprobe loop
assert_finish
