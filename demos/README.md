# demos/

Runnable demo scripts for `datamesh-reference-arch-quarkus`, one per
capability in the slide/tutorial matrix (`_plans/build-plan.md`, "Demo ↔
slide ↔ capability matrix"). Each `demo-*.sh` is a thin, assert-driven
wrapper over an already-built service — it asserts *positive content*
(a parsed field, an exact status code, a decision enum, a replica count),
never just "exit code was zero". See `_plans/phase-d-step10-plan.md` for the
full step-by-step build plan.

This step (10.0) ships only the shared harness: `lib/_demo.sh` (sourced by
every demo) and this README. The `demo-*.sh` scripts themselves land in
later steps (10.1–10.9); `walkthrough.sh` (10.10) is the five-act presenter
orchestrator that ties them together.

## Harness

Every demo sources `lib/_demo.sh` and follows this shape:

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"
demo_begin "demo-order"
require curl jq docker
# ... compose_up / svc_start_dev / assert_* ...
demo_ok
```

`demo_begin`/`demo_ok` install a success-flag + `EXIT` trap: if the script
exits 0 without ever reaching `demo_ok` (a short-circuited step, a stray
early `return`), the trap reports it as a FAILURE instead of letting it pass
silently. See the header comment in `lib/_demo.sh` for the full helper list
(`require`, `wait_http`, `assert_http_200`, `assert_json_field`,
`compose_up`/`compose_down`, `svc_start_dev`/`svc_stop`, `check`,
`act_header`/`run_act`/`prompt_enter` for orchestration).

## Demo matrix, by infra

### bare — JVM / Dev Services only, no compose, no cluster

| Demo | Capability | What it asserts |
|------|-----------|------------------|
| `demo-jbang-prototype.sh` | JBang scripting / Camel CLI prototyping | A JBang-run script produces the expected output without a full Maven build |
| `demo-continuous-testing.sh` | Quarkus continuous testing + Dev Services | `quarkus:dev` continuous testing reruns and turns green after a code edit, with Dev Services bringing up its own backing container automatically |
| `demo-native.sh` *(opt-in — native)* | Native compilation (GraalVM/Mandrel) | A native binary builds, boots, and serves HTTP 200 on a real endpoint |

Prereqs: JDK 25, Maven 3.9.x, `jbang` on PATH (jbang-prototype), GraalVM/Mandrel
for native (`-Pnative` or `quarkus build --native`) — no `docker compose`
needed for this group.

### compose — infra baseline (`docker compose up -d`)

| Demo | Capability | What it asserts |
|------|-----------|------------------|
| `demo-order.sh` | Panache + REST data product | POST `/orders` creates a row; GET round-trips it by id and the row is confirmed via a direct Postgres query |
| `demo-grpc.sh` | gRPC (`quarkus-grpc`) | A gRPC call returns the expected response message/fields |
| `demo-graphql.sh` | SmallRye GraphQL gateway | A single GraphQL query fans out to multiple backing services and returns the expected field values |
| `demo-kafka.sh` | Kafka (Reactive Messaging) | A published message round-trips through Kafka with Avro/Apicurio wire format confirmed (magic byte `0x0` + schema id) |
| `demo-tracing.sh` | OpenTelemetry | A request produces the expected trace-span count/shape in the otel-lgtm stack (Tempo) |
| `demo-websocket.sh` | WebSockets.Next | A WebSocket client receives the expected message/event after a triggering action |
| `demo-reactive-vertx.sh` | Vert.x unified reactive + imperative | A reactive endpoint returns correct data, demonstrating non-blocking I/O alongside imperative code in the same app |
| `demo-oidc.sh` *(feasibility-gated, DRQ-005 — may be skipped)* | `quarkus-oidc` | A protected endpoint returns 401 unauthenticated and 200 with a valid token |

Prereqs: `docker` + the Compose v2 plugin (`docker compose`, not the legacy
binary), `cp .env.example .env`, `docker compose up -d` from the repo root
(brings up postgres, kafka-native, apicurio, otel-lgtm — no profile flag
needed).

### compose + `--profile ollama` — opt-in, heaviest infra

| Demo | Capability | What it asserts |
|------|-----------|------------------|
| `demo-ai-classify.sh` | langchain4j (single-shot chat classify) | The classify endpoint returns one of the defined category labels |
| `demo-ai-mcp.sh` | langchain4j + MCP | The MCP-server surface lists the `order-status` tool and returns the deterministic lookup result (`ORD-001`); prints the DEF-001 caveat banner and asserts **only** the MCP-server path, never in-process tool-calling |
| `demo-camel-integration.sh` | Quarkus + Camel EIP | A Camel route correctly transforms/routes a message end-to-end through its EIPs |
| `demo-ai-triage.sh` *(showcase, DRQ-012)* | langchain4j classify + embedded Drools decide | ≥2 distinct inputs produce ≥2 distinct Drools decisions among `FRAUD_HOLD` / `EXPEDITE` / `ROUTE_TO_WAREHOUSE`, with zero reliance on LLM tool-calling |

Prereqs: everything in the `compose` group, plus `docker compose --profile
ollama up -d` and a pulled model in the Ollama container. **Opt-in** — this
is the heaviest profile (8g mem budget for Ollama alone); skip it if you
only need the core service matrix.

### minikube — reuses the step-9 Kubernetes substrate

| Demo | Capability | What it asserts |
|------|-----------|------------------|
| `demo-keda-kafka.sh` *(opt-in — minikube)* | KEDA autoscaling on Kafka consumer lag | Replica count scales 0 → N on a lag burst and back to 0 as the backlog drains |
| `demo-keda-http.sh` *(opt-in — minikube)* | KEDA autoscaling on HTTP (scale-to-zero) | A scaled-to-zero deployment wakes to ≥1 replica in response to an inbound HTTP request through the interceptor |

Prereqs: the `lgtm-minikube-stack` substrate from Phase C / step 9
(minikube cluster with Istio, KEDA, Strimzi, CloudNativePG bootstrapped),
`kubectl` context pointed at it. **Opt-in** — not required for the core
compose-based demo set.

### Orchestrator

| Script | What it does |
|--------|--------------|
| `walkthrough.sh` | Five-act presenter walkthrough that runs a curated subset of the above demos in sequence with narration and Enter-to-advance pacing (`--only`/`--skip`/`--no-preflight` flags). Acts touching ollama/native/minikube are opt-in and gated behind flags/preflight checks — the default run only needs `docker compose up -d`. |

## Opt-in summary

- **ollama**: `demo-ai-classify.sh`, `demo-ai-mcp.sh`, `demo-camel-integration.sh`,
  `demo-ai-triage.sh` — require `docker compose --profile ollama up -d`.
- **native**: `demo-native.sh` — requires a GraalVM/Mandrel native build
  (slow; CI-grade machine recommended).
- **minikube**: `demo-keda-kafka.sh`, `demo-keda-http.sh` — require the
  step-9 minikube substrate, not just `docker compose`.
- **feasibility-gated**: `demo-oidc.sh` — ships only if DRQ-005 confirms
  `quarkus-oidc` wiring is in scope; otherwise this row is dropped.

Everything else (`bare` and `compose` groups minus the above) is the
default, always-runnable demo set.
