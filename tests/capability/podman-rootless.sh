#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #143: rootless podman/buildah map the runner's subordinate IDs
# (/etc/subuid) through newuidmap. If the sandbox's own ID range does not
# cover them (Incus default: 65536 IDs), every build and pull fails with
# "newuidmap: write to uid_map failed: Operation not permitted".
command -v podman >/dev/null || skip_test "podman-rootless" "podman not installed"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "sandbox uid_map: $(tr -s ' ' < /proc/self/uid_map)"
echo "subuid: $(grep "^$(id -un):" /etc/subuid)"

# podman's own error goes to the log; the verdict line keeps the command.
if podman unshare true; then ok "podman-unshare" "subordinate IDs mapped"
else fail "podman-unshare" "failed (wanted success): podman unshare true"; fi

# A real base image (alpine owns files as gid 42) plus a non-root chown needs
# the whole subordinate range. --network=none keeps issue #63 out of it.
printf 'FROM docker.io/library/alpine:latest\nRUN adduser -D -u 1234 t && chown 1234:1234 /home/t\n' > "$tmp/Containerfile"
if podman build --network=none -t podman-rootless-smoke "$tmp"; then ok "podman-build" "rootless build ran"
else fail "podman-build" "failed (wanted success): podman build --network=none (alpine + chown 1234)"; fi
assert_finish
