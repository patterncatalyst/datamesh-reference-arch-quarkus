---
title: "Summary: the four principles in practice"
order: 11
part: Lessons & close
marker: "11"
description: "A closing summary — for each of the four data-mesh principles, the value it delivers, the Quarkus pieces in this repo that implement it, and what happens without it."
duration: 12 minutes
---

The preceding chapters covered this project by *concern*: substrate, services,
contracts, planes, progressive delivery, scaling, observability, failure modes.
This chapter reorganizes the same material by *principle*. For each of Dehghani's
four principles it gives the value delivered, the Quarkus and Kubernetes
pieces in [examples]({{ site.repo_tree }}/examples), [k8s]({{ site.repo_tree }}/k8s), and [scripts]({{ site.repo_tree }}/scripts) that implement it, and the failure mode
the [previous chapter]({{ '/docs/09-anti-patterns/' | relative_url }}) describes when it is missing.

Everything below describes this project: a Quarkus rebuild
of `datamesh-reference-arch-python` running order, inventory, payment,
shipping, notification, and review services plus a GraphQL gateway, all in
one `datamesh` namespace for demo simplicity. Where the build implements a
principle only partially, the text says so; the
[anti-patterns chapter]({{ '/docs/09-anti-patterns/' | relative_url }})
describes why partial adoption matters.

## Principle 01 — Domain ownership

Each domain ships its data product on its own, with a clear owner and an
enforced boundary. No central data team sits in the path between the domain
that produces the data and the domains that consume it. The platform's job
is to enforce the boundaries; the domain's job is to fill them with a
working product.

Ownership is unambiguous. One
module is responsible for orders, one for inventory, one for payments. The
people who understand a domain decide how it evolves: its schema, its
release cadence, its on-call rotation. Nobody has to file a ticket with a
central team to change how an order is shaped, and nobody downstream has to
guess who to ask when the shape changes — the owner is the module.

{% include excalidraw.html file="10-value-domain-ownership" alt="Diagram showing each domain owning its own service, data, and contract boundary end to end, with no central team in the path" caption="Figure 10.1 — Domain ownership: value, pieces, and what's missing without it" %}

The implementation pieces: [examples]({{ site.repo_tree }}/examples) is a multi-module Maven project of independently
buildable modules — `order-service`, `inventory-service`, `payment-service`,
`shipping-service`, `notification-service`, `review-service`, and
`graphql-gateway`. Each is its own Quarkus application with its own Panache
entities and its own logical database (`orderdb`, `inventorydb`, and so on,
per `%prod.quarkus.datasource.jdbc.url` in each service's
`application.properties`). The entities are not
reused across services: `order-service` owns [Order.java]({{ site.repo_blob }}/examples/order-service/src/main/java/com/patterncatalyst/datamesh/order/Order.java)
(`com.patterncatalyst.datamesh.order`), `inventory-service` owns
[Stock.java]({{ site.repo_blob }}/examples/inventory-service/src/main/java/com/patterncatalyst/datamesh/inventory/Stock.java) (`com.patterncatalyst.datamesh.inventory`), and neither module
imports the other's entity class. `order-service` never reaches into
inventory's schema directly. It calls `inventory-service` over gRPC
(`CheckStock`, defined in [contracts]({{ site.repo_tree }}/examples/contracts)'s [inventory.proto]({{ site.repo_blob }}/examples/contracts/src/main/proto/capstone/inventory/v1/inventory.proto), under
the `capstone.inventory.v1` package) as any other consumer would.
What crosses a domain boundary is a narrow
*contract*, never another domain's entity. [domain-model]({{ site.repo_tree }}/examples/domain-model) holds
the shared, framework-agnostic edge types every service depends on
(`OrderDto`, `OrderCreate`, `OrderStatus`, `StockDto`, `ReviewDto`,
`NotificationDto`, and the `Topics` constants). [contracts]({{ site.repo_tree }}/examples/contracts)
holds the versioned Avro schemas and the gRPC `.proto`. The discipline is in
*what* is shared: DTOs and events that are explicitly part of a service's
published interface, not its internal persistence model. A service's Panache
entity (`Order`, `Stock`) stays private to that service. Only its DTO and its
event schema are shared. That is the line domain ownership draws
here: a shared contract module is fine; a shared *entity* module would be
the coupling to avoid.

This build runs all seven modules in a single shared
`datamesh` Kubernetes namespace ([base]({{ site.repo_tree }}/k8s/base)), not one namespace per domain.
There is no namespace-scoped RBAC or `ResourceQuota` enforcing the
boundary at the cluster level — ownership here is structural (module and
database boundaries) rather than platform-enforced.

