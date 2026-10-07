#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
: "${DURATION:=2}"
sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fio >/dev/null 2>&1 || true
f="${RUNNER_TEMP:-/tmp}/stress-testfile"
expect_ok "disk-io" fio --name=vm-disk-test --filename="$f" --size=2G --rw=randrw \
  --rwmixread=50 --bs=4k --iodepth=16 --numjobs=4 --runtime="${DURATION}m" \
  --time_based --direct=1 --group_reporting
rm -f "$f"
assert_finish
