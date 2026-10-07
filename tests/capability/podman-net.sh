#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #63: AppArmor blocks podman/buildah socket() on container runners.
if command -v podman >/dev/null; then
  sudo apt-get install -y slirp4netns >/dev/null 2>&1 || true
  expect_ok "podman-dns" podman run --rm docker.io/library/alpine:latest nslookup google.com
else
  skip "podman-dns" "podman not installed"
fi
assert_finish