A further gap: only four of the seven services — `order-service`,
`inventory-service`, `notification-service`, and `graphql-gateway` — have
Kubernetes manifests in [base]({{ site.repo_tree }}/k8s/base) today (see [kustomization.yaml]({{ site.repo_blob }}/k8s/base/kustomization.yaml)'s
resource list). `payment-service`, `shipping-service`, and `review-service`
run in the local Maven dev loop against the Compose infra baseline but
haven't been given Deployment/Service manifests yet. That is a gap in coverage, not a design position: domain ownership does not
require every domain to be deployed the same way at the start, but a reference
with seven independent services should eventually show seven independent
Deployments, and it currently shows four. Both gaps are simplifications for a
single-machine reference; production would want namespace isolation and
full-fleet deployment parity.

Without this principle: fuzzy boundaries and ownership vacuums. Data that
nobody owns gets modeled three different ways by three different teams, a
schema change ripples sideways instead of staying contained, and the
question "who do I ask about this field" has no answer. The mesh becomes a
misnomer: a centralized data store with extra steps and extra latency
from the service calls in between.

## Principle 02 — Data as a product

A data product is *discoverable*, *addressable*, *trustworthy*, and
*self-describing*. Consumers find it through its contract rather than
through a relationship with the producing team. They depend on it through a
versioned schema rather than a phone call, and they can verify what they're
getting rather than taking the producer's word for it.

Consumption decouples from
production. A consumer doesn't need to know which team owns a data product;
they need to know what it is, what it guarantees, and how to address it.
That decoupling lets a mesh scale past the point where everyone can
ask around. At five services, tribal knowledge works; past a dozen, it
does not, and the contract has to carry that weight.

{% include excalidraw.html file="10-value-data-product" alt="Diagram showing a data product as discoverable, addressable, trustworthy, and self-describing, backed by a versioned contract and a schema registry" caption="Figure 10.2 — Data as a product: value, pieces, and what's missing without it" %}

The implementation pieces: the Deployment + Service pairs that do exist in
[base]({{ site.repo_tree }}/k8s/base) make the product *addressable* — a consumer reaches
`order-service.datamesh.svc.cluster.local:8080` (the Service in
[order-service.yaml]({{ site.repo_blob }}/k8s/base/order-service.yaml) exposes port `8080` under the name `http`) and
gets the order product without knowing which team wrote it. During
the local Maven dev loop, the same services are addressable at their own
`localhost` ports instead, with [compose.yaml]({{ site.repo_blob }}/compose.yaml) supplying only the shared
infra (Postgres, Kafka, and Apicurio), not the app services. The shared [contracts]({{ site.repo_tree }}/examples/contracts) module holds the *versioned
contracts*: three Avro schemas ([order-placed.avsc]({{ site.repo_blob }}/examples/contracts/src/main/avro/order-placed.avsc), [payment-captured.avsc]({{ site.repo_blob }}/examples/contracts/src/main/avro/payment-captured.avsc),
[shipment-dispatched.avsc]({{ site.repo_blob }}/examples/contracts/src/main/avro/shipment-dispatched.avsc), each in its own `capstone.*.v1` namespace:
`capstone.order.v1`, `capstone.payment.v1`, `capstone.shipping.v1`) for the
three Kafka events, plus the [inventory.proto]({{ site.repo_blob }}/examples/contracts/src/main/proto/capstone/inventory/v1/inventory.proto) gRPC
contract, packaged as a framework-free JAR that any JVM consumer can depend on
without pulling in Quarkus itself. The Apicurio Schema Registry
([setup-apicurio.sh]({{ site.repo_blob }}/scripts/setup-apicurio.sh), the v3 API at `/apis/registry/v3`) is where
those Avro schemas live at runtime: every producer and consumer
resolves its schema from the registry rather than from a copy baked into
its own jar, so the registry also serves as this build's
*discovery* point: browse it and you see every event type in the mesh, its
schema, and (by convention) which service registered it. The registry
also makes a product *trustworthy* in a checkable sense: `OrderPlacedAvroWireIT`
in `order-service` verifies the wire format by producing a
`capstone.order.v1.OrderPlaced` record through the application's
serializer and then reading the raw bytes back with a plain
`KafkaConsumer<byte[], byte[]>` that has no Avro deserializer configured,
asserting the Avro magic byte (`0x00`) is present and the JSON marker
(`0x7B`, an opening brace) is not.

This build does not run a dedicated catalog product
(a discoverability and lineage tool, such as the OpenMetadata instance the Python sibling reference
runs) alongside Apicurio — the registry is the one
discovery surface here, and it covers schemas, not lineage or ownership
metadata. Nothing in this build answers "which
products exist, who owns them, and what feeds into what" the way a catalog
would; you would have to read [base]({{ site.repo_tree }}/k8s/base), [contracts]({{ site.repo_tree }}/examples/contracts), and this
chapter together to reconstruct it by hand. The project's reconciliation notes track the gap.

