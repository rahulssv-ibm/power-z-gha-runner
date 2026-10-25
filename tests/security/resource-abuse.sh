#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# A runaway job (fork bomb, leaking build) must only exhaust its own sandbox.
# Jobs have passwordless sudo, so only caps the job cannot lift count:
# - processes, container: the sandbox's own cgroup (cgroup-namespace root, set
#   from the host by LXD/Incus limits.processes). Soft ulimit -u and user.slice
#   are the job's to change, and RLIMIT_NPROC is per-uid, so sudo sidesteps it.
#   Uncapped, the job draws on the HOST's threads-max, shared with every other
#   job on that host.
# - processes, VM (ours or GitHub-hosted): the job owns the kernel, so a runaway
#   stops at that VM's threads-max and hurts no one else; the check passes and
#   records the numbers. That gives the parity gate a GitHub-hosted reference:
#   in 2026-10 a hosted 16 GB VM had ulimit -u 63795 and threads-max ~127k.
# - open files: the hard rlimit; raising it needs CAP_SYS_RESOURCE on the host.
tmax="$(cat /proc/sys/kernel/threads-max)"
nproc="$(ulimit -u)"
if [ "${PROFILE:-}" = container ] || systemd-detect-virt --container --quiet 2>/dev/null; then
  pids="$(cat /sys/fs/cgroup/pids.max /sys/fs/cgroup/pids/pids.max 2>/dev/null | head -1)"
  if [ -n "$pids" ] && [ "$pids" != max ]; then
    ok "pids-cap" "sandbox pids.max=$pids (ulimit -u=$nproc)"
  else
    fail "pids-cap" "sandbox pids.max=${pids:-absent}, ulimit -u=$nproc: a runaway can take the host's threads-max=$tmax, shared by every job on it (set limits.processes)"
  fi
else
  ok "pids-cap" "own kernel (VM): a runaway stops at this VM's threads-max=$tmax (ulimit -u=$nproc)"
fi
nofile="$(ulimit -Hn)"
if [ "$nofile" != "unlimited" ]; then ok "fd-cap" "hard nofile=$nofile"; else fail "fd-cap" "hard fd limit is unlimited"; fi
assert_finish
