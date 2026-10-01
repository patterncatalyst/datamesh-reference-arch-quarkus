---
title: "The data mesh — start here"
order: 0
part: Foundations
description: "The map of this tutorial — the five parts, the reading order, and a link to every chapter. Start here."
duration: "5 min"
marker: "00"
---

This is the reading guide for the data-mesh-on-Quarkus reference — the map of what the
tutorial covers and the order to read it in. It builds one working system end to end: a
data mesh of Quarkus services that own their data as products, talk over a deliberate
mix of protocols, evolve their contracts safely, scale to demand, and stay observable
throughout — plus a dedicated part on what Quarkus itself brings to that build, including
a runnable Spring Boot twin service for a direct side-by-side comparison.

The tutorial is written to be read straight through the first time — each chapter picks
up where the last left off, and the cross-references assume you've seen the earlier
material. If you're returning to find one thing, the descriptions below will point you
at the right chapter.

## How the tutorial is organized

The fourteen chapters fall into five parts. **Part 0, Foundations** (this part) grounds
the landscape of data architectures, what a data mesh is, and why Kubernetes is a
natural substrate for one. **Part 1, Building data products** builds the services and
their data products: the contracts and catalog that make them discoverable, and the data
planes they communicate over. **Part 2, Operating the mesh** covers progressive delivery
with mutual TLS, elastic scaling and recovery, and the observability to see it all.
**Part 3, Lessons & close** steps back to the anti-patterns that derail data-mesh efforts
even when the technology is sound, then closes by reorganizing the same material by
principle. **Part 4, The Quarkus deep-dive** is specific to this rebuild: a tour of the
Quarkus capabilities the services exercise, a side-by-side comparison against the Spring
Boot twin service, and a look at the three different orchestration styles the domain
services demonstrate side by side.

## Part 0 — Foundations

- [**00 · Start here**]({{ '/docs/00-index/' | relative_url }}) — this page.
- [**01 · Data architectures**]({{ '/docs/01-data-architectures/' | relative_url }}) —
  The landscape from pipelines to warehouses to lakes to mesh — what each pattern is, the
  problem it solves, and why the mesh is a different kind of answer.
- [**01 · Concepts & principles**]({{ '/docs/01-concepts/' | relative_url }}) —
  What a data mesh is, operational versus analytical data, and Dehghani's four
  principles. The grounding before any commands.
- [**02 · Kubernetes as the substrate**]({{ '/docs/02-kubernetes-substrate/' | relative_url }}) —
  Why the four principles map cleanly onto namespaces, operators, RBAC, and platform
  primitives, and the shape of the minikube substrate this build stands up with Docker.

## Part 1 — Building data products

- [**03 · Services & data products**]({{ '/docs/03-services-and-data-products/' | relative_url }}) —
  The anatomy of a data product, the domain services plus the GraphQL gateway, and the
  order-service template the others follow.
- [**04 · Contracts & the catalog**]({{ '/docs/04-contracts-and-catalog/' | relative_url }}) —
  Versioned Avro contracts in the Apicurio registry, the runtime-versus-discovery
  distinction, and why a catalog is a mesh requirement rather than an add-on.
- [**05 · The data planes**]({{ '/docs/05-data-planes/' | relative_url }}) —
  The synchronous read layer (REST, gRPC, a GraphQL gateway) and the asynchronous event
  backbone, and why the build uses all of them.

## Part 2 — Operating the mesh

- [**06 · Progressive delivery & mTLS**]({{ '/docs/06-progressive-delivery-mtls/' | relative_url }}) —
  Evolving a contract in the open with a canary, mTLS for free from the service mesh, and
  the decision to mesh selectively rather than namespace-wide.
- [**07 · Elastic & resilient**]({{ '/docs/07-elastic-and-resilient/' | relative_url }}) —
  Scaling to demand and to zero with KEDA, and the cloud-native recoverability the
  platform provides.
- [**08 · Observability**]({{ '/docs/08-observability/' | relative_url }}) —
  Metrics, distributed traces across products, and the live view of traffic moving
  through the mesh.

