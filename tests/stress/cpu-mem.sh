#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
: "${DURATION:=2}"
sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y stress-ng >/dev/null 2>&1 || true
expect_ok "cpu-mem" stress-ng --cpu "$(nproc)" --vm 2 --vm-bytes 60% --io 4 --timeout "${DURATION}m" --metrics-brief
assert_finish
