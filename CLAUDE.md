# CLAUDE.md

## Project overview

A Quarkus + Apache Camel reference architecture for a data mesh, built on
the shipping/order domain. It rebuilds `datamesh-reference-arch-python`'s
data-mesh reference (Zhamak Dehghani's four principles: domain ownership,
data as a product, self-serve platform, federated computational
governance) as a running Quarkus system, with a dual purpose: demonstrate
**DataMesh** patterns (data products, contracts, catalog, progressive
delivery, event-driven autoscaling, observability) *and* demonstrate
**Quarkus** capabilities (Panache, gRPC, GraphQL, Reactive Messaging,
Camel-on-Quarkus, langchain4j/MCP, WebSockets.Next, OIDC, Vert.x reactive,
native compilation) side by side. One runnable Spring Boot twin service
ships for a real side-by-side comparison (startup time, memory, native
build). Jekyll site + runnable examples + demos aligned 1:1 to a slide
deck and tutorial chapters.

See `PRD.md` for goals/scope and `_plans/decisions.md` +
`_plans/build-plan.md` for the settled architecture decisions and the
step-by-step build plan (read-only references — do not edit them from a
coding task; decisions/plan changes go through the planning skill).

## Version matrix

| Component | Version | Notes |
|-----------|---------|-------|
| Quarkus | **3.39.5** | Current latest stable (4.0.0 is Beta only). |
| JDK | **25** (`25-tem`) | Supported on Quarkus 3.39.x. |
| Camel | **platform-aligned** | Import `quarkus-camel-bom:3.39.5`; do NOT pin a standalone Camel version. |
| langchain4j (Quarkiverse) | **1.7.4** | Seed-matched; converges dev.langchain4j to 1.11.0 with no manual pin. Ollama tool-calling is an open upstream deferral (DEF-001), independent of version. |
| Maven | 3.9.x | |
| Base images | UBI (`ubi10/openjdk-25` builder + `-runtime`) | Multi-stage builds. |
| Container toolchain | **docker** / docker compose | NOT podman — see `lgtm-docker-stack` skill. |

## Key conventions

(Adopted from `enterprise-integration-patterns-with-camel/CLAUDE.md`.)

- **Shipping/order domain** — all examples use order, inventory, payment,
  shipping, notification, review services plus a GraphQL gateway. Keep
  entity names and relationships consistent with the sibling Camel and
  Python repos.
- **Codetabs** — use
  `{% include codetabs.html langs="Quarkus|Spring Boot" %}` (or add
  `|YAML DSL` where a Camel route has a YAML equivalent) followed by one
  fenced code block per tab, in the same order as the labels. Only tabify
  code that actually differs per runtime (route/config definitions), not
  every snippet.
- **Conventional Commits** for all commit messages (`feat:`, `fix:`,
  `docs:`, `chore:`, etc., with a scope where useful, e.g. `feat(order):`).
- **No Co-authored-by or other attribution trailers** in git commits.
- **Docker, not podman**, for every container/compose example in this
  repo (`lgtm-docker-stack`, not `lgtm-podman-stack`).
- Diagrams are paired SVG + Excalidraw sources (see `lgtm-diagram-generator`),
  kept visually uniform across the site and deck.
- Chapters end with a verification status footer (unverified until run in
  a real environment) — mirrors the Python repo's and the Camel tutorial's
  reconciliation discipline. Track drift against the Python repo in
  `_plans/reconciliation.md`.

## Build / test commands

```bash
# Quarkus dev loop (per service, e.g. examples/.../order-service)
mvn quarkus:dev                 # live reload + continuous testing (press 'r' to run tests)

# Full verification
mvn verify

# Native build
mvn package -Pnative
# or, via the Quarkus CLI:
quarkus build --native

# Jekyll site
bundle exec jekyll build
bundle exec jekyll serve

# Docker stack (infra: Kafka, Postgres, etc. — see lgtm-docker-stack)
docker compose up -d
docker compose down
```

## Per-task skill / MCP mapping

Use this table to pick the right skill (and MCP server, where noted) for
a given kind of task in this repo. This mirrors the phase/skill column in
`_plans/build-plan.md`.

| Task | Skill | MCP |
|------|-------|-----|
| Jekyll site scaffolding, chapters, nav, theme | `lgtm-jekyll` | — |
| Tutorial chapter authoring / depth pass / packaging an iteration | `lgtm-tutorial` | — |
| Quarkus service code (Panache, gRPC, GraphQL, Reactive Messaging, WebSockets.Next, OIDC, native) | `lgtm-quarkus` | `quarkus-agent` |
| Camel routes / EIPs on Quarkus, langchain4j + MCP tool routes | `lgtm-camel` | `camel-mcp` (+ `quarkus-agent` for the Quarkus host app) |
| Docker/compose infra, Testcontainers, Dev Services, devcontainers | `lgtm-docker-stack` | — |
| Kubernetes/minikube substrate, Istio, KEDA, Strimzi, CloudNativePG | `lgtm-minikube-stack` | — |
| Diagrams (architecture, sequence, topology figures) | `lgtm-diagram-generator` | — |
| Presentation deck (pptx/docx) | `lgtm-presentation` | — |
| GitHub repo creation, release-sync, push-up, PR | `lgtm-github` | — |
| Planning / re-planning a multi-step chunk of work | `lgtm-relay` | — |
| Notion abstract / durable notes | — | Notion MCP |

General rule: reach for `quarkus-agent` MCP tools (`quarkus_create`,
`quarkus_skills`, `quarkus_searchDocs`, `quarkus_start`/`quarkus_logs`)
for any Quarkus-specific question or dev-loop action instead of running
`mvn`/CLI manually where an MCP tool covers it. Reach for `camel-mcp`
tools for Camel catalog lookups, route validation, and runtime
introspection instead of guessing component/EIP syntax.

## Structure (evolving — see `_plans/build-plan.md` for the authoritative step list)

```
_docs/          — tutorial chapters (Jekyll docs collection)
_parts/         — part index pages
_plans/         — decisions.md, build-plan.md, reconciliation.md (living)
examples/       — runnable examples
  domain-model/ — shared canonical entities (framework-agnostic)
  <service>/    — order, inventory, payment, shipping, notification, review, graphql-gateway
  spring-boot-compare/ — the one runnable Spring Boot twin service
demos/          — demo-*.sh scripts, one per capability (see build-plan.md's demo↔capability matrix)
presentation/   — deck source
scripts/        — setup/bootstrap/diagram scripts
```
