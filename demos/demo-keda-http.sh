#!/usr/bin/env bash
#
# demos/demo-keda-http.sh — "minikube" group demo, opt-in.
#
# KEDA HTTP add-on scaling graphql-gateway from zero on inbound HTTP request
# rate, using the real minikube substrate already brought up by this repo's
# bootstrap — nothing here is invented:
#
#   k8s/base/graphql-gateway.yaml          — the Deployment/Service KEDA scales
#   k8s/keda/gateway-httpscaledobject.yaml — the HTTPScaledObject
#                                             (http.keda.sh/v1alpha1, KEDA HTTP
#                                             add-on 0.15.0)
#   k8s/overlays/minikube/                 — the app overlay (images ->
#                                             minikube docker daemon)
#   scripts/bootstrap.sh                   — brings up the minikube profile
#                                             ("datamesh") + the KEDA tier
#                                             (scripts/setup-keda.sh, pins the
#                                             HTTP add-on to 0.15.0 — matches the
#                                             python reference; the v0.14.0
#                                             interceptor panic #1668 is fixed
#                                             before 0.15.0)
#
# HTTPScaledObject (see k8s/keda/gateway-httpscaledobject.yaml and its header
# comment for full sourcing): targets Deployment/Service graphql-gateway
# (port 8080), hosts=[graphql-gateway.datamesh.svc.cluster.local],
# pathPrefixes=[/graphql], replicas.min=0/max=10,
# scalingMetric.requestRate.targetValue=50 per 1m window (granularity 1s).
# There is no Ingress/external hostname in this stack (see that file's own
# header) — all traffic that counts toward the scaler MUST go through the
# KEDA HTTP add-on's own interceptor proxy Service
# (keda-add-ons-http-interceptor-proxy.keda.svc.cluster.local, installed by
# scripts/setup-keda.sh's `keda-add-ons-http` helm release) with the Host
# header set to the hosts entry above — exactly the invocation
# k8s/keda/README.md documents under "gateway-httpscaledobject.yaml — observe
# scale 0→N on HTTP load". Requests sent directly to graphql-gateway's own
# ClusterIP Service bypass the interceptor entirely and would NOT be counted
# by the scaler or wake a scaled-to-zero Deployment — this demo deliberately
# routes through the interceptor, not the Service, for that reason.
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
# Same reasoning as demo-keda-kafka.sh's header: this environment has no
# standalone `kustomize` binary (only kubectl's bundled kustomize v5.7.1 —
# confirmed via `kubectl version --client`), matching k8s/keda/README.md's
# own documented validation method ("Rendering was verified with `kubectl
# kustomize ...` — no cluster required for that check"). This demo `require`s
# `kubectl` (not a separate `kustomize` binary) and uses `kubectl kustomize`
# for the static render checks below.
#
# ── Why this demo is NOT blocked by the inventory-service gap ───────────────
# Unlike demo-keda-kafka.sh (whose load path goes through order-service's
# gRPC-gated POST /orders, which 503s on this substrate — see that script's
# header for the full gap writeup), the KEDA HTTP add-on's interceptor
# proxy counts REQUEST ARRIVALS, not successful business responses: it
# forwards (or queues, while cold-starting a replica) every request matching
# hosts/pathPrefixes regardless of what graphql-gateway ultimately returns.
# A GraphQL query against /graphql with no body/variables will typically
# come back as an HTTP 4xx from graphql-gateway itself (or a 502 while no
# replica is up yet and the interceptor is still waiting on
# interceptor.replicas.waitTimeout=180s, per scripts/setup-keda.sh) — either
# way, the request still counts toward requestRate and still demonstrates
# scale-from-zero. This demo does not assert on the HTTP status code it gets
# back, only on the resulting replica count (a real, positive-content
# jsonpath assertion), which is the thing this demo is actually about.
#
# ── Cleanup ──────────────────────────────────────────────────────────────────
# The only resource this demo itself CREATES is a single throwaway load-
# generator Pod (`kubectl run ... --restart=Never`) in the datamesh
# namespace; it is deleted in the EXIT trap. The app Deployment / KEDA
# HTTPScaledObject applied via `kubectl apply -k` are the standing step-9
# substrate and are intentionally left in place, not torn down.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-keda-http"
require kubectl minikube curl jq

