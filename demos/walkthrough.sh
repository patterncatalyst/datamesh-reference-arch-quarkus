#!/usr/bin/env bash
#
# demos/walkthrough.sh — the five-act presenter orchestrator that ties the
# 19 demo-*.sh scripts together for a live talk.
#
# This script does not reimplement any demo's logic and does not manage
# compose/Dev Services/cluster lifecycle itself — every demo-*.sh already
# owns its own `compose_up`/`compose_down` (or Dev Services, or `kubectl`)
# and its own per-run-unique state (orders, topics, tokens, ...). This
# orchestrator's only job is to invoke each one, IN SEQUENCE (back-to-back
# compose up/down per demo is slower than sharing one stack across all of
# them, but the demos bind fixed host ports and that sharing would be a
# bigger refactor out of scope for now), narrate the five acts, pace a presenter
# through them with `prompt_enter`, and report a final tally. Demos are
# always run sequentially (one `run_act` after another) — never in
# parallel; that is both a presenter-pacing choice and a hard requirement
# (fixed host ports + a single compose.yaml baseline).
#
# ── The five acts (19 demos total) ──────────────────────────────────────────
#   ACT 1 — Data products & protocols (8): demo-order, demo-grpc,
#           demo-graphql, demo-kafka, demo-tracing, demo-websocket,
#           demo-reactive-vertx, demo-oidc. The core compose-baseline
#           surface, security included — always runs by default.
#   ACT 2 — Three orchestration styles (1): demo-orchestration-styles.
#           Kafka choreography vs a Camel route vs a Quarkus Flow workflow,
#           side by side. Needs the compose `ollama` profile — gated behind
#           --with-ollama.
#   ACT 3 — AI, Camel EIPs & embedded Drools (4): demo-ai-classify,
#           demo-ai-mcp, demo-camel-integration, demo-ai-triage. The AI
#           showcase, including the known tool-calling limitation
#           (langchain4j classify + Drools decide + Camel EIPs + the MCP
#           tool-server surface). Also needs the `ollama` profile — gated
#           behind --with-ollama.
#   ACT 4 — Developer experience & native (4): demo-jbang-prototype,
#           demo-continuous-testing and demo-panama run by default (cheap,
#           no compose, no cluster); demo-native (a GraalVM/Mandrel
#           compile, several minutes) is gated behind --with-native.
#   ACT 5 — Platform: event-driven autoscaling (2): demo-keda-kafka,
#           demo-keda-http. Both need the local Kubernetes cluster
#           (scripts/bootstrap.sh), so both are gated behind
#           --with-minikube and SKIPPED by default.
#
# Gating is per-DEMO, not per-act — ACT 4 is the clearest example: its three
# default demos run unconditionally while its native demo is independently
# gated. An act is reported SKIPPED only when every demo selected into it
# was gate-skipped; otherwise it is PASSED/FAILED on its executed demos.
#
# ── Flags ────────────────────────────────────────────────────────────────────
#   --with-ollama       run ACT2/ACT3's ollama-profile demos
#   --with-native        run ACT4's demo-native (slow native compile)
#   --with-minikube       run ACT5's KEDA demos (needs a live cluster)
#   --only <d[,d...]>    run only the named demo(s) (comma-separated)
#   --skip <d[,d...]>    run every selected demo EXCEPT the named one(s)
#   --no-preflight       skip the environment/toolchain preflight sweep
#   --no-pause / --auto  don't wait for Enter between acts (CI/self-test)
#   -h / --help          list acts, demos, and flags, then exit
#
# `--only` and `--skip` operate on demo NAMES (e.g. `demo-order`), are
# mutually exclusive, and select the demo SET before gating is applied — a
# gated demo named in `--only` without its flag still shows the SKIP path
# rather than running (see the live verification notes in this step's
# report for exactly that case).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

