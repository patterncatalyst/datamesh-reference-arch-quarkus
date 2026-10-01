---
title: "Concepts & principles"
order: 2
part: Foundations
description: "What a data mesh is, operational vs. analytical data, and Dehghani's four principles — the conceptual grounding before any commands."
duration: "15 min"
marker: "01"
---

The [previous chapter]({{ '/docs/01-data-architectures/' | relative_url }}) covered the
landscape of data architectures — pipelines, warehouses, and lakes — and where the mesh
sits in relation to all of them. This chapter goes deeper into what a data mesh actually
is and the four principles it rests on.

Before any commands, it's worth being precise about what a data mesh actually is —
because the term gets attached to a lot of things it isn't. This chapter is a working
grounding in the idea and its four principles, enough to make the rest of the tutorial
make sense. It's deliberately brief: the point here is just enough vocabulary to build
on, not the full history of the pattern.

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
themselves. The analogy that lands hardest is microservices. Just as a monolithic
application gets refactored into bounded contexts owned by domain teams, a monolithic
data platform gets refactored into bounded *data products* owned by domain teams. The
mesh is the network of those products plus the platform and standards that let them
interoperate.

## Operational vs. analytical data

One distinction underlies everything and is worth stating plainly, because blurring it
is itself a common mistake. **Operational data** is the current-state data behind a
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
leaving analytical data as a stale downstream copy.

This build models the **operational** side concretely — Quarkus services that own their
data and emit events over Kafka as Avro records — and shows how analytical consumers
attach to that operational flow through the event backbone, rather than through a
nightly extract. That's the loop the mesh is meant to keep closed.

## The four principles

Dehghani's data mesh rests on four interlocking principles. They depend on each other —
implement one without the others and you get a distributed mess rather than a mesh — and
each shows up explicitly in this build:

**Domain ownership.** Data is owned, end to end, by the domain team that produces it.
There is no central team that "owns the warehouse." Each domain owns its data's schema,
its lifecycle, and its evolution. In this build, each domain service owns its data
outright — the order domain owns orders, inventory owns stock — and nothing reaches
across that boundary to mutate another domain's data directly.

**Data as a product.** A data product is held to the same standards as any other
software product: it's discoverable, addressable, trustworthy, self-describing, and
carries explicit expectations about quality and availability. It is not a renamed
table. In this build, each domain service publishes its event schemas as versioned Avro
contracts to the Apicurio registry and its metadata to a catalog, so consumers can find
it, understand it, and depend on it — the subject of the
[contracts & catalog chapter]({{ '/docs/04-contracts-and-catalog/' | relative_url }}).

**Self-serve data platform.** Domain teams should not each build their own event
streaming, observability, registry, or catalog. The platform provides these as shared
infrastructure that every domain consumes, so a domain team can stand up a data product
without first becoming experts in running Kafka or Prometheus. In this build, the event
backbone, the observability stack, the schema registry, the catalog, and autoscaling are
all platform infrastructure shared by the services —
[Kubernetes as the substrate]({{ '/docs/02-kubernetes-substrate/' | relative_url }}) is
about exactly how Kubernetes makes that self-serve layer real.

**Federated computational governance.** Standards are enforced *computationally* — by
the platform, automatically — rather than by review meetings and policy documents. A
small set of global rules keeps independent products interoperable; the platform
enforces them. In this build, the Istio service mesh enforces mutual TLS between
services automatically, the Apicurio registry rejects schema-incompatible contract
changes at publish time, and lineage is recorded as part of deploying rather than as a
separate audit. The
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

*Verification status: <span class="status status--unverified">unverified</span>. The
mapping of each principle to a specific piece of this build (Apicurio for the registry,
Istio for mTLS, KEDA for autoscaling) describes the intended architecture; confirm each
claim against the chapter that actually implements it (04, 02, 07) once those land, since
this chapter asserts them ahead of the hands-on chapters that prove them out.*
