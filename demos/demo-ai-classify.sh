#!/usr/bin/env bash
#
# demos/demo-ai-classify.sh — langchain4j single-shot chat classification.
#
# ai-mcp-service's OrderClassifierRoute exposes POST /api/orders/classify ->
# direct:classify-order -> langchain4j-chat:classifier. This is a single-shot
# chat call (CHAT_SINGLE_MESSAGE_WITH_PROMPT) -- NOT an agent, NOT tool
# calling -- so it structurally avoids the tool-calling defect (the embedded
# MCP server / tool-calling limitation lives entirely in OrderLookupToolRoute
# / OrderAssistantRoute, neither of which this demo touches).
#
# BUG FOUND + FIXED (uncommitted) while wiring this demo:
# OrderClassifierRoute.java set a header literally named
# "CamelLangChain4jChatPrompt" (missing the "Template" suffix) and never
# switched the langchain4j-chat endpoint off its default CHAT_SINGLE_MESSAGE
# operation. Per the camel-mcp catalog (camel_catalog_component_doc
# langchain4j-chat, includeHeaders=true) and LangChain4jChatProducer's
# bytecode, the real header is LangChain4jChatHeaders.PROMPT_TEMPLATE =
# "CamelLangChain4jChatPromptTemplate", and it is only read when the endpoint
# is configured chatOperation=CHAT_SINGLE_MESSAGE_WITH_PROMPT. Neither
# condition held, so the component silently fell back to CHAT_SINGLE_MESSAGE:
# the raw order JSON was sent to Ollama as a bare chat message and the model
# just chatted about it ("You have requested one laptop. Is there anything
# else...") instead of classifying it -- confirmed deterministically across
# repeated real calls against the live qwen2.5:3b before the fix (never once
# produced JSON). Fixed in
# examples/ai-mcp-service/src/main/java/.../OrderClassifierRoute.java (NOT
# committed -- flagged here same as the ai-rules-service pom.xml fix in
# demo-ai-triage.sh): corrected header name + chatOperation query param +
# an empty-Map body (CHAT_SINGLE_MESSAGE_WITH_PROMPT requires a
# Map<String,Object> body of PromptTemplate variables; the prompt text is
# already fully resolved by Camel's simple() before the component sees it,
# so no variables are needed).
#
# Infra: this demo OWNS the compose ollama-profile lifecycle itself
# (compose_up ollama / compose_down), unlike demo-ai-triage.sh (which reuses
# an already-running host Ollama). qwen2.5:3b must be pulled into the
# ollama container; this demo pulls it if missing (idempotent, fast if
# already cached in the ollama-data named volume).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-ai-classify"
require curl jq docker mvn java

MODULE_DIR="${EXAMPLES_DIR}/ai-mcp-service"
PORT=8088
BASE_URL="http://localhost:${PORT}"
OLLAMA_URL="http://localhost:11434"
MODEL="qwen2.5:3b"

narrate "langchain4j-chat single-shot classification: POST /api/orders/classify"
narrate "runs CHAT_SINGLE_MESSAGE_WITH_PROMPT against Ollama (${MODEL}) -- no"
narrate "agent, no tool calling -- structurally avoids the tool-calling defect."

# ─── Compose lifecycle: this script owns it ──────────────────────────────────
step "bring up compose (baseline + ollama profile)"
compose_up ollama

_cleanup() {
    local rc=$?
    [[ -n "${SVC_PIDFILE:-}" ]] && svc_stop "$SVC_PIDFILE" 2>/dev/null || true
    # Pass the `ollama` profile so the profile-gated ollama service is torn
    # down too (a bare `docker compose down` leaves it running).
    compose_down ollama 2>/dev/null || true
    return "$rc"
}
trap '_cleanup; _demo_exit_trap' EXIT

step "preflight: Ollama reachable + ${MODEL} pulled"
wait_http "${OLLAMA_URL}/api/tags" 60 \
    || fail "ollama did not answer at ${OLLAMA_URL}/api/tags within 60s after compose up"
assert_http_200 "${OLLAMA_URL}/api/tags"
TAGS_JSON="$(curl -fsS --max-time 5 "${OLLAMA_URL}/api/tags")"
if ! jq -e --arg m "$MODEL" '.models[]? | select(.name == $m)' <<<"$TAGS_JSON" >/dev/null 2>&1; then
    info "${MODEL} not found in the ollama container -- pulling (first pull is slow)"
    docker exec datamesh-ollama ollama pull "$MODEL" \
        || fail "docker exec datamesh-ollama ollama pull ${MODEL} failed"
