#!/usr/bin/env bash
#
# scripts/run-all-tests.sh — the single test-pyramid runner: one entry point
# that drives UNIT -> IT -> TWIN -> (STACK-UP -> FUNCTIONAL -> LOAD) in a
# fixed order, so a contributor (or CI) never has to remember the right
# incantation sequence across mvn, docker compose, Newman, and the two
# tooling/load/*.sh scripts.
#
# Reuses the shared demo harness (demos/lib/_demo.sh) for require/fail/
# step/narrate/check/wait_http/compose_up/compose_down/svc_start_dev/
# svc_stop/demo_begin/demo_ok, same as every demo-*.sh and tooling/*.sh --
# a run that short-circuits before producing its final report must never
# read as clean.
#
# ── CI-headless-capable vs needs-a-live-stack ───────────────────────────
#   UNIT   — `mvn -f examples/pom.xml test` — plain @QuarkusTest, no Docker.
#   IT     — `mvn -f examples/pom.xml verify` — adds the bound `*IT`s, which
#            use Dev Services/Testcontainers (needs a reachable Docker
#            daemon, but NOT a standing compose stack or any already-running
#            service -- Dev Services spins up and tears down its own
#            ephemeral containers per module).
#   TWIN   — builds domain-model/contracts, then `mvn test` against the
#            standalone Spring Boot twin (OrderControllerTest uses
#            @ServiceConnection + Testcontainers -- needs Docker, same as
#            IT, still no standing stack).
#   => UNIT, IT, and TWIN are all CI-headless-capable: a GitHub
#      Actions/GitLab CI runner with just Docker-in-Docker and a JDK can run
#      them with no other services, no exposed ports, no manual bring-up.
#
#   STACK-UP, FUNCTIONAL, LOAD — need a LIVE stack: compose infra
#   (Postgres/Kafka/Apicurio) plus order-service (8091), inventory-service
#   (8092 HTTP / 9000 gRPC), graphql-gateway (8080), and review-service
#   (8098) all actually listening on real host ports. These phases are only
#   run with --load/--all, and are not meaningfully "CI-headless" in the
#   same sense (they bind real ports and run considerably longer).
#
#   Ollama-backed `*IT`s (OrderTriageFlowRouteIT, OrderTriageRouteIT,
#   OrderAssistantRouteIT) are NEVER run here. They are gated behind
#   `@EnabledIfSystemProperty(named = "ollama.tests.enabled", matches =
#   "true")`, which this script never sets, so a plain `mvn verify` already
#   skips them -- no extra exclusion flag needed.
#
# ── Why STACK-UP happens AFTER every mvn phase (STRICT order) ───────────
# Quarkus's default test HTTP port is 8081 and `@QuarkusTest`/`*IT` runs
# (via Dev Services) can also claim other ephemeral ports/containers that
# collide with a standing stack's already-bound ports (order-service 8091,
# inventory-service 8092/9000, graphql-gateway 8080, Apicurio's own compose
# port 8081 -- see demos/demo-graphql.sh's header comment on exactly that
# 8081 collision). Running UNIT/IT/TWIN to completion BEFORE ever bringing
# up a live stack means those test runs never have a standing stack to
# collide with, and the live stack never has to coexist with a test JVM
# binding the same ports out from under it. Do not reorder these phases.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../demos/lib/_demo.sh
source "${SCRIPT_DIR}/../demos/lib/_demo.sh"

EXAMPLES_POM="${REPO_ROOT}/examples/pom.xml"
SPRING_POM="${REPO_ROOT}/examples/spring-boot-compare/pom.xml"
NEWMAN_RUNNER="${REPO_ROOT}/tooling/newman/run-newman.sh"
LOAD_ORDERS="${REPO_ROOT}/tooling/load/load-orders.sh"
LOAD_CHECKSTOCK="${REPO_ROOT}/tooling/load/load-checkstock.sh"

ORDER_DIR="${EXAMPLES_DIR}/order-service"
INVENTORY_DIR="${EXAMPLES_DIR}/inventory-service"
GATEWAY_DIR="${EXAMPLES_DIR}/graphql-gateway"
REVIEW_DIR="${EXAMPLES_DIR}/review-service"

ORDER_PORT=8091
INVENTORY_PORT=8092
INVENTORY_GRPC_PORT=9000
GATEWAY_PORT=8080
REVIEW_PORT=8098

ORDER_BASE="http://localhost:${ORDER_PORT}"
INVENTORY_BASE="http://localhost:${INVENTORY_PORT}"
GATEWAY_BASE="http://localhost:${GATEWAY_PORT}"
REVIEW_BASE="http://localhost:${REVIEW_PORT}"

