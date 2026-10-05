#!/usr/bin/env bash
#
# demos/demo-tracing.sh — "compose (infra baseline)" demo:
# OpenTelemetry distributed tracing, proven against the real compose
# otel-lgtm stack's Tempo backend (LGTM observability is an always-on
# baseline — compose_up with no profile already brings it up).
#
# POST /orders on order-service calls inventory-service over gRPC
# (CheckStock), same cross-service hop demo-order.sh exercises for Panache —
# this demo rides the SAME request to prove it produces one real, queryable,
# multi-service trace: order-service's REST span is the trace root, and a
# CheckStock gRPC span plus Postgres spans from BOTH services are children
# of it, all stitched together by W3C trace-context propagation across the
# gRPC call. This demo queries Tempo's HTTP API (not application logs) for
# the proof: it finds the trace by service name, fetches it by id, and
# parses span count + the set of service.name values actually present.
#
# ── No module has quarkus-opentelemetry on its classpath (found wiring this
# demo) — zero-pom-touch path chosen instead ──────────────────────────────
# Neither order-service's nor inventory-service's pom.xml pulls in
# `quarkus-opentelemetry` (confirmed: grep for "opentelemetry" across every
# examples/*/pom.xml returns nothing), so no amount of `-D`/env config alone
# could turn on Quarkus's own OTel extension — it is a BUILD-time extension,
# not something a runtime flag can retrofit onto an already-packaged jar.
# Per this step's hard constraint (module source/pom edits are reserved for
# the websocket demo's one flagged addition), this demo does NOT add the
# extension to either module. Instead it attaches the upstream OpenTelemetry
# Java auto-instrumentation agent (a single `-javaagent:` JVM flag, zero
# source/pom changes, the same "runtime workaround over file edit" idiom
# demo-order.sh/demo-kafka.sh use for their Avro/gRPC-port fixes) to both
# packaged quarkus-run.jar processes. It auto-instruments JAX-RS/RESTEasy,
# the gRPC client AND server, and JDBC with zero code changes, and exports
# real OTLP spans to the compose otel-lgtm collector — confirmed empirically
# (see below) to produce an 11-span trace spanning both services for a
# single POST /orders.
#
# The agent jar is cached at ~/.cache/datamesh-demos/opentelemetry-javaagent.jar
# (NOT inside this repo — it's a large, independently-versioned binary, not
# project source) and downloaded once from the upstream GitHub release if
# missing. If the download fails (offline host), this demo fails loudly with
# the exact manual-download command rather than silently skipping tracing.
#
# ── Tempo API shape (confirmed empirically against otel-lgtm:0.8.1) ────────
# `GET /api/search?tags=service.name=<name>` returns `{"traces":[{"traceID":
# ...,"rootServiceName":...,"rootTraceName":...}, ...]}`, newest first.
# `GET /api/traces/<id>` returns the OTEL-COLLECTOR-INTERNAL "batches" shape
# (Jaeger-style: `.batches[].resource.attributes[]` for resource attributes
# incl. `service.name`, and `.batches[].scopeSpans[]?.spans[]` /
# `.batches[].instrumentationLibrarySpans[]?.spans[]` for the actual spans —
# NOT the OTLP-JSON `resourceSpans` shape some newer Tempo docs show; this
# otel-lgtm image's bundled Tempo answers with the older key names, verified
# live) — this demo parses both possible span-array keys defensively.
# `/ready` lags `/api/search` answering 200 by ~30-40s on a cold container
# (confirmed empirically) — this demo polls `/api/search` directly instead
# of gating on `/ready`.
#
# ── Port plan (same convention as demo-order.sh/demo-kafka.sh) ─────────────
#   order-service      HTTP 8091
#   inventory-service  HTTP 8092, gRPC 9000 (canonical default -- see
#                       demo-order.sh's header comment)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-tracing"
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
AVRO_SERIALIZABLE_PACKAGES="capstone.order.v1"

AGENT_CACHE_DIR="${HOME}/.cache/datamesh-demos"
AGENT_JAR="${AGENT_CACHE_DIR}/opentelemetry-javaagent.jar"
AGENT_URL="https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar"

