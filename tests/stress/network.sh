#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Network reliability under concurrency (migrated from network-stress-test).
# shellcheck disable=SC2016  # inner $vars expand in the nested bash -c
expect_ok "dns" bash -c '
  for h in github.com download.docker.com ports.ubuntu.com registry-1.docker.io quay.io; do
    nslookup "$h" >/dev/null 2>&1 || exit 1
  done'
# shellcheck disable=SC2016  # inner $vars expand in the nested bash -c
expect_ok "pulls" bash -c 'docker pull alpine:latest && docker pull ubuntu:noble'
# shellcheck disable=SC2016  # inner $vars expand in the nested bash -c
expect_ok "clones" bash -c 'd=/tmp/net-$$; git clone --depth 1 https://github.com/opencontainers/runc "$d" && rm -rf "$d"'
assert_finish
