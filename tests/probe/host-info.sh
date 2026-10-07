#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Informational host snapshot (migrated from smoke-test.yaml).
whoami; id; uname -a
cat /etc/os-release 2>/dev/null || true
lscpu 2>/dev/null || true
df -h 2>/dev/null || true
free -h 2>/dev/null || true
ip a 2>/dev/null || true
ip r 2>/dev/null || true
ok "host-info" "collected"
assert_finish
