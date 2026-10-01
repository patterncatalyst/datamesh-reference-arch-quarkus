#!/usr/bin/env bash
#
# compare-quarkus-springboot.sh — DRQ-006: reproducible JVM startup-time and
# memory comparison between the Quarkus order-service and its Spring Boot
# twin (examples/spring-boot-compare), so tutorial chapter 12 can cite
# MEASURED numbers.
#
# *** JVM-ONLY. *** There is no native/GraalVM mode in this script. It builds
# and boots the plain JVM artifact for each service, measures wall-clock
# startup time and post-startup RSS, and prints a two-row comparison table.
# Any cell it could not measure in a given run prints the literal placeholder
# `<measured-on-run>` — this script NEVER fabricates a number.
#
# ── What is measured, identically for both services ─────────────────────────
#   jvm-startup — wall-clock seconds from process launch to the first HTTP
#                 200 from the service's health endpoint (order-service:
#                 /q/health, spring-boot-compare: /actuator/health),
#                 cross-checked (best-effort, informational only) against the
#                 "started in Xs" / "Started ... in X seconds" log line.
#   jvm-rss     — RSS immediately after that first 200, read from
#                 /proc/<pid>/status VmRSS, falling back to `ps -o rss=`.
#
# Both services are launched against the SAME throwaway `postgres:18`
# container (TZ=UTC/PGTZ=UTC), with the SAME JVM system properties:
#   -Dorg.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1 -Duser.timezone=UTC
#
# ── Honesty note (dependency surface) ────────────────────────────────────────
# Both services carry the SAME dependency surface: REST + JPA/Hibernate ORM +
# health + Kafka/Avro producer + a gRPC client to inventory-service. No
# exclusion caveat is needed. The gRPC channel initializes lazily, so these
# startup/RSS numbers do NOT require inventory-service to be running —
# exercising POST /orders end-to-end would additionally need it up, but that
# is out of scope for this script.
#
# ── Prerequisites ─────────────────────────────────────────────────────────────
#   - docker (throwaway Postgres container)
#   - mvn, curl, jq on PATH
#   - examples/domain-model and examples/contracts installed to the local
#     repo first (spring-boot-compare is a standalone Maven project, not a
#     module of the examples/ reactor): this script runs
#     `mvn -pl domain-model,contracts -am install -DskipTests` itself before
#     building spring-boot-compare, so a fresh checkout works unattended.
#
# Usage:
#   scripts/compare-quarkus-springboot.sh [--help]
#
# Exits non-zero (via the shared demo-lib fail()/trap convention) on any
# build or boot failure — it does not silently skip a service that should
# have worked. A missing/absent TOOLCHAIN is not a thing in JVM-only mode;
# the only legitimate "could not measure" case is a hard failure, which this
# script surfaces loudly rather than papering over.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../demos/lib/_demo.sh
source "${SCRIPT_DIR}/../demos/lib/_demo.sh"

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: scripts/compare-quarkus-springboot.sh [--help]

Builds and boots (JVM mode only — no native/GraalVM) order-service (Quarkus)
and examples/spring-boot-compare (Spring Boot) one at a time against the same
throwaway postgres:18 container, measures wall-clock startup time and
post-startup RSS for each, and prints an aligned comparison table suitable
for pasting into tutorial chapter 12.

Options:
  --help    Show this help and exit.

Unmeasured cells always print the literal placeholder "<measured-on-run>" —
this script never invents a number.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown argument: %s\n\n' "$arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done

demo_begin "compare-quarkus-springboot"
require mvn curl jq docker

ORDER_SERVICE_DIR="${EXAMPLES_DIR}/order-service"
SPRING_COMPARE_DIR="${EXAMPLES_DIR}/spring-boot-compare"

[[ -f "${ORDER_SERVICE_DIR}/pom.xml" ]] \
    || fail "order-service not found at ${ORDER_SERVICE_DIR} (expected examples/order-service/pom.xml)"
[[ -f "${SPRING_COMPARE_DIR}/pom.xml" ]] \
    || fail "spring-boot-compare not found at ${SPRING_COMPARE_DIR} (expected examples/spring-boot-compare/pom.xml) -- it is built separately (DRQ-006); run this script again once it exists"

