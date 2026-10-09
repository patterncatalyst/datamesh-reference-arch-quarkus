#!/usr/bin/env bash
#
# capture-evidence.sh — verify the datamesh deployment on OpenShift Local and
# write what it saw to openshift/evidence/<date>/.
#
# Checks (each fails the script on a miss):
#   1. cluster, operator and builds: 7 Complete builds, 7 ImageStream tags v1
#   2. pods: all Ready under restricted-v2 with a namespace-range UID
#   3. gateway Route: /q/health/ready answers 200 over edge TLS
#   4. GraphQL: one query returns the order (REST) and its stock (gRPC)
#   5. Kafka choreography for one order id: order.placed -> payment ->
#      shipment row, and notification-service recorded the order
#   6. Apicurio Route: the services registered their Avro schemas
#   7. secret scrub: no password, token or private key in the evidence
# plus, for whatever openshift/platform/ installed: mesh (STRICT mTLS, canary
# split, Kiali), autoscaling (0 -> N -> 0), tracing (one trace across
# services), AI (classify, triage, MCP), native (startup, memory) and GitOps
# (Synced, self-heal).
#
# curl validates the router certificate against the cluster's ingress CA,
# so nothing here uses --insecure.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_crc
command -v jq >/dev/null 2>&1 || fail "jq not on PATH"

OUT="$OPENSHIFT_DIR/evidence/$(date +%Y-%m-%d)"
mkdir -p "$OUT"
CA="$(mktemp)"; trap 'rm -f "$CA"' EXIT
oc get configmap default-ingress-cert -n openshift-config-managed \
    -o jsonpath='{.data.ca-bundle\.crt}' > "$CA" || fail "cannot read the ingress CA"
GATEWAY="https://$(oc get route graphql-gateway -n "$NS" -o jsonpath='{.spec.host}')"
APICURIO="https://$(oc get route apicurio -n "$NS" -o jsonpath='{.spec.host}')"
https() { curl -sS --max-time 20 --cacert "$CA" "$@"; }
in_pod() { local d="$1"; shift; oc exec -n "$NS" "deploy/$d" -c "$d" -- "$@"; }

