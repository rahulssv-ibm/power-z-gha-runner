#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Container runners share the host kernel: an untrusted job must run under
# finite caps so a runaway cannot exhaust the host. (Container-only: a VM is
# capped by its hypervisor, so a runaway there only hurts the tenant's VM.)
pids="$(ulimit -u)"
nofile="$(ulimit -n)"
if [ "$pids" != "unlimited" ]; then ok "pids-cap" "nproc=$pids"; else fail "pids-cap" "process limit is unlimited"; fi
if [ "$nofile" != "unlimited" ]; then ok "fd-cap" "nofile=$nofile"; else fail "fd-cap" "fd limit is unlimited"; fi
assert_finish
