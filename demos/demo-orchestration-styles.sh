#!/usr/bin/env bash
#
# demos/demo-orchestration-styles.sh — Phase D step 10 showcase demo
# (DRQ-015): "three engines, different orchestration styles" over the SAME
# shipping/order domain.
#
# This is the teaching demo for choreography vs orchestration. It runs THREE
# coordination mechanisms back to back and narrates the distinction:
#
#   1. KAFKA = CHOREOGRAPHY (decentralized, no coordinator). A real order
#      triggers order-service to publish order.placed; payment-service reacts
#      on its own and publishes payment.captured; shipping-service reacts to
#      THAT on its own and publishes shipment.dispatched. No service knows
#      about the whole sequence -- each one only knows "when I see event X, I
#      do Y and emit Z". All three events are Avro over Kafka (Apicurio).
#
#   2. CAMEL = ORCHESTRATION (centralized route/EIP coordinates steps).
#      ai-rules-service's POST /api/orders/triage runs a single Camel route
#      that explicitly sequences classify -> Drools rules -> decision.
#
#   3. QUARKUS FLOW = ORCHESTRATION (declarative CNCF Serverless Workflow
#      engine, a SECOND, different orchestration engine coordinating the
#      identical steps). POST /api/orders/triage-flow runs the same
#      classify -> Drools rules -> decision sequence, declared as a workflow
#      document instead of imperative route code.
#
# Kafka's chain and the two triage endpoints are two independent capabilities
# of this reactor (order/payment/shipping/notification-service vs
# ai-rules-service) -- there is no single "the same literal order" flowing
# through all three engines end to end, because the triage endpoints only
# accept the order's line-item fields (no persistence, no event publish) and
# the Kafka leg's order payload was never run through a classifier-stability
# trial. What IS the same across all three legs is the DOMAIN (shipping/order)
# and the comparison this demo exists to make: one decentralized mechanism
# (Kafka) vs two differently-shaped centralized ones (a Camel route; a
# declarative workflow document) coordinating the equivalent kind of step.
#
# ── Why packaged JVM mode against the compose baseline (not `quarkus:dev`) ──
# Mirrors demo-order.sh/demo-kafka.sh/demo-websocket.sh exactly: every
# service here wires its REAL external Postgres/Kafka/Apicurio ONLY under
# %prod (see each module's application.properties), which a packaged
# `quarkus-run.jar` runs under by default. This demo owns the compose
# baseline for its run (no other demo may run concurrently against compose)
# and tears it down on exit regardless of outcome.
#
# ── Avro SERIALIZABLE_PACKAGES -- producer AND consumer, per hop (DEF-002) ──
# Avro 1.12.x's ClassSecurityValidator refuses to (de)serialize a generated
# SpecificRecord class via reflection unless its package is explicitly
# trusted via -Dorg.apache.avro.SERIALIZABLE_PACKAGES on a plain `java -jar`
# process (a Quarkus-bootstrapped dev/test JVM trusts the app's own packages
# implicitly; a packaged prod JVM does not) -- see demo-order.sh/demo-kafka.sh
# header comments for the full trace, and demo-websocket.sh for the
# consumer-side instance of the identical gap. This demo's chain touches
# THREE different Avro packages across FOUR services, each of which needs
# every package it either reads or writes trusted:
#   order-service        (produces OrderPlaced)                    capstone.order.v1
#   payment-service       (consumes OrderPlaced, produces
#                          PaymentCaptured)             capstone.order.v1,capstone.payment.v1
#   shipping-service      (consumes PaymentCaptured, produces
#                          ShipmentDispatched)        capstone.payment.v1,capstone.shipping.v1
#   notification-service  (consumes OrderPlaced)                    capstone.order.v1
# Omitting any one of these throws "SecurityException: Forbidden
# capstone.*.v1.*!" on that service's own JVM, every time, for that hop only
# -- the rest of the chain looks fine, making a missing property on one
# single downstream hop easy to miss if you only watch the topic right after
# it (confirmed empirically while wiring this demo: dropping
# payment-service's capstone.payment.v1 entry let OrderPlaced deserialize
# fine but made every outgoing PaymentCaptured publish throw, so
# shipment.dispatched never appeared and the symptom looked like a
# shipping-service bug until payment-service's own log was checked).
#
# ── Per-run unique topics, threaded through every hop consistently ─────────
# Same reasoning as demo-kafka.sh/demo-websocket.sh (compose's kafka-data
# volume persists across runs) but THREE topics deep: the order-placed topic
# override must match on order-service's OUTGOING channel, payment-service's
# INCOMING channel, AND notification-service's INCOMING channel; the
# payment-captured topic override must match on payment-service's OUTGOING
# channel and shipping-service's INCOMING channel; the shipment-dispatched
# topic override only has one side (shipping-service's OUTGOING channel, read
# back by kcat, not by another service in this reactor).
#
# ── inventory-service gRPC port (canonical 9000, same as demo-order.sh) ─────
# order-service's gRPC client port and inventory-service's gRPC server port
# both default to 9000 (F2), both overridable via the same INVENTORY_GRPC_PORT
# env var -- started here with `-Dquarkus.grpc.server.port=9000` purely to
# keep the two sides programmatically in agreement. order-service cannot
# place an order at all without inventory-service reachable
# (InventoryClient.checkStock fails the whole request closed), so
# inventory-service is required even though it plays no further part in the
# choreography/orchestration comparison itself.
#
# ── ai-rules-service: Ollama via compose's `ollama` profile ─────────────────
# ai-rules-service's application.properties points at
# http://localhost:11434 unconditionally (no %prod override exists for it).
# demo-ai-triage.sh assumes a HOST Ollama is already running there; this demo
# instead brings up compose's `ollama` profile (`compose_up ollama`), which
# publishes the container's 11434 to the SAME host port (.env.example's
# OLLAMA_PORT=11434) -- so ai-rules-service needs no code/config change
# either way. Same preflight check as demo-ai-triage.sh (Ollama reachable,
# qwen2.5:3b in its model list), just pointed at the compose-managed
# container instead of a host install, and run AFTER compose_up instead of
# before. The qwen2.5:3b model must already be pulled into compose's
# `ollama-data` named volume (`docker exec datamesh-ollama ollama pull
# qwen2.5:3b` once) -- this demo does not pull it itself (a multi-GB
# download does not belong in a demo's critical path); the preflight below
# fails loud with that exact command if it's missing.
#
# ── Port plan (avoiding compose's host-published ports — see .env.example) ──
#   order-service          HTTP 8091
#   inventory-service      HTTP 8092, gRPC 9000 (canonical default)
#   notification-service   HTTP 8093
#   payment-service        HTTP 8094
#   shipping-service       HTTP 8095
#   ai-rules-service       HTTP 8089 (same port demo-ai-triage.sh uses)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-orchestration-styles"
require curl jq docker mvn java kcat od wc

