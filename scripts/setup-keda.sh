#!/usr/bin/env bash
#
# setup-keda.sh — install KEDA (core + HTTP add-on) into the datamesh cluster,
# in preparation for the two DRQ-011 autoscalers (Phase C lands the substrate;
# the demo-keda-*.sh demos land in Phase D):
#   * Kafka consumer-lag scaling for notification-service (core KEDA;
#     notification-service consumes order.placed)
#   * HTTP request scaling for graphql-gateway (the HTTP add-on)
#
# Run-once-per-cluster, separate from the app releases. Idempotent.
#
# Usage (from the project root):
#   ./scripts/setup-keda.sh
#
# Then, once the scaler manifests exist (Phase D):
#   kubectl apply -f keda/notification-scaledobject.yaml
#   kubectl apply -f keda/gateway-httpscaledobject.yaml

set -euo pipefail

NAMESPACE="keda"
PROFILE_NAME="datamesh"
KEDA_VERSION="${KEDA_VERSION:-2.19.0}"
# 0.15.0 — matches the datamesh-reference-arch-python reference (proven there)
# and enables HTTP/REST request-rate scaling for graphql-gateway. The v0.14.0
# interceptor POST-forwarding panic (kedacore/http-add-on#1668, "invalid
# concurrent Body.Read call") is CLOSED — introduced in 0.14.0 and fixed before
# 0.15.0 (Jun 2025). 0.15.0 also adds HTTP/2 + gRPC scaling and cold-start
# placeholder responses. (0.16.0 is newer but we track the python-proven pin.)
KEDA_HTTP_VERSION="${KEDA_HTTP_VERSION:-0.15.0}"

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }
command -v helm    >/dev/null 2>&1 || { printf 'ERROR: helm not in PATH.\n' >&2; exit 1; }

current_context="$(kubectl config current-context 2>/dev/null || echo "")"
if [[ "$current_context" != "$PROFILE_NAME" ]]; then
    printf 'WARNING: current kubectl context is "%s", not "%s".\n' "$current_context" "$PROFILE_NAME" >&2
    printf 'Switch with: kubectl config use-context %s\n' "$PROFILE_NAME" >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── 1. kedacore helm repo ───────────────────────────────────────────────────
printf '==> Ensuring the kedacore helm repo is registered\n'
if helm repo list 2>/dev/null | grep -q '^kedacore'; then
    helm repo update kedacore >/dev/null
else
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update kedacore >/dev/null
fi

# ─── 2. KEDA core ────────────────────────────────────────────────────────────
printf '==> Installing KEDA core %s into namespace %s\n' "$KEDA_VERSION" "$NAMESPACE"
helm upgrade --install keda kedacore/keda \
    --version "$KEDA_VERSION" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait

# ─── 3. KEDA HTTP add-on ─────────────────────────────────────────────────────
printf '==> Installing the KEDA HTTP add-on %s into namespace %s\n' "$KEDA_HTTP_VERSION" "$NAMESPACE"
# interceptor.replicas.waitTimeout (default 20s) is how long the interceptor
# holds a request waiting for the scaled-from-zero workload to have a Ready
# replica. 20s is too short for a JVM cold start (KEDA activation + image
# pull + Quarkus boot + startupProbe), so requests 502 with "context deadline
# exceeded" BEFORE a backend exists — which also starves KEDA of the stable
# pending-request pressure it needs to activate promptly. 180s holds the
# request through the whole cold start.
helm upgrade --install keda-add-ons-http kedacore/keda-add-ons-http \
    --version "$KEDA_HTTP_VERSION" \
    --namespace "$NAMESPACE" \
    --set interceptor.replicas.waitTimeout=180s \
    --wait

# ─── Done ────────────────────────────────────────────────────────────────────
printf '\n==> KEDA core + HTTP add-on installed in the %s namespace.\n\n' "$NAMESPACE"
printf 'Scaler manifests land in Phase D. Once applied:\n'
printf '  kubectl apply -f keda/notification-scaledobject.yaml   # Kafka lag, notification-service\n'
printf '  kubectl apply -f keda/gateway-httpscaledobject.yaml    # HTTP volume, graphql-gateway\n'
