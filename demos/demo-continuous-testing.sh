#!/usr/bin/env bash
#
# demos/demo-continuous-testing.sh — "bare" toolchain demo.
#
# Demonstrates Quarkus continuous testing + Dev Services together: `mvn
# quarkus:dev` on order-service, with continuous testing set to auto-run
# (`quarkus.test.continuous-testing=enabled` — by default it starts
# *paused*, waiting for an interactive `r` keypress, which this
# non-interactive demo can never send), and Dev Services bringing up its own
# Postgres + Kafka + Apicurio Testcontainers with zero compose/.env needed.
#
# What's asserted (primary, strong): the dev-mode console log contains the
# continuous-testing pass banner Quarkus 3.39.5 prints —
#     "All N tests are passing (M skipped), N tests were run in ...ms."
# — parsed for the passing/run counts, asserting run>=1 and passing==run
# (i.e. zero failures). This string was captured from a run of this Quarkus version,
# not taken from the docs.
#
# Fallback (if reliable parsing isn't achievable): if that banner never appears within the budget — e.g. a
# future Quarkus version rewords it — this demo does not silently downgrade
# to a pass. It still asserts dev mode started (HTTP 200 + a real
# JSON array from Dev-Services-backed Postgres via GET /orders) but reports
# the missing continuous-testing banner as a clearly labeled, non-fatal
# DEGRADED result, then still fails the demo
# (continuous testing is the capability under test — "the app came up" alone
# is not sufficient to call this demo a pass). See the final branch below.
#
# ── Known environment gotcha this script works around ──────────────────────
# postgres:18 (this repo's pinned Dev Services image, see
# order-service/application.properties and compose.yaml) rejects legacy
# Olson timezone IDs like "US/Eastern" that pgjdbc forwards from a
# non-UTC-TZ host ("FATAL: invalid value for parameter "TimeZone":
# "US/Eastern"") — confirmed empirically on this host, and already
# documented for the compose stack in compose.yaml ("TZ=UTC / PGTZ=UTC avoid
# the US/Eastern boot failure"). Dev Services doesn't expose a hook to
# set the *container's* TZ, so this script instead sets TZ=UTC on the mvn
# process itself, which changes the JVM's (and therefore pgjdbc's) default
# timezone to one postgres:18 always recognizes. Confirmed fix: identical
# run without TZ=UTC fails every test with that FATAL error; with it, all 4
# tests pass.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-continuous-testing"
require mvn curl jq docker

MODULE_DIR="${EXAMPLES_DIR}/order-service"
PORT=8097
BASE_URL="http://localhost:${PORT}"

step "preflight: docker daemon reachable (Dev Services needs it)"
docker info >/dev/null 2>&1 \
    || fail "docker is on PATH but the daemon is not reachable — start Docker Desktop/the docker service and retry (Dev Services needs a working docker to launch Postgres/Kafka/Apicurio Testcontainers)"
info "docker daemon is reachable"

narrate "starting order-service in 'mvn quarkus:dev' with continuous testing set"
narrate "to auto-run (quarkus.test.continuous-testing=enabled) -- Dev Services will"
narrate "bring up its own Postgres + Kafka + Apicurio containers with zero compose/.env"

export QUARKUS_TEST_CONTINUOUS_TESTING=enabled
# See header comment: works around a real postgres:18 + non-UTC-host TZ
# incompatibility that otherwise FATALs every Dev-Services-backed test.
export TZ=UTC

# Not using the harness's svc_start_dev here: it doesn't hand back its
# logfile path, and this demo needs to grep that log for the
# continuous-testing banner. Same "cd + exec in a backgrounded subshell"
# idiom (so $! is mvn's real PID, no orphaned wrapper -- see svc_start_dev's
# own comment), just with the logfile path kept.
SVC_PIDFILE="$(mktemp -t demo-ct-pid-XXXXXX)"
SVC_LOGFILE="$(mktemp -t demo-ct-log-XXXXXX)"
info "log: $SVC_LOGFILE"
( cd "$MODULE_DIR" && exec mvn -q -Dquarkus.http.port="$PORT" quarkus:dev ) >"$SVC_LOGFILE" 2>&1 &
echo "$!" > "$SVC_PIDFILE"

