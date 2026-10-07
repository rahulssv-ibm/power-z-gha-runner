#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #7: OverlayFS mount on Btrfs via mkosi sandbox.
work="$(mktemp -d)"; cd "$work" || exit 1
# mkosi needs unprivileged userns; relax the AppArmor restriction for the test
# only, then restore it so a reused runner is not left weakened.
knob=/proc/sys/kernel/apparmor_restrict_unprivileged_userns
orig="$(cat "$knob" 2>/dev/null)"
if [ -n "$orig" ]; then sudo sysctl -qw kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1 || true; fi
expect_ok "overlay" bash -c 'git clone --depth 1 https://github.com/systemd/mkosi && cd mkosi && mkdir lower upper work && python3 mkosi/sandbox.py --bind / / --become-root --overlay-lowerdir lower/ --overlay-workdir work/ --overlay-upperdir upper/ --overlay overlay mount'
if [ -n "$orig" ]; then sudo sysctl -qw kernel.apparmor_restrict_unprivileged_userns="$orig" >/dev/null 2>&1 || true; fi
assert_finish
