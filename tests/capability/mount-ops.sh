#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #7: systemd/mkosi needs mount/umount + loopback for image builds.
# shellcheck disable=SC2016  # $d expands in the inner sudo bash, not here
expect_ok "tmpfs-mount" sudo bash -c 'd=$(mktemp -d) && mount -t tmpfs -o size=16M tmpfs "$d" && echo hi > "$d/t" && cat "$d/t" && umount "$d" && rmdir "$d"'
assert_finish
