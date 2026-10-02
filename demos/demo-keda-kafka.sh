#!/usr/bin/env bash
#
# demos/demo-keda-kafka.sh — "minikube" group demo, opt-in.
#
# KEDA core scaling notification-service on Kafka consumer-group lag, using
# the real step-9 substrate — nothing here is invented:
#
#   k8s/base/notification-service.yaml   — the Deployment/Service KEDA scales
#   k8s/keda/consumer-scaledobject.yaml  — the ScaledObject (keda.sh/v1alpha1)
#   k8s/overlays/minikube/               — the app overlay (images -> minikube
#                                           docker daemon)
#   scripts/bootstrap.sh                 — brings up the minikube profile
#                                           ("datamesh") + Istio/CNPG/Strimzi/
#                                           KEDA/LGTM/Kiali/Apicurio tiers
#
# ScaledObject trigger (see k8s/keda/consumer-scaledobject.yaml and its
# header comment for full sourcing): type=kafka,
# bootstrapServers=datamesh-kafka-bootstrap.datamesh.svc.cluster.local:9092,
# consumerGroup=notification-service, topic=order.placed, lagThreshold=5,
# minReplicaCount=0, maxReplicaCount=10, pollingInterval=15,
# cooldownPeriod=120. This demo drives lag above 5 and then asserts (a) the
# Deployment's replica count climbs off its baseline within a budget wide
# enough for one or two polling intervals plus pod cold-start, and (b) it
# falls back to its pre-burst baseline once cooldownPeriod has elapsed with
# lag back under threshold.
#
# ── AUTHOR-ONLY / no live cluster here ───────────────────────────────────────
# This environment has no "datamesh" minikube profile (confirmed:
# `minikube status -p datamesh` -> "Profile \"datamesh\" not found") and no
# kubectl context at all (`kubectl config current-context` -> "current-
# context is not set"). This script is written to be CORRECT for an author
# running it against a real step-9 substrate, but it is only ever exercised
# here up through static manifest validation (no cluster needed for that —
# see below) before gating LOUDLY on cluster reachability. It never starts
# minikube itself.
#
# ── Static validation vs. standalone `kustomize` ─────────────────────────────
# The task brief for this step names `kubectl kustomize` (and a standalone
# `kustomize`) as preflight dependencies. This environment (and, per
# k8s/keda/README.md's own "Validation performed for this step" section, the
# environment step 9c itself was authored in) has NO standalone `kustomize`
# binary on PATH — only kubectl's bundled kustomize (confirmed: `kubectl
# version --client` reports "Kustomize Version: v5.7.1" bundled into kubectl
# v1.35.3; a bare `kustomize version` is "command not found"). Requiring a
# standalone `kustomize` binary here would hard-fail this demo at the
# toolchain gate before it ever reached the (intended, more informative)
# cluster-reachability gate below — so, matching k8s/keda/README.md's own
# precedent ("Rendering was verified with `kubectl kustomize ...` — no
# cluster required for that check"), this demo uses `kubectl kustomize`
# exclusively and does NOT `require` a standalone `kustomize` binary.
#
# ── order-service's gRPC inventory-check (canonical 9000) ───────────────────
# The "real" way this system emits order.placed is POST /orders on
# order-service (see examples/order-service/.../OrderResource.java): it
# synchronously calls InventoryClient.checkStock() over gRPC and ONLY
# persists + publishes order.placed if that call succeeds; a failed/
# unreachable call fails CLOSED with HTTP 503 and publishes nothing (by
# design — see InventoryClient.java's javadoc). This is fully wired on the
# step-9 substrate:
#   - examples/order-service/src/main/resources/application.properties sets
#     `quarkus.grpc.clients.inventory.host=${INVENTORY_GRPC_HOST:localhost}` /
#     `quarkus.grpc.clients.inventory.port=${INVENTORY_GRPC_PORT:9000}`.
#   - k8s/base/config.yaml's datamesh-app-config ConfigMap sets
#     INVENTORY_GRPC_HOST=inventory-service.datamesh.svc.cluster.local and
#     INVENTORY_GRPC_PORT=9000, and both order-service.yaml and
#     inventory-service.yaml consume it via envFrom.configMapRef.
#   - k8s/base/inventory-service.yaml defines the inventory-service
#     Deployment/Service (grpc port 9000) and is listed as a resource in
#     k8s/base/kustomization.yaml, so it is applied as part of
#     `kubectl apply -k k8s/overlays/minikube` below.
# So on the current step-9 substrate, POST /orders in-cluster should reach
# inventory-service over gRPC at the canonical port and succeed, publishing
# order.placed as the KEDA ScaledObject's trigger expects. This script has
# never actually been exercised against a live cluster in this environment
# (see "AUTHOR-ONLY" above), so if the scale-up assertion below still fails,
# treat it as a live-cluster issue to diagnose fresh (e.g. image build/push,
# Postgres/Kafka readiness, RBAC) rather than this previously-documented
# port-wiring gap, which is now fixed.
#
# ── Cleanup ──────────────────────────────────────────────────────────────────
# The only resource this demo itself CREATES is a single throwaway load-
# generator Pod (`kubectl run ... --restart=Never`) in the datamesh
# namespace; it is deleted in the EXIT trap. The app Deployments / KEDA
# ScaledObject applied via `kubectl apply -k` are the standing step-9
# substrate (same objects scripts/bootstrap.sh's own docs describe as
# persistent across runs) and are intentionally left in place, not torn
# down, matching k8s/README.md's "replicas vs. KEDA (9c)" section.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-keda-kafka"
require kubectl minikube curl jq

