#!/usr/bin/env bash
#
# demos/demo-native.sh — "bare" toolchain demo.
#
# *** LONG-RUNNING / OPT-IN. *** A real GraalVM/Mandrel native compile of
# order-service. This is not part of any default/fast demo run (and is not
# wired into walkthrough.sh's default acts) — invoke it explicitly, and
# expect it to take several minutes (longer still the first time a
# container-build builder image has to be pulled, which can be 1-2GB).
#
# Builds ONE service — order-service, the smallest clean REST+Panache
# service in the project — to a native executable, then boots the produced
# binary directly (bypassing the JVM entirely: no `java`, no quarkus-run.jar)
# and asserts it serves real HTTP 200 traffic through the full
# REST+Hibernate ORM+Panache stack.
#
# ── Toolchain preflight (never fakes success) ───────────────────────────────
# Tries a LOCAL GraalVM/Mandrel `native-image` first (fastest, no container
# overhead); falls back to Quarkus's own `quarkus.native.container-build=true`
# (needs a working `docker`) if no local native-image is found. If NEITHER is
# available this demo FAILS with an explicit message — it never silently
# builds a JVM jar instead and calls that "native".
#
# ── Why this demo also starts a throwaway Postgres container ───────────────
# order-service's `%prod` profile (which native/packaged mode always runs
# under) is wired for a real external Postgres
# (order-service/application.properties:
# `%prod.quarkus.datasource.jdbc.url=${JDBC_URL:jdbc:postgresql://postgres:5432/orderdb}`)
# — unlike `quarkus:dev`/tests, native mode gets NO Dev Services. Its
# `quarkus.hibernate-orm.schema-management.strategy=drop-and-create` setting
# applies in every profile and runs eagerly at boot, so the native binary
# will only boot successfully (and only serve a real GET /orders) against a
# real, reachable Postgres. demos/README.md documents this capability group
# as "no docker compose needed" — true here: this starts one throwaway
# `docker run` Postgres container scoped to this demo's own lifecycle (not
# the repo's compose.yaml stack, no profiles, no .env), and tears it down on
# exit. Docker is already a hard dependency of this demo's container-build
# fallback path anyway.
#
# KAFKA_BOOTSTRAP_SERVERS / APICURIO_REGISTRY_URL are also overridden to
# `localhost:<unused port>` rather than left at their `kafka`/`apicurio`
# compose-network-only defaults: those hostnames don't resolve on the bare
# host, and an unresolvable bootstrap host can make some Kafka client paths
# fail fast at startup (unlike a resolvable-but-refused address, which the
# reactive-messaging Kafka connector retries lazily in the background — a
# real limitation of running order-service "bare" that's being worked around here).
#
# ── Known environment gotcha ─────────────────────────────────────────────────
# postgres:18 rejects legacy Olson timezone IDs like "US/Eastern" that pgjdbc
# forwards as the session TimeZone from a non-UTC-TZ CLIENT (confirmed
# empirically on this host -- including against the native binary itself:
# a native executable still reads the host's TZ the same way a JVM does).
# The throwaway Postgres container's own TZ=UTC/PGTZ=UTC does not fix this --
# postgres:18's image has no "US/Eastern" zoneinfo entry at all, no
# matter what timezone the server itself runs in -- so the fix has to be on
# the client side: TZ=UTC is set on the native runner process below, same
# fix (and same root cause) as demo-continuous-testing.sh's TZ=UTC export,
# and the same one already documented in compose.yaml for the full stack.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-native"
require mvn curl jq docker

MODULE_DIR="${EXAMPLES_DIR}/order-service"
APP_PORT=8098
BASE_URL="http://localhost:${APP_PORT}"

PG_CONTAINER="demo-native-order-pg-$$"
PG_PORT=15433
PG_DB=orderdb
PG_USER=appuser
PG_PASSWORD=apppass

# ─── Toolchain preflight ─────────────────────────────────────────────────────
step "preflight: native toolchain"
HAVE_LOCAL_NATIVE=0
if command -v native-image >/dev/null 2>&1; then
    HAVE_LOCAL_NATIVE=1
    info "found local native-image on PATH: $(command -v native-image)"
elif [[ -n "${GRAALVM_HOME:-}" && -x "${GRAALVM_HOME}/bin/native-image" ]]; then
    HAVE_LOCAL_NATIVE=1
    info "found local native-image via GRAALVM_HOME: ${GRAALVM_HOME}/bin/native-image"
else
    info "no local native-image on PATH or \$GRAALVM_HOME"
fi

HAVE_CONTAINER_BUILD=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    HAVE_CONTAINER_BUILD=1
    info "docker is available and reachable -- quarkus.native.container-build=true is viable"
else
    info "docker is not available/reachable -- container-build fallback is not viable"
fi

if (( HAVE_LOCAL_NATIVE == 0 && HAVE_CONTAINER_BUILD == 0 )); then
    fail "no native toolchain available: no local GraalVM/Mandrel 'native-image' on PATH or \$GRAALVM_HOME, AND no working docker for quarkus.native.container-build. Install ONE of: (1) a GraalVM/Mandrel distribution for JDK 25 with native-image on PATH (e.g. 'sdk install java 25.<x>-graalce && sdk use java 25.<x>-graalce && gu install native-image', or a Mandrel-for-JDK25 distribution); or (2) Docker Engine so Quarkus can run the native build inside its quay.io/quarkus Mandrel builder container. This demo does not build a JVM-mode substitute and call it native."
fi

NATIVE_BUILD_ARGS=(-Pnative -pl order-service -am -DskipTests package)
if (( HAVE_LOCAL_NATIVE == 1 )); then
    narrate "building order-service native with a LOCAL GraalVM/Mandrel native-image"
