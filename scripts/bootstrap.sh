#!/usr/bin/env bash
#
# bootstrap.sh — stand up the datamesh-reference-arch-quarkus minikube substrate
# from a fresh node, in the correct order, with a health gate between each tier.
#
# SUPPORTED HOSTS: Fedora or RHEL (bare metal or VM), Docker Engine.
#
# HOST RESOURCE REQUIREMENTS (heavy profile — Istio + Kiali + KEDA + LGTM +
# Strimzi + CNPG + Apicurio are ALL ON by default):
#   - Host RAM:  >= 32 GB recommended (64 GB verified-comfortable). The
#     minikube profile itself is sized at 24 GB / 16 vCPUs / 80 GB disk
#     (see setup-profile.sh); leave that much headroom over the profile's
#     footprint for the host OS, IDE, browser, etc.
#   - Host CPU:  >= 8 physical cores recommended; profile requests 16 vCPUs
#     but minikube will spread across whatever the host actually has.
#   - Host disk: >= 30 GB free beyond the profile's 80 GB disk image, for the
#     container image cache and growing PVs.
#   - Idle in-cluster footprint with every flag on (approximate, see
#     references/opt-in-flags.md and references/lgtm-on-minikube-sizing.md in
#     the lgtm-minikube-stack skill): Istio ~150 MiB, CNPG cluster ~200 MiB,
#     Strimzi + Kafka ~600 MiB, KEDA ~150 MiB, LGTM (Loki+Grafana+Tempo+Mimir+
#     Collector) ~1.4 GiB, Kiali ~100 MiB, Apicurio ~250 MiB — roughly
#     ~2.9 GiB idle, comfortably inside the 24 GB profile.
#   - Toolchain: minikube (--driver=docker), kubectl, helm, docker. Docker Engine.
#
# Tiers (each gated on health before the next):
#   1. minikube profile (docker driver)              —
#   2. Istio control plane                           (ENABLE_ISTIO, default true)
#   3. CloudNativePG operator + Postgres cluster CR  (ENABLE_POSTGRES, default true)
#   4. Strimzi operator + Kafka cluster CR           (ENABLE_KAFKA, default true)
#   5. KEDA core + HTTP add-on (pinned 0.15.0)       (ENABLE_KEDA, default true)
#   6. LGTM observability stack                      (ENABLE_LGTM, default true)
#      (Loki + Grafana + Tempo + Mimir + OTel Collector)
#   7. Kiali mesh-topology UI                         (ENABLE_KIALI, default = ENABLE_ISTIO)
#   8. Apicurio schema registry (3.x, v3 API)         (ENABLE_APICURIO, default true)
#
# Idempotent: helm upgrade --install, kubectl apply, kubectl wait — re-running
# resumes safely after an interrupted run.
#
# Run from the project root:
#   ./scripts/bootstrap.sh
#
# Override defaults via env:
#   ENABLE_KAFKA=false ENABLE_POSTGRES=false ./scripts/bootstrap.sh

set -uo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
PROFILE="${MINIKUBE_PROFILE:-datamesh}"
NS="datamesh"
OBS_NS="${OBS_NAMESPACE:-observability}"

# Feature flags. Defaults: Istio+Kiali
# ON (mesh kept), KEDA on (notification-service Kafka-lag scaler + gateway
# HTTP scaler land later via separate demos), Apicurio needed for Avro schemas.
ENABLE_ISTIO="${ENABLE_ISTIO:-true}"
ENABLE_POSTGRES="${ENABLE_POSTGRES:-true}"
ENABLE_KAFKA="${ENABLE_KAFKA:-true}"
ENABLE_KEDA="${ENABLE_KEDA:-true}"
ENABLE_LGTM="${ENABLE_LGTM:-true}"
ENABLE_KIALI="${ENABLE_KIALI:-${ENABLE_ISTIO}}"
ENABLE_APICURIO="${ENABLE_APICURIO:-true}"

# ─── Helpers ────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }
skip() { printf '    \xe2\x97\x8b %s\n' "$1"; }
fail() { printf '\n\xe2\x9c\x97 %s\n' "$1" >&2; exit 1; }

# Sanity-check dependency relationships before doing any work.
if [[ "$ENABLE_KIALI" == "true" && "$ENABLE_ISTIO" != "true" ]]; then
    fail "ENABLE_KIALI=true requires ENABLE_ISTIO=true (Kiali shows mesh topology)"
fi
if [[ "$ENABLE_APICURIO" == "true" && "$ENABLE_KAFKA" != "true" ]]; then
    printf 'NOTE: ENABLE_APICURIO=true without ENABLE_KAFKA=true — registry will be installed but unused.\n'
fi

