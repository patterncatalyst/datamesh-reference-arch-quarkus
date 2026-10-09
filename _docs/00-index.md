---
title: "The data mesh — start here"
order: 0
part: Foundations
description: "The map of this tutorial — the six parts, the reading order, and a link to every chapter. Start here."
duration: "5 min"
marker: "00"
---

This is the reading guide for the data-mesh-on-Quarkus reference. It builds one working
system end to end: a data mesh of Quarkus services that own their data as products, talk
over a mix of protocols, evolve their contracts safely, scale to demand, and stay observable
throughout. A dedicated part covers what Quarkus itself brings to that build, including
a runnable Spring Boot twin service for a direct side-by-side comparison.

Read the tutorial straight through the first time: each chapter builds on the last, and
the cross-references assume the earlier material. To find a single topic, use the
chapter descriptions below.

## How the tutorial is organized

The twenty-one chapters fall into six parts, each described in its own section below:
**Part 0, Foundations**; **Part 1, Building data products**; **Part 2, Operating the
mesh**; **Part 3, Lessons & close**; **Part 4, The Quarkus deep-dive**; and **Part 5,
Appendices**.

## Part 0 — Foundations

- [**00 · Start here**]({{ '/docs/00-index/' | relative_url }}) — this page.
- [**01 · Data architectures**]({{ '/docs/01-data-architectures/' | relative_url }}) —
  The landscape from pipelines to warehouses to lakes to mesh — what each pattern is, the
  problem it solves, and why the mesh is a different kind of answer.
- [**02 · Concepts & principles**]({{ '/docs/01-concepts/' | relative_url }}) —
  What a data mesh is, operational versus analytical data, and Dehghani's four
  principles. The grounding before any commands.
- [**03 · Kubernetes as the substrate**]({{ '/docs/02-kubernetes-substrate/' | relative_url }}) —
  Why the four principles map cleanly onto namespaces, operators, RBAC, and platform
  primitives, and the shape of the local Kubernetes substrate this build stands up with Docker.

## Part 1 — Building data products

- [**04 · Services & data products**]({{ '/docs/03-services-and-data-products/' | relative_url }}) —
  The anatomy of a data product, the domain services plus the GraphQL gateway, and the
  order-service template the others follow.
- [**05 · Contracts & the catalog**]({{ '/docs/04-contracts-and-catalog/' | relative_url }}) —
  Versioned Avro contracts in the Apicurio registry, the runtime-versus-discovery
  distinction, and why a catalog is a mesh requirement, not an add-on.
- [**06 · The data planes**]({{ '/docs/05-data-planes/' | relative_url }}) —
  The synchronous read layer (REST, gRPC, a GraphQL gateway) and the asynchronous event
  backbone, and why the build uses all of them.

## Part 2 — Operating the mesh

- [**07 · Progressive delivery & mTLS**]({{ '/docs/06-progressive-delivery-mtls/' | relative_url }}) —
  Evolving a contract in the open with a canary, mTLS provided by the service mesh, and
  the decision to mesh selectively rather than namespace-wide.
- [**08 · Elastic & resilient**]({{ '/docs/07-elastic-and-resilient/' | relative_url }}) —
  Scaling to demand and to zero with KEDA, and the cloud-native recoverability the
  platform provides.
- [**09 · Observability**]({{ '/docs/08-observability/' | relative_url }}) —
  Metrics, distributed traces across products, and the live view of traffic moving
  through the mesh.

## Part 3 — Lessons & close

- [**10 · Anti-patterns**]({{ '/docs/09-anti-patterns/' | relative_url }}) —
  The conceptual and organizational ways data-mesh efforts go wrong, so you can recognize
  them early.
- [**11 · Summary**]({{ '/docs/10-summary/' | relative_url }}) —
  Each principle, reorganized: the value it delivers, the implementation pieces that
  implement it, and the failure mode when it's missing.

## Part 4 — The Quarkus deep-dive

- [**12 · Quarkus capability tour**]({{ '/docs/11-quarkus-capability-tour/' | relative_url }}) —
  A tour of the Quarkus capabilities the domain services exercise side by side — Panache,
  gRPC, GraphQL, Reactive Messaging, WebSockets.Next, unified Vert.x reactive/imperative
  execution, continuous testing with Dev Services, native compilation, OIDC, and JBang
  prototyping.
