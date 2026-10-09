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
#           (scripts/setup-profile.sh + scripts/bootstrap.sh), so both are
#           gated behind --with-minikube and SKIPPED by default. ACT 5 always
#           runs last, after every compose demo has run its compose_down.
#           It STARTS the stopped `datamesh` profile (`minikube start -p
#           datamesh`; the published NodePort bindings persist), verifies the
#           profile publishes the required ports on 127.0.0.1, and resets the
#           node's FORWARD policy if needed (ensure_node_forwarding). It fails
#           with "create it: ./scripts/setup-profile.sh && ./scripts/bootstrap.sh"
#           if no profile exists. Host access is by NodePorts published on
#           127.0.0.1 (demos/lib/endpoints.sh): no helper process is started.
#
# ── Compose and the minikube profile are mutually exclusive ──────────────────
# A running `datamesh` minikube profile holds host ports 3000/3100/3200/4317/
# 4318 that the compose stack needs. If the profile is running and any
# compose-based demo is selected, the preflight fails with:
#   minikube stop -p datamesh
#
# Gating is per-DEMO, not per-act — ACT 4 is the clearest example: its three
# default demos run unconditionally while its native demo is independently
# gated. An act is reported SKIPPED only when every demo selected into it
# was gate-skipped; otherwise it is PASSED/FAILED on its executed demos.
#
# ── Presenter pacing ─────────────────────────────────────────────────────────
# Every demo gets a header (position, name, act), 2-3 lines of context from
# the DEMO_INFO registry (what it shows, what to watch, URLs to open), then
# "Press Enter to start <demo>..." before it runs and "<demo> complete --
# Press Enter to continue..." after it (the latter says FAILED when the demo
# failed). A gate-skipped demo prints its one-line skip reason instead of the
# explanation and never pauses. The between-act pause is kept.
#
# Where the Enter keypress is read from:
#   - stdin is a TTY (normal use, also with stdout piped to `tee`): stdin.
#   - stdin is piped/redirected: lines are consumed from it, one per pause
#     (`printf '\n\n\n' | walkthrough.sh ...` scripts a run). When the input is
#     exhausted, /dev/tty is used if the process has one; if not, pausing is
#     switched off for the rest of the run, with a notice, and the run
#     continues unattended.
#   - --auto / --no-pause: no pause is ever shown (CI/self-test).
# Each demo runs as a child process with stdin from /dev/null, so a demo can
# never swallow keystrokes meant for the presenter.
#
# ── Flags ────────────────────────────────────────────────────────────────────
#   --with-ollama       run ACT2/ACT3's ollama-profile demos
#   --with-native        run ACT4's demo-native (slow native compile)
#   --with-minikube       run ACT5's KEDA demos (starts the stopped datamesh profile)
#   --only <d[,d...]>    run only the named demo(s) (comma-separated)
#   --skip <d[,d...]>    run every selected demo EXCEPT the named one(s)
#   --from <demo|actN>   start at that demo (or the first demo of act N, e.g.
#                        act4) and run everything after it; composes with
#                        --only/--skip and the --with-* gates
#   --list               print the acts and demos with gate requirements, exit 0
#   --no-preflight       skip the environment/toolchain preflight sweep
#   --no-pause / --auto  show no pauses at all (CI/self-test)
#   -h / --help          list acts, demos, and flags, then exit
#
# ── Environment ──────────────────────────────────────────────────────────────
#   PLATFORM_READY_TIMEOUT   seconds (default 600) ACT 5 waits for the pods in
#                            the datamesh namespace and the KEDA and Strimzi
#                            operators to be Ready after a start. On a failure
#                            it prints `kubectl get pods -n datamesh` first.
#
# `--only` and `--skip` operate on demo NAMES (e.g. `demo-order`), are
# mutually exclusive, and select the demo SET before gating is applied — a
# gated demo named in `--only` without its flag still shows the SKIP path
# rather than running. `--from` is applied on top of that selection, in
# catalog order. Unknown names for --only/--skip/--from fail before any
# demo runs.
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
    "KEDA autoscaling on Kafka consumer-group lag and on inbound HTTP (scale-to-zero), on the local Kubernetes cluster (scripts/setup-profile.sh, scripts/bootstrap.sh). Runs last; starts the stopped datamesh profile. Needs --with-minikube."
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

