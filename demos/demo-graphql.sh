#!/usr/bin/env bash
#
# demos/demo-graphql.sh — Phase D step 10.6 "compose (infra baseline)" demo:
# SmallRye GraphQL gateway.
#
# graphql-gateway federates two downstream protocols behind one /graphql
# endpoint (GatewayApi): `order(id)` resolves an order over REST from
# order-service, and the nested `stock` field on that order resolves over
# gRPC from inventory-service -- one client query, two backing protocols,
# with the gRPC call made ONLY if the client actually selects `stock`
# (standard MicroProfile GraphQL @Source behavior).
#
# Flow: place a real order via order-service's REST data product (reusing
# the same Panache round trip demo-order.sh proves), then issue ONE GraphQL
# query to the gateway that fans out to both order-service (REST) and
# inventory-service (gRPC) and assert the stitched response -- order fields
# AND nested stock fields, all in a single parsed `.data.order` payload, with
# no `.errors`. A second, negative-control query for an unknown order id
# documents a real GatewayApi 404-handling gotcha found while wiring this
# demo -- see the comment right above that step, near the end of this file.
#
# ── Port plan (avoiding compose's host-published ports — see .env.example,
# notably APICURIO_PORT=8081, which rules out order-service's own default
# dev port of 8081) ──────────────────────────────────────────────────────
#   order-service      HTTP 8091 (graphql-gateway's ORDER_SERVICE_URL env
#                       var is overridden to point here -- its own default,
#                       localhost:8081, collides with compose's Apicurio
#                       host port).
#   inventory-service  HTTP 8092, gRPC 9001 (override -- see below).
#   graphql-gateway    HTTP 8080 (module default), INVENTORY_GRPC_PORT=9001
#                       override env var.
#
# ── The inventory gRPC port mismatch (found wiring this demo, same root
# cause as demo-order.sh/demo-kafka.sh) ─────────────────────────────────────
# order-service's gRPC CLIENT port is hardcoded, NOT profile- or
# env-gated: `quarkus.grpc.clients.inventory.port=9001`. inventory-service's
# gRPC SERVER port default is 9000, and graphql-gateway's own gRPC client
# default (`INVENTORY_GRPC_PORT:9000`) matches THAT default -- but NOT
# order-service's hardcoded 9001. Confirmed empirically: with
# inventory-service left at its default 9000, order-service's POST /orders
# failed with "503 inventory-service unreachable: UNAVAILABLE: io
# exception" because it dialed :9001 where nothing was listening. This demo
# runs inventory-service's gRPC server at 9001 (matching order-service's
# hardcoded expectation) and overrides graphql-gateway's INVENTORY_GRPC_PORT
# to 9001 too, so both callers agree -- a runtime config override on both
# launched processes, no module source touched.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-graphql"
require curl jq docker mvn java

ORDER_DIR="${EXAMPLES_DIR}/order-service"
INVENTORY_DIR="${EXAMPLES_DIR}/inventory-service"
GATEWAY_DIR="${EXAMPLES_DIR}/graphql-gateway"

ORDER_PORT=8091
INVENTORY_PORT=8092
INVENTORY_GRPC_PORT=9001
GATEWAY_PORT=8080

ORDER_BASE="http://localhost:${ORDER_PORT}"
INVENTORY_BASE="http://localhost:${INVENTORY_PORT}"
GATEWAY_BASE="http://localhost:${GATEWAY_PORT}"

POSTGRES_PORT="${POSTGRES_PORT:-5432}"
KAFKA_HOST_PORT="${KAFKA_HOST_PORT:-9092}"
APICURIO_PORT="${APICURIO_PORT:-8081}"
# Avro 1.12.x's ClassSecurityValidator rejects capstone.order.v1.OrderPlaced
# outside a Quarkus-bootstrapped JVM unless explicitly trusted -- see
# demo-order.sh's header comment for the full empirical trace (confirmed via
# a SecurityException in order-service's own log on every order.placed
# publish attempt without this). Not required for THIS demo's assertions
# (the GraphQL query only reads order-service's REST surface + inventory's
# gRPC), but set anyway so order-service's Kafka publish attempts don't
# silently fail in its log for no reason.
AVRO_SERIALIZABLE_PACKAGES="capstone.order.v1"

