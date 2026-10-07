#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Closes the gap that the old encode_credentials.sh demonstrated: the runner's
# registration credentials must NOT be readable from an untrusted job.
for p in /opt/runner/.credentials /opt/runner/.credentials_rsaparams \
         /home/runner/runners/*/.credentials; do
  expect_blocked "cred-read:$p" bash -c "cat $p >/dev/null 2>&1"
done
# No host-level secrets should bleed through the environment.
expect_blocked "env-token" bash -c 'env | grep -Eiq "RUNNER_TOKEN|REGISTRATION_TOKEN|ACTIONS_RUNNER_.*TOKEN|LXD_"'
assert_finish
