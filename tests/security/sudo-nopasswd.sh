#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Reproduces pentest 9984-4 (privileged access to build user): the runner user
# holds sudo NOPASSWD:ALL, so an untrusted job escalates to root without a
# secret. PASS = passwordless root is not available to the job.
#
# GitHub-hosted runners also grant the runner user passwordless sudo, so this
# reads PARITY there (non-gating): it only gates if OUR runners are MORE
# permissive than GitHub-hosted. It becomes a real PASS once the runner user's
# sudoers is narrowed to the specific commands provisioning needs.
if ! command -v sudo >/dev/null; then
  skip_test "sudo-nopasswd" "sudo not installed"
fi
# -n: never prompt. Succeeds only when a NOPASSWD rule covers the invoking user.
if sudo -n true 2>/dev/null; then
  fail "sudo-nopasswd" "passwordless sudo to root available (NOPASSWD); job can become root"
else
  ok "sudo-nopasswd" "sudo requires authentication"
fi
assert_finish