- [**13 · Quarkus vs. Spring Boot**]({{ '/docs/12-quarkus-vs-spring-boot/' | relative_url }}) —
  The one runnable Spring Boot twin service this build ships, and the side-by-side
  startup-time, memory, and native-build numbers it produces.
- [**14 · Orchestration styles**]({{ '/docs/13-orchestration-styles/' | relative_url }}) —
  The same order-to-shipment domain, coordinated three different ways: Kafka
  choreography, a Camel route, and a Quarkus Flow workflow.
- [**15 · AI rules triage**]({{ '/docs/14-ai-rules-triage/' | relative_url }}) —
  The `ai-rules-service` triage flow — classification plus a rules decision — exercised
  through both the Camel route and the Quarkus Flow workflow from the previous chapter.

## Part 5 — Appendices

Optional deep-dives. Each goes further on a single topic than the main narrative and
stands on its own.

- [**16 · Scaling WebSocket push with Kafka**]({{ '/docs/16-websocket-scaling/' | relative_url }}) —
  What the single-instance push does today, why it breaks across replicas, and the
  Kafka fan-out pattern a multi-replica deployment would need.
- [**17 · Gotchas**]({{ '/docs/17-gotchas/' | relative_url }}) —
  The pitfalls hit building this system — timezone, Avro, gRPC ports,
  integration-test wiring — each with its symptom and the fix that landed.
- [**18 · Agentic recommendations**]({{ '/docs/18-agentic-recommendations/' | relative_url }}) —
  Practical guidance for AI-agent-assisted development on a
  Quarkus/Camel codebase: the plan/execute/validate relay and grounding in MCP tooling.
- [**19 · Testing, in detail**]({{ '/docs/19-testing-details/' | relative_url }}) —
  The full test pyramid — unit, integration, functional, and load — and the
  single-entry runner that walks it.
- [**20 · In-memory vs. Kafka messaging**]({{ '/docs/20-messaging-in-memory-vs-kafka/' | relative_url }}) —
  The in-memory Vert.x connector used in tests versus the Kafka connector used in
  production — same code, different connector — and the trade-offs.
- [**21 · The three engines, compared**]({{ '/docs/21-orchestration-engines-compared/' | relative_url }}) —
  A deeper comparison than Part 4's tour: Kafka choreography versus two shapes of
  orchestration, across coupling, failure handling, debuggability, and more.

## Who this is for

This tutorial assumes you read Java comfortably and have used Kubernetes at
the level of `kubectl apply` and `kubectl get pods`. It does not assume prior exposure
to data mesh (Part 0 covers it) or to Kafka, Avro, gRPC, GraphQL, Istio, or KEDA; each
is introduced where the build first needs it, with a pointer to the file that uses it.
It suits two audiences: platform or data engineers evaluating whether data mesh fits
their organization, and Quarkus developers who want one coherent codebase that
exercises most of the framework's reactive and imperative surface instead of ten
disconnected quickstarts.

If you're coming from the sibling `datamesh-reference-arch-python` repository,
the domain, the four principles, and the chapter structure carry over: this build is the
same reference architecture on Quarkus. A reconciliation document tracks where the two
repos diverge and which divergences are bugs to fix.

## Prerequisites to run the code

Reading Part 0 needs nothing but a browser. Once you reach Part 1 and want to run
the services rather than just read about them, you'll want: JDK 25 (`25-tem`),
Maven 3.9.x, Docker Engine plus the Compose v2 plugin on Fedora or RHEL (bare metal or VM), and — only once you reach
Part 2's Kubernetes material — `minikube` (a local single-node Kubernetes cluster), `kubectl`, and `helm`. The
[Kubernetes substrate chapter]({{ '/docs/02-kubernetes-substrate/' | relative_url }})
covers the heavier [bootstrap.sh]({{ site.repo_blob }}/scripts/bootstrap.sh) prerequisites (32 GB of host RAM
recommended) in full; nothing before that chapter needs a cluster at all. Part 4's
native-compilation material additionally wants a GraalVM/Mandrel distribution,
called out again at that point.

## How the chapters map to runnable code

Every part past Part 0 is backed by something you can execute. The mapping is 1:1
wherever possible:

- **Part 1's services** are the Maven reactor under
  [examples]({{ site.repo_tree }}/examples) — `order-service`,
  `inventory-service`, `payment-service`, `shipping-service`,
  `notification-service`, `review-service`, `graphql-gateway`, plus the shared,
  framework-agnostic `domain-model` and `contracts` modules every service depends
  on. [spring-boot-compare]({{ site.repo_tree }}/examples/spring-boot-compare) is
  the one runnable Spring Boot twin that Part 4's comparison chapter measures
  against.
