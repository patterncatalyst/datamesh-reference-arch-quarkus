#!/usr/bin/env bash
#
# cluster-status.sh — one-shot, read-only health report for the datamesh
# minikube substrate: profile, control plane, and every platform component
# bootstrap.sh can bring up (Istio, CNPG, Strimzi/Kafka, KEDA, LGTM, Kiali,
# Apicurio). Does not check application workloads — this is the substrate
# layer (step 9a); app-level health checks land with the app manifests.
#
# Read-only: it changes nothing. Use it any time something looks off, and as
# the closing summary of bootstrap.sh.
#
# Run from the project root:  ./scripts/cluster-status.sh

set -uo pipefail

PROFILE="datamesh"
NS="datamesh"
OBS_NS="${OBS_NAMESPACE:-observability}"

step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }   # check
warn() { printf '    \xe2\x9a\xa0 %s\n' "$1"; }   # warn
bad()  { printf '    \xe2\x9c\x97 %s\n' "$1"; }   # cross

PROBLEMS=0
note_problem() { PROBLEMS=$((PROBLEMS + 1)); }

# ─── Profile / node ──────────────────────────────────────────────────────────
step "minikube profile"
if minikube status -p "$PROFILE" >/dev/null 2>&1; then
    ok "profile '$PROFILE' is running"
else
    bad "profile '$PROFILE' is not running — start it with: ./scripts/bootstrap.sh"
    note_problem
    printf '\n(Stopping here — nothing else can be checked while the node is down.)\n'
    exit 1
fi

# ─── Control plane (the etcd-wedge check) ────────────────────────────────────
step "Control plane"
if kubectl get --raw='/readyz' >/dev/null 2>&1; then
    ok "API server is serving (/readyz)"
else
    bad "API server is NOT responding — control plane may be wedged"
    note_problem
fi
# A long-lived node can wedge etcd on its peer port (:2380), crashlooping it
# (Exit 1, not OOM) and taking the rest of the control plane down with it.
cp_bad="$(kubectl get pods -n kube-system 2>/dev/null \
    | grep -iE 'etcd|scheduler|controller-manager|apiserver' \
    | grep -ivE 'Running|Completed' || true)"
if [[ -n "$cp_bad" ]]; then
    bad "control-plane pods not healthy:"
    printf '%s\n' "$cp_bad" | sed 's/^/        /'
    warn "if etcd shows 'address already in use', cycle the node: minikube stop -p $PROFILE && minikube start -p $PROFILE"
    note_problem
else
    ok "etcd / scheduler / controller-manager all Running"
fi

# ─── Workload health by namespace ────────────────────────────────────────────
report_ns() {
    local ns="$1" label="$2"
    if ! kubectl get ns "$ns" >/dev/null 2>&1; then
        warn "${label}: namespace '${ns}' does not exist (component not installed / disabled)"
        return
    fi
    local bad_pods
    # Completed Jobs and 0-replica (KEDA-scaled) workloads are not failures.
    bad_pods="$(kubectl get pods -n "$ns" 2>/dev/null \
        | tail -n +2 | grep -ivE 'Running|Completed' || true)"
    if [[ -z "$bad_pods" ]]; then
        ok "${label}: all pods Running/Completed"
    else
        bad "${label}: pods not healthy:"
        printf '%s\n' "$bad_pods" | sed 's/^/        /'
        note_problem
    fi
}
step "Platform components"
report_ns istio-system    "istio-system (istiod, kiali)"
report_ns "$NS"           "$NS (CNPG cluster, Strimzi cluster, Apicurio)"
report_ns "$OBS_NS"       "$OBS_NS (Loki/Grafana/Tempo/Mimir/OTel Collector)"
report_ns keda            "keda (autoscaler + HTTP add-on)"
report_ns cnpg-system     "cnpg-system (CloudNativePG operator)"

# ─── Component-specific readiness ────────────────────────────────────────────
step "Component readiness"

if kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1; then
    pg_status="$(kubectl get pods -n "$NS" -l "cnpg.io/cluster,role=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "$pg_status" == "True" ]]; then
        ok "Postgres (CNPG) primary is Ready"
    else
        warn "Postgres (CNPG) primary not Ready (status: ${pg_status:-unknown})"
    fi
else
    warn "CNPG CRDs not found (Postgres disabled or not yet installed)"
fi

if kubectl get crd kafkas.kafka.strimzi.io >/dev/null 2>&1; then
    kafka_status="$(kubectl get kafka -n "$NS" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "$kafka_status" == "True" ]]; then
        ok "Kafka (Strimzi) cluster is Ready"
    else
        warn "Kafka (Strimzi) cluster not Ready (status: ${kafka_status:-unknown})"
    fi
else
    warn "Strimzi CRDs not found (Kafka disabled or not yet installed)"
fi

if kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1; then
    ok "KEDA CRDs present"
else
    warn "KEDA CRDs not found (KEDA disabled or not yet installed)"
fi

if kubectl get deploy istiod -n istio-system >/dev/null 2>&1; then
    ok "istiod present"
else
    warn "istiod not found (Istio disabled or not yet installed)"
fi

if kubectl get deploy -n istio-system -l app=kiali >/dev/null 2>&1 && \
   [[ -n "$(kubectl get deploy -n istio-system -l app=kiali -o name 2>/dev/null)" ]]; then
    ok "Kiali present"
else
    warn "Kiali not found (Kiali disabled or not yet installed)"
fi

if kubectl get deploy apicurio -n "$NS" >/dev/null 2>&1; then
    ok "Apicurio present"
else
    warn "Apicurio not found (disabled or not yet installed)"
fi

# ─── Verdict ─────────────────────────────────────────────────────────────────
step "Verdict"
if [[ $PROBLEMS -eq 0 ]]; then
    ok "cluster substrate looks healthy"
else
    bad "$PROBLEMS area(s) need attention (see above). Re-run ./scripts/bootstrap.sh to resume/heal."
    exit 1
fi
