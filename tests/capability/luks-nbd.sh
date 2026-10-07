#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #44: Confidential Containers needs dm-crypt + nbd modules and LUKS2.
expect_ok "dm-crypt" sudo modprobe dm_crypt
expect_ok "nbd" sudo modprobe nbd
# shellcheck disable=SC2016  # $img expands in the inner sudo bash, not here
expect_ok "luks" sudo bash -c 'img=$(mktemp) && dd if=/dev/zero of="$img" bs=1M count=32 && echo -n testpassword | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$img" && echo -n testpassword | cryptsetup open --type luks2 --key-file=- "$img" tl$$ && cryptsetup close tl$$ && rm -f "$img"'
assert_finish
