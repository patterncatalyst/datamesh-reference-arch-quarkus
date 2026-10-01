#!/usr/bin/env bash
#
# demos/demo-order.sh — Phase D step 10.6 "compose (infra baseline)" demo:
# the Panache + REST order data product.
#
# POST /orders on order-service:
#   1. calls inventory-service over gRPC (CheckStock) to validate the SKU
#      has enough stock on hand,
#   2. persists the Order via Hibernate ORM Panache (Postgres),
#   3. publishes order.placed to Kafka (best-effort, not asserted here —
#      see demo-kafka.sh for the Avro-wire-format proof of that path).
#
# This demo proves the FIRST two: a real round trip through Panache/Postgres.
# order-service cannot place an order at all without a reachable
# inventory-service (InventoryClient.checkStock is called synchronously and
# uncaught gRPC failures fail the whole request closed — see
# OrderResource.placeOrder), so this demo also boots inventory-service.
#
# ── Why packaged JVM mode (java -jar quarkus-run.jar), not `mvn quarkus:dev`
# Both order-service and inventory-service wire their REAL external
# Postgres/Kafka/Apicurio ONLY under the %prod profile (see each module's
# application.properties, "%prod overrides" section) — exactly the
# compose.yaml stack this demo brings up (infra/db/init/00-init.sql
# pre-creates one database per service: orderdb, inventorydb, ...). A
# packaged quarkus-run.jar runs under the "prod" profile by default (no
# Dev Services), so this is the natural way to exercise the compose
# baseline rather than each service's own ephemeral Dev Services
# Testcontainers (which `mvn quarkus:dev` would instead spin up, bypassing
# the compose stack entirely).
#
# ── The inventory gRPC port (F2 fixed; canonical 9000) ──────────────────────
# order-service's gRPC CLIENT port and inventory-service's gRPC SERVER port
# both default to the SAME value, 9000, and are both overridable via the
# SAME env var:
#     quarkus.grpc.clients.inventory.port=${INVENTORY_GRPC_PORT:9000}   (order-service)
#     quarkus.grpc.server.port=${INVENTORY_GRPC_PORT:9000}              (inventory-service)
# So a bare `java -jar inventory-service quarkus-run.jar` next to a bare
# `java -jar order-service quarkus-run.jar` connects with no override at
# all. This demo still pins INVENTORY_GRPC_PORT explicitly (kept at the
# canonical 9000 below) and passes it to the launched inventory-service
# process as `-Dquarkus.grpc.server.port=$INVENTORY_GRPC_PORT`, purely so
# both sides stay programmatically in agreement if this value is ever
# changed — no module source was touched.
#
# ── import.sql seed data never loads in packaged/%prod mode (found wiring
# this demo) — see the "seed deterministic stock" step below for the full
# explanation. Short version: %prod.quarkus.hibernate-orm.database.
# generation=update (the deprecated alias) wins over the unqualified
# schema-management.strategy=drop-and-create once "prod" is active, and
# Hibernate skips import.sql under "update" — so this demo seeds WIDGET-1
# itself via POST /stock (StockResource's own documented demo/test
# convenience) instead of depending on import.sql.
#
# ── order.placed publish silently fails in packaged/%prod mode without an
# Avro security system property (found wiring this demo -- a real, previously
# undetected production-readiness gap, not just a demo-script wrinkle) ──────
# A packaged order-service boots and serves POST /orders fine (the publish
# is fire-and-forget -- OrderEventProducer's failure path only logs, see
# OrderResource.placeOrder's `.exceptionally(...)`), but EVERY order.placed
# publish throws, every time, confirmed via the process's own log:
#   java.lang.SecurityException: Forbidden capstone.order.v1.OrderPlaced!
#   This class is not trusted to be included in Avro schemas. You may
#   either use the system properties org.apache.avro.SERIALIZABLE_CLASSES
#   and org.apache.avro.SERIALIZABLE_PACKAGES ...
# This is Avro 1.12.x's ClassSecurityValidator (a real security hardening
# feature introduced upstream, not a Quarkus/Apicurio bug) -- it allow-lists
# which packages/classes may be instantiated via reflection during Avro
# (de)serialization, and nothing in this reactor trusts capstone.order.v1
# by default outside of a Quarkus-bootstrapped JVM (dev/test mode trusts it
# implicitly; a plain `java -jar` does not). _plans/decisions.md's DEF-002
# entry already names the exact same fix for the OTHER place this bites
# (OrderPlacedAvroWireIT's failsafe execution passes
# org.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1 as a plain JUnit
# system property for the identical reason). This demo applies the same
# fix as a JVM system property on the launched order-service process --
# no module source touched -- but this is worth flagging upstream: the
# packaged/production image has the SAME exposure and would silently drop
# every order.placed event in a real deployment unless this property (or an
# equivalent JAVA_TOOL_OPTIONS/JVM arg) is set wherever the image runs.
#
# ── Port plan (deliberately avoiding compose's host-published ports:
# 5432/9092/9094/8081/3000/4317/4318/9090/3100/3200 — .env.example) ───────
#   order-service      HTTP 8091
#   inventory-service  HTTP 8092, gRPC 9000 (canonical default, see above)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-order"
require curl jq docker mvn java

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
# Avro 1.12.x's ClassSecurityValidator -- see header comment below.
AVRO_SERIALIZABLE_PACKAGES="capstone.order.v1"

