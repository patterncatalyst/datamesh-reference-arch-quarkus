---
title: "Summary — the four principles, realized"
order: 11
marker: "10"
part: Lessons & close
description: "A closing summary — for each of the four data-mesh principles, the value it delivers, the Quarkus pieces in this repo that realize it, and what happens without it."
duration: 10 minutes
---

The reading set so far has worked through this reactor by *concern* —
substrate, services, contracts, planes, progressive delivery, scaling,
observability, failure modes. This closing page reorganizes the same
material by *principle*. For each of Dehghani's four principles, you'll see
the value it delivers when it's honored, the concrete Quarkus/Kubernetes
pieces in `examples/`, `k8s/`, and `scripts/` that realize it in this repo,
and the failure mode the [previous chapter]({{ '/docs/09-anti-patterns/' | relative_url }})
names for when it's missing.

Everything below describes *this* reactor specifically — a Quarkus rebuild
of `datamesh-reference-arch-python` running order, inventory, payment,
shipping, notification, and review services plus a GraphQL gateway, all in
one `datamesh` namespace for demo simplicity. Where this build only
partially realizes a principle, that's named plainly rather than smoothed
over — see the [anti-patterns chapter]({{ '/docs/09-anti-patterns/' | relative_url }})
for why half-measures are worth naming.

## Principle 01 — Domain ownership

Each domain ships its data product on its own, with a clear owner and an
enforced boundary. No central data team sits in the path between the domain
that produces the data and the domains that consume it. The platform's job
is to enforce the boundaries; the domain's job is to fill them with a
working product.

The value of getting this right is that ownership is unambiguous. There's
one module responsible for orders, one for inventory, one for payments. The
people who understand a domain decide how it evolves.