# ─── Demo catalog (parallel arrays; index 0 unused to keep act numbers 1-based) ─
ACT_TITLE=(
    ""
    "Data products & protocols"
    "Three orchestration styles"
    "AI, Camel EIPs & embedded Drools"
    "Developer experience & native compilation"
    "Platform: event-driven autoscaling (KEDA)"
)
ACT_LEDE=(
    ""
    "The core data-mesh surface against the same compose baseline (Postgres/Kafka/Apicurio/otel-lgtm): REST+Panache, gRPC, GraphQL federation, Kafka/Avro wire format, OpenTelemetry tracing, WebSockets.Next, Vert.x reactive, and an OIDC-secured endpoint."
    "The identical shipping/order domain, coordinated three different ways: Kafka choreography (decentralized, no coordinator) vs a Camel route vs a Quarkus Flow workflow (two differently-shaped centralized orchestration engines). Needs --with-ollama."
    "langchain4j single-shot classification, an embedded Drools rules engine deciding FRAUD_HOLD/EXPEDITE/ROUTE_TO_WAREHOUSE, Camel EIPs, and the MCP tool-server surface -- including the known tool-calling limitation. Needs --with-ollama."
    "JBang single-file Camel prototyping, Quarkus continuous testing and Panama FFM native calls run every time (no compose, no cluster); a GraalVM/Mandrel native compile is opt-in behind --with-native (several minutes, pulls a builder image on first run)."
    "KEDA autoscaling on Kafka consumer-group lag and on inbound HTTP (scale-to-zero), on the local Kubernetes cluster (scripts/bootstrap.sh). Needs --with-minikube."
)

# DEMO_ACT[i] / DEMO_NAMES[i] / DEMO_GATE[i] — one entry per demo, in act
# order. DEMO_GATE is "" (always eligible) or one of ollama/native/minikube.
DEMO_ACT=(1 1 1 1 1 1 1 1   2   3 3 3 3   4 4 4 4   5 5)
DEMO_NAMES=(
    demo-order demo-grpc demo-graphql demo-kafka demo-tracing demo-websocket demo-reactive-vertx demo-oidc
    demo-orchestration-styles
    demo-ai-classify demo-ai-mcp demo-camel-integration demo-ai-triage
    demo-jbang-prototype demo-continuous-testing demo-panama demo-native
    demo-keda-kafka demo-keda-http
)
DEMO_GATE=(
    "" "" "" "" "" "" "" ""
    ollama
    ollama ollama ollama ollama
    "" "" "" native
    minikube minikube
)
DEMO_COUNT=${#DEMO_NAMES[@]}

# _demo_required_cmds <name> — echoes the space-separated binaries that demo
# `require`s itself (mirrors each demo-*.sh's own `require` line / dedicated
# preflight check), so this orchestrator's preflight can report the exact
# union needed for the selected demos, instead of an over-broad
# fixed list.
_demo_required_cmds() {
    case "$1" in
        demo-order|demo-graphql|demo-tracing|demo-ai-classify|demo-ai-mcp|demo-camel-integration|demo-oidc)
            echo "curl jq docker mvn java" ;;
        demo-grpc|demo-reactive-vertx)
            echo "curl jq docker mvn java grpcurl" ;;
        demo-kafka|demo-orchestration-styles)
            echo "curl jq docker mvn java kcat od wc" ;;
        demo-websocket)
            echo "curl jq docker mvn java jbang" ;;
        demo-ai-triage)
            echo "curl jq mvn java" ;;
        demo-jbang-prototype|demo-panama)
            echo "jbang" ;;
        demo-continuous-testing|demo-native)
            echo "mvn curl jq docker" ;;
        demo-keda-kafka|demo-keda-http)
            echo "kubectl minikube curl jq" ;;
    esac
}

