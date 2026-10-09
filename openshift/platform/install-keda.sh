#!/usr/bin/env bash
#
# install-keda.sh — the Custom Metrics Autoscaler (Red Hat's KEDA) and the
# chart's keda flag: notification-service scales 0 -> N on Kafka consumer
# lag on order.placed and back to 0 after the cooldown.
#
#   ./openshift/platform/install-keda.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
PLATFORM="$OPENSHIFT_DIR/platform"

require_crc
oc get deployment notification-service -n "$NS" >/dev/null 2>&1 || fail "core not deployed: run deploy.sh first"

step "1/3 Custom Metrics Autoscaler operator"
install_operator "$PLATFORM/subscriptions/custom-metrics-autoscaler.yaml" openshift-keda \
    openshift-custom-metrics-autoscaler-operator custom-metrics-autoscaler.v2.19.0-4

step "2/3 KedaController"
oc apply -f "$PLATFORM/keda/kedacontroller.yaml" >/dev/null || fail "apply KedaController"
for d in keda-operator keda-metrics-apiserver keda-admission; do
    wait_for 300 "$d created" oc get deployment "$d" -n openshift-keda
    oc rollout status "deployment/$d" -n openshift-keda --timeout=300s >/dev/null || fail "$d not Ready"
done
ok "KEDA operator, metrics API server and admission webhooks Ready"

step "3/3 ScaledObject for notification-service"
"$OPENSHIFT_DIR/deploy.sh" --set keda.enabled=true >/dev/null || fail "deploy.sh with keda.enabled failed"
oc wait scaledobject/notification-service -n "$NS" --for=condition=Ready --timeout=120s >/dev/null \
    || fail "ScaledObject not Ready (oc describe scaledobject notification-service -n $NS)"
ok "ScaledObject Ready: min 0, max 10, lagThreshold 5 on order.placed"
