#!/usr/bin/env bash
#
# teardown.sh — return OpenShift Local to a clean state, then stop it.
#
# This CRC is dedicated to the datamesh workshop, so teardown removes
# everything install-infra.sh, build-images.sh and deploy.sh added:
#   the Helm release, the Kafka cluster, the datamesh project (builds,
#   ImageStreams, PVCs), the AMQ Streams Subscription, CSV and InstallPlans,
#   and the Strimzi CRDs.
# Kafka resources go before the project so no Strimzi finalizer is left
# waiting on an operator that is already gone.
#
#   ./openshift/teardown.sh                 # clean up, then crc stop
#   ./openshift/teardown.sh --keep-running  # clean up, leave CRC running
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KEEP_RUNNING=false
[[ "${1:-}" == "--keep-running" ]] && KEEP_RUNNING=true

require_crc
gone() { ! oc get "$@" >/dev/null 2>&1; }
# A label selector with no matches still exits 0, so test for empty output.
kafka_pods_gone() { [[ -z "$(oc get pod -n "$NS" -l strimzi.io/cluster=datamesh -o name 2>/dev/null)" ]]; }

step "1/5 Helm release"
if helm status datamesh -n "$NS" --kube-context "$OCP_CONTEXT" >/dev/null 2>&1; then
    helm uninstall datamesh -n "$NS" --kube-context "$OCP_CONTEXT" --wait >/dev/null || fail "helm uninstall"
    ok "release datamesh uninstalled"
else
    ok "no release"
fi

step "2/5 Kafka (while the operator can still process finalizers)"
if oc get crd kafkas.kafka.strimzi.io >/dev/null 2>&1 && oc get project "$NS" >/dev/null 2>&1; then
    oc delete kafkatopics.kafka.strimzi.io,kafkausers.kafka.strimzi.io --all -n "$NS" --wait=true --timeout=120s >/dev/null 2>&1
    oc delete kafka,kafkanodepool --all -n "$NS" --wait=true --timeout=300s >/dev/null || fail "delete Kafka"
    wait_for 300 "Kafka pods gone" kafka_pods_gone
else
    ok "no Kafka"
fi

step "3/5 Project $NS"
if oc get project "$NS" >/dev/null 2>&1; then
    oc delete project "$NS" --wait=false >/dev/null || fail "delete project"
    wait_for 600 "project $NS deleted" gone namespace "$NS"
else
    ok "no project"
fi

step "4/5 AMQ Streams operator"
oc delete subscriptions.operators.coreos.com amq-streams -n openshift-operators --ignore-not-found >/dev/null
for csv in $(oc get csv -n openshift-operators -o name | grep amqstreams); do
    oc delete "$csv" -n openshift-operators --wait=true >/dev/null
done
for ip in $(oc get installplan -n openshift-operators -o jsonpath='{range .items[*]}{.metadata.name} {.spec.clusterServiceVersionNames}{"\n"}{end}' | awk '/amqstreams/{print $1}'); do
    oc delete installplan "$ip" -n openshift-operators >/dev/null
done
ok "Subscription, CSV and InstallPlans removed"

step "5/5 Strimzi CRDs"
crds="$(oc get crd -o name | grep -E '\.strimzi\.io$')"
if [[ -n "$crds" ]]; then
    # shellcheck disable=SC2086
    oc delete $crds --wait=true >/dev/null || fail "delete Strimzi CRDs"
fi
ok "no Strimzi CRDs left"

leftover="$(oc get subscriptions.operators.coreos.com -A --no-headers 2>/dev/null; oc get ns --no-headers -o name | grep -v -E '^namespace/(openshift|kube-|default$|hostpath-provisioner$)')"
[[ -z "$leftover" ]] && ok "CRC is clean" || printf '    note: still present (not created by datamesh?):\n%s\n' "$leftover"

if [[ "$KEEP_RUNNING" == false ]]; then
    step "crc stop"
    crc stop >/dev/null 2>&1 && ok "OpenShift Local stopped" || fail "crc stop"
fi
