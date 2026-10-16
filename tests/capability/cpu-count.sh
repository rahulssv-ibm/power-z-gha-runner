#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #38: a job may run on fewer CPUs (cpuset/quota) than it sees online,
# so tools that size by the online count (Python os.cpu_count, Go, mpstat,
# /proc/cpuinfo readers) oversubscribe and the load average explodes.
# Not `nproc --all`: on PowerVM that counts the LPAR's possible (DLPAR) CPUs,
# 192 even on the bare host.
usable="$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"
online="$(getconf _NPROCESSORS_ONLN)"
echo "usable=$usable online=$online nproc-all=$(nproc --all) cpuinfo=$(grep -c ^processor /proc/cpuinfo)"
if [ "$online" -le "$usable" ]; then
  ok "cpu-count" "online=$online usable=$usable"
else
  fail "cpu-count" "online=$online > usable=$usable: tools oversubscribe (issue #38)"
fi
assert_finish
