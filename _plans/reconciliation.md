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

**Status legend:** `not started` · `in progress` · `ported` · `ported (adapted)` · `deferred` · `n/a (python-only)`

## Chapters (`_docs/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `_docs/00-index.md` | `_docs/00-index.md` | not started | |
| `_docs/01-concepts.md` | `_docs/01-concepts.md` | not started | Principles content is stack-agnostic; port near-verbatim |
| `_docs/01-data-architectures.md` | `_docs/01-data-architectures.md` | not started | |
| `_docs/02-kubernetes-substrate.md` | `_docs/02-kubernetes-substrate.md` | not started | Docker vs podman note needs updating (DRQ-003) |
| `_docs/03-services-and-data-products.md` | `_docs/03-services-and-data-products.md` | not started | Rewrite service code samples in Quarkus (Panache) |
| `_docs/04-contracts-and-catalog.md` | `_docs/04-contracts-and-catalog.md` | not started | |
| `_docs/05-data-planes.md` | `_docs/05-data-planes.md` | not started | Add Camel EIP framing where Quarkus uses Camel routes |
| `_docs/06-progressive-delivery-mtls.md` | `_docs/06-progressive-delivery-mtls.md` | not started | |
| `_docs/07-elastic-and-resilient.md` | `_docs/07-elastic-and-resilient.md` | not started | |
| `_docs/08-observability.md` | `_docs/08-observability.md` | not started | |
| `_docs/09-anti-patterns.md` | `_docs/09-anti-patterns.md` | not started | |
| `_docs/10-summary.md` | `_docs/10-summary.md` | not started | |
| _(none — new)_ | `_docs/11-quarkus-capability-tour.md` | not started | New chapter, no python source |
| _(none — new)_ | `_docs/12-quarkus-vs-spring-boot.md` | not started | New chapter; depends on DRQ-006 twin service measurements |

## Services (`examples/lgtm-datamesh/services/` → `examples/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `services/order-service` | `examples/order-service` | not started | Panache + REST; primary data product |
| `services/inventory-service` | `examples/inventory-service` | not started | |
| `services/payment-service` | `examples/payment-service` | not started | |
| `services/shipping-service` | `examples/shipping-service` | not started | |
| `services/notification-service` | `examples/notification-service` | not started | Kafka consumer via Reactive Messaging |
| `services/review-service` | `examples/review-service` | not started | |
| `services/graphql-gateway` | `examples/graphql-gateway` | not started | SmallRye GraphQL |
| `proto/capstone/*.proto` | `examples/*/proto/*.proto` | not started | Reuse proto defs where domain shapes match |
| _(none — new)_ | `examples/spring-boot-compare` (order-service twin) | not started | DRQ-006; comparison chapter depends on this |
| _(none — new)_ | `examples/domain-model` | not started | Shared framework-agnostic entities, per build-plan step 5 |
| _(none — seed)_ | ported from `enterprise-integration-patterns-with-camel/examples/42-ai-mcp/quarkus` | not started | AI/MCP seed — see build-plan step 6 |

