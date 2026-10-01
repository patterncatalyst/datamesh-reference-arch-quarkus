#!/usr/bin/env bash
#
# demos/demo-ai-mcp.sh — Phase D step 10.4 (second half): the embedded Camel
# MCP server surface (DEF-001-honest).
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║ DEF-001 CAVEAT — READ BEFORE TRUSTING ANYTHING THIS DEMO PRINTS          ║
# ║                                                                          ║
# ║ camel-quarkus-support-langchain4j unconditionally enforces the          ║
# ║ Quarkiverse JAX-RS HTTP client factory for EVERY dev.langchain4j model  ║
# ║ on the classpath (SupportQuarkusLangchain4jProcessor.enforceJaxRsHttp   ║
# ║ Client() sets the global system property                                ║
# ║ langchain4j.http.clientBuilderFactory -- there is no toggle for it).     ║
# ║ This means the hand-built OllamaChatModel backing                       ║
# ║ OrderAssistantRoute's langchain4j-agent:assistant endpoint              ║
# ║ (AgentProducers.assistantAgent()) does NOT get the transport its own    ║
# ║ builder configured -- and the agent's in-process TOOL-CALLING round     ║
# ║ trip to the order-status ai-tool NEVER FIRES on this stack. This is     ║
# ║ DEF-001, an OPEN upstream deferral (see _plans/decisions.md), confirmed ║
# ║ by exhaustive diagnosis in this repo: direct Ollama /api/chat calls DO  ║
# ║ return tool_calls for qwen2.5:3b, tool/tag registration is correct, and ║
# ║ the behaviour reproduces across every langchain4j version tried. It is ║
# ║ a transport-wiring bug in camel-quarkus-support-langchain4j, not a bug  ║
# ║ in this module, not a model-capability gap, and not something this     ║
# ║ demo can route around in-process.                                       ║
# ║                                                                          ║
# ║ CONSEQUENCE FOR THIS DEMO: it NEVER calls POST /api/assistant/chat and  ║
# ║ NEVER treats a non-empty chat response as evidence of tool calling      ║
# ║ (that would be a green-washed lie over a known-broken path). Instead it ║
# ║ demonstrates the ONE part of this stack that genuinely works end to     ║
# ║ end: the embedded Camel MCP server (camel-quarkus-mcp-server, which     ║
# ║ wraps the Quarkiverse quarkus-mcp-server-http extension) publishing the ║
# ║ shipping-tagged order-status ai-tool to EXTERNAL MCP clients speaking   ║
# ║ the real MCP Streamable HTTP wire protocol -- a completely separate     ║
# ║ code path from the in-process langchain4j-agent that DEF-001 breaks.   ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# What this demo asserts (MCP-server surface ONLY):
#   1. POST /mcp {method:"initialize"} succeeds and returns a protocolVersion
#      + an Mcp-Session-Id header (real MCP Streamable HTTP handshake).
#   2. POST /mcp {method:"tools/list"} (with that session) lists a tool
#      literally named "order-status".
#   3. POST /mcp {method:"tools/call", params:{name:"order-status", ...}}
#      for ORD-001/ORD-002/ORD-003 returns the exact deterministic fake
#      lookup body OrderLookupToolRoute hardcodes for each id (status field
#      parsed out of the nested JSON-in-a-string content block).
# This is scripted as a minimal real MCP client over curl+jq (no new
# runtime dependency) speaking actual JSON-RPC 2.0 over the Streamable HTTP
# transport -- endpoints and protocol confirmed empirically against the live
# service (GET /mcp -> 405, confirming POST-only; startup log line "MCP HTTP
# transport endpoints [streamable: http://localhost:8088/mcp, SSE:
# http://localhost:8088/mcp/sse]"; default root path "/mcp" confirmed via
# McpHttpServerBuildTimeConfig.Http.rootPath()'s @WithDefault("/mcp")).
#
# Infra: this demo OWNS the compose ollama-profile lifecycle itself
# (compose_up ollama / compose_down). Technically the MCP-server path here
# never calls Ollama at all (order-status is a hardcoded fake lookup, not an
# LLM call) -- Ollama is still brought up because ai-mcp-service's
# quarkus-langchain4j-ollama extension is on this module's classpath and the
# module is part of the "compose + --profile ollama" demo group per
# demos/README.md.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-ai-mcp"
require curl jq docker mvn java