AVRO_SERIALIZABLE_PACKAGES="capstone.order.v1"

usage() {
    cat <<'EOF'
Usage: scripts/run-all-tests.sh [options]

The single test-pyramid runner: preflight, UNIT/IT, the standalone Spring
Boot TWIN, then (if requested) a live STACK-UP, the Newman FUNCTIONAL
collection, and a short LOAD pass -- in that strict order -- followed by a
sectioned PASS/FAIL/SKIP report.

Options:
  --unit       Run the UNIT phase (mvn test -- plain @QuarkusTest, no IT).
  --it         Run the IT phase (mvn verify -- unit + bound *IT via Dev
               Services/Testcontainers) and the TWIN phase. Implies --unit's
               coverage (verify runs the unit tests too; this script never
               runs `test` then `verify` back to back).
  --load       Run STACK-UP, FUNCTIONAL (Newman), and LOAD (hey + ghz).
  --all        Run everything above. This is also the DEFAULT when no
               phase flag is given.
  --keep-up    After --load/--all, leave the compose stack and the four
               services running instead of tearing them down on exit.
  -h, --help   Show this help and exit.

Examples:
  scripts/run-all-tests.sh                 # everything (default)
  scripts/run-all-tests.sh --unit          # fast inner-loop check, no Docker needed
  scripts/run-all-tests.sh --it            # unit + IT + twin, needs Docker
  scripts/run-all-tests.sh --load          # live-stack Newman + load pass only
  scripts/run-all-tests.sh --all --keep-up # full run, leave the stack up after
EOF
}

RUN_UNIT=0
RUN_IT=0
RUN_LOAD=0
RUN_ALL=0
KEEP_UP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unit)     RUN_UNIT=1; shift ;;
        --it)       RUN_IT=1; shift ;;
        --load)     RUN_LOAD=1; shift ;;
        --all)      RUN_ALL=1; shift ;;
        --keep-up)  KEEP_UP=1; shift ;;
        -h|--help)
            usage
            exit 0 ;;
        *)
            usage >&2
            fail "unknown argument: $1 (see --help above)" ;;
    esac
done

# No phase flag at all => --all (the documented default).
if (( RUN_UNIT == 0 && RUN_IT == 0 && RUN_LOAD == 0 && RUN_ALL == 0 )); then
    RUN_ALL=1
fi
if (( RUN_ALL == 1 )); then
    RUN_UNIT=1
    RUN_IT=1
    RUN_LOAD=1
fi
# --it's `mvn verify` already covers --unit's `mvn test` coverage; running
# IT implies unit coverage too, so the MVN_PHASE step below picks `verify`
# whenever IT is requested instead of running `test` first and `verify`
# second.

demo_begin "run-all-tests"

# ─── Per-phase PASS/FAIL/SKIP ledger (report printed at the very end) ──────
declare -A PHASE_RESULT=(
    [preflight]="SKIP"
    [unit-it]="SKIP"
    [twin]="SKIP"
    [stack-up]="SKIP"
    [functional]="SKIP"
    [load]="SKIP"
)
PHASE_ORDER=(preflight unit-it twin stack-up functional load)

# ─── Phase 1: PREFLIGHT ─────────────────────────────────────────────────────
step "PREFLIGHT"
check "mvn on PATH"    "command -v mvn >/dev/null 2>&1"    "install Maven 3.9.x (see CLAUDE.md's version matrix)"
check "java on PATH"   "command -v java >/dev/null 2>&1"   "install JDK 25 via SDKMAN: sdk install java 25-tem"
check "curl on PATH"   "command -v curl >/dev/null 2>&1"   "install curl (sudo dnf install curl)"
check "jq on PATH"     "command -v jq >/dev/null 2>&1"     "install jq (sudo dnf install jq)"
check "docker daemon reachable" "docker info >/dev/null 2>&1" \
    "start Docker Engine (sudo systemctl start docker) -- UNIT's *IT and TWIN's Testcontainers both need it"
if (( RUN_LOAD == 1 )); then
    check "hey on PATH"    "command -v hey >/dev/null 2>&1"    "go install github.com/rakyll/hey@v0.1.5"
    check "ghz on PATH"    "command -v ghz >/dev/null 2>&1"    "go install github.com/bojand/ghz/cmd/ghz@v0.121.0"
    check "newman or npx on PATH" \
        "command -v newman >/dev/null 2>&1 || command -v npx >/dev/null 2>&1" \
        "npm install -g newman@6.2.2 (or ensure Node.js/npx is on PATH)"