# DEMO_INFO[name] — 2-3 lines shown under the per-demo header before the demo
# runs: what it shows, what to watch for, URLs to open. Derived from the
# deck's per-demo speaker notes (presentation/datamesh-201/build-deck.js).
# Ports come from compose.yaml/.env.example (Grafana 3000, Apicurio 8081,
# Kafka UI 8090 under --profile tools).
declare -A DEMO_INFO
DEMO_INFO[demo-order]=$'POST /orders checks stock over gRPC, persists through Panache, then publishes order.placed to Kafka.\nWatch for: 201 on create, 200 on GET by id, 404 on an unknown id, then the row confirmed directly in Postgres.\nCompose baseline (Postgres, Kafka, Apicurio) starts and stops with the demo.'
DEMO_INFO[demo-grpc]=$'inventory-service answers capstone.inventory.v1.InventoryService/CheckStock over gRPC; the server base class is generated from inventory.proto.\nWatch for: the grpcurl call against the .proto returning available and quantityOnHand. @Blocking keeps the Panache work off the event loop.\nCompose baseline.'
DEMO_INFO[demo-graphql]=$'The gateway resolves order(id) over REST and the nested stock field lazily over gRPC; both come back in one /graphql response.\nWatch for: REST-sourced and gRPC-sourced fields together in one .data.order payload, no .errors. Gateway orchestration of reads, not subgraph federation.\nCompose baseline.'
DEMO_INFO[demo-kafka]=$'Avro on the wire against the Apicurio Schema Registry. order-service pins AvroKafkaSerializer; the demo reads the raw topic bytes back.\nWatch for: first byte 0x00 (Apicurio/Confluent magic byte); JSON would start with 0x7B. Registry at http://localhost:8081 while the stack is up.\nCompose baseline.'
DEMO_INFO[demo-tracing]=$'One order request produces a single cross-service trace in Tempo: REST root span, the CheckStock gRPC child, two Postgres children.\nWatch for: the span count and the service.name set the script parses from the Tempo API. To browse it: Grafana http://localhost:3000, Explore, Tempo datasource (up only while the demo runs).\nCompose baseline (LGTM always on).'
DEMO_INFO[demo-websocket]=$'WebSockets.Next composed with Reactive Messaging: a Kafka consumer in notification-service pushes to every open socket after commit.\nWatch for: a JBang JDK WebSocket client, connected before the order is placed, receiving a message whose orderId, customerId and itemSku match the order. Endpoint ws://localhost:8093/ws/notifications.\nCompose baseline; needs jbang.'
DEMO_INFO[demo-reactive-vertx]=$'Reactive and imperative code on one Vert.x reactor under concurrent load; the framework picks the thread pool from @Blocking and the return type.\nWatch for: three gRPC and three REST calls fired concurrently at one process, all six answers correct and uncorrelated.\nCompose baseline.'
DEMO_INFO[demo-oidc]=$'Bearer-token exchange against a Dev Services Keycloak, no mocked header: 401 without a token, 403 for a valid token missing the role, then 204 followed by 404 for the authorized caller.\nWatch for: the 403 for Bob is RBAC, not authentication. The Keycloak port is random (Testcontainers), found with docker port.\nCompose baseline; needs a live Keycloak Dev Service.'
DEMO_INFO[demo-orchestration-styles]=$'One domain coordinated three ways: Kafka choreography, a Camel route, and a Quarkus Flow workflow.\nWatch for: the Avro magic byte on every Act 1 hop, and matching strict decisions from the Camel and Flow engines. Act 1 skips the classifier-stability trial the other two require.\nCompose ollama profile (--with-ollama).'
DEMO_INFO[demo-ai-classify]=$'A single-shot langchain4j chat call classifies an order against the local Ollama model (qwen2.5:3b).\nWatch for: the classify endpoint returning one of the defined category labels. Single-shot classification is reliable; multi-turn tool calling is the known limitation.\nCompose ollama profile (--with-ollama).'
DEMO_INFO[demo-ai-mcp]=$'The working MCP-server tool-calling path. The in-process agent endpoint, which has a known defect, is never called.\nWatch for: the MCP JSON-RPC handshake, the tool list, and three deterministic lookups. The limitation is a transport-wiring defect in camel-quarkus-support-langchain4j (open upstream deferral), not model capability.\nCompose ollama profile (--with-ollama).'
DEMO_INFO[demo-camel-integration]=$'Camel EIPs in isolation: separates "does the route logic work" from "does AI tool calling work".\nWatch for: all four branches, including the fallback for an unrecognized order id (ORD-001, ORD-002, ORD-003, then the fallback).\nCompose ollama profile (--with-ollama).'
DEMO_INFO[demo-ai-triage]=$'Classify, then decide: the same pipeline through both orchestration shapes, with Drools (not tool calling) making the decision.\nWatch for: FRAUD_HOLD, EXPEDITE and ROUTE_TO_WAREHOUSE on three pre-validated inputs, identical across both endpoints. Needs qwen2.5:3b on the host or the ollama profile.\nPrimary AI demo (--with-ollama).'
DEMO_INFO[demo-jbang-prototype]=$'A complete Camel route in one Java file: no pom.xml, no Maven module, only jbang resolving pinned Camel dependencies.\nWatch for: the transformed marker JBANG_PROTOTYPE_OK in the route log, not just a zero exit code. The first run downloads dependencies and can take a while.\nNo docker; needs jbang. Pinned Camel 4.22.1 resolves from Maven Central; there is no remote script to trust.'
DEMO_INFO[demo-continuous-testing]=$'Quarkus continuous testing: instant reruns with Dev Services provisioning infra, the fast end of the feedback-loop spectrum.\nWatch for: the banner "All 4 tests are passing". A missing banner fails the demo.\nJDK and Maven only; Dev Services starts its own containers.'
DEMO_INFO[demo-panama]=$'A JBang script (JDK 25, no Maven) calls libc getpid() and strlen() through the FFM API and checks both against Java.\nWatch for: PANAMA_GETPID equal to JVM_PID, and PANAMA_STRLEN equal to JAVA_LENGTH (strlen counts UTF-8 bytes).\nNo docker; needs jbang.'
DEMO_INFO[demo-native]=$'order-service compiled to a native executable and run with no JVM in the process.\nWatch for: the native boot log and a GET /orders response. Long-running: several minutes, longer on the first run while a 1-2 GB builder image is pulled.\nOne throwaway Postgres container (--with-native).'
DEMO_INFO[demo-keda-kafka]=$'KEDA scales notification-service from zero on Kafka consumer-group lag, on the local Kubernetes cluster built by scripts/setup-profile.sh and scripts/bootstrap.sh.\nWatch for: replicas climbing from zero on a lag burst, then returning to zero as the backlog drains.\nNeeds the datamesh profile (--with-minikube); the walkthrough starts it if stopped.'
DEMO_INFO[demo-keda-http]=$'KEDA HTTP add-on scales graphql-gateway from zero on inbound request rate through its interceptor.\nWatch for: the scaled-to-zero deployment reaching at least one replica within budget. A scaled-to-zero workload reports unknown health until the first request; that is expected.\nNeeds the datamesh profile (--with-minikube); the walkthrough starts it if stopped.'

