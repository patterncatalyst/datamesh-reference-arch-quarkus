#!/usr/bin/env bash
#
# setup-kiali.sh — install Kiali (the mesh-visualization console) into the
# datamesh cluster via the upstream kiali-server Helm chart, wired to the
# EXISTING LGTM observability stack (installed by setup-lgtm.sh) rather than
# standing up its own Prometheus/Grafana/tracing backend.
#
# SINGLE-STACK WIRING (the whole point of this script): Kiali's chart
# defaults point at a bundled Prometheus. This project has no standalone
# Prometheus — Mimir (installed by setup-lgtm.sh) exposes a Prometheus-
# compatible query API at /prometheus, exactly like the Grafana datasource
# (scripts/grafana-datasources.yaml) already does. Kiali is pointed at that
# same endpoint, plus the existing Grafana and Tempo.
#
# Prerequisites (run these first):
#   - scripts/setup-istio.sh   (istiod)
#   - scripts/setup-lgtm.sh    (Mimir + Grafana + Tempo in the observability ns)
#
# ACCESS CONVENTION: NodePort published on 127.0.0.1 at profile creation
# (setup-profile.sh; map in demos/lib/endpoints.sh). The `deployment.service_type`/`deployment.node_port`
# --set keys below match the kiali-server chart's values schema as of the
# pinned version; unverified against a live install (see setup-lgtm.sh header
# for why — minikube bring-up was not executed in this step).
#
# Idempotent: helm upgrade --install.
#
# Usage (from the project root):
#   ./scripts/setup-kiali.sh
#
# Then view:
#   http://localhost:20001/kiali   (Graph -> namespace: datamesh)

set -euo pipefail

NS="datamesh"
PROFILE_NAME="${MINIKUBE_PROFILE:-datamesh}"
ISTIO_SYSTEM="istio-system"
OBS_NS="${OBS_NAMESPACE:-observability}"
KIALI_VERSION="${KIALI_VERSION:-2.23.0}"

# LGTM stack service endpoints (single-stack wiring targets — see setup-lgtm.sh
# and scripts/grafana-datasources.yaml for the same URLs).
PROM_URL="http://mimir-nginx.${OBS_NS}.svc.cluster.local:80/prometheus"
GRAFANA_IN_URL="http://grafana.${OBS_NS}.svc.cluster.local:80"
GRAFANA_EXT_URL="http://localhost:3000"          # what a browser uses (published NodePort)
TEMPO_URL="http://tempo.${OBS_NS}.svc.cluster.local:3200"

step() { printf '\n==> %s\n' "$1"; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────

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

kubectl get ns "$ISTIO_SYSTEM" >/dev/null 2>&1 \
    || { printf 'ERROR: namespace %s not found — run scripts/setup-istio.sh first.\n' "$ISTIO_SYSTEM" >&2; exit 1; }

# The single-stack wiring targets should exist; warn (not fail) so Kiali can
# still come up for topology even if the LGTM stack is mid-install.
if ! kubectl get svc mimir-nginx -n "$OBS_NS" >/dev/null 2>&1; then
    printf 'WARNING: %s/mimir-nginx not found. Kiali will install but its\n' "$OBS_NS" >&2
    printf 'metrics integration will be dark until scripts/setup-lgtm.sh has run.\n' >&2
fi

# ─── 1. kiali helm repo ───────────────────────────────────────────────────────

step "Ensuring the kiali helm repo is registered"
if helm repo list 2>/dev/null | grep -q '^kiali[[:space:]]'; then
    helm repo update kiali >/dev/null
else
    helm repo add kiali https://kiali.org/helm-charts
    helm repo update kiali >/dev/null
fi

# ─── 2. install kiali-server, wired to the LGTM stack ────────────────────────

step "Installing kiali-server ${KIALI_VERSION} into ${ISTIO_SYSTEM}, wired to LGTM"
printf '    prometheus (Mimir): %s\n' "$PROM_URL"
printf '    grafana:            %s (in-cluster) / %s (browser)\n' "$GRAFANA_IN_URL" "$GRAFANA_EXT_URL"
printf '    tracing (Tempo):    %s\n' "$TEMPO_URL"

helm upgrade --install kiali-server kiali/kiali-server \
    --namespace "$ISTIO_SYSTEM" \
    --version "$KIALI_VERSION" \
    --set auth.strategy=anonymous \
    --set deployment.view_only_mode=false \
    --set deployment.service_type=NodePort \
    --set deployment.node_port=30201 \
    --set external_services.istio.root_namespace="$ISTIO_SYSTEM" \
    --set external_services.prometheus.url="$PROM_URL" \
    --set external_services.grafana.enabled=true \
    --set external_services.grafana.internal_url="$GRAFANA_IN_URL" \
    --set external_services.grafana.external_url="$GRAFANA_EXT_URL" \
    --set external_services.tracing.enabled=true \
    --set external_services.tracing.provider=tempo \
    --set external_services.tracing.internal_url="$TEMPO_URL" \
    --set external_services.tracing.use_grpc=false \
    --wait --timeout 5m

# ─── Done ────────────────────────────────────────────────────────────────────

step "Kiali is installed and wired to the LGTM observability stack."
printf '\nView the mesh topology (NodePort published on 127.0.0.1):\n'
printf '  http://localhost:20001/kiali   (Graph -> namespace: %s)\n' "$NS"
printf '\nNote: the live traffic graph only shows edges while traffic is flowing —\n'
printf 'the mesh graph is quiet until a service is opted into the mesh (see\n'
printf 'setup-istio.sh) and is receiving traffic.\n'