narrate "SmallRye GraphQL gateway: one POST /graphql query stitches an order"
narrate "(fetched over REST from order-service) with its live stock (fetched"
narrate "over gRPC from inventory-service) into a single response."

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

# ─── Build all three services (idempotent) ──────────────────────────────────
step "build order-service, inventory-service, graphql-gateway"
for mod in "$ORDER_DIR" "$INVENTORY_DIR" "$GATEWAY_DIR"; do
    ( cd "$mod" && mvn -q -DskipTests package ) \
        || fail "mvn package failed for $(basename "$mod")"
    [[ -f "${mod}/target/quarkus-app/quarkus-run.jar" ]] \
        || fail "$(basename "$mod") build did not produce target/quarkus-app/quarkus-run.jar"
done

# ─── Start inventory-service ─────────────────────────────────────────────────
step "start inventory-service (HTTP ${INVENTORY_PORT}, gRPC ${INVENTORY_GRPC_PORT})"
INV_PIDFILE="$(mktemp -t demo-gql-inv-pid-XXXXXX)"
INV_LOGFILE="$(mktemp -t demo-gql-inv-log-XXXXXX)"
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
    -d '{"sku":"WIDGET-2","quantityOnHand":12,"available":true}' >/dev/null \
    || fail "seeding WIDGET-2 via POST /stock failed"

# ─── Start order-service ─────────────────────────────────────────────────────
step "start order-service (HTTP ${ORDER_PORT})"
ORD_PIDFILE="$(mktemp -t demo-gql-ord-pid-XXXXXX)"
ORD_LOGFILE="$(mktemp -t demo-gql-ord-log-XXXXXX)"
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
info "order-service is up"

# ─── Start graphql-gateway (ORDER_SERVICE_URL override -- see header) ───────
step "start graphql-gateway (HTTP ${GATEWAY_PORT})"
GW_PIDFILE="$(mktemp -t demo-gql-gw-pid-XXXXXX)"
GW_LOGFILE="$(mktemp -t demo-gql-gw-log-XXXXXX)"
info "log: $GW_LOGFILE"
( cd "$GATEWAY_DIR" && exec env \
    TZ=UTC \
    ORDER_SERVICE_URL="${ORDER_BASE}" \
    INVENTORY_GRPC_HOST=localhost \
    INVENTORY_GRPC_PORT="$INVENTORY_GRPC_PORT" \
    java -Dquarkus.http.port="$GATEWAY_PORT" -jar target/quarkus-app/quarkus-run.jar \
) >"$GW_LOGFILE" 2>&1 &
echo "$!" > "$GW_PIDFILE"
SVC_PIDFILES+=("$GW_PIDFILE")
wait_http "${GATEWAY_BASE}/q/health/live" 60 \
    || { tail -n 60 "$GW_LOGFILE" >&2; fail "graphql-gateway did not become healthy within 60s -- see $GW_LOGFILE"; }
info "graphql-gateway is up"

# ─── Seed an order via order-service REST ───────────────────────────────────
step "POST /orders (WIDGET-2 x1) via order-service REST"
CUSTOMER_ID="cust-demo-graphql-$$"
CREATE_RESP="$(curl -sS --max-time 15 -w '\n%{http_code}' -X POST "${ORDER_BASE}/orders" \
    -H 'Content-Type: application/json' \
    -d '{"customerId":"'"$CUSTOMER_ID"'","itemSku":"WIDGET-2","quantity":1,"amount":9.99}')"
CREATE_BODY="$(head -n -1 <<<"$CREATE_RESP")"
CREATE_CODE="$(tail -n1 <<<"$CREATE_RESP")"
[[ "$CREATE_CODE" == "201" ]] \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "expected HTTP 201 from POST /orders, got $CREATE_CODE (body: $CREATE_BODY)"; }
ORDER_ID="$(jq -r '.orderId' <<<"$CREATE_BODY")"
[[ -n "$ORDER_ID" && "$ORDER_ID" != "null" ]] || fail "POST /orders response had no .orderId: $CREATE_BODY"
narrate "seed order id=${ORDER_ID}"

# ─── Query the gateway: one query, two protocols stitched ──────────────────
step "POST /graphql -- order(id) { ... stock { ... } }"
GQL_QUERY=$(jq -n --arg id "$ORDER_ID" \
    '{query: ("{ order(id: \"" + $id + "\") { id customerId itemSku quantity status stock { sku quantityOnHand available } } }")}')
