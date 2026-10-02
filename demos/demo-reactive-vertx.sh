#!/usr/bin/env bash
#
# demos/demo-reactive-vertx.sh — "compose (infra baseline)"
# demo: Vert.x unified reactive + imperative, inside ONE Quarkus app
# (inventory-service).
#
# inventory-service exposes the SAME stock data through two execution
# models on the SAME Vert.x reactor, in the SAME JVM:
#   - REACTIVE: InventoryGrpcService.checkStock(...) implements the
#     Mutiny-typed `InventoryService` gRPC stub Quarkus generates from
#     contracts/.../inventory.proto — its public API is `Uni<CheckStockResponse>`,
#     the textbook reactive shape, even though the handler body is annotated
#     `@Blocking` (it does a Panache/JDBC lookup) so Vert.x offloads it to a
#     worker thread instead of ever parking the event loop. This IS exactly
#     Quarkus/Vert.x's "unified reactive + imperative" story: a reactive
#     (Uni) contract at the edge, blocking work safely delegated underneath,
#     all on one reactor.
#   - IMPERATIVE: StockResource (classic JAX-RS + Hibernate ORM Panache,
#     thread-per-request, no Uni/Multi anywhere) answers the exact same
#     `stock` table on the exact same running instance.
#
# This demo proves BOTH independently (distinct, request-dependent computed
# fields — see below) AND proves they coexist correctly under CONCURRENT
# load: it fires gRPC (reactive) and REST (imperative) calls at the SAME
# TIME against the one running inventory-service process and asserts every
# response is individually correct — no cross-talk, no blocking-each-other
# failure, non-blocking I/O and classic imperative code sharing one app.
#
# ── Why CheckStock's gRPC answer and the REST GET /stock/{sku} answer are
# NOT the same computation (the point of running both, not just one) ───────
# REST's `available` is a static snapshot: `quantityOnHand > 0`. The gRPC
# path's `available` is REQUEST-DEPENDENT: `quantity > 0 && onHand >=
# quantity` (see InventoryGrpcService.checkStock) — asking for more than is
# on hand returns `available=false` over gRPC even though REST still reports
# the SKU as "available" (nonzero stock). This demo's WIDGET-2 case (3 on
# hand) asserts exactly that divergence: REST says available=true,
# qty=3; gRPC asked for 100 says available=false, qty=3 — proving the
# gRPC path is a real, independently-computed reactive endpoint, not just a
# thin pass-through of the same REST logic.
#
# ── Why grpcurl with -proto (not server reflection) ─────────────────────────
# Quarkus's dev-mode gRPC server happens to answer `grpcurl list` via
# reflection (confirmed empirically), but that's a dev-mode convenience, not
# a guaranteed contract — this demo instead points grpcurl straight at the
# real .proto the service was generated from
# (contracts/src/main/proto/capstone/inventory/v1/inventory.proto), the same
# source of truth order-service's own generated gRPC client uses, so the
# demo doesn't depend on reflection being enabled.
#
# ── Why `mvn quarkus:dev` + Dev Services, not the compose stack ────────────
# This demo only exercises ONE service's own internal reactive-vs-imperative
# duality — no cross-service call, no Kafka/Apicurio/Postgres-with-real-data
# dependency beyond what inventory-service already owns — so Dev Services
# (its own ephemeral Postgres Testcontainer, zero compose/.env) is the
# simpler, faster path, per this step's general prod-readiness guidance.
# Same postgres:18 timezone gotcha as demo-continuous-testing.sh/demo-native.sh
# applies (TZ=UTC exported on the mvn process).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-reactive-vertx"
require curl jq mvn java docker grpcurl

MODULE_DIR="${EXAMPLES_DIR}/inventory-service"
PROTO_DIR="${EXAMPLES_DIR}/contracts/src/main/proto"
PROTO_FILE="capstone/inventory/v1/inventory.proto"
[[ -f "${PROTO_DIR}/${PROTO_FILE}" ]] \
    || fail "expected proto file not found: ${PROTO_DIR}/${PROTO_FILE}"

HTTP_PORT=8095
GRPC_PORT=9000
BASE_URL="http://localhost:${HTTP_PORT}"
GRPC_ADDR="localhost:${GRPC_PORT}"

narrate "inventory-service exposes one 'stock' table through two execution"
narrate "models on the same Vert.x reactor: a reactive Mutiny Uni<...> gRPC"
narrate "endpoint (InventoryGrpcService.checkStock) and a classic imperative"
narrate "JAX-RS+Panache REST endpoint (StockResource) -- this demo exercises"
narrate "both independently and concurrently against the same running process."