print_help() {
    cat <<EOF
${BOLD}demos/walkthrough.sh${RST} — five-act presenter orchestrator for the
datamesh-reference-arch-quarkus demo suite (19 demos, 5 acts).

${BOLD}Usage:${RST}
  ./demos/walkthrough.sh [flags]

${BOLD}Acts:${RST}
EOF
    local n
    for (( n = 1; n <= 5; n++ )); do
        printf '  ACT %d  %s\n' "$n" "${ACT_TITLE[n]}"
        local i
        for (( i = 0; i < DEMO_COUNT; i++ )); do
            if [[ "${DEMO_ACT[i]}" == "$n" ]]; then
                if [[ -n "${DEMO_GATE[i]}" ]]; then
                    printf '          - %s  (gated: --with-%s)\n' "${DEMO_NAMES[i]}" "${DEMO_GATE[i]}"
                else
                    printf '          - %s\n' "${DEMO_NAMES[i]}"
                fi
            fi
        done
    done
    cat <<EOF

${BOLD}Flags:${RST}
  --with-ollama         run ACT2/ACT3's ollama-profile demos (default: skipped)
  --with-native         run ACT4's demo-native, a real native compile (default: skipped)
  --with-minikube       run ACT5's KEDA demos, needs a live cluster (default: skipped)
  --only <d[,d...]>     run only the named demo(s) (comma-separated, exact name)
  --skip <d[,d...]>     run every selected demo except the named one(s)
  --no-preflight        skip the environment/toolchain preflight sweep
  --no-pause, --auto    don't wait for Enter between acts (CI/self-test)
  -h, --help            show this help and exit

--only and --skip are mutually exclusive and operate on demo names (see the
list above), e.g.: --only demo-order,demo-grpc
EOF
}

# ─── Argument parsing ────────────────────────────────────────────────────────
WITH_OLLAMA=0
WITH_NATIVE=0
WITH_MINIKUBE=0
ONLY_LIST=""
SKIP_LIST=""
NO_PREFLIGHT=0
AUTO=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        --with-ollama) WITH_OLLAMA=1; shift ;;
        --with-native) WITH_NATIVE=1; shift ;;
        --with-minikube) WITH_MINIKUBE=1; shift ;;
        --only) ONLY_LIST="${2:-}"; shift 2 ;;
        --only=*) ONLY_LIST="${1#*=}"; shift ;;
        --skip) SKIP_LIST="${2:-}"; shift 2 ;;
        --skip=*) SKIP_LIST="${1#*=}"; shift ;;
        --no-preflight) NO_PREFLIGHT=1; shift ;;
        --no-pause|--auto) AUTO=1; shift ;;
        *)
            printf '\n%s✗ FAILED:%s unknown argument: %s (see --help)\n' "$RED" "$RST" "$1" >&2
            exit 1
            ;;
    esac
done

demo_begin "walkthrough"

if [[ -n "$ONLY_LIST" && -n "$SKIP_LIST" ]]; then
    fail "--only and --skip are mutually exclusive -- pass one or the other"
fi

# _in_csv <needle> <csv> — true iff <needle> is one of <csv>'s comma-separated items.
_in_csv() {
    local needle="$1" csv="$2" item IFS=','
    for item in $csv; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

VALID_NAMES="$(IFS=,; echo "${DEMO_NAMES[*]}")"
if [[ -n "$ONLY_LIST" ]]; then
    IFS=',' read -r -a _names <<<"$ONLY_LIST"
    for n in "${_names[@]}"; do
        _in_csv "$n" "$VALID_NAMES" || fail "--only: unknown demo name '$n' -- valid names: $VALID_NAMES"
    done
fi
if [[ -n "$SKIP_LIST" ]]; then
    IFS=',' read -r -a _names <<<"$SKIP_LIST"
    for n in "${_names[@]}"; do
        _in_csv "$n" "$VALID_NAMES" || fail "--skip: unknown demo name '$n' -- valid names: $VALID_NAMES"
    done
fi

# is_selected <name> — true iff <name> survives the --only/--skip filter.
is_selected() {
    local name="$1"
    if [[ -n "$ONLY_LIST" ]]; then
        _in_csv "$name" "$ONLY_LIST"
    elif [[ -n "$SKIP_LIST" ]]; then
        ! _in_csv "$name" "$SKIP_LIST"
    else
        return 0
    fi
}

# gate_satisfied <gate> — true iff an empty gate, or its --with-X flag was passed.
gate_satisfied() {
    case "$1" in
        "") return 0 ;;
        ollama) (( WITH_OLLAMA )) ;;
        native) (( WITH_NATIVE )) ;;
        minikube) (( WITH_MINIKUBE )) ;;
        *) return 1 ;;
    esac
}

