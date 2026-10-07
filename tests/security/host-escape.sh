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

# Host kernel ring buffer must not be readable (leaks host state).
expect_blocked "host-dmesg" bash -c 'dmesg 2>/dev/null | grep -qi hypervisor'
assert_finish