MODULE_DIR="${EXAMPLES_DIR}/ai-mcp-service"
PORT=8088
BASE_URL="http://localhost:${PORT}"
MCP_URL="${BASE_URL}/mcp"
OLLAMA_URL="http://localhost:11434"

cat >&2 <<'BANNER'

################################################################################
#  DEF-001 CAVEAT: in-process langchain4j-agent tool-calling does NOT fire   #
#  on this stack (camel-quarkus-support-langchain4j unconditionally enforces #
#  a JAX-RS HTTP client transport that ignores the agent's configured Ollama #
#  base-url). This demo NEVER calls /api/assistant/chat and NEVER asserts    #
#  tool-calling succeeded. It asserts ONLY the embedded MCP server's wire    #
#  protocol surface (tools/list, tools/call) talked to directly as an        #
#  external MCP client would. See _plans/decisions.md (DEF-001) and         #
#  examples/ai-mcp-service/README.md for the full root-cause writeup.        #
################################################################################

BANNER

narrate "Demonstrating the embedded Camel MCP server (camel-quarkus-mcp-server)"
narrate "as seen by an EXTERNAL MCP client speaking the real Streamable HTTP"
narrate "JSON-RPC 2.0 wire protocol -- NOT the broken in-process agent path."

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

step "preflight: Ollama reachable (module classpath requirement)"
wait_http "${OLLAMA_URL}/api/tags" 60 \
    || fail "ollama did not answer at ${OLLAMA_URL}/api/tags within 60s after compose up"
assert_http_200 "${OLLAMA_URL}/api/tags"
info "ollama is reachable"

step "start ai-mcp-service (port ${PORT})"
SVC_PIDFILE="$(svc_start_dev "$MODULE_DIR" "$PORT")"

# No GET-able 200 route on this module (classify/assistant are POST-only,
# /mcp is POST-only -> GET answers 405) -- wait for ANY HTTP response, same
# pattern as demo-ai-triage.sh / demo-ai-classify.sh.
wait_any_http() {
    local url="$1" budget="${2:-60}" i
    for (( i = 0; i < budget; i++ )); do
        curl -s -o /dev/null --max-time 2 "$url" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}
wait_any_http "${BASE_URL}/mcp" 90 \
    || fail "ai-mcp-service did not start listening on ${PORT} within 90s"
info "ai-mcp-service is listening on ${PORT}"

# ─── Minimal real MCP client (Streamable HTTP transport, JSON-RPC 2.0) ──────
# mcp_rpc <session-header-or-empty> <json-rpc-body> — POST one JSON-RPC
# message to /mcp, capture both headers and body. Echoes "<headers-file>
# <body-file>" (two temp file paths) so the caller can inspect both.
mcp_rpc() {
    local session="$1" body="$2" hfile bfile
    hfile="$(mktemp -t demo-ai-mcp-headers-XXXXXX)"
    bfile="$(mktemp -t demo-ai-mcp-body-XXXXXX)"
    if [[ -n "$session" ]]; then
        curl -sS --max-time 20 -D "$hfile" -o "$bfile" \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json, text/event-stream' \
            -H "Mcp-Session-Id: $session" \
            -X POST "$MCP_URL" -d "$body" \
            || fail "MCP POST failed (session=$session body=$body)"
    else
        curl -sS --max-time 20 -D "$hfile" -o "$bfile" \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json, text/event-stream' \
            -X POST "$MCP_URL" -d "$body" \
            || fail "MCP POST failed (body=$body)"
    fi
    echo "$hfile $bfile"
}

# ─── 1. initialize — real MCP handshake ──────────────────────────────────────
step "MCP handshake: POST /mcp {method:\"initialize\"}"
read -r INIT_HFILE INIT_BFILE < <(mcp_rpc "" \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"demo-ai-mcp-client","version":"1.0.0"}}}')
INIT_BODY="$(cat "$INIT_BFILE")"
info "initialize response: $INIT_BODY"
assert_json_field "$INIT_BODY" '.result.serverInfo.name' 'ai-mcp-service'
assert_json_field "$INIT_BODY" '.result.protocolVersion' '2025-06-18'

SESSION_ID="$(grep -i '^Mcp-Session-Id:' "$INIT_HFILE" | tr -d '\r' | awk '{print $2}')"
[[ -n "$SESSION_ID" ]] || fail "no Mcp-Session-Id header in initialize response (headers: $(cat "$INIT_HFILE"))"
info "MCP session established: $SESSION_ID"
rm -f "$INIT_HFILE" "$INIT_BFILE"

