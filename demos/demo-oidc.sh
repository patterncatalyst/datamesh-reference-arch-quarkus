#!/usr/bin/env bash
#
# demos/demo-oidc.sh — Quarkus OIDC bearer-token security, via the Keycloak
# Dev Service. review-service is the smallest module in the project (three
# plain REST endpoints, Postgres as its only other Dev Services dependency,
# no cross-service calls), which made it the right place to add ONE real
# protected endpoint rather than faking the capability.
#
# ── What review-service got, and why the change is minimal ─────────────────
# `quarkus-oidc` was added to review-service's pom.xml with ZERO
# `quarkus.oidc.*` application.properties — with no `auth-server-url`
# configured, Quarkus Dev Services auto-provisions a disposable Keycloak
# container in dev/test (verified via quarkus_searchDocs,
# security-openid-connect-dev-services.adoc "Keycloak initialization"): realm
# `quarkus`, client `quarkus-app`/`secret`, and two builtin accounts —
# alice/alice (roles admin+user) and bob/bob (role user only). One new
# endpoint, `DELETE /reviews/{id}` (admin-only moderation), is annotated
# `@RolesAllowed("admin")`; every existing endpoint (POST/GET /reviews,
# GET /reviews/{id}) is untouched and still unauthenticated. `mvn verify`
# stays green — ReviewResourceTest's 5 existing tests never touch the new
# endpoint, confirmed by an actual run before this demo was written.
#
# ── What this demo proves ────────────────────────────────────────────────
#   1. DELETE with NO bearer token  -> 401 (unauthenticated)
#   2. DELETE with bob's token (user role, no admin) -> 403 (unauthorized —
#      an RBAC check: a token alone is insufficient)
#   3. DELETE with alice's token (admin role) -> 204, and the review is
#      gone (follow-up GET -> 404), which confirms the delete took effect
# All three tokens are obtained from the REAL Keycloak Dev Service via the
# password grant (same idiom as the Quarkus bearer-token-auth-tutorial), not
# faked/mocked — this is a live OIDC round trip end to end.
#
# ── Why `mvn quarkus:dev` + Dev Services, not compose ───────────────────────
# Same rationale as demo-reactive-vertx.sh: review-service's own Dev Services
# (Postgres + — now — Keycloak, both ephemeral Testcontainers) are a complete,
# independent substrate for this one module. No compose baseline, no other
# service, no Kafka/Apicurio dependency here at all.
#
# ── Keycloak port discovery ──────────────────────────────────────────────
# The Keycloak Dev Service container binds its container port 8080 to a
# RANDOM host port (same as Postgres's Dev Services container) — there is no
# fixed URL to curl. This demo greps the dev-mode logfile svc_start_dev
# already captures for the container id Testcontainers assigns
# ("Container quay.io/keycloak/keycloak:... is starting: <id>"), then asks
# `docker port <id> 8080/tcp` for the actual host:port mapping — the same
# "find it, don't guess it" idiom as demo-ai-mcp.sh's Mcp-Session-Id header
# grep.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-oidc"
require curl jq mvn java docker

MODULE_DIR="${EXAMPLES_DIR}/review-service"
HTTP_PORT=8098
BASE_URL="http://localhost:${HTTP_PORT}"

narrate "review-service's DELETE /reviews/{id} is the project's one live OIDC"
narrate "capability demo: a Keycloak Dev Service-backed bearer-token"
narrate "+ @RolesAllowed(\"admin\") check, proven with real tokens end to end."

step "preflight: docker daemon reachable (Dev Services needs it for Postgres + Keycloak)"
docker info >/dev/null 2>&1 \
    || fail "docker is on PATH but the daemon is not reachable -- start Docker Desktop/the docker service and retry"
info "docker daemon is reachable"

# postgres:18 (Dev Services' pinned image) rejects legacy Olson TZ ids like
# "US/Eastern" forwarded by pgjdbc from a non-UTC host -- same fix as
# demo-reactive-vertx.sh/demo-continuous-testing.sh/demo-native.sh.
export TZ=UTC