# COMPOSE_DEMOS — the demos that call compose_up (they bind host ports 3000/
# 3100/3200/4317/4318, which a running minikube profile also holds).
COMPOSE_DEMOS="demo-order demo-grpc demo-graphql demo-kafka demo-tracing demo-websocket demo-orchestration-styles demo-ai-classify demo-ai-mcp demo-camel-integration demo-ai-triage"

# _demo_index <name> — echoes the catalog index of a demo, or returns 1.
_demo_index() {
    local i
    for (( i = 0; i < DEMO_COUNT; i++ )); do
        if [[ "${DEMO_NAMES[i]}" == "$1" ]]; then echo "$i"; return 0; fi
    done
    return 1
}

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
  --with-minikube       run ACT5's KEDA demos; starts the stopped datamesh profile (default: skipped)
  --only <d[,d...]>     run only the named demo(s) (comma-separated, exact name)
  --skip <d[,d...]>     run every selected demo except the named one(s)
  --from <demo|actN>    start at that demo, or at the first demo of act N (act1..act5),
                        and run everything after it (composes with --only/--skip/gates)
  --list                list acts and demos with gate requirements, then exit
  --no-preflight        skip the environment/toolchain preflight sweep
  --no-pause, --auto    show no pauses at all (CI/self-test)
  -h, --help            show this help and exit