narrate "OpenTelemetry distributed tracing: POST /orders crosses a real"
narrate "service boundary (order-service -> inventory-service gRPC CheckStock)."
narrate "This demo attaches the upstream OTel Java agent to both packaged"
narrate "services (zero source/pom changes) and queries Tempo's HTTP API in"
narrate "the compose otel-lgtm stack for a parsed, multi-service trace --"
narrate "not just 'the app logged something'."

# ─── OTel Java agent: download once, cache outside the repo ────────────────
step "preflight: OpenTelemetry Java auto-instrumentation agent"
mkdir -p "$AGENT_CACHE_DIR"
if [[ ! -s "$AGENT_JAR" ]]; then
    info "no cached agent at $AGENT_JAR -- downloading from $AGENT_URL"
    if ! curl -fsSL --max-time 120 -o "$AGENT_JAR.tmp" "$AGENT_URL"; then
        rm -f "$AGENT_JAR.tmp"
        fail "could not download the OpenTelemetry Java agent from $AGENT_URL (offline host?) -- download it manually to $AGENT_JAR and retry, e.g.: curl -fsSL -o '$AGENT_JAR' '$AGENT_URL'"
    fi
    mv "$AGENT_JAR.tmp" "$AGENT_JAR"
fi
[[ -s "$AGENT_JAR" ]] || fail "OpenTelemetry agent jar at $AGENT_JAR is missing or empty"
info "using OTel Java agent: $AGENT_JAR ($(du -h "$AGENT_JAR" | cut -f1))"

# ─── .env prereq (compose var resolution) ───────────────────────────────────
if [[ ! -f "${REPO_ROOT}/.env" ]]; then
    [[ -f "${REPO_ROOT}/.env.example" ]] \
        || fail ".env is missing and there is no .env.example to copy from at ${REPO_ROOT}"
    info "no .env found -- copying .env.example -> .env (gitignored, documented prereq)"
    cp "${REPO_ROOT}/.env.example" "${REPO_ROOT}/.env"
fi
# shellcheck disable=SC1091
source "${REPO_ROOT}/.env"
TEMPO_PORT="${TEMPO_PORT:-3200}"
TEMPO_BASE="http://localhost:${TEMPO_PORT}"
OTLP_HTTP_PORT="${OTLP_HTTP_PORT:-4318}"
OTLP_ENDPOINT="http://localhost:${OTLP_HTTP_PORT}"

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

step "preflight: compose Postgres reachable, Tempo search API answering"
for (( i = 0; i < 30; i++ )); do
    docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 && break
    sleep 1
done
docker exec datamesh-postgres pg_isready -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 \
    || fail "compose Postgres (orderdb) did not become ready within 30s"
# Tempo's own /ready lags /api/search answering 200 by ~30-40s on a cold
# container (confirmed empirically) -- poll the API we actually use instead.
wait_http "${TEMPO_BASE}/api/search?limit=1" 90 \
    || fail "Tempo search API at ${TEMPO_BASE}/api/search did not answer within 90s -- is the datamesh-lgtm container healthy? (docker logs datamesh-lgtm)"
assert_http_200 "${TEMPO_BASE}/api/search?limit=1"
info "compose Postgres + Tempo search API are reachable"

# ─── Build both services (idempotent) ───────────────────────────────────────
step "build order-service + inventory-service (mvn -DskipTests package)"
( cd "$ORDER_DIR" && mvn -q -DskipTests package ) || fail "mvn package failed for order-service"
[[ -f "${ORDER_DIR}/target/quarkus-app/quarkus-run.jar" ]] \
    || fail "order-service build did not produce target/quarkus-app/quarkus-run.jar"
( cd "$INVENTORY_DIR" && mvn -q -DskipTests package ) || fail "mvn package failed for inventory-service"
[[ -f "${INVENTORY_DIR}/target/quarkus-app/quarkus-run.jar" ]] \
    || fail "inventory-service build did not produce target/quarkus-app/quarkus-run.jar"