## Demos (`examples/lgtm-datamesh/demos/` → `demos/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `demos/demo-order.sh` | `demos/demo-order.sh` | not started | Panache + REST data product |
| `demos/demo-grpc.sh` | `demos/demo-grpc.sh` | not started | quarkus-grpc |
| `demos/demo-graphql.sh` | `demos/demo-graphql.sh` | not started | SmallRye GraphQL |
| `demos/demo-kafka.sh` | `demos/demo-kafka.sh` | not started | Reactive Messaging |
| `demos/demo-avro.sh` | (fold into demo-kafka.sh or contracts chapter) | not started | Evaluate whether it needs a standalone script |
| `demos/demo-canary.sh` + `demo-canary-verify.sh` | `demos/demo-canary.sh` (+ verify) | not started | Istio, mirrors python 1:1 |
| `demos/demo-keda-http.sh` | `demos/demo-keda-http.sh` | verified | 2026-10-06 act 5: graphql-gateway 0→1 through the interceptor (port 8080), 120/120 GraphQL POSTs returned 200; starts from zero after KEDA's scale-down window |
| `demos/demo-keda-kafka.sh` | `demos/demo-keda-kafka.sh` | verified | 2026-10-06 act 5: notification-service 0→1 on lag from 60 orders, drained to 0 after cooldown; starts from zero |
| `demos/demo-observability.sh` / `demo-tracing.sh` | `demos/demo-tracing.sh` | not started | OpenTelemetry |
| `demos/demo-discovery.sh` | `demos/demo-discovery.sh` | not started | Contracts/catalog discovery |
| `demos/demo-om-lineage.sh` / `demo-openmetadata.sh` | `demos/demo-om-lineage.sh` | not started | |
| `demos/demo-kiali.sh` | `demos/demo-kiali.sh` | not started | |
| `demos/demo-notifications.sh` | `demos/demo-notifications.sh` | not started | |
| `demos/demo-reviews.sh` | `demos/demo-reviews.sh` | not started | |
| `demos/demo-service.sh` | `demos/demo-service.sh` | not started | Generic per-service smoke pattern |
| `demos/demo-trace-flow.sh` | `demos/demo-trace-flow.sh` | not started | |
| `demos/demo-add-data-product.sh` | `demos/demo-add-data-product.sh` | not started | |
| `demos/walkthrough.sh` | `demos/walkthrough.sh` | not started | Orchestrator; five-act structure preserved where capability set overlaps |
| _(none — new)_ | `demos/demo-jbang-prototype.sh` | not started | jbang / Camel CLI prototyping |
| _(none — new)_ | `demos/demo-continuous-testing.sh` | not started | Quarkus continuous testing + Dev Services |
| _(none — new)_ | `demos/demo-ai-classify.sh` | not started | langchain4j, seeded from 42-ai-mcp `OrderClassifierRoute` |
| _(none — new)_ | `demos/demo-ai-mcp.sh` | not started | langchain4j + MCP, seeded from 42-ai-mcp `OrderLookupToolRoute` |
| _(none — new)_ | `demos/demo-camel-integration.sh` | not started | Quarkus + Camel EIPs |
| _(none — new)_ | `demos/demo-websocket.sh` | not started | websocket.next |
| _(none — new)_ | `demos/demo-oidc.sh` | not started | quarkus-oidc; feasibility-gated per DRQ-005 |
| _(none — new)_ | `demos/demo-reactive-vertx.sh` | not started | Vert.x unified reactive+imperative |
| _(none — new)_ | `demos/demo-native.sh` | not started | Native compilation (GraalVM/Mandrel) |

## Scripts (`scripts/` and `examples/lgtm-datamesh/scripts/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `scripts/bootstrap-capstone.sh` | `scripts/bootstrap.sh` | not started | Adapt to docker-compose + minikube split |
| `scripts/check-cross-references.sh` | `scripts/check-cross-references.sh` | not started | Port as-is, path-adjusted |
| `scripts/check-liquid-collisions.sh` | `scripts/check-liquid-collisions.sh` | not started | Port as-is |
| `scripts/splice-diagrams.sh` | `scripts/splice-diagrams.sh` | not started | Pairs with `lgtm-diagram-generator` |
| `scripts/sync-example-pages.sh` | `scripts/sync-example-pages.sh` | not started | |
| `scripts/setup-istio.sh` | `scripts/setup-istio.sh` | not started | Via `lgtm-minikube-stack` |
| `scripts/setup-keda.sh` | `scripts/setup-keda.sh` | verified | Via `lgtm-minikube-stack`; 2026-10-06 bootstrap, Helm repo name match fixed |
| `scripts/setup-strimzi.sh` | `scripts/setup-strimzi.sh` | not started | Via `lgtm-minikube-stack` |
| `examples/.../scripts/setup-postgres-operator.sh` | `scripts/setup-postgres-operator.sh` | not started | Via `lgtm-minikube-stack` (CloudNativePG) |
| `examples/.../scripts/setup-openmetadata.sh` / `ingest-openmetadata.sh` | `scripts/setup-openmetadata.sh` / `ingest-openmetadata.sh` | not started | |
| `examples/.../scripts/setup-observability.sh` | `scripts/setup-observability.sh` | not started | |
| `examples/.../scripts/scaffold-service.sh` | `scripts/scaffold-service.sh` | not started | Rework for Quarkus/Maven layout |
| `examples/.../scripts/gen-protos.sh` | `scripts/gen-protos.sh` | not started | |
| `examples/.../scripts/restore-baseline.sh` | `scripts/restore-baseline.sh` | not started | |
| `examples/.../scripts/teardown.sh` | `scripts/teardown.sh` | not started | |
| `examples/.../scripts/cluster-up.sh` / `cluster-status.sh` | `scripts/cluster-up.sh` / `cluster-status.sh` | not started | |
| `examples/.../scripts/tunnel-services.sh` | `scripts/tunnel-services.sh` | not started | |
| `examples/.../scripts/publish-discovery-contracts.sh` | `scripts/publish-discovery-contracts.sh` | not started | |
| `scripts/audit-fedora-prereqs.sh` | (evaluate: docker prereq audit) | not started | Fedora/podman-specific; needs docker-toolchain rewrite or drop |
| `scripts/editorial-audit.sh` | `scripts/editorial-audit.sh` | not started | |
| `scripts/test-template.sh` | `scripts/test-template.sh` | not started | |
| `examples/.../scripts/build-image.sh` | `scripts/build-image.sh` | not started | UBI + docker build, not podman |

