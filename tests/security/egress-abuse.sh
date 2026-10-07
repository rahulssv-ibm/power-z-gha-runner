#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Resource/network abuse boundary. PASS = abuse channel is bounded/blocked.

# Cloud instance-metadata endpoint must not be reachable from a job.
expect_blocked "imds" curl -sf --max-time 5 http://169.254.169.254/latest/meta-data/

# Known crypto-mining pool endpoints should be blocked by egress policy.
for hp in stratum.slushpool.com:3333 xmr-eu1.nanopool.org:14444 pool.minexmr.com:4444; do
  host="${hp%:*}"; port="${hp##*:}"
  if timeout 6 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    fail "mining-egress:$hp" "egress to mining pool reachable (tighten policy)"
  else
    ok "mining-egress:$hp" "egress bounded/blocked"
  fi
done
assert_finish