fi
# Guard (only when a compose-using phase is selected: --load/--all => STACK-UP,
# FUNCTIONAL, LOAD): the compose stack publishes 3000/3100/3200/4317/4318 on the
# host, the same ports the minikube profile publishes. Refuse to run anything,
# mvn included, while the profile's node container is running.
if (( RUN_LOAD == 1 )); then
    if [[ "$(docker container inspect -f '{{.State.Running}}' "${MINIKUBE_PROFILE:-datamesh}" 2>/dev/null)" == "true" ]]; then
        PHASE_RESULT[preflight]="FAIL"
        fail "the datamesh minikube profile is running and holds ports 3000/3100/3200/4317/4318 that the compose stack needs; stop it first: minikube stop -p ${MINIKUBE_PROFILE:-datamesh}"
    fi
fi
if (( _DEMO_CHECK_FAILURES > 0 )); then
    PHASE_RESULT[preflight]="FAIL"
    fail "${_DEMO_CHECK_FAILURES} preflight check(s) failed (see fix hints above) -- aborting before running anything"
fi
PHASE_RESULT[preflight]="PASS"
info "preflight OK"

# ─── Phase 2: UNIT / IT ─────────────────────────────────────────────────────
if (( RUN_UNIT == 1 || RUN_IT == 1 )); then
    if (( RUN_IT == 1 )); then
        step "UNIT+IT (mvn -f examples/pom.xml verify)"
        narrate "runs every @QuarkusTest plus the bound *IT (Dev Services/Testcontainers) -- Ollama *ITs stay skipped (ollama.tests.enabled unset)"
        if ( cd "${REPO_ROOT}" && mvn -f "$EXAMPLES_POM" verify ); then
            PHASE_RESULT[unit-it]="PASS"
        else
            PHASE_RESULT[unit-it]="FAIL"
        fi
    else
        step "UNIT only (mvn -f examples/pom.xml test)"
        narrate "plain @QuarkusTest only -- no *IT, no Docker required for this phase"
        if ( cd "${REPO_ROOT}" && mvn -f "$EXAMPLES_POM" test ); then
            PHASE_RESULT[unit-it]="PASS"
        else
            PHASE_RESULT[unit-it]="FAIL"
        fi
    fi
    [[ "${PHASE_RESULT[unit-it]}" == "PASS" ]] && info "UNIT/IT phase passed" || warn "UNIT/IT phase FAILED -- continuing so the rest of the pyramid still reports"
fi

# ─── Phase 3: TWIN (standalone Spring Boot comparison service) ─────────────
if (( RUN_IT == 1 )); then
    step "TWIN (domain-model + contracts install, then mvn test against spring-boot-compare)"
    narrate "the one runnable Spring Boot twin -- OrderControllerTest uses @ServiceConnection + Testcontainers, needs Docker, no standing stack"
    if ( cd "${REPO_ROOT}" \
            && mvn -f "$EXAMPLES_POM" -pl domain-model,contracts -am install -DskipTests \
            && mvn -f "$SPRING_POM" test ); then
        PHASE_RESULT[twin]="PASS"
    else
        PHASE_RESULT[twin]="FAIL"
    fi
    [[ "${PHASE_RESULT[twin]}" == "PASS" ]] && info "TWIN phase passed" || warn "TWIN phase FAILED -- continuing so the rest of the pyramid still reports"
fi

