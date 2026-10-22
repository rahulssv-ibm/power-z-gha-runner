#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Reproduces pentest 9984-8 (docker and LXD group membership): membership in
# docker / lxd / incus / incus-admin is root-equivalent on the host — the group
# socket drives the container manager, which can mount the host root or run a
# privileged container. PASS = the job's user is not in a host-control group.
#
# GitHub-hosted puts the runner user in `docker`, so group:docker reads PARITY
# there (non-gating); lxd/incus do not exist on hosted, so those gate only on
# our runners.
groups_now="$(id -nG 2>/dev/null)"
for g in docker lxd incus incus-admin kvm; do
  if printf '%s\n' $groups_now | grep -qx "$g"; then
    fail "group:$g" "job user is in '$g' (host-equivalent control via its socket/device)"
  else
    ok "group:$g" "job user not in '$g'"
  fi
done
assert_finish
