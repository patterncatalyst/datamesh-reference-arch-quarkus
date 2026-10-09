# Product Requirements Document — datamesh-reference-arch-quarkus

This PRD captures what this project is, who it's for, what success looks
like, and what's deliberately excluded. It's a living document — changes
that touch its commitments (especially the goals and non-goals in §3, and
the scope in §5) should be discussed before they ship. It adapts
`datamesh-reference-arch-python/PRD.md` for a Quarkus-first rebuild; see
`_plans/reconciliation.md` for the artifact-by-artifact mapping between
the two repos.

---

## 1. Summary

**One sentence.** A working, runnable reference implementation of a data
mesh built on Quarkus and Apache Camel — domain services across REST,
gRPC, GraphQL, and Kafka, with versioned contracts, event-driven
autoscaling, and end-to-end observability — that doubles as a tour of
Quarkus's own capabilities (Panache, reactive messaging, gRPC, GraphQL,
Camel-on-Quarkus, langchain4j/MCP, WebSockets.Next, OIDC, native
compilation), fits on a laptop, and stays recognisable as the same shape
you'd run in production.

**One paragraph.** This reference takes Zhamak Dehghani's four data-mesh
principles (domain ownership, data as a product, self-serve platform,
federated computational governance) and shows what they look like as a
running Quarkus system. Domain services (order, inventory, payment,
shipping, notification, review) plus a GraphQL gateway communicate
through a deliberate protocol mix: REST for cross-product APIs, gRPC for
service-to-service hot paths, GraphQL at the synchronous read surface,
Kafka events (Reactive Messaging) on the asynchronous spine, and Camel
routes wherever an EIP-shaped integration problem shows up (content-based
routing, aggregation, the AI-assisted order-classification and
MCP-tool-lookup routes). Unlike the Python sibling reference, this repo
carries a second, equally deliberate goal: every data-mesh capability is
also a vehicle for showing a specific piece of the Quarkus platform doing
real work — Panache for the data-product persistence layer, SmallRye
Reactive Messaging for the Kafka spine, SmallRye GraphQL for the gateway,
quarkus-grpc for service-to-service calls, Quarkus continuous testing and
Dev Services for the inner dev loop, langchain4j (Quarkiverse) for an
AI-assisted classification and MCP tool-lookup demo, WebSockets.Next for
a live order-status stream, quarkus-oidc for the security story, and
GraalVM/Mandrel native compilation for the startup/memory story. One
runnable Spring Boot twin service (same order domain, same API shape)
ships alongside so the Quarkus-vs-Spring-Boot comparison is a measured
one — real startup time, real RSS, real native-image numbers — not an
assertion. The whole system runs on Docker Compose for the service-level
demos and on a minikube profile (Istio, KEDA, Strimzi, CloudNativePG) for
the platform-substrate story, brought up by bootstrap scripts and
exercised end to end by a demo suite aligned 1:1 with a presentation
deck.

It exists because the Python reference proved the data-mesh shape is
worth showing runnably, but it couldn't also carry "and here's what a
modern Java/Quarkus stack buys you" — that needs its own worked example,
in Java, with its own demo set and its own deck.

---

## 2. Problem statement

### Who is the reader?

Three audiences, with overlapping needs:

