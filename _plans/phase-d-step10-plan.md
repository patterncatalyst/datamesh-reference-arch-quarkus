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
| 10.0 | Shared harness `demos/lib/_demo.sh` + `demos/README.md` | — | **done** (committed; `info()` fixed to write to stderr so `svc_start_dev`'s pidfile-on-stdout contract holds) |
| 10.1 | Embedded-Drools light probe (drools-core + trivial `.drl`, JDK25/Q3.39.5) | — | **done — GO**: Drools 10.2.0 works on JDK25. Deps: `drools-bom:10.2.0` (import) + `drools-engine:10.2.0` + **`drools-mvel:10.2.0`** (required — ConstraintBuilder SPI). Recipe: in-memory `KieHelper.build()` → `KieBase` at `StartupEvent`, `KieSession` per request. Skews trivial. JVM-only. |
| 10.2 | `examples/ai-rules-service` module: Camel `OrderTriageRoute` + `.drl` + isolated Drools unit test (in `mvn verify`, no Ollama) + opt-in Ollama IT | 10.1 | **done** (committed; reactor green, 5 tests) |
| 10.1b | Quarkus Flow version/compat spike (quarkus-flow-bom on Q3.39.5/JDK25; coexist w/ camel-quarkus+langchain4j) | — | **done — GO**: `quarkus-flow-bom:1.1.3` imported LAST (after langchain4j→quarkus→camel), `quarkus-flow` version-less. No kogito/kie/drools pulled; no conflicts; serverlessworkflow-api 7.32.1.Final. Wire steps via `FlowDSL.function(name, bean::method)` + `switchCase(caseOf(...).then(...), caseDefault(...))`; **terminate branches with `.then(FlowDirectiveEnum.END)`** or they fall through. JVM clean on JDK25. |
| 10.2b | DRQ-014: add Quarkus Flow orchestration of triage to `ai-rules-service` (`POST /api/orders/triage-flow`), reuse DRL + classify + facts; unit test the workflow path | 10.2, 10.1b | **done** (committed; shared TriageService, 8 tests, reactor green, Flow pulls serverlessworkflow only) |
| 10.3 | `demos/demo-ai-triage.sh` showcase — assert decision enum on BOTH `/triage` (Camel) and `/triage-flow` (Flow); DEF-001-proof | 10.2, 10.2b | **done** (live-run ×2; 6 strict + 6 membership + 6 reason-nonnull assertions across both endpoints × 3 inputs) |
| 10.4 | Honest `demo-ai-classify.sh` + `demo-ai-mcp.sh` (MCP path + caveat) | 10.0 | **done** (both live-run ✓). classify asserts strict `.category` on 3 pre-validated inputs (PERISHABLE/HAZARDOUS/FRAGILE) + presence of priority/fulfillmentType. ai-mcp speaks real MCP Streamable-HTTP JSON-RPC (initialize/tools-list/tools-call), asserts `order-status` tool + ORD-001/2/3 payload; loud DEF-001 banner, never asserts in-process tool-calling. **Surfaced + fixed a real classify-route bug** (`fix(ai-mcp)` b42a4cf: wrong prompt header + chat op). |
| 10.5 | `demo-camel-integration.sh` | 10.0 | **done** (live-run ✓). Targets `OrderLookupToolRoute`'s Content-Based Router EIP — exercises all 4 branches incl. `.otherwise()` fallback (ORD-NO-SUCH-ORDER → not-found) via MCP `tools/call`. EIP-centric narration, distinct from demo-ai-mcp. (Only 4 RouteBuilders exist; the other 3 are used by 10.3/10.4.) |
| 10.6 | Core: demo-order, demo-grpc, demo-graphql, demo-kafka (Avro byte), demo-tracing, demo-websocket, demo-reactive-vertx | 10.0 | **done** (all 7 live-run ✓, packaged `quarkus-run.jar` on compose baseline, prod profile — except demo-reactive-vertx which uses Dev Services, no real external infra needed). Part 1: order (REST round-trip + `psql` row assert), grpc (`grpcurl` reflection + `CheckStock`), graphql (stitched `order{...stock{...}}` asserting `.data` incl. gRPC leg), kafka (`kcat` leading `0x00` Avro byte + Apicurio artifact, DEF-002). Part 2 (committed 627318e): tracing (OTel `-javaagent` → Tempo API, asserts ≥5 spans + both service.name + CheckStock span), websocket (new `/ws/notifications` `@WebSocket` + `OrderPlacedConsumer` broadcast via `OpenConnections`; JDK `java.net.http.WebSocket` client via jbang asserts live push after a real `order.placed`), reactive-vertx (gRPC `Uni` vs imperative REST on same stock table). See Findings below (F1 now has a confirmed consumer-side instance). |
| 10.7 | `demo-oidc.sh` (feasibility-gated, DRQ-005) | 10.0 | **done — GO (live, not deferred)** (committed 6fc5d58). Quarkus OIDC + Keycloak Dev Service needs zero `quarkus.oidc.*` config (auto realm `quarkus`/client `quarkus-app`/users alice=admin+user, bob=user). Minimal source: added one admin-only `DELETE /reviews/{id}` `@RolesAllowed("admin")` to review-service (smallest service, no gRPC/Kafka, no other demo touches it) + `quarkus-oidc` dep; all existing endpoints byte-unchanged. `mvn verify` green (5 tests, oidc+security installed). Demo (Dev Services, no compose) asserts 401 no-token, 403 bob/user-role (bonus RBAC), 204 alice/admin + 404 follow-up. Live-run ×2 to SUCCESS per executor; orchestrator verified build+diffs, deferred live re-run (docker contention w/ concurrent orchestration-styles run). |
| 10.8 | Toolchain: demo-jbang-prototype, demo-continuous-testing, demo-native (≥1 native build) | 10.0 | **done** (all 3 real-run end-to-end: jbang via `camel@apache/camel run` on single `.java`; continuous-testing via `quarkus:dev` + `QUARKUS_TEST_CONTINUOUS_TESTING=enabled`, parsed test counts; native via Mandrel `jdk-25` container-build 84s + throwaway `docker run` pg. Each gates its toolchain + fails loud w/ install hint. `TZ=UTC` needed client-side for Dev Services + native runtime — pg18 rejects `US/Eastern`) |
| 10.9 | KEDA: demo-keda-kafka, demo-keda-http (minikube-gated) | step 9 | **done — author-only** (no live cluster here). Both reference real step-9 manifests (`k8s/keda/{consumer-scaledobject,gateway-httpscaledobject}.yaml`, `k8s/overlays/minikube`); run `kubectl kustomize` in-script + grep-assert the rendered ScaledObject/HTTPScaledObject; no-cluster gate fails loud → `./scripts/bootstrap.sh`. Live path asserts jsonpath-parsed replica delta. Use bundled `kubectl kustomize` (no standalone binary). **Substrate gap (DEFER):** `order-service` hardcodes `quarkus.grpc.clients.inventory.host=localhost`, no `%prod`/env override in `k8s/base/*` → `POST /orders` 503s on cluster, no `order.placed` emitted. kafka demo documents + fails honestly rather than faking a bypass producer. |
| DRQ-015 | `demo-orchestration-styles.sh` — three-engine comparison (Kafka choreography / Camel / Quarkus Flow) | 10.3, 10.6 | **done** (committed 8b1ae7f; live-run ×3 to SUCCESS). ACT1 Kafka choreography (order.placed→payment.captured→shipment.dispatched, kcat `0x00` magic byte ×2 + `shippingdb.shipment` row + notifications), ACT2 Camel `/triage` strict `ROUTE_TO_WAREHOUSE`, ACT3 Flow `/triage-flow` same. Per-hop `SERIALIZABLE_PACKAGES` scoped per service; inventory grpc 9001; ollama via compose profile. Narrated choreography-vs-orchestration recap. Runtime `-D`/env only. |
| 10.10 | `walkthrough.sh` five-act orchestrator | all | **done** (committed bda49ba). 18 demos→5 acts (ACT1 data products+protocols+oidc / ACT2 DRQ-015 orchestration-styles / ACT3 AI+Camel+Drools+MCP / ACT4 dev-experience+native / ACT5 KEDA). Per-demo gating `--with-ollama`/`--with-native`/`--with-minikube` (SKIPPED not failed when absent); `--only`/`--skip` (exact names, mutually exclusive), `--no-preflight`, `--no-pause`/`--auto`, `-h`. Invokes each demo as a child via `run_act`; pass-fail-skip tally + non-zero exit on any non-skipped fail. Executor caught+fixed a real `DEMO_NAME`-array vs lib-global collision. Orchestrator re-verified independently: `--help`, live `--only demo-order --auto --no-preflight` (SUCCESS, child compose cleaned), bad-name→exit1 (lists all 18), `--only`+`--skip`→exit1, gated-skip (native/keda)→exit0 SKIPPED. Not run: full 5-act live pass (hours; individual demos already verified). |

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

## Findings surfaced by the demo runs (candidate deferrals — NOT fixed in source)

Demos ran against the real packaged `%prod` services + compose baseline (not
just Dev Services), which exposed genuine **production-readiness** gaps in the
step-7/8 service code. Each was worked around at the *demo-script* level (runtime
`-D`/env only, documented inline) to keep the demos honest; none is fixed in
module source. These are for the **post-step-10 reassessment** (DRQ-013) to
triage — several undermine the headline "order placement emits events and
autoscales" narrative when actually deployed (K8s/packaged), so they likely
warrant real fixes before chapters/deck (steps 11/13) and before any publish.

> **Update (post-step-10 reassessment, HIGH findings fixed + validated).** The
> three HIGH findings F1/F1b/F2 were fixed in source via the lgtm-relay
> (plan→execute→validate) and merged onto `build/phase-d-step10-demos`:
> `60d035f fix(avro)` (image-intrinsic `JAVA_TOOL_OPTIONS` Avro trusted-packages
> on all 4 Avro services) and `e8f78d5 fix(grpc)` (canonical gRPC port 9000,
> env-overridable both sides, new inventory-service image + `k8s/base/
> inventory-service.yaml` + ConfigMap wiring). **Opus live validation PASSED all
> 6 criteria**: `mvn verify` green with DEF-002 IT intact; `kubectl kustomize`
> renders inventory + env; and the real-image proof — built order/inventory
> images, ran against compose with NO `-D` overrides: `Picked up
> JAVA_TOOL_OPTIONS=...capstone.order.v1`, zero `SecurityException`, a genuine
> `0x00`-magic-byte Avro `order.placed` record published, and `POST /orders` →
> 201 (gRPC CheckStock connected on default 9000). The deployed choreography now
> actually emits events, so KEDA-on-Kafka-lag has something to scale on.
> **F3 resolved won't-fix/documented** (see F3 entry below). **F4/F5/F6/F7 all
> RESOLVED + validated** (lgtm-relay, Opus verdict FIXES SOUND) in four commits on
> `fix/phase-d-low-findings`: `fix(gateway)...(F4)`, `fix(shipping)...(F5)`,
> `fix(order)...(F6)`, `fix(inventory)...(F7)`. `mvn verify` green on all four
> touched modules with DEF-002 `OrderPlacedAvroWireIT` intact (Tests run: 1,
> Failures: 0). **F6** (order-service non-fatal `FileHandler.setFile` startup
> trace — quarkus.log.file on a path non-root UID 185 can't write) fixed by gating
> file logging to `%dev`/`%test` so `%prod` is console-only per 12-factor. **F7**
> (inventory `import.sql` Postgres `null value in column "id"` seed warning) fixed
> by switching `Stock` to `PanacheEntityBase` + `GenerationType.IDENTITY`. With
> these, all step-10 review findings F1–F7 are closed.

- **F1 — order.placed never publishes in packaged/%prod runs (HIGH).** Avro
  1.12 `ClassSecurityValidator` throws `SecurityException: Forbidden
  capstone.order.v1.OrderPlaced!` from a plain `java -jar` JVM (a
  Quarkus-bootstrapped dev/test JVM trusts app packages; a packaged one does
  not). `OrderEventProducer`'s failure is caught-and-logged, so `POST /orders`
  still returns 201 — the failure is invisible without reading logs. Fix already
  named in DEF-002 for the IT: set `org.apache.avro.SERIALIZABLE_PACKAGES=
  capstone.order.v1` (via `JAVA_TOOL_OPTIONS`/image env for real deploys).
  demo-kafka.sh caught this (kcat timed out — nothing was produced). **Converges
  with 10.9's substrate gap** — together they mean the real deployed flow emits
  no events, so KEDA-on-Kafka-lag has nothing to scale on.
  **F1b — SECOND instance, consumer side (HIGH, found wiring demo-websocket.sh).**
  The identical `SERIALIZABLE_PACKAGES` requirement hits the **consumer**:
  notification-service is the only service that *deserializes* `OrderPlaced` back
  into a `capstone.order.v1` `SpecificRecord`, and its packaged `%prod` JVM throws
  the same `ClassSecurityValidator` `SecurityException` without
  `-Dorg.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1`. Previously only the
  producer side was documented (DEF-002). So the real fix must set this on **both**
  producer and consumer JVMs (via `JAVA_TOOL_OPTIONS`/image env) — worth flagging
  upstream as a second, previously-undetected instance of the same pattern.
- **F2 — order→inventory gRPC wiring broken in prod (HIGH).** order-service
  pins `quarkus.grpc.clients.inventory.port=9001` (and host `localhost`, per
  10.9) with no `%prod`/env override; inventory-service's gRPC server defaults
  to 9000 and `k8s/base/*` sets no inventory Service/env. Side-by-side packaged
  runs never connect; on-cluster `POST /orders` fails closed (503). Demos
  force `-Dquarkus.grpc.server.port=9001` on inventory-service.
- **F3 — seed data never loads in packaged/%prod (MEDIUM) — DISPOSITION: WON'T-FIX / DOCUMENTED.**
  inventory-service's `%prod.quarkus.hibernate-orm.database.generation=${DB_GENERATION:update}`
  (deprecated alias) overrides `schema-management.strategy=drop-and-create`, so
  `import.sql` (WIDGET-1/2, GADGET-1) is skipped outside dev/test. Demos seed via
  the existing `POST /stock` convenience endpoint.
  **Resolved as working-as-intended:** auto-seeding `%prod` would require
  `create`/`drop-and-create` generation and its data-loss risk, which is against
  secure-by-design defaults for a real deployment — an empty inventory on a fresh
  `%prod` deploy is correct. Seeding is done over the REST surface (demos +
  `walkthrough.sh` already do this). Documented in
  `examples/inventory-service/README.md` ("Seeding in `%prod`"). No source change.
- **F4 — GatewayApi.order() 404→null branch is dead code (LOW) — RESOLVED.** MP REST Client
  throws `WebApplicationException` for any non-2xx regardless of the `Response`
  return type, so the `if (status==NOT_FOUND) return null` line never runs.
  Client-visible end state (`.data.order==null`) happens to match intent but
  arrives via a `.errors` `DataFetchingException`. demo-graphql.sh asserts the
  *actual* behavior, not the intended one.
  **Fixed:** dead branch removed, `OrderRestClient` javadoc corrected, and the
  `GatewayApiTest` negative-control reworked to mock a thrown `WebApplicationException`
  and assert the real `DataFetchingException` path. demo-graphql.sh assertions
  unchanged (narration only).
- **F5 — `Shipment` entity has no `@Column` overrides (LOW, cosmetic) — RESOLVED.** Unlike
  `Order` (explicit `customer_id`/`item_sku`/…), `shipping-service`'s `Shipment`
  uses Hibernate default naming → columns `orderid`/`customerid`/`trackingnumber`/
  `dispatchedat` (lowercased, no underscores). Hibernate round-trips it correctly;
  only matters for hand-written SQL (demo-orchestration-styles.sh's `psql` assert
  uses `orderid`, documented inline). Not a functional gap — a naming-consistency
  nit vs the other entities; optional tidy-up before chapters/deck.
  **Fixed:** snake_case `@Column(name=...)` added (`order_id`/`customer_id`/`item_sku`/
  `tracking_number`/`dispatched_at`); demo-orchestration-styles.sh psql assert updated
  in lockstep. %prod `update`-generation note: on an EXISTING shippingdb Hibernate
  adds the new columns and leaves the old lowercased ones as nullable orphans — run
  the demo against a fresh shippingdb for a clean schema (dev/test drop-and-create
  is clean).
- **Demo-only (not source bugs):** gRPC reflection is dev/test-only (packaged
  needs `-Dquarkus.grpc.server.enable-reflection-service=true`); grpcurl JSON is
  proto3 snake_case + omits defaults (`-emit-defaults`). Handled in the scripts.