PROFILE="datamesh"
NS="datamesh"
KEDA_NS="keda"
K8S_DIR="${REPO_ROOT}/k8s"
INTERCEPTOR_HOST="keda-add-ons-http-interceptor-proxy.${KEDA_NS}.svc.cluster.local"
SCALED_HOST="graphql-gateway.${NS}.svc.cluster.local"

narrate "KEDA HTTP add-on scaling graphql-gateway 0 -> N on inbound request"
narrate "rate through the interceptor proxy, exactly as k8s/keda/README.md"
narrate "documents. Targets the real step-9 substrate manifests — see this"
narrate "script's header for exact file references."

# ─── Static manifest validation (no cluster required) ───────────────────────
step "static validation: kubectl kustomize (no cluster required)"

APP_RENDER_LOG="$(mktemp -t demo-keda-http-app-render-XXXXXX)"
if kubectl kustomize "${K8S_DIR}/overlays/minikube" >"$APP_RENDER_LOG" 2>&1; then
    check "k8s/overlays/minikube renders" "true" "n/a"
else
    cat "$APP_RENDER_LOG" >&2
    check "k8s/overlays/minikube renders" "false" "inspect the kustomization under k8s/overlays/minikube and k8s/base"
fi
check "rendered overlay contains graphql-gateway Deployment" \
    "grep -q 'name: graphql-gateway' '$APP_RENDER_LOG'" \
    "check k8s/base/graphql-gateway.yaml and k8s/base/kustomization.yaml"
check "rendered graphql-gateway Service exposes port 8080" \
    "grep -q 'port: 8080' '$APP_RENDER_LOG'" \
    "check k8s/base/graphql-gateway.yaml's Service spec.ports"

KEDA_RENDER_LOG="$(mktemp -t demo-keda-http-keda-render-XXXXXX)"
if kubectl kustomize "${K8S_DIR}/keda" >"$KEDA_RENDER_LOG" 2>&1; then
    check "k8s/keda renders" "true" "n/a"
else
    cat "$KEDA_RENDER_LOG" >&2
    check "k8s/keda renders" "false" "inspect k8s/keda/kustomization.yaml and its two resource files"
fi
check "rendered k8s/keda contains the HTTPScaledObject kind" \
    "grep -q '^kind: HTTPScaledObject$' '$KEDA_RENDER_LOG'" \
    "check k8s/keda/gateway-httpscaledobject.yaml's apiVersion/kind"
check "rendered HTTPScaledObject is named graphql-gateway-httpscaledobject" \
    "grep -q 'name: graphql-gateway-httpscaledobject' '$KEDA_RENDER_LOG'" \
    "check k8s/keda/gateway-httpscaledobject.yaml's metadata.name"
check "rendered HTTPScaledObject targets the real Service/host" \
    "grep -q '${SCALED_HOST}' '$KEDA_RENDER_LOG'" \
    "check k8s/keda/gateway-httpscaledobject.yaml's spec.hosts"
check "rendered HTTPScaledObject allows scale-to-zero (replicas.min: 0)" \
    "grep -A2 '^  replicas:' '$KEDA_RENDER_LOG' | grep -q 'min: 0'" \
    "check k8s/keda/gateway-httpscaledobject.yaml's spec.replicas.min"

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

step "live preflight: namespace + KEDA HTTP add-on"
kubectl get namespace "$NS" >/dev/null 2>&1 \
    || fail "namespace '${NS}' does not exist — run ./scripts/bootstrap.sh first"
kubectl get crd httpscaledobjects.http.keda.sh >/dev/null 2>&1 \
    || fail "KEDA HTTP add-on CRDs not found — run ./scripts/setup-keda.sh (or ./scripts/bootstrap.sh with ENABLE_KEDA=true, the default)"
kubectl get svc keda-add-ons-http-interceptor-proxy -n "$KEDA_NS" >/dev/null 2>&1 \
    || fail "interceptor proxy Service 'keda-add-ons-http-interceptor-proxy' not found in namespace ${KEDA_NS} — the KEDA HTTP add-on helm release (scripts/setup-keda.sh) may not have installed correctly"
info "namespace '${NS}' exists, KEDA HTTP add-on CRDs installed, interceptor proxy Service present"

step "apply the real app overlay + KEDA scalers"
kubectl apply -k "${K8S_DIR}/overlays/minikube" \
    || fail "kubectl apply -k k8s/overlays/minikube failed"
