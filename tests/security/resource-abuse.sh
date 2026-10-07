#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# An untrusted job must run under finite resource caps so a runaway cannot
# exhaust the host.
pids="$(ulimit -u)"
nofile="$(ulimit -n)"
if [ "$pids" != "unlimited" ]; then ok "pids-cap" "nproc=$pids"; else fail "pids-cap" "process limit is unlimited"; fi
if [ "$nofile" != "unlimited" ]; then ok "fd-cap" "nofile=$nofile"; else fail "fd-cap" "fd limit is unlimited"; fi
assert_finish
