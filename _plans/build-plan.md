---
title: Build Plan
description: Full implementation plan (relay) for datamesh-reference-arch-quarkus
---

# Build Plan — datamesh-reference-arch-quarkus

Rebuild the Python DataMesh reference architecture as a Quarkus (+ Camel) reference:
Jekyll site + runnable examples + demos aligned 1:1 to slides + tutorial + deck.
Demonstrate BOTH DataMesh AND Quarkus capabilities. Shipping/order domain throughout.

**Sources:** `../datamesh-reference-arch-python` (site/chapters/deck/PRD/scripts),
`../enterprise-integration-patterns-with-camel/examples/42-ai-mcp/quarkus` (Camel+langchain4j+MCP seed).

See [decisions.md](decisions.md) for the version matrix and settled decisions (DRQ-001…008).

## Step status table

| # | Step | Phase | Skills/MCP | Status |
|---|------|-------|-----------|--------|
| 1 | Lock toolchain & versions → decisions.md | A | lgtm-quarkus, quarkus-agent, camel-mcp | DONE |
| 2 | Create `lgtm-docker-stack` skill (no podman) | A | mirror lgtm-podman/minikube-stack | DONE (merged lgtm-skills#13) |
| 3 | Scaffold Jekyll site | A | lgtm-jekyll | DONE (build 0 errors) |
| 4 | CLAUDE.md + PRD + plans | A | — | DONE |
| 5 | Example tree + shared domain-model | B | lgtm-quarkus, quarkus-agent | pending |
| 6 | Port AI/MCP seed (42-ai-mcp) | B | lgtm-camel, lgtm-quarkus, camel-mcp | pending |
| 7 | Quarkus data-product services (Panache/gRPC/GraphQL/Kafka) | B | lgtm-quarkus, quarkus-agent, camel-mcp | pending |
| 8 | Docker compose + Testcontainers + devcontainer | C | lgtm-docker-stack | pending |
| 9 | Minikube/K8s substrate + KEDA | C | lgtm-minikube-stack | pending |
| 10 | Demos 1:1 with slides | D | lgtm-quarkus, lgtm-camel, MCPs | pending |
| 11 | Tutorial chapters (+ Spring-Boot compare) | D | lgtm-tutorial, quarkus-agent, camel-mcp | pending |
| 12 | Diagrams (uniform) | D | lgtm-diagram-generator | pending |
| 13 | Presentation deck | D | lgtm-presentation | pending |
| 14 | Newman/load tooling | E | lgtm-quarkus | pending |
| 15 | Notion 1-hour abstract | E | Notion MCP | pending |
| 16 | (optional) refresh lgtm-quarkus ancillary pins | E | — | optional |
| 17 | Validate → publish to GitHub (after approval) | E | lgtm-github | pending |

## Demo ↔ slide ↔ capability matrix

| Demo | Capability | Seed |
|------|-----------|------|
| demo-jbang-prototype.sh | jbang | lgtm-quarkus/camel CLI |
| demo-order.sh | Panache + REST data product | python |
| demo-grpc.sh | gRPC (quarkus-grpc) | python, proto/ |
| demo-graphql.sh | SmallRye GraphQL gateway | python |
| demo-kafka.sh | Kafka (Reactive Messaging) | python |
| demo-continuous-testing.sh | Continuous testing + Dev Services | lgtm-quarkus |
| demo-ai-classify.sh | langchain4j | 42-ai-mcp OrderClassifierRoute |
| demo-ai-mcp.sh | langchain4j + MCP | 42-ai-mcp OrderLookupToolRoute |
| demo-camel-integration.sh | Quarkus + Camel EIP | 42-ai-mcp routes |
| demo-websocket.sh | websocket.next | new |
| demo-tracing.sh | OpenTelemetry | python |
| demo-oidc.sh | quarkus-oidc (feasibility-gated) | new |
| demo-keda-kafka.sh / demo-keda-http.sh | KEDA autoscaling | python |
| demo-reactive-vertx.sh | Vert.x unified reactive+imperative | new |
| demo-native.sh | Native compilation (GraalVM/Mandrel) | new |
| walkthrough.sh | orchestrates all (five acts) | python |

## Acceptance criteria

- `bundle exec jekyll build` → 0 errors; Pages workflow green.
- `_docs/` ≥ 16 chapters (00–10 mirrored + Quarkus-capability + Quarkus-vs-Spring-Boot), each with front-matter + verification footer.
- Every required capability → exactly 1 demo + 1 slide; each demo has runnable README + passing test.
- Code runs Quarkus 3.39.5 / JDK 25; `mvn verify` per service; ≥1 native build succeeds.
- `lgtm-docker-stack` skill exists (SKILL.md + templates), no podman references.
- CLAUDE.md states version matrix + per-task skill mapping; PRD.md + decisions.md present.
- Deck builds with Quarkus code + Spring-Boot compare slides + one slide per demo; diagrams paired SVG+Excalidraw.
- Notion 1-hour abstract page exists.
- Publish only after approval; repo PUBLIC.

## Risks

- langchain4j 1.14.1 API drift (empty toolExecutions) → assert non-empty in demo-ai-mcp.sh.
- Native build reflection/resource failures → native build in CI, not just JVM verify.
- Camel platform-BOM skew → dependency:tree check; import only quarkus-camel-bom:3.39.5.
- Laptop resource exhaustion (Ollama+Kafka+PG+LGTM+OIDC) → per-demo compose profiles; OIDC/Ollama opt-in.
- Codetabs Liquid collisions → port check-liquid-collisions.sh.
- Diagram/deck drift → port check-cross-references.sh.
