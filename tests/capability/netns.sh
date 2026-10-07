#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #43: mmdebstrap-style network namespaces (break DNS on container runners).
expect_ok "netns" sudo bash -c 'ip netns add tns-$$ && ip netns exec tns-$$ ip link set lo up && ip netns exec tns-$$ ip a && ip netns delete tns-$$'
assert_finish
