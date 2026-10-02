#!/usr/bin/env bash
#
# demos/demo-websocket.sh — "compose (infra baseline)"
# demo: WebSockets.Next, pushing a real event to a live WebSocket client.
#
# ── NEW endpoint added for this demo (flagged, per this step's plan) ───────
# notification-service had no WebSocket endpoint before this step. This demo
# required adding ONE minimal `quarkus-websockets-next` endpoint to make the
# capability demoable at all -- see the "FILES ADDED/CHANGED" list below.
# It is the natural home: notification-service already consumes
# `order.placed` off Kafka and persists a `Notification` row per order
# (OrderPlacedConsumer) — the new socket pushes that SAME, already-persisted
# Notification to any live client, in real time, as soon as it's committed.
#
#   NEW  examples/notification-service/src/main/java/.../OrderNotificationSocket.java
#        A minimal `@WebSocket(path = "/ws/notifications")` endpoint. Its
#        only job is an `@OnOpen` connection ack (`{"type":"connected"}`);
#        it does not itself push anything.
#   NEW  examples/notification-service/src/main/java/.../OrderPlacedPushConsumer.java
#        Injects `io.quarkus.websockets.next.OpenConnections` and, right
#        after `notification.persist()`, broadcasts the persisted
#        Notification (serialized to JSON by WebSockets.Next the same way
#        REST does) to every open connection.
#   EDIT examples/notification-service/pom.xml
#        Adds the `quarkus-websockets-next` extension dependency (not
#        previously used ANYWHERE in this reactor — confirmed by grepping
#        every examples/*/pom.xml for "websockets" before starting).
#
# This demo rides the SAME real pipeline demo-order.sh/demo-kafka.sh already
# prove (order-service -> inventory-service gRPC -> Postgres -> Avro/Kafka
# publish -> Apicurio), with notification-service added as a THIRD packaged
# service consuming that same order.placed event — so the WebSocket push
# this demo asserts is driven by a genuine, already-proven, cross-service,
# at-least-once Kafka event, not a synthetic/local trigger.
#
# ── Real WS client: plain JDK java.net.http.WebSocket via jbang ────────────
# `websocat` is NOT installed on this host and is not a toolchain dependency
# already established elsewhere in this repo (unlike `jbang`, used by
# demo-jbang-prototype.sh) — rather than adding a brand new external binary
# dependency for one demo, this uses demos/jbang/WsNotificationClient.java,
# a small dependency-free JDK WebSocket client run via `jbang` (already a
# required/documented toolchain piece here). If `websocat` IS present this
# demo still doesn't need it — jbang's client is the primary path; this
# comment documents why `require jbang`, not `require websocat`, gates this
# demo. (Install hint if jbang itself is missing: see demo-jbang-prototype.sh.)
#
# ── Per-run unique Kafka topic (same reasoning as demo-kafka.sh) ───────────
# order.placed's topic lives on compose's persistent `kafka-data` volume;
# notification-service dedups by orderId so a stale redelivery wouldn't
# corrupt correctness, but it WOULD push extra, unrelated WS messages to our
# listening client ahead of the one this run cares about, making "the next
# message on the socket" ambiguous. A per-run unique topic (set identically
# on both order-service's outgoing channel and notification-service's
# incoming channel) sidesteps this exactly like demo-kafka.sh does.
#
# ── order.placed Avro security property — BOTH producer AND consumer sides
# (found wiring THIS demo; demo-order.sh/demo-kafka.sh only needed it on the
# producer) ──────────────────────────────────────────────────────────────
# order-service (producer) needs org.apache.avro.SERIALIZABLE_PACKAGES=
# capstone.order.v1 or every order.placed publish throws (Avro 1.12.x's
# ClassSecurityValidator — see demo-order.sh's header comment for the full
# trace). What's NEW here: notification-service (the consumer, and the only
# service in this reactor that actually DESERIALIZES OrderPlaced back into a
# capstone.order.v1.OrderPlaced SpecificRecord) needs the IDENTICAL system
# property on its own packaged JVM for the SAME reason — confirmed
# empirically: without it, every poll fails with "java.lang.SecurityException:
# Forbidden capstone.order.v1.OrderPlaced!" (SRMSG18249 in notification-
# service's log), so no Notification is ever persisted and nothing is ever
# pushed over the WebSocket, even though order-service's publish itself
# succeeds. This is a second, previously-undetected instance of the same
# production-readiness gap already named for the producer side — worth
# flagging upstream for every %prod Avro consumer in this reactor, not
# just the ones already covered by an existing demo/IT.
#
# ── Port plan ────────────────────────────────────────────────────────────
#   order-service         HTTP 8091
#   inventory-service      HTTP 8092, gRPC 9000 (canonical default, see demo-order.sh)
#   notification-service   HTTP 8093 (REST /notifications + WS /ws/notifications)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-websocket"
require curl jq docker mvn java jbang

