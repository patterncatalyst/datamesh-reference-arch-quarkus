#!/usr/bin/env bash
#
# tooling/load/load-checkstock.sh — ghz-based gRPC load generator for the
# inventory-service CheckStock capacity story (mirrors load-orders.sh's
# house style, but for the gRPC surface hey cannot reach — see
# tooling/README.md's old "gRPC CheckStock ... not covered" exclusion,
# which this script closes).
#
# Lives under tooling/, not demos/, but reuses the demos' house style
# (demos/lib/_demo.sh: require/fail/step/narrate/wait_http, the
# demo_begin/demo_ok success-flag + trap idiom) — a load run that
# short-circuits before producing a summary must never read as clean.
#
# ── Target ───────────────────────────────────────────────────────────────
#   capstone.inventory.v1.InventoryService/CheckStock, over plaintext
#   HTTP/2 gRPC, against inventory-service's gRPC port (canonical 9000 —
#   see demos/demo-order.sh's header comment on the shared
#   INVENTORY_GRPC_PORT default). Proto:
#     examples/contracts/src/main/proto/capstone/inventory/v1/inventory.proto
#
# ── Ports (match demos/demo-order.sh's / demos/demo-graphql.sh's bring-up) ──
#   inventory-service  HTTP 8092 (preflight probe target, hardcoded)
#                       gRPC 9000 (default --host, load target)
#
# gRPC itself has no easy curl probe, so preflight gates on
# inventory-service's HTTP /q/health instead — a live HTTP health endpoint
# on the same process is strong evidence the gRPC server (started in the
# same Quarkus boot) is also up. Bring the service up first
# (demos/demo-order.sh or demos/demo-graphql.sh) before pointing this at
# it — the health gate below fails loud, naming both scripts, if the
# target isn't reachable.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../demos/lib/_demo.sh
source "${SCRIPT_DIR}/../../demos/lib/_demo.sh"

GHZ_BIN="${GHZ_BIN:-ghz}"
INVENTORY_HEALTH_BASE="http://localhost:8092"
PROTO_FILE="${REPO_ROOT}/examples/contracts/src/main/proto/capstone/inventory/v1/inventory.proto"
GRPC_CALL="capstone.inventory.v1.InventoryService/CheckStock"
GRPC_DATA='{"sku":"WIDGET-1","quantity":1}'

usage() {
    cat <<'EOF'
Usage: tooling/load/load-checkstock.sh [options]

ghz-based gRPC load generator for the inventory-service CheckStock
capacity story. Health-gates inventory-service's HTTP endpoint (gRPC has
no easy curl probe), runs `ghz`, and lets its native summary print
(throughput, latency distribution, status-code breakdown).

Options:
  -c <n>         Concurrency (number of ghz workers). Default: 10.
  -z <duration>  Duration to run, e.g. "20s", "3m". Default: 20s.
                 Mutually exclusive with -n — whichever is given last wins.
  -n <count>     Fixed number of requests instead of a duration.
  --host <addr>  gRPC host:port of inventory-service. Default: localhost:9000
                 (canonical — see demos/demo-order.sh).
  --insecure     Use plaintext/insecure gRPC (ghz --insecure). Default: on —
                 inventory-service does not terminate TLS in this repo, so
                 there is no alternative mode; the flag exists for parity
                 with ghz's own vocabulary and is a no-op if passed.
  -h, --help     Show this help and exit.

Examples:
  tooling/load/load-checkstock.sh
  tooling/load/load-checkstock.sh -c 25 -z 60s
  tooling/load/load-checkstock.sh -n 2000 --host localhost:9000
EOF
}

CONCURRENCY=10
DURATION="20s"
COUNT=""
HOST="localhost:9000"
INSECURE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c)
            CONCURRENCY="$2"; shift 2 ;;
        -z)
            DURATION="$2"; COUNT=""; shift 2 ;;
        -n)
            COUNT="$2"; DURATION=""; shift 2 ;;
        --host)
            HOST="$2"; shift 2 ;;
        --insecure)
            INSECURE=1; shift ;;
        -h|--help)
            usage
            exit 0 ;;
        *)
            usage >&2
            fail "unknown argument: $1 (see --help above)" ;;
    esac
done

demo_begin "load-checkstock"
require curl jq

# ghz has no generic apt/dnf/brew package most places — give an actionable
# install hint rather than the generic `require` message.
command -v "$GHZ_BIN" >/dev/null 2>&1 \
    || fail "missing required command: ${GHZ_BIN} — install it with: go install github.com/bojand/ghz/cmd/ghz@latest (or grab a release from https://ghz.sh/)"

[[ -f "$PROTO_FILE" ]] \
    || fail "inventory.proto not found at ${PROTO_FILE} — has the contracts module moved?"

narrate "ghz gRPC load against ${HOST} ${GRPC_CALL} (concurrency=${CONCURRENCY}$( [[ -n "$COUNT" ]] && echo ", n=${COUNT}" || echo ", z=${DURATION}" ))"

step "preflight: ${INVENTORY_HEALTH_BASE}/q/health reachable (HTTP proxy for the gRPC port on the same process)"
wait_http "${INVENTORY_HEALTH_BASE}/q/health" 5 \
    || fail "inventory-service health check failed at ${INVENTORY_HEALTH_BASE}/q/health -- bring it up first (see demos/demo-order.sh or demos/demo-graphql.sh) and retry"
info "inventory-service is up (HTTP ${INVENTORY_HEALTH_BASE}, gRPC target ${HOST})"

GHZ_ARGS=(--proto "$PROTO_FILE" --call "$GRPC_CALL" -d "$GRPC_DATA" -c "$CONCURRENCY")
if [[ -n "$COUNT" ]]; then
    GHZ_ARGS+=(-n "$COUNT")
else
    GHZ_ARGS+=(-z "$DURATION")
fi
if (( INSECURE == 1 )); then
    GHZ_ARGS+=(--insecure)
fi

step "ramp: ${GRPC_CALL} @ ${HOST}"
"$GHZ_BIN" "${GHZ_ARGS[@]}" "$HOST"

narrate "throughput and latency distribution above are ghz's own summary -- read the \"Requests/sec\" (RPS) line and the 50/90/99th percentile breakdown for the capacity story, same as load-orders.sh's hey summary"

demo_ok
