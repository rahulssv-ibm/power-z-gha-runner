#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #7: OverlayFS mount on Btrfs via mkosi sandbox.
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 2>/dev/null || true
work="$(mktemp -d)"; cd "$work" || exit 1
expect_ok "overlay" bash -c 'git clone --depth 1 https://github.com/systemd/mkosi && cd mkosi && mkdir lower upper work && python3 mkosi/sandbox.py --bind / / --become-root --overlay-lowerdir lower/ --overlay-workdir work/ --overlay-upperdir upper/ --overlay overlay mount'
assert_finish