ORDER_DIR="${EXAMPLES_DIR}/order-service"
INVENTORY_DIR="${EXAMPLES_DIR}/inventory-service"
NOTIFICATION_DIR="${EXAMPLES_DIR}/notification-service"
PAYMENT_DIR="${EXAMPLES_DIR}/payment-service"
SHIPPING_DIR="${EXAMPLES_DIR}/shipping-service"
AI_RULES_DIR="${EXAMPLES_DIR}/ai-rules-service"

ORDER_PORT=8091
INVENTORY_PORT=8092
INVENTORY_GRPC_PORT=9000
NOTIFICATION_PORT=8093
PAYMENT_PORT=8094
SHIPPING_PORT=8095
AI_RULES_PORT=8089

ORDER_BASE="http://localhost:${ORDER_PORT}"
INVENTORY_BASE="http://localhost:${INVENTORY_PORT}"
NOTIFICATION_BASE="http://localhost:${NOTIFICATION_PORT}"
PAYMENT_BASE="http://localhost:${PAYMENT_PORT}"
SHIPPING_BASE="http://localhost:${SHIPPING_PORT}"
AI_RULES_BASE="http://localhost:${AI_RULES_PORT}"
OLLAMA_URL="http://localhost:11434"

POSTGRES_PORT="${POSTGRES_PORT:-5432}"
KAFKA_HOST_PORT="${KAFKA_HOST_PORT:-9092}"
APICURIO_PORT="${APICURIO_PORT:-8081}"

