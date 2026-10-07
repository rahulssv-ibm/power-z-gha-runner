#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Closes the gap the old encode_credentials.sh demonstrated: the runner's
# registration credentials must NOT be readable from an untrusted job.
# Runner install dir is /opt/runner-cache.
shopt -s nullglob
found=0
for p in /opt/runner-cache/.credentials* /home/runner/runners/*/.credentials*; do
  found=1
  expect_blocked "cred-read:$p" test -r "$p"   # one check per file
done
[ "$found" -eq 1 ] || ok "cred-files" "no runner credential files present in sandbox"

# No runner/registration or container-manager tokens in the job environment.
expect_blocked "env-token" bash -c 'env | grep -Eiq "RUNNER_TOKEN|REGISTRATION_TOKEN|ACTIONS_RUNNER_.*TOKEN|LXD_|INCUS_"'
assert_finish
