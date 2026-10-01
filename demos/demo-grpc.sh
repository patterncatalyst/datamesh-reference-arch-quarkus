#!/usr/bin/env bash
#
# demos/demo-grpc.sh — Phase D step 10.6 "compose (infra baseline)" demo:
# Quarkus gRPC (quarkus-grpc).
#
# inventory-service exposes capstone.inventory.v1.InventoryService/CheckStock
# (see contracts/src/main/proto/capstone/inventory/v1/inventory.proto and
# InventoryGrpcService) -- the first real cross-service call in the mesh
# (order-service dials this same RPC before placing an order; see
# demo-order.sh). This demo talks to it DIRECTLY with grpcurl -- a real gRPC
# client issuing a real unary RPC over HTTP/2 -- not through order-service's
# REST facade, so there is no ambiguity about which protocol is actually
# being exercised.
#
# ── Why grpcurl, not just "REST worked so gRPC must be fine" ───────────────
# grpcurl -plaintext against the server's reflection service lists
# capstone.inventory.v1.InventoryService (proof Quarkus gRPC's reflection
# support is live), then invokes CheckStock with a real protobuf request and
# parses the real protobuf-over-JSON response. If this were secretly REST
# under the hood, reflection listing a gRPC *service* (not a path) and a
# `grpcurl ... CheckStock` unary call would both fail outright.
#
# ── Port plan (avoiding compose's host-published ports — see .env.example) ──
#   inventory-service  HTTP 8093, gRPC 9000 (module default -- no override
#                       needed for this standalone test; see demo-order.sh's
#                       header comment for the 9000-vs-9001 port mismatch
#                       this demo deliberately sidesteps by not needing
#                       order-service at all).
#
# ── gRPC reflection is OFF by default outside dev mode (found wiring this
# demo) ──────────────────────────────────────────────────────────────────
# `quarkus.grpc.server.enable-reflection-service` defaults to true only in
# dev/test; a packaged %prod run (confirmed empirically: `grpcurl list`
# against an unmodified inventory-service packaged jar fails with "server
# does not support the reflection API") needs it explicitly enabled. This
# demo passes `-Dquarkus.grpc.server.enable-reflection-service=true` on the
# launched process (a runtime config override, not a module source change)
# purely so grpcurl's `list`/`describe` reflection calls below have
# something to talk to; the `CheckStock` RPC calls themselves don't need it.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-grpc"
require curl jq docker mvn java grpcurl

INVENTORY_DIR="${EXAMPLES_DIR}/inventory-service"
INVENTORY_PORT=8093
INVENTORY_GRPC_PORT=9000
INVENTORY_BASE="http://localhost:${INVENTORY_PORT}"
GRPC_ADDR="localhost:${INVENTORY_GRPC_PORT}"

POSTGRES_PORT="${POSTGRES_PORT:-5432}"

narrate "quarkus-grpc: a real gRPC client (grpcurl) calls"
narrate "capstone.inventory.v1.InventoryService/CheckStock over HTTP/2 against"
narrate "inventory-service -- not REST, not a mock."

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

INV_PIDFILE=""
_cleanup() {
    local rc=$?
    [[ -n "$INV_PIDFILE" ]] && svc_stop "$INV_PIDFILE" 2>/dev/null || true
    compose_down 2>/dev/null || true
    return "$rc"
}
trap '_cleanup; _demo_exit_trap' EXIT

step "preflight: compose Postgres (inventorydb) reachable"
for (( i = 0; i < 30; i++ )); do
    docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d inventorydb >/dev/null 2>&1 && break
    sleep 1
done
docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d inventorydb >/dev/null 2>&1 \
    || fail "compose Postgres (inventorydb) did not become ready within 30s"

step "build inventory-service (mvn -DskipTests package)"
( cd "$INVENTORY_DIR" && mvn -q -DskipTests package ) \
    || fail "mvn package failed for inventory-service"
[[ -f "${INVENTORY_DIR}/target/quarkus-app/quarkus-run.jar" ]] \
    || fail "inventory-service build did not produce target/quarkus-app/quarkus-run.jar"