TOPIC_ORDER="order.placed.orch.demo.$$"
TOPIC_PAYMENT="payment.captured.orch.demo.$$"
TOPIC_SHIPMENT="shipment.dispatched.orch.demo.$$"

narrate "DRQ-015: three engines, different orchestration styles, same"
narrate "shipping/order domain. Kafka choreography (order -> payment ->"
narrate "shipping, no coordinator) vs two ORCHESTRATION engines doing the"
narrate "identical classify-then-decide triage: a Camel route, and a"
narrate "declarative Quarkus Flow (Serverless Workflow) document."

# ─── .env prereq (compose var resolution) ───────────────────────────────────
if [[ ! -f "${REPO_ROOT}/.env" ]]; then
    [[ -f "${REPO_ROOT}/.env.example" ]] \
        || fail ".env is missing and there is no .env.example to copy from at ${REPO_ROOT}"
    info "no .env found -- copying .env.example -> .env (gitignored, documented prereq)"
    cp "${REPO_ROOT}/.env.example" "${REPO_ROOT}/.env"
fi
# shellcheck disable=SC1091
source "${REPO_ROOT}/.env"

# ─── Compose lifecycle: this script owns it (baseline + ollama profile) ────
step "bring up compose baseline + ollama profile (postgres, kafka, apicurio, otel-lgtm, ollama)"
compose_up ollama

SVC_PIDFILES=()
_cleanup() {
    local rc=$?
    local pf
    for pf in "${SVC_PIDFILES[@]:-}"; do
        [[ -n "$pf" ]] && svc_stop "$pf" 2>/dev/null || true
    done
    compose_down ollama 2>/dev/null || true
    return "$rc"
}
trap '_cleanup; _demo_exit_trap' EXIT

step "preflight: compose Postgres/Apicurio reachable"
for (( i = 0; i < 30; i++ )); do
    docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 && break
    sleep 1
done
docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 \
    || fail "compose Postgres (orderdb) did not become ready within 30s"
info "compose Postgres is ready"

# ─── Preflight: compose's Ollama container reachable with qwen2.5:3b pulled
# (same check demo-ai-triage.sh runs against a host Ollama; here it targets
# the compose-managed container instead, given the container's healthcheck
# has up to a 150s start_period/retry budget before Docker itself reports
# healthy) ───────────────────────────────────────────────────────────────
step "preflight: Ollama (ai-rules-service's triage dependency)"
OLLAMA_READY=0
for (( i = 0; i < 60; i++ )); do
    curl -fsS --max-time 5 "${OLLAMA_URL}/api/tags" >/tmp/demo-orch-ollama-tags.$$ 2>/dev/null && { OLLAMA_READY=1; break; }
    sleep 2
done
(( OLLAMA_READY == 1 )) \
    || fail "Ollama not reachable at ${OLLAMA_URL} after bringing up the compose 'ollama' profile"
grep -q 'qwen2.5:3b' /tmp/demo-orch-ollama-tags.$$ \
    || fail "qwen2.5:3b not found in Ollama's model list at ${OLLAMA_URL}/api/tags — pull it into the compose volume first: docker exec datamesh-ollama ollama pull qwen2.5:3b"
rm -f /tmp/demo-orch-ollama-tags.$$
info "Ollama is up and qwen2.5:3b is pulled"

# ─── Build every module this demo runs (idempotent) ─────────────────────────
step "build order/inventory/notification/payment/shipping/ai-rules services (mvn -DskipTests package)"
for d in "$ORDER_DIR" "$INVENTORY_DIR" "$NOTIFICATION_DIR" "$PAYMENT_DIR" "$SHIPPING_DIR" "$AI_RULES_DIR"; do
    ( cd "$d" && mvn -q -DskipTests package ) || fail "mvn package failed for ${d#"${REPO_ROOT}"/}"
    [[ -f "${d}/target/quarkus-app/quarkus-run.jar" ]] \
        || fail "${d#"${REPO_ROOT}"/} build did not produce target/quarkus-app/quarkus-run.jar"