The **platform engineer or Java/Quarkus developer** at a mid-to-large
organisation has working knowledge of Java, Kubernetes primitives, and
probably Spring Boot, and is deciding whether Quarkus is worth adopting
for a new service or a migration. They've heard the "fast startup, low
memory, native-image-capable" pitch and want to see it demonstrated
against a real workload shape (a data mesh's mixed-protocol services)
rather than a hello-world benchmark.

The **architect evaluating a data mesh** has the same needs as in the
Python reference's audience: bridging "the four principles" to "what
this looks like running." This repo answers that question specifically
for readers whose target runtime is the JVM (or GraalVM native) rather
than a polyglot Python stack.

The **conference audience / workshop participant** wants a live,
narratable demo set — one demo per capability, one slide per demo — that
a presenter can run end to end without surprises, covering both the
data-mesh principles and the Quarkus feature tour.

### What's their pain today?

Data-mesh material is either conceptual (Dehghani's book, principles
decks) or tied to a specific vendor/stack. Quarkus material is either
feature-by-feature "getting started" guides or isolated benchmark
numbers, rarely assembled into one coherent multi-service system that
exercises the features under a realistic cross-product workload. This
reference fills the specific gap of "a data mesh, in Quarkus, with the
comparison numbers against Spring Boot actually run."

### Why now?

Quarkus 3.39.x (JDK 25) is the current stable line with a mature
extension ecosystem (Panache, Reactive Messaging, gRPC, GraphQL,
Camel-on-Quarkus, Quarkiverse langchain4j, WebSockets.Next, OIDC) and a
native-image toolchain (GraalVM/Mandrel) that is production-viable. The
Python sibling reference has already validated the data-mesh demo
architecture (bootstrap script, per-capability demos, walkthrough,
reconciliation discipline) — this repo reuses that validated shape
instead of inventing a new one, which lets the effort concentrate on the
Quarkus-specific content.

---

## 3. Goals and non-goals

### Goals (testable)

- A reader who finishes the reading set understands the four data-mesh
  principles concretely, as in the Python reference, but sees every
  principle realised with Quarkus-idiomatic code (Panache repositories,
  Reactive Messaging channels, SmallRye GraphQL, quarkus-grpc stubs).
- A reader who runs the example tree gets a working data mesh on their
  laptop: domain services, contracts, autoscaling, observability, all
  green within a reasonable bootstrap window, using Quarkus continuous
  testing and Dev Services to keep the inner loop fast.
- A reader can point to a specific demo for every capability in the
  demo↔capability matrix (`_plans/build-plan.md`) — jbang prototyping,
  Panache/REST, gRPC, GraphQL, Kafka, continuous testing, langchain4j
  classification, langchain4j+MCP tool lookup, Camel EIPs on Quarkus,
  WebSockets.Next, OpenTelemetry tracing, OIDC (feasibility-gated), KEDA
  autoscaling (Kafka-lag and HTTP), Vert.x reactive/imperative unification,
  and native compilation — each with a runnable script and a passing test.
- A reader gets real, reproducible startup-time/memory/native-image
  numbers comparing the Quarkus order-service to the Spring Boot twin
  (DRQ-006), not just a qualitative claim.
- The Jekyll tutorial site builds cleanly (`bundle exec jekyll build`, 0
  errors) with ≥16 chapters (the Python reference's chapters mirrored
  0–10, plus a Quarkus-capability chapter and a Quarkus-vs-Spring-Boot
  comparison chapter), each ending in a verification footer.
- The presentation deck has one slide per demo plus the Spring Boot
  comparison slides, built with paired SVG+Excalidraw diagrams kept
  uniform with the site.

### Non-goals (deliberate exclusions)

- **Production deployment guidance.** As in the Python reference — this
  is for learning and evaluating, not for copying into production
  as-is. Simplifying choices (single-node Postgres, dev-mode services,
  laptop-scoped resource budgets) are called out explicitly.
- **Re-litigating the data-mesh case.** The conceptual argument for data
  mesh is the Python reference's job; this repo assumes the reader
  already buys (or is separately evaluating) the four principles and is
  here for the Quarkus-specific realisation and the Quarkus/Spring Boot
  comparison.
- **A general Spring-Boot-vs-Quarkus feature audit.** The comparison is
  scoped to the one twin service (DRQ-006: order-service) and the
  specific numbers that service produces (startup time, memory, native
  build), not an exhaustive framework feature matrix.
- **Comparative coverage of data-mesh products.** Same exclusion as the
  Python reference — no vendor comparisons for the mesh substrate pieces
  (Kafka operator, catalog, mesh). Where a choice must be made the role
  is named generically in prose even though one implementation is
  picked.
- **Building a generic reusable framework.** This is a reference
  implementation, not a library or framework meant for extraction and
  reuse across organisations.

---

## 4. Audience details

### Primary audience

Java/Quarkus developers and platform engineers evaluating Quarkus for a
new service or a Spring Boot migration, who also have (or are acquiring)
data-mesh context. Comfortable with Java, Maven, containers, and basic
Kubernetes.

### Secondary audience

Architects and technical leads deciding on both a data-mesh adoption and
a JVM-stack choice at the same time; conference presenters and workshop
instructors who want a paired talk (Quarkus-primary) and full-day
workshop (Quarkus + Spring Boot) — see `project_devnexus_2027_abstracts`
notes — built on real, runnable material.

### Audience explicitly NOT served

Readers who want a Python/polyglot data-mesh reference (the sibling repo
serves them); readers who want production Kubernetes guidance; readers
who want a framework-neutral or exhaustive Spring-vs-Quarkus benchmark
suite beyond the one twin service.

---

## 5. Scope

Mirrors the Python reference's ten-section reading set (`_docs/00`–`10`),
adapted to Quarkus content, plus two Quarkus-specific chapters:

| § | Title | What it covers |
|---|-------|-----------------|
| 0 | Index | Map and reading order |
| 1 | Concepts & principles | The four data-mesh principles |
| 2 | Kubernetes as the substrate | Principles mapped to K8s primitives; Docker for local, minikube for the substrate story |
| 3 | Services & data products | Order/inventory/payment/shipping/notification/review services + GraphQL gateway, in Quarkus |
| 4 | Contracts & the catalog | Versioned contracts; catalog/discovery |
| 5 | The data planes | REST/gRPC/GraphQL synchronous layer; Kafka (Reactive Messaging) async backbone; Camel EIPs where they fit |
| 6 | Progressive delivery & mTLS | Istio canary of a v1→v2 contract; selective mesh injection |
| 7 | Elastic & resilient | KEDA on Kafka lag and HTTP request volume |
| 8 | Observability | OpenTelemetry, metrics, traces, topology view |
| 9 | Anti-patterns | Failure modes, mesh and Quarkus-adoption both |
| 10 | Summary | Principles-to-implementation recap |
| 11 | Quarkus capability tour | Panache, Reactive Messaging, gRPC, GraphQL, Camel-on-Quarkus, langchain4j+MCP, WebSockets.Next, OIDC, Vert.x reactive/imperative, native compilation |
| 12 | Quarkus vs. Spring Boot | The one runnable twin service; measured startup/memory/native numbers; where the frameworks actually differ for this workload |

The demo↔capability↔seed matrix lives in `_plans/build-plan.md` and is
the single source of truth for "does capability X have exactly one demo
and one slide" — this PRD does not duplicate that table, it points to
it.

---

## 6. Runnable examples

- **`examples/`** — per-service Quarkus projects (Panache/REST, gRPC,
  GraphQL gateway, Kafka/Reactive Messaging consumers, Camel routes) plus
  a shared framework-agnostic `domain-model/` and the one
  `spring-boot-compare/` twin service (DRQ-006).
- **`demos/demo-*.sh`** — one script per capability in the demo↔capability
  matrix (`_plans/build-plan.md`), each its own pass/fail gate.
- **`demos/walkthrough.sh`** — orchestrates the demo set end to end
  (mirrors the Python reference's five-act walkthrough where the
  capability set overlaps).
- Docker Compose (`lgtm-docker-stack`) for the service-level demos;
  minikube (`lgtm-minikube-stack`: Istio, KEDA, Strimzi, CloudNativePG)
  for the substrate-level demos (canary, autoscaling).

---

## 7. Diagrams

Paired SVG + Excalidraw sources for every figure (`lgtm-diagram-generator`),
kept visually uniform with the Jekyll site theme and the deck. Naming and
storage conventions mirror the Python reference's `assets/diagrams/`
pattern.

---

## 8. Success metrics

### Verification metrics (project-controlled)

- `bundle exec jekyll build` exits 0; the Pages workflow is green.
- `_docs/` has ≥16 chapters, each with front matter and a verification
  footer.
- Every capability in the demo↔capability matrix has exactly one demo
  script and one deck slide; each demo has a runnable README and a
  passing test.
- `mvn verify` passes per service; at least one service builds natively
  (`mvn package -Pnative` / `quarkus build --native`).
- The Quarkus/Spring Boot comparison numbers (startup, memory, native
  build) are captured and reproducible, not anecdotal.
- `_plans/reconciliation.md` tracks drift against the Python reference
  artifact by artifact and is kept current as this repo diverges or
  catches up.

### Adoption metrics (external, indicative)

Same as the Python reference: stars/forks/watchers (slow signal), issue
quality as an engagement signal, external talks/posts that cite the repo.

---

## 9. Constraints and dependencies

### Technical constraints

- **Quarkus 3.39.5 / JDK 25**, platform-aligned Camel
  (`quarkus-camel-bom:3.39.5`, never a standalone Camel pin), langchain4j
  (Quarkiverse) 1.14.1. See `_plans/decisions.md` for the full version
  matrix and rationale.
- **Docker Engine** for the container toolchain (DRQ-003, DRQ-017).
- **UBI base images**, multi-stage builds.
- **Kubernetes substrate** for the mesh/canary/autoscaling story, same as
  the Python reference; the verified runtime and any portability notes
  are tracked in `_plans/decisions.md` and `_plans/build-plan.md`, not
  duplicated here.
- **No mocks for the platform pieces** — Kafka, Postgres, the mesh, and
  the autoscaler are real, per the Python reference's precedent.

### Editorial constraints

Same as the Python reference: "you" for the reader, no "we" voice,
copy-pasteable code from the documented working directory, SVG+Excalidraw
diagram pairs, and a decision-log entry (`_plans/decisions.md`, DRQ-NNN)
for every significant architectural choice.

### Dependencies

Quarkus 3.39.5, the quarkus-camel-bom, Quarkiverse langchain4j 1.14.1,
Docker/Docker Compose, and — for the substrate-level demos — minikube,
Istio, Strimzi, CloudNativePG, KEDA. Version pins live in
`_plans/decisions.md` and the setup scripts; `_plans/reconciliation.md`
tracks any deferred items relative to the Python reference.

---

## 10. Risks and mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| langchain4j 1.14.1 API drift (empty `toolExecutions`) | Medium | Medium | Assert non-empty tool executions in `demo-ai-mcp.sh`; pin version explicitly |
| Native build reflection/resource failures | High | Medium | Native build runs in CI, not just JVM `mvn verify` |
| Camel platform-BOM skew | Medium | Low | `dependency:tree` check; import only `quarkus-camel-bom:3.39.5` |
| Laptop resource exhaustion (Ollama + Kafka + Postgres + LGTM stack + OIDC) | Medium | Medium | Per-demo Docker Compose profiles; OIDC/Ollama opt-in demos |
| Readers conflate the Quarkus reference with a Spring Boot indictment | Medium | Low | Comparison chapter states measured numbers and scope explicitly; no editorializing beyond the data |
| Reference drifts from the Python sibling repo unnoticed | Medium | Medium | `_plans/reconciliation.md` kept current as a living checklist |

---

## 11. Timeline and milestones

Forward milestones for this repo are tracked in `_plans/decisions.md`
starting from DRQ-001. The step-by-step build plan (phases A–E) is
tracked in `_plans/build-plan.md`. This repo is built on
`build/initial-scaffold` and is not published (GitHub, public) until
explicit user approval (DRQ-002).

---

## 12. Open questions

- Which minikube-substrate demos (canary, KEDA) get a Docker-Compose-only
  fallback path for readers who don't want to stand up minikube, versus
  which are minikube-only? Tracked as a possible future DRQ-NNN entry.
- How far does the OIDC demo go if the live Keycloak Dev Service path is
  too resource-heavy on a given laptop (DRQ-005) — conceptual
  documentation with a logged deferral, mirroring the Python reference's
  CAP-047 pattern.
- Should a second Spring Boot twin service be added beyond order-service
  once the first comparison lands, or does one twin stay sufficient for
  the comparison chapter's claims? Deferred; DRQ-006 currently scopes to
  one.

---

## 13. Decision log pointer

Active decisions live in `_plans/decisions.md`, numbered from DRQ-001.
The build plan (phases, skill mapping, demo↔capability matrix,
acceptance criteria) lives in `_plans/build-plan.md`. Both are read-only
references for this PRD and for coding tasks — changes to them go
through the planning skill (`lgtm-relay`), not ad hoc edits.

---

## 14. How this PRD is used

This document is read at the start of each work session for context, and
referenced when scope-creep tempts (if the change isn't covered by §5 or
the open questions in §12, it needs a decision-log entry before it
ships). When something significant changes — a goal shifts, a non-goal
becomes a goal, a constraint relaxes — the relevant section is updated
and the change is committed with a clear Conventional Commit message.
`_plans/reconciliation.md` is the audit trail against the Python sibling
repo; `_plans/decisions.md` is the audit trail for this repo's own
choices.
