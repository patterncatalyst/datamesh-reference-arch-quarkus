#!/usr/bin/env bash
#
# setup-kafka-operator.sh — install the Strimzi Kafka operator (Helm) into the
# datamesh namespace, then apply a single-node KRaft Kafka cluster CR (raw
# manifest — Helm is reserved for operators; app/cluster-shaped
# resources are plain manifests, not charts).
#
# Strimzi runs in KRaft mode (no ZooKeeper). Single node / replication factor
# 1 — correct for a single-node minikube dev cluster, not for production.
#
# Strimzi 1.x serves only the kafka.strimzi.io/v1 API (v1beta2 is gone).
# KRaft and node pools are the only mode, so the old strimzi.io/kraft and
# strimzi.io/node-pools annotations are not set. The CRs below validate
# against the strimzi-crds-1.2.0.yaml release asset.
#
# Idempotent: re-running upgrades the operator in place and re-applies the CR.
#
# Usage (from the project root):
#   ./scripts/setup-kafka-operator.sh

set -euo pipefail

NS="datamesh"
STRIMZI_VERSION="${STRIMZI_VERSION:-1.2.0}"
# Strimzi 1.2.0 supports Kafka 4.2.x and 4.3.x (4.1.x was dropped in 1.1.0);
# 4.3.1 also matches the apache/kafka-native:4.3.1 image the compose stack
# and the Dev Services use.
KAFKA_VERSION="${KAFKA_VERSION:-4.3.1}"
CLUSTER_NAME="datamesh"

step() { printf '\n==> %s\n' "$1"; }

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }
command -v helm    >/dev/null 2>&1 || { printf 'ERROR: helm not in PATH.\n' >&2; exit 1; }

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# ─── 1. Strimzi cluster operator ────────────────────────────────────────────

step "Installing the Strimzi cluster operator ${STRIMZI_VERSION} into '${NS}' (Helm)"
helm upgrade --install strimzi-cluster-operator \
    oci://quay.io/strimzi-helm/strimzi-kafka-operator \
    --version "$STRIMZI_VERSION" \
    --namespace "$NS" --create-namespace

step "Waiting for the operator to be Available"
kubectl wait --for=condition=Available deployment -n "$NS" \
    -l strimzi.io/kind=cluster-operator --timeout=180s \
    || kubectl rollout status deployment/strimzi-cluster-operator -n "$NS" --timeout=180s

step "Strimzi operator ready"
kubectl get crd | grep -i kafka.strimzi.io | head

# ─── 2. Kafka cluster CR (single-node KRaft) ────────────────────────────────

step "Applying the ${CLUSTER_NAME} Kafka cluster CR (single-node KRaft) into '${NS}'"
kubectl apply -n "$NS" -f - <<EOF
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata:
  name: dual-role
  namespace: ${NS}
  labels:
    strimzi.io/cluster: ${CLUSTER_NAME}
spec:
  replicas: 1
  roles:
    - controller
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 10Gi
        deleteClaim: true
---
apiVersion: kafka.strimzi.io/v1
kind: Kafka
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${NS}
spec:
  kafka:
    version: ${KAFKA_VERSION}
    metadataVersion: ${KAFKA_VERSION}
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
      min.insync.replicas: 1
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF

step "Waiting for Kafka cluster '${CLUSTER_NAME}' to be Ready (can take a few minutes)"
kubectl wait "kafka/${CLUSTER_NAME}" -n "$NS" --for=condition=Ready --timeout=360s

step "Kafka cluster is Ready."
printf '\nBootstrap servers (in-cluster): %s-kafka-bootstrap.%s.svc.cluster.local:9092\n' "$CLUSTER_NAME" "$NS"
printf 'Apicurio (schema registry) is applied separately by scripts/setup-apicurio.sh.\n'