done

# ─── Start inventory-service (order-service's gRPC CheckStock dependency) ──
step "start inventory-service (HTTP ${INVENTORY_PORT}, gRPC ${INVENTORY_GRPC_PORT})"
INV_PIDFILE="$(mktemp -t demo-orch-inv-pid-XXXXXX)"
INV_LOGFILE="$(mktemp -t demo-orch-inv-log-XXXXXX)"
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

# ─── Start order-service: produces order.placed (TOPIC_ORDER) ─────────────
step "start order-service (HTTP ${ORDER_PORT}, topic=${TOPIC_ORDER})"
ORD_PIDFILE="$(mktemp -t demo-orch-ord-pid-XXXXXX)"
ORD_LOGFILE="$(mktemp -t demo-orch-ord-log-XXXXXX)"
info "log: $ORD_LOGFILE"
( cd "$ORDER_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/orderdb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
    APICURIO_REGISTRY_URL="http://localhost:${APICURIO_PORT}/apis/registry/v3" \
    java -Dquarkus.http.port="$ORDER_PORT" \
        -Dmp.messaging.outgoing.order-placed.topic="$TOPIC_ORDER" \
        -Dorg.apache.avro.SERIALIZABLE_PACKAGES="capstone.order.v1" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$ORD_LOGFILE" 2>&1 &
echo "$!" > "$ORD_PIDFILE"
SVC_PIDFILES+=("$ORD_PIDFILE")
wait_http "${ORDER_BASE}/q/health/live" 60 \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "order-service did not become healthy within 60s -- see $ORD_LOGFILE"; }
info "order-service is up"