${BOLD}Environment:${RST}
  PLATFORM_READY_TIMEOUT  seconds ACT 5 waits for the pods in the datamesh namespace and
                          the KEDA and Strimzi operators after a start (default 600; a
                          VM-based engine can need more than 5 minutes)

${BOLD}Pacing:${RST}
  Each demo prints a header and 2-3 lines of context, then waits:
    "Press Enter to start <demo>..."  before it runs
    "<demo> complete -- Press Enter to continue..."  after it (FAILED if it failed)
  A pause also separates acts. Gate-skipped demos print their skip reason and
  do not pause. Enter is read from stdin when it is a TTY; when stdin is piped
  one line is consumed per pause, then /dev/tty is used if available,
  otherwise pausing is switched off for the rest of the run.

--only and --skip are mutually exclusive and operate on demo names (see the
list above), e.g.: --only demo-order,demo-grpc
--from examples: --from demo-tracing, --from act4, --from act4 --with-native
EOF
}

print_list() {
    local n i tag
    printf 'Acts and demos (19 demos, 5 acts):\n'
    for (( n = 1; n <= 5; n++ )); do
        printf '\nact%d  %s\n' "$n" "${ACT_TITLE[n]}"
        for (( i = 0; i < DEMO_COUNT; i++ )); do
            [[ "${DEMO_ACT[i]}" == "$n" ]] || continue
            tag="default"
            [[ -n "${DEMO_GATE[i]}" ]] && tag="requires --with-${DEMO_GATE[i]}"
            printf '  %2d. %-28s %s\n' $(( i + 1 )) "${DEMO_NAMES[i]}" "$tag"
        done
    done
}

# ─── Argument parsing ────────────────────────────────────────────────────────
WITH_OLLAMA=0
WITH_NATIVE=0
WITH_MINIKUBE=0
ONLY_LIST=""
SKIP_LIST=""
FROM_TARGET=""
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
        --from) FROM_TARGET="${2:-}"; shift 2 ;;
        --from=*) FROM_TARGET="${1#*=}"; shift ;;
        --list) print_list; exit 0 ;;
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

# --from <demo|actN>: resolve to a catalog index (FROM_IDX); everything
# before it is excluded. Fails before any demo runs on an unknown name.
FROM_IDX=0
if [[ -n "$FROM_TARGET" ]]; then
    if [[ "$FROM_TARGET" =~ ^act([1-5])$ ]]; then
        for (( i = 0; i < DEMO_COUNT; i++ )); do
            if [[ "${DEMO_ACT[i]}" == "${BASH_REMATCH[1]}" ]]; then FROM_IDX=$i; break; fi
        done
    elif idx="$(_demo_index "$FROM_TARGET")"; then
        FROM_IDX=$idx
    else
        fail "--from: unknown demo or act '$FROM_TARGET' -- use act1..act5 or one of: $VALID_NAMES"
    fi
fi