narrate "Panache + REST data product: POST /orders checks stock over gRPC,"
narrate "persists the Order with Hibernate ORM Panache against the compose"
narrate "Postgres, and GET /orders/{id} round-trips the exact row back."

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

step "preflight: compose Postgres reachable"
for (( i = 0; i < 30; i++ )); do
    docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 && break
    sleep 1
done
docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 \
    || fail "compose Postgres (orderdb) did not become ready within 30s"
info "compose Postgres is ready (orderdb, inventorydb)"

# ─── Build both services (idempotent) ───────────────────────────────────────
step "build order-service + inventory-service (mvn -DskipTests package)"
( cd "$ORDER_DIR" && mvn -q -DskipTests package ) \
    || fail "mvn package failed for order-service"
[[ -f "${ORDER_DIR}/target/quarkus-app/quarkus-run.jar" ]] \
    || fail "order-service build did not produce target/quarkus-app/quarkus-run.jar"
( cd "$INVENTORY_DIR" && mvn -q -DskipTests package ) \
    || fail "mvn package failed for inventory-service"
[[ -f "${INVENTORY_DIR}/target/quarkus-app/quarkus-run.jar" ]] \
    || fail "inventory-service build did not produce target/quarkus-app/quarkus-run.jar"

# ─── Start inventory-service (packaged, %prod, against compose Postgres) ───
step "start inventory-service (HTTP ${INVENTORY_PORT}, gRPC ${INVENTORY_GRPC_PORT})"
INV_PIDFILE="$(mktemp -t demo-order-inv-pid-XXXXXX)"
INV_LOGFILE="$(mktemp -t demo-order-inv-log-XXXXXX)"
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
assert_http_200 "${INVENTORY_BASE}/q/health/live"
info "inventory-service is up"

# Seed deterministic stock via the REST demo surface (StockResource.seed is
# an idempotent upsert, explicitly documented as "a convenience for
# demos/tests") rather than relying on import.sql's dev/test-only seed rows.
# FOUND wiring this demo: in packaged/%prod mode, inventory-service's
# effective Hibernate schema-generation action resolves to "update", not
# the "drop-and-create" its own (non-profiled)
# quarkus.hibernate-orm.schema-management.strategy=drop-and-create implies —
# because %prod.quarkus.hibernate-orm.database.generation=${DB_GENERATION:
# update} (the deprecated alias for the same underlying Hibernate setting)
# wins once the "prod" profile is active (confirmed empirically: Hibernate's
# own startup debug log shows `jakarta.persistence.schema-generation.
# database.action=update` and `hibernate.hbm2ddl.skip_default_import_file=
# true` on a packaged run). Hibernate does not run `import.sql` under
# "update", so WIDGET-1/WIDGET-2/GADGET-1 never get seeded against the
# compose Postgres in packaged mode -- only in dev/test. No module source
# was touched for this: POST /stock already exists for exactly this case,
# so the demo seeds its own deterministic stock instead.
step "seed deterministic stock via REST (idempotent upsert)"
curl -fsS --max-time 10 -X POST "${INVENTORY_BASE}/stock" \
    -H 'Content-Type: application/json' \
    -d '{"sku":"WIDGET-1","quantityOnHand":50,"available":true}' >/dev/null \
    || fail "seeding WIDGET-1 via POST /stock failed"
STOCK_JSON="$(curl -fsS --max-time 10 "${INVENTORY_BASE}/stock/WIDGET-1")" \
    || fail "GET ${INVENTORY_BASE}/stock/WIDGET-1 failed right after seeding it"
assert_json_field "$STOCK_JSON" '.sku' 'WIDGET-1'
assert_json_field "$STOCK_JSON" '.available' 'true'
info "confirmed seed stock: $STOCK_JSON"

