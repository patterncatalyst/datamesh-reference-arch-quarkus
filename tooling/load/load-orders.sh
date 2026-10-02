#!/usr/bin/env bash
#
# tooling/load/load-orders.sh — hey-based HTTP load generator for the
# order-service capacity story: ramps GET/POST traffic
# against /orders and lets `hey`'s own summary report throughput (RPS)
# and the latency distribution.
#
# Lives under tooling/, not demos/, but reuses the demos' house style
# (demos/lib/_demo.sh: require/fail/step/narrate/info/wait_http, the
# demo_begin/demo_ok success-flag + trap idiom) — a load run that
# short-circuits before producing a summary must never read as clean.
#
# ── Modes ─────────────────────────────────────────────────────────────────
#   get  (default, read-only, safe) — GET {{base}}/orders. Never writes.
#   post (opt-in)                   — first seeds WIDGET-1 with a large
#                                      stock quantity via inventory-
#                                      service's POST /stock (so the ramp's
#                                      orders don't 409 on insufficient
#                                      stock), then ramps POST {{base}}/orders.
#
# ── Ports (match demos/demo-order.sh's bring-up) ────────────────────────────
#   order-service      HTTP 8091  (default --base)
#   inventory-service  HTTP 8092  (post-mode seed target, hardcoded)
#
# Bring both services up first (demos/demo-order.sh) before pointing this
# at them — the health gate below fails loud, naming that script, if the
# target isn't reachable.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../demos/lib/_demo.sh
source "${SCRIPT_DIR}/../../demos/lib/_demo.sh"

HEY_BIN="${HEY_BIN:-hey}"
INVENTORY_BASE="http://localhost:8092"

usage() {
    cat <<'EOF'
Usage: tooling/load/load-orders.sh [options]

hey-based HTTP load generator for the order-service capacity story.
Health-gates the target, runs `hey`, and lets its native summary print
(Requests/sec, latency distribution, status-code histogram).

Options:
  -c <n>         Concurrency (number of hey workers). Default: 10.
  -z <duration>  Duration to run, e.g. "20s", "3m". Default: 20s.
                 Mutually exclusive with -n — whichever is given last wins.
  -n <count>     Fixed number of requests instead of a duration.
  --base <url>   Base URL of order-service. Default: http://localhost:8091
  --mode <m>     "get"  (default, read-only) GET {{base}}/orders
                 "post" (opt-in) seeds WIDGET-1 stock on inventory-service
                        (http://localhost:8092/stock), then ramps
                        POST {{base}}/orders
  -h, --help     Show this help and exit.

Examples:
  tooling/load/load-orders.sh
  tooling/load/load-orders.sh -c 25 -z 60s
  tooling/load/load-orders.sh -n 2000 --mode post
  tooling/load/load-orders.sh --base http://localhost:8091 --mode get
EOF
}

CONCURRENCY=10
DURATION="20s"
COUNT=""
BASE="http://localhost:8091"
MODE="get"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c)
            CONCURRENCY="$2"; shift 2 ;;
        -z)
            DURATION="$2"; COUNT=""; shift 2 ;;
        -n)
            COUNT="$2"; DURATION=""; shift 2 ;;
        --base)
            BASE="$2"; shift 2 ;;
        --mode)
            MODE="$2"; shift 2 ;;
        -h|--help)
            usage
            exit 0 ;;
        *)
            usage >&2
            fail "unknown argument: $1 (see --help above)" ;;
    esac
done

[[ "$MODE" == "get" || "$MODE" == "post" ]] \
    || fail "invalid --mode: ${MODE} (must be \"get\" or \"post\")"

demo_begin "load-orders (${MODE})"
require curl jq hey

if [[ -n "$COUNT" ]]; then
    narrate "hey load against ${BASE}/orders (mode=${MODE}, concurrency=${CONCURRENCY}, n=${COUNT})"
else
    narrate "hey load against ${BASE}/orders (mode=${MODE}, concurrency=${CONCURRENCY}, z=${DURATION})"
fi

step "preflight: ${BASE}/q/health reachable"
wait_http "${BASE}/q/health" 5 \
    || fail "order-service health check failed at ${BASE}/q/health -- bring it up first (see demos/demo-order.sh) and retry"
info "order-service is up at ${BASE}"

HEY_ARGS=(-c "$CONCURRENCY")
if [[ -n "$COUNT" ]]; then
    HEY_ARGS+=(-n "$COUNT")
else
    HEY_ARGS+=(-z "$DURATION")
fi

if [[ "$MODE" == "post" ]]; then
    step "seed WIDGET-1 stock on inventory-service (so the ramp doesn't 409)"
    curl -fsS --max-time 10 -X POST "${INVENTORY_BASE}/stock" \
        -H 'Content-Type: application/json' \
        -d '{"sku":"WIDGET-1","quantityOnHand":100000,"available":true}' >/dev/null \
        || fail "seeding WIDGET-1 via POST ${INVENTORY_BASE}/stock failed -- is inventory-service up (see demos/demo-order.sh)?"
    info "seeded WIDGET-1 with 100000 units on hand"

    step "ramp: POST ${BASE}/orders"
    HEY_ARGS+=(-m POST -T application/json -d '{"customerId":"load","itemSku":"WIDGET-1","quantity":1,"amount":9.99}')
    "$HEY_BIN" "${HEY_ARGS[@]}" "${BASE}/orders"
else
    step "ramp: GET ${BASE}/orders"
    HEY_ARGS+=(-m GET)
    "$HEY_BIN" "${HEY_ARGS[@]}" "${BASE}/orders"
fi

narrate "throughput (RPS) and latency distribution above are hey's own summary -- read the Requests/sec line and the 50/90/99th percentile breakdown for the capacity story"

demo_ok