PROFILE="datamesh"
NS="datamesh"
K8S_DIR="${REPO_ROOT}/k8s"

narrate "KEDA core scaling notification-service 0 -> N on order.placed consumer"
narrate "lag, then back to 0 once the backlog drains and cooldownPeriod elapses."
narrate "Targets the real step-9 substrate manifests — see this script's header"
narrate "comment for exact file references for the order-service -> inventory-"
narrate "service gRPC wiring (canonical port 9000) this flow depends on."

# ─── Static manifest validation (no cluster required) ───────────────────────
step "static validation: kubectl kustomize (no cluster required)"

APP_RENDER_LOG="$(mktemp -t demo-keda-kafka-app-render-XXXXXX)"
if kubectl kustomize "${K8S_DIR}/overlays/minikube" >"$APP_RENDER_LOG" 2>&1; then
    check "k8s/overlays/minikube renders" "true" "n/a"
else
    cat "$APP_RENDER_LOG" >&2
    check "k8s/overlays/minikube renders" "false" "inspect the kustomization under k8s/overlays/minikube and k8s/base"
fi
check "rendered overlay contains notification-service Deployment" \
    "grep -q 'name: notification-service' '$APP_RENDER_LOG'" \
    "check k8s/base/notification-service.yaml and k8s/base/kustomization.yaml"
check "rendered overlay contains the datamesh-app-config ConfigMap" \
    "grep -q 'name: datamesh-app-config' '$APP_RENDER_LOG'" \
    "check k8s/base/config.yaml"

KEDA_RENDER_LOG="$(mktemp -t demo-keda-kafka-keda-render-XXXXXX)"
if kubectl kustomize "${K8S_DIR}/keda" >"$KEDA_RENDER_LOG" 2>&1; then
    check "k8s/keda renders" "true" "n/a"
else
    cat "$KEDA_RENDER_LOG" >&2
    check "k8s/keda renders" "false" "inspect k8s/keda/kustomization.yaml and its two resource files"
fi
check "rendered k8s/keda contains the ScaledObject kind" \
    "grep -q '^kind: ScaledObject$' '$KEDA_RENDER_LOG'" \
    "check k8s/keda/consumer-scaledobject.yaml's apiVersion/kind"
check "rendered ScaledObject is named notification-service-scaledobject" \
    "grep -q 'name: notification-service-scaledobject' '$KEDA_RENDER_LOG'" \
    "check k8s/keda/consumer-scaledobject.yaml's metadata.name"
check "rendered ScaledObject targets the real Kafka bootstrap service" \
    "grep -q 'bootstrapServers: datamesh-kafka-bootstrap.datamesh.svc.cluster.local:9092' '$KEDA_RENDER_LOG'" \
    "check k8s/keda/consumer-scaledobject.yaml's kafka trigger metadata"
