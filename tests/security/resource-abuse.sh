#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Container runners share the host kernel: an untrusted job must run under
# finite caps so a runaway cannot exhaust the host. (Container-only: a VM is
# capped by its hypervisor, so a runaway there only hurts the tenant's VM.)
# Jobs have passwordless sudo, so only caps the job cannot lift count:
# - processes: the sandbox's own cgroup (cgroup-namespace root, set from the
#   host by LXD/Incus limits.processes). Soft ulimit -u and user.slice are the
#   job's to change, and RLIMIT_NPROC is per-uid, so sudo sidesteps it.
# - open files: the hard rlimit; raising it needs CAP_SYS_RESOURCE on the host.
pids="$(cat /sys/fs/cgroup/pids.max /sys/fs/cgroup/pids/pids.max 2>/dev/null | head -1)"
nofile="$(ulimit -Hn)"
if [ -n "$pids" ] && [ "$pids" != max ]; then
  ok "pids-cap" "sandbox pids.max=$pids"
else
  fail "pids-cap" "sandbox pids.max=${pids:-absent}: no process cap (set limits.processes)"
fi
if [ "$nofile" != "unlimited" ]; then ok "fd-cap" "hard nofile=$nofile"; else fail "fd-cap" "hard fd limit is unlimited"; fi
assert_finish