AVRO_SERIALIZABLE_PACKAGES="capstone.order.v1"
JVM_PROPS=(-Dorg.apache.avro.SERIALIZABLE_PACKAGES="$AVRO_SERIALIZABLE_PACKAGES" -Duser.timezone=UTC)

Q_PORT=8095
S_PORT=8096
Q_BASE_URL="http://localhost:${Q_PORT}"
S_BASE_URL="http://localhost:${S_PORT}"

PG_CONTAINER="compare-qs-pg-$$"
PG_PORT=15434
PG_DB=orderdb
PG_USER=appuser
PG_PASSWORD=apppass

# ─── Result placeholders — overwritten only when actually measured ─────────
Q_JVM_STARTUP="<measured-on-run>"
Q_JVM_RSS="<measured-on-run>"
S_JVM_STARTUP="<measured-on-run>"
S_JVM_RSS="<measured-on-run>"

# ─── Helpers ─────────────────────────────────────────────────────────────────

# extract_started_in <logfile> — best-effort cross-check only: pulls the
# number out of a "started in Xs" (Quarkus) or "Started ... in X seconds"
# (Spring Boot) log line. Prints nothing (not a failure) if no such line is
# found — callers must never treat an empty result as an error.
extract_started_in() {
    local logfile="$1"
    grep -Eio '[Ss]tarted[^0-9]*[0-9]+\.[0-9]+ ?s(econds)?' "$logfile" 2>/dev/null \
        | tail -n1 \
        | grep -Eo '[0-9]+\.[0-9]+' \
        | tail -n1 || true
}

# get_rss_kb <pid> — RSS in KB via /proc, falling back to ps. Prints nothing
# (not a failure) if neither source is readable.
get_rss_kb() {
    local pid="$1" kb=""
    if [[ -r "/proc/${pid}/status" ]]; then
        kb="$(awk '/^VmRSS:/{print $2; exit}' "/proc/${pid}/status" 2>/dev/null || true)"
    fi
    if [[ -z "$kb" ]]; then
        kb="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
    fi
    printf '%s' "$kb"
}

fmt_secs_ms() {
    local ms="$1"
    awk -v m="$ms" 'BEGIN { printf "%.2fs", m / 1000 }'
}

fmt_rss_kb() {
    local kb="$1"
    if [[ -z "$kb" ]]; then
        printf '<measured-on-run>'
    else
        awk -v k="$kb" 'BEGIN { printf "%.0f MB", k / 1024 }'
    fi
}

CURRENT_PID=""

# stop_current — TERM, wait up to 5s, then KILL. Safe to call with no process
# launched (no-op).
stop_current() {
    [[ -n "$CURRENT_PID" ]] || return 0
    kill "$CURRENT_PID" 2>/dev/null || true
    local i
    for ((i = 0; i < 10; i++)); do
        kill -0 "$CURRENT_PID" 2>/dev/null || break
        sleep 0.5
    done
    if kill -0 "$CURRENT_PID" 2>/dev/null; then
        kill -9 "$CURRENT_PID" 2>/dev/null || true
    fi
    wait "$CURRENT_PID" 2>/dev/null || true
    CURRENT_PID=""
}

# run_and_measure <health-url> <logfile> <cmd...> — launches <cmd...> in the
# background (via a subshelled `exec` so $! is the real target PID, same
# idiom as demos/demo-native.sh), waits for the first HTTP 200 on
# <health-url>, and sets RESULT_STARTUP_MS / RESULT_RSS_KB / RESULT_LOG_SECS.
# Hard-fails (via the shared fail()) if the service never answers — a boot
# failure is a real problem to surface, not a cell to leave blank.
RESULT_STARTUP_MS=""
RESULT_RSS_KB=""
RESULT_LOG_SECS=""
run_and_measure() {
    local health_url="$1" logfile="$2"
    shift 2
    local start_ms end_ms
    start_ms="$(date +%s%3N)"
    ( exec "$@" ) >"$logfile" 2>&1 &
    CURRENT_PID=$!
    if ! wait_http "$health_url" 90; then
        tail -n 60 "$logfile" >&2
        fail "service did not answer ${health_url} within 90s -- see $logfile"
    fi
    assert_http_200 "$health_url"
    end_ms="$(date +%s%3N)"
    RESULT_STARTUP_MS=$(( end_ms - start_ms ))
    RESULT_RSS_KB="$(get_rss_kb "$CURRENT_PID")"
    RESULT_LOG_SECS="$(extract_started_in "$logfile")"
}

