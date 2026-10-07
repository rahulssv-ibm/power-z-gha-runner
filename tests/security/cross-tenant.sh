#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# A job must not read other tenants' data. Own $HOME is excluded so seeing your
# own workspace is not a false positive.

# No other user's shell history or ssh keys are readable.
# shellcheck disable=SC2016  # $HOME/$d expand in the inner bash -c
expect_blocked "other-home" bash -c '
  for d in /home/* /root; do
    [ "$d" = "$HOME" ] && continue
    cat "$d"/.ssh/id_* "$d"/.bash_history 2>/dev/null
  done | grep -q .'

# No other runner working directory (excluding our own) is visible.
# shellcheck disable=SC2016  # $HOME expands in the inner bash -c
expect_blocked "other-work" bash -c '
  ls -d /home/*/actions-runner*/_work /opt/*runner*/_work 2>/dev/null \
    | grep -v "${HOME:-/nonexistent}" | grep -q .'
assert_finish