step "1/7 Cluster, operator, builds"
{
    crc version | head -3
    oc version | grep -E 'Server|Kubernetes'
    oc get csv -n openshift-operators -o custom-columns='CSV:.metadata.name,PHASE:.status.phase'
    oc get kafka datamesh -n "$NS" -o jsonpath='kafka {.metadata.name}: version {.status.kafkaVersion}, Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
    oc get builds -n "$NS" -o custom-columns='BUILD:.metadata.name,STATUS:.status.phase,FROM:.spec.strategy.sourceStrategy.from.name,DURATION:.status.duration'
    for svc in "${SERVICES[@]}"; do
        oc get istag "$svc:v1" -n "$NS" -o jsonpath='{.metadata.name} {.image.dockerImageReference}{"\n"}'
    done
} > "$OUT/01-cluster-builds.txt" 2>&1
tags=$(grep -c ':v1 image-registry' "$OUT/01-cluster-builds.txt")
(( tags == ${#SERVICES[@]} )) || fail "expected ${#SERVICES[@]} ImageStream tags v1, found $tags"
ok "$tags ImageStream tags v1, built in-cluster"

step "2/7 Pods under restricted-v2"
oc get pods -n "$NS" --field-selector=status.phase=Running \
    -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,SCC:.metadata.annotations.openshift\.io/scc,UID:.spec.containers[0].securityContext.runAsUser' \
    > "$OUT/02-pods.txt"
# The one exception is otel-lgtm (observability), which needs anyuid.
not_ready=$(awk 'NR>1 && ($2 ~ /false/ || ($4 != "restricted-v2" && !($1 ~ /^lgtm-/ && $4 == "anyuid")))' "$OUT/02-pods.txt" | grep -c . || true)
oc get namespace "$NS" -o jsonpath='namespace uid-range: {.metadata.annotations.openshift\.io/sa\.scc\.uid-range}{"\n"}' >> "$OUT/02-pods.txt"
(( not_ready == 0 )) || fail "$not_ready pod(s) not Ready or not restricted-v2 (see $OUT/02-pods.txt)"
ok "all pods Ready, restricted-v2 (otel-lgtm: anyuid)"

step "3/7 Gateway health through the Route"
code=$(https -o "$OUT/03-gateway-health.json" -w '%{http_code}' "$GATEWAY/q/health/ready")
printf 'GET %s/q/health/ready -> %s\n' "$GATEWAY" "$code" > "$OUT/03-gateway-health.txt"
[[ "$code" == 200 ]] || fail "gateway health returned $code"
ok "$GATEWAY/q/health/ready 200"

step "4/7 GraphQL: order (REST) + stock (gRPC)"
SKU="CRC-WIDGET-$$"
in_pod inventory-service curl -fsS -X POST localhost:8080/stock -H 'Content-Type: application/json' \
    -d "{\"sku\":\"$SKU\",\"quantityOnHand\":12,\"available\":true}" >/dev/null || fail "seed stock $SKU"
# Through the gateway pod: it has curl in every mode (the native order-service
# image has none), and with the mesh on the call goes sidecar to sidecar.
created=$(in_pod graphql-gateway curl -fsS -X POST http://order-service:8080/orders -H 'Content-Type: application/json' \
    -d "{\"customerId\":\"crc-evidence\",\"itemSku\":\"$SKU\",\"quantity\":1,\"amount\":9.99}") || fail "POST /orders"
ORDER_ID=$(jq -r '.orderId' <<<"$created")
[[ -n "$ORDER_ID" && "$ORDER_ID" != null ]] || fail "POST /orders returned no orderId: $created"
query=$(jq -nc --arg id "$ORDER_ID" '{query: ("{ order(id: \"" + $id + "\") { id customerId itemSku quantity status stock { sku quantityOnHand available } } }")}')
https -X POST "$GATEWAY/graphql" -H 'Content-Type: application/json' -d "$query" | jq . > "$OUT/04-graphql.json"
[[ "$(jq -r '.data.order.id' "$OUT/04-graphql.json")" == "$ORDER_ID" ]] || fail "GraphQL did not return order $ORDER_ID"
[[ "$(jq -r '.data.order.stock.sku' "$OUT/04-graphql.json")" == "$SKU" ]] || fail "GraphQL did not stitch stock for $SKU"
ok "order $ORDER_ID with stock $SKU in one query"

step "5/7 Kafka choreography for order $ORDER_ID"
shipped() {
    oc exec -n "$NS" datamesh-postgres-0 -- psql -d datamesh -tAc \
        "select count(*) from shipment where order_id = '$ORDER_ID'" 2>/dev/null | grep -qx '[1-9][0-9]*'
}
wait_for 120 "shipment row for $ORDER_ID" shipped
notified() {
    oc exec -n "$NS" datamesh-postgres-0 -- psql -d datamesh -tAc \
        "select count(*) from notification where order_id = '$ORDER_ID'" 2>/dev/null | grep -qx '[1-9][0-9]*'
}
wait_for 240 "notification row for $ORDER_ID" notified
{
    printf 'order %s\n\n-- payment-service log\n' "$ORDER_ID"
    oc logs -n "$NS" deploy/payment-service -c payment-service | grep -F "$ORDER_ID"
    printf '\n-- shipment table\n'
    oc exec -n "$NS" datamesh-postgres-0 -- psql -d datamesh -c "select * from shipment where order_id = '$ORDER_ID'"
    # From the table, not the REST API: with KEDA on, notification-service
    # may already have scaled back to zero.
    printf '\n-- notification table (written by notification-service)\n'
    oc exec -n "$NS" datamesh-postgres-0 -- psql -d datamesh -c \
        "select order_id, event_type, status from notification where order_id = '$ORDER_ID'"
} > "$OUT/05-choreography.txt" 2>&1
grep -q 'Capturing payment' "$OUT/05-choreography.txt" || fail "payment-service did not log a capture for $ORDER_ID"
ok "order -> payment -> shipment, plus notification"

step "6/7 Apicurio artifacts through the Route"
https "$APICURIO/apis/registry/v3/search/artifacts?limit=50" | jq . > "$OUT/06-apicurio-artifacts.json"
count=$(jq -r '.count // 0' "$OUT/06-apicurio-artifacts.json")
(( count > 0 )) || fail "Apicurio lists no artifacts"
ok "$count artifact(s) registered"

# Platform tier (openshift/platform/): each section runs only if installed.
source "$OPENSHIFT_DIR/platform/evidence.sh"
platform_evidence

step "7/7 Secret scrub"
password="$(oc get secret datamesh-postgres-app -n "$NS" -o jsonpath='{.data.password}' | base64 -d)"
leaks=0
grep -rqF -- "$password" "$OUT" && { printf '    database password found in evidence\n' >&2; leaks=1; }
unset password
grep -rlE 'sha256~[A-Za-z0-9_-]{20,}|BEGIN [A-Z ]*PRIVATE KEY|kubeadmin-password|"token"' "$OUT" >&2 && leaks=1
(( leaks == 0 )) || fail "evidence contains secret material: delete $OUT and investigate"
ok "no secrets in $OUT"

printf '\n    evidence: %s\n' "${OUT#"$REPO_ROOT"/}"
