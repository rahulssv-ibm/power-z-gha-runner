#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Reproduces pentest 9984-6 (overly permissive Linux capabilities): the runner
# container keeps the full capability bounding set (profile raw.lxc has an empty
# lxc.cap.drop=), so a job can load kernel modules and do raw I/O against the
# SHARED host kernel. PASS = the sharpest host-compromising caps are dropped
# from the bounding set.
#
# Container-only: a VM runs its own kernel, so these caps there only reach the
# tenant's own VM (manifest marks expected_vm as n/a). Scoped here too for a
# correct result when the script is run standalone on a VM.
if [ "${PROFILE:-}" = vm ]; then
  skip_test "cap-bounding-set" "VM runs its own kernel"
fi

cap="$(awk '/^CapBnd:/{print $2}' /proc/self/status)"
if [ -z "$cap" ]; then
  skip_test "cap-bounding-set" "CapBnd not readable from /proc/self/status"
fi

# Dangerous on a container that shares the host kernel, and no GitHub Actions
# build needs them. Bit positions from <linux/capability.h>.
#   CAP_SYS_MODULE = 16  (load/unload host kernel modules)
#   CAP_SYS_RAWIO  = 17  (raw port/memory I/O)
#   CAP_SYS_TIME   = 25  (set the host clock)
#   CAP_SYS_BOOT   = 22  (reboot the host)
check_cap() { # id bit human
  if (( 0x$cap & (1 << $2) )); then
    fail "cap:$1" "$3 present in bounding set (0x$cap)"
  else
    ok "cap:$1" "$3 dropped from bounding set"
  fi
}
check_cap sys_module 16 CAP_SYS_MODULE
check_cap sys_rawio  17 CAP_SYS_RAWIO
check_cap sys_time   25 CAP_SYS_TIME
check_cap sys_boot   22 CAP_SYS_BOOT
assert_finish