# ─── Start payment-service: consumes order.placed, produces payment.captured
step "start payment-service (HTTP ${PAYMENT_PORT}, in=${TOPIC_ORDER} out=${TOPIC_PAYMENT})"
PAY_PIDFILE="$(mktemp -t demo-orch-pay-pid-XXXXXX)"
PAY_LOGFILE="$(mktemp -t demo-orch-pay-log-XXXXXX)"
info "log: $PAY_LOGFILE"
( cd "$PAYMENT_DIR" && exec env \
    TZ=UTC \
    KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
    APICURIO_REGISTRY_URL="http://localhost:${APICURIO_PORT}/apis/registry/v3" \
    java -Dquarkus.http.port="$PAYMENT_PORT" \
        -Dmp.messaging.incoming.order-placed.topic="$TOPIC_ORDER" \
        -Dmp.messaging.outgoing.payment-captured.topic="$TOPIC_PAYMENT" \
        -Dorg.apache.avro.SERIALIZABLE_PACKAGES="capstone.order.v1,capstone.payment.v1" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$PAY_LOGFILE" 2>&1 &
echo "$!" > "$PAY_PIDFILE"
SVC_PIDFILES+=("$PAY_PIDFILE")
wait_http "${PAYMENT_BASE}/q/health/live" 60 \
    || { tail -n 60 "$PAY_LOGFILE" >&2; fail "payment-service did not become healthy within 60s -- see $PAY_LOGFILE"; }
info "payment-service is up"

# ─── Start shipping-service: consumes payment.captured, produces
# shipment.dispatched, persists a Shipment row (shippingdb) ────────────────
step "start shipping-service (HTTP ${SHIPPING_PORT}, in=${TOPIC_PAYMENT} out=${TOPIC_SHIPMENT})"
SHIP_PIDFILE="$(mktemp -t demo-orch-ship-pid-XXXXXX)"
SHIP_LOGFILE="$(mktemp -t demo-orch-ship-log-XXXXXX)"
info "log: $SHIP_LOGFILE"
( cd "$SHIPPING_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/shippingdb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
    APICURIO_REGISTRY_URL="http://localhost:${APICURIO_PORT}/apis/registry/v3" \
    java -Dquarkus.http.port="$SHIPPING_PORT" \
        -Dmp.messaging.incoming.payment-captured.topic="$TOPIC_PAYMENT" \
        -Dmp.messaging.outgoing.shipment-dispatched.topic="$TOPIC_SHIPMENT" \
        -Dorg.apache.avro.SERIALIZABLE_PACKAGES="capstone.payment.v1,capstone.shipping.v1" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$SHIP_LOGFILE" 2>&1 &
echo "$!" > "$SHIP_PIDFILE"
SVC_PIDFILES+=("$SHIP_PIDFILE")
wait_http "${SHIPPING_BASE}/q/health/live" 60 \
    || { tail -n 60 "$SHIP_LOGFILE" >&2; fail "shipping-service did not become healthy within 60s -- see $SHIP_LOGFILE"; }
info "shipping-service is up"

# ─── Start notification-service: consumes order.placed independently of the
# payment/shipping chain -- its own reaction to the SAME event, proving
# there is no single coordinator deciding "who reacts to order.placed" ─────
step "start notification-service (HTTP ${NOTIFICATION_PORT}, in=${TOPIC_ORDER})"
NOTIF_PIDFILE="$(mktemp -t demo-orch-notif-pid-XXXXXX)"
NOTIF_LOGFILE="$(mktemp -t demo-orch-notif-log-XXXXXX)"
info "log: $NOTIF_LOGFILE"
( cd "$NOTIFICATION_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/notificationdb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
    APICURIO_REGISTRY_URL="http://localhost:${APICURIO_PORT}/apis/registry/v3" \
    java -Dquarkus.http.port="$NOTIFICATION_PORT" \
        -Dmp.messaging.incoming.order-placed.topic="$TOPIC_ORDER" \
        -Dorg.apache.avro.SERIALIZABLE_PACKAGES="capstone.order.v1" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$NOTIF_LOGFILE" 2>&1 &
echo "$!" > "$NOTIF_PIDFILE"
SVC_PIDFILES+=("$NOTIF_PIDFILE")
wait_http "${NOTIFICATION_BASE}/q/health/live" 60 \
    || { tail -n 60 "$NOTIF_LOGFILE" >&2; fail "notification-service did not become healthy within 60s -- see $NOTIF_LOGFILE"; }
info "notification-service is up"

# ─── Start ai-rules-service (both triage endpoints live on one process,
# exactly like demo-ai-triage.sh) ───────────────────────────────────────────
step "start ai-rules-service (HTTP ${AI_RULES_PORT})"
AI_PIDFILE="$(mktemp -t demo-orch-ai-pid-XXXXXX)"
AI_LOGFILE="$(mktemp -t demo-orch-ai-log-XXXXXX)"
info "log: $AI_LOGFILE"
( cd "$AI_RULES_DIR" && exec java -Dquarkus.http.port="$AI_RULES_PORT" -jar target/quarkus-app/quarkus-run.jar >"$AI_LOGFILE" 2>&1 ) &
echo "$!" > "$AI_PIDFILE"
SVC_PIDFILES+=("$AI_PIDFILE")

# ai-rules-service has no GET route that answers 2xx (only POST
# /api/orders/triage[-flow]), so wait_http (which requires a 2xx/3xx) can
# never succeed here -- same gap demo-ai-triage.sh documents. Wait for ANY
# HTTP response (connection refused -> connected) instead.
wait_any_http() {
    local url="$1" budget="${2:-60}" i
    for (( i = 0; i < budget; i++ )); do
        curl -s -o /dev/null --max-time 2 "$url" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}
wait_any_http "${AI_RULES_BASE}/api/orders/triage" 60 \
    || { tail -n 60 "$AI_LOGFILE" >&2; fail "ai-rules-service did not start listening on ${AI_RULES_PORT} within 60s -- see $AI_LOGFILE"; }
info "ai-rules-service is listening on ${AI_RULES_PORT}"

# ═══════════════════════════════════════════════════════════════════════════
# ACT 1 — KAFKA CHOREOGRAPHY: order.placed -> payment.captured ->
# shipment.dispatched, no central coordinator
# ═══════════════════════════════════════════════════════════════════════════
step "ACT 1/3 — Kafka choreography: order-service -> payment-service -> shipping-service"
narrate "placing one real order. order-service only knows how to publish"
narrate "order.placed -- it has never heard of payment-service or"
narrate "shipping-service. Each downstream service decided for itself to"
narrate "react to the event it cares about and emit the next one."

CUSTOMER_ID="cust-demo-orch-$$"
CREATE_RESP="$(curl -sS --max-time 15 -w '\n%{http_code}' -X POST "${ORDER_BASE}/orders" \
    -H 'Content-Type: application/json' \
    -d '{"customerId":"'"$CUSTOMER_ID"'","itemSku":"WIDGET-1","quantity":1,"amount":39.99}')"
CREATE_BODY="$(head -n -1 <<<"$CREATE_RESP")"
CREATE_CODE="$(tail -n1 <<<"$CREATE_RESP")"
[[ "$CREATE_CODE" == "201" ]] \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "expected HTTP 201 from POST /orders, got $CREATE_CODE (body: $CREATE_BODY)"; }
ORDER_ID="$(jq -r '.orderId' <<<"$CREATE_BODY")"
[[ -n "$ORDER_ID" && "$ORDER_ID" != "null" ]] || fail "POST /orders response had no .orderId: $CREATE_BODY"
narrate "placed order id=${ORDER_ID} -- polling the choreography chain next"

# ─── Hop 1: payment-service reacted to order.placed and emitted
# payment.captured (raw bytes, no Avro decoder -- same DEF-002 proof as
# demo-kafka.sh) ─────────────────────────────────────────────────────────
step "kcat -- hop 1: payment.captured (topic ${TOPIC_PAYMENT})"
PAY_RAW="$(mktemp -t demo-orch-pay-raw-XXXXXX.bin)"
PAY_KCAT_LOG="$(mktemp -t demo-orch-pay-kcat-log-XXXXXX)"
GOT_PAYMENT=0
for (( i = 0; i < 45; i++ )); do
    if kcat -C -b "localhost:${KAFKA_HOST_PORT}" -t "$TOPIC_PAYMENT" -o beginning -c 1 -e -f '%s' \
        >"$PAY_RAW" 2>"$PAY_KCAT_LOG" && [[ -s "$PAY_RAW" ]]; then
        GOT_PAYMENT=1
        break
    fi
    sleep 1
done
(( GOT_PAYMENT == 1 )) \
    || { cat "$PAY_KCAT_LOG" >&2; tail -n 60 "$PAY_LOGFILE" >&2; fail "did not receive a message on topic ${TOPIC_PAYMENT} within 45s -- payment-service never reacted to order.placed -- see kcat log and $PAY_LOGFILE"; }
PAY_LEN="$(wc -c < "$PAY_RAW" | tr -d '[:space:]')"
(( PAY_LEN > 5 )) || fail "payment.captured record value too short (${PAY_LEN} bytes) to carry an Apicurio Avro schema id"
PAY_FIRST_BYTE="$(od -An -tx1 -N1 "$PAY_RAW" | tr -d '[:space:]')"
info "payment.captured raw record: ${PAY_LEN} bytes, first byte = 0x${PAY_FIRST_BYTE}"
[[ "$PAY_FIRST_BYTE" == "00" ]] \
    || fail "expected Apicurio/Confluent Avro wire-format magic byte 0x00 on payment.captured, got 0x${PAY_FIRST_BYTE}"
narrate "confirmed: payment-service reacted to order.placed on its own and emitted"
narrate "a real Avro payment.captured event -- order-service never told it to"

# ─── Hop 2: shipping-service reacted to payment.captured and emitted
# shipment.dispatched ───────────────────────────────────────────────────
step "kcat -- hop 2: shipment.dispatched (topic ${TOPIC_SHIPMENT})"
SHIP_RAW="$(mktemp -t demo-orch-ship-raw-XXXXXX.bin)"
SHIP_KCAT_LOG="$(mktemp -t demo-orch-ship-kcat-log-XXXXXX)"
GOT_SHIPMENT=0
for (( i = 0; i < 45; i++ )); do
    if kcat -C -b "localhost:${KAFKA_HOST_PORT}" -t "$TOPIC_SHIPMENT" -o beginning -c 1 -e -f '%s' \
        >"$SHIP_RAW" 2>"$SHIP_KCAT_LOG" && [[ -s "$SHIP_RAW" ]]; then
        GOT_SHIPMENT=1
        break
    fi
    sleep 1
done
(( GOT_SHIPMENT == 1 )) \
    || { cat "$SHIP_KCAT_LOG" >&2; tail -n 60 "$SHIP_LOGFILE" >&2; fail "did not receive a message on topic ${TOPIC_SHIPMENT} within 45s -- shipping-service never reacted to payment.captured -- see kcat log and $SHIP_LOGFILE"; }
SHIP_LEN="$(wc -c < "$SHIP_RAW" | tr -d '[:space:]')"
(( SHIP_LEN > 5 )) || fail "shipment.dispatched record value too short (${SHIP_LEN} bytes) to carry an Apicurio Avro schema id"
SHIP_FIRST_BYTE="$(od -An -tx1 -N1 "$SHIP_RAW" | tr -d '[:space:]')"
info "shipment.dispatched raw record: ${SHIP_LEN} bytes, first byte = 0x${SHIP_FIRST_BYTE}"
[[ "$SHIP_FIRST_BYTE" == "00" ]] \
    || fail "expected Apicurio/Confluent Avro wire-format magic byte 0x00 on shipment.dispatched, got 0x${SHIP_FIRST_BYTE}"
narrate "confirmed: shipping-service reacted to payment.captured on its own and"
narrate "emitted a real Avro shipment.dispatched event -- payment-service never"
narrate "told it to, and neither service knows the OTHER exists"

# ─── Corroborate: shipping-service's own data product has the row ─────────
# Column names: Shipment (shipping-service's entity) now carries explicit
# @Column(name = "...") overrides on its multi-word fields, mirroring
# Order's (order_id/customer_id) -- confirmed by inspecting \d shipment
# against a live run: columns are order_id/customer_id/item_sku/
# tracking_number/dispatched_at (snake_case), no longer the prior
# Hibernate-default lowercased-no-underscore names.
step "direct Postgres row check (shippingdb) -- shipping-service's own data product"
SHIP_ROW_COUNT="$(docker exec datamesh-postgres psql -U "${POSTGRES_USER:-appuser}" -d shippingdb -tAc \
    "SELECT count(*) FROM shipment WHERE order_id = '${ORDER_ID}' AND customer_id = '${CUSTOMER_ID}' AND status = 'dispatched';" \
    2>/dev/null | tr -d '[:space:]')"
[[ "$SHIP_ROW_COUNT" == "1" ]] \
    || fail "expected exactly 1 matching row in shippingdb.shipment for order ${ORDER_ID}, found '${SHIP_ROW_COUNT}'"
narrate "confirmed: 1 row in shippingdb.shipment for order ${ORDER_ID} (shipping-service's own persisted record)"

# ─── Corroborate: notification-service reacted to order.placed independently
# of the payment/shipping chain -- a THIRD, unrelated reaction to the SAME
# original event, further proof there is no single coordinator ────────────
step "corroborate: notification-service independently reacted to order.placed"
NOTIF_LIST=""
for (( i = 0; i < 30; i++ )); do
    NOTIF_LIST="$(curl -fsS --max-time 10 "${NOTIFICATION_BASE}/notifications" 2>/dev/null)"
    if jq -e --arg id "$ORDER_ID" 'any(.[]?; .orderId == $id)' <<<"$NOTIF_LIST" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
jq -e --arg id "$ORDER_ID" 'any(.[]?; .orderId == $id)' <<<"$NOTIF_LIST" >/dev/null \
    || { tail -n 60 "$NOTIF_LOGFILE" >&2; fail "GET /notifications never showed order ${ORDER_ID} -- notification-service did not react to order.placed: $NOTIF_LIST"; }
narrate "confirmed: notification-service ALSO reacted to the same order.placed event on"
narrate "its own -- three independent reactions (payment, shipping, notification) to ONE"
narrate "event, with no service orchestrating the others. This is choreography."

# ═══════════════════════════════════════════════════════════════════════════
# ACT 2 — CAMEL ORCHESTRATION: one centrally-coordinated route
# ═══════════════════════════════════════════════════════════════════════════
VALID_DECISIONS='FRAUD_HOLD EXPEDITE ROUTE_TO_WAREHOUSE'
# Pre-validated stable input (same as demo-ai-triage.sh): low amount,
# ordinary item -> deterministic ROUTE_TO_WAREHOUSE for qwen2.5:3b across
# repeated trials, so this assertion is strict, not merely membership.
TRIAGE_ORDER='{"customerId":"CUST-1001","itemSku":"BOOK-NOVEL-001","quantity":1,"amount":19.99}'

assert_decision_member() {
    local json="$1" label="$2" actual
    actual="$(jq -r '.decision' <<<"$json" 2>/dev/null)" \
        || fail "[$label] response was not parseable JSON: $json"
    case " $VALID_DECISIONS " in
        *" $actual "*) ;;
        *) fail "[$label] .decision = '$actual' is not one of {$VALID_DECISIONS} (json: $json)" ;;
    esac
    echo "$actual"
}

