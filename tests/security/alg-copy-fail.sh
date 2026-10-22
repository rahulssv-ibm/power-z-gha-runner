#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Reproduces pentest 9984-5 (Copy Fail / CVE-2026-31431, s390x): the kernel
# vulnerability is reached through the AF_ALG "aead" interface. On s390x the
# module blocklist was bypassable and only the seccomp filter blocked the
# socket; ppc64le is also kernel-patched. This checks the net control a job
# sees: the AF_ALG aead interface must NOT be reachable from inside the job.
# PASS = creating/binding an AF_ALG aead socket is blocked (by seccomp or by a
# kernel that does not expose algif_aead). Runs on every arch so a seccomp
# regression that re-opens the path on s390x shows up as a FAIL.
if ! command -v python3 >/dev/null; then
  skip_test "algif-aead" "python3 not available to probe AF_ALG"
fi

# Exit 0 = AF_ALG interface reachable (bad); 3 = blocked (good); other = error.
# The control under test is whether seccomp blocks the AF_ALG socket at all, so
# the verdict keys on socket() creation, NOT on bind(). A successful socket()
# means the interface is reachable even if gcm(aes) is not a registered
# algorithm (an attacker binds a different one); treating a bind ENOENT as
# "blocked" there would be a false PASS while the boundary is open.
out="$(python3 - <<'PY' 2>&1
import socket, sys
try:
    s = socket.socket(socket.AF_ALG, socket.SOCK_SEQPACKET, 0)
except AttributeError:
    print("AF_ALG unsupported by this python build"); sys.exit(3)
except OSError as e:
    print("AF_ALG socket blocked:", e); sys.exit(3)
# socket() succeeded: the AF_ALG interface is exposed to the job -> reachable.
detail = "AF_ALG socket created (interface reachable)"
try:
    s.bind(("aead", "gcm(aes)"))
    detail = "AF_ALG aead bound: gcm(aes)"
except OSError as e:
    detail += "; aead bind errored (%s) but the socket family is still open" % e
finally:
    s.close()
print(detail); sys.exit(0)
PY
)"
rc=$?
case "$rc" in
  0) fail "algif-aead" "AF_ALG aead reachable (CVE-2026-31431 path exposed): $out" ;;
  3) ok   "algif-aead" "AF_ALG aead blocked: $out" ;;
  *) fail "algif-aead" "probe error (rc=$rc): $out" ;;
esac
assert_finish