step "start review-service (mvn quarkus:dev, Dev Services Postgres + Keycloak, HTTP ${HTTP_PORT})"
# svc_start_dev only echoes the pidfile path on stdout -- its logfile path is
# only ever printed via `info "log: $logfile"` on STDERR. Capture that stderr
# stream (still passing it through to the real stderr via `tee`) so this demo
# can recover the exact logfile path for THIS invocation, instead of
# globbing /tmp (which would race with any stale demo-svc-log-* file left
# over from an earlier run).
SVC_STDERR_CAPTURE="$(mktemp -t demo-oidc-svc-stderr-XXXXXX)"
PIDFILE="$(svc_start_dev "$MODULE_DIR" "$HTTP_PORT" 2> >(tee "$SVC_STDERR_CAPTURE" >&2))"
_cleanup() {
    local rc=$?
    svc_stop "$PIDFILE" 2>/dev/null || true
    rm -f "$SVC_STDERR_CAPTURE"
    return "$rc"
}
trap '_cleanup; _demo_exit_trap' EXIT

wait_http "${BASE_URL}/q/health/live" 90 \
    || fail "review-service dev mode did not answer HTTP within 90s"
assert_http_200 "${BASE_URL}/q/health/live"
info "review-service is up (dev mode, Dev Services Postgres + Keycloak)"

# The `tee` behind the process-substitution pipe above is asynchronous --
# retry briefly rather than assume the "log: ..." line has landed in
# $SVC_STDERR_CAPTURE the instant svc_start_dev returns.
SVC_LOGFILE=""
for (( i = 0; i < 10; i++ )); do
    SVC_LOGFILE="$(grep -oE '^\s*log: .*$' "$SVC_STDERR_CAPTURE" 2>/dev/null | head -n1 | sed -E 's/^\s*log: //')"
    [[ -n "$SVC_LOGFILE" && -f "$SVC_LOGFILE" ]] && break
    sleep 0.5
done
[[ -n "$SVC_LOGFILE" && -f "$SVC_LOGFILE" ]] \
    || fail "could not recover the svc_start_dev logfile path from captured stderr ($SVC_STDERR_CAPTURE)"
info "service logfile: $SVC_LOGFILE"

step "discover the Keycloak Dev Service container + its random host port"
# Wait for the "Dev Services for Keycloak started." line -- Keycloak takes
# noticeably longer to boot than Postgres (10-15s is typical).
KC_READY=0
for (( i = 0; i < 60; i++ )); do
    grep -q "Dev Services for Keycloak started" "$SVC_LOGFILE" 2>/dev/null && { KC_READY=1; break; }
    sleep 1
done
(( KC_READY == 1 )) \
    || fail "Keycloak Dev Service did not report ready within 60s (log: $SVC_LOGFILE)"
info "Keycloak Dev Service reported ready"

KC_CONTAINER_ID="$(grep -oE 'keycloak/keycloak:[^]]+ is starting: [0-9a-f]+' "$SVC_LOGFILE" \
    | head -n1 | awk '{print $NF}')"
[[ -n "$KC_CONTAINER_ID" ]] \
    || fail "could not find the Keycloak container id in $SVC_LOGFILE"
info "Keycloak Dev Service container: $KC_CONTAINER_ID"

KC_HOST_PORT="$(docker port "$KC_CONTAINER_ID" 8080/tcp 2>/dev/null | head -n1 | sed -E 's/.*:([0-9]+)$/\1/')"
[[ -n "$KC_HOST_PORT" ]] \
    || fail "docker port $KC_CONTAINER_ID 8080/tcp returned no mapping"
info "Keycloak Dev Service reachable at localhost:${KC_HOST_PORT}"

TOKEN_URL="http://localhost:${KC_HOST_PORT}/realms/quarkus/protocol/openid-connect/token"

# get_token <username> <password> — real password-grant round trip against
# the live Keycloak Dev Service (default realm "quarkus", client
# "quarkus-app"/"secret" -- Quarkus Dev Services builtin defaults, no custom
# realm file). Echoes the access_token.
get_token() {
    local user="$1" pass="$2" resp token
    resp="$(curl -sS --max-time 15 -X POST "$TOKEN_URL" \
        --user quarkus-app:secret \
        -d "username=${user}&password=${pass}&grant_type=password")" \
        || fail "token request for user '$user' failed"
    token="$(jq -r '.access_token // empty' <<<"$resp" 2>/dev/null)"
    [[ -n "$token" ]] || fail "no access_token in Keycloak response for user '$user': $resp"
    echo "$token"
}