## Part 3 — Lessons & close

- [**09 · Anti-patterns**]({{ '/docs/09-anti-patterns/' | relative_url }}) —
  The conceptual and organizational ways data-mesh efforts go wrong, so you can recognize
  them early.
- [**10 · Summary**]({{ '/docs/10-summary/' | relative_url }}) —
  Each principle, reorganized: the value it delivers, the implementation pieces that
  realize it, and the failure mode when it's missing.

## Part 4 — The Quarkus deep-dive

- [**11 · Quarkus capability tour**]({{ '/docs/11-quarkus-capability-tour/' | relative_url }}) —
  A tour of the Quarkus capabilities the domain services exercise side by side — Panache,
  gRPC, GraphQL, Reactive Messaging, Camel-on-Quarkus, langchain4j/MCP, WebSockets.Next,
  OIDC, and native compilation.
- [**12 · Quarkus vs. Spring Boot**]({{ '/docs/12-quarkus-vs-spring-boot/' | relative_url }}) —
  The one runnable Spring Boot twin service this build ships, and the side-by-side
  startup-time, memory, and native-build numbers it produces.
- [**13 · Orchestration styles**]({{ '/docs/13-orchestration-styles/' | relative_url }}) —
  The same order-to-shipment domain, coordinated three different ways: Kafka
  choreography, a Camel route, and a Quarkus Flow workflow.
- [**14 · AI rules triage**]({{ '/docs/14-ai-rules-triage/' | relative_url }}) —
  The `ai-rules-service` triage flow — classification plus a rules decision — exercised
  through both the Camel route and the Quarkus Flow workflow from the previous chapter.

## Who this is for

This tutorial assumes you can read Java comfortably and have used Kubernetes at
the level of `kubectl apply` and `kubectl get pods` — it does not re-teach either.
It does *not* assume prior exposure to data mesh as a pattern (Part 0 builds that
from the ground up), nor does it assume you've used Kafka, Avro, gRPC, GraphQL,
Istio, or KEDA before; each gets introduced at the point the build first needs it,
with a pointer to the real file that uses it. Two audiences get the most out of
it: platform or data engineers evaluating whether data mesh is the right answer
for their organization, and Quarkus developers who want a single, coherent,
non-trivial codebase that exercises most of the framework's reactive and
imperative surface area at once rather than ten disconnected quickstarts.

If you're coming from the sibling `datamesh-reference-arch-python` repository,
the domain, the four principles, and the chapter structure are intentionally
familiar — this build is the same reference architecture re-expressed on
Quarkus, not a different design. `_plans/reconciliation.md` tracks where the two
repos deliberately diverge (and where a divergence is a bug to fix rather than a
choice).

## Prerequisites to actually run anything

Reading Part 0 needs nothing but a browser. Once you reach Part 1 and want to run
the services rather than just read about them, you'll want: JDK 25 (`25-tem`),
Maven 3.9.x, Docker plus the Compose v2 plugin (this repo standardizes on Docker,
not Podman, for every compose and container workflow), and — only once you reach
Part 2's Kubernetes material — `minikube`, `kubectl`, and `helm`. The
[Kubernetes substrate chapter]({{ '/docs/02-kubernetes-substrate/' | relative_url }})
covers the heavier `./scripts/bootstrap.sh` prerequisites (32 GB of host RAM
recommended) in full; nothing before that chapter needs a cluster at all. Part 4's
native-compilation material additionally wants a GraalVM/Mandrel distribution,
called out again at that point.

## How the chapters map to runnable code

Every part past Part 0 is backed by something you can actually execute, not just
read. The mapping is deliberately 1:1 wherever possible:

- **Part 1's services** are the Maven reactor under `examples/` — `order-service`,
  `inventory-service`, `payment-service`, `shipping-service`,
  `notification-service`, `review-service`, `graphql-gateway`, plus the shared,
  framework-agnostic `domain-model` and `contracts` modules every service depends
  on. `examples/spring-boot-compare` is the one runnable Spring Boot twin that
  Part 4's comparison chapter measures against.