ORDER_DIR="${EXAMPLES_DIR}/order-service"
INVENTORY_DIR="${EXAMPLES_DIR}/inventory-service"
NOTIFICATION_DIR="${EXAMPLES_DIR}/notification-service"
WS_CLIENT="${SCRIPT_DIR}/jbang/WsNotificationClient.java"
[[ -f "$WS_CLIENT" ]] || fail "WebSocket client source not found: $WS_CLIENT"

ORDER_PORT=8091
INVENTORY_PORT=8092
INVENTORY_GRPC_PORT=9000
NOTIFICATION_PORT=8093

ORDER_BASE="http://localhost:${ORDER_PORT}"
INVENTORY_BASE="http://localhost:${INVENTORY_PORT}"
NOTIFICATION_BASE="http://localhost:${NOTIFICATION_PORT}"
WS_URL="ws://localhost:${NOTIFICATION_PORT}/ws/notifications"

POSTGRES_PORT="${POSTGRES_PORT:-5432}"
KAFKA_HOST_PORT="${KAFKA_HOST_PORT:-9092}"
APICURIO_PORT="${APICURIO_PORT:-8081}"
AVRO_SERIALIZABLE_PACKAGES="capstone.order.v1"
TOPIC="order.placed.ws.demo.$$"

narrate "WebSockets.Next: a live client connects to notification-service's"
narrate "new /ws/notifications endpoint; placing a real order propagates"
narrate "order-service -> gRPC CheckStock -> inventory-service -> Postgres,"
narrate "then order-service -> Kafka (Avro/Apicurio) -> notification-service,"
narrate "which persists a Notification row and pushes it over the live socket."
narrate "This demo asserts the parsed content of that pushed message."

# ─── .env prereq (compose var resolution) ───────────────────────────────────
if [[ ! -f "${REPO_ROOT}/.env" ]]; then
    [[ -f "${REPO_ROOT}/.env.example" ]] \
        || fail ".env is missing and there is no .env.example to copy from at ${REPO_ROOT}"
    info "no .env found -- copying .env.example -> .env (gitignored, documented prereq)"
    cp "${REPO_ROOT}/.env.example" "${REPO_ROOT}/.env"
fi
# shellcheck disable=SC1091
source "${REPO_ROOT}/.env"

# ─── Compose lifecycle: this script owns it ─────────────────────────────────
step "bring up compose baseline (postgres, kafka, apicurio, otel-lgtm)"
compose_up

SVC_PIDFILES=()
WS_CLIENT_PID=""
WS_CLIENT_LOG=""
_cleanup() {
    local rc=$?
    local pf
    if [[ -n "$WS_CLIENT_PID" ]] && kill -0 "$WS_CLIENT_PID" 2>/dev/null; then
        kill "$WS_CLIENT_PID" 2>/dev/null || true
        wait "$WS_CLIENT_PID" 2>/dev/null || true
    fi
    for pf in "${SVC_PIDFILES[@]:-}"; do
        [[ -n "$pf" ]] && svc_stop "$pf" 2>/dev/null || true
    done
    compose_down 2>/dev/null || true
    return "$rc"
}
trap '_cleanup; _demo_exit_trap' EXIT

