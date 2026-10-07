#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
files="$(cd "$(dirname "${BASH_SOURCE[0]}")/files" && pwd)"
# Issue #59: misconfigured LXD MTU breaks the TLS handshake during image pulls.
expect_ok "mtu" docker build -f "$files/mtu.Dockerfile" -t mtu-test "$files"
assert_finish
