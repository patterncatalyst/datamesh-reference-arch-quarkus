#!/usr/bin/env bash
#
# demos/demo-ai-triage.sh — showcase demo: LLM classifies, Drools decides.
#
# "LLM classifies, Drools decides — orchestrated two ways (Camel route vs
# Quarkus Flow)."
#
# The ai-rules-service module exposes TWO REST endpoints that run the exact
# same classify-then-decide logic (TriageService):
#
#   POST /api/orders/triage       — orchestrated by a Camel route
#   POST /api/orders/triage-flow  — orchestrated by a Quarkus Flow workflow
#
# Both delegate classification to a single-shot langchain4j chat call against
# Ollama (qwen2.5:3b) — not an agent, not tool-calling — and both hand the
# classified fields to the same embedded Drools rule set
# (rules/order-triage.drl) to make the actual business decision
# (FRAUD_HOLD / EXPEDITE / ROUTE_TO_WAREHOUSE). This is the shape that
# structurally avoids the tool-calling defect: neither path has a
# langchain4j-agent / ai-tool / mcp-server dependency, so neither can
# regress into the upstream Ollama tool-calling failure — there is no
# in-process tool-calling round trip to fail in the first place.
#
# Infra: this demo talks to a HOST Ollama already running on
# http://localhost:11434 (ai-rules-service's application.properties already
# points there) — it does not start/stop Ollama itself (compose_up ollama is
# also an option, but would collide with an already-running host Ollama on
# the same port, so this script assumes host Ollama is up, same as this
# module's opt-in IT does).
#
# Service lifecycle: this module's pom.xml is missing the
# quarkus-maven-plugin <build> binding that its sibling modules
# (order-service, et al.) have, so `mvn quarkus:dev` (the harness's
# svc_start_dev) silently no-ops ("assumed to be a support library") and
# never opens the port. That same gap also means a plain `mvn package` only
# produces a thin jar, not target/quarkus-app/quarkus-run.jar. This demo
# packages the module itself (idempotent — fast on an unchanged tree) and
# runs the resulting quarkus-run.jar directly, which is both more reliable
# here and faster to boot than dev mode. See the one-line pom.xml fix this
# step applied (examples/ai-rules-service/pom.xml) — not committed.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-ai-triage"
require curl jq mvn java

MODULE_DIR="${EXAMPLES_DIR}/ai-rules-service"
PORT=8089
BASE_URL="http://localhost:${PORT}"
OLLAMA_URL="http://localhost:11434"

narrate "An order is classified by Ollama (qwen2.5:3b,"
narrate "single-shot chat — no tool-calling), then a shared Drools rule set makes"
narrate "the FRAUD_HOLD / EXPEDITE / ROUTE_TO_WAREHOUSE decision. Two endpoints,"
narrate "same TriageService logic: /triage (Camel route) vs /triage-flow (Quarkus"
narrate "Flow workflow). This shape structurally avoids the tool-calling defect —"
narrate "zero langchain4j tool-calling anywhere in either path."

# ─── Preflight: host Ollama must be reachable with qwen2.5:3b pulled ────────
step "preflight: host Ollama"
curl -fsS --max-time 5 "${OLLAMA_URL}/api/tags" >/tmp/demo-ai-triage-ollama-tags.$$ 2>/dev/null \
    || fail "host Ollama not reachable at ${OLLAMA_URL} — start it (ollama serve) before running this demo"
grep -q 'qwen2.5:3b' /tmp/demo-ai-triage-ollama-tags.$$ \
    || fail "qwen2.5:3b not found in Ollama's model list at ${OLLAMA_URL}/api/tags — run: ollama pull qwen2.5:3b"
rm -f /tmp/demo-ai-triage-ollama-tags.$$
info "host Ollama is up and qwen2.5:3b is pulled"

# ─── Build + start ai-rules-service as a packaged jar ───────────────────────
step "build ai-rules-service"
info "mvn -DskipTests package (idempotent — fast if already built)"
( cd "$MODULE_DIR" && mvn -q -DskipTests package ) \
    || fail "mvn package failed for ai-rules-service — see output above"
[[ -f "${MODULE_DIR}/target/quarkus-app/quarkus-run.jar" ]] \
    || fail "build did not produce target/quarkus-app/quarkus-run.jar"

step "start ai-rules-service (port ${PORT})"
SVC_PIDFILE="$(mktemp -t demo-ai-triage-pid-XXXXXX)"
SVC_LOGFILE="$(mktemp -t demo-ai-triage-log-XXXXXX)"
info "log: $SVC_LOGFILE"
( cd "$MODULE_DIR" && exec java -Dquarkus.http.port="$PORT" -jar target/quarkus-app/quarkus-run.jar >"$SVC_LOGFILE" 2>&1 ) &
echo "$!" > "$SVC_PIDFILE"

# Chain our own service-stop cleanup in FRONT of the harness's
# success/failure trap. `_cleanup_service` preserves and re-returns the
# original exit code so `_demo_exit_trap` (installed by demo_begin) still
# sees the real outcome, not svc_stop's own (always-0) return value.
_cleanup_service() {
    local rc=$?
    svc_stop "$SVC_PIDFILE" 2>/dev/null || true
    return "$rc"
}
trap '_cleanup_service; _demo_exit_trap' EXIT