step "preflight: docker daemon reachable (Dev Services needs it)"
docker info >/dev/null 2>&1 \
    || fail "docker is on PATH but the daemon is not reachable -- start Docker Desktop/the docker service and retry (Dev Services needs a working docker to launch a Postgres Testcontainer)"
info "docker daemon is reachable"

# See header comment: postgres:18 (Dev Services' pinned image) rejects
# legacy Olson TZ ids like "US/Eastern" forwarded by pgjdbc from a non-UTC
# host -- same fix as demo-continuous-testing.sh/demo-native.sh.
export TZ=UTC

step "start inventory-service (mvn quarkus:dev, Dev Services Postgres, HTTP ${HTTP_PORT}, gRPC ${GRPC_PORT})"
PIDFILE="$(svc_start_dev "$MODULE_DIR" "$HTTP_PORT")"
trap 'svc_stop "'"$PIDFILE"'" 2>/dev/null || true; _demo_exit_trap' EXIT

wait_http "${BASE_URL}/q/health/live" 90 \
    || fail "inventory-service dev mode did not answer HTTP within 90s"
assert_http_200 "${BASE_URL}/q/health/live"
info "inventory-service is up (dev mode, Dev Services Postgres)"

step "seed deterministic stock via the imperative REST surface (idempotent upsert)"
curl -fsS --max-time 10 -X POST "${BASE_URL}/stock" -H 'Content-Type: application/json' \
    -d '{"sku":"WIDGET-1","quantityOnHand":50,"available":true}' >/dev/null \
    || fail "seeding WIDGET-1 failed"
curl -fsS --max-time 10 -X POST "${BASE_URL}/stock" -H 'Content-Type: application/json' \
    -d '{"sku":"WIDGET-2","quantityOnHand":3,"available":true}' >/dev/null \
    || fail "seeding WIDGET-2 failed"
curl -fsS --max-time 10 -X POST "${BASE_URL}/stock" -H 'Content-Type: application/json' \
    -d '{"sku":"GADGET-1","quantityOnHand":0,"available":false}' >/dev/null \
    || fail "seeding GADGET-1 failed"
info "seeded WIDGET-1=50, WIDGET-2=3, GADGET-1=0"

grpc_check_stock() {
    # grpc_check_stock <sku> <quantity> -- calls the REACTIVE Mutiny
    # Uni<CheckStockResponse> gRPC endpoint via grpcurl against the real
    # .proto (no reflection dependency). Prints the JSON response (proto3
    # omits default-valued fields, so a false `available`/0 `quantityOnHand`
    # may be entirely absent from the output -- callers parse with `// false`
    # / `// 0` defaults, same idiom as a sparse JSON API).
    local sku="$1" qty="$2"
    grpcurl -plaintext -import-path "$PROTO_DIR" -proto "$PROTO_FILE" \
        -d '{"sku":"'"$sku"'","quantity":'"$qty"'}' \
        "$GRPC_ADDR" capstone.inventory.v1.InventoryService/CheckStock
}

# ─── Part 1: reactive and imperative paths compute DIFFERENT answers ───────
step "Reactive gRPC CheckStock (Mutiny Uni<CheckStockResponse>) -- sufficient stock"
G1="$(grpc_check_stock WIDGET-1 10)" || fail "gRPC CheckStock(WIDGET-1, 10) failed"
info "CheckStock(WIDGET-1, qty=10): $G1"
assert_json_field "$G1" '.available // false' 'true'
assert_json_field "$G1" '.quantityOnHand // 0' '50'
narrate "confirmed: reactive gRPC endpoint reports WIDGET-1 available for a request of 10 (50 on hand)"

step "Reactive gRPC CheckStock -- insufficient stock (request > on-hand)"
G2="$(grpc_check_stock WIDGET-2 100)" || fail "gRPC CheckStock(WIDGET-2, 100) failed"
info "CheckStock(WIDGET-2, qty=100): $G2"
assert_json_field "$G2" '.available // false' 'false'
assert_json_field "$G2" '.quantityOnHand // 0' '3'
narrate "confirmed: reactive gRPC endpoint reports available=false when the request (100) exceeds on-hand (3)"