Without this principle: "inert" data products (a renamed table with no
contract that cannot serve itself, govern itself, or describe itself to
consumers). Discovery becomes a Slack channel; trust becomes word-of-mouth;
and the first time a schema changes without warning, every downstream
consumer finds out in production instead of at build time.

## Principle 03 — Self-serve data platform

Domains consume the platform's capabilities — streaming, databases, scaling
— *by declaration*. They don't operate the substrate themselves. The
platform's job is to make the right choices the default; the domain's job is to
declare what its product needs and let the platform deliver it, the same
way a developer declares a dependency in a `pom.xml` instead of vendoring
the library's source.

The platform stops being a
bottleneck. A service can ship without its team provisioning a Kafka
cluster, standing up a database, or hand-wiring an autoscaler, and the platform team stops being a queue that every domain has to
wait in, because the self-serve surface is a declaration any domain can
make on its own schedule.

{% include excalidraw.html file="10-value-self-serve" alt="Diagram showing domains declaring their infrastructure needs — topics, databases, scaling policies — and the platform's operators fulfilling them automatically" caption="Figure 10.3 — Self-serve data platform: value, pieces, and what's missing without it" %}

The implementation pieces: [setup-kafka-operator.sh]({{ site.repo_blob }}/scripts/setup-kafka-operator.sh) installs
Strimzi so a service declares a topic rather than runs a broker;
[setup-postgres-operator.sh]({{ site.repo_blob }}/scripts/setup-postgres-operator.sh) installs CloudNativePG so a service
declares a database rather than operates Postgres; [setup-apicurio.sh]({{ site.repo_blob }}/scripts/setup-apicurio.sh)
installs the schema registry the same declarative way. All three, along
with Istio and KEDA, install via idempotent `helm upgrade --install`
([setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh), [setup-keda.sh]({{ site.repo_blob }}/scripts/setup-keda.sh)), the same pattern every
operator in this stack follows, so a domain never hand-rolls its own copy of
shared infrastructure. KEDA itself is the clearest instance of
"self-serve by declaration": [consumer-scaledobject.yaml]({{ site.repo_blob }}/k8s/keda/consumer-scaledobject.yaml) declares
that `notification-service` should scale on Kafka consumer-group lag on the
`order.placed` topic — `lagThreshold: "5"`, `minReplicaCount: 0`,
`maxReplicaCount: 10` — and [gateway-httpscaledobject.yaml]({{ site.repo_blob }}/k8s/keda/gateway-httpscaledobject.yaml)
declares that `graphql-gateway` should scale on HTTP request volume through
the KEDA HTTP add-on's interceptor, targeting 50 requests per minute per
replica. In both cases the domain states the demand signal in a
ten-or-so-line YAML file and KEDA's operator does the scaling, including to
zero and back. [demo-keda-kafka.sh]({{ site.repo_blob }}/demos/demo-keda-kafka.sh) and
[demo-keda-http.sh]({{ site.repo_blob }}/demos/demo-keda-http.sh) drive load against each
scaler and assert the replica count climbs and falls back on
schedule. [bootstrap.sh]({{ site.repo_blob }}/scripts/bootstrap.sh) ties the whole substrate together in one
pass on a local Kubernetes cluster (`minikube`), bringing up the profile, then Istio, then
CloudNativePG, then Strimzi, then KEDA, then the LGTM stack, then Kiali,
then Apicurio — each tier gated behind a health check before the next one
starts.

Without this principle: every domain reinvents the same infrastructure
badly. Each team builds its own Kafka cluster, its own database, its own
scaling logic, and the cost of that duplication hides in domain budgets
where nobody sees it as a platform problem; it shows up as "our team's
velocity is slow" rather than "we're all paying to reinvent the same
plumbing," which is harder to notice, let alone fix.

## Principle 04 — Federated computational governance

Global rules — security, contract conventions, observability standards —
are enforced *by the platform*, ideally automatically, at the boundary.
Standards hold across the mesh while ownership stays decentralized: a rule
that only holds because every team remembers to follow it is not
governance; it is a hope.

Decentralization does not require
giving up consistency: every domain can ship independently *because* the
platform enforces the shared rules, not because every team remembered to.
Done well, a developer never has to think about the global rules at all —
they just can't violate them, the same way a type system stops a certain
class of bug without the developer consciously avoiding it.

{% include excalidraw.html file="10-value-governance" alt="Diagram showing global rules — contract format, security, observability — enforced automatically at the platform boundary while domains keep independent ownership" caption="Figure 10.4 — Federated computational governance: value, pieces, and what's missing without it" %}

