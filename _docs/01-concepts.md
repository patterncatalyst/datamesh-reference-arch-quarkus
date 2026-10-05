---
title: "Concepts & principles"
order: 2
part: Foundations
description: "What a data mesh is, operational vs. analytical data, and Dehghani's four principles — the conceptual grounding before any commands."
duration: "20 min"
marker: "02"
---

The [previous chapter]({{ '/docs/01-data-architectures/' | relative_url }}) covered the
landscape of data architectures — pipelines, warehouses, and lakes — and where the mesh
sits in relation to all of them. This chapter defines what a data mesh actually is,
precisely, since the term gets attached to a lot of things it isn't, and works through
the four principles it rests on. It's deliberately brief: enough vocabulary to build on
for the rest of the tutorial, not the full history of the pattern.

## What a data mesh is

The term **data mesh** was coined by Zhamak Dehghani in 2019 and formalized in *Data
Mesh: Delivering Data-Driven Value at Scale* (O'Reilly, 2022). It's a response to a
recurring failure: centralized data platforms — the monolithic data lake, the monolithic
warehouse, the sprawl of ETL pipelines feeding them — stop scaling once an organization
has enough data sources, enough consumers, and enough use cases. The bottleneck isn't
the technology; it's that one central team ends up owning all the data but understanding
none of the domains it came from.

The shift a data mesh proposes is from "centralize the data, then carve out access" to
**decentralize ownership: let each domain own its data as a product**, with a shared
platform providing the substrate those products use to publish, discover, and govern
themselves. The closest analogy is microservices. Just as a monolithic
application gets refactored into bounded contexts owned by domain teams, a monolithic
data platform gets refactored into bounded *data products* owned by domain teams. The
mesh is the network of those products plus the platform and standards that let them
interoperate. Figure 1.6 draws that analogy directly: the same monolith-to-services
transition most engineers have already lived through, applied to data ownership instead
of application code.

{% include excalidraw.html file="01-monolith-to-mesh" alt="A monolithic application and its monolithic data platform both decomposing into domain-owned services and domain-owned data products" caption="Figure 1.6 — From monolith to mesh" %}

When a monolithic application is decomposed into microservices, the hard part was never
drawing boxes on a diagram — it was deciding where one bounded context ends and the
next begins, and then living with the API contract at that boundary. Decomposing a
monolithic data platform into domain-owned data products is the same exercise one
layer up: the boundary is no longer a REST endpoint between two services but a
published, versioned contract between two domains' data. This build draws that
boundary at the level of the domain services themselves — order, inventory, payment,
shipping, notification, review — each one both an operational microservice *and* the
owner of the analytical data product derived from its own events. There is no separate
"data team" service in this repository; the boundary the mesh cares about and the
boundary the microservice decomposition already drew are the same boundary.

## Operational vs. analytical data

One distinction underlies everything, and blurring it is a common mistake.
**Operational data** is the current-state data behind a
domain's running services — the rows a microservice reads and writes to do its job,
transactional and live. **Analytical data** is the historical, aggregated view used to
make decisions, train models, and understand the business over time. Traditionally these
live in separate worlds joined by a tangle of pipelines: operational databases on one
side, a lake or warehouse on the other, ETL shuttling between them on a delay.

A data mesh doesn't erase the distinction, but it reorganizes it by *domain* rather than
by *technology layer*. Instead of "all operational data here, all analytical data there,
pipelines between," each domain owns both its operational systems and the analytical
products derived from them, and publishes those products for other domains to consume.
The aim is to close the loop between the two planes within each domain, rather than
leaving analytical data as a stale downstream copy. Figure 1.7 contrasts the two layouts
directly — the traditional cross-cutting split on the left, the per-domain reorganization
on the right.

{% include excalidraw.html file="01-operational-vs-analytical" alt="Operational data and analytical data shown first as two separate technology layers joined by pipelines, then reorganized so each domain owns both planes for its own data" caption="Figure 1.7 — Operational vs. analytical data, reorganized by domain" %}

This build models the **operational** side concretely — Quarkus services that own their
data and emit events over Kafka as Avro records — and shows how analytical consumers
attach to that operational flow through the event backbone, rather than through a
nightly extract. That's the loop the mesh is meant to keep closed.

Concretely, each domain service's operational plane is a Panache entity backed by its
own Postgres database — `order-service`'s `Order` entity, for instance, persisted with
`quarkus.hibernate-orm.schema-management.strategy=drop-and-create` in dev and an
env-driven `%prod.quarkus.datasource.jdbc.url` in production (order-service's
[application.properties]({{ site.repo_blob }}/examples/order-service/src/main/resources/application.properties)).
The moment that
operational write happens, the service also emits an `OrderPlaced` Avro event onto the
`order.placed` Kafka topic — the analytical plane's on-ramp. Nothing about the
operational database table is shared outward; the *event* is the product. A downstream
analytical consumer — a lakehouse job, a dashboard, another domain's materialized view —
subscribes to the topic and the versioned schema, never to the table. That's the
mechanical difference between "a pipeline reads my database" and "I publish my data as
a product": the first creates a hidden dependency on a storage implementation detail the
domain is free to change; the second creates an explicit, versioned contract the domain
is responsible for honoring.

## The four principles

Dehghani's data mesh rests on four interlocking principles. They depend on each other —
implement one without the others and you get a distributed mess rather than a mesh — and
each shows up explicitly in this build. Figure 1.8 shows all four as one picture before
the detail below takes each one in turn.

{% include excalidraw.html file="01-data-mesh-four-principles" alt="The four data mesh principles — domain ownership, data as a product, self-serve data platform, federated computational governance — shown as interlocking pieces" caption="Figure 1.8 — The four principles of data mesh" %}

**Domain ownership.** Data is owned, end to end, by the domain team that produces it.
There is no central team that "owns the warehouse." Each domain owns its data's schema,
its lifecycle, and its evolution. In this build, each domain service owns its data
outright — the order domain owns orders, inventory owns stock — and nothing reaches
across that boundary to mutate another domain's data directly. This is realized very
literally at the persistence layer: `order-service`, `inventory-service`,
`payment-service`, and `shipping-service` each get their own Panache entities and their
own schema, never a shared table another service reaches into directly. When
`order-service` needs to know whether an item is in stock, it doesn't query inventory's
database — it calls inventory's gRPC `CheckStock` RPC
([inventory.proto]({{ site.repo_blob }}/examples/contracts/src/main/proto/capstone/inventory/v1/inventory.proto)),
a contract inventory owns and can evolve on its own schedule. The ownership boundary is enforced by
the absence of a shortcut, not by a policy document: there is no shared connection
string, no cross-service JDBC URL, nothing to accidentally reach through.

**Data as a product.** A data product is held to the same standards as any other
software product: it's discoverable, addressable, trustworthy, self-describing, and
carries explicit expectations about quality and availability. It is not a renamed
table. In this build, each domain service publishes its event schemas as versioned Avro
contracts to the Apicurio registry and its metadata to a catalog, so consumers can find
it, understand it, and depend on it — the subject of the
[contracts & catalog chapter]({{ '/docs/04-contracts-and-catalog/' | relative_url }}).
Concretely, the [contracts]({{ site.repo_tree }}/examples/contracts) module is where
that product boundary becomes a build artifact:
[order-placed.avsc]({{ site.repo_blob }}/examples/contracts/src/main/avro/order-placed.avsc),
[payment-captured.avsc]({{ site.repo_blob }}/examples/contracts/src/main/avro/payment-captured.avsc),
and
[shipment-dispatched.avsc]({{ site.repo_blob }}/examples/contracts/src/main/avro/shipment-dispatched.avsc)
are the three Avro schemas every producer and consumer compiles against, generated
into typed `SpecificRecord` Java classes
(`OrderPlaced`, `PaymentCaptured`, `ShipmentDispatched`) rather than hand-maintained
POJOs that could silently drift from the wire format. A consumer doesn't guess at
`order-service`'s event shape from documentation — it depends on the `contracts` jar and
gets the exact shape the compiler enforces. That's "self-describing" made literal: the
schema *is* the description, and it travels with the artifact rather than living in a
wiki page that goes stale.

**Self-serve data platform.** Domain teams should not each build their own event
streaming, observability, registry, or catalog. The platform provides these as shared
infrastructure that every domain consumes, so a domain team can stand up a data product
without first becoming experts in running Kafka or Prometheus. In this build, the event
backbone, the observability stack, the schema registry, the catalog, and autoscaling are
all platform infrastructure shared by the services —
[Kubernetes as the substrate]({{ '/docs/02-kubernetes-substrate/' | relative_url }}) is
about exactly how Kubernetes makes that self-serve layer real. Concretely, a domain team
adding a new service to this mesh does not stand up its own Kafka cluster or its own
schema registry — it points `mp.messaging.outgoing.<channel>.connector` at the Strimzi
cluster [setup-kafka-operator.sh]({{ site.repo_blob }}/scripts/setup-kafka-operator.sh)
already runs, and `mp.messaging.connector.smallrye-kafka.apicurio.registry.url` at the
Apicurio instance [setup-apicurio.sh]({{ site.repo_blob }}/scripts/setup-apicurio.sh)
already runs, both by declaration rather than by operating either system themselves.
The same is true of autoscaling (KEDA,
[setup-keda.sh]({{ site.repo_blob }}/scripts/setup-keda.sh)) and observability (the
LGTM stack, [setup-lgtm.sh]({{ site.repo_blob }}/scripts/setup-lgtm.sh)): a new
domain consumes each one as a platform capability, the way `notification-service`
already does for its Kafka-lag `ScaledObject`
([consumer-scaledobject.yaml]({{ site.repo_blob }}/k8s/keda/consumer-scaledobject.yaml)).

**Federated computational governance.** Standards are enforced *computationally* — by
the platform, automatically — rather than by review meetings and policy documents. A
small set of global rules keeps independent products interoperable; the platform
enforces them. In this build, the Istio service mesh is built to establish mutual TLS
automatically between any two services that opt into it — the mechanism the
[progressive delivery & mTLS chapter]({{ '/docs/06-progressive-delivery-mtls/' | relative_url }})
walks in full, including the deliberate choice to mesh selectively, per Deployment,
rather than label the whole `datamesh` namespace for injection. And on the contract side,
Apicurio can enforce a compatibility rule on a registered Avro artifact that rejects an
incompatible schema change at publish time, before it ever reaches a consumer — the
mechanism the
[contracts & catalog chapter]({{ '/docs/04-contracts-and-catalog/' | relative_url }})
covers, including which part of that is wired up today versus which part is a configured
rule left as a documented next step. Both examples share the same shape: the rule is
code or configuration that runs at a boundary — the mesh sidecar, the registry's publish
path — not a human in a review meeting. The
[anti-patterns chapter]({{ '/docs/09-anti-patterns/' | relative_url }}) covers what
happens when governance is instead bolted on from outside, or re-centralized into an
approval bottleneck.

## The pattern is not the tools

A data mesh isn't a product, a tool, or a vendor offering — it's an organizational and
architectural pattern. The tools this build uses — Quarkus, Kafka with Avro and
Apicurio, Istio, KEDA — are *expressions* of the pattern, chosen because each one makes
a principle concrete and runnable, not because any of them *is* the mesh. That
distinction matters enough that it's the first
[anti-pattern]({{ '/docs/09-anti-patterns/' | relative_url }}): the most common way these
efforts fail is mistaking the tooling for the transformation. This tutorial additionally
builds the same domain on Quarkus specifically — and ships one Spring Boot twin service
for comparison — precisely to keep that distinction visible: the mesh's principles hold
regardless of which runtime implements them, and
[Part 4]({{ '/docs/11-quarkus-capability-tour/' | relative_url }}) is where the runtime
choice itself gets examined.

With the vocabulary in place, the next chapter looks at why Kubernetes is a natural
substrate for all of this — and how each of the four principles maps onto concrete
Kubernetes primitives.

---

*Status: <span class="status status--conceptual">conceptual</span>. This chapter is
conceptual framing with no code or commands to run. The
mapping of each principle to a specific piece of this build (Apicurio for the registry,
Istio for mTLS, KEDA for autoscaling) describes the intended architecture; confirm each
claim against the chapter that actually implements it (04, 06, 07) once those land, since
this chapter asserts them ahead of the hands-on chapters that prove them out.*
