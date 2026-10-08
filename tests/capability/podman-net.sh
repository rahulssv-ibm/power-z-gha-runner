#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #63: AppArmor blocks podman/buildah socket() on container runners.
command -v podman >/dev/null || skip_test "podman-dns" "podman not installed"
sudo apt-get install -y slirp4netns >/dev/null 2>&1 || true
expect_ok "podman-dns" podman run --rm docker.io/library/alpine:latest nslookup google.com
assert_finish