check "rendered ScaledObject's trigger targets topic order.placed" \
    "grep -q 'topic: order.placed' '$KEDA_RENDER_LOG'" \
    "check k8s/keda/consumer-scaledobject.yaml's kafka trigger metadata"

rm -f "$APP_RENDER_LOG" "$KEDA_RENDER_LOG"

if (( _DEMO_CHECK_FAILURES > 0 )); then
    fail "${_DEMO_CHECK_FAILURES} static manifest validation check(s) failed (see above) — fix the manifest(s) before retrying"
fi
info "all static manifest checks passed — k8s/overlays/minikube and k8s/keda both render the expected real resources"

# ─── Cluster reachability gate ───────────────────────────────────────────────
step "preflight: live '${PROFILE}' minikube cluster reachable?"

CLUSTER_REACHABLE=1
if ! minikube status -p "$PROFILE" >/dev/null 2>&1; then
    CLUSTER_REACHABLE=0
    info "minikube profile '${PROFILE}' is not running"
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
    CLUSTER_REACHABLE=0
    info "kubectl cannot reach a live API server (current-context: $(kubectl config current-context 2>/dev/null || echo '<none>'))"
fi

if (( CLUSTER_REACHABLE == 0 )); then
    fail "no live '${PROFILE}' minikube cluster reachable. Bring up the step-9 substrate first: ./scripts/bootstrap.sh (verify afterwards with ./scripts/cluster-status.sh), then re-run this demo. This is expected in an author-only environment with no minikube node running — see this script's header comment."
fi
info "minikube profile '${PROFILE}' is running and kubectl can reach the API server"

# ─── Everything below here only runs against a real, reachable cluster ─────

step "live preflight: namespace + KEDA CRDs"
kubectl get namespace "$NS" >/dev/null 2>&1 \
    || fail "namespace '${NS}' does not exist — run ./scripts/bootstrap.sh first"
kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1 \
    || fail "KEDA core CRDs not found — run ./scripts/setup-keda.sh (or ./scripts/bootstrap.sh with ENABLE_KEDA=true, the default)"
info "namespace '${NS}' exists and KEDA CRDs are installed"

step "apply the real app overlay + KEDA scalers"
kubectl apply -k "${K8S_DIR}/overlays/minikube" \
    || fail "kubectl apply -k k8s/overlays/minikube failed"
kubectl apply -k "${K8S_DIR}/keda" \
    || fail "kubectl apply -k k8s/keda failed"
info "applied k8s/overlays/minikube and k8s/keda"

kubectl get deployment notification-service -n "$NS" >/dev/null 2>&1 \
    || fail "deployment/notification-service not found in namespace ${NS} after apply"

# ─── Replica-count helper (positive-content jsonpath parse, never bare exit 0)
get_replicas() {
    local val
    val="$(kubectl get deployment notification-service -n "$NS" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)"
    [[ "$val" =~ ^[0-9]+$ ]] || val=0
    echo "$val"
}

BASELINE_REPLICAS="$(get_replicas)"
info "baseline notification-service replicas: ${BASELINE_REPLICAS}"

# ─── Generate load: burst POST /orders faster than notification-service can
# drain, via a throwaway in-cluster pod (order-service has no Ingress/
# NodePort in this substrate — only an in-cluster ClusterIP Service).
step "generate load: burst POST /orders against order-service.${NS}.svc.cluster.local"

LOADGEN_POD="demo-keda-kafka-loadgen-$$"
ORDER_CREATE_BODY='{"customerId":"CUST-KEDA-DEMO","itemSku":"KEDA-DEMO-SKU","quantity":1,"amount":9.99}'
LOADGEN_SCRIPT="i=0; while [ \$i -lt 60 ]; do curl -s -o /dev/null -w '%{http_code} ' -X POST -H 'Content-Type: application/json' -d '${ORDER_CREATE_BODY}' http://order-service.${NS}.svc.cluster.local:8080/orders; i=\$((i+1)); done; echo"

_cleanup_loadgen_pod() {
    local rc=$?
    kubectl delete pod "$LOADGEN_POD" -n "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    return "$rc"
}
trap '_cleanup_loadgen_pod; _demo_exit_trap' EXIT