# ─── Start inventory-service, OTel agent attached ──────────────────────────
step "start inventory-service (HTTP ${INVENTORY_PORT}, gRPC ${INVENTORY_GRPC_PORT}, OTel agent attached)"
INV_PIDFILE="$(mktemp -t demo-tracing-inv-pid-XXXXXX)"
INV_LOGFILE="$(mktemp -t demo-tracing-inv-log-XXXXXX)"
info "log: $INV_LOGFILE"
( cd "$INVENTORY_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/inventorydb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    OTEL_SERVICE_NAME=inventory-service \
    OTEL_TRACES_EXPORTER=otlp \
    OTEL_METRICS_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none \
    OTEL_EXPORTER_OTLP_ENDPOINT="$OTLP_ENDPOINT" \
    OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
    OTEL_BSP_SCHEDULE_DELAY=1000 \
    java -javaagent:"$AGENT_JAR" \
        -Dquarkus.http.port="$INVENTORY_PORT" -Dquarkus.grpc.server.port="$INVENTORY_GRPC_PORT" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$INV_LOGFILE" 2>&1 &
echo "$!" > "$INV_PIDFILE"
SVC_PIDFILES+=("$INV_PIDFILE")

wait_http "${INVENTORY_BASE}/q/health/live" 60 \
    || { tail -n 60 "$INV_LOGFILE" >&2; fail "inventory-service did not become healthy within 60s -- see $INV_LOGFILE"; }
assert_http_200 "${INVENTORY_BASE}/q/health/live"
info "inventory-service is up"

step "seed deterministic stock via REST (idempotent upsert)"
curl -fsS --max-time 10 -X POST "${INVENTORY_BASE}/stock" \
    -H 'Content-Type: application/json' \
    -d '{"sku":"WIDGET-1","quantityOnHand":50,"available":true}' >/dev/null \
    || fail "seeding WIDGET-1 via POST /stock failed"

# ─── Start order-service, OTel agent attached ──────────────────────────────
step "start order-service (HTTP ${ORDER_PORT}, OTel agent attached)"
ORD_PIDFILE="$(mktemp -t demo-tracing-ord-pid-XXXXXX)"
ORD_LOGFILE="$(mktemp -t demo-tracing-ord-log-XXXXXX)"
info "log: $ORD_LOGFILE"
( cd "$ORDER_DIR" && exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/orderdb" \
    DB_USERNAME="${POSTGRES_USER:-appuser}" \
    DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
    KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
    APICURIO_REGISTRY_URL="http://localhost:${APICURIO_PORT}/apis/registry/v3" \
    OTEL_SERVICE_NAME=order-service \
    OTEL_TRACES_EXPORTER=otlp \
    OTEL_METRICS_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none \
    OTEL_EXPORTER_OTLP_ENDPOINT="$OTLP_ENDPOINT" \
    OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
    OTEL_BSP_SCHEDULE_DELAY=1000 \
    java -javaagent:"$AGENT_JAR" \
        -Dquarkus.http.port="$ORDER_PORT" \
        -Dorg.apache.avro.SERIALIZABLE_PACKAGES="$AVRO_SERIALIZABLE_PACKAGES" \
        -jar target/quarkus-app/quarkus-run.jar \
) >"$ORD_LOGFILE" 2>&1 &
echo "$!" > "$ORD_PIDFILE"
SVC_PIDFILES+=("$ORD_PIDFILE")

wait_http "${ORDER_BASE}/q/health/live" 60 \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "order-service did not become healthy within 60s -- see $ORD_LOGFILE"; }
assert_http_200 "${ORDER_BASE}/q/health/live"
info "order-service is up"

# ─── Trigger: a real cross-service request ─────────────────────────────────
step "POST /orders -- the traced request (order-service REST -> gRPC CheckStock -> inventory-service)"
CUSTOMER_ID="cust-demo-tracing-$$"
CREATE_RESP="$(curl -sS --max-time 15 -w '\n%{http_code}' -X POST "${ORDER_BASE}/orders" \
    -H 'Content-Type: application/json' \
    -d '{"customerId":"'"$CUSTOMER_ID"'","itemSku":"WIDGET-1","quantity":1,"amount":9.99}')"
CREATE_BODY="$(head -n -1 <<<"$CREATE_RESP")"
CREATE_CODE="$(tail -n1 <<<"$CREATE_RESP")"
[[ "$CREATE_CODE" == "201" ]] \
    || { tail -n 60 "$ORD_LOGFILE" >&2; fail "expected HTTP 201 from POST /orders, got $CREATE_CODE (body: $CREATE_BODY)"; }
ORDER_ID="$(jq -r '.orderId' <<<"$CREATE_BODY")"
[[ -n "$ORDER_ID" && "$ORDER_ID" != "null" ]] || fail "POST /orders response had no .orderId: $CREATE_BODY"
narrate "placed order id=${ORDER_ID} -- span export is async (batch processor), polling Tempo next"

