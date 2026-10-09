#!/usr/bin/env bash
#
# setup-lgtm.sh — install the LGTM observability stack into the cluster.
#
#   Loki (L)   — log aggregation, single-binary mode, filesystem storage
#   Grafana (G) — visualization, with datasources + dashboards provisioned
#   Tempo (T)   — distributed tracing, monolithic mode, filesystem storage
#   Mimir (M)   — metrics, monolithic mode (single binary), filesystem storage
#   OTel Collector — single deployment pod that receives OTLP and routes
#                    signals to the three backends
#
# All four storage components run in monolithic / single-binary mode because
# this is a single-node minikube. Production deployments use distributed mode
# (separate ingester / distributor / querier / etc.); that's appropriate when
# you have nodes to spread across, not when you have one.
#
# Apps emit OTLP to the Collector at otel-collector.<obs_ns>.svc.cluster.local
# (HTTP on 4318, gRPC on 4317). The Collector routes:
#   logs    -> Loki  (loki-gateway.<obs_ns>.svc:80, /loki/api/v1/push)
#   traces  -> Tempo (tempo.<obs_ns>.svc:4317 OTLP gRPC)
#   metrics -> Mimir (mimir-nginx.<obs_ns>.svc:80, /api/v1/push)
#
# ACCESS CONVENTION (repo-wide — see references/ports-and-endpoints.md in the
# lgtm-minikube-stack skill): host access is via NodePorts published on
# 127.0.0.1 when the minikube profile is created (setup-profile.sh); the
# canonical map is demos/lib/endpoints.sh. Each chart below is installed with a NodePort service at
# the fixed port from that allocation map. NOTE: these --set overrides use
# each chart's documented values-schema key as of the pinned chart version
# below; they have not been verified against a live install in this
# environment (minikube bring-up was not executed in this step) — re-check
# `helm show values <chart> --version <pinned>` if a NodePort doesn't appear
# after install.
#
# Idempotent: helm upgrade --install everywhere, kubectl apply for the
# config-only resources.
#
# Usage:
#   ./scripts/setup-lgtm.sh

set -euo pipefail

NAMESPACE="${OBS_NAMESPACE:-observability}"

# Chart versions — pinned for reproducibility. Bump deliberately, not by drift.
LOKI_VERSION="${LOKI_VERSION:-6.16.0}"
TEMPO_VERSION="${TEMPO_VERSION:-1.10.0}"
MIMIR_VERSION="${MIMIR_VERSION:-5.4.0}"
GRAFANA_VERSION="${GRAFANA_VERSION:-8.5.0}"
OTEL_COLLECTOR_VERSION="${OTEL_COLLECTOR_VERSION:-0.97.0}"

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }
command -v helm    >/dev/null 2>&1 || { printf 'ERROR: helm not in PATH.\n' >&2; exit 1; }

# ─── helm repos ─────────────────────────────────────────────────────────────
printf '==> Ensuring helm repos are registered\n'
for repo in \
    "grafana=https://grafana.github.io/helm-charts" \
    "open-telemetry=https://open-telemetry.github.io/opentelemetry-helm-charts"
do
    name="${repo%=*}"; url="${repo#*=}"
    if helm repo list 2>/dev/null | grep -q "^${name}[[:space:]]"; then
        helm repo update "$name" >/dev/null
    else
        helm repo add "$name" "$url"
    fi
done
helm repo update grafana open-telemetry >/dev/null 2>&1 || true

# ─── Namespace ──────────────────────────────────────────────────────────────
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# ─── Apply the project's grafana datasource + dashboard ConfigMaps ─────────
# (These ship alongside this script under scripts/; created before Grafana
# installs so the chart's sidecar can mount them.)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT}/scripts/grafana-datasources.yaml" ]]; then
    printf '==> Applying Grafana datasource ConfigMap\n'
    kubectl apply -n "$NAMESPACE" -f "${ROOT}/scripts/grafana-datasources.yaml"
