#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# A job must not read other users' data. Own $HOME is excluded so seeing your
# own files is not a false positive. Network-level isolation between sibling
# runners (shared bridge) is not covered here; it needs the network topology.

# No other user's shell history or ssh keys are readable.
# shellcheck disable=SC2016  # $HOME/$d expand in the inner bash -c
expect_blocked "other-home" bash -c '
  for d in /home/* /root; do
    [ "$d" = "$HOME" ] && continue
    cat "$d"/.ssh/id_* "$d"/.bash_history 2>/dev/null
  done | grep -q .'
assert_finish
