#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Sandbox integrity: an untrusted job must NOT reach the container manager or
# the host. Each check PASSes when the operation is denied.

# LXD management socket must be absent / unreachable from a job.
expect_blocked "lxd-socket" test -S /var/snap/lxd/common/lxd/unix.socket
expect_blocked "lxd-api" curl -sf --max-time 5 --unix-socket /var/snap/lxd/common/lxd/unix.socket lxd/1.0

# The job's PID 1 must be its own init, not the host's lxc monitor.
expect_blocked "host-pid1" bash -c 'grep -qa lxc /proc/1/cmdline'

# Container runners share the host kernel, so their ring buffer IS the host's:
# reading it leaks host state. A VM's dmesg is the tenant's own kernel.
if [ "${PROFILE:-}" = container ]; then
  expect_blocked "host-dmesg" dmesg
else
  skip "host-dmesg" "VM runs its own kernel"
fi
assert_finish