# ─── Compute the active act list (acts with >=1 selected demo) ─────────────
# An act with no selected demo (entirely excluded by --only/--skip) is not
# shown at all -- it is irrelevant to a narrowed run. An act whose selected
# demos are all gate-skipped is still shown (so the presenter/operator sees
# the SKIP explanation), just reported as SKIPPED rather than PASSED/FAILED.
ACTIVE_ACTS=()
for (( n = 1; n <= 5; n++ )); do
    for (( i = 0; i < DEMO_COUNT; i++ )); do
        if [[ "${DEMO_ACT[i]}" == "$n" ]] && is_selected "${DEMO_NAMES[i]}"; then
            ACTIVE_ACTS+=("$n")
            break
        fi
    done
done

step "walkthrough: 5 acts, 19 demos"
narrate "selected acts: ${ACTIVE_ACTS[*]:-none}"
(( WITH_OLLAMA ))   && narrate "--with-ollama enabled (ACT2/ACT3 ollama-profile demos in scope)"
(( WITH_NATIVE ))   && narrate "--with-native enabled (ACT4 native compile in scope)"
(( WITH_MINIKUBE )) && narrate "--with-minikube enabled (ACT5 KEDA demos in scope)"
(( AUTO )) && narrate "--auto/--no-pause: running unattended, no Enter prompts between acts"

