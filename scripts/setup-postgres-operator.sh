#!/usr/bin/env bash
#
# setup-postgres-operator.sh — install the CloudNativePG operator (cluster-
# wide, via Helm) and then apply a single-instance Postgres Cluster CR (raw
# manifest — Helm is reserved for operators) into the datamesh
# namespace.
#
# IMPORTANT: installing the operator is a CLUSTER-WIDE action. It registers
# CRDs (Cluster, Pooler, Backup, ... — always cluster-scoped) and runs a
# controller in cnpg-system that reconciles those CRs across every namespace.
#
# The Cluster CR pins the PostgreSQL image (PG_IMAGE, 18.6, the same minor as
# the compose stack and Dev Services) and postgresql.parameters.timezone=UTC (matches
# the Testcontainers/Dev Services convention elsewhere in this repo; avoids
# the "invalid value for parameter TimeZone" boot failure some hosts trigger
# with legacy Olson zone ids like US/Eastern).
#
# Do NOT label the datamesh namespace for Istio sidecar injection while this
# Cluster is running (known-issues #2): the operator's own TLS handshake to
# the primary collides with the sidecar's mTLS wrapping.
#
# Idempotent — re-running upgrades the operator in place and re-applies the CR.
#
# Usage:
#   ./scripts/setup-postgres-operator.sh [namespace]

set -euo pipefail

NS="${1:-datamesh}"
PROFILE_NAME="datamesh"
OPERATOR_NS="cnpg-system"
CHART_VERSION="${CNPG_CHART_VERSION:-0.29.1}"   # operator 1.30.1
# PostgreSQL image for the Cluster, pinned instead of the operator default.
PG_IMAGE="${PG_IMAGE:-ghcr.io/cloudnative-pg/postgresql:18.6-standard-trixie}"
RELEASE_NAME="cnpg"
CLUSTER_NAME="${CLUSTER_NAME:-datamesh-postgres}"
PG_DATABASE="${PG_DATABASE:-datamesh}"
PG_OWNER="${PG_OWNER:-datamesh}"

step() { printf '\n==> %s\n' "$1"; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────

command -v helm    >/dev/null 2>&1 || { printf 'ERROR: helm not in PATH.\n' >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }

current_context=$(kubectl config current-context 2>/dev/null || echo "")
if [[ "$current_context" != "$PROFILE_NAME" ]]; then
    printf 'WARNING: current kubectl context is "%s", not "%s".\n' "$current_context" "$PROFILE_NAME" >&2
    printf 'The operator will be installed cluster-wide on THAT cluster.\n' >&2
    printf 'Switch with: kubectl config use-context %s\n' "$PROFILE_NAME" >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# ─── 1. Install the operator (cluster-wide) ──────────────────────────────────

step "Adding the CloudNativePG helm repository"
helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true
helm repo update cnpg >/dev/null

step "Installing CloudNativePG operator ${CHART_VERSION} (cluster-wide) into ${OPERATOR_NS}"
helm upgrade --install "$RELEASE_NAME" cnpg/cloudnative-pg \
    --namespace "$OPERATOR_NS" \
    --create-namespace \
    --version "$CHART_VERSION" \
    --wait \
    --timeout 5m

step "Waiting for the operator deployment to be Available"
kubectl wait --for=condition=Available --timeout=180s \
    deployment/cnpg-cloudnative-pg \
    -n "$OPERATOR_NS"

step "Verifying CRDs are registered (cluster-scoped)"
kubectl get crd | grep -E 'cnpg\.io' || {
    printf 'ERROR: CloudNativePG CRDs not found after install.\n' >&2
    exit 1
}

# ─── 2. Apply the Cluster CR ─────────────────────────────────────────────────

step "Applying Postgres Cluster CR '${CLUSTER_NAME}' into '${NS}' (1 instance, TZ=UTC)"
kubectl apply -n "$NS" -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${NS}
spec:
  instances: 1
  imageName: ${PG_IMAGE}
  storage:
    size: 5Gi
  postgresql:
    parameters:
      timezone: "UTC"
  bootstrap:
    initdb:
      database: ${PG_DATABASE}
      owner: ${PG_OWNER}
EOF

step "Waiting for the Postgres primary to be Ready (can take a couple minutes)"
pg_ready=0
for i in $(seq 1 72); do
    # cnpg.io/instanceRole replaces the deprecated role label (CNPG 1.30).
    status="$(kubectl get pods -n "$NS" -l "cnpg.io/cluster=${CLUSTER_NAME},cnpg.io/instanceRole=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "$status" == "True" ]]; then
        pg_ready=1
        break
    fi
    sleep 5
done
if (( ! pg_ready )); then
    printf 'ERROR: Postgres primary did not become Ready in time.\n' >&2
    exit 1
fi

step "Postgres primary is Ready."
printf '\nConnection (in-cluster): %s-rw.%s.svc.cluster.local:5432/%s (owner: %s)\n' \
    "$CLUSTER_NAME" "$NS" "$PG_DATABASE" "$PG_OWNER"
printf 'Password: kubectl get secret -n %s %s-app -o jsonpath="{.data.password}" | base64 -d\n' "$NS" "$CLUSTER_NAME"
