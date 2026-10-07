#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #38: container cgroup exposes wrong CPU count via nproc --all.
all="$(nproc --all)"
echo "nproc=$(nproc) nproc-all=$all cpuinfo=$(grep -c ^processor /proc/cpuinfo)"
if [ "$all" -le 16 ]; then
  ok "cpu-count" "nproc --all=$all (bounded)"
else
  fail "cpu-count" "nproc --all=$all exposes host CPUs (issue #38)"
fi
assert_finish
