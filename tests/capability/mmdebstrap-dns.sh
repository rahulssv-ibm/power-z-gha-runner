#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #43: with SYS_ADMIN, mmdebstrap makes its own netns which breaks DNS on
# container runners (the setup-hook's apt-get update is where DNS fails).
case "$(uname -m)" in
  ppc64le) dpkgarch=ppc64el ;;
  s390x)   dpkgarch=s390x ;;
  *)       dpkgarch="$(dpkg --print-architecture 2>/dev/null || echo amd64)" ;;
esac
# $dpkgarch is interpolated here; the \"...\" are quotes for the nested bash -c
# that runs inside the container, mirroring the original workflow.
inner='apt-get update && apt-get install -y iproute2 iputils-ping mmdebstrap && mmdebstrap --mode=root --arch='"$dpkgarch"' --variant=required noble /tmp/rootfs --setup-hook="bash -c \"ip a >&2; cat /etc/resolv.conf >&2; apt-get update >&2\""'
if docker run --rm --cap-add SYS_ADMIN --cap-add SYS_CHROOT --cap-add MKNOD \
     --security-opt apparmor=unconfined -v /tmp:/tmp ubuntu:noble bash -c "$inner"; then
  ok "mmdebstrap" "ran ($dpkgarch)"
else
  fail "mmdebstrap" "mmdebstrap failed (netns DNS break / caps)"
fi
assert_finish