# ─── Start order-service (packaged, %prod, against compose Postgres/Kafka) ──
step "start order-service (HTTP ${ORDER_PORT})"
ORD_PIDFILE="$(mktemp -t demo-order-ord-pid-XXXXXX)"
ORD_LOGFILE="$(mktemp -t demo-order-ord-log-XXXXXX)"
info "log: $ORD_LOGFILE"
( cd "$ORDER_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/orderdb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
    APICURIO_REGISTRY_URL="http://localhost:${APICURIO_PORT}/apis/registry/v3" \
    java -Dquarkus.http.port="$ORDER_PORT" \
        -Dorg.apache.avro.SERIALIZABLE_PACKAGES="$AVRO_SERIALIZABLE_PACKAGES" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$ORD_LOGFILE" 2>&1 &
echo "$!" > "$ORD_PIDFILE"
SVC_PIDFILES+=("$ORD_PIDFILE")

wait_http "${ORDER_BASE}/q/health/live" 60 \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "order-service did not become healthy within 60s -- see $ORD_LOGFILE"; }
assert_http_200 "${ORDER_BASE}/q/health/live"
info "order-service is up"

# ─── Exercise the data product ───────────────────────────────────────────────
step "POST /orders (WIDGET-1 x2, customer cust-demo-order)"
CUSTOMER_ID="cust-demo-order-$$"
CREATE_PAYLOAD='{"customerId":"'"$CUSTOMER_ID"'","itemSku":"WIDGET-1","quantity":2,"amount":59.98}'
CREATE_RESP="$(curl -sS --max-time 15 -w '\n%{http_code}' -X POST "${ORDER_BASE}/orders" \
    -H 'Content-Type: application/json' -d "$CREATE_PAYLOAD")"
CREATE_BODY="$(head -n -1 <<<"$CREATE_RESP")"
CREATE_CODE="$(tail -n1 <<<"$CREATE_RESP")"
info "response ($CREATE_CODE): $CREATE_BODY"
[[ "$CREATE_CODE" == "201" ]] \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "expected HTTP 201 from POST /orders, got $CREATE_CODE (body: $CREATE_BODY)"; }

ORDER_ID="$(jq -r '.orderId' <<<"$CREATE_BODY")"
[[ -n "$ORDER_ID" && "$ORDER_ID" != "null" ]] \
    || fail "POST /orders response had no .orderId: $CREATE_BODY"
assert_json_field "$CREATE_BODY" '.customerId' "$CUSTOMER_ID"
assert_json_field "$CREATE_BODY" '.itemSku' 'WIDGET-1'
assert_json_field "$CREATE_BODY" '.quantity' '2'
assert_json_field "$CREATE_BODY" '.status' 'PLACED'
narrate "created order id=${ORDER_ID}"

step "GET /orders/${ORDER_ID} (Panache round trip through compose Postgres)"
FETCHED="$(curl -fsS --max-time 10 "${ORDER_BASE}/orders/${ORDER_ID}")" \
    || fail "GET ${ORDER_BASE}/orders/${ORDER_ID} failed"
info "response: $FETCHED"
assert_json_field "$FETCHED" '.orderId' "$ORDER_ID"
assert_json_field "$FETCHED" '.customerId' "$CUSTOMER_ID"
assert_json_field "$FETCHED" '.itemSku' 'WIDGET-1'
assert_json_field "$FETCHED" '.quantity' '2'
assert_json_field "$FETCHED" '.amount' '59.98'
assert_json_field "$FETCHED" '.status' 'PLACED'
narrate "GET echoed back exactly what POST wrote -- confirmed Panache persistence"

step "GET /orders list contains the new order"
LIST_JSON="$(curl -fsS --max-time 10 "${ORDER_BASE}/orders")" \
    || fail "GET ${ORDER_BASE}/orders failed"
jq -e --arg id "$ORDER_ID" 'any(.[]; .orderId == $id)' <<<"$LIST_JSON" >/dev/null \
    || fail "GET /orders list did not contain order ${ORDER_ID}: $LIST_JSON"
info "confirmed: /orders list contains ${ORDER_ID}"

step "direct Postgres row check (bypass the REST layer entirely)"
ROW_COUNT="$(docker exec datamesh-postgres psql -U "${POSTGRES_USER:-appuser}" -d orderdb -tAc \
    "SELECT count(*) FROM orders WHERE id = '${ORDER_ID}' AND customer_id = '${CUSTOMER_ID}' AND status = 'PLACED';" \
    2>/dev/null | tr -d '[:space:]')"
[[ "$ROW_COUNT" == "1" ]] \
    || fail "expected exactly 1 matching row in orders for id=${ORDER_ID}, found '${ROW_COUNT}'"
narrate "confirmed: 1 row in Postgres orders table for id=${ORDER_ID} (direct psql query, not via REST)"

demo_ok
