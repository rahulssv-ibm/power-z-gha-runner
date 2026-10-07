#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #3: Falco needs delete_module to reach the kernel (ENOENT=2), not be
# blocked by seccomp (ENOSYS=38).
sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends build-essential >/dev/null 2>&1 || true
work="$(mktemp -d)"
cat > "$work/t.c" <<'EOF'
#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>
int main(){ long r=syscall(__NR_delete_module,"nonexistent",O_NONBLOCK); (void)r; return errno; }
EOF
if gcc "$work/t.c" -o "$work/t" 2>/dev/null; then
  sudo "$work/t"; e=$?
  if [ "$e" -eq 2 ]; then
    ok "delete_module" "ENOENT: syscall reached kernel"
  else
    fail "delete_module" "errno=$e (38=ENOSYS means seccomp-filtered)"
  fi
else
  fail "delete_module" "gcc unavailable"
fi
assert_finish
