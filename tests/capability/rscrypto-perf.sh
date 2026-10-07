#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #71: unprivileged userspace perf (cycles:u) with perf_event_paranoid=2.
cat /proc/sys/kernel/perf_event_paranoid || true
if ! command -v perf >/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y linux-tools-common "linux-tools-$(uname -r)" >/dev/null 2>&1 \
    || sudo apt-get install -y linux-tools-generic >/dev/null 2>&1 || true
fi
expect_ok "perf-paranoid" sudo sysctl kernel.perf_event_paranoid=2
expect_ok "cycles-u" perf stat --event cycles:u -- true
assert_finish
