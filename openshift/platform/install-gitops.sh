#!/usr/bin/env bash
#
# install-gitops.sh — hand the datamesh release to Argo CD (OpenShift
# GitOps). The Application renders openshift/helm/datamesh from this repo on
# GitHub with the values the running release already has, adopts its
# resources, and from then on keeps the cluster equal to git (self-heal).
#
#   ./openshift/platform/install-gitops.sh [revision]   # default: main
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
PLATFORM="$OPENSHIFT_DIR/platform"

REVISION="${1:-main}"
REPO_URL="https://github.com/patterncatalyst/datamesh-reference-arch-quarkus.git"

require_crc
helm status datamesh -n "$NS" --kube-context "$OCP_CONTEXT" >/dev/null 2>&1 || fail "release datamesh missing: run deploy.sh first"

step "1/3 OpenShift GitOps operator"
install_operator "$PLATFORM/subscriptions/gitops.yaml" openshift-gitops-operator \
    openshift-gitops-operator openshift-gitops-operator.v1.22.1
wait_for 600 "default Argo CD instance Available" \
    bash -c '[[ "$(oc get argocd openshift-gitops -n openshift-gitops -o jsonpath={.status.phase})" == Available ]]'

step "2/3 Let Argo CD manage project $NS"
oc label namespace "$NS" argocd.argoproj.io/managed-by=openshift-gitops --overwrite >/dev/null || fail "label namespace"
ok "namespace labelled argocd.argoproj.io/managed-by=openshift-gitops"

step "3/3 Application datamesh (revision $REVISION)"
APP="$(mktemp --suffix=.json)"; trap 'rm -f "$APP"' EXIT
values="$(helm get values datamesh -n "$NS" --kube-context "$OCP_CONTEXT" -o json)"
jq -n --arg repo "$REPO_URL" --arg rev "$REVISION" --arg ns "$NS" --argjson values "$values" '{
  apiVersion: "argoproj.io/v1alpha1", kind: "Application",
  metadata: {name: "datamesh", namespace: "openshift-gitops",
             labels: {"app.kubernetes.io/part-of": "datamesh"},
             finalizers: ["resources-finalizer.argocd.argoproj.io"]},
  spec: {
    project: "default",
    source: {repoURL: $repo, targetRevision: $rev, path: "openshift/helm/datamesh",
             helm: {releaseName: "datamesh", valuesObject: $values}},
    destination: {server: "https://kubernetes.default.svc", namespace: $ns},
    # Argo CD renders with helm template, where lookup returns nothing, so the
    # chart would mint a new Postgres password on every sync. Never touch it.
    ignoreDifferences: [{kind: "Secret", name: "datamesh-postgres-app", jsonPointers: ["/data/password"]}],
    syncPolicy: {automated: {prune: true, selfHeal: true},
                 syncOptions: ["RespectIgnoreDifferences=true", "ApplyOutOfSyncOnly=true"]}
  }}' > "$APP"
oc apply -f "$APP" >/dev/null || fail "apply Application"
synced_healthy() {
    [[ "$(oc get application datamesh -n openshift-gitops -o jsonpath='{.status.sync.status}/{.status.health.status}')" == Synced/Healthy ]]
}
wait_for 900 "Application datamesh Synced/Healthy" synced_healthy
ok "Argo CD https://$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')"
