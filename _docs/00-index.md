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