kubectl apply -k "${K8S_DIR}/keda" \
    || fail "kubectl apply -k k8s/keda failed"
info "applied k8s/overlays/minikube and k8s/keda"

kubectl get deployment graphql-gateway -n "$NS" >/dev/null 2>&1 \
    || fail "deployment/graphql-gateway not found in namespace ${NS} after apply"

# ─── Replica-count helper (positive-content jsonpath parse, never bare exit 0)
get_replicas() {
    local val
    val="$(kubectl get deployment graphql-gateway -n "$NS" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)"
    [[ "$val" =~ ^[0-9]+$ ]] || val=0
    echo "$val"
}

BASELINE_REPLICAS="$(get_replicas)"
info "baseline graphql-gateway replicas: ${BASELINE_REPLICAS}"

# ─── Generate load: burst GET requests through the interceptor proxy with the
# Host header the HTTPScaledObject matches on (k8s/keda/README.md's own
# documented invocation), via a throwaway in-cluster pod — there is no
# Ingress/external hostname in this stack, so this MUST run in-cluster.
step "generate load: burst requests through the KEDA HTTP add-on interceptor"

LOADGEN_POD="demo-keda-http-loadgen-$$"
# 120 requests, comfortably above scalingMetric.requestRate.targetValue=50
# per 1m window (k8s/keda/gateway-httpscaledobject.yaml). --max-time bounds
# each request so a cold-starting backend (interceptor.replicas.waitTimeout=
# 180s, scripts/setup-keda.sh) can't stall the whole burst indefinitely.
LOADGEN_SCRIPT="i=0; while [ \$i -lt 120 ]; do curl -s -o /dev/null --max-time 5 -w '%{http_code} ' -H 'Host: ${SCALED_HOST}' http://${INTERCEPTOR_HOST}/graphql; i=\$((i+1)); done; echo"

_cleanup_loadgen_pod() {
    local rc=$?
    kubectl delete pod "$LOADGEN_POD" -n "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    return "$rc"
}
trap '_cleanup_loadgen_pod; _demo_exit_trap' EXIT

kubectl run "$LOADGEN_POD" -n "$NS" --restart=Never --image=curlimages/curl:8.11.1 \
    --command -- /bin/sh -c "$LOADGEN_SCRIPT" \
    || fail "failed to start load-generator pod ${LOADGEN_POD}"

# Wait for the burst to finish (120 requests x up to 5s --max-time each in
# the worst case of a slow cold start, bounded by this budget).
LOADGEN_DONE=0
for (( i = 0; i < 240; i++ )); do
    phase="$(kubectl get pod "$LOADGEN_POD" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)"
    if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
        LOADGEN_DONE=1
        break
    fi
    sleep 1
done
(( LOADGEN_DONE == 1 )) || warn "load-generator pod did not finish within 240s — continuing anyway (it may still be driving load)"

LOADGEN_LOG="$(kubectl logs "$LOADGEN_POD" -n "$NS" 2>/dev/null || true)"
info "interceptor response codes from the burst: ${LOADGEN_LOG:-<none captured>}"

# ─── Assert: replica count climbs off baseline (wakes from scale-to-zero) ───
step "assert: graphql-gateway replica count increases on HTTP load"

SCALE_UP_BUDGET=240
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
    fail "graphql-gateway replicas did not increase above baseline (${BASELINE_REPLICAS}) within ${SCALE_UP_BUDGET}s of the load burst (last observed: ${CURRENT_REPLICAS}). Check: requests actually reached the interceptor (kubectl logs -n ${KEDA_NS} -l app=keda-add-ons-http-interceptor), the Host header matched spec.hosts exactly (${SCALED_HOST}), and the HTTPScaledObject's status: kubectl get httpscaledobject graphql-gateway-httpscaledobject -n ${NS} -o yaml."
fi
info "graphql-gateway scaled from ${BASELINE_REPLICAS} to ${CURRENT_REPLICAS} replicas"

narrate "KEDA's HTTP add-on woke graphql-gateway from ${BASELINE_REPLICAS} replica(s) to"
narrate "${CURRENT_REPLICAS} in response to inbound HTTP load routed through the real"
narrate "interceptor proxy and the real k8s/keda/gateway-httpscaledobject.yaml trigger."

demo_ok
