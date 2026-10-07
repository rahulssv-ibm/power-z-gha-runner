#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Informational: kernel sysctl snapshot (migrated from sysctl.yml).
sysctl -a 2>/dev/null || true
ok "sysctl" "collected"
assert_finish