# is_selected <name> — true iff <name> survives --from and the --only/--skip filter.
is_selected() {
    local name="$1" idx
    idx="$(_demo_index "$name")" || return 1
    (( idx >= FROM_IDX )) || return 1
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
[[ -n "$FROM_TARGET" ]] && narrate "--from ${FROM_TARGET}: starting at $(printf '%s' "${DEMO_NAMES[FROM_IDX]}")"
(( AUTO )) && narrate "--auto/--no-pause: running unattended, no Enter prompts"

if [[ ${#ACTIVE_ACTS[@]} -eq 0 ]]; then
    fail "no demos selected -- check --only/--skip for a typo (valid names: $VALID_NAMES)"
fi

# ─── Scope: which compose demos and ACT 5 demos will actually run ───────────
COMPOSE_IN_SCOPE=0
ACT5_IN_SCOPE=0
for (( i = 0; i < DEMO_COUNT; i++ )); do
    name="${DEMO_NAMES[i]}"
    is_selected "$name" || continue
    gate_satisfied "${DEMO_GATE[i]}" || continue
    _in_csv "$name" "${COMPOSE_DEMOS// /,}" && COMPOSE_IN_SCOPE=1
    [[ "${DEMO_ACT[i]}" == "5" ]] && ACT5_IN_SCOPE=1
done

# PROFILE_STATE — running | stopped | absent (the profile's docker container).
PROFILE_NAME="${MINIKUBE_PROFILE:-datamesh}"
PROFILE_STATE="absent"
if command -v docker >/dev/null 2>&1 && docker container inspect "$PROFILE_NAME" >/dev/null 2>&1; then
    if [[ "$(docker container inspect -f '{{.State.Running}}' "$PROFILE_NAME" 2>/dev/null)" == "true" ]]; then
        PROFILE_STATE="running"
    else
        PROFILE_STATE="stopped"
    fi
fi

# prepare_platform — once, before the first ACT 5 demo: verify the published
# NodePorts, start the profile if it is stopped, and guard node forwarding.
PLATFORM_READY=0
prepare_platform() {
    (( PLATFORM_READY )) && return 0
    # shellcheck source=lib/endpoints.sh
    source "${SCRIPT_DIR}/lib/endpoints.sh"
    docker_engine_ok || fail "Docker Engine is not reachable (sudo systemctl start docker)"
    profile_container_exists \
        || fail "the '${EP_PROFILE}' minikube profile does not exist -- create it: ./scripts/setup-profile.sh && ./scripts/bootstrap.sh"
    check_published_ports || fail "the '${EP_PROFILE}' profile does not publish the required NodePorts (see the hint above)"
    if ! profile_container_running || ! minikube status -p "$EP_PROFILE" >/dev/null 2>&1; then
        # Stopped profile: it holds no listeners, so every host port must be
        # free. A container that is still running but whose `minikube status`
        # fails (wedged node) holds its own docker-proxy listeners: exempt them.
        own_ports=""
        if profile_container_running; then
            own_ports="$(published_ports | awk '{print $2}' | tr '\n' ' ')"
            narrate "the '${EP_PROFILE}' container is running but minikube status fails; restarting it"
        else
            narrate "starting the stopped '${EP_PROFILE}' profile (published NodePort bindings persist)"
        fi
        assert_host_ports_free "$own_ports" \
            || fail "host ports needed by the '${EP_PROFILE}' profile are in use (something else is listening); stop other clusters and compose stacks first"
        minikube start -p "$EP_PROFILE" || fail "minikube start -p ${EP_PROFILE} failed"
        check_published_ports || fail "the '${EP_PROFILE}' profile does not publish the required NodePorts after start (see the hint above)"
    fi
    ensure_node_forwarding
    kubectl config use-context "$EP_PROFILE" >/dev/null \
        || fail "kubectl config use-context ${EP_PROFILE} failed"
    # Readiness: a started profile needs a few minutes before the platform
    # answers (longer on a VM-based engine). Tunable with PLATFORM_READY_TIMEOUT.
    local ready_to="${PLATFORM_READY_TIMEOUT:-600}"
    [[ "$ready_to" =~ ^[0-9]+$ ]] || fail "PLATFORM_READY_TIMEOUT must be a number of seconds (got '${ready_to}')"
    narrate "waiting up to ${ready_to}s for the platform to be ready (pods in ${EP_APP_NS}, KEDA and Strimzi operators)"
    if ! kubectl --context "$EP_PROFILE" wait --for=condition=Ready pods --all -n "$EP_APP_NS" \
            --field-selector=status.phase!=Succeeded --timeout="${ready_to}s"; then
        kubectl --context "$EP_PROFILE" get pods -n "$EP_APP_NS" >&2 || true
        fail "pods in namespace ${EP_APP_NS} are not Ready after ${ready_to}s (raise PLATFORM_READY_TIMEOUT, or inspect: kubectl --context ${EP_PROFILE} get pods -n ${EP_APP_NS})"
    fi
    if ! kubectl --context "$EP_PROFILE" wait --for=condition=Available deployment/keda-operator \
            -n keda --timeout="${ready_to}s"; then
        kubectl --context "$EP_PROFILE" get pods -n "$EP_APP_NS" >&2 || true
        fail "the KEDA operator (namespace keda) is not Available after ${ready_to}s (raise PLATFORM_READY_TIMEOUT)"
    fi
    if ! kubectl --context "$EP_PROFILE" wait --for=condition=Available deployment/strimzi-cluster-operator \
            -n "$EP_APP_NS" --timeout="${ready_to}s"; then
        kubectl --context "$EP_PROFILE" get pods -n "$EP_APP_NS" >&2 || true
        fail "the Strimzi operator (namespace ${EP_APP_NS}) is not Available after ${ready_to}s (raise PLATFORM_READY_TIMEOUT)"
    fi
    PLATFORM_READY=1
}

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

    # Compose and the running profile cannot coexist (shared host ports).
    if (( COMPOSE_IN_SCOPE )) && [[ "$PROFILE_STATE" == "running" ]]; then
        fail "the datamesh minikube profile is running and holds host ports 3000/3100/3200/4317/4318 that compose needs; stop it first: minikube stop -p ${MINIKUBE_PROFILE:-datamesh}"
    fi

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
    if (( ACT5_IN_SCOPE )); then
        if [[ "$PROFILE_STATE" == "absent" ]]; then
            fail "ACT 5 needs the '${PROFILE_NAME}' minikube profile and it does not exist -- create it: ./scripts/setup-profile.sh && ./scripts/bootstrap.sh"
        elif [[ "$PROFILE_STATE" == "running" ]]; then
            info "minikube profile '${PROFILE_NAME}' is running"
        else
            info "minikube profile '${PROFILE_NAME}' is stopped -- ACT 5 will start it after the compose demos finish"
        fi
    fi
fi

# ─── Pacing helpers ──────────────────────────────────────────────────────────
PAUSES_OFF=0

# pause <label> — Enter-to-advance; see "Presenter pacing" in the header for
# where the keypress is read from. No-op under --auto/--no-pause.
pause() {
    (( AUTO || PAUSES_OFF )) && return 0
    printf '\n%s[%s]%s ' "$BOLD" "$1" "$RST"
    if [[ -t 0 ]]; then
        read -r _ || PAUSES_OFF=1
    elif read -r _; then
        printf '\n'
    elif { read -r _ </dev/tty; } 2>/dev/null; then
        :
    else
        PAUSES_OFF=1
        printf '\n%s  (no input available for pauses; continuing unattended)%s\n' "$DIM" "$RST"
        return 0
    fi
    return 0
}

# demo_header <index> — per-demo banner plus the registry context lines.
demo_header() {
    local i="$1" name="${DEMO_NAMES[$1]}" line
    printf '\n%s%s───────────────────────────────────────────────────────────────%s\n' "$BOLD" "$BLU" "$RST"
    printf '%s%s  Demo %d of %d  ·  %s  ·  ACT %d%s\n' "$BOLD" "$BLU" $(( i + 1 )) "$DEMO_COUNT" "$name" "${DEMO_ACT[i]}" "$RST"
    printf '%s%s───────────────────────────────────────────────────────────────%s\n' "$BOLD" "$BLU" "$RST"
    while IFS= read -r line; do
        printf '  %s\n' "$line"
    done <<<"${DEMO_INFO[$name]:-}"
}

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
            printf '\n%s  · %s%s\n' "$DIM" "${name}" "$RST"
            narrate "SKIP ${name} -- requires --with-${gate} (not passed; opt-in, skipped by design)"
            TOTAL_SKIP=$(( TOTAL_SKIP + 1 ))
            continue
        fi

        if [[ "${DEMO_ACT[i]}" == "5" ]]; then
            # Runs after every compose demo's compose_down (ACT 5 is last).
            prepare_platform
        fi

        act_any_ran=1
        TOTAL_RUN=$(( TOTAL_RUN + 1 ))
        demo_header "$i"
        pause "Press Enter to start ${name}…"
        if run_act "$name" bash "${SCRIPT_DIR}/${name}.sh" </dev/null; then
            TOTAL_PASS=$(( TOTAL_PASS + 1 ))
            pause "${name} complete — Press Enter to continue…"
        else
            TOTAL_FAIL=$(( TOTAL_FAIL + 1 ))
            act_any_failed=1
            FAILED_DEMOS+=("$name")
            pause "${name} FAILED — Press Enter to continue…"
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
    if (( act_idx < ${#ACTIVE_ACTS[@]} - 1 )); then
        next_n="${ACTIVE_ACTS[act_idx+1]}"
        pause "Enter to continue — next act: ${ACT_TITLE[next_n]}"
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