fi
if [[ -d "${ROOT}/scripts/grafana-dashboards" ]]; then
    printf '==> Applying Grafana dashboard ConfigMaps\n'
    for f in "${ROOT}"/scripts/grafana-dashboards/*.yaml; do
        [[ -f "$f" ]] && kubectl apply -n "$NAMESPACE" -f "$f"
    done
fi

# ─── Loki (single-binary mode) ──────────────────────────────────────────────
printf '==> Installing Loki %s (single-binary mode)\n' "$LOKI_VERSION"
helm upgrade --install loki grafana/loki \
    --version "$LOKI_VERSION" \
    --namespace "$NAMESPACE" \
    --wait \
    --set deploymentMode=SingleBinary \
    --set 'loki.commonConfig.replication_factor=1' \
    --set 'loki.storage.type=filesystem' \
    --set 'loki.auth_enabled=false' \
    --set 'loki.schemaConfig.configs[0].from=2024-01-01' \
    --set 'loki.schemaConfig.configs[0].store=tsdb' \
    --set 'loki.schemaConfig.configs[0].object_store=filesystem' \
    --set 'loki.schemaConfig.configs[0].schema=v13' \
    --set 'loki.schemaConfig.configs[0].index.prefix=loki_index_' \
    --set 'loki.schemaConfig.configs[0].index.period=24h' \
    --set 'singleBinary.replicas=1' \
    --set 'singleBinary.persistence.enabled=true' \
    --set 'singleBinary.persistence.size=5Gi' \
    --set 'chunksCache.enabled=false' \
    --set 'resultsCache.enabled=false' \
    --set 'minio.enabled=false' \
    --set 'read.replicas=0' \
    --set 'write.replicas=0' \
    --set 'backend.replicas=0' \
    --set 'gateway.enabled=true' \
    --set 'gateway.replicas=1' \
    --set 'gateway.service.type=NodePort' \
    --set 'gateway.service.nodePort=30100' \
    --set 'lokiCanary.enabled=false' \
    --set 'test.enabled=false'

# ─── Tempo (monolithic mode) ────────────────────────────────────────────────
printf '==> Installing Tempo %s (monolithic mode)\n' "$TEMPO_VERSION"
helm upgrade --install tempo grafana/tempo \
    --version "$TEMPO_VERSION" \
    --namespace "$NAMESPACE" \
    --wait \
    --set 'tempo.storage.trace.backend=local' \
    --set 'tempo.storage.trace.local.path=/var/tempo/traces' \
    --set 'persistence.enabled=true' \
    --set 'persistence.size=5Gi' \
    --set 'tempo.receivers.otlp.protocols.grpc.endpoint=0.0.0.0:4317' \
    --set 'tempo.receivers.otlp.protocols.http.endpoint=0.0.0.0:4318' \
    --set 'service.type=NodePort' \
    --set 'service.nodePort=30320'

# ─── Mimir (monolithic mode) ────────────────────────────────────────────────
printf '==> Installing Mimir %s (monolithic mode)\n' "$MIMIR_VERSION"
helm upgrade --install mimir grafana/mimir-distributed \
    --version "$MIMIR_VERSION" \
    --namespace "$NAMESPACE" \
    --wait \
    --set 'metaMonitoring.serviceMonitor.enabled=false' \
    --set 'minio.enabled=false' \
    --set 'mimir.structuredConfig.common.storage.backend=filesystem' \
    --set 'mimir.structuredConfig.common.storage.filesystem.dir=/data/common' \
    --set 'mimir.structuredConfig.blocks_storage.backend=filesystem' \
    --set 'mimir.structuredConfig.blocks_storage.filesystem.dir=/data/blocks' \
    --set 'mimir.structuredConfig.ruler_storage.backend=filesystem' \
    --set 'mimir.structuredConfig.ruler_storage.filesystem.dir=/data/ruler' \
    --set 'mimir.structuredConfig.alertmanager_storage.backend=filesystem' \
    --set 'mimir.structuredConfig.alertmanager_storage.filesystem.dir=/data/alertmanager' \
    --set 'mimir.structuredConfig.compactor.data_dir=/data/compactor' \
    --set 'mimir.structuredConfig.ruler.rule_path=/data/ruler-work' \
    --set 'mimir.structuredConfig.alertmanager.data_dir=/data/alertmanager-work' \
    --set 'nginx.service.type=NodePort' \
    --set 'nginx.service.nodePort=30009'

# ─── OpenTelemetry Collector (single deployment pod) ────────────────────────
printf '==> Installing OpenTelemetry Collector %s\n' "$OTEL_COLLECTOR_VERSION"
# Apply the canonical 3-signal Collector config (ships alongside this script)
if [[ -f "${ROOT}/scripts/otel-collector-config.yaml" ]]; then
    kubectl apply -n "$NAMESPACE" -f "${ROOT}/scripts/otel-collector-config.yaml"
fi
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
    --version "$OTEL_COLLECTOR_VERSION" \
    --namespace "$NAMESPACE" \
    --wait \
    --set 'mode=deployment' \
    --set 'replicaCount=1' \
    --set 'image.repository=otel/opentelemetry-collector-contrib' \
    --set 'configMap.create=false' \
    --set 'configMap.existingName=otel-collector-config' \
    --set 'ports.otlp.enabled=true' \
    --set 'ports.otlp.nodePort=30417' \
    --set 'ports.otlp-http.enabled=true' \
    --set 'ports.otlp-http.nodePort=30418' \
    --set 'service.enabled=true' \
    --set 'service.type=NodePort'

# ─── Grafana (with datasources + dashboards pre-provisioned) ────────────────
printf '==> Installing Grafana %s\n' "$GRAFANA_VERSION"
helm upgrade --install grafana grafana/grafana \
    --version "$GRAFANA_VERSION" \
    --namespace "$NAMESPACE" \
    --wait \
    --set 'persistence.enabled=true' \
    --set 'persistence.size=2Gi' \
    --set 'adminUser=admin' \
    --set 'adminPassword=admin' \
    --set 'service.type=NodePort' \
    --set 'service.nodePort=30300' \
    --set 'sidecar.datasources.enabled=true' \
    --set 'sidecar.datasources.label=grafana_datasource' \
    --set 'sidecar.datasources.labelValue=1' \
    --set 'sidecar.dashboards.enabled=true' \
    --set 'sidecar.dashboards.label=grafana_dashboard' \
    --set 'sidecar.dashboards.labelValue=1' \
    --set 'sidecar.dashboards.folderAnnotation=grafana_folder' \
    --set 'sidecar.dashboards.provider.foldersFromFilesStructure=true'

# ─── Done ───────────────────────────────────────────────────────────────────
printf '\n==> LGTM stack installed in the %s namespace.\n\n' "$NAMESPACE"
printf 'Host access (NodePorts published on 127.0.0.1; ./scripts/show-endpoints.sh):\n'
printf '  Grafana: http://localhost:3000  (admin/admin)\n'
printf '  Tempo:   http://localhost:3200\n'
printf '  Loki:    http://localhost:3100\n'
printf '  Mimir:   http://localhost:9009\n'
printf '\n'
printf 'Applications should emit OTLP to:\n'
printf '  HTTP:  http://otel-collector.%s.svc.cluster.local:4318\n' "$NAMESPACE"
printf '  gRPC:  otel-collector.%s.svc.cluster.local:4317\n' "$NAMESPACE"
