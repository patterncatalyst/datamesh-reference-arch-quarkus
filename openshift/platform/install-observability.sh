#!/usr/bin/env bash
#
# install-observability.sh — tracing for the datamesh services on OpenShift
# Local: the Red Hat build of OpenTelemetry operator injects the
# OpenTelemetry Java agent (no pom or image change), and the chart's
# observability flag deploys grafana/otel-lgtm with a Grafana Route.
#
#   ./openshift/platform/install-observability.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
PLATFORM="$OPENSHIFT_DIR/platform"

require_crc
oc get deployment order-service -n "$NS" >/dev/null 2>&1 || fail "core not deployed: run deploy.sh first"

step "1/3 OpenTelemetry operator"
install_operator "$PLATFORM/subscriptions/opentelemetry.yaml" openshift-opentelemetry-operator \
    opentelemetry-product opentelemetry-operator.v0.158.0-2

step "2/3 Instrumentation CR and otel-lgtm"
"$OPENSHIFT_DIR/deploy.sh" --set observability.enabled=true >/dev/null || fail "deploy.sh with observability.enabled failed"
oc get instrumentation datamesh-java -n "$NS" >/dev/null 2>&1 || fail "Instrumentation datamesh-java missing"
oc rollout status deployment/lgtm -n "$NS" --timeout=600s >/dev/null || fail "otel-lgtm not Ready"
ok "otel-lgtm Ready (SCC $(oc get pod -n "$NS" -l app.kubernetes.io/name=lgtm -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}'))"

step "3/3 Agent injection"
# Helm creates the Deployments before the Instrumentation CR, so pods that
# started in the same upgrade may have missed the injection webhook.
# Restart whatever lacks the agent.
for d in $(oc get deployment -n "$NS" -l app.kubernetes.io/part-of=datamesh -o name); do
    oc get "$d" -n "$NS" -o jsonpath='{.spec.template.metadata.annotations}' | grep -q inject-java || continue
    pod="$(oc get pod -n "$NS" -l "app.kubernetes.io/name=${d#deployment.apps/}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
    [[ -z "$pod" ]] && continue   # scaled to zero (KEDA): injected on its next start
    oc get pod "$pod" -n "$NS" -o jsonpath='{.spec.initContainers[*].name}' | grep -q opentelemetry-auto-instrumentation \
        || oc rollout restart "$d" -n "$NS" >/dev/null
done
for d in $(oc get deployment -n "$NS" -l app.kubernetes.io/part-of=datamesh -o name); do
    oc rollout status "$d" -n "$NS" --timeout=600s >/dev/null || fail "$d did not roll out"
done
ok "Java agent injected; Grafana https://$(oc get route grafana -n "$NS" -o jsonpath='{.spec.host}')"

if oc get kiali kiali -n istio-system >/dev/null 2>&1; then
    step "Kiali graph metrics"
    # The mesh is installed: Kiali reads the sidecar metrics that otel-lgtm's
    # Prometheus now scrapes.
    oc patch kiali kiali -n istio-system --type merge -p \
        "{\"spec\":{\"external_services\":{\"prometheus\":{\"enabled\":true,\"url\":\"http://lgtm.$NS.svc.cluster.local:9090\"}}}}" >/dev/null \
        || fail "patch Kiali"
    sleep 10
    oc rollout status deployment/kiali -n istio-system --timeout=300s >/dev/null || fail "Kiali not Ready after the patch"
    ok "Kiali uses http://lgtm.$NS.svc.cluster.local:9090"
fi
