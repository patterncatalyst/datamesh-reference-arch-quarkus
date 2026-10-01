---
title: Phase D · Step 10 — Runnable Demos (plan)
description: Implementation plan for the demo scripts (1:1 with slides) and the DRQ-012 Drools showcase
---

# Phase D, Step 10 — Runnable demo scripts

Settled plan for step 10 (demos 1:1 with the slide/capability matrix) incl. the
DRQ-012 Ollama + Camel + **Drools** showcase. Engine decision: **plain embedded
Drools** (library + `KieContainer`), NOT Kogito/KIE — KIE is not a roadmap item;
Quarkus + Camel does the orchestration. See `decisions.md` DRQ-012/DRQ-013,
DEF-001.

## Approach

`demos/` built from scratch: a shared `demos/lib/_demo.sh` helper (ported from the
Python repo idiom) + one `demo-*.sh` per capability + a `walkthrough.sh` five-act
orchestrator. Demos are thin, assert-driven wrappers over already-built services.
The only new **code** is the DRQ-012 module. Demos grouped by infra:

- **bare** (Dev Services / JVM only): demo-jbang-prototype, demo-continuous-testing, demo-native
- **compose** (infra baseline): demo-order, demo-grpc, demo-graphql, demo-kafka, demo-tracing, demo-websocket, demo-reactive-vertx, demo-oidc
- **compose + `--profile ollama`**: demo-ai-classify, demo-ai-mcp, demo-camel-integration, **demo-ai-triage (showcase)**
- **minikube** (reuse step-9 substrate): demo-keda-kafka, demo-keda-http

Design decisions:
- **DRQ-012 → new module `examples/ai-rules-service`** (not extend ai-mcp-service).
  Reuses only the proven single-shot `langchain4j-chat` classify; no agent/tool
  deps → structurally DEF-001-proof. LLM classifies, **Drools decides**
  (`FRAUD_HOLD` / `EXPEDITE` / `ROUTE_TO_WAREHOUSE`).
- **Embedded Drools, no KIE/Kogito** (user directive). Light early probe only:
  `drools-core`/`drools-compiler` compiles + runs a trivial `.drl` on Quarkus
  3.39.5 / JDK 25. JVM-mode module (native not a goal here).
- **demo-ai-mcp honest**: embedded MCP-server path (external client lists
  `order-status`, returns `ORD-001`) + loud DEF-001 caveat banner. Never asserts
  in-process tool-calling.
- **New-code flags**: demo-websocket needs a small `websocket.next` endpoint;
  demo-oidc may add `quarkus-oidc` wiring (feasibility-gated per DRQ-005).

## Steps (status: `todo` / `wip` / `done`)

| # | Step | Depends | Status |
|---|------|---------|--------|
| 10.0 | Shared harness `demos/lib/_demo.sh` + `demos/README.md` | — | todo |
| 10.1 | Embedded-Drools light probe (drools-core + trivial `.drl`, JDK25/Q3.39.5) | — | **done — GO**: Drools 10.2.0 works on JDK25. Deps: `drools-bom:10.2.0` (import) + `drools-engine:10.2.0` + **`drools-mvel:10.2.0`** (required — ConstraintBuilder SPI). Recipe: in-memory `KieHelper.build()` → `KieBase` at `StartupEvent`, `KieSession` per request. Skews trivial. JVM-only. |
| 10.2 | `examples/ai-rules-service` module: Camel `OrderTriageRoute` + `.drl` + isolated Drools unit test (in `mvn verify`, no Ollama) + opt-in Ollama IT | 10.1 | todo |
| 10.1b | Quarkus Flow version/compat spike (quarkus-flow-bom on Q3.39.5/JDK25; coexist w/ camel-quarkus+langchain4j) | — | **done — GO**: `quarkus-flow-bom:1.1.3` imported LAST (after langchain4j→quarkus→camel), `quarkus-flow` version-less. No kogito/kie/drools pulled; no conflicts; serverlessworkflow-api 7.32.1.Final. Wire steps via `FlowDSL.function(name, bean::method)` + `switchCase(caseOf(...).then(...), caseDefault(...))`; **terminate branches with `.then(FlowDirectiveEnum.END)`** or they fall through. JVM clean on JDK25. |
| 10.2b | DRQ-014: add Quarkus Flow orchestration of triage to `ai-rules-service` (`POST /api/orders/triage-flow`), reuse DRL + classify + facts; unit test the workflow path | 10.2, 10.1b | todo |
| 10.3 | `demos/demo-ai-triage.sh` showcase — assert decision enum on BOTH `/triage` (Camel) and `/triage-flow` (Flow); DEF-001-proof | 10.2, 10.2b | todo |
| 10.4 | Honest `demo-ai-classify.sh` + `demo-ai-mcp.sh` (MCP path + caveat) | 10.0 | todo |
| 10.5 | `demo-camel-integration.sh` | 10.0 | todo |
| 10.6 | Core: demo-order, demo-grpc, demo-graphql, demo-kafka (Avro byte), demo-tracing, demo-websocket, demo-reactive-vertx | 10.0 | todo |
| 10.7 | `demo-oidc.sh` (feasibility-gated, DRQ-005) | 10.0 | todo |
| 10.8 | Toolchain: demo-jbang-prototype, demo-continuous-testing, demo-native (≥1 native build) | 10.0 | todo |
| 10.9 | KEDA: demo-keda-kafka, demo-keda-http (minikube-gated) | step 9 | todo |
| 10.10 | `walkthrough.sh` five-act orchestrator | all | todo |

## Acceptance criteria

- `mvn verify` stays green with `ai-rules-service` joined; default build needs
  **neither Ollama nor a cluster** (isolated Drools unit test fires all 3 branches).
- Every demo asserts *positive content* (parsed id, Avro `0x0` byte, decision enum,
  trace-span count, replica delta) — not just exit 0; `set -uo pipefail` + `fail()`
  + success-flag trap so a short-circuited step can't report success.
- demo-ai-triage: ≥2 inputs → 2 distinct decisions, zero reliance on tool-calling.
- demo-ai-mcp prints the DEF-001 banner, asserts only the MCP-server surface.
- demo-native builds one native binary that boots + serves HTTP 200.
- Each matrix capability → exactly 1 demo + README + verifiable assertion.
- `walkthrough.sh` default acts complete with compose up; ollama/native/minikube
  acts gated behind flags; `--only`/`--skip`/`--no-preflight` work.

## Risks

- **Embedded Drools on JDK 25 / Quarkus 3.39.5** — caught by the 10.1 probe before
  module code; isolated Drools unit test in `mvn verify` fails the build (not just
  the demo) if the engine regresses.
- **Ollama nondeterminism** — assert the Drools decision (deterministic given
  extracted facts), not LLM text; enum-membership not exact match; opt-in only.
- **Green-wash demos** — mandatory content assertion + pipefail + success trap.
- **DEF-001 dishonesty** — caveat banner + MCP-surface-only assert + structurally
  separate module.
- **Reactor BOM skew from Drools** — inherit BOMs from parent, no module-level
  `dependencyManagement`, `dependency:tree` check in the probe, green `mvn verify`.
