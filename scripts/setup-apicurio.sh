#!/usr/bin/env bash
#
# setup-apicurio.sh — install Apicurio Registry 3.x into the cluster as the
# schema registry for the Avro contracts used by every Kafka channel in this
# repo (order-placed.avsc, payment-captured.avsc,
# shipment-dispatched.avsc, ...). Uses the v3 registry API
# (/apis/registry/v3).
#
# This is the dev-scale install: in-memory storage (the default when no
# APICURIO_STORAGE_KIND env is set), single replica. Data does not survive a
# pod restart; producers re-register their contracts on startup, which is
# fine for development (known-issues #9 in the lgtm-minikube-stack skill).
#
# For production-style persistence, set APICURIO_STORAGE_KIND=sql with a
# datasource pointing at the CNPG-managed Postgres (see Apicurio docs).
#
# Usage:
#   ./scripts/setup-apicurio.sh [namespace]

set -euo pipefail

NS="${1:-datamesh}"
APICURIO_VERSION="${APICURIO_VERSION:-3.2.4}"
RELEASE="apicurio"

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

printf '==> Installing Apicurio Registry %s into namespace %s (in-memory storage, dev-scale, v3 API)\n' \
    "$APICURIO_VERSION" "$NS"

# Apply Deployment + Service inline. Plain manifests — no chart dependency.
kubectl apply -n "$NS" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $RELEASE
  labels:
    app.kubernetes.io/name: apicurio-registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: apicurio-registry
  template:
    metadata:
      labels:
        app.kubernetes.io/name: apicurio-registry
    spec:
      containers:
        - name: apicurio
          image: quay.io/apicurio/apicurio-registry:$APICURIO_VERSION
          ports:
            - name: http
              containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              memory: 1Gi
          readinessProbe:
            # Apicurio Registry 3.2.4's image does not expose SmallRye health at
            # /q/health; the registry API's lightweight system-info endpoint is a
            # reliable readiness signal (returns 200 once the app is serving).
            httpGet:
              path: /apis/registry/v3/system/info
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: $RELEASE
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: apicurio-registry
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30084
      name: http
EOF

printf '==> Waiting for Apicurio to roll out\n'
kubectl rollout status -n "$NS" "deploy/$RELEASE" --timeout=120s

printf '\n==> Apicurio Registry installed.\n\n'
printf 'In-cluster endpoint: http://%s.%s.svc.cluster.local:8080/apis/registry/v3\n' "$RELEASE" "$NS"
printf 'Host access (NodePort published on 127.0.0.1; ./scripts/show-endpoints.sh):\n'
printf '  UI at http://localhost:8084\n'
printf '  API at http://localhost:8084/apis/registry/v3\n'