## Deck (`presentation/`)

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `presentation/data-mesh-101/` | `presentation/datamesh-quarkus-101/` | not started | Rebuild with `lgtm-presentation`; one slide per demo + Spring Boot compare slides |
| `presentation/data-mesh-openshift/` | `presentation/datamesh-quarkus-openshift/` | deferred | Lower priority than the primary deck; revisit after core demos land |
| _(none — new)_ | Notion 1-hour abstract page | not started | Build-plan step 15 |

## Other project docs

| Python artifact | Quarkus counterpart | Status | Notes |
|---|---|---|---|
| `PRD.md` | `PRD.md` | ported (adapted) | This pass |
| `_plans/decisions.md` (DRA-series) | `_plans/decisions.md` (DRQ-series) | ported (adapted) | Distinct numbering series, per python precedent |
| `_plans/reconciliation.md` (verification-claim log) | `_plans/reconciliation.md` (this file — artifact map) | ported (adapted) | Different shape deliberately: this file tracks artifact-level porting status; add a verification-claim log section once demos are runnable |
| `README.md` | `README.md` | not started | |
| `onboarding/GETTING-STARTED.md` | `onboarding/GETTING-STARTED.md` | not started | |
| `onboarding/LESSONS-LEARNED.md` | `onboarding/LESSONS-LEARNED.md` | not started | Populate as this build surfaces its own lessons; don't copy python's |
| `.github/workflows/pages.yml` | `.github/workflows/pages.yml` | not started | |
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
| _(none — new)_ | `demos/demo-panama.sh`, `demos/jbang/PanamaFfm.java` | verified | Ran on JDK 25.0.3 with JBang 0.138.0: `PANAMA_GETPID` equals `JVM_PID`, `PANAMA_STRLEN` equals `JAVA_LENGTH` (31). Linux and macOS only (libc default lookup) |
| _(none — new)_ | JDK 25 AOT cache comparison: `scripts/compare-quarkus-springboot.sh --aot`, `_docs/12-quarkus-vs-spring-boot.md` | measured | Temurin 25.0.3, 2026-10-05, single run; startup, RSS, and cache size recorded in chapter 12. Not a benchmark |
| _(none — new)_ | Figure `11-panache-patterns` | unverified | Explanatory; the `PanacheRepository` example in chapter 11 is illustrative and not run |
| _(none — new)_ | Figure `11-uni-vs-imperative` | unverified | Explanatory; grounded in `InventoryGrpcService.checkStock` and `StockResource.get` |
| _(none — new)_ | Figure `11-websockets-next` | unverified | Explanatory; legacy versus Next comparison |
| _(none — new)_ | Figure `11-jbang-tooling` | unverified | Explanatory; the three scripts in `demos/jbang` are run by their demos |
| _(none — new)_ | Figure `11-startup-paths` | unverified | Qualitative; numbers are in chapter 12 |
| _(none — new)_ | Figure `11-panama-ffm` | unverified | Explanatory; the code it describes was run (see Panama row) |
| _(none — new)_ | Figure `11-oidc-token-flow` | unverified | Explanatory; the flow matches what `demo-oidc.sh` exercised |
| _(none — new)_ | Figure `16-websocket-failover` | unverified | Reconnect and backoff are conceptual; `WsNotificationClient` does not implement them |
| _(none — new)_ | Figure `20-vertx-in-memory` | unverified | Event bus usage is illustrative; the project uses the in-memory connector in shipping-service tests |
| _(none — new)_ | Figure `20-kafka-messaging` | unverified | Explanatory; consumer groups and partitions as used by the Kafka legs |

## How to keep this current

Update a row's status when the corresponding artifact is created or
substantively changed:

- `not started` → `in progress` when work begins.
- `in progress` → `ported` (content matches the python source's intent,
  adapted only for language/framework) or `ported (adapted)` (the
  Quarkus version deliberately diverges in scope or approach — note why).
- `deferred` when explicitly postponed — cross-reference the
  `_plans/decisions.md` entry or `_plans/build-plan.md` risk that
  explains the deferral.
- Add new rows immediately when a new artifact (python-sourced or
  Quarkus-only) is created — don't batch updates until the end of a
  phase.
