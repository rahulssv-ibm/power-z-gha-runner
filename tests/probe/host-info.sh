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
# Which sandbox ran this job: virt type, plus the LXD or Incus guest API socket.
virt="$(systemd-detect-virt 2>/dev/null || echo unknown)"
backend=unknown
[ -S /dev/lxd/sock ] && backend=lxd
[ -S /dev/incus/sock ] && backend=incus
echo "virt=$virt backend=$backend"
ok "host-info" "virt=$virt backend=$backend"
assert_finish
