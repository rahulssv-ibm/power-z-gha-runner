#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Scale a kind deployment (migrated from lxd-vm-stress-suite kubernetes-scale).
# kind/kubectl come from the setup-kind-ppc64le action; node image is ppc64le.
[ "${ARCH:-}" = "ppc64le" ] || skip_test "kube-scale" "prebuilt kind-node image is ppc64le-only"
cluster="scale-$$"
expect_ok "kube-scale" bash -c "
  kind create cluster --name $cluster --image quay.io/powercloud/kind-node:v1.30.2 --wait 120s &&
  kubectl create deployment scale-test --image=nginx --replicas=20 &&
  kubectl wait --for=condition=available --timeout=300s deployment/scale-test"
kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
assert_finish