GQL_RESP="$(curl -fsS --max-time 15 -X POST "${GATEWAY_BASE}/graphql" \
    -H 'Content-Type: application/json' \
    -d "$GQL_QUERY")" \
    || { tail -n 60 "$GW_LOGFILE" >&2; fail "POST ${GATEWAY_BASE}/graphql failed"; }
info "response: $GQL_RESP"

# Positive-content assertion: NO .errors array, and every stitched field
# parses to the expected value -- never just "exit 0" / "got 200".
ERRORS="$(jq -r 'if has("errors") then (.errors | length) else 0 end' <<<"$GQL_RESP")"
[[ "$ERRORS" == "0" ]] \
    || fail "GraphQL response carried ${ERRORS} error(s), expected none: $(jq -c '.errors' <<<"$GQL_RESP")"

assert_json_field "$GQL_RESP" '.data.order.id' "$ORDER_ID"
assert_json_field "$GQL_RESP" '.data.order.customerId' "$CUSTOMER_ID"
assert_json_field "$GQL_RESP" '.data.order.itemSku' 'WIDGET-2'
assert_json_field "$GQL_RESP" '.data.order.quantity' '1'
assert_json_field "$GQL_RESP" '.data.order.status' 'PLACED'

# The nested `stock` object proves the SECOND protocol (gRPC to
# inventory-service) actually fired for this query -- GatewayApi.stock()
# is only invoked when a client selects the field.
STOCK_SKU="$(jq -r '.data.order.stock.sku' <<<"$GQL_RESP")"
[[ "$STOCK_SKU" == "WIDGET-2" ]] || fail "expected .data.order.stock.sku == WIDGET-2, got '$STOCK_SKU'"
STOCK_AVAILABLE="$(jq -r '.data.order.stock.available' <<<"$GQL_RESP")"
[[ "$STOCK_AVAILABLE" == "true" ]] || fail "expected .data.order.stock.available == true, got '$STOCK_AVAILABLE'"
STOCK_QOH="$(jq -r '.data.order.stock.quantityOnHand' <<<"$GQL_RESP")"
[[ "$STOCK_QOH" =~ ^[0-9]+$ ]] || fail "expected .data.order.stock.quantityOnHand to be a number, got '$STOCK_QOH'"

narrate "confirmed: one GraphQL query fanned out to order-service (REST) AND"
narrate "inventory-service (gRPC) and returned both halves, error-free:"
narrate "order ${ORDER_ID} (WIDGET-2) with live stock quantityOnHand=${STOCK_QOH} available=${STOCK_AVAILABLE}"

# Negative control: unknown order id. GatewayApi.order() used to have an
# `if (response.getStatus() == NOT_FOUND) return null` branch, but that
# branch was unreachable dead code (confirmed empirically, with
# quarkus.smallrye-graphql.show-runtime-exception-message enabled for a
# one-off debug run): Quarkus's MP REST Client still throws a
# WebApplicationException ("Received: 'Not Found, status code 404' ...") for
# ANY non-2xx response even when the method return type is Response. The
# dead branch has since been removed (see OrderRestClient's Javadoc).
# SmallRye GraphQL catches that exception at the field resolver level and
# nulls out the (nullable) `order` field while ALSO reporting a
# DataFetchingException in `.errors` -- so the client-visible end result
# (`.data.order == null`) is reached via error recovery, not a clean
# return. This demo asserts what ACTUALLY happens (null data + a reported
# error).
step "negative control: unknown order id -- .data.order is null (see note above)"
GQL_NULL_QUERY='{"query":"{ order(id: \"does-not-exist\") { id } }"}'
GQL_NULL_RESP="$(curl -fsS --max-time 15 -X POST "${GATEWAY_BASE}/graphql" \
    -H 'Content-Type: application/json' -d "$GQL_NULL_QUERY")" \
    || fail "POST ${GATEWAY_BASE}/graphql (null case) failed"
info "response: $GQL_NULL_RESP"
assert_json_field "$GQL_NULL_RESP" '.data.order' 'null'
assert_json_field "$GQL_NULL_RESP" '.errors[0].extensions.classification' 'DataFetchingException'
narrate "confirmed: unknown order id -> .data.order is null (via a reported"
narrate "DataFetchingException, not a clean 404-to-null branch -- the dead"
narrate "branch in GatewayApi.order() has been removed)"

demo_ok
