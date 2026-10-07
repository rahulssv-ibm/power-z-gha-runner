#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
files="$(cd "$(dirname "${BASH_SOURCE[0]}")/files" && pwd)"
# Issue #78: AppArmor blocks privileged Docker ops (mock) on container runners.
expect_ok "mock-build" docker build -f "$files/manageiq.Dockerfile" -t mock:latest "$files"
# mock config name tracks the host arch (fedora-43-ppc64le / fedora-43-s390x).
expect_ok "mock-run" docker run --privileged --rm mock:latest mock -r "fedora-43-$(uname -m)" --init
assert_finish
