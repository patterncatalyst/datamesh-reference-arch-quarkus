#!/usr/bin/env bash
#
# demos/demo-kafka.sh — "compose (infra baseline)" demo:
# Kafka via Reactive Messaging, Avro-serialized.
#
# order-service's OrderEventProducer publishes order.placed as a real Avro
# record against the Apicurio Schema Registry (io.apicurio.registry.serde.
# avro.AvroKafkaSerializer, set EXPLICITLY in application.properties --
# Quarkus's connector-serializer autodetection was proven to silently fall
# back to a Jackson/JSON serializer here, see that file's comment). This
# demo places a real order (which triggers the publish) and then reads the
# RAW bytes back off the compose Kafka broker with a plain byte-level
# consumer (kcat) -- no Avro deserializer involved on the read side -- and
# asserts the Apicurio/Confluent wire-format magic byte (0x00) is the first
# byte of the record value. This is the same proof
# OrderPlacedAvroWireIT makes with Testcontainers in `mvn verify`; this demo
# makes the identical proof against the real standing compose stack instead.
#
# ── Why a per-run unique topic name ─────────────────────────────────────────
# order.placed's Kafka topic lives on compose's `kafka-data` NAMED VOLUME,
# which survives `docker compose down` (only `down -v` wipes it) -- so a
# fixed topic name would accumulate messages across repeated demo runs,
# spread over `KAFKA_NUM_PARTITIONS=3` partitions with no message key
# (OrderEventProducer sends unkeyed -- see its Javadoc), making "the last
# message on the topic" ambiguous without decoding Avro just to correlate
# content. Overriding `mp.messaging.outgoing.order-placed.topic` to a
# per-run unique name (a MicroProfile Config property, legitimately
# overridable via -D at launch, no module source touched) sidesteps this
# entirely: this run's topic has EXACTLY one message, so "the first message
# on this topic" is unambiguously ours.
#
# ── order.placed publish silently fails in packaged/%prod mode without an
# Avro security system property (found wiring THIS demo -- a real,
# previously undetected production-readiness gap) ───────────────────────────
# A packaged order-service boots and serves POST /orders fine (the publish
# is fire-and-forget -- OrderEventProducer's failure path only logs, see
# OrderResource.placeOrder's `.exceptionally(...)`), but without this fix
# every order.placed publish throws, every time (confirmed via order-
# service's own log; the symptom from this demo's point of view was kcat
# timing out waiting for a message that was never produced):
#   java.lang.SecurityException: Forbidden capstone.order.v1.OrderPlaced!
#   This class is not trusted to be included in Avro schemas. You may
#   either use the system properties org.apache.avro.SERIALIZABLE_CLASSES
#   and org.apache.avro.SERIALIZABLE_PACKAGES ...
# This is Avro 1.12.x's ClassSecurityValidator (upstream security
# hardening, not a Quarkus/Apicurio bug) -- it allow-lists which
# packages/classes may be instantiated via reflection during Avro
# (de)serialization, and a plain `java -jar` (unlike a Quarkus-bootstrapped
# dev/test JVM, which trusts the application's own packages implicitly)
# trusts nothing by default. The identical fix is already documented
# for the OTHER place this bites
# (OrderPlacedAvroWireIT's failsafe execution passes
# org.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1 as a plain JUnit
# system property for the same reason). This demo applies the same fix as a
# JVM system property on the launched order-service process -- no module
# source touched. Open upstream issue: the packaged/
# production image has the same exposure and would silently drop every
# order.placed event in a deployment unless this property (or an
# equivalent JAVA_TOOL_OPTIONS/JVM arg) is set wherever the image runs.
#
# ── Port plan (avoiding compose's host-published ports — see .env.example) ──
#   order-service      HTTP 8091
#   inventory-service  HTTP 8092, gRPC 9000 (canonical default -- see
#                       demo-order.sh's header comment)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-kafka"
require curl jq docker mvn java kcat od wc

ORDER_DIR="${EXAMPLES_DIR}/order-service"
INVENTORY_DIR="${EXAMPLES_DIR}/inventory-service"

ORDER_PORT=8091
INVENTORY_PORT=8092
INVENTORY_GRPC_PORT=9000

ORDER_BASE="http://localhost:${ORDER_PORT}"
INVENTORY_BASE="http://localhost:${INVENTORY_PORT}"

POSTGRES_PORT="${POSTGRES_PORT:-5432}"
KAFKA_HOST_PORT="${KAFKA_HOST_PORT:-9092}"
APICURIO_PORT="${APICURIO_PORT:-8081}"
APICURIO_BASE="http://localhost:${APICURIO_PORT}/apis/registry/v3"
# Avro 1.12.x's ClassSecurityValidator -- see header comment below. Without
# this, every order.placed publish from a packaged order-service throws
# (confirmed empirically -- this is the specific bug this fix sidesteps;
# there would be nothing on the topic at all otherwise).
AVRO_SERIALIZABLE_PACKAGES="capstone.order.v1"