kubectl run "$LOADGEN_POD" -n "$NS" --restart=Never --image=curlimages/curl:8.11.1 \
    --command -- /bin/sh -c "$LOADGEN_SCRIPT" \
    || fail "failed to start load-generator pod ${LOADGEN_POD}"

# Wait for the burst to finish (budget covers 60 sequential requests plus
# gRPC-timeout-driven slow 503s: InventoryClient's CALL_TIMEOUT is 3s, so a
# worst case of 60 timed-out calls is ~180s).
LOADGEN_DONE=0
for (( i = 0; i < 200; i++ )); do
    phase="$(kubectl get pod "$LOADGEN_POD" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)"
    if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
        LOADGEN_DONE=1
        break
    fi
    sleep 1
done
(( LOADGEN_DONE == 1 )) || warn "load-generator pod did not finish within 200s — continuing anyway (it may still be driving load)"

LOADGEN_LOG="$(kubectl logs "$LOADGEN_POD" -n "$NS" 2>/dev/null || true)"
info "order-service response codes from the burst: ${LOADGEN_LOG:-<none captured>}"
if [[ -n "$LOADGEN_LOG" ]] && ! grep -q '201' <<<"$LOADGEN_LOG"; then
    warn "no HTTP 201 responses observed in the burst — the gRPC inventory wiring this flow depends on is canonical (port 9000; see this script's header), so investigate as a live-cluster issue: kubectl logs -n ${NS} -l app.kubernetes.io/name=order-service --tail=50, and confirm inventory-service's pod/service are Ready"
fi

# ─── Assert: replica count climbs off baseline within a scale-up budget ────
step "assert: notification-service replica count increases on lag"

SCALE_UP_BUDGET=180
SCALED_UP=0
CURRENT_REPLICAS="$BASELINE_REPLICAS"
for (( i = 0; i < SCALE_UP_BUDGET; i += 5 )); do
    CURRENT_REPLICAS="$(get_replicas)"
    if (( CURRENT_REPLICAS > BASELINE_REPLICAS )); then
        SCALED_UP=1
        break
    fi
    sleep 5
done

if (( SCALED_UP == 0 )); then
    fail "notification-service replicas did not increase above baseline (${BASELINE_REPLICAS}) within ${SCALE_UP_BUDGET}s of the load burst (last observed: ${CURRENT_REPLICAS}). The order-service -> inventory-service gRPC wiring is canonical on this substrate (port 9000 -- see this script's header), so this is not the previously-documented port gap; diagnose fresh. Check: kubectl logs -n ${NS} -l app.kubernetes.io/name=order-service --tail=50 (did POST /orders calls succeed?), kubectl get pods -n ${NS} -l app.kubernetes.io/name=inventory-service (is it Ready?), and whether lag actually crossed lagThreshold=5 on the ScaledObject."
fi
info "notification-service scaled from ${BASELINE_REPLICAS} to ${CURRENT_REPLICAS} replicas"

# ─── Assert: replica count drains back to baseline once lag clears + cooldown
step "assert: notification-service replica count drains back down"

# cooldownPeriod=120s (k8s/keda/consumer-scaledobject.yaml) + pollingInterval
# buffer + consumption time.
SCALE_DOWN_BUDGET=300
SCALED_DOWN=0
for (( i = 0; i < SCALE_DOWN_BUDGET; i += 10 )); do
    CURRENT_REPLICAS="$(get_replicas)"
    if (( CURRENT_REPLICAS <= BASELINE_REPLICAS )); then
        SCALED_DOWN=1
        break
    fi
    sleep 10
done

if (( SCALED_DOWN == 0 )); then
    fail "notification-service replicas did not drain back to baseline (${BASELINE_REPLICAS}) within ${SCALE_DOWN_BUDGET}s after the burst (last observed: ${CURRENT_REPLICAS}) — expected cooldownPeriod=120s (k8s/keda/consumer-scaledobject.yaml) to have elapsed well within this budget"
fi
info "notification-service drained back to ${CURRENT_REPLICAS} replicas (baseline was ${BASELINE_REPLICAS})"

narrate "KEDA scaled notification-service 0/${BASELINE_REPLICAS} -> up on Kafka lag and back down to"
narrate "baseline on drain + cooldown, driven entirely by the real k8s/keda/consumer-scaledobject.yaml"
narrate "trigger against the real order.placed topic."

demo_ok
