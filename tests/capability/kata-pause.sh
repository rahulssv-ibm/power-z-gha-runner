#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #43: build the Kata Containers pause image.
work="$(mktemp -d)"; cd "$work" || exit 1
expect_ok "pause-image" bash -c 'git clone --depth 1 https://github.com/kata-containers/kata-containers.git && cd kata-containers && sudo make pause-image-tarball-build'
assert_finish