# ─── Cleanup (always runs) ───────────────────────────────────────────────────
_cleanup_compare() {
    local rc=$?
    stop_current
    docker stop "$PG_CONTAINER" >/dev/null 2>&1 || true
    return "$rc"
}
# bash only keeps the LAST `trap EXIT` registration -- chain in front of the
# harness's own trap (installed by demo_begin), same idiom as demo-native.sh.
trap '_cleanup_compare; _demo_exit_trap' EXIT

# ─── Throwaway Postgres (shared by both services, sequentially) ────────────
step "starting a throwaway Postgres container for both runs"
docker run -d --rm \
    --name "$PG_CONTAINER" \
    -e TZ=UTC -e PGTZ=UTC \
    -e POSTGRES_USER="$PG_USER" \
    -e POSTGRES_PASSWORD="$PG_PASSWORD" \
    -e POSTGRES_DB="$PG_DB" \
    -p "${PG_PORT}:5432" \
    postgres:18 >/dev/null \
    || fail "failed to start throwaway Postgres container ($PG_CONTAINER)"
info "postgres container: $PG_CONTAINER (host port $PG_PORT)"

for (( i = 0; i < 30; i++ )); do
    docker exec "$PG_CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1 && break
    sleep 1
done
docker exec "$PG_CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1 \
    || fail "throwaway Postgres container did not become ready within 30s"
info "throwaway Postgres is ready"

JDBC_URL="jdbc:postgresql://localhost:${PG_PORT}/${PG_DB}"

# ═══ order-service (Quarkus) ════════════════════════════════════════════════
step "building order-service (JVM)"
BUILD_LOG="$(mktemp -t compare-qs-build-order-XXXXXX)"
info "log: $BUILD_LOG"
if ! ( cd "$EXAMPLES_DIR" && mvn -pl order-service -am -DskipTests package ) >"$BUILD_LOG" 2>&1; then
    tail -n 100 "$BUILD_LOG" >&2
    fail "order-service build failed -- see $BUILD_LOG"
fi
Q_JAR="${ORDER_SERVICE_DIR}/target/quarkus-app/quarkus-run.jar"
[[ -f "$Q_JAR" ]] || fail "expected ${Q_JAR} after build but it was not found -- see $BUILD_LOG"
narrate "order-service built: $Q_JAR"

step "booting order-service (JVM) and measuring startup + RSS"
RUN_LOG="$(mktemp -t compare-qs-run-order-XXXXXX)"
info "log: $RUN_LOG"
run_and_measure "${Q_BASE_URL}/q/health" "$RUN_LOG" \
    env TZ=UTC \
        JDBC_URL="$JDBC_URL" \
        DB_USERNAME="$PG_USER" \
        DB_PASSWORD="$PG_PASSWORD" \
        KAFKA_BOOTSTRAP_SERVERS="localhost:19999" \
        APICURIO_REGISTRY_URL="http://localhost:19999/apis/registry/v3" \
    java "${JVM_PROPS[@]}" -Dquarkus.http.port="$Q_PORT" -jar "$Q_JAR"
Q_JVM_STARTUP="$(fmt_secs_ms "$RESULT_STARTUP_MS")"
Q_JVM_RSS="$(fmt_rss_kb "$RESULT_RSS_KB")"
info "order-service: wall-clock ${Q_JVM_STARTUP}, app-reported ${RESULT_LOG_SECS:-n/a}s, RSS ${Q_JVM_RSS}"
stop_current

