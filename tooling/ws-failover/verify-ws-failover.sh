#!/usr/bin/env bash
#
# tooling/ws-failover/verify-ws-failover.sh — verify chapter 16's replica
# failure and client reconnect pattern on the local Kubernetes cluster.
#
# What it shows:
#   1. notification-service runs two replicas behind its ClusterIP Service,
#      each with its own push consumer group (every replica sees every event).
#   2. demos/jbang/WsReconnectClient.java, running in-cluster, connects through
#      the Service and receives a pushed order.
#   3. The replica holding the client's socket is deleted. The client sees the
#      close, waits with jittered exponential backoff, and reconnects through
#      the Service to a surviving replica.
#   4. On reconnect the client re-fetches GET /notifications and de-duplicates
#      by orderId, then receives a second order pushed by the survivor.
#
# The client's replica is found by elimination: delete one pod; if the
# client's socket does not close within a few seconds, wait for that pod's
# replacement to be Ready and delete the other one.
#
# Preconditions: ./scripts/bootstrap.sh, ./scripts/load-images.sh, and the app
# overlay plus KEDA scalers applied (demos/demo-keda-kafka.sh applies both).
# KEDA owns notification-service's replica count, so this script pauses the
# ScaledObject at two replicas and removes the pause on exit.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../demos/lib/_demo.sh
source "${REPO_ROOT}/demos/lib/_demo.sh"

demo_begin "verify-ws-failover"
require kubectl minikube jq

PROFILE="${MINIKUBE_PROFILE:-datamesh}"
NS="datamesh"
DEPLOY="notification-service"
SCALEDOBJECT="notification-service-scaledobject"
CLIENT_POD="ws-failover-client-$$"
CLIENT_CM="ws-failover-client-$$"
CLIENT_IMAGE="docker.io/library/eclipse-temurin:25.0.4.1_1-jdk"
CURL_IMAGE="docker.io/curlimages/curl:8.22.0"
SVC_HOST="${DEPLOY}.${NS}.svc.cluster.local"
WS_URL="ws://${SVC_HOST}:8080/ws/notifications"
REST_URL="http://${SVC_HOST}:8080/notifications"
SKU="WS-FAILOVER-SKU"
RUN_SECONDS=420

# ─── Preflight ──────────────────────────────────────────────────────────────
step "preflight: cluster, deployments, ScaledObject"
minikube status -p "$PROFILE" >/dev/null 2>&1 \
    || fail "minikube profile '${PROFILE}' is not running; run ./scripts/bootstrap.sh first"
for d in "$DEPLOY" order-service inventory-service; do
    kubectl get deployment "$d" -n "$NS" >/dev/null 2>&1 \
        || fail "deployment/${d} not found in ${NS}; run ./scripts/load-images.sh, then kubectl apply -k k8s/overlays/minikube"
done
kubectl get scaledobject "$SCALEDOBJECT" -n "$NS" >/dev/null 2>&1 \
    || fail "scaledobject/${SCALEDOBJECT} not found; kubectl apply -k k8s/keda"
info "cluster '${PROFILE}' reachable; deployments and ScaledObject present"

_cleanup() {
    local rc=$?
    kubectl delete pod "$CLIENT_POD" -n "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl delete configmap "$CLIENT_CM" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
    kubectl annotate scaledobject "$SCALEDOBJECT" -n "$NS" autoscaling.keda.sh/paused-replicas- >/dev/null 2>&1 || true
    return "$rc"
}
trap '_cleanup; _demo_exit_trap' EXIT

# in_cluster_curl <args...> — run curl in a throwaway pod and print its output.
in_cluster_curl() {
    kubectl run "ws-failover-curl-$$-${RANDOM}" -n "$NS" --rm -i --restart=Never --quiet \
        --image="$CURL_IMAGE" --command -- curl -sS --max-time 30 "$@" 2>/dev/null
}

# place_order — POST /orders in-cluster and print the new order's id.
place_order() {
    in_cluster_curl -X POST -H 'Content-Type: application/json' \
        -d "{\"customerId\":\"CUST-WS-FAILOVER\",\"itemSku\":\"${SKU}\",\"quantity\":1,\"amount\":1.00}" \
        "http://order-service.${NS}.svc.cluster.local:8080/orders" | jq -r '.orderId // empty'
}

client_log() { kubectl logs "$CLIENT_POD" -n "$NS" 2>/dev/null; }

# wait_log <pattern> <seconds> — wait until the client log matches.
wait_log() {
    local pattern="$1" budget="$2" i
    # Capture first: under pipefail, `kubectl logs | grep -q` fails with
    # SIGPIPE when grep exits early on a long log.
    local out
    for (( i = 0; i < budget; i += 2 )); do
        out="$(client_log)"
        grep -qE "$pattern" <<<"$out" && return 0
        sleep 2
    done
    return 1
}

count_log() { client_log | grep -cE "$1" || true; }

# ready_pods — names of Ready replicas that are not terminating.
ready_pods() {
    kubectl get pods -n "$NS" -l "app.kubernetes.io/name=${DEPLOY}" -o json 2>/dev/null \
        | jq -r '.items[]
            | select(.metadata.deletionTimestamp == null)
            | select(any(.status.containerStatuses[]?; .ready))
            | .metadata.name'
}

wait_ready_replicas() {
    local want="$1" budget="$2" i
    for (( i = 0; i < budget; i += 3 )); do
        (( $(ready_pods | wc -l) >= want )) && return 0
        sleep 3
    done
    return 1
}

