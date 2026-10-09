#!/usr/bin/env bash
#
# install-infra.sh — the datamesh platform tier on OpenShift Local (CRC):
# the datamesh project, the AMQ Streams operator (pinned, from OperatorHub)
# and the "datamesh" Kafka cluster. Postgres and Apicurio ship in the Helm
# chart (openshift/helm/datamesh), not here.
#
# Idempotent: re-running skips what already exists. Undo with teardown.sh.
#
#   eval "$(crc oc-env)"
#   ./openshift/install-infra.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CSV="amqstreams.v3.2.1-14"

require_crc

step "1/4 Project $NS"
if oc get project "$NS" >/dev/null 2>&1; then
    ok "project $NS exists"
else
    oc new-project "$NS" --display-name="DataMesh reference architecture" >/dev/null || fail "oc new-project $NS"
    ok "project $NS created"
fi

step "2/4 AMQ Streams operator ($CSV)"
existing="$(oc get subscriptions.operators.coreos.com -A -o jsonpath='{range .items[?(@.spec.name=="amq-streams")]}{.metadata.namespace}/{.metadata.name} {.status.installedCSV}{"\n"}{end}')"
if [[ -n "$existing" && "$existing" != "openshift-operators/amq-streams $CSV" && "$existing" != "openshift-operators/amq-streams " ]]; then
    fail "an AMQ Streams Subscription already exists ($existing); this CRC is meant for datamesh only, run teardown.sh first"
fi
# redhat-operators reports READY before it serves packages (about a minute
# after crc start), so wait for the package itself.
wait_for 300 "OperatorHub serves amq-streams" \
    oc get packagemanifest amq-streams -n openshift-marketplace
oc apply -f "$OPENSHIFT_DIR/infra/amq-streams-subscription.yaml" >/dev/null || fail "apply Subscription"
installplan_for_csv() {
    oc get installplan -n openshift-operators \
        -o jsonpath="{range .items[?(@.spec.clusterServiceVersionNames[0]==\"$CSV\")]}{.metadata.name}{end}"
}
installplan_proposed() { [[ -n "$(installplan_for_csv)" ]]; }
csv_succeeded() {
    [[ "$(oc get csv "$CSV" -n openshift-operators -o jsonpath='{.status.phase}' 2>/dev/null)" == Succeeded ]]
}
if ! csv_succeeded; then
    wait_for 300 "InstallPlan for $CSV proposed" installplan_proposed
    oc patch installplan "$(installplan_for_csv)" -n openshift-operators \
        --type merge -p '{"spec":{"approved":true}}' >/dev/null || fail "approve InstallPlan"
    wait_for 600 "CSV $CSV Succeeded" csv_succeeded
else
    ok "CSV $CSV already Succeeded"
fi

step "3/4 Kafka cluster datamesh (KRaft, 1 dual-role node)"
oc apply -f "$OPENSHIFT_DIR/infra/kafka.yaml" >/dev/null || fail "apply Kafka"
oc wait kafka/datamesh -n "$NS" --for=condition=Ready --timeout=900s >/dev/null \
    || fail "Kafka datamesh not Ready (oc get pods -n $NS; oc describe kafka datamesh -n $NS)"
ok "Kafka datamesh Ready"

step "4/4 Summary"
oc get kafka datamesh -n "$NS" -o jsonpath='    kafka {.status.kafkaVersion}, bootstrap {.status.listeners[0].bootstrapServers}{"\n"}'
printf '    next: ./openshift/build-images.sh, then ./openshift/deploy.sh\n'