else
    narrate "no local native-image found -- building order-service native via"
    narrate "quarkus.native.container-build=true (docker). This pulls a Mandrel"
    narrate "builder image on first use (~1-2GB) and can take several minutes."
    # Pin the builder image: Quarkus's default is the floating
    # ubi9-quarkus-mandrel-builder-image:jdk-25. This is the newest UBI 10
    # Mandrel for JDK 25, the same one openshift/platform/native/Containerfile uses.
    NATIVE_BUILD_ARGS+=(-Dquarkus.native.container-build=true
        -Dquarkus.native.builder-image=quay.io/quarkus/ubi10-quarkus-mandrel-builder-image:jdk-25.0.4.1)
fi

BUILD_LOGFILE="$(mktemp -t demo-native-build-log-XXXXXX)"
info "log: $BUILD_LOGFILE"
step "mvn ${NATIVE_BUILD_ARGS[*]} (run from examples/ -- this is the slow part)"

BUILD_START=$(date +%s)
if ! ( cd "$EXAMPLES_DIR" && mvn "${NATIVE_BUILD_ARGS[@]}" ) >"$BUILD_LOGFILE" 2>&1; then
    tail -n 100 "$BUILD_LOGFILE" >&2
    fail "native build failed -- see $BUILD_LOGFILE"
fi
BUILD_SECS=$(( $(date +%s) - BUILD_START ))
narrate "native build completed in ${BUILD_SECS}s"

RUNNER_BIN="$(ls "${MODULE_DIR}"/target/*-runner 2>/dev/null | head -n1)"
[[ -n "$RUNNER_BIN" && -x "$RUNNER_BIN" ]] \
    || fail "expected a native runner binary at ${MODULE_DIR}/target/*-runner but none was found/executable -- see $BUILD_LOGFILE"
info "native runner binary: $RUNNER_BIN ($(du -h "$RUNNER_BIN" | cut -f1))"

# ─── Throwaway Postgres for the native binary's %prod datasource ───────────
# See header comment: native mode gets no Dev Services, and
# schema-management.strategy=drop-and-create needs a real, reachable
# Postgres to even boot. --rm so a `docker stop` is the only cleanup needed.
step "starting a throwaway Postgres container for the native run"
docker run -d --rm \
    --name "$PG_CONTAINER" \
    -e TZ=UTC -e PGTZ=UTC \
    -e POSTGRES_USER="$PG_USER" \
    -e POSTGRES_PASSWORD="$PG_PASSWORD" \
    -e POSTGRES_DB="$PG_DB" \
    -p "${PG_PORT}:5432" \
    docker.io/library/postgres:18.6 >/dev/null \
    || fail "failed to start throwaway Postgres container ($PG_CONTAINER) for the native run"
info "postgres container: $PG_CONTAINER (host port $PG_PORT)"

RUNNER_PID=""
_cleanup_native_run() {
    local rc=$?
    [[ -n "$RUNNER_PID" ]] && kill "$RUNNER_PID" 2>/dev/null
    [[ -n "$RUNNER_PID" ]] && wait "$RUNNER_PID" 2>/dev/null
    docker stop "$PG_CONTAINER" >/dev/null 2>&1 || true
    return "$rc"
}
# Chains in front of the harness's success/failure EXIT trap (installed by
# demo_begin) -- bash only keeps the LAST `trap EXIT` registration, so this
# re-invokes it explicitly after our own cleanup, same idiom as
# demo-ai-triage.sh / demo-continuous-testing.sh.
trap '_cleanup_native_run; _demo_exit_trap' EXIT

for (( i = 0; i < 30; i++ )); do
    docker exec "$PG_CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1 && break
    sleep 1
done
docker exec "$PG_CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1 \
    || fail "throwaway Postgres container did not become ready within 30s"
info "throwaway Postgres is ready"

# ─── Boot the native binary directly (no JVM) ──────────────────────────────
step "boot the native binary and assert HTTP 200"
RUN_LOGFILE="$(mktemp -t demo-native-run-log-XXXXXX)"
info "log: $RUN_LOGFILE"

( exec env \
    TZ=UTC \
    JDBC_URL="jdbc:postgresql://localhost:${PG_PORT}/${PG_DB}" \
    DB_USERNAME="$PG_USER" \
    DB_PASSWORD="$PG_PASSWORD" \
    KAFKA_BOOTSTRAP_SERVERS="localhost:19999" \
    APICURIO_REGISTRY_URL="http://localhost:19999/apis/registry/v3" \
    "$RUNNER_BIN" -Dquarkus.http.port="$APP_PORT" \
) >"$RUN_LOGFILE" 2>&1 &
RUNNER_PID=$!

wait_http "${BASE_URL}/q/health/live" 60 \
    || { tail -n 60 "$RUN_LOGFILE" >&2; fail "native binary did not answer HTTP within 60s -- see $RUN_LOGFILE"; }
assert_http_200 "${BASE_URL}/q/health/live"
info "native binary is up and serving HTTP on ${APP_PORT}"

ORDERS_JSON="$(curl -fsS --max-time 10 "${BASE_URL}/orders")" \
    || { tail -n 60 "$RUN_LOGFILE" >&2; fail "GET ${BASE_URL}/orders failed against the native binary"; }
echo "$ORDERS_JSON" | jq -e 'type == "array"' >/dev/null \
    || fail "/orders did not return a JSON array from the native binary: $ORDERS_JSON"
info "GET /orders returned a JSON array from the native binary: $ORDERS_JSON"

narrate "native binary booted (${BUILD_SECS}s build) and served HTTP + Postgres traffic with zero JVM"
demo_ok