# ─── Two replicas, held by pausing KEDA ─────────────────────────────────────
step "hold ${DEPLOY} at two replicas (pause the ScaledObject)"
kubectl annotate scaledobject "$SCALEDOBJECT" -n "$NS" autoscaling.keda.sh/paused-replicas=2 --overwrite >/dev/null \
    || fail "could not annotate scaledobject/${SCALEDOBJECT}"
wait_ready_replicas 2 240 || fail "${DEPLOY} did not reach two Ready replicas within 240s"
info "Ready replicas: $(ready_pods | tr '\n' ' ')"

step "seed stock for ${SKU}"
in_cluster_curl -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' \
    -d "{\"sku\":\"${SKU}\",\"quantityOnHand\":100000}" \
    "http://inventory-service.${NS}.svc.cluster.local:8080/stock" >/dev/null \
    || fail "seeding stock via inventory-service failed"

# ─── Start the reconnecting client in-cluster ───────────────────────────────
step "start WsReconnectClient in-cluster (${CLIENT_IMAGE})"
kubectl create configmap "$CLIENT_CM" -n "$NS" \
    --from-file=WsReconnectClient.java="${REPO_ROOT}/demos/jbang/WsReconnectClient.java" >/dev/null \
    || fail "could not create configmap ${CLIENT_CM}"
kubectl apply -n "$NS" -f - >/dev/null <<EOF || fail "could not create pod ${CLIENT_POD}"
apiVersion: v1
kind: Pod
metadata:
  name: ${CLIENT_POD}
  annotations:
    sidecar.istio.io/inject: "false"
spec:
  restartPolicy: Never
  containers:
    - name: client
      image: ${CLIENT_IMAGE}
      command: ["java", "/client/WsReconnectClient.java", "${WS_URL}", "${REST_URL}", "${RUN_SECONDS}"]
      volumeMounts:
        - name: client
          mountPath: /client
  volumes:
    - name: client
      configMap:
        name: ${CLIENT_CM}
EOF
wait_log '^WS_OPEN attempt=1$' 240 \
    || { client_log | tail -20 >&2; fail "client did not open its WebSocket within 240s"; }
info "client connected through the Service"

# ─── Order A over the first connection ──────────────────────────────────────
step "place order A and receive it over the first connection"
ORDER_A="$(place_order)"
[[ -n "$ORDER_A" ]] || fail "POST /orders for order A returned no id"
wait_log "^ORDER ${ORDER_A} via=" 90 \
    || { client_log | tail -20 >&2; fail "order A (${ORDER_A}) did not reach the client within 90s"; }
info "order A ${ORDER_A}: $(client_log | grep -E "^ORDER ${ORDER_A} " | head -1)"

# ─── Delete the replica holding the client's socket ─────────────────────────
step "delete the replica holding the client's socket"
CLOSES_BEFORE="$(count_log '^WS_(CLOSED|ERROR)')"
mapfile -t PODS < <(ready_pods)
(( ${#PODS[@]} >= 2 )) || fail "expected two Ready replicas, found ${#PODS[@]}"

kill_and_check() {
    local pod="$1"
    info "deleting pod ${pod}"
    kubectl delete pod "$pod" -n "$NS" --wait=false >/dev/null || fail "kubectl delete pod ${pod} failed"
    local i
    for (( i = 0; i < 20; i += 2 )); do
        (( $(count_log '^WS_(CLOSED|ERROR)') > CLOSES_BEFORE )) && return 0
        sleep 2
    done
    return 1
}

if kill_and_check "${PODS[0]}"; then
    KILLED="${PODS[0]}"
else
    info "the client was not on ${PODS[0]}; waiting for its replacement before deleting ${PODS[1]}"
    wait_ready_replicas 2 240 || fail "replacement for ${PODS[0]} did not become Ready within 240s"
    kill_and_check "${PODS[1]}" || fail "the client's socket did not close after deleting either replica"
    KILLED="${PODS[1]}"
fi
info "client socket closed when ${KILLED} was deleted: $(client_log | grep -E '^WS_(CLOSED|ERROR)' | tail -1)"

# ─── Reconnect with backoff, catch up, de-duplicate ─────────────────────────
step "client reconnects through the Service with backoff"
wait_log '^WS_OPEN attempt=([2-9]|[1-9][0-9])$' 120 \
    || { client_log | tail -20 >&2; fail "client did not reconnect within 120s"; }
client_log | grep -E '^WS_RECONNECT ' | tail -3 | while read -r line; do info "$line"; done
CATCHUP_AFTER="$(client_log | grep -E '^CATCHUP ' | tail -1)"
info "after reconnect: ${CATCHUP_AFTER}"
[[ "$CATCHUP_AFTER" =~ fetched=([0-9]+) ]] && (( BASH_REMATCH[1] >= 1 )) \
    || fail "the catch-up fetch after reconnect returned no notifications (${CATCHUP_AFTER})"
(( $(count_log "^ORDER ${ORDER_A} ") == 1 )) \
    || fail "order A was reported more than once; de-duplication failed"

# ─── Order B over the new connection ────────────────────────────────────────
step "place order B and receive it from a surviving replica"
ORDER_B="$(place_order)"
[[ -n "$ORDER_B" ]] || fail "POST /orders for order B returned no id"
wait_log "^ORDER ${ORDER_B} via=" 90 \
    || { client_log | tail -20 >&2; fail "order B (${ORDER_B}) did not reach the client within 90s"; }
info "order B ${ORDER_B}: $(client_log | grep -E "^ORDER ${ORDER_B} " | head -1)"

narrate "the client lost its replica, backed off, reconnected through the Service to a"
narrate "survivor, caught up via GET /notifications without duplicating order A, and"
narrate "received order B from the survivor's own push consumer."
demo_ok