fi
TAGS_JSON="$(curl -fsS --max-time 5 "${OLLAMA_URL}/api/tags")"
jq -e --arg m "$MODEL" '.models[]? | select(.name == $m)' <<<"$TAGS_JSON" >/dev/null 2>&1 \
    || fail "${MODEL} still not listed in ${OLLAMA_URL}/api/tags after pull"
info "${MODEL} is present in the ollama container"

# ─── Start ai-mcp-service (mvn quarkus:dev — pom.xml already binds the ─────
# quarkus-maven-plugin's build/generate-code executions via the parent's
# pluginManagement, same as order-service; unlike ai-rules-service this
# module needed no pom.xml fix).
step "start ai-mcp-service (port ${PORT})"
SVC_PIDFILE="$(svc_start_dev "$MODULE_DIR" "$PORT")"

# This module has no health/actuator endpoint and its only GET-able routes
# 404/405 rather than 200 (classify/assistant are POST-only, /mcp is
# POST-only) -- the harness's wait_http (curl -f, needs 2xx/3xx) can't be
# used directly. Wait for ANY HTTP response (connection refused -> connected)
# instead, same pattern as demo-ai-triage.sh.
wait_any_http() {
    local url="$1" budget="${2:-60}" i
    for (( i = 0; i < budget; i++ )); do
        curl -s -o /dev/null --max-time 2 "$url" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}
wait_any_http "${BASE_URL}/api/orders/classify" 90 \
    || fail "ai-mcp-service did not start listening on ${PORT} within 90s"
info "ai-mcp-service is listening on ${PORT}"

# ─── Test inputs ─────────────────────────────────────────────────────────────
# Each was sampled 3x against the live qwen2.5:3b (post-fix) before being
# wired in here; the "category" field was STABLE across all 3 trials for
# each input (priority/fulfillmentType were noisier -- qwen2.5:3b is a small
# model and occasionally emits a value outside the documented enum for those
# two fields, e.g. "NORMAL" for priority -- so this demo asserts category
# strictly and only checks priority/fulfillmentType for presence, not exact
# enum membership, to stay honest about what is and isn't deterministic
# here).
classify_post() {
    local body="$1"
    curl -sS --max-time 90 -X POST "${BASE_URL}/api/orders/classify" \
        -H 'Content-Type: application/json' \
        -d "$body"
}

VALID_CATEGORIES='ELECTRONICS PERISHABLE HAZARDOUS FRAGILE STANDARD'

run_classify_case() {
    local label="$1" body="$2" expected_category="$3" json category priority fulfillment

    narrate "${label} -> expect category=${expected_category} (strict, pre-validated 3x)"
    json="$(classify_post "$body")"
    info "response: $json"
    category="$(jq -r '.category' <<<"$json" 2>/dev/null)" \
        || fail "[${label}] response was not parseable JSON: $json"
    case " $VALID_CATEGORIES " in
        *" $category "*) ;;
        *) fail "[${label}] .category = '$category' is not one of {$VALID_CATEGORIES} (json: $json)" ;;
    esac
    assert_json_field "$json" '.category' "$expected_category"

    priority="$(jq -r '.priority' <<<"$json")"
    fulfillment="$(jq -r '.fulfillmentType' <<<"$json")"
    [[ -n "$priority" && "$priority" != "null" ]] || fail "[${label}] .priority was null/empty (json: $json)"
    [[ -n "$fulfillment" && "$fulfillment" != "null" ]] || fail "[${label}] .fulfillmentType was null/empty (json: $json)"
    info "priority=${priority} fulfillmentType=${fulfillment} (presence-checked, not enum-strict)"
}

step "POST /api/orders/classify — 3 pre-validated inputs"
run_classify_case "perishable order (fresh strawberries)" \
    '{"item":"fresh strawberries","quantity":50}' "PERISHABLE"
run_classify_case "hazardous order (industrial sulfuric acid)" \
    '{"item":"industrial sulfuric acid, corrosive chemical","quantity":4}' "HAZARDOUS"
run_classify_case "fragile order (antique crystal wine glasses)" \
    '{"item":"antique crystal wine glasses","quantity":6}' "FRAGILE"

step "classification confirmed"
narrate "All 3 orders were classified into the correct category label by a"
narrate "single-shot langchain4j-chat call against Ollama (${MODEL}) -- no"
narrate "agent, no tool calling, no exposure to the tool-calling defect."

demo_ok
