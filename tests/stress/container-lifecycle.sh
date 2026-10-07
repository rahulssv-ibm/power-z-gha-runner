#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Churn many short-lived containers in parallel (migrated from lxd-vm-stress-suite).
: "${PARALLEL:=50}"
# shellcheck disable=SC2016  # inner $vars expand in the nested bash -c
expect_ok "container-lifecycle" bash -c '
  pids=()
  for i in $(seq 1 '"$PARALLEL"'); do
    docker run -d --rm --name "stress-$$-$i" alpine:latest \
      sh -c "for n in \$(seq 1 200); do echo \$n >/dev/null; done; sleep 5" >/dev/null &
    pids+=("$!")
  done
  rc=0
  for p in "${pids[@]}"; do wait "$p" || rc=1; done
  docker ps -a >/dev/null
  exit $rc'
assert_finish