# Print the active configuration so the user sees what's about to run.
printf '\n\033[1m==> Active configuration\033[0m\n'
printf '    profile:    %s\n' "$PROFILE"
printf '    namespace:  %s\n' "$NS"
printf '    obs ns:     %s\n' "$OBS_NS"
printf '    Istio:           %s\n' "$ENABLE_ISTIO"
printf '    Postgres (CNPG): %s\n' "$ENABLE_POSTGRES"
printf '    Kafka (Strimzi): %s\n' "$ENABLE_KAFKA"
printf '    KEDA:            %s\n' "$ENABLE_KEDA"
printf '    LGTM:            %s\n' "$ENABLE_LGTM"
printf '    Kiali:           %s\n' "$ENABLE_KIALI"
printf '    Apicurio:        %s\n' "$ENABLE_APICURIO"

# ─── Tier 1: profile ────────────────────────────────────────────────────────
step "1/8 minikube profile (docker driver)"
./scripts/setup-profile.sh || fail "profile setup failed"
[[ "$(kubectl config current-context 2>/dev/null)" == "$PROFILE" ]] || kubectl config use-context "$PROFILE"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "profile up, context set, namespace $NS exists"

# ─── Tier 2: Istio ──────────────────────────────────────────────────────────
step "2/8 Istio control plane"
if [[ "$ENABLE_ISTIO" == "true" ]]; then
    if kubectl get ns istio-system >/dev/null 2>&1 && kubectl get deploy istiod -n istio-system >/dev/null 2>&1; then
        ok "istiod already present"
    else
        ./scripts/setup-istio.sh || fail "istio setup failed"
    fi
    kubectl wait -n istio-system --for=condition=Available deploy/istiod --timeout=180s || fail "istiod not Available"
    ok "istiod Available"
else
    skip "Istio disabled"
fi

# ─── Tier 3: CloudNativePG operator + Postgres cluster CR ───────────────────
step "3/8 CloudNativePG operator + Postgres cluster CR"
if [[ "$ENABLE_POSTGRES" == "true" ]]; then
    ./scripts/setup-postgres-operator.sh "$NS" || fail "postgres-operator/CR setup failed"
    ok "CNPG operator installed, Postgres primary Ready"
else
    skip "Postgres disabled (operator + cluster CR not installed)"
fi

# ─── Tier 4: Kafka operator + cluster CR ────────────────────────────────────
step "4/8 Kafka (Strimzi operator + cluster CR)"
if [[ "$ENABLE_KAFKA" == "true" ]]; then
    ./scripts/setup-kafka-operator.sh || fail "kafka-operator setup failed"
    ok "Kafka cluster Ready"
else
    skip "Kafka disabled"
fi

# ─── Tier 5: KEDA ───────────────────────────────────────────────────────────
step "5/8 KEDA (core + HTTP add-on, pinned 0.15.0)"
if [[ "$ENABLE_KEDA" == "true" ]]; then
    if kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1; then
        ok "KEDA CRDs already present"
    else
        ./scripts/setup-keda.sh || fail "keda setup failed"
    fi
else
    skip "KEDA disabled"
fi

# ─── Tier 6: LGTM observability stack ───────────────────────────────────────
step "6/8 LGTM observability stack (Loki + Grafana + Tempo + Mimir + Collector)"
if [[ "$ENABLE_LGTM" == "true" ]]; then
    ./scripts/setup-lgtm.sh || fail "LGTM setup failed"
    ok "LGTM stack installed (namespace: $OBS_NS)"
else
    skip "LGTM disabled"
fi

# ─── Tier 7: Kiali ──────────────────────────────────────────────────────────
step "7/8 Kiali (mesh-topology UI)"
if [[ "$ENABLE_KIALI" == "true" ]]; then
    ./scripts/setup-kiali.sh || fail "kiali setup failed"
    ok "Kiali installed"
else
    skip "Kiali disabled"
fi

# ─── Tier 8: Apicurio ────────────────────────────────────────────────────────
step "8/8 Apicurio schema registry (3.x, v3 API)"
if [[ "$ENABLE_APICURIO" == "true" ]]; then
    ./scripts/setup-apicurio.sh "$NS" || fail "apicurio setup failed"
    ok "Apicurio installed"
else
    skip "Apicurio disabled"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
step "Bring-up complete."
cat <<EOF

    Service images:        ./scripts/load-images.sh   (build + load into the profile; the KEDA demos need them)
    Cluster status:        ./scripts/cluster-status.sh
    Host access:           NodePorts published on 127.0.0.1 (./scripts/show-endpoints.sh)
    Tear down the profile: ./scripts/teardown.sh

EOF
./scripts/show-endpoints.sh || fail "show-endpoints.sh reported a problem: a port is unpublished or the cluster is not reachable"
printf '\n'
