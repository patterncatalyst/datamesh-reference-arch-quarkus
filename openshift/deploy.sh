#!/usr/bin/env bash
#
# deploy.sh — install or upgrade the datamesh Helm chart on OpenShift Local
# and wait until every workload is Ready.
#
#   ./openshift/deploy.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_crc
command -v helm >/dev/null 2>&1 || fail "helm not on PATH"
oc wait kafka/datamesh -n "$NS" --for=condition=Ready --timeout=10s >/dev/null 2>&1 \
    || fail "Kafka datamesh not Ready: run ./openshift/install-infra.sh first"
for svc in "${SERVICES[@]}"; do
    oc get istag "$svc:v1" -n "$NS" >/dev/null 2>&1 || fail "image $svc:v1 missing: run ./openshift/build-images.sh"
done

step "helm upgrade --install datamesh"
helm upgrade --install datamesh "$OPENSHIFT_DIR/helm/datamesh" \
    --namespace "$NS" --kube-context "$OCP_CONTEXT" >/dev/null || fail "helm upgrade --install failed"
ok "release datamesh applied"

step "Waiting for workloads"
oc rollout status statefulset/datamesh-postgres -n "$NS" --timeout=300s >/dev/null || fail "Postgres not Ready"
ok "datamesh-postgres Ready"
oc wait deployment --all -n "$NS" -l app.kubernetes.io/part-of=datamesh \
    --for=condition=Available --timeout=600s >/dev/null \
    || fail "deployments not Available (oc get pods -n $NS)"
ok "all deployments Available"
oc get pods -n "$NS" -l app.kubernetes.io/part-of=datamesh \
    -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,UID:.spec.containers[0].securityContext.runAsUser,SCC:.metadata.annotations.openshift\.io/scc'
oc get routes -n "$NS" -o custom-columns='ROUTE:.metadata.name,HOST:.spec.host'
