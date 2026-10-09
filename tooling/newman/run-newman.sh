#!/usr/bin/env bash
#
# tooling/newman/run-newman.sh — run the Datamesh Postman
# collection (tooling/newman/datamesh.postman_collection.json) against the
# local stack via Newman, using the environment file
# tooling/newman/local.postman_environment.json.
#
# Reuses the shared demo harness (demos/lib/_demo.sh) for require/fail/step/
# narrate/wait_http so this script fails loud the same way the demo-*.sh
# scripts do, instead of letting Newman itself fail on connection-refused
# with a confusing stack of HTTP errors.
#
# Services this collection targets (brought up by the demos, not by this
# script):
#   order-service        http://localhost:8091   (demos/demo-graphql.sh)
#   inventory-service     http://localhost:8092   (demos/demo-graphql.sh)
#   graphql-gateway        http://localhost:8080   (demos/demo-graphql.sh)
#   review-service          http://localhost:8098   (demos/demo-oidc.sh)
#
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../demos/lib/_demo.sh
source "${SCRIPT_DIR}/../../demos/lib/_demo.sh"

FOLDER=""

usage() {
    cat <<'EOF'
Usage: tooling/newman/run-newman.sh [--folder <name>] [--help]

Run the Datamesh Postman collection (datamesh.postman_collection.json)
against the local stack using Newman and local.postman_environment.json.

Options:
  --folder <name>   Run only the named Postman folder (e.g. Health,
                     Inventory, Order, GraphQL, Review) instead of the
                     whole collection. Useful when only part of the stack
                     is up.
  --help            Show this help and exit.

Prerequisites (always checked before running, except with --help):
  - curl, jq on PATH
  - newman on PATH, or npx available to run the pinned newman@6.2.2 on demand
  - order-service (8091), inventory-service (8092), and graphql-gateway
    (8080) reachable — bring them up with:
        docker compose up -d
        demos/demo-graphql.sh
  - review-service (8098) reachable, unless --folder restricts the run to
    a non-Review folder — bring it up with:
        demos/demo-oidc.sh
EOF
}

# ─── Arg parsing (do this before anything that requires services) ──────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --folder)
            [[ $# -ge 2 ]] || fail "--folder requires an argument"
            FOLDER="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unrecognized argument: $1 (see --help)"
            ;;
    esac
done

require curl jq

# Guard: the compose stack publishes 3000/3100/3200/4317/4318 on the host, the
# same ports the minikube profile publishes. Refuse to start compose while the
# profile's node container is running.
if [[ "$(docker container inspect -f '{{.State.Running}}' "${MINIKUBE_PROFILE:-datamesh}" 2>/dev/null)" == "true" ]]; then
    fail "the datamesh minikube profile is running and holds ports 3000/3100/3200/4317/4318; stop it first: minikube stop -p datamesh"
fi

# ─── Resolve the Newman runner ──────────────────────────────────────────────
NEWMAN_RUNNER=()
if command -v newman >/dev/null 2>&1; then
    NEWMAN_RUNNER=(newman)
elif command -v npx >/dev/null 2>&1; then
    NEWMAN_RUNNER=(npx --yes newman@6.2.2)
else
    fail "neither 'newman' nor 'npx' found on PATH — install newman (npm install -g newman@6.2.2) or Node.js (for npx)"
fi

# ─── Prerequisite gate: order-service, inventory-service, graphql-gateway ──
step "checking required services are up"

declare -A REQUIRED_BASES=(
    [order-service]="http://localhost:8091"
    [inventory-service]="http://localhost:8092"
    [graphql-gateway]="http://localhost:8080"
)

DOWN=()
for name in "${!REQUIRED_BASES[@]}"; do
    base="${REQUIRED_BASES[$name]}"
    narrate "probing ${name} (${base}/q/health)"
    wait_http "${base}/q/health" 5 || DOWN+=("${name} (${base})")
done

if (( ${#DOWN[@]} > 0 )); then
    DOWN_LIST="$(printf '%s, ' "${DOWN[@]}")"
    DOWN_LIST="${DOWN_LIST%, }"
    fail "service(s) not reachable: ${DOWN_LIST} — bring up the stack first: 'docker compose up -d' then 'demos/demo-graphql.sh'"
fi

# ─── Conditional review-service gate ────────────────────────────────────────
# Only gate on review-service if the run isn't explicitly restricted to a
# non-Review folder (so a partial stack can still exercise one folder).
FOLDER_LC="$(printf '%s' "${FOLDER}" | tr '[:upper:]' '[:lower:]')"
if [[ -z "${FOLDER}" || "${FOLDER_LC}" == "review" ]]; then
    REVIEW_BASE="http://localhost:8098"
    narrate "probing review-service (${REVIEW_BASE}/q/health)"
    wait_http "${REVIEW_BASE}/q/health" 5 \
        || fail "review-service not reachable (${REVIEW_BASE}) — bring it up first: 'demos/demo-oidc.sh'"
fi

# ─── Run Newman ──────────────────────────────────────────────────────────
COLLECTION="${SCRIPT_DIR}/datamesh.postman_collection.json"
ENVIRONMENT="${SCRIPT_DIR}/local.postman_environment.json"

NEWMAN_ARGS=(run "${COLLECTION}" -e "${ENVIRONMENT}" -r cli)
if [[ -n "${FOLDER}" ]]; then
    NEWMAN_ARGS+=(--folder "${FOLDER}")
fi

step "running newman"
narrate "${NEWMAN_RUNNER[*]} ${NEWMAN_ARGS[*]}"
"${NEWMAN_RUNNER[@]}" "${NEWMAN_ARGS[@]}"