- **Part 2's operating concerns** — progressive delivery, KEDA autoscaling,
  observability — run against the Kubernetes substrate `scripts/bootstrap.sh`
  stands up, with the application manifests living under `k8s/`.
- **Nearly every capability chapter has a matching demo script** under `demos/` —
  `demo-order.sh` for the Panache/REST data product, `demo-grpc.sh` for the
  order→inventory gRPC call, `demo-graphql.sh` for the gateway fan-out,
  `demo-kafka.sh` for the Avro/Apicurio event path, `demo-keda-http.sh` and
  `demo-keda-kafka.sh` for the two autoscaling triggers, `demo-tracing.sh` for
  the observability stack, and several more for the AI, Camel, and orchestration
  material in Part 4. Each demo is a thin, assertion-driven script — it checks a
  specific field, status code, or replica count, never just an exit code — and
  `demos/README.md` has the full matrix grouped by how much infrastructure each
  one needs (bare JVM, `docker compose`, or compose plus the opt-in Ollama
  profile). `demos/walkthrough.sh` chains the core set into a single five-act
  presenter run, if you'd rather watch the whole system than drive it chapter by
  chapter.
- **Part 4's orchestration-styles and AI-rules chapters** are backed by
  `examples/ai-rules-service` and `examples/ai-mcp-service`, exercised by
  `demo-orchestration-styles.sh`, `demo-ai-triage.sh`, `demo-ai-classify.sh`, and
  `demo-ai-mcp.sh` — the last two needing the heavier, opt-in Ollama compose
  profile rather than the baseline stack.

If a chapter cites a path, it's a path in this layout — the chapters are written
against the actual repository, not an idealized one, and each closes with a
verification-status footer noting what has and hasn't been run end to end.

## Suggested reading paths

**Straight through**, start to finish, is the path the tutorial is written for —
each chapter assumes the vocabulary and the running example built up by the ones
before it. Budget roughly four to five hours for Parts 0 through 3 if you read
without running code, longer if you run the demos alongside each chapter.

**Evaluating data mesh as a pattern, not as a Quarkus build?** Read Part 0 in
full, then [anti-patterns]({{ '/docs/09-anti-patterns/' | relative_url }}) and
[the summary]({{ '/docs/10-summary/' | relative_url }}), and treat Parts 1
through 4 as a reference to dip into for the specific mechanism you need to see
made concrete (contracts, mTLS, autoscaling).

**Here for Quarkus, already know data mesh?** Skim Part 0 for the vocabulary
this build's comments and prose assume, then jump straight to
[Part 4]({{ '/docs/11-quarkus-capability-tour/' | relative_url }}) — the
capability tour, the Spring Boot comparison, and the orchestration-styles and
AI-rules chapters stand on their own and don't require having run the Part 1–2
services first, though the cross-references will make more sense if you have.

**Building something similar yourself?** Part 1 (data products, contracts,
planes) and Part 2 (delivery, scaling, observability) are the operational core —
read those closely, run the demos as you go, and treat Part 0 and Part 3 as the
framing that explains *why* the Part 1–2 decisions were made the way they were.

## If you have time for only a few

Read [**concepts & principles**]({{ '/docs/01-concepts/' | relative_url }}) for the
vocabulary, [**contracts & the catalog**]({{ '/docs/04-contracts-and-catalog/' | relative_url }})
for the idea that holds a mesh together, and
[**anti-patterns**]({{ '/docs/09-anti-patterns/' | relative_url }}) for what to avoid. If
you're here specifically for the Quarkus angle, skip ahead to
[**the capability tour**]({{ '/docs/11-quarkus-capability-tour/' | relative_url }}) once
you've read Part 0 — it and the Spring Boot comparison stand on their own.

Start with [data architectures]({{ '/docs/01-data-architectures/' | relative_url }}).

---

*Verification status: <span class="status status--unverified">unverified</span>. The
chapter numbers, titles, and links above assume every chapter in the manifest lands
under the filename shown; confirm each link resolves once Parts 1 through 4 are
authored, and that no chapter was renamed in the process.*
