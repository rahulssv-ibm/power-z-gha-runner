#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #43: Kata "Make ioctl against /dev/random" fails on container runners.
prog="$(mktemp)"
cat > "$prog" <<'PY'
import fcntl, os, struct, platform
arch = platform.machine()
RNDGETENTCNT = 0x40045200 if arch in ("ppc64le", "ppc64", "ppc") else 0x80045200
fd = os.open("/dev/random", os.O_RDONLY)
buf = fcntl.ioctl(fd, RNDGETENTCNT, b"\x00" * 4)
print("entropy", struct.unpack("I", buf)[0])
os.close(fd)
PY
expect_ok "ioctl-random" python3 "$prog"
rm -f "$prog"
assert_finish
