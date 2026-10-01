#!/usr/bin/env bash
#
# demos/demo-camel-integration.sh — Phase D step 10.5: Quarkus + Camel EIP
# ("A Camel route correctly transforms/routes a message end-to-end through
# its EIPs" — demos/README.md).
#
# Subject: OrderLookupToolRoute (examples/ai-mcp-service), a
# from("ai-tool:order-status?...") route whose body is a textbook Content-
# Based Router EIP (.choice()/.when()/.when()/.when()/.otherwise()) that
# inspects the ${header.orderId} the MCP layer hands it and routes to one of
# four distinct, statically-defined response bodies. This demo is
# Camel/EIP-focused: it asserts the ROUTING LOGIC is correct across ALL FOUR
# branches, including the .otherwise() fallback for an order id none of the
# .when() predicates match — a branch demo-ai-mcp.sh does not exercise
# (that demo only smoke-tests ORD-001/002/003 as part of proving the MCP
# server surface works; this demo is the one that actually proves the
# Content-Based Router EIP itself transforms/routes correctly end to end,
# including the negative case).
#
# Why reach it through /mcp at all? ai-tool: is a Camel component consumed
# by registered callers in the shared AiToolRegistry — there is no plain
# REST endpoint for it. The only two consumers wired in this module are the
# in-process langchain4j-agent (OrderAssistantRoute — broken by DEF-001, see
# demo-ai-mcp.sh's caveat banner) and the embedded Camel MCP server
# (camel-quarkus-mcp-server). The MCP server's tools/call JSON-RPC method is
# therefore the only HTTP-reachable way to actually invoke this route from
# outside the JVM, and crucially it is a STRUCTURALLY SEPARATE code path
# from the broken in-process agent (no langchain4j-agent, no in-process tool
# calling anywhere in this demo) — so routing a message through it here is
# not a DEF-001 regression risk.
#
# Infra: this demo OWNS the compose ollama-profile lifecycle itself
# (compose_up ollama / compose_down), per the "compose + --profile ollama"
# demo group in demos/README.md (ai-mcp-service's quarkus-langchain4j-ollama
# extension is on the classpath even though this specific route never calls
# an LLM — the four responses OrderLookupToolRoute returns are hardcoded).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-camel-integration"
require curl jq docker mvn java

MODULE_DIR="${EXAMPLES_DIR}/ai-mcp-service"
PORT=8088
BASE_URL="http://localhost:${PORT}"
MCP_URL="${BASE_URL}/mcp"
OLLAMA_URL="http://localhost:11434"

narrate "Camel EIP under test: OrderLookupToolRoute's Content-Based Router"
narrate "(.choice()/.when()/.otherwise()) — 4 branches, reached via the"
narrate "embedded MCP server's tools/call (the only HTTP-reachable entry"
narrate "point into an ai-tool: route). No langchain4j-agent anywhere here."

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
# Same protocol as demo-ai-mcp.sh (duplicated per this repo's house style of
# self-contained demo-*.sh scripts, not shared beyond lib/_demo.sh) — see
# that script's header comment for how the endpoint/protocol were confirmed.
mcp_rpc() {
    local session="$1" body="$2" hfile bfile
    hfile="$(mktemp -t demo-camel-eip-headers-XXXXXX)"
    bfile="$(mktemp -t demo-camel-eip-body-XXXXXX)"
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

step "MCP handshake (prerequisite plumbing — not the thing under test)"
read -r INIT_HFILE INIT_BFILE < <(mcp_rpc "" \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"demo-camel-integration","version":"1.0.0"}}}')
INIT_BODY="$(cat "$INIT_BFILE")"
assert_json_field "$INIT_BODY" '.result.serverInfo.name' 'ai-mcp-service'
SESSION_ID="$(grep -i '^Mcp-Session-Id:' "$INIT_HFILE" | tr -d '\r' | awk '{print $2}')"
[[ -n "$SESSION_ID" ]] || fail "no Mcp-Session-Id header in initialize response"
rm -f "$INIT_HFILE" "$INIT_BFILE"

read -r NOTIF_HFILE NOTIF_BFILE < <(mcp_rpc "$SESSION_ID" '{"jsonrpc":"2.0","method":"notifications/initialized"}')
rm -f "$NOTIF_HFILE" "$NOTIF_BFILE"
info "MCP session established ($SESSION_ID) — now exercising the EIP itself"

# route_order_status <orderId> — invoke the Content-Based Router with a given
# orderId and echo the PARSED inner JSON body (double-parse: the MCP content
# block's "text" field is itself a JSON string — the literal body
# OrderLookupToolRoute's .choice() branch set with setBody(constant(...))).
route_order_status() {
    local order_id="$1" hfile bfile body inner
    read -r hfile bfile < <(mcp_rpc "$SESSION_ID" \
        "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"order-status\",\"arguments\":{\"orderId\":\"${order_id}\"}}}")
    body="$(cat "$bfile")"
    rm -f "$hfile" "$bfile"
    [[ "$(jq -r '.result.isError' <<<"$body" 2>/dev/null)" == "false" ]] \
        || fail "[$order_id] route returned isError (response: $body)"
    inner="$(jq -r '.result.content[0].text' <<<"$body" 2>/dev/null)" \
        || fail "[$order_id] could not parse route response: $body"
    echo "$inner"
}

step "Content-Based Router EIP — branch 1 of 4: \${header.orderId} == 'ORD-001'"
narrate "expect the route to transform the message into the SHIPPED/FedEx body"
R1="$(route_order_status "ORD-001")"
info "routed body: $R1"
assert_json_field "$R1" '.status' 'SHIPPED'
assert_json_field "$R1" '.carrier' 'FedEx'

step "Content-Based Router EIP — branch 2 of 4: \${header.orderId} == 'ORD-002'"
narrate "expect the route to transform the message into the PROCESSING body"
R2="$(route_order_status "ORD-002")"
info "routed body: $R2"
assert_json_field "$R2" '.status' 'PROCESSING'
assert_json_field "$R2" '.warehouse' 'West Coast Hub'

step "Content-Based Router EIP — branch 3 of 4: \${header.orderId} == 'ORD-003'"
narrate "expect the route to transform the message into the DELIVERED body"
R3="$(route_order_status "ORD-003")"
info "routed body: $R3"
assert_json_field "$R3" '.status' 'DELIVERED'

step "Content-Based Router EIP — branch 4 of 4: .otherwise() fallback"
narrate "an order id matching NONE of the .when() predicates must fall through"
narrate "to the .otherwise() branch — expect {\"error\":\"Order not found\"}"
R4="$(route_order_status "ORD-NO-SUCH-ORDER")"
info "routed body: $R4"
assert_json_field "$R4" '.error' 'Order not found'

step "EIP routing confirmed end to end"
narrate "All 4 branches of OrderLookupToolRoute's Content-Based Router"
narrate "(.choice()/.when()x3/.otherwise()) correctly transformed the inbound"
narrate "message's orderId into the matching canned response — including the"
narrate "negative/fallback case. Zero langchain4j-agent / in-process tool"
narrate "calling involved; this exercises the Camel route logic itself."

demo_ok