step "password grant: real tokens for alice (admin+user) and bob (user only)"
ALICE_TOKEN="$(get_token alice alice)"
info "alice token acquired (admin+user roles)"
BOB_TOKEN="$(get_token bob bob)"
info "bob token acquired (user role only)"

step "seed a review to delete (unauthenticated POST /reviews -- unchanged by OIDC)"
CREATE_BODY='{"sku":"SKU-OIDC-DEMO","rating":4,"reviewer":"demo-oidc","comment":"created for the OIDC demo, will be deleted"}'
CREATE_RESP="$(curl -fsS --max-time 10 -X POST "${BASE_URL}/reviews" \
    -H 'Content-Type: application/json' -d "$CREATE_BODY")" \
    || fail "seeding the review to delete failed"
info "created: $CREATE_RESP"
REVIEW_ID="$(jq -r '.id // empty' <<<"$CREATE_RESP")"
[[ -n "$REVIEW_ID" ]] || fail "could not parse review id from create response: $CREATE_RESP"
assert_json_field "$CREATE_RESP" '.sku' 'SKU-OIDC-DEMO'
info "seeded review id=$REVIEW_ID"

step "1/3 -- DELETE with no bearer token: expect 401 (unauthenticated)"
CODE_NOAUTH="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X DELETE "${BASE_URL}/reviews/${REVIEW_ID}")"
info "DELETE /reviews/${REVIEW_ID} (no token) -> HTTP $CODE_NOAUTH"
[[ "$CODE_NOAUTH" == "401" ]] \
    || fail "expected 401 for DELETE with no bearer token, got $CODE_NOAUTH"
narrate "confirmed: no token -> 401, the endpoint requires authentication"

step "2/3 -- DELETE with bob's token (user role, not admin): expect 403 (unauthorized)"
CODE_FORBIDDEN="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X DELETE "${BASE_URL}/reviews/${REVIEW_ID}" \
    -H "Authorization: Bearer ${BOB_TOKEN}")"
info "DELETE /reviews/${REVIEW_ID} (bob token) -> HTTP $CODE_FORBIDDEN"
[[ "$CODE_FORBIDDEN" == "403" ]] \
    || fail "expected 403 for DELETE with a valid-but-insufficient-role token, got $CODE_FORBIDDEN"
narrate "confirmed: a valid token without the admin role -> 403, this is RBAC: a valid token alone is insufficient"

step "3/3 -- DELETE with alice's token (admin role): expect 204, then confirm the review is gone"
CODE_AUTHORIZED="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X DELETE "${BASE_URL}/reviews/${REVIEW_ID}" \
    -H "Authorization: Bearer ${ALICE_TOKEN}")"
info "DELETE /reviews/${REVIEW_ID} (alice token) -> HTTP $CODE_AUTHORIZED"
[[ "$CODE_AUTHORIZED" == "204" ]] \
    || fail "expected 204 for DELETE with a valid admin-role token, got $CODE_AUTHORIZED"
narrate "confirmed: a token with the admin role -> 204, the DELETE was accepted"

CODE_GONE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${BASE_URL}/reviews/${REVIEW_ID}")"
info "GET /reviews/${REVIEW_ID} after delete -> HTTP $CODE_GONE"
[[ "$CODE_GONE" == "404" ]] \
    || fail "expected 404 after the authorized delete, got $CODE_GONE -- the DELETE did not take effect"
narrate "confirmed: the review row is gone (follow-up GET returned 404)"

step "live OIDC + Keycloak Dev Service demo confirmed"
narrate "Three real password-grant tokens from a disposable Keycloak Dev Service"
narrate "container (random host port, discovered via docker port) drove one"
narrate "@RolesAllowed(\"admin\") endpoint through all three outcomes: 401 (no"
narrate "token), 403 (wrong role), 204+404-after (right role, real effect)."
narrate "This is the live OIDC path, proven end to end rather than deferred."

demo_ok