# This module has no health/actuator endpoint and no GET route that answers
# 200 (its only routes are POST /api/orders/triage[-flow]), so the harness's
# wait_http (which requires curl -f, i.e. a 2xx/3xx) can never succeed here.
# Wait for ANY HTTP response instead (connection refused -> connected),
# which is enough to know the HTTP listener itself is up.
wait_any_http() {
    local url="$1" budget="${2:-60}" i
    for (( i = 0; i < budget; i++ )); do
        # No -f: curl itself exits 0 for ANY actual HTTP response (2xx
        # through 5xx) and non-zero only for a connection-level failure
        # (refused/timeout/etc) -- exactly the "any response" wait we need.
        curl -s -o /dev/null --max-time 2 "$url" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}

wait_any_http "${BASE_URL}/api/orders/triage" 60 \
    || fail "ai-rules-service did not start listening on ${PORT} within 60s — see $SVC_LOGFILE"
info "ai-rules-service is listening on ${PORT}"

# ─── Test inputs ─────────────────────────────────────────────────────────────
# All three inputs were pre-validated directly against the live host Ollama
# (same prompt TriageService.buildClassifyPrompt builds, same model) across
# repeated trials before wiring them into this script, specifically to find
# inputs whose classification is STABLE for qwen2.5:3b rather than noisy —
# see the inline note on each input for what was confirmed and how that maps
# through rules/order-triage.drl to a specific decision. Because Drools'
# decision is a deterministic function of the classified riskSignal/amount
# (not of the LLM's prose), a stable classification yields a stable decision,
# which is why these three assertions below are STRICT (exact decision), not
# mere membership-in-the-valid-set — stronger than this module's own opt-in
# ITs (OrderTriageRouteIT / OrderTriageFlowRouteIT), which only assert
# membership because they don't control for classifier noise.
#
#   1. BENIGN_ORDER   — low amount, ordinary item. Observed riskSignal=LOW
#      and amount < 1000 across repeated trials -> neither the fraud-hold nor
#      the expedite rule can match -> deterministic ROUTE_TO_WAREHOUSE
#      (Drools' default/catch-all rule).
BENIGN_ORDER='{"customerId":"CUST-1001","itemSku":"BOOK-NOVEL-001","quantity":1,"amount":19.99}'
#   2. EXPEDITE_ORDER — ordinary item, amount >= 1000. Observed riskSignal=LOW
#      and amount >= 1000 across repeated trials -> "Expedite large trusted
#      order" rule matches -> deterministic EXPEDITE.
EXPEDITE_ORDER='{"customerId":"CUST-VERIFIED-LONGTIME","itemSku":"OFFICE-CHAIR-ERGO","quantity":2,"amount":1250.00}'
#   3. RISKY_ORDER    — a fraud-signalling item description
#      (bulk reselling of stolen gift cards) at high volume/amount. Observed
#      riskSignal=HIGH across repeated trials -> "Fraud hold on high risk"
#      rule matches (highest salience) -> deterministic FRAUD_HOLD,
#      regardless of amount.
RISKY_ORDER='{"customerId":"CUST-ANON-9999","itemSku":"STOLEN-GIFTCARD-BULK-RESHIP-FRAUD","quantity":500,"amount":48999.99}'

VALID_DECISIONS='FRAUD_HOLD EXPEDITE ROUTE_TO_WAREHOUSE'

# triage_post <endpoint> <order-json> — POST to one of the two triage
# endpoints and print the raw JSON response body.
triage_post() {
    local endpoint="$1" body="$2"
    curl -sS --max-time 60 -X POST "${BASE_URL}${endpoint}" \
        -H 'Content-Type: application/json' \
        -d "$body"
}

# assert_decision_member <json> <endpoint-label> — membership assertion: the
# field is present and is one of the three valid enum values. Used as a
# baseline sanity check on every response (strict checks below are on top of
# this, not instead of it).
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

run_for_endpoint() {
    local endpoint="$1" label="$2"
    local json decision

    step "${label}: POST ${endpoint}"

    narrate "benign low-value order -> expect ROUTE_TO_WAREHOUSE (strict)"
    json="$(triage_post "$endpoint" "$BENIGN_ORDER")"
    info "response: $json"
    decision="$(assert_decision_member "$json" "${label} benign")"
    info "decision: $decision"
    assert_json_field "$json" '.decision' 'ROUTE_TO_WAREHOUSE'
    [[ "$(jq -r '.reason' <<<"$json")" != "null" ]] || fail "[${label} benign] .reason was null"

    narrate "high-value trusted-looking order -> expect EXPEDITE (strict)"
    json="$(triage_post "$endpoint" "$EXPEDITE_ORDER")"
    info "response: $json"
    decision="$(assert_decision_member "$json" "${label} expedite")"
    info "decision: $decision"
    assert_json_field "$json" '.decision' 'EXPEDITE'
    [[ "$(jq -r '.reason' <<<"$json")" != "null" ]] || fail "[${label} expedite] .reason was null"

    narrate "high-risk / high-volume order -> expect FRAUD_HOLD (strict)"
    json="$(triage_post "$endpoint" "$RISKY_ORDER")"
    info "response: $json"
    decision="$(assert_decision_member "$json" "${label} risky")"
    info "decision: $decision"
    assert_json_field "$json" '.decision' 'FRAUD_HOLD'
    [[ "$(jq -r '.reason' <<<"$json")" != "null" ]] || fail "[${label} risky] .reason was null"
}

run_for_endpoint "/api/orders/triage" "Camel (/triage)"
run_for_endpoint "/api/orders/triage-flow" "Flow (/triage-flow)"

step "A/B contrast confirmed"
narrate "Both /triage (Camel route) and /triage-flow (Quarkus Flow workflow)"
narrate "returned the same TriageDecision JSON shape and the same three"
narrate "decisions for the same three inputs — proving both orchestration"
narrate "paths drive the identical classify-then-decide logic end-to-end,"
narrate "with Drools (not the LLM) making every decision."

demo_ok