step "ACT 2/3 — Camel orchestration: POST /api/orders/triage"
narrate "one Camel route explicitly sequences classify (Ollama) -> Drools"
narrate "rules -> decision -- a single, named, centrally-coordinated flow."
CAMEL_JSON="$(curl -sS --max-time 60 -X POST "${AI_RULES_BASE}/api/orders/triage" \
    -H 'Content-Type: application/json' -d "$TRIAGE_ORDER")"
info "response: $CAMEL_JSON"
CAMEL_DECISION="$(assert_decision_member "$CAMEL_JSON" "Camel /triage")"
assert_json_field "$CAMEL_JSON" '.decision' 'ROUTE_TO_WAREHOUSE'
[[ "$(jq -r '.reason' <<<"$CAMEL_JSON")" != "null" ]] || fail "[Camel /triage] .reason was null"
narrate "confirmed: decision=${CAMEL_DECISION}, reason present -- the Camel route"
narrate "coordinated every step of this request itself"

# ═══════════════════════════════════════════════════════════════════════════
# ACT 3 — QUARKUS FLOW ORCHESTRATION: a second, differently-shaped
# orchestration engine coordinating the identical steps
# ═══════════════════════════════════════════════════════════════════════════
step "ACT 3/3 — Quarkus Flow orchestration: POST /api/orders/triage-flow"
narrate "the SAME classify -> Drools -> decision sequence, this time declared"
narrate "as a CNCF Serverless Workflow document and run by the Quarkus Flow"
narrate "engine instead of imperative Camel route code."
FLOW_JSON="$(curl -sS --max-time 60 -X POST "${AI_RULES_BASE}/api/orders/triage-flow" \
    -H 'Content-Type: application/json' -d "$TRIAGE_ORDER")"
