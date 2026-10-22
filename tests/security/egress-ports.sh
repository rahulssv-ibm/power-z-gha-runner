#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Reproduces pentest 9984-1 (shell access: a compiled callback phones home on an
# arbitrary port) and 9984-3 (unrestricted egress: nearly all outbound TCP ports
# open). An egress allowlist should pass GitHub, package repos and DNS only, so
# these non-build destinations must be unreachable. PASS = egress is bounded.
#
# Live endpoints only: a dead host's refused connection would read as "blocked"
# and hide an open policy. egress-abuse.sh covers IMDS and mining pools; this is
# the generic "can a job open a channel off-net on a non-allowlisted port" check.
# While our runners match GitHub-hosted (egress wide open) these read PARITY, not
# FAIL; they become a real PASS once an egress filter is in place on our runners.
#
# Ports must be ones GitHub-hosted leaves OPEN, or the parity model mislabels
# them: port 25 is blocked upstream on hosted (Azure) but not on every one of
# our runners, so an open:25 here would never parity-match and would gate as a
# false "only here" FAIL. SMTP/25 is therefore not probed; IRC/6667 and DoT/853
# are open on hosted and genuinely read PARITY until our egress filter lands.
if ! command -v timeout >/dev/null; then
  # Without timeout a connect could hang, and a non-zero "command not found"
  # would read as "blocked" and mask wide-open egress. Report honestly instead.
  skip_test "egress-ports" "timeout(1) not available to bound connect attempts"
fi
for hp in \
    irc:irc.libera.chat:6667 \
    dot:1.1.1.1:853; do
  name="${hp%%:*}"; rest="${hp#*:}"; host="${rest%:*}"; port="${rest##*:}"
  if timeout 6 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    fail "egress-port:$name" "egress to $host:$port reachable (tighten egress policy)"
  else
    ok "egress-port:$name" "egress to $host:$port bounded/blocked"
  fi
done
assert_finish
