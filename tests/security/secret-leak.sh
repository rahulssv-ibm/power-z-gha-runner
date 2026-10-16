#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Closes the gap the old encode_credentials.sh demonstrated: the runner's
# registration credentials must NOT be readable from an untrusted job.
# The install dir comes from the running Runner.Worker (/opt/runner-cache
# here, elsewhere on GitHub-hosted); check ids use the file name only so the
# parity gate can compare them across platforms.
shopt -s nullglob
roots="$({ ps -eo args= | awk '$1 ~ /^\/.*\/bin\/Runner\.(Worker|Listener)$/ { sub(/\/bin\/Runner\.(Worker|Listener)$/, "", $1); print $1 }'; echo /opt/runner-cache; } | sort -u)"
echo "runner roots: ${roots//$'\n'/ }"
found=0
for r in $roots; do
  for p in "$r"/.credentials*; do
    found=1
    expect_blocked "cred-read:${p##*/}" test -r "$p"   # one check per file
  done
done
[ "$found" -eq 1 ] || ok "cred-files" "no runner credential files present in sandbox"

# No runner/registration or container-manager tokens in the job environment.
expect_blocked "env-token" bash -c 'env | grep -Eiq "RUNNER_TOKEN|REGISTRATION_TOKEN|ACTIONS_RUNNER_.*TOKEN|LXD_|INCUS_"'
assert_finish