The implementation pieces in this build, and what they cover:
Avro-against-Apicurio is a wire-level governance rule every producer and
consumer follows by using the shared `contracts` module, and a
regression test enforces it. `OrderPlacedAvroWireIT`
(order-service) spins up its own pinned Kafka and
Apicurio Testcontainers, produces an `order.placed` record through the
application's own `AvroKafkaSerializer`, and asserts the Avro magic byte on
the wire, byte `0x00`, and asserts it's *not* `0x7B` (the start of a JSON
object) — so a silent fallback to JSON fails the build instead of surfacing
in production months later. Istio installs cluster-wide
([setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh)) as an mTLS-capable control plane, using the same
install path as every other operator here, with Kiali ([setup-kiali.sh]({{ site.repo_blob }}/scripts/setup-kiali.sh))
installed alongside it to make the mesh's traffic visible once it's in use.
The LGTM stack (Grafana/Loki/Tempo/Mimir plus the OpenTelemetry Collector)
runs as an always-on baseline in [compose.yaml]({{ site.repo_blob }}/compose.yaml), not an opt-in profile, so
every service's traces and metrics are visible by default
([demo-tracing.sh]({{ site.repo_blob }}/demos/demo-tracing.sh) drives this, producing an 11-span trace across
`order-service` and `inventory-service` for a single `POST /orders`). And
at the pod level, every Deployment that does exist in [base]({{ site.repo_tree }}/k8s/base) hand-authors
the same security baseline — `runAsNonRoot: true`, all Linux capabilities
dropped, the `RuntimeDefault` seccomp profile, and explicit CPU/memory
requests and limits (see [order-service.yaml]({{ site.repo_blob }}/k8s/base/order-service.yaml)) This is a governance rule,
though one repeated by hand: every service in this mesh runs
unprivileged and resource-bounded, whether or not an admission controller
is there to check.

Istio's sidecar injection in this build is a per-Deployment opt-in, applied
by the [istio]({{ site.repo_tree }}/k8s/istio) overlay rather than in
[order-service.yaml]({{ site.repo_blob }}/k8s/base/order-service.yaml), so the base manifests ship unmeshed. mTLS and the
canary split are exercised in the
[progressive-delivery chapter](/docs/06-progressive-delivery-mtls/). This
build has no `ValidatingAdmissionPolicy`, OPA/Gatekeeper, or Kyverno enforcing
mesh-wide invariants such as "every Deployment has resource requests set". The
pod security baseline above holds because the same block is repeated in each
manifest, not because the cluster would reject a Deployment missing it. The
computational governance here is the contract and wire-format rule plus the
always-on observability; the policy-admission layer is not yet implemented.

Without this principle: governance bolted on from outside the platform
never quite fits, or worse, re-centralizes into an approval bottleneck — the
mesh's own anti-pattern of "federated governance" implemented as a review
board. The [previous chapter]({{ '/docs/09-anti-patterns/' | relative_url }})
walks through that failure mode directly.

## Where this leaves the mesh

Three of the four principles have running pieces behind them in this
repo: domain ownership through independent service modules (even if only
four of seven currently ship Kubernetes manifests), data-as-product through
addressable services and a shared contract registry, and self-serve
infrastructure through operator-installed, declaratively-consumed Kafka,
Postgres, and autoscaling. The fourth, federated computational governance,
is *started* rather than *finished* here: a wire-format rule with a
regression test, a hand-authored pod security baseline, always-on
observability, and a mesh-capable control plane with no admission-policy
layer yet. This is not unique to this build; the anti-patterns literature
names this principle as the hardest to get right.

What ties all four together is a single
thread from contract to runtime: the same schema, registry, and
observability stack carry every event from a `.avsc` file in
[contracts]({{ site.repo_tree }}/examples/contracts) to a Grafana dashboard. That thread is this build's
trusted supply chain for data: the four principles followed end to end,
with no separate security product added afterward.

{% include excalidraw.html file="10-trusted-supply-chain" alt="Diagram showing the trust path from a contract defined once, through registration and wire-format verification, to runtime observability" caption="Figure 10.5 — The trusted supply chain: from contract to runtime, in one thread" %}

The data-mesh half of this tutorial ends here. [The Quarkus deep-dive]({{ '/parts/quarkus-deep-dive/' | relative_url }})
turns from what the mesh requires to what the runtime underneath it
offers: a capability tour, a measured Spring Boot comparison, and
two ways to orchestrate the same decision across these same
services.

---

*Verification status: <span class="status status--verified">verified</span>. The architectural claims (module/database boundaries, Apicurio as the registry, the KEDA ScaledObject/HTTPScaledObject targets, Istio injection being opt-in, the absence of an admission policy) are confirmed by the passing build and the committed `k8s/` manifests. The runtime behaviors they summarize are exercised in the progressive-delivery and elasticity chapters, which still require a live cluster.*
