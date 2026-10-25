#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Egress parity with GitHub-hosted: the ports builds use beyond DNS, HTTP/S,
# SSH and NTP must stay reachable through the container egress filter, as they
# are on GitHub-hosted runners. security/egress-ports and egress-abuse hold the
# other side (IRC, DoT, mining pools and the metadata endpoint stay blocked for
# pentest 9984-1/9984-3). Together they are the allowlist's contract: this list
# matches the ports container-egress-filter.policy.xml (PowerVS) and GHA_EGRESS
# (IBM Z, tasks/container_egress_filter.yml) open in actions-deploy.
#
# Live endpoints only, the same ones the hosted rows run: a dead endpoint fails
# there too and reads PARITY, not a false "only here" FAIL. portquiz.net
# answers on every TCP port, for ports with no well-known public service.
if ! command -v timeout >/dev/null; then
  # Without timeout a connect could hang, and a non-zero "command not found"
  # would read as "blocked". Report honestly instead.
  skip_test "egress-reach" "timeout(1) not available to bound connect attempts"
fi
for hp in \
    git:git.kernel.org:9418 \
    hkp:keyserver.ubuntu.com:11371 \
    rsync:rsync.kernel.org:873 \
    http-alt:portquiz.net:8080 \
    https-alt:portquiz.net:8443 \
    registry:portquiz.net:5000 \
    smtp-submission:smtp.gmail.com:587 \
    smtps:smtp.gmail.com:465 \
    postgres:portquiz.net:5432 \
    mysql:portquiz.net:3306 \
    redis:portquiz.net:6379 \
    mongodb:portquiz.net:27017; do
  name="${hp%%:*}"; rest="${hp#*:}"; host="${rest%:*}"; port="${rest##*:}"
  if timeout 6 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    ok "egress-reach:$name" "egress to $host:$port reachable"
  else
    fail "egress-reach:$name" "egress to $host:$port blocked (allowlist misses port $port)"
  fi
done
assert_finish