# ─── Query Tempo: find the trace, fetch it, parse spans ────────────────────
step "query Tempo /api/search for order-service's POST /orders trace"
TRACE_ID=""
SEARCH_JSON=""
for (( i = 0; i < 60; i++ )); do
    SEARCH_JSON="$(curl -fsS --max-time 10 "${TEMPO_BASE}/api/search?tags=service.name%3Dorder-service&limit=20" 2>/dev/null)" || true
    TRACE_ID="$(jq -r --arg name "POST /orders" \
        '[.traces[]? | select(.rootTraceName == $name)] | sort_by(.startTimeUnixNano | tonumber) | last | .traceID // empty' \
        <<<"$SEARCH_JSON" 2>/dev/null)"
    [[ -n "$TRACE_ID" && "$TRACE_ID" != "null" ]] && break
    sleep 1
done
[[ -n "$TRACE_ID" && "$TRACE_ID" != "null" ]] \
    || fail "no 'POST /orders' trace rooted at order-service appeared in Tempo within 60s -- last search response: ${SEARCH_JSON}"
narrate "found trace id=${TRACE_ID} in Tempo"

step "GET /api/traces/${TRACE_ID} -- parse span count and participating services"
TRACE_JSON="$(curl -fsS --max-time 10 "${TEMPO_BASE}/api/traces/${TRACE_ID}")" \
    || fail "GET ${TEMPO_BASE}/api/traces/${TRACE_ID} failed"

# Tempo (otel-lgtm:0.8.1) answers with the Jaeger-style "batches" shape, with
# spans nested under EITHER "scopeSpans" or the older "instrumentationLibrarySpans"
# key depending on exporter version -- parse both defensively (confirmed
# live: this build uses "scopeSpans").
SPAN_COUNT="$(jq '[.batches[]? | (.scopeSpans[]?.spans[]?, .instrumentationLibrarySpans[]?.spans[]?)] | length' <<<"$TRACE_JSON")"
SERVICE_NAMES="$(jq -r '[.batches[]?.resource.attributes[]? | select(.key == "service.name") | .value.stringValue] | unique | join(",")' <<<"$TRACE_JSON")"
info "trace ${TRACE_ID}: ${SPAN_COUNT} spans, services=[${SERVICE_NAMES}]"

[[ -n "$SPAN_COUNT" && "$SPAN_COUNT" =~ ^[0-9]+$ ]] || fail "could not parse a numeric span count from the Tempo trace response"
(( SPAN_COUNT >= 5 )) \
    || fail "expected at least 5 spans in the POST /orders trace (REST + gRPC client/server + 2x Postgres minimum), got ${SPAN_COUNT}"
narrate "confirmed: trace ${TRACE_ID} has ${SPAN_COUNT} spans (>= 5)"

jq -e '[.batches[]?.resource.attributes[]? | select(.key == "service.name" and .value.stringValue == "order-service")] | length >= 1' <<<"$TRACE_JSON" >/dev/null \
    || fail "trace ${TRACE_ID} has no span whose resource.service.name == order-service: ${SERVICE_NAMES}"
jq -e '[.batches[]?.resource.attributes[]? | select(.key == "service.name" and .value.stringValue == "inventory-service")] | length >= 1' <<<"$TRACE_JSON" >/dev/null \
    || fail "trace ${TRACE_ID} has no span whose resource.service.name == inventory-service -- cross-service propagation did not reach Tempo: ${SERVICE_NAMES}"
narrate "confirmed: trace ${TRACE_ID} contains spans from both order-service and inventory-service --"
narrate "W3C trace-context propagated across the real gRPC call, exported to Tempo, and queried back"

jq -e --arg t "$TRACE_ID" '[.batches[]? | (.scopeSpans[]?.spans[]?, .instrumentationLibrarySpans[]?.spans[]?) | select(.name == "capstone.inventory.v1.InventoryService/CheckStock")] | length >= 1' <<<"$TRACE_JSON" >/dev/null \
    || fail "trace ${TRACE_ID} has no CheckStock gRPC span -- expected the cross-service hop to be captured"
narrate "confirmed: the CheckStock gRPC span is present in the parsed trace"

demo_ok
