#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Sandbox integrity: an untrusted job must stay inside the LXD/Incus sandbox
# its label promises and must not be handed the host's container manager.
# Works the same for LXD and Incus, containers and VMs.

# 1. The job really runs inside the promised sandbox type.
#    LXD and Incus containers both report "lxc"; their VMs report kvm/qemu.
if command -v systemd-detect-virt >/dev/null; then
  if [ "${PROFILE:-}" = container ]; then
    t="$(systemd-detect-virt --container || true)"
    case "$t" in
      lxc) ok "sandbox-type" "container: $t" ;;
      *)   fail "sandbox-type" "expected an LXD/Incus container, detected: $t" ;;
    esac
  else
    t="$(systemd-detect-virt --vm || true)"
    case "$t" in
      kvm|qemu) ok "sandbox-type" "vm: $t" ;;
      *)        fail "sandbox-type" "expected an LXD/Incus VM, detected: $t" ;;
    esac
  fi
else
  skip "sandbox-type" "systemd-detect-virt not available"
fi

# 2. No host LXD/Incus management socket is shared into the sandbox.
#    A host socket handed in shows up as a bind mount, so we read mountinfo
#    (root=$4, mountpoint=$5) instead of testing the path: a VM image with its
#    own lxd snap or incus package has that path legitimately. The guest API
#    (/dev/lxd, /dev/incus) is by design and does not match.
# shellcheck disable=SC2016  # $4/$5 are awk fields, not shell expansions
expect_blocked "mgmt-socket" awk '
  $4 ~ /(lxd|incus)\/unix\.socket$/ || $5 ~ /(lxd|incus)\/unix\.socket$/ { f = 1 }
  $4 ~ /^\/(var\/lib\/(lxd|incus)|var\/snap\/lxd\/common\/lxd)$/      { f = 1 }
  END { exit !f }' /proc/self/mountinfo

# 3. Containers share the host kernel, so their ring buffer IS the host's:
#    reading it leaks host state. A VM's dmesg is the tenant's own kernel.
if [ "${PROFILE:-}" = container ]; then
  expect_blocked "host-dmesg" dmesg
else
  skip "host-dmesg" "VM runs its own kernel"
fi
assert_finish
