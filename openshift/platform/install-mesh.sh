#!/usr/bin/env bash
#
# install-mesh.sh — OpenShift Service Mesh 3 for the datamesh project:
# the OSSM 3 and Kiali operators, the Istio and IstioCNI control plane, the
# chart's mesh flag (sidecars, STRICT mTLS, gateway PERMISSIVE) and,
# with --canary, order-service v2 behind a 90/10 VirtualService.
#
#   ./openshift/platform/install-mesh.sh [--canary]
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
PLATFORM="$OPENSHIFT_DIR/platform"

CANARY=false
[[ "${1:-}" == "--canary" ]] && CANARY=true

require_crc
oc get deployment order-service -n "$NS" >/dev/null 2>&1 || fail "core not deployed: run deploy.sh first"

step "1/4 Operators"
install_operator "$PLATFORM/subscriptions/servicemesh.yaml" openshift-operators servicemeshoperator3 servicemeshoperator3.v3.4.3
install_operator "$PLATFORM/subscriptions/kiali.yaml" openshift-operators kiali-ossm kiali-operator.v2.27.5

step "2/4 Istio v1.30.5 control plane"
oc apply -f "$PLATFORM/mesh/istio.yaml" >/dev/null || fail "apply Istio/IstioCNI"
oc wait istiocni/default --for=condition=Ready --timeout=300s >/dev/null || fail "IstioCNI not Ready"
ok "IstioCNI Ready"
oc wait istio/default --for=condition=Ready --timeout=600s >/dev/null || fail "Istio not Ready"
ok "Istio Ready ($(oc get istio default -o jsonpath='{.status.activeRevisionName}'))"

step "3/4 Sidecars and mTLS"
"$OPENSHIFT_DIR/deploy.sh" --set mesh.enabled=true --set mesh.canary.enabled="$CANARY" >/dev/null \
    || fail "deploy.sh with mesh.enabled failed"
ok "release upgraded with mesh.enabled=true, canary=$CANARY"

step "4/4 Kiali"
oc apply -f "$PLATFORM/mesh/kiali.yaml" >/dev/null || fail "apply Kiali"
wait_for 600 "Kiali deployment created" oc get deployment kiali -n istio-system
oc rollout status deployment/kiali -n istio-system --timeout=600s >/dev/null || fail "Kiali not Ready"
ok "Kiali https://$(oc get route kiali -n istio-system -o jsonpath='{.spec.host}')"