step "MCP handshake: notifications/initialized"
read -r NOTIF_HFILE NOTIF_BFILE < <(mcp_rpc "$SESSION_ID" \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}')
NOTIF_STATUS="$(head -n1 "$NOTIF_HFILE" | tr -d '\r')"
[[ "$NOTIF_STATUS" == *" 202 "* ]] || fail "expected HTTP 202 for notifications/initialized, got: $NOTIF_STATUS"
rm -f "$NOTIF_HFILE" "$NOTIF_BFILE"
info "session initialized"

# ─── 2. tools/list — the order-status tool must be published ───────────────
step "MCP: POST /mcp {method:\"tools/list\"} — external client lists tools"
read -r LIST_HFILE LIST_BFILE < <(mcp_rpc "$SESSION_ID" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
LIST_BODY="$(cat "$LIST_BFILE")"
info "tools/list response: $LIST_BODY"
rm -f "$LIST_HFILE" "$LIST_BFILE"

TOOL_NAME="$(jq -r '.result.tools[] | select(.name == "order-status") | .name' <<<"$LIST_BODY" 2>/dev/null)"
[[ "$TOOL_NAME" == "order-status" ]] \
    || fail "MCP tools/list did not include a tool named 'order-status' (response: $LIST_BODY)"
info "external MCP client confirms the 'order-status' tool is published"
assert_json_field "$LIST_BODY" '.result.tools[0].name' 'order-status'
assert_json_field "$LIST_BODY" '.result.tools[0].inputSchema.required[0]' 'orderId'

# ─── 3. tools/call — deterministic fake lookup for ORD-001/002/003 ─────────
# mcp_call_order_status <orderId> — POST a tools/call for order-status and
# echo the PARSED inner JSON payload (the MCP content block's "text" field
# is itself a JSON string -- a double-parse, same shape OrderLookupToolRoute
# hardcodes).
mcp_call_order_status() {
    local order_id="$1" hfile bfile body inner
    read -r hfile bfile < <(mcp_rpc "$SESSION_ID" \
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"order-status\",\"arguments\":{\"orderId\":\"${order_id}\"}}}")
    body="$(cat "$bfile")"
    rm -f "$hfile" "$bfile"
    [[ "$(jq -r '.result.isError' <<<"$body" 2>/dev/null)" == "false" ]] \
        || fail "[$order_id] MCP tools/call reported isError (response: $body)"
    inner="$(jq -r '.result.content[0].text' <<<"$body" 2>/dev/null)" \
        || fail "[$order_id] could not parse tools/call response: $body"
    echo "$inner"
}

step "MCP: POST /mcp {method:\"tools/call\"} order-status for ORD-001/002/003"

narrate "ORD-001 -> expect status=SHIPPED, carrier=FedEx (hardcoded fake lookup)"
ORD001="$(mcp_call_order_status "ORD-001")"
info "order-status(ORD-001) = $ORD001"
assert_json_field "$ORD001" '.orderId' 'ORD-001'
assert_json_field "$ORD001" '.status' 'SHIPPED'
assert_json_field "$ORD001" '.carrier' 'FedEx'

narrate "ORD-002 -> expect status=PROCESSING, warehouse=West Coast Hub"
ORD002="$(mcp_call_order_status "ORD-002")"
info "order-status(ORD-002) = $ORD002"
assert_json_field "$ORD002" '.orderId' 'ORD-002'
assert_json_field "$ORD002" '.status' 'PROCESSING'
assert_json_field "$ORD002" '.warehouse' 'West Coast Hub'

narrate "ORD-003 -> expect status=DELIVERED"
ORD003="$(mcp_call_order_status "ORD-003")"
info "order-status(ORD-003) = $ORD003"
assert_json_field "$ORD003" '.orderId' 'ORD-003'
assert_json_field "$ORD003" '.status' 'DELIVERED'

step "MCP-server surface confirmed"
narrate "An external MCP client (plain curl+jq speaking real JSON-RPC 2.0 over"
narrate "the MCP Streamable HTTP transport) listed the order-status tool and"
narrate "invoked it 3x with deterministic results -- all through the embedded"
narrate "Camel MCP server, zero in-process langchain4j-agent tool-calling"
narrate "anywhere in this demo. DEF-001 remains open and undemonstrated-as-fixed."

demo_ok