TOPIC="order.placed.demo.$$"

narrate "Reactive Messaging + Avro: placing an order triggers"
narrate "OrderEventProducer to publish order.placed as Avro against Apicurio."
narrate "This demo reads the raw bytes back off the compose Kafka broker"
narrate "(kcat, no Avro decoder) and asserts the Apicurio/Confluent wire-format"
narrate "magic byte 0x00 -- confirmation it's Avro on the wire, not JSON."

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
_cleanup() {
    local rc=$?
    local pf
    for pf in "${SVC_PIDFILES[@]:-}"; do
        [[ -n "$pf" ]] && svc_stop "$pf" 2>/dev/null || true
    done
    compose_down 2>/dev/null || true
    return "$rc"
}
trap '_cleanup; _demo_exit_trap' EXIT

step "preflight: compose Postgres/Kafka/Apicurio reachable"
for (( i = 0; i < 30; i++ )); do
    docker exec datamesh-postgres pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 && break
    sleep 1
done
docker exec datamesh-postgres pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 \
    || fail "compose Postgres (orderdb) did not become ready within 30s"
wait_http "${APICURIO_BASE}/system/info" 60 \
    || fail "Apicurio registry did not answer at ${APICURIO_BASE}/system/info within 60s"
assert_http_200 "${APICURIO_BASE}/system/info"
info "Postgres + Apicurio are reachable"

# ─── Build both services (idempotent) ───────────────────────────────────────
step "build order-service + inventory-service (mvn -DskipTests package)"
( cd "$ORDER_DIR" && mvn -q -DskipTests package ) || fail "mvn package failed for order-service"
( cd "$INVENTORY_DIR" && mvn -q -DskipTests package ) || fail "mvn package failed for inventory-service"

# ─── Start inventory-service (order-service's gRPC CheckStock dependency) ──
step "start inventory-service (HTTP ${INVENTORY_PORT}, gRPC ${INVENTORY_GRPC_PORT})"
INV_PIDFILE="$(mktemp -t demo-kafka-inv-pid-XXXXXX)"
INV_LOGFILE="$(mktemp -t demo-kafka-inv-log-XXXXXX)"
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

# Seed deterministic stock via the REST demo surface instead of relying on
# import.sql: in packaged/%prod mode, inventory-service's effective
# Hibernate schema-generation action resolves to "update" (its %prod
# profile's deprecated database.generation=update alias wins over the
# unqualified schema-management.strategy=drop-and-create once "prod" is
# active -- confirmed empirically, see demo-order.sh's header comment for
# the full trace), and Hibernate skips import.sql under "update". No module
# source touched -- StockResource.seed() already exists for exactly this.
step "seed deterministic stock via REST (idempotent upsert)"
curl -fsS --max-time 10 -X POST "${INVENTORY_BASE}/stock" \
    -H 'Content-Type: application/json' \
    -d '{"sku":"WIDGET-1","quantityOnHand":50,"available":true}' >/dev/null \
    || fail "seeding WIDGET-1 via POST /stock failed"

# ─── Start order-service with a per-run unique order-placed topic ──────────
step "start order-service (HTTP ${ORDER_PORT}, topic=${TOPIC})"
ORD_PIDFILE="$(mktemp -t demo-kafka-ord-pid-XXXXXX)"
ORD_LOGFILE="$(mktemp -t demo-kafka-ord-log-XXXXXX)"
info "log: $ORD_LOGFILE"
( cd "$ORDER_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/orderdb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
    APICURIO_REGISTRY_URL="${APICURIO_BASE}" \
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

# ─── Baseline Apicurio artifact count (so the post-produce check is a real
# delta against this baseline, so artifacts registered earlier do not count) ──────────
BASELINE_COUNT="$(curl -fsS --max-time 10 "${APICURIO_BASE}/search/artifacts?limit=1" \
    | jq -r '.count // 0')"
info "Apicurio artifact count before producing: ${BASELINE_COUNT}"

# ─── Produce: place a real order, which triggers OrderEventProducer ────────
step "POST /orders (WIDGET-1 x1) -- triggers OrderEventProducer.publish()"
CUSTOMER_ID="cust-demo-kafka-$$"
CREATE_RESP="$(curl -sS --max-time 15 -w '\n%{http_code}' -X POST "${ORDER_BASE}/orders" \
    -H 'Content-Type: application/json' \
    -d '{"customerId":"'"$CUSTOMER_ID"'","itemSku":"WIDGET-1","quantity":1,"amount":29.99}')"
CREATE_BODY="$(head -n -1 <<<"$CREATE_RESP")"
CREATE_CODE="$(tail -n1 <<<"$CREATE_RESP")"
[[ "$CREATE_CODE" == "201" ]] \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "expected HTTP 201 from POST /orders, got $CREATE_CODE (body: $CREATE_BODY)"; }
ORDER_ID="$(jq -r '.orderId' <<<"$CREATE_BODY")"
[[ -n "$ORDER_ID" && "$ORDER_ID" != "null" ]] || fail "POST /orders response had no .orderId: $CREATE_BODY"
narrate "placed order id=${ORDER_ID} -- order.placed publish is best-effort/async, polling the topic next"

