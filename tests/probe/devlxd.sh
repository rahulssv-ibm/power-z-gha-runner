#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Informational, for pentest 9984-7 (host information disclosure): the LXD/Incus
# guest API (devlxd) is exposed into the sandbox by design, and querying it
# returns the instance's own config/devices and metadata. This records exactly
# what that channel exposes to a job, so an operator can see whether it leaks
# anything beyond the instance itself. Never gates — the host kernel ring-buffer
# leak that DOES gate is in security/host-escape.sh (host-dmesg).
sock=""
[ -S /dev/lxd/sock ]   && sock=/dev/lxd/sock
[ -S /dev/incus/sock ] && sock=/dev/incus/sock

if [ -z "$sock" ]; then
  echo "no devlxd/guestapi socket present"
  ok "devlxd" "no guest API socket exposed to this job"
elif ! command -v curl >/dev/null; then
  echo "guest API socket present at $sock but curl unavailable to query it"
  ok "devlxd" "guest API socket present ($sock); not queried (no curl)"
else
  echo "== devlxd $sock /1.0"
  curl -s --max-time 5 --unix-socket "$sock" http://devlxd/1.0 2>/dev/null || true
  echo
  echo "== devlxd $sock /1.0/config (keys the job can read)"
  curl -s --max-time 5 --unix-socket "$sock" http://devlxd/1.0/config 2>/dev/null || true
  echo
  ok "devlxd" "guest API reachable at $sock (config/metadata exposed by design — snapshot above)"
fi
assert_finish