# ─── Phases 4-6: STACK-UP / FUNCTIONAL / LOAD (only --load/--all) ──────────
if (( RUN_LOAD == 1 )); then
    # EXIT trap installed HERE, immediately before anything is brought up --
    # same idiom as demos/demo-order.sh/demo-graphql.sh's "this script owns
    # it" compose lifecycle, so Ctrl-C or any later failure still tears down
    # (unless --keep-up).
    SVC_PIDFILES=()
    _cleanup() {
        local rc=$?
        if (( KEEP_UP == 1 )); then
            warn "--keep-up: leaving compose + services running (stop them yourself when done)"
            return "$rc"
        fi
        local pf
        for pf in "${SVC_PIDFILES[@]:-}"; do
            [[ -n "$pf" ]] && svc_stop "$pf" 2>/dev/null || true
        done
        compose_down 2>/dev/null || true
        return "$rc"
    }
    trap '_cleanup; _demo_exit_trap' EXIT

    STACK_UP_OK=1

    step "STACK-UP: compose baseline + order/inventory/gateway/review"
    if [[ ! -f "${REPO_ROOT}/.env" ]]; then
        [[ -f "${REPO_ROOT}/.env.example" ]] \
            || { STACK_UP_OK=0; warn ".env is missing and there is no .env.example to copy from"; }
        if (( STACK_UP_OK == 1 )); then
            info "no .env found -- copying .env.example -> .env (gitignored, documented prereq)"
            cp "${REPO_ROOT}/.env.example" "${REPO_ROOT}/.env"
        fi
    fi
    if (( STACK_UP_OK == 1 )); then
        # shellcheck disable=SC1091
        source "${REPO_ROOT}/.env"
        POSTGRES_PORT="${POSTGRES_PORT:-5432}"
        KAFKA_HOST_PORT="${KAFKA_HOST_PORT:-9092}"
        APICURIO_PORT="${APICURIO_PORT:-8081}"

        compose_up || STACK_UP_OK=0
    fi

    if (( STACK_UP_OK == 1 )); then
        for (( i = 0; i < 30; i++ )); do
            docker exec datamesh-postgres pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 && break
            sleep 1
        done
        docker exec datamesh-postgres pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-appuser}" -d orderdb >/dev/null 2>&1 \
            || { STACK_UP_OK=0; warn "compose Postgres (orderdb) did not become ready within 30s"; }
    fi

    if (( STACK_UP_OK == 1 )); then
        step "build order-service, inventory-service, graphql-gateway (mvn -DskipTests package)"
        for mod in "$ORDER_DIR" "$INVENTORY_DIR" "$GATEWAY_DIR"; do
            if ! ( cd "$mod" && mvn -q -DskipTests package ) \
                || [[ ! -f "${mod}/target/quarkus-app/quarkus-run.jar" ]]; then
                STACK_UP_OK=0
                warn "build failed for $(basename "$mod")"
                break
            fi
        done
    fi

    if (( STACK_UP_OK == 1 )); then
        step "start inventory-service (HTTP ${INVENTORY_PORT}, gRPC ${INVENTORY_GRPC_PORT})"
        INV_PIDFILE="$(mktemp -t run-all-tests-inv-pid-XXXXXX)"
        INV_LOGFILE="$(mktemp -t run-all-tests-inv-log-XXXXXX)"
        info "log: $INV_LOGFILE"
        ( cd "$INVENTORY_DIR" && exec env \
            TZ=UTC \
            JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/inventorydb" \
            DB_USERNAME="${POSTGRES_USER:-appuser}" \
            DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
            java -Dquarkus.http.port="$INVENTORY_PORT" -Dquarkus.grpc.server.port="$INVENTORY_GRPC_PORT" \
                -jar target/quarkus-app/quarkus-run.jar \
        ) >"$INV_LOGFILE" 2>&1 &
        echo "$!" > "$INV_PIDFILE"
        SVC_PIDFILES+=("$INV_PIDFILE")
        if wait_http "${INVENTORY_BASE}/q/health/live" 60; then
            info "inventory-service is up"
            curl -fsS --max-time 10 -X POST "${INVENTORY_BASE}/stock" \
                -H 'Content-Type: application/json' \
                -d '{"sku":"WIDGET-1","quantityOnHand":50,"available":true}' >/dev/null \
                || { STACK_UP_OK=0; warn "seeding WIDGET-1 via POST ${INVENTORY_BASE}/stock failed"; }
        else
            tail -n 60 "$INV_LOGFILE" >&2
            STACK_UP_OK=0
            warn "inventory-service did not become healthy within 60s -- see $INV_LOGFILE"
        fi
    fi

    if (( STACK_UP_OK == 1 )); then
        step "start order-service (HTTP ${ORDER_PORT})"
        ORD_PIDFILE="$(mktemp -t run-all-tests-ord-pid-XXXXXX)"
        ORD_LOGFILE="$(mktemp -t run-all-tests-ord-log-XXXXXX)"
        info "log: $ORD_LOGFILE"
        ( cd "$ORDER_DIR" && exec env \
            TZ=UTC \
            JDBC_URL="jdbc:postgresql://localhost:${POSTGRES_PORT}/orderdb" \
            DB_USERNAME="${POSTGRES_USER:-appuser}" \
            DB_PASSWORD="${POSTGRES_PASSWORD:-apppass}" \
            KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_HOST_PORT}" \
            APICURIO_REGISTRY_URL="http://localhost:${APICURIO_PORT}/apis/registry/v3" \
            java -Dquarkus.http.port="$ORDER_PORT" \
                -Dorg.apache.avro.SERIALIZABLE_PACKAGES="$AVRO_SERIALIZABLE_PACKAGES" \
                -jar target/quarkus-app/quarkus-run.jar \
        ) >"$ORD_LOGFILE" 2>&1 &
        echo "$!" > "$ORD_PIDFILE"
        SVC_PIDFILES+=("$ORD_PIDFILE")
        if wait_http "${ORDER_BASE}/q/health/live" 60; then
            info "order-service is up"
        else
            tail -n 60 "$ORD_LOGFILE" >&2
            STACK_UP_OK=0
            warn "order-service did not become healthy within 60s -- see $ORD_LOGFILE"
        fi
    fi

    if (( STACK_UP_OK == 1 )); then
        step "start graphql-gateway (HTTP ${GATEWAY_PORT})"
        GW_PIDFILE="$(mktemp -t run-all-tests-gw-pid-XXXXXX)"
        GW_LOGFILE="$(mktemp -t run-all-tests-gw-log-XXXXXX)"
        info "log: $GW_LOGFILE"
        ( cd "$GATEWAY_DIR" && exec env \
            TZ=UTC \
            ORDER_SERVICE_URL="${ORDER_BASE}" \
            INVENTORY_GRPC_HOST=localhost \
            INVENTORY_GRPC_PORT="$INVENTORY_GRPC_PORT" \
            java -Dquarkus.http.port="$GATEWAY_PORT" -jar target/quarkus-app/quarkus-run.jar \
        ) >"$GW_LOGFILE" 2>&1 &
        echo "$!" > "$GW_PIDFILE"
        SVC_PIDFILES+=("$GW_PIDFILE")
        if wait_http "${GATEWAY_BASE}/q/health/live" 60; then
            info "graphql-gateway is up"
        else
            tail -n 60 "$GW_LOGFILE" >&2
            STACK_UP_OK=0
            warn "graphql-gateway did not become healthy within 60s -- see $GW_LOGFILE"
        fi
    fi

    if (( STACK_UP_OK == 1 )); then
        step "start review-service (mvn quarkus:dev, Dev Services Postgres + Keycloak, HTTP ${REVIEW_PORT})"
        REV_PIDFILE="$(svc_start_dev "$REVIEW_DIR" "$REVIEW_PORT")"
        SVC_PIDFILES+=("$REV_PIDFILE")
        if wait_http "${REVIEW_BASE}/q/health/live" 90; then
            info "review-service is up"
        else
            STACK_UP_OK=0
            warn "review-service did not become healthy within 90s"
        fi
    fi

    PHASE_RESULT[stack-up]="$([[ $STACK_UP_OK == 1 ]] && echo PASS || echo FAIL)"

    # ─── Phase 5: FUNCTIONAL (Newman) ───────────────────────────────────────
    if (( STACK_UP_OK == 1 )); then
        step "FUNCTIONAL (tooling/newman/run-newman.sh)"
        if "$NEWMAN_RUNNER"; then
            PHASE_RESULT[functional]="PASS"
        else
            PHASE_RESULT[functional]="FAIL"
        fi
    else
        warn "skipping FUNCTIONAL -- STACK-UP did not complete"
        PHASE_RESULT[functional]="SKIP"
    fi

    # ─── Phase 6: LOAD (hey + ghz, short pass) ─────────────────────────────
    if (( STACK_UP_OK == 1 )); then
        step "LOAD (tooling/load/load-orders.sh + tooling/load/load-checkstock.sh, -c 10 -z 20s)"
        LOAD_OK=1
        "$LOAD_ORDERS" -c 10 -z 20s || LOAD_OK=0
        "$LOAD_CHECKSTOCK" -c 10 -z 20s || LOAD_OK=0
        PHASE_RESULT[load]="$([[ $LOAD_OK == 1 ]] && echo PASS || echo FAIL)"
    else
        warn "skipping LOAD -- STACK-UP did not complete"
        PHASE_RESULT[load]="SKIP"
    fi
fi

# ─── Phase 8: REPORT ────────────────────────────────────────────────────────
step "REPORT"
OVERALL_FAIL=0
printf '\n%s%s  Phase        Result%s\n' "$BOLD" "$BLU" "$RST"
printf '%s  -----------  ------%s\n' "$BLU" "$RST"
for p in "${PHASE_ORDER[@]}"; do
    r="${PHASE_RESULT[$p]}"
    case "$r" in
        PASS) color="$GRN" ;;
        FAIL) color="$RED"; OVERALL_FAIL=1 ;;
        *)    color="$DIM" ;;
    esac
    printf '  %-12s %s%s%s\n' "$p" "$color" "$r" "$RST"
done
printf '\n'

if (( OVERALL_FAIL == 1 )); then
    printf '%s✗ one or more phases FAILED -- see per-phase output above%s\n' "$RED" "$RST" >&2
    exit 1
fi

demo_ok