step "Imperative REST GET /stock/WIDGET-2 -- the same row, the other (static) availability rule"
R2="$(curl -fsS --max-time 10 "${BASE_URL}/stock/WIDGET-2")" || fail "GET /stock/WIDGET-2 failed"
info "GET /stock/WIDGET-2: $R2"
assert_json_field "$R2" '.sku' 'WIDGET-2'
assert_json_field "$R2" '.available' 'true'
assert_json_field "$R2" '.quantityOnHand' '3'
narrate "confirmed: REST's static snapshot (available = qty>0) says WIDGET-2 is available, while the"
narrate "reactive gRPC path just said available=false for a request of 100 -- two real, independently"
narrate "computed answers against the same row, from two different execution models in one app"

# ─── Part 2: concurrent reactive + imperative traffic, same process ───────
step "fire 3 reactive gRPC calls + 3 imperative REST calls concurrently, assert each is correct"
CONC_DIR="$(mktemp -d -t demo-reactive-vertx-conc-XXXXXX)"
CONC_START=$(date +%s%N)

( grpc_check_stock WIDGET-1 10  > "${CONC_DIR}/g-widget1.json"  2>"${CONC_DIR}/g-widget1.err" )  &
( grpc_check_stock WIDGET-2 100 > "${CONC_DIR}/g-widget2.json"  2>"${CONC_DIR}/g-widget2.err" )  &
( grpc_check_stock GADGET-1 1   > "${CONC_DIR}/g-gadget1.json"  2>"${CONC_DIR}/g-gadget1.err" )  &
( curl -fsS --max-time 10 "${BASE_URL}/stock/WIDGET-1" > "${CONC_DIR}/r-widget1.json" ) &
( curl -fsS --max-time 10 "${BASE_URL}/stock/WIDGET-2" > "${CONC_DIR}/r-widget2.json" ) &
( curl -fsS --max-time 10 "${BASE_URL}/stock"          > "${CONC_DIR}/r-list.json" )    &
wait
CONC_END=$(date +%s%N)
CONC_MS=$(( (CONC_END - CONC_START) / 1000000 ))
info "all 6 concurrent calls (3 reactive gRPC + 3 imperative REST) completed in ${CONC_MS}ms"

[[ -s "${CONC_DIR}/g-widget1.json" ]] || { cat "${CONC_DIR}/g-widget1.err" >&2; fail "concurrent gRPC call for WIDGET-1 produced no output"; }
assert_json_field "$(cat "${CONC_DIR}/g-widget1.json")" '.available // false' 'true'
assert_json_field "$(cat "${CONC_DIR}/g-widget1.json")" '.quantityOnHand // 0' '50'

[[ -s "${CONC_DIR}/g-widget2.json" ]] || { cat "${CONC_DIR}/g-widget2.err" >&2; fail "concurrent gRPC call for WIDGET-2 produced no output"; }
assert_json_field "$(cat "${CONC_DIR}/g-widget2.json")" '.available // false' 'false'
assert_json_field "$(cat "${CONC_DIR}/g-widget2.json")" '.quantityOnHand // 0' '3'

[[ -s "${CONC_DIR}/g-gadget1.json" ]] || { cat "${CONC_DIR}/g-gadget1.err" >&2; fail "concurrent gRPC call for GADGET-1 produced no output"; }
assert_json_field "$(cat "${CONC_DIR}/g-gadget1.json")" '.available // false' 'false'
assert_json_field "$(cat "${CONC_DIR}/g-gadget1.json")" '.quantityOnHand // 0' '0'

assert_json_field "$(cat "${CONC_DIR}/r-widget1.json")" '.sku' 'WIDGET-1'
assert_json_field "$(cat "${CONC_DIR}/r-widget1.json")" '.quantityOnHand' '50'
assert_json_field "$(cat "${CONC_DIR}/r-widget2.json")" '.sku' 'WIDGET-2'
assert_json_field "$(cat "${CONC_DIR}/r-widget2.json")" '.quantityOnHand' '3'

jq -e 'map(.sku) | sort == ["GADGET-1","WIDGET-1","WIDGET-2"]' "${CONC_DIR}/r-list.json" >/dev/null \
    || fail "concurrent REST list did not contain exactly the 3 seeded SKUs: $(cat "${CONC_DIR}/r-list.json")"

rm -rf "$CONC_DIR"
narrate "confirmed: 3 reactive (Mutiny gRPC) + 3 imperative (REST/Panache) calls run concurrently"
narrate "against the same inventory-service process each returned its own correct, uncorrupted"
narrate "result (${CONC_MS}ms wall clock for all 6) -- the unified Vert.x reactor serves both"
narrate "execution models side by side without them interfering with each other"

demo_ok