# Cleanup must run on every exit path (success, fail(), or an unexpected
# error) -- demo_begin already installed the harness's success/failure EXIT
# trap, and bash only honors the LAST `trap ... EXIT` registration, so this
# chains ours in front of it (same idiom as demo-ai-triage.sh): capture the
# real exit code, stop the service, then re-invoke the harness trap so it
# still sees that original code (not svc_stop's always-0 return).
_cleanup_service() {
    local rc=$?
    svc_stop "$SVC_PIDFILE" 2>/dev/null || true
    return "$rc"
}
trap '_cleanup_service; _demo_exit_trap' EXIT

step "waiting for order-service dev mode to start listening on ${PORT}"
wait_http "${BASE_URL}/q/health/live" 180 \
    || fail "order-service dev mode did not answer HTTP within 180s -- see ${SVC_LOGFILE:-<unknown log>}"
assert_http_200 "${BASE_URL}/q/health/live"
info "dev mode is up and healthy"

# Corroborating positive-content check regardless of how the continuous
# testing parse below goes: Dev-Services-backed Postgres is serving
# requests through the full REST+Panache stack, not a bare
# liveness probe.
ORDERS_JSON="$(curl -fsS --max-time 10 "${BASE_URL}/orders")" \
    || fail "GET ${BASE_URL}/orders failed against the Dev-Services-backed app"
echo "$ORDERS_JSON" | jq -e 'type == "array"' >/dev/null \
    || fail "/orders did not return a JSON array: $ORDERS_JSON"
info "GET /orders returned a JSON array (Dev Services Postgres is live): $ORDERS_JSON"

step "waiting for the continuous-testing pass banner"
# Quarkus 3.39.5's ACTUAL wording (confirmed on a real run against this
# module), not the older phrasing from the continuous-testing guide:
#   "All 4 tests are passing (0 skipped), 4 tests were run in 8318ms."
PASS_RE='All ([0-9]+) tests? (are|is) passing \(([0-9]+) skipped\), ([0-9]+) tests? (were|was) run in'
BUDGET=180
FOUND_LINE=""
if [[ -n "$SVC_LOGFILE" && -r "$SVC_LOGFILE" ]]; then
    for (( i = 0; i < BUDGET; i++ )); do
        FOUND_LINE="$(grep -E "$PASS_RE" "$SVC_LOGFILE" | tail -n1 || true)"
        [[ -n "$FOUND_LINE" ]] && break
        sleep 1
    done
fi

if [[ -n "$FOUND_LINE" ]]; then
    [[ "$FOUND_LINE" =~ $PASS_RE ]] \
        || fail "internal error: matched line failed to re-match its own regex: $FOUND_LINE"
    PASSING_COUNT="${BASH_REMATCH[1]}"
    RUN_COUNT="${BASH_REMATCH[4]}"
    info "continuous testing summary: $FOUND_LINE"
    (( RUN_COUNT >= 1 )) \
        || fail "continuous testing reported 0 tests run -- expected OrderResourceTest's 4 tests"
    (( PASSING_COUNT == RUN_COUNT )) \
        || fail "continuous testing reported $PASSING_COUNT passing out of $RUN_COUNT run -- expected all passing (log: ${SVC_LOGFILE})"
    narrate "continuous testing auto-ran and reported ${PASSING_COUNT}/${RUN_COUNT} tests passing"
    demo_ok
else
    # Degraded path -- see header comment. The capability under test
    # (continuous testing reporting a pass) was not observed; app-came-up is
    # real but is not what this demo exists to prove, so it still fails,
    # loudly, with every diagnostic needed to tell a real regression from a
    # wording change in a future Quarkus version.
    warn "DEGRADED: never observed the continuous-testing pass banner (pattern: '$PASS_RE') within ${BUDGET}s"
    warn "dev mode itself DID start and DID serve real HTTP traffic (see above) -- only the"
    warn "continuous-testing parse failed, which is the thing this demo exists to prove"
    if [[ -n "$SVC_LOGFILE" && -r "$SVC_LOGFILE" ]]; then
        warn "last 40 lines of ${SVC_LOGFILE}:"
        tail -n 40 "$SVC_LOGFILE" >&2
    else
        warn "could not even recover the dev-mode logfile path to show diagnostics"
    fi
    fail "continuous-testing pass banner not observed -- see DEGRADED diagnostics above"
fi