The implementation pieces: `examples/` is a Maven reactor of independently
buildable modules — `order-service`, `inventory-service`, `payment-service`,
`shipping-service`, `notification-service`, `review-service`, and
`graphql-gateway` — each its own Quarkus application with its own Panache
entities and its own logical database (`orderdb`, `inventorydb`, and so on,
per `%prod.quarkus.datasource.jdbc.url` in each service's
`application.properties`). `order-service` never reaches into inventory's
schema directly; it calls `inventory-service` over gRPC (`CheckStock`,
defined in `examples/contracts`'s `inventory.proto`) the same way any other
consumer would.

Worth naming plainly: this build runs all seven modules in a single shared
`datamesh` Kubernetes namespace (`k8s/base/`), not one namespace per domain,
and there's no namespace-scoped RBAC or `ResourceQuota` enforcing the
boundary at the cluster level — ownership here is structural (module and
database boundaries) rather than platform-enforced. That's a deliberate
simplification for a laptop-scoped reference, not a claim that namespace
isolation is unnecessary in a production mesh.

Without this principle: fuzzy boundaries and ownership vacuums. Data that
nobody owns gets modeled three different ways by three different teams. The
mesh becomes a misnomer — a centralized data store with extra steps.

## Principle 02 — Data as a product

A data product is *discoverable*, *addressable*, *trustworthy*, and
*self-describing*. Consumers find it through its contract rather than
through a relationship with the producing team. They depend on it through a
versioned schema rather than a phone call.

The value of getting this right is that consumption decouples from
production. A consumer doesn't need to know which team owns a data product;
they need to know what it is, what it guarantees, and how to address it.

The implementation pieces: every service's Deployment + Service in `k8s/base/`
makes the product *addressable* — a consumer reaches
`order-service.datamesh.svc.cluster.local` (or, on the Compose-only path,
`localhost:<port>` per `compose.yaml`) and gets the order product, no
knowledge of which team wrote it required. The shared `examples/contracts`
module holds the *versioned contracts*: three Avro schemas
(`order-placed.avsc`, `payment-captured.avsc`, `shipment-dispatched.avsc`,
each in its own `capstone.*.v1` namespace per DRQ-009) for the three Kafka
events, plus the `inventory.proto` gRPC contract — a plain, framework-free
JAR that any JVM consumer can depend on without pulling in Quarkus itself.
The Apicurio Schema Registry (`scripts/setup-apicurio.sh`, the v3 API) is
where those Avro schemas actually live at runtime: every producer and
consumer resolves its schema from the registry rather than from a copy
baked into its own jar, which is what makes the registry double as this
build's *discovery* point — browse it and you see every event type in the
mesh, its schema, and (by convention) which service registered it.

Worth naming plainly: this build does not run a dedicated catalog product
(the kind of discoverability/lineage tool the Python sibling reference
pairs with OpenMetadata) alongside Apicurio — the registry is the one
discovery surface here, and it covers schemas, not lineage or ownership
metadata. That gap is tracked, not hidden, in `_plans/reconciliation.md`.

Without this principle: "dumb" data products — a renamed table with no
contract that can't serve itself, govern itself, or describe itself to
consumers. Discovery becomes a Slack channel; trust becomes word-of-mouth.

## Principle 03 — Self-serve data platform

Domains consume the platform's capabilities — streaming, databases, scaling
— *by declaration*. They don't operate the substrate themselves. The
platform's job is to make the right things easy; the domain's job is to
declare what its product needs and let the platform deliver it.

The value of getting this right is that the platform stops being a
bottleneck. A service can ship without its team provisioning a Kafka
cluster, standing up a database, or hand-wiring an autoscaler.

The implementation pieces: `scripts/setup-kafka-operator.sh` installs
Strimzi so a service declares a topic rather than runs a broker;
`scripts/setup-postgres-operator.sh` installs CloudNativePG so a service
declares a database rather than operates Postgres; `scripts/setup-apicurio.sh`
installs the schema registry the same declarative way. All three — along
with Istio and KEDA — install via idempotent `helm upgrade --install`
(`scripts/setup-istio.sh`, `scripts/setup-keda.sh`), the same pattern every
operator in this stack follows, so a domain never hand-rolls its own copy of
shared infrastructure. KEDA itself is the clearest instance of
"self-serve by declaration": `k8s/keda/consumer-scaledobject.yaml` declares
that `notification-service` should scale on Kafka consumer lag, and
`k8s/keda/gateway-httpscaledobject.yaml` declares that `graphql-gateway`
should scale on HTTP request volume — in both cases the domain states the
demand signal and KEDA's operator does the scaling, including to zero.
`scripts/bootstrap.sh` brings the whole substrate up in one pass on
minikube.

Without this principle: every domain reinvents the same infrastructure
badly. Each team builds its own Kafka cluster, its own database, its own
scaling logic, and the cost of that duplication hides in domain budgets
where nobody sees it as a platform problem.

## Principle 04 — Federated computational governance

Global rules — security, contract conventions, observability standards —
are enforced *by the platform*, ideally automatically, at the boundary.
Standards hold across the mesh while ownership stays decentralized.

The value of getting this right is that decentralization doesn't require
giving up consistency: every domain can ship independently *because* the
platform enforces the shared rules, not because every team remembered to.

The implementation pieces this build actually has, and what they cover:
Avro-against-Apicurio is a wire-level governance rule every producer and
consumer opts into just by using the shared `contracts` module — and it's
enforced hard enough to have its own regression test: `OrderPlacedAvroWireIT`
(order-service) asserts the Avro magic byte on a real Kafka record, byte
`0x00`, and asserts it's *not* `0x7B` (the start of a JSON object), so a
silent fallback to JSON fails the build rather than fails quietly. Istio
installs cluster-wide (`scripts/setup-istio.sh`) as a real mTLS-capable
control plane, the same install path as every other operator here. The LGTM
stack (Grafana/Loki/Tempo/Mimir plus the OpenTelemetry Collector) runs as an
always-on baseline in `compose.yaml`, not an opt-in profile, so every
service's traces and metrics are visible by default
(`demos/demo-tracing.sh` drives this).

Worth naming plainly, in the same spirit as the previous chapter: Istio's
sidecar injection in this build is per-Deployment opt-in, and no application
Deployment currently carries the injection annotation (see the comment in
`k8s/base/order-service.yaml`), so mTLS and canary traffic-shifting are
*installed capabilities*, not yet a running, demoed behavior — there's no
`demo-canary.sh` in `demos/` today. Likewise, this build has no
`ValidatingAdmissionPolicy`, OPA/Gatekeeper, or Kyverno enforcing mesh-wide
invariants like "every Deployment has resource requests set" — the
governance that's real here is the contract/wire-format rule and the
always-on observability; the policy-admission layer is substrate that's
installed (Istio, after all, needs a control plane before it can enforce
anything) but not yet wired into an enforced, demoed rule.

Without this principle: governance bolted on from outside the platform
never quite fits, or worse, re-centralizes into an approval bottleneck — the
mesh's own anti-pattern of "federated governance" implemented as a review
board. The [previous chapter]({{ '/docs/09-anti-patterns/' | relative_url }})
walks through that failure mode directly.

## Where this leaves the mesh, plainly stated

Three of the four principles have real, running pieces behind them in this
repo: domain ownership through independent service modules, data-as-product
through addressable services and a shared contract registry, and self-serve
infrastructure through operator-installed, declaratively-consumed Kafka,
Postgres, and autoscaling. The fourth, federated computational governance,
is the one most accurately described as *started* rather than *finished* here
— a real wire-format rule with a regression test backing it, real
always-on observability, and a mesh-capable control plane installed but not
yet exercised end to end. That's not a flaw unique to this build; it's the
principle the anti-patterns literature names as hardest to get right in
general, and this reference doesn't pretend otherwise.

The data-mesh half of this tutorial ends here. [The Quarkus deep-dive]({{ '/parts/quarkus-deep-dive/' | relative_url }})
turns from what the mesh asks for to what the runtime underneath it
actually offers — a capability tour, a measured Spring Boot comparison, and
two different ways to orchestrate the same decision across these same
services.

---

*Verification status: <span class="status status--unverified">unverified</span>.
The architectural claims here (module/database boundaries, Apicurio as the
registry/discovery point, the KEDA ScaledObject/HTTPScaledObject targets,
the Istio injection-is-opt-in state, the absence of an admission-policy
layer) are read from the current repo tree, not confirmed by a live
minikube run — re-check `k8s/`, `scripts/`, and `_plans/decisions.md`
(DRQ-009, DRQ-011) against the actual cluster state before treating this
page as a status report rather than a design description.*