step "start inventory-service (HTTP ${INVENTORY_PORT}, gRPC ${INVENTORY_GRPC_PORT})"
INV_PIDFILE="$(mktemp -t demo-grpc-inv-pid-XXXXXX)"
INV_LOGFILE="$(mktemp -t demo-grpc-inv-log-XXXXXX)"
info "log: $INV_LOGFILE"
( cd "$INVENTORY_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/inventorydb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    java -Dquarkus.http.port="$INVENTORY_PORT" \
        -Dquarkus.grpc.server.enable-reflection-service=true \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$INV_LOGFILE" 2>&1 &
echo "$!" > "$INV_PIDFILE"

wait_http "${INVENTORY_BASE}/q/health/live" 60 \
    || { tail -n 60 "$INV_LOGFILE" >&2; fail "inventory-service did not become healthy within 60s -- see $INV_LOGFILE"; }
assert_http_200 "${INVENTORY_BASE}/q/health/live"
info "inventory-service is up"

# Re-seed deterministic stock levels for this run via the REST demo surface
# (idempotent upsert — StockResource.seed) rather than relying solely on
# import.sql's defaults, so the gRPC assertions below are self-contained.
step "seed deterministic stock via REST (idempotent upsert)"
curl -fsS --max-time 10 -X POST "${INVENTORY_BASE}/stock" \
    -H 'Content-Type: application/json' \
    -d '{"sku":"GRPC-DEMO-SKU","quantityOnHand":42,"available":true}' >/dev/null \
    || fail "seeding GRPC-DEMO-SKU via POST /stock failed"
info "seeded GRPC-DEMO-SKU with 42 on hand"

for (( i = 0; i < 30; i++ )); do
    grpcurl -plaintext -connect-timeout 2 "$GRPC_ADDR" list >/dev/null 2>&1 && break
    sleep 1
done

# ─── Prove it's really gRPC: server reflection lists the service ───────────
step "grpcurl list -- server reflection"
SERVICES="$(grpcurl -plaintext "$GRPC_ADDR" list 2>&1)" \
    || { tail -n 60 "$INV_LOGFILE" >&2; fail "grpcurl list failed against ${GRPC_ADDR} -- is gRPC reflection enabled? output: $SERVICES"; }
info "services: $SERVICES"
grep -q 'capstone.inventory.v1.InventoryService' <<<"$SERVICES" \
    || fail "grpcurl list did not include capstone.inventory.v1.InventoryService: $SERVICES"
narrate "confirmed via reflection: capstone.inventory.v1.InventoryService is live on ${GRPC_ADDR}"

step "grpcurl describe -- method signature"
METHOD_DESC="$(grpcurl -plaintext "$GRPC_ADDR" describe capstone.inventory.v1.InventoryService.CheckStock 2>&1)" \
    || fail "grpcurl describe CheckStock failed: $METHOD_DESC"
info "$METHOD_DESC"
grep -q 'CheckStockRequest' <<<"$METHOD_DESC" || fail "CheckStock description missing CheckStockRequest: $METHOD_DESC"
grep -q 'CheckStockResponse' <<<"$METHOD_DESC" || fail "CheckStock description missing CheckStockResponse: $METHOD_DESC"

# ─── Real unary RPC calls, parsed responses ─────────────────────────────────
step "grpcurl CheckStock -- in-stock SKU (available=true)"
RESP1="$(grpcurl -plaintext -emit-defaults -d '{"sku":"GRPC-DEMO-SKU","quantity":10}' \
    "$GRPC_ADDR" capstone.inventory.v1.InventoryService/CheckStock 2>&1)" \
    || fail "grpcurl CheckStock call failed: $RESP1"
info "response: $RESP1"
assert_json_field "$RESP1" '.available' 'true'
assert_json_field "$RESP1" '.quantity_on_hand' '42'
narrate "confirmed: CheckStock(GRPC-DEMO-SKU, 10) -> available=true, quantityOnHand=42"

step "grpcurl CheckStock -- quantity exceeds stock (available=false)"
RESP2="$(grpcurl -plaintext -emit-defaults -d '{"sku":"GRPC-DEMO-SKU","quantity":999}' \
    "$GRPC_ADDR" capstone.inventory.v1.InventoryService/CheckStock 2>&1)" \
    || fail "grpcurl CheckStock call failed: $RESP2"
info "response: $RESP2"
assert_json_field "$RESP2" '.available' 'false'
assert_json_field "$RESP2" '.quantity_on_hand' '42'
narrate "confirmed: CheckStock(GRPC-DEMO-SKU, 999) -> available=false (still reports quantityOnHand=42)"

step "grpcurl CheckStock -- unknown SKU (zero on hand)"
RESP3="$(grpcurl -plaintext -emit-defaults -d '{"sku":"NO-SUCH-SKU","quantity":1}' \
    "$GRPC_ADDR" capstone.inventory.v1.InventoryService/CheckStock 2>&1)" \
    || fail "grpcurl CheckStock call failed: $RESP3"
info "response: $RESP3"
assert_json_field "$RESP3" '.available' 'false'
QOH3="$(jq -r '.quantity_on_hand // 0' <<<"$RESP3")"
[[ "$QOH3" == "0" ]] || fail "expected quantityOnHand=0 for an unknown SKU, got '$QOH3' (json: $RESP3)"
narrate "confirmed: CheckStock(NO-SUCH-SKU, 1) -> available=false, quantityOnHand=0"

demo_ok