if [[ ${#ACTIVE_ACTS[@]} -eq 0 ]]; then
    fail "no demos selected -- check --only/--skip for a typo (valid names: $VALID_NAMES)"
fi

# ─── Preflight (unless --no-preflight) ──────────────────────────────────────
if (( NO_PREFLIGHT )); then
    step "preflight: skipped (--no-preflight)"
else
    step "preflight: environment + toolchain for the selected, gate-satisfied demos"

    UNION_CMDS=""
    for (( i = 0; i < DEMO_COUNT; i++ )); do
        name="${DEMO_NAMES[i]}"; gate="${DEMO_GATE[i]}"
        is_selected "$name" || continue
        gate_satisfied "$gate" || continue
        UNION_CMDS="${UNION_CMDS} $(_demo_required_cmds "$name")"
    done
    # shellcheck disable=SC2086
    UNION_CMDS="$(printf '%s\n' ${UNION_CMDS} | sort -u | tr '\n' ' ')"
    info "toolchain union for this run: ${UNION_CMDS:-<none>}"

    if [[ "$UNION_CMDS" == *docker* ]]; then
        check "docker CLI present" "command -v docker >/dev/null 2>&1" \
            "install Docker: https://docs.docker.com/engine/install/"
        check "docker compose v2 plugin present" "docker compose version >/dev/null 2>&1" \
            "install the Docker Compose v2 plugin (this repo uses 'docker compose', not the legacy 'docker-compose' binary)"
        check "docker daemon reachable" "docker info >/dev/null 2>&1" \
            "start the Docker daemon and retry"
    fi
    for c in $UNION_CMDS; do
        [[ "$c" == "docker" ]] && continue
        check "'$c' on PATH" "command -v $c >/dev/null 2>&1" "install '$c' and retry (or narrow the run with --only/--skip)"
    done

    if (( _DEMO_CHECK_FAILURES > 0 )); then
        fail "${_DEMO_CHECK_FAILURES} preflight check(s) failed -- see the fix hints above, or re-run with --no-preflight once addressed"
    fi
    narrate "preflight passed"

    # Soft, non-fatal heads-up for the opt-in toolchains -- these WARN, they
    # never fail preflight: each gated demo already fails loudly and
    # correctly on its own if its real dependency (model/toolchain/cluster)
    # turns out to be missing when it runs.
    if (( WITH_OLLAMA )); then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^datamesh-ollama$' \
            && docker exec datamesh-ollama ollama list 2>/dev/null | grep -q 'qwen2.5:3b'; then
            info "qwen2.5:3b already cached in the running datamesh-ollama container"
        else
            warn "qwen2.5:3b not confirmed cached in datamesh-ollama -- ACT2/ACT3's first call may pull it (slow, ~8g mem budget for the ollama profile)"
        fi
    fi
    if (( WITH_NATIVE )); then
        if command -v native-image >/dev/null 2>&1; then
            info "local GraalVM/Mandrel native-image found on PATH -- ACT4's native build will use it"
        else
            warn "no local native-image on PATH -- ACT4's native build falls back to container-build (docker; first run pulls a 1-2GB builder image, several minutes)"
        fi
    fi
    if (( WITH_MINIKUBE )); then
        if command -v minikube >/dev/null 2>&1 && minikube status -p datamesh >/dev/null 2>&1; then
            info "minikube profile 'datamesh' appears to be running"
        else
            warn "minikube profile 'datamesh' not detected -- ACT5 needs the local Kubernetes cluster (./scripts/bootstrap.sh); its demos will fail loudly if it is missing"
        fi
    fi
fi

# ─── Run the acts ────────────────────────────────────────────────────────────
TOTAL_RUN=0 TOTAL_PASS=0 TOTAL_FAIL=0 TOTAL_SKIP=0
ACT_PASS=0 ACT_FAIL=0 ACT_SKIP=0
FAILED_DEMOS=()

for act_idx in "${!ACTIVE_ACTS[@]}"; do
    n="${ACTIVE_ACTS[act_idx]}"
    act_header "act${n}" "${ACT_TITLE[n]}" "${ACT_LEDE[n]}"

    act_any_ran=0
    act_any_failed=0
    for (( i = 0; i < DEMO_COUNT; i++ )); do
        [[ "${DEMO_ACT[i]}" == "$n" ]] || continue
        name="${DEMO_NAMES[i]}"; gate="${DEMO_GATE[i]}"
        is_selected "$name" || continue

        if ! gate_satisfied "$gate"; then
            narrate "SKIP ${name} -- requires --with-${gate} (not passed; opt-in, skipped by design)"
            TOTAL_SKIP=$(( TOTAL_SKIP + 1 ))
            continue
        fi

        act_any_ran=1
        TOTAL_RUN=$(( TOTAL_RUN + 1 ))
        if run_act "$name" bash "${SCRIPT_DIR}/${name}.sh"; then
            TOTAL_PASS=$(( TOTAL_PASS + 1 ))
        else
            TOTAL_FAIL=$(( TOTAL_FAIL + 1 ))
            act_any_failed=1
            FAILED_DEMOS+=("$name")
        fi
    done

    # NOTE: act_header (lib/_demo.sh) prints its own auto-incrementing "ACT
    # N" banner number -- it does not use this script's act identity ($n),
    # so when --only/--skip narrows the run that banner number can diverge
    # from $n (e.g. the first act shown is still printed "ACT 1").
    # Refer to acts by TITLE below, not by number, so these lines never
    # contradict the banner just printed above.
    if (( act_any_ran == 0 )); then
        narrate "'${ACT_TITLE[n]}' result: SKIPPED (every selected demo in this act was gated off)"
        ACT_SKIP=$(( ACT_SKIP + 1 ))
    elif (( act_any_failed )); then
        narrate "'${ACT_TITLE[n]}' result: FAILED (see ✗ lines above)"
        ACT_FAIL=$(( ACT_FAIL + 1 ))
    else
        narrate "'${ACT_TITLE[n]}' result: PASSED"
        ACT_PASS=$(( ACT_PASS + 1 ))
    fi

    # Pause between acts (presenter pacing), unless --auto/--no-pause, and
    # never after the last act shown.
    if (( ! AUTO )) && (( act_idx < ${#ACTIVE_ACTS[@]} - 1 )); then
        next_n="${ACTIVE_ACTS[act_idx+1]}"
        prompt_enter "Enter to continue -- next: ${ACT_TITLE[next_n]}"
    fi
done

# ─── Final summary ───────────────────────────────────────────────────────────
step "walkthrough summary"
narrate "acts:  ${#ACTIVE_ACTS[@]} considered -- ${ACT_PASS} passed, ${ACT_FAIL} failed, ${ACT_SKIP} skipped entirely"
narrate "demos: ${TOTAL_RUN} run -- ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed, ${TOTAL_SKIP} skipped (gated)"
if (( ${#FAILED_DEMOS[@]} > 0 )); then
    narrate "failed demo(s): ${FAILED_DEMOS[*]}"
fi

if (( ACT_FAIL > 0 )); then
    fail "${ACT_FAIL} act(s) failed -- re-run the failing demo-*.sh directly for full diagnostics"
fi

demo_ok