# ═══ spring-boot-compare (Spring Boot) ══════════════════════════════════════
step "installing domain-model + contracts (prereq for the standalone spring-boot-compare build)"
INSTALL_LOG="$(mktemp -t compare-qs-install-shared-XXXXXX)"
info "log: $INSTALL_LOG"
if ! ( cd "$EXAMPLES_DIR" && mvn -pl domain-model,contracts -am install -DskipTests ) >"$INSTALL_LOG" 2>&1; then
    tail -n 100 "$INSTALL_LOG" >&2
    fail "domain-model/contracts install failed -- see $INSTALL_LOG"
fi

step "building spring-boot-compare (JVM)"
BUILD_LOG2="$(mktemp -t compare-qs-build-spring-XXXXXX)"
info "log: $BUILD_LOG2"
if ! ( mvn -f "${SPRING_COMPARE_DIR}/pom.xml" -DskipTests package ) >"$BUILD_LOG2" 2>&1; then
    tail -n 100 "$BUILD_LOG2" >&2
    fail "spring-boot-compare build failed -- see $BUILD_LOG2"
fi
# Spring Boot repackage leaves the executable jar alongside a `*.jar.original`
# (the pre-repackage thin jar) -- exclude that one.
S_JAR="$(find "${SPRING_COMPARE_DIR}/target" -maxdepth 1 -name '*.jar' ! -name '*.original' | head -n1 || true)"
[[ -n "$S_JAR" && -f "$S_JAR" ]] \
    || fail "expected an executable jar under ${SPRING_COMPARE_DIR}/target after build but none was found -- see $BUILD_LOG2"
narrate "spring-boot-compare built: $S_JAR"

step "booting spring-boot-compare (JVM) and measuring startup + RSS"
RUN_LOG2="$(mktemp -t compare-qs-run-spring-XXXXXX)"
info "log: $RUN_LOG2"
# spring-boot-compare reads the SAME DRQ-011 env contract as the Quarkus
# side (JDBC_URL / DB_USERNAME / DB_PASSWORD / KAFKA_BOOTSTRAP_SERVERS /
# APICURIO_REGISTRY_URL) via ${ENV:default} placeholders in its
# application.properties -- NOT Spring's relaxed-binding SPRING_* names.
# Run under the prod profile so this mirrors the packaged image, exactly as
# the Quarkus jar above runs its %prod config.
run_and_measure "${S_BASE_URL}/actuator/health" "$RUN_LOG2" \
    env TZ=UTC \
        JDBC_URL="$JDBC_URL" \
        DB_USERNAME="$PG_USER" \
        DB_PASSWORD="$PG_PASSWORD" \
        KAFKA_BOOTSTRAP_SERVERS="localhost:19999" \
        APICURIO_REGISTRY_URL="http://localhost:19999/apis/registry/v3" \
    java "${JVM_PROPS[@]}" -Dspring.profiles.active=prod -jar "$S_JAR" --server.port="$S_PORT"
S_JVM_STARTUP="$(fmt_secs_ms "$RESULT_STARTUP_MS")"
S_JVM_RSS="$(fmt_rss_kb "$RESULT_RSS_KB")"
info "spring-boot-compare: wall-clock ${S_JVM_STARTUP}, app-reported ${RESULT_LOG_SECS:-n/a}s, RSS ${S_JVM_RSS}"
stop_current

# ═══ Report ══════════════════════════════════════════════════════════════════
step "comparison table (JVM mode — paste into chapter 12)"
printf '\n'
printf '%-22s %-14s %-14s\n' "service" "jvm-startup" "jvm-rss"
printf '%-22s %-14s %-14s\n' "----------------------" "--------------" "--------------"
printf '%-22s %-14s %-14s\n' "order-service" "$Q_JVM_STARTUP" "$Q_JVM_RSS"
printf '%-22s %-14s %-14s\n' "spring-boot-compare" "$S_JVM_STARTUP" "$S_JVM_RSS"
printf '\n'
printf 'NOTE: both services carry the SAME dependency surface -- REST + JPA/Hibernate\n'
printf 'ORM + health + Kafka/Avro producer + a gRPC client to inventory-service. No\n'
printf 'exclusion caveat applies. The gRPC channel initializes lazily, so these\n'
printf 'startup/RSS numbers do NOT require inventory-service to be running --\n'
printf 'exercising POST /orders end-to-end would additionally need it up, but that\n'
printf 'is out of scope for this measurement.\n'

demo_ok
