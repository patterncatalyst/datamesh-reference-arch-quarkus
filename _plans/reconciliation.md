---
title: Reconciliation
description: Living map of python-repo artifacts to their Quarkus counterparts, with build status
---

# Reconciliation — datamesh-reference-arch-quarkus

Tracks drift between `../datamesh-reference-arch-python` (the source
reference) and this repo (the Quarkus rebuild). Each row is one artifact
— a chapter, a demo, a script, a deck, a config file — with its Quarkus
counterpart and a status. Update this file as artifacts are ported;
don't let it fall behind the build-plan step table in `build-plan.md`
(which tracks phases/skills, not per-artifact drift).

**Status legend:** `not ported` · `ported` · `ported (adapted)` · `verified` · `verified (partial)` · `conceptual` · `unverified` · `measured` · `deferred` · `n/a (python-only)`

`verified` means the artifact ran in a real environment and produced its claimed effect. `ported` means it exists with no recorded run. `verified (partial)` means some parts ran and the Notes name what did not. `not ported` means no counterpart exists; Notes say what covers it or that it was not carried over.

## Chapters (`_docs/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `_docs/00-index.md` | `_docs/00-index.md` | verified | Site builds with 0 errors; chapter links resolve |
| `_docs/01-concepts.md` | `_docs/01-concepts.md` | conceptual | Principles chapter; stack-agnostic, no runnable claims |
| `_docs/01-data-architectures.md` | `_docs/01-data-architectures.md` | conceptual | Architecture background; no runnable claims |
| `_docs/02-kubernetes-substrate.md` | `_docs/02-kubernetes-substrate.md` | verified | bootstrap.sh drove all eight tiers 2026-10-06 (50 pods Running); docker driver, Docker Engine (provided by Docker Desktop on the authoring host); Docker note updated (DRQ-003) |
| `_docs/03-services-and-data-products.md` | `_docs/03-services-and-data-products.md` | verified | `mvn verify` green; demo-order and demo-grpc passed; Quarkus Panache samples |
| `_docs/04-contracts-and-catalog.md` | `_docs/04-contracts-and-catalog.md` | verified (partial) | Avro wire assertion verified; incompatible-schema rejection by Apicurio not exercised; OpenMetadata not ported |
| `_docs/05-data-planes.md` | `_docs/05-data-planes.md` | verified (partial) | demo-graphql and demo-grpc passed; Camel YAML DSL variant not run |
| `_docs/06-progressive-delivery-mtls.md` | `_docs/06-progressive-delivery-mtls.md` | verified | Istio mTLS and 90/10 canary observed on minikube; selective injection by pod label |
| `_docs/07-elastic-and-resilient.md` | `_docs/07-elastic-and-resilient.md` | verified | KEDA scale-to-zero and lag scaling run 2026-10-06 (act 5); single run |
| `_docs/08-observability.md` | `_docs/08-observability.md` | verified (partial) | demo-tracing passed against compose otel-lgtm; mesh/Kiali view needs a live cluster |
| `_docs/09-anti-patterns.md` | `_docs/09-anti-patterns.md` | verified | "In this build" callouts confirmed by the Maven build and committed manifests |
| `_docs/10-summary.md` | `_docs/10-summary.md` | verified | Architectural claims confirmed by build and `k8s/` manifests; runtime claims covered in chapters 6 and 7 |
| _(none — new)_ | `_docs/11-quarkus-capability-tour.md` | verified | Demos for each capability passed; native run 2026-10-06 (single run); Panache example is illustrative |
| _(none — new)_ | `_docs/12-quarkus-vs-spring-boot.md` | verified | compare script run 2026-10-05, JVM and `--aot`; single run, not a benchmark |
| _(none — new)_ | `_docs/13-orchestration-styles.md` | verified | demo-orchestration-styles passed with Ollama (acts 2-3); unit tests green |
| _(none — new)_ | `_docs/14-ai-rules-triage.md` | verified | demo-ai-classify, demo-ai-mcp, demo-camel-integration, demo-ai-triage passed with Ollama qwen2.5:3b |
| _(none — new)_ | `_docs/16-websocket-scaling.md` | verified | Two-replica fan-out on minikube; replica failure and client reconnect verified 2026-10-06 with `tooling/ws-failover/verify-ws-failover.sh` (#48) |
| _(none — new)_ | `_docs/17-gotchas.md` | verified | Fixes re-run green by `mvn verify` |
| _(none — new)_ | `_docs/18-agentic-recommendations.md` | conceptual | Distilled recommendations; no build or demo; upstream langchain4j defect claim to re-check |
| _(none — new)_ | `_docs/19-testing-details.md` | verified | Automated tiers green; Newman 49/49 and hey/ghz load passes ran 2026-10-06 via `run-all-tests.sh --load` (#47) |
| _(none — new)_ | `_docs/20-messaging-in-memory-vs-kafka.md` | verified (partial) | In-memory connector tests green; Vert.x event-bus and Kafka scaling material conceptual |
| _(none — new)_ | `_docs/21-orchestration-engines-compared.md` | verified | Orchestration tests green; demos passed with Ollama 2026-10-06 (single run) |

## Services (`examples/lgtm-datamesh/services/` → `examples/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `services/order-service` | `examples/order-service` | verified | Panache + REST; primary data product; `mvn verify` 2026-10-06; exercised by demo-order |
| `services/inventory-service` | `examples/inventory-service` | verified | `mvn verify` 2026-10-06; exercised by demo-grpc |
| `services/payment-service` | `examples/payment-service` | verified | `mvn verify` 2026-10-06; Avro choreography processor (DRQ-010), exercised by demo-kafka |
| `services/shipping-service` | `examples/shipping-service` | verified | `mvn verify` 2026-10-06; in-memory connector tests; exercised by demo-reactive-vertx |
| `services/notification-service` | `examples/notification-service` | verified | Kafka consumer via Reactive Messaging; `mvn verify` 2026-10-06; exercised by demo-websocket and demo-keda-kafka |
| `services/review-service` | `examples/review-service` | verified | `mvn verify` 2026-10-06 |
| `services/graphql-gateway` | `examples/graphql-gateway` | verified | SmallRye GraphQL; `mvn verify` 2026-10-06; exercised by demo-graphql and demo-keda-http |
| `proto/capstone/*.proto` | `examples/*/proto/*.proto` | verified | Protos live in `examples/contracts/src/main/proto`; used by gRPC demo and `mvn verify` |
| _(none — new)_ | `examples/spring-boot-compare` (order-service twin) | verified | Outside the reactor; chapter 12 footer: twin `mvn verify` passed, compare script run 2026-10-05 (DRQ-006) |
| _(none — new)_ | `examples/domain-model` | verified | Shared framework-agnostic entities; reactor module, `mvn verify` 2026-10-06 |
| _(none — new)_ | `examples/ai-rules-service` | verified | Ollama classify + Drools decide (DRQ-012/014); `mvn verify` 2026-10-06; exercised by demo-ai-triage |
| _(none — new)_ | `examples/contracts` | verified | Avro and gRPC contract module; `mvn verify` 2026-10-06 |
| _(none — seed)_ | ported from `enterprise-integration-patterns-with-camel/examples/42-ai-mcp/quarkus` | verified | Landed as `examples/ai-mcp-service`; `mvn verify` 2026-10-06; exercised by demo-ai-mcp |

## Demos (`examples/lgtm-datamesh/demos/` → `demos/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `demos/demo-order.sh` | `demos/demo-order.sh` | verified | 2026-10-06 walkthrough; Panache + REST data product |
| `demos/demo-grpc.sh` | `demos/demo-grpc.sh` | verified | 2026-10-06 walkthrough; quarkus-grpc |
| `demos/demo-graphql.sh` | `demos/demo-graphql.sh` | verified | 2026-10-06 walkthrough; SmallRye GraphQL |
| `demos/demo-kafka.sh` | `demos/demo-kafka.sh` | verified | 2026-10-06 walkthrough; Reactive Messaging; also asserts Avro magic byte |
| `demos/demo-avro.sh` | (fold into demo-kafka.sh or contracts chapter) | not ported | Folded into demo-kafka.sh (raw-byte Avro assertion) and `OrderPlacedAvroWireIT`; DRQ-009, DEF-002; absent from build-plan demo matrix |
| `demos/demo-canary.sh` + `demo-canary-verify.sh` | `demos/demo-canary.sh` (+ verify) | not ported | No demo script; canary delivered as `k8s/istio/` manifests, verified manually (70 requests, 63 v1 / 7 v2) and documented in chapter 6; absent from build-plan demo matrix |
| `demos/demo-keda-http.sh` | `demos/demo-keda-http.sh` | verified | 2026-10-06 act 5: graphql-gateway 0→1 through the interceptor (port 8080), 120/120 GraphQL POSTs returned 200; starts from zero after KEDA's scale-down window |
| `demos/demo-keda-kafka.sh` | `demos/demo-keda-kafka.sh` | verified | 2026-10-06 act 5: notification-service 0→1 on lag from 60 orders, drained to 0 after cooldown; starts from zero |
| `demos/demo-observability.sh` / `demo-tracing.sh` | `demos/demo-tracing.sh` | verified | 2026-10-06 walkthrough; OpenTelemetry; cross-service trace against compose otel-lgtm |
| `demos/demo-discovery.sh` | `demos/demo-discovery.sh` | not ported | No OpenMetadata deployment in this repo; chapter 4 states the gap; absent from build-plan demo matrix |
| `demos/demo-om-lineage.sh` / `demo-openmetadata.sh` | `demos/demo-om-lineage.sh` | not ported | OpenMetadata not carried over (chapter 4 states the gap); absent from build-plan demo matrix |
| `demos/demo-kiali.sh` | `demos/demo-kiali.sh` | not ported | Kiali installed by `scripts/setup-kiali.sh`; no standalone demo script; absent from build-plan demo matrix |
| `demos/demo-notifications.sh` | `demos/demo-notifications.sh` | not ported | Covered by demo-websocket.sh and demo-keda-kafka.sh; absent from build-plan demo matrix |
| `demos/demo-reviews.sh` | `demos/demo-reviews.sh` | not ported | review-service has no standalone demo; covered by `mvn verify`; absent from build-plan demo matrix |
| `demos/demo-service.sh` | `demos/demo-service.sh` | not ported | Per-service smoke pattern replaced by `demos/lib/_demo.sh` and the per-capability demos |
| `demos/demo-trace-flow.sh` | `demos/demo-trace-flow.sh` | not ported | Folded into demo-tracing.sh (cross-service trace); absent from build-plan demo matrix |
| `demos/demo-add-data-product.sh` | `demos/demo-add-data-product.sh` | not ported | No `scaffold-service.sh` carried over; absent from build-plan demo matrix |
| `demos/walkthrough.sh` | `demos/walkthrough.sh` | verified | Drove all five acts 2026-10-06 (19 demos, `--with-ollama --with-native --with-minikube`); five-act structure preserved |
| _(none — new)_ | `demos/demo-jbang-prototype.sh` | verified | 2026-10-06 walkthrough; jbang / Camel CLI prototyping |
| _(none — new)_ | `demos/demo-continuous-testing.sh` | verified | 2026-10-06 walkthrough; Quarkus continuous testing + Dev Services |
| _(none — new)_ | `demos/demo-ai-classify.sh` | verified | 2026-10-06 walkthrough; langchain4j, seeded from 42-ai-mcp `OrderClassifierRoute`; Ollama qwen2.5:3b |
| _(none — new)_ | `demos/demo-ai-mcp.sh` | verified | 2026-10-06 walkthrough; langchain4j + MCP, seeded from 42-ai-mcp `OrderLookupToolRoute`; Ollama |
| _(none — new)_ | `demos/demo-camel-integration.sh` | verified | 2026-10-06 walkthrough; Quarkus + Camel EIPs; Ollama |
| _(none — new)_ | `demos/demo-websocket.sh` | verified | 2026-10-06 walkthrough; websocket.next |
| _(none — new)_ | `demos/demo-oidc.sh` | verified | 2026-10-06 walkthrough; quarkus-oidc against a live Keycloak Dev Service |
| _(none — new)_ | `demos/demo-reactive-vertx.sh` | verified | 2026-10-06 walkthrough; Vert.x unified reactive + imperative |
| _(none — new)_ | `demos/demo-native.sh` | verified | 2026-10-06 walkthrough; Mandrel builder container, single run |
| _(none — new)_ | `demos/demo-ai-triage.sh` | verified | 2026-10-06 walkthrough; Camel route and Quarkus Flow A/B; Ollama |
| _(none — new)_ | `demos/demo-orchestration-styles.sh` | verified | 2026-10-06 walkthrough; choreography, Camel, and Flow over one domain; Ollama |
| _(none — new)_ | `demos/demo-panama.sh` | verified | 2026-10-06 walkthrough; see Panama row below |

## Scripts (`scripts/` and `examples/lgtm-datamesh/scripts/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `scripts/bootstrap-capstone.sh` | `scripts/bootstrap.sh` | verified | 2026-10-06 ran all 8 steps; docker-compose + minikube split |
| `scripts/check-cross-references.sh` | `scripts/check-cross-references.sh` | not ported | Not carried over; build-plan risk list planned the port, none landed; build-plan step 3 site build checks links |
| `scripts/check-liquid-collisions.sh` | `scripts/check-liquid-collisions.sh` | not ported | Not carried over; build-plan risk list planned the port, none landed |
| `scripts/splice-diagrams.sh` | `scripts/splice-diagrams.sh` | not ported | Replaced by `scripts/make-*-diagrams.js` and `svglib.js` |
| `scripts/sync-example-pages.sh` | `scripts/sync-example-pages.sh` | not ported | Not carried over; chapters link examples via `site.repo_blob` |
| `scripts/setup-istio.sh` | `scripts/setup-istio.sh` | verified | Via `lgtm-minikube-stack`; 2026-10-06 bootstrap |
| `scripts/setup-keda.sh` | `scripts/setup-keda.sh` | verified | Via `lgtm-minikube-stack`; 2026-10-06 bootstrap, Helm repo name match fixed |
| `scripts/setup-strimzi.sh` | `scripts/setup-strimzi.sh` | verified | Landed as `scripts/setup-kafka-operator.sh`; 2026-10-06 bootstrap |
| `examples/.../scripts/setup-postgres-operator.sh` | `scripts/setup-postgres-operator.sh` | verified | Via `lgtm-minikube-stack` (CloudNativePG); 2026-10-06 bootstrap |
| `examples/.../scripts/setup-openmetadata.sh` / `ingest-openmetadata.sh` | `scripts/setup-openmetadata.sh` / `ingest-openmetadata.sh` | not ported | OpenMetadata not carried over (chapter 4 states the gap) |
| `examples/.../scripts/setup-observability.sh` | `scripts/setup-observability.sh` | verified | Landed as `scripts/setup-lgtm.sh`; 2026-10-06 bootstrap |
| `examples/.../scripts/scaffold-service.sh` | `scripts/scaffold-service.sh` | not ported | Not carried over; absent from build-plan |
| `examples/.../scripts/gen-protos.sh` | `scripts/gen-protos.sh` | not ported | Protos and Avro generated by the Maven build in `examples/contracts` |
| `examples/.../scripts/restore-baseline.sh` | `scripts/restore-baseline.sh` | not ported | Not carried over; absent from build-plan |
| `examples/.../scripts/teardown.sh` | `scripts/teardown.sh` | ported | Exists; not separately verified |
| `examples/.../scripts/cluster-up.sh` / `cluster-status.sh` | `scripts/cluster-up.sh` / `cluster-status.sh` | ported | `cluster-up` landed as `setup-profile.sh` (rewritten; re-verification pending); `cluster-status.sh` exists, not separately verified |
| `demos/lib/endpoints.sh` + `scripts/show-endpoints.sh` (Python `examples/lgtm-datamesh/`) | `demos/lib/endpoints.sh` + `scripts/show-endpoints.sh` | unverified (pending live run) | Replaces the old forwarding helper (DRQ-016) |
| `examples/.../scripts/publish-discovery-contracts.sh` | `scripts/publish-discovery-contracts.sh` | not ported | Not carried over; no OpenMetadata discovery here (chapter 4) |
| `scripts/audit-fedora-prereqs.sh` | (evaluate: docker prereq audit) | not ported | Fedora-specific audit; dropped, no docker audit written; `setup-profile.sh` pre-flight covers it |
| `scripts/forbidden-syntax.sh` (Python repo) | `scripts/forbidden-syntax.sh` | unverified (pending live run) | Scans 1-5 ported plus scan 6 for other-OS mentions (DRQ-017) |
| `.github/workflows/checks.yml` (Python repo) | `.github/workflows/checks.yml` | unverified (pending live run) | Runs the gate on push and pull request |
| gRPC resolver fix (Python DRA-017/019) | (none) | not applicable | Quarkus clients use the JDK/Netty resolver and `INVENTORY_GRPC_HOST` is an FQDN |
| `scripts/editorial-audit.sh` | `scripts/editorial-audit.sh` | not ported | Not carried over; `lgtm-professional-voice` scan covers it |
| `scripts/test-template.sh` | `scripts/test-template.sh` | not ported | Not carried over; `scripts/run-all-tests.sh` is the test entry point |
| _(none — new)_ | `tooling/newman/`, `tooling/load/` | verified | 2026-10-06 `run-all-tests.sh --load`: Newman 49/49; hey ~18k req/s all 200; ghz ~12k calls/s, 8 Unavailable + 1 Canceled; newman 6.2.2, hey v0.1.5, ghz v0.121.0 pinned |
| _(none — new)_ | `tooling/ws-failover/verify-ws-failover.sh` + `demos/jbang/WsReconnectClient.java` | verified | 2026-10-06 on minikube: replica deleted, client reconnected (979 ms backoff), catch-up without duplicate, next order from the survivor |
| `examples/.../scripts/build-image.sh` | `scripts/build-image.sh` | not ported | Folded into `scripts/load-images.sh` (docker build + minikube image load); UBI Containerfiles |
| _(none — new)_ | `scripts/load-images.sh` | verified | Builds service images and loads them into minikube (containerd); 2026-10-06 act 5 |
| _(none — new)_ | `scripts/setup-profile.sh` | rewritten; re-verification pending | minikube profile; first verified via the 2026-10-06 bootstrap, since rewritten for published NodePorts |
| _(none — new)_ | `scripts/setup-lgtm.sh`, `setup-kiali.sh`, `setup-apicurio.sh`, `setup-kafka-operator.sh` | verified | 2026-10-06 bootstrap |
| _(none — new)_ | `scripts/run-all-tests.sh` | ported | Test-pyramid runner; exists, not separately verified |

## Deck (`presentation/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `presentation/data-mesh-101/` | `presentation/datamesh-quarkus-101/` | ported (adapted) | Landed as `presentation/datamesh-101/` (r1.1, 17 slides); built with `lgtm-presentation` |
| `presentation/data-mesh-openshift/` | `presentation/datamesh-quarkus-openshift/` | deferred | Lower priority than the primary deck; revisit after core demos land |
| _(none — new)_ | `presentation/datamesh-201/` | ported (adapted) | r1.1, 102 slides; Quarkus-specific deck (capability tour, comparison, KEDA)|
| _(none — new)_ | Notion 1-hour abstract page | not ported | Build-plan step 15 still pending; lives in Notion, not in this repo |

## Other project docs

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `PRD.md` | `PRD.md` | ported (adapted) | This pass |
| `_plans/decisions.md` (DRA-series) | `_plans/decisions.md` (DRQ-series) | ported (adapted) | Distinct numbering series, per python precedent |
| `_plans/reconciliation.md` (verification-claim log) | `_plans/reconciliation.md` (this file — artifact map) | ported (adapted) | Different shape deliberately: this file tracks artifact-level porting status; add a verification-claim log section once demos are runnable |
| `README.md` | `README.md` | ported | Exists; not separately verified |
| `onboarding/GETTING-STARTED.md` | `onboarding/GETTING-STARTED.md` | not ported | No `onboarding/` directory; README and `demos/README.md` cover setup |
| `onboarding/LESSONS-LEARNED.md` | `onboarding/LESSONS-LEARNED.md` | not ported | Not started; lessons recorded in `_docs/17-gotchas.md` and `_plans/RESUME.md` |
| `.github/workflows/pages.yml` | `.github/workflows/pages.yml` | ported | Exists; not separately verified |
| `_plans/archive/` (CAP-series history) | _(n/a)_ | n/a (python-only) | This repo's own history starts at DRQ-001; no capstone archive to port |

## New artifacts with no python source

These exist only because of the Quarkus-specific goal (see PRD §3/§5) and
have no reconciliation target — listed here so they aren't mistaken for
missing ports:

- `_docs/11-quarkus-capability-tour.md`, `_docs/12-quarkus-vs-spring-boot.md`
- `examples/spring-boot-compare/`
- `demos/demo-jbang-prototype.sh`, `demo-continuous-testing.sh`,
  `demo-ai-classify.sh`, `demo-ai-mcp.sh`, `demo-camel-integration.sh`,
  `demo-websocket.sh`, `demo-oidc.sh`, `demo-reactive-vertx.sh`,
  `demo-native.sh`
- The `lgtm-docker-stack` skill itself (DRQ-003)

## Professional content pass additions (no python source)

Entries added by the `docs/professional-content-pass` branch. Status
describes what actually ran: `verified` means the demo or script ran in this
environment; `measured` means numbers were captured; `unverified` means the
content is explanatory or conceptual and was not run.

| Artifact | Counterpart | Status | Notes |
|---|---|---|---|
| _(none — new)_ | `_docs/11-quarkus-capability-tour.md`: twelve-capability tour (was nine; ten in practice) | verified (adapted) | Adds JDK AOT cache (Leyden), Panama FFM, Panache patterns, Uni and imperative subsection. Native image verified 2026-10-06 via `demo-native.sh` (Mandrel builder container: 136 s build, 141 MB binary, 0.081 s startup, single run); Figures 11.6 and 11.7 draw the native and AOT cache build pipelines |
| _(none — new)_ | `demos/demo-panama.sh`, `demos/jbang/PanamaFfm.java` | verified | Ran on JDK 25.0.3 with JBang 0.138.0: `PANAMA_GETPID` equals `JVM_PID`, `PANAMA_STRLEN` equals `JAVA_LENGTH` (31). Linux only (libc default lookup) |
| _(none — new)_ | JDK 25 AOT cache comparison: `scripts/compare-quarkus-springboot.sh --aot`, `_docs/12-quarkus-vs-spring-boot.md` | measured | Temurin 25.0.3, 2026-10-05, single run; startup, RSS, and cache size recorded in chapter 12. Not a benchmark |
| _(none — new)_ | Figure `11-panache-patterns` | unverified | Explanatory; the `PanacheRepository` example in chapter 11 is illustrative and not run |
| _(none — new)_ | Figure `11-uni-vs-imperative` | unverified | Explanatory; grounded in `InventoryGrpcService.checkStock` and `StockResource.get` |
| _(none — new)_ | Figure `11-websockets-next` | unverified | Explanatory; legacy versus Next comparison |
| _(none — new)_ | Figure `11-jbang-tooling` | unverified | Explanatory; the three scripts in `demos/jbang` are run by their demos |
| _(none — new)_ | Figure `11-startup-paths` | unverified | Qualitative; numbers are in chapter 12 |
| _(none — new)_ | Figure `11-panama-ffm` | unverified | Explanatory; the code it describes was run (see Panama row) |
| _(none — new)_ | Figure `11-oidc-token-flow` | unverified | Explanatory; the flow matches what `demo-oidc.sh` exercised |
| _(none — new)_ | Figure `16-websocket-failover` | verified | The drawn flow matches the 2026-10-06 `verify-ws-failover.sh` run: socket closed on replica loss, jittered backoff, reconnect, catch-up via `GET /notifications` |
| _(none — new)_ | Figure `20-vertx-in-memory` | unverified | Event bus usage is illustrative; the project uses the in-memory connector in shipping-service tests |
| _(none — new)_ | Figure `20-kafka-messaging` | unverified | Explanatory; consumer groups and partitions as used by the Kafka legs |

## How to keep this current

Update a row's status when the corresponding artifact is created or
substantively changed:

- `not ported` → `ported` when the counterpart is created: `ported` (content matches the python source's intent,
  adapted only for language/framework) or `ported (adapted)` (the
  Quarkus version deliberately diverges in scope or approach — note why).
- `deferred` when explicitly postponed — cross-reference the
  `_plans/decisions.md` entry or `_plans/build-plan.md` risk that
  explains the deferral.
- Promote to `verified` only after a real run that produced the claimed
  effect, and record the date in Notes.
- Add new rows immediately when a new artifact (python-sourced or
  Quarkus-only) is created — don't batch updates until the end of a
  phase.
