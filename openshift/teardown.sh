#!/usr/bin/env bash
#
# teardown.sh — return OpenShift Local to a clean state, then stop it.
#
# This CRC is dedicated to the datamesh workshop, so teardown removes
# everything the openshift/ scripts added:
#   - the Argo CD Application (platform/install-gitops.sh), then the Helm
#     release, the Kafka cluster and the datamesh project (builds,
#     ImageStreams, PVCs);
#   - the platform control planes: Kiali, Istio and IstioCNI, the
#     KedaController, the default Argo CD instance;
#   - every operator (AMQ Streams, OSSM 3, Kiali, Custom Metrics Autoscaler,
#     OpenTelemetry, OpenShift GitOps): Subscription, CSV, InstallPlans, the
#     CRDs each CSV owns, and the operator namespaces.
# Custom resources go while their operator still runs, so no finalizer is
# left waiting on an operator that is already gone.
#
#   ./openshift/teardown.sh                 # clean up, then crc stop
#   ./openshift/teardown.sh --keep-running  # clean up, leave CRC running
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KEEP_RUNNING=false
[[ "${1:-}" == "--keep-running" ]] && KEEP_RUNNING=true

require_crc
gone() { ! oc get "$@" >/dev/null 2>&1; }
has_crd() { oc get crd "$1" >/dev/null 2>&1; }
# A label selector with no matches still exits 0, so test for empty output.
kafka_pods_gone() { [[ -z "$(oc get pod -n "$NS" -l strimzi.io/cluster=datamesh -o name 2>/dev/null)" ]]; }

# subscription-namespace subscription-name, in removal order
OPERATORS=(
    "openshift-gitops-operator openshift-gitops-operator"
    "openshift-opentelemetry-operator opentelemetry-product"
    "openshift-keda openshift-custom-metrics-autoscaler-operator"
    "openshift-operators kiali-ossm"
    "openshift-operators servicemeshoperator3"
    "openshift-operators amq-streams"
)
OPERATOR_NAMESPACES=(openshift-gitops openshift-gitops-operator openshift-opentelemetry-operator
                     openshift-keda istio-system istio-cni)

step "1/6 Workloads"
if has_crd applications.argoproj.io && oc get application datamesh -n openshift-gitops >/dev/null 2>&1; then
    # The resources finalizer makes Argo CD prune what it manages first.
    oc delete application datamesh -n openshift-gitops --wait=true --timeout=300s >/dev/null || fail "delete Argo CD Application"
    ok "Argo CD Application deleted (resources pruned)"
fi
if helm status datamesh -n "$NS" --kube-context "$OCP_CONTEXT" >/dev/null 2>&1; then
    helm uninstall datamesh -n "$NS" --kube-context "$OCP_CONTEXT" --wait >/dev/null || fail "helm uninstall"
    ok "release datamesh uninstalled"
fi
if has_crd kafkas.kafka.strimzi.io && oc get project "$NS" >/dev/null 2>&1; then
    oc delete kafkatopics.kafka.strimzi.io,kafkausers.kafka.strimzi.io --all -n "$NS" --wait=true --timeout=120s >/dev/null 2>&1
    oc delete kafka,kafkanodepool --all -n "$NS" --wait=true --timeout=300s >/dev/null || fail "delete Kafka"
    wait_for 300 "Kafka pods gone" kafka_pods_gone
fi
ok "workloads removed"

step "2/6 Project $NS"
if oc get project "$NS" >/dev/null 2>&1; then
    oc delete project "$NS" --wait=false >/dev/null || fail "delete project"
    wait_for 600 "project $NS deleted" gone namespace "$NS"
else
    ok "no project"
fi

step "3/6 Platform control planes"
has_crd kialis.kiali.io && oc delete kiali --all -n istio-system --wait=true --timeout=300s >/dev/null 2>&1
has_crd istios.sailoperator.io && oc delete istio --all --wait=true --timeout=300s >/dev/null 2>&1
has_crd istiocnis.sailoperator.io && oc delete istiocni --all --wait=true --timeout=300s >/dev/null 2>&1
has_crd kedacontrollers.keda.sh && oc delete kedacontroller --all -n openshift-keda --wait=true --timeout=300s >/dev/null 2>&1
has_crd argocds.argoproj.io && oc delete argocd --all -n openshift-gitops --wait=true --timeout=300s >/dev/null 2>&1
ok "Kiali, Istio, IstioCNI, KedaController and Argo CD instances removed"

step "4/6 Operators"
for entry in "${OPERATORS[@]}"; do
    read -r ns sub <<<"$entry"
    csv="$(oc get subscriptions.operators.coreos.com "$sub" -n "$ns" -o jsonpath='{.status.installedCSV}' 2>/dev/null)"
    oc delete subscriptions.operators.coreos.com "$sub" -n "$ns" --ignore-not-found >/dev/null
    [[ -z "$csv" ]] && continue
    owned="$(oc get csv "$csv" -n "$ns" -o jsonpath='{range .spec.customresourcedefinitions.owned[*]}{.name}{"\n"}{end}' 2>/dev/null)"
    oc delete csv "$csv" -n "$ns" --wait=true >/dev/null 2>&1
    for ip in $(oc get installplan -n "$ns" -o json 2>/dev/null | jq -r --arg c "$csv" '.items[] | select(.spec.clusterServiceVersionNames | index($c)) | .metadata.name'); do
        oc delete installplan "$ip" -n "$ns" >/dev/null 2>&1
    done
    # shellcheck disable=SC2086
    [[ -n "$owned" ]] && oc delete crd $owned --ignore-not-found --wait=true >/dev/null 2>&1
    ok "$csv removed with $(wc -w <<<"$owned") CRD(s)"
done

step "5/6 Remaining CRDs"
# Istio's own CRDs are created by the Sail operator, not owned by its CSV.
crds="$(oc get crd -o name | grep -E '\.(istio\.io|strimzi\.io|sailoperator\.io|kiali\.io|keda\.sh|opentelemetry\.io|argoproj\.io)$')"
# shellcheck disable=SC2086
[[ -n "$crds" ]] && oc delete $crds --wait=true >/dev/null 2>&1
ok "no datamesh platform CRDs left"

step "6/6 Operator namespaces"
for ns in "${OPERATOR_NAMESPACES[@]}"; do
    if oc get namespace "$ns" >/dev/null 2>&1; then
        oc delete namespace "$ns" --wait=false >/dev/null
        wait_for 300 "namespace $ns deleted" gone namespace "$ns"
    fi
done

leftover="$(
    oc get subscriptions.operators.coreos.com -A --no-headers 2>/dev/null
    oc get csv -n openshift-operators --no-headers 2>/dev/null | grep -v -E '^packageserver'
    oc get ns --no-headers -o name | grep -v -E '^namespace/(openshift|kube-|default$|hostpath-provisioner$)'
    for ns in "${OPERATOR_NAMESPACES[@]}"; do oc get ns "$ns" -o name 2>/dev/null; done
    oc get crd -o name | grep -E '\.(istio\.io|strimzi\.io|sailoperator\.io|kiali\.io|keda\.sh|opentelemetry\.io|argoproj\.io)$'
)"
[[ -z "$leftover" ]] && ok "CRC is clean" || printf '    note: still present:\n%s\n' "$leftover"

if [[ "$KEEP_RUNNING" == false ]]; then
    step "crc stop"
    crc stop >/dev/null 2>&1 && ok "OpenShift Local stopped" || fail "crc stop"
fi