# ─── Consume: raw bytes, no Avro deserializer, off the real compose broker ──
step "kcat -C -- raw consume from topic ${TOPIC} (no schema, no Avro decoder)"
RAW_FILE="$(mktemp -t demo-kafka-raw-XXXXXX.bin)"
KCAT_LOG="$(mktemp -t demo-kafka-kcat-log-XXXXXX)"
GOT_MESSAGE=0
for (( i = 0; i < 30; i++ )); do
    if kcat -C -b "localhost:${KAFKA_HOST_PORT}" -t "$TOPIC" -o beginning -c 1 -e -f '%s' \
        >"$RAW_FILE" 2>"$KCAT_LOG" && [[ -s "$RAW_FILE" ]]; then
        GOT_MESSAGE=1
        break
    fi
    sleep 1
done
(( GOT_MESSAGE == 1 )) \
    || { cat "$KCAT_LOG" >&2; fail "did not receive a message on topic ${TOPIC} within 30s -- see kcat log above and ${ORD_LOGFILE}"; }

RAW_LEN="$(wc -c < "$RAW_FILE" | tr -d '[:space:]')"
(( RAW_LEN > 5 )) \
    || fail "record value too short (${RAW_LEN} bytes) to carry an Apicurio Avro schema id"
FIRST_BYTE_HEX="$(od -An -tx1 -N1 "$RAW_FILE" | tr -d '[:space:]')"
info "raw record value: ${RAW_LEN} bytes, first byte = 0x${FIRST_BYTE_HEX}"

[[ "$FIRST_BYTE_HEX" == "00" ]] \
    || fail "expected Apicurio/Confluent Avro wire-format magic byte 0x00 as the first byte, got 0x${FIRST_BYTE_HEX} (is OrderEventProducer still using AvroKafkaSerializer?)"
[[ "$FIRST_BYTE_HEX" != "7b" ]] \
    || fail "record value starts with '{' (0x7b) -- serde has regressed to JSON (Avro wire format expected)"
narrate "confirmed: order.placed value on the compose Kafka broker starts with the"
narrate "Avro wire-format magic byte 0x00 -- not JSON, not any other encoding"

# ─── Corroborate: Apicurio registered a schema for this publish ────────────
step "Apicurio registry -- confirm a schema was registered for this run"
AFTER_JSON="$(curl -fsS --max-time 10 "${APICURIO_BASE}/search/artifacts?limit=100")" \
    || fail "GET ${APICURIO_BASE}/search/artifacts failed"
AFTER_COUNT="$(jq -r '.count // 0' <<<"$AFTER_JSON")"
info "Apicurio artifact count after producing: ${AFTER_COUNT} (was ${BASELINE_COUNT})"
(( AFTER_COUNT > BASELINE_COUNT )) \
    || fail "Apicurio artifact count did not increase after publishing to ${TOPIC} (before=${BASELINE_COUNT}, after=${AFTER_COUNT}) -- auto-register may have failed"

MATCHING_ARTIFACT="$(jq -r --arg t "$TOPIC" \
    '[.artifacts[]? | select((.artifactId // "") | test($t))] | length' <<<"$AFTER_JSON")"
if [[ "$MATCHING_ARTIFACT" -ge 1 ]]; then
    narrate "confirmed: Apicurio registered an artifact whose id references topic ${TOPIC}"
else
    ARTIFACT_NAMES="$(jq -r '.artifacts[]?.artifactId' <<<"$AFTER_JSON" | tr '\n' ' ')"
    info "no artifactId matched the topic name directly (default Apicurio id strategy may key on the"
    info "record's fully-qualified Avro name instead) -- registered artifact ids: ${ARTIFACT_NAMES}"
    jq -e --arg t "capstone.order.v1.OrderPlaced" \
        '[.artifacts[]? | select((.artifactId // "") == $t)] | length >= 1' <<<"$AFTER_JSON" >/dev/null \
        || fail "could not find a registered artifact matching either the topic name (${TOPIC}) or capstone.order.v1.OrderPlaced: ${ARTIFACT_NAMES}"
    narrate "confirmed: Apicurio registered the capstone.order.v1.OrderPlaced schema"
fi

demo_ok