info "response: $FLOW_JSON"
FLOW_DECISION="$(assert_decision_member "$FLOW_JSON" "Flow /triage-flow")"
assert_json_field "$FLOW_JSON" '.decision' 'ROUTE_TO_WAREHOUSE'
[[ "$(jq -r '.reason' <<<"$FLOW_JSON")" != "null" ]] || fail "[Flow /triage-flow] .reason was null"
narrate "confirmed: decision=${FLOW_DECISION}, reason present -- the Quarkus Flow"
narrate "engine coordinated every step of this request itself, via a declarative"
narrate "workflow document instead of a route"

# ═══════════════════════════════════════════════════════════════════════════
# RECAP
# ═══════════════════════════════════════════════════════════════════════════
step "recap: choreography vs orchestration, side by side"
narrate "CHOREOGRAPHY (Kafka)   -- order.placed -> payment.captured ->"
narrate "                          shipment.dispatched: 3 services, each"
narrate "                          reacting independently, NO coordinator."
narrate "ORCHESTRATION (Camel)  -- /api/orders/triage: ONE route centrally"
narrate "                          sequences classify -> rules -> decision."
narrate "ORCHESTRATION (Flow)   -- /api/orders/triage-flow: the SAME steps,"
narrate "                          coordinated by a SECOND, different engine"
narrate "                          -- a declarative workflow document, not"
narrate "                          imperative route code."
narrate "Same domain, same kind of decision -- three different coordination"
narrate "mechanisms, two of which (Camel, Flow) are both \"orchestration\" but"
narrate "are not the same engine."

demo_ok
