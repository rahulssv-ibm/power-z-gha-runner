#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Heavy build-from-source workload (migrated from build-benchmark redis job).
# shellcheck disable=SC2016  # inner $vars expand in the nested bash -c
expect_ok "redis-build" bash -c '
  d=/tmp/redis-$$
  git clone --depth 1 --branch 7.4.0 https://github.com/redis/redis.git "$d" &&
  make -C "$d" -j"$(nproc)" && "$d"/src/redis-server --version
  rc=$?; rm -rf "$d"; exit $rc'
assert_finish