step "preflight: compose Postgres/Kafka/Apicurio reachable"
for (( i = 0; i < 30; i++ )); do
    docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 && break
    sleep 1
done
docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 \
    || fail "compose Postgres (orderdb) did not become ready within 30s"
info "compose Postgres is ready"

# ─── Build all three services (idempotent) ──────────────────────────────────
step "build order-service + inventory-service + notification-service (mvn -DskipTests package)"
( cd "$ORDER_DIR" && mvn -q -DskipTests package ) || fail "mvn package failed for order-service"
( cd "$INVENTORY_DIR" && mvn -q -DskipTests package ) || fail "mvn package failed for inventory-service"
( cd "$NOTIFICATION_DIR" && mvn -q -DskipTests package ) || fail "mvn package failed for notification-service"
[[ -f "${NOTIFICATION_DIR}/target/quarkus-app/quarkus-run.jar" ]] \
    || fail "notification-service build did not produce target/quarkus-app/quarkus-run.jar"

# ─── Start inventory-service (order-service's gRPC CheckStock dependency) ──
step "start inventory-service (HTTP ${INVENTORY_PORT}, gRPC ${INVENTORY_GRPC_PORT})"
INV_PIDFILE="$(mktemp -t demo-ws-inv-pid-XXXXXX)"
INV_LOGFILE="$(mktemp -t demo-ws-inv-log-XXXXXX)"
info "log: $INV_LOGFILE"
( cd "$INVENTORY_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/inventorydb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    java -Dquarkus.http.port="$INVENTORY_PORT" -Dquarkus.grpc.server.port="$INVENTORY_GRPC_PORT" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$INV_LOGFILE" 2>&1 &
echo "$!" > "$INV_PIDFILE"
SVC_PIDFILES+=("$INV_PIDFILE")
wait_http "${INVENTORY_BASE}/q/health/live" 60 \
    || { tail -n 60 "$INV_LOGFILE" >&2; fail "inventory-service did not become healthy within 60s -- see $INV_LOGFILE"; }
info "inventory-service is up"

step "seed deterministic stock via REST (idempotent upsert)"
curl -fsS --max-time 10 -X POST "${INVENTORY_BASE}/stock" \
    -H 'Content-Type: application/json' \
    -d '{"sku":"WIDGET-1","quantityOnHand":50,"available":true}' >/dev/null \
    || fail "seeding WIDGET-1 via POST /stock failed"

# ─── Start notification-service with the per-run unique incoming topic ────
step "start notification-service (HTTP ${NOTIFICATION_PORT}, topic=${TOPIC})"
NOTIF_PIDFILE="$(mktemp -t demo-ws-notif-pid-XXXXXX)"
NOTIF_LOGFILE="$(mktemp -t demo-ws-notif-log-XXXXXX)"
info "log: $NOTIF_LOGFILE"
( cd "$NOTIFICATION_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/notificationdb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
    APICURIO_REGISTRY_URL="http://localhost:${APICURIO_PORT}/apis/registry/v3" \
    java -Dquarkus.http.port="$NOTIFICATION_PORT" \
        -Dmp.messaging.incoming.order-placed.topic="$TOPIC" \
        -Dorg.apache.avro.SERIALIZABLE_PACKAGES="$AVRO_SERIALIZABLE_PACKAGES" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$NOTIF_LOGFILE" 2>&1 &
echo "$!" > "$NOTIF_PIDFILE"
SVC_PIDFILES+=("$NOTIF_PIDFILE")
wait_http "${NOTIFICATION_BASE}/q/health/live" 60 \
    || { tail -n 60 "$NOTIF_LOGFILE" >&2; fail "notification-service did not become healthy within 60s -- see $NOTIF_LOGFILE"; }
info "notification-service is up (REST /notifications + WS /ws/notifications)"

# ─── Start order-service with the matching per-run unique outgoing topic ──
step "start order-service (HTTP ${ORDER_PORT}, topic=${TOPIC})"
ORD_PIDFILE="$(mktemp -t demo-ws-ord-pid-XXXXXX)"
ORD_LOGFILE="$(mktemp -t demo-ws-ord-log-XXXXXX)"
info "log: $ORD_LOGFILE"
( cd "$ORDER_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/orderdb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
    APICURIO_REGISTRY_URL="http://localhost:${APICURIO_PORT}/apis/registry/v3" \
    java -Dquarkus.http.port="$ORDER_PORT" \
        -Dmp.messaging.outgoing.order-placed.topic="$TOPIC" \
        -Dorg.apache.avro.SERIALIZABLE_PACKAGES="$AVRO_SERIALIZABLE_PACKAGES" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$ORD_LOGFILE" 2>&1 &
echo "$!" > "$ORD_PIDFILE"
SVC_PIDFILES+=("$ORD_PIDFILE")
wait_http "${ORDER_BASE}/q/health/live" 60 \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "order-service did not become healthy within 60s -- see $ORD_LOGFILE"; }
info "order-service is up"

# ─── Connect the REAL WebSocket client BEFORE triggering the event ─────────
step "connect a real WebSocket client to ${WS_URL} (jbang, plain JDK java.net.http.WebSocket)"
WS_CLIENT_LOG="$(mktemp -t demo-ws-client-log-XXXXXX)"
info "log: $WS_CLIENT_LOG"
# Expect exactly 2 text messages on this connection: (1) the @OnOpen
# connection ack, (2) the Notification pushed by OrderPlacedPushConsumer once
# this run's order.placed event is consumed.
jbang "$WS_CLIENT" "$WS_URL" 90 2 >"$WS_CLIENT_LOG" 2>&1 &
WS_CLIENT_PID=$!

WS_OPEN_SEEN=0
for (( i = 0; i < 60; i++ )); do
    grep -qF "WS_OPEN" "$WS_CLIENT_LOG" 2>/dev/null && { WS_OPEN_SEEN=1; break; }
    kill -0 "$WS_CLIENT_PID" 2>/dev/null || break
    sleep 1
done
(( WS_OPEN_SEEN == 1 )) \
    || { cat "$WS_CLIENT_LOG" >&2; fail "WebSocket client never reported WS_OPEN within 60s -- see $WS_CLIENT_LOG"; }
narrate "WebSocket client connected"

step "assert connection-ack message (first WS_MSG)"
ACK_JSON=""
for (( i = 0; i < 20; i++ )); do
    ACK_JSON="$(grep -m1 '^WS_MSG:' "$WS_CLIENT_LOG" 2>/dev/null | sed 's/^WS_MSG://')"
    [[ -n "$ACK_JSON" ]] && break
    sleep 0.5
done
[[ -n "$ACK_JSON" ]] || { cat "$WS_CLIENT_LOG" >&2; fail "no connection-ack message observed on the WebSocket within budget"; }
info "ack message: $ACK_JSON"
assert_json_field "$ACK_JSON" '.type' 'connected'
narrate "confirmed: real WebSocket connection-ack received and parsed (.type == \"connected\")"

# ─── Trigger: a real order, which triggers the full event chain ───────────
step "POST /orders (WIDGET-1 x1) -- triggers the order.placed -> Kafka -> notification-service -> WS chain"
CUSTOMER_ID="cust-demo-ws-$$"
CREATE_RESP="$(curl -sS --max-time 15 -w '\n%{http_code}' -X POST "${ORDER_BASE}/orders" \
    -H 'Content-Type: application/json' \
    -d '{"customerId":"'"$CUSTOMER_ID"'","itemSku":"WIDGET-1","quantity":1,"amount":19.99}')"
CREATE_BODY="$(head -n -1 <<<"$CREATE_RESP")"
CREATE_CODE="$(tail -n1 <<<"$CREATE_RESP")"
[[ "$CREATE_CODE" == "201" ]] \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "expected HTTP 201 from POST /orders, got $CREATE_CODE (body: $CREATE_BODY)"; }
ORDER_ID="$(jq -r '.orderId' <<<"$CREATE_BODY")"
[[ -n "$ORDER_ID" && "$ORDER_ID" != "null" ]] || fail "POST /orders response had no .orderId: $CREATE_BODY"
narrate "placed order id=${ORDER_ID} -- waiting for it to arrive over the live WebSocket"

# ─── Assert: the SECOND WS message is the pushed Notification for THIS order
step "assert the pushed Notification message (second WS_MSG) matches this order"
PUSH_JSON=""
for (( i = 0; i < 90; i++ )); do
    PUSH_JSON="$(grep '^WS_MSG:' "$WS_CLIENT_LOG" 2>/dev/null | sed -n '2p' | sed 's/^WS_MSG://')"
    [[ -n "$PUSH_JSON" ]] && break
    kill -0 "$WS_CLIENT_PID" 2>/dev/null || break
    sleep 1
done
if [[ -z "$PUSH_JSON" ]]; then
    tail -n 60 "$ORD_LOGFILE" >&2
    tail -n 60 "$NOTIF_LOGFILE" >&2
    cat "$WS_CLIENT_LOG" >&2
    fail "no Notification message arrived over the live WebSocket within 90s for order ${ORDER_ID} -- see service logs and WS client log above"
fi
info "pushed message: $PUSH_JSON"
assert_json_field "$PUSH_JSON" '.orderId' "$ORDER_ID"
assert_json_field "$PUSH_JSON" '.eventType' 'order.placed'
assert_json_field "$PUSH_JSON" '.customerId' "$CUSTOMER_ID"
assert_json_field "$PUSH_JSON" '.itemSku' 'WIDGET-1'
assert_json_field "$PUSH_JSON" '.quantity' '1'
narrate "confirmed: a real, parsed Notification for order ${ORDER_ID} was pushed over the live"
narrate "WebSocket connection -- orderId/eventType/customerId/itemSku/quantity all match the order"
narrate "just placed, proving the full order-service -> Kafka -> notification-service -> WS chain"

step "wait for the WS client to exit cleanly (received its expected 2 messages)"
wait "$WS_CLIENT_PID"
WS_CLIENT_RC=$?
WS_CLIENT_PID=""
(( WS_CLIENT_RC == 0 )) \
    || { cat "$WS_CLIENT_LOG" >&2; fail "WebSocket client exited non-zero ($WS_CLIENT_RC) -- see $WS_CLIENT_LOG"; }
grep -qF "WS_DONE" "$WS_CLIENT_LOG" \
    || { cat "$WS_CLIENT_LOG" >&2; fail "WebSocket client did not report WS_DONE"; }
narrate "WebSocket client received exactly its expected 2 messages and closed cleanly"

step "corroborate: GET /notifications (REST) shows the same row the WS push carried"
NOTIF_LIST="$(curl -fsS --max-time 10 "${NOTIFICATION_BASE}/notifications")" \
    || fail "GET ${NOTIFICATION_BASE}/notifications failed"
jq -e --arg id "$ORDER_ID" 'any(.[]; .orderId == $id)' <<<"$NOTIF_LIST" >/dev/null \
    || fail "GET /notifications did not contain order ${ORDER_ID}: $NOTIF_LIST"
narrate "confirmed: the persisted Notification row (REST) and the WebSocket push agree on order ${ORDER_ID}"

demo_ok
