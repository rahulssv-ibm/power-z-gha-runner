#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #33/#110: nested virtualization (KVM) for kernel testing / Packer.
expect_ok "kvm-device" test -e /dev/kvm
assert_finish
