#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #68: plain `docker run` fails inside container runners.
# - docker-run: on the default bridge network docker sets
#   net.ipv4.ip_unprivileged_port_start=0, which newer runc writes through a
#   reopened procfs fd that some LXC/Incus hosts deny (seen on s390x):
#   "open sysctl net.ipv4.ip_unprivileged_port_start file: reopen fd 8: permission denied".
# - docker-nofile: containerd 2.x dropped LimitNOFILE=infinity, so it inherits
#   DefaultLimitNOFILE=65536 and runc cannot raise a container above that:
#   "error setting rlimit type 7: operation not permitted".
command -v docker >/dev/null || skip_test "docker-run" "docker not installed"
img=docker.io/library/alpine:latest

# run <check> <cmd...>: keep docker's own error as the reason, not just "failed".
run() {
  local id="$1" out err; shift
  if out="$("$@" 2>&1)"; then ok "$id" "ran: $*"; return; fi
  printf '%s\n' "$out"
  err="$(printf '%s\n' "$out" | grep -m1 'Error' || printf '%s\n' "$out" | tail -n1)"
  fail "$id" "${err##*error during container init: }"
}

run "docker-run" docker run --rm "$img" true

# Host network: no per-container sysctl, so only the rlimit path runs. Ask for
# the sandbox's own maximum (PID 1's hard limit, capped at 1M); anything above
# 65536 is refused while containerd is held to DefaultLimitNOFILE.
max="$(awk '/^Max open files/ {print $5}' /proc/1/limits)"
case "$max" in unlimited) max=1048576 ;; ''|*[!0-9]*) max=0 ;; esac
[ "$max" -gt 1048576 ] && max=1048576
if [ "$max" -gt 65536 ]; then
  run "docker-nofile" docker run --rm --network host --ulimit "nofile=$max:$max" "$img" true
else
  skip "docker-nofile" "sandbox hard nofile is $max; nothing above 65536 to ask for"
fi
assert_finish