- **Part 2's operating concerns** — progressive delivery, KEDA autoscaling,
  observability — run against the Kubernetes substrate
  [bootstrap.sh]({{ site.repo_blob }}/scripts/bootstrap.sh) stands up, with the
  application manifests living under [k8s]({{ site.repo_tree }}/k8s).
- **Nearly every capability chapter has a matching demo script** under
  [demos]({{ site.repo_tree }}/demos) —
  [demo-order.sh]({{ site.repo_blob }}/demos/demo-order.sh) for the Panache/REST
  data product, [demo-grpc.sh]({{ site.repo_blob }}/demos/demo-grpc.sh) for the
  order→inventory gRPC call,
  [demo-graphql.sh]({{ site.repo_blob }}/demos/demo-graphql.sh) for the gateway
  fan-out, [demo-kafka.sh]({{ site.repo_blob }}/demos/demo-kafka.sh) for the
  Avro/Apicurio event path,
  [demo-keda-http.sh]({{ site.repo_blob }}/demos/demo-keda-http.sh) and
  [demo-keda-kafka.sh]({{ site.repo_blob }}/demos/demo-keda-kafka.sh) for the two
  autoscaling triggers, [demo-tracing.sh]({{ site.repo_blob }}/demos/demo-tracing.sh)
  for the observability stack, and several more for the AI, Camel, and
  orchestration material in Part 4. Each demo is a thin, assertion-driven script that
  checks a specific field, status code, or replica count, not just an exit
  code, and the demos' [README.md]({{ site.repo_blob }}/demos/README.md) has the
  full matrix grouped by how much infrastructure each one needs (bare JVM,
  `docker compose`, or compose plus the opt-in Ollama profile).
  [walkthrough.sh]({{ site.repo_blob }}/demos/walkthrough.sh) chains the core set
  into a single five-act presenter run, if you'd rather watch the whole system
  than drive it chapter by chapter.
- **Part 4's orchestration-styles and AI-rules chapters** are backed by
  [ai-rules-service]({{ site.repo_tree }}/examples/ai-rules-service) and
  [ai-mcp-service]({{ site.repo_tree }}/examples/ai-mcp-service), exercised by
  [demo-orchestration-styles.sh]({{ site.repo_blob }}/demos/demo-orchestration-styles.sh),
  [demo-ai-triage.sh]({{ site.repo_blob }}/demos/demo-ai-triage.sh),
  [demo-ai-classify.sh]({{ site.repo_blob }}/demos/demo-ai-classify.sh), and
  [demo-ai-mcp.sh]({{ site.repo_blob }}/demos/demo-ai-mcp.sh) — the last two
  need the heavier, opt-in Ollama compose profile rather than the baseline
  stack.

Paths cited in chapters refer to this layout. Each chapter closes with a
verification-status footer noting what has and hasn't been run end to end.

## Suggested reading paths

**Straight through**, start to finish, is the intended path: each chapter assumes
the terms and the running example built up by the ones before it. Budget roughly four to five hours for Parts 0 through 3 if you read
without running code, longer if you run the demos alongside each chapter.

**Evaluating data mesh as a pattern, not as a Quarkus build.** Read Part 0 in
full, then [anti-patterns]({{ '/docs/09-anti-patterns/' | relative_url }}) and
[the summary]({{ '/docs/10-summary/' | relative_url }}), and treat Parts 1
through 4 as a reference to dip into for the specific mechanism you need to see
in code (contracts, mTLS, autoscaling).

**Here for Quarkus, already know data mesh.** Skim Part 0 for the terminology
this build assumes, then jump straight to
[Part 4]({{ '/docs/11-quarkus-capability-tour/' | relative_url }}) — the
capability tour, the Spring Boot comparison, and the orchestration-styles and
AI-rules chapters stand on their own and don't require having run the Part 1–2
services first, though the cross-references will make more sense if you have.

**Building something similar yourself.** Part 1 (data products, contracts,
planes) and Part 2 (delivery, scaling, observability) are the operational core —
read those closely, run the demos as you go, and treat Part 0 and Part 3 as the
framing for *why* the Part 1–2 decisions were made.

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

*Verification status: <span class="status status--verified">verified</span>. The site builds with `bundle exec jekyll build` (0 errors), and every chapter link in this index resolves to a rendered page.*
