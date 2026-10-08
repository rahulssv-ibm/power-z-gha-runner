#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Issue #49: kind cluster needs privileged containers. kind/kubectl are placed
# on PATH by the setup-kind-ppc64le action. The prebuilt node image is ppc64le;
# s390x builds kind differently and is out of scope here.
[ "${ARCH:-}" = "ppc64le" ] || skip_test "kind-cluster" "prebuilt kind-node image is ppc64le-only"
cluster="cap-kind-$$"
expect_ok "kind-create" kind create cluster --name "$cluster" --image quay.io/powercloud/kind-node:v1.30.2 --wait 120s
expect_ok "kind-nginx" bash -c "kubectl create deployment nginx-test --image=nginx && kubectl wait --for=condition=available --timeout=120s deployment/nginx-test"
kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
assert_finish
