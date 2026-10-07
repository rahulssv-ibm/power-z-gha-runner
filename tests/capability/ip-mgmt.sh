#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #43: Kata "Add an IP address" fails on container runners.
expect_ok "ip-add" sudo bash -c 'ip link add d$$ type dummy && ip addr add 192.168.99.1/24 dev d$$ && ip link set d$$ up && ip addr show d$$ && ip link delete d$$'
assert_finish
