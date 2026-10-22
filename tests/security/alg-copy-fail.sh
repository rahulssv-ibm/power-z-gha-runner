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

# Exit 0 = aead socket reachable (bad); 3 = blocked (good); other = probe error.
out="$(python3 - <<'PY' 2>&1
import socket, sys
try:
    s = socket.socket(socket.AF_ALG, socket.SOCK_SEQPACKET, 0)
except AttributeError:
    print("AF_ALG unsupported by this python"); sys.exit(3)
except OSError as e:
    print("AF_ALG socket blocked:", e); sys.exit(3)
try:
    s.bind(("aead", "gcm(aes)"))
except OSError as e:
    print("algif_aead bind blocked:", e); sys.exit(3)
finally:
    s.close()
print("algif_aead aead interface reachable"); sys.exit(0)
PY
)"
rc=$?
case "$rc" in
  0) fail "algif-aead" "AF_ALG aead reachable (CVE-2026-31431 path exposed): $out" ;;
  3) ok   "algif-aead" "AF_ALG aead blocked: $out" ;;
  *) fail "algif-aead" "probe error (rc=$rc): $out" ;;
esac
assert_finish
