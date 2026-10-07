#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Informational: environment snapshot (migrated from env.yml).
env
cat /etc/environment 2>/dev/null || true
ok "env" "collected"
assert_finish
