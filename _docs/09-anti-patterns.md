---
title: "Anti-patterns"
order: 10
part: Lessons & close
marker: "10"
description: "The conceptual and organizational ways data-mesh efforts go wrong, drawn from the literature, for recognizing them early."
duration: 15 minutes
---

Earlier chapters cover what to build and how. This chapter covers what goes
wrong: not implementation gaps in this build (a shared namespace instead of one per
domain, no automated schema compatibility gate yet, an Istio control plane installed
but not injected by default), but the *conceptual and organizational* failure modes
that recur in data-mesh efforts. Most are invisible at the architecture-diagram level
and become obvious only months in, once they have calcified.

A data mesh is a **socio-technical** system. The technical pieces (a schema
registry, event streams, autoscaling, a service mesh) are the easier part, and this
tutorial spends most of its pages there because they are concrete and runnable. The
literature is nearly unanimous that data-mesh efforts fail for *organizational*
reasons far more often than technical ones. The anti-patterns below are mostly
organizational and stated generally, with a note on where each one touched this build.

## The tool will solve it

The most common trap is treating data mesh as something you buy or install. A
team adopts a registry product, relabels its database tables as "data
products," and declares the mesh delivered. But the principles a mesh rests
on (domain ownership, product thinking, self-serve infrastructure, federated
governance) concern *how people and teams work*, not which software
is running. Practitioners writing about failed adoptions consistently put
this first: a data mesh is a shift in operating model, and no tool delivers
an operating-model change on its own. Software can *support* the
principles or undermine them, but it cannot substitute for the
cultural and structural change underneath.

The tell is a project plan that is entirely a tooling rollout with no mention
of team boundaries, ownership, or incentives. If the only thing changing is
the software, the result is the old centralized model with a
new dashboard.

*In this build:* every component it runs (Apicurio, Strimzi
(Kafka), CloudNativePG (Postgres), KEDA, Istio) is a
*substrate* the services build on, not a turnkey mesh. None of them,
installed alone, makes anything a data product; `order-service` still has
to define its own entity, emit its own event, and own its own contract on
top of that substrate. The [Foundations]({{ '/parts/foundations/' | relative_url }})
part frames each one as serving a principle.

## Centralization under a new name

Data mesh exists to break the bottleneck of a single central data team that
owns all the data but none of the domains. The failure mode is recreating
that bottleneck under new names. It takes a few recognizable shapes. A
central team stays the *proxy* for every domain — still the only group that
can ship a data product, now called a "platform team." Or
governance re-centralizes as a manual approval gate: every schema change,
every deployment, every contract waits on a review board, and the lead times
data mesh was meant to eliminate return. Or domains, lacking
support, spin up *shadow* data teams of their own, and you end up with silos
again, only more of them.

The common thread is that decentralization is the whole point, and any
structure that funnels decisions back through one team — for control, for
"consistency," for governance — reintroduces the original problem. The fix
the literature points to is the same in every case: push ownership and
the ability to ship to the domains, and make governance *automated and
policy-driven* instead of approval-driven.

*In this build:* order, inventory, payment, shipping, notification, and
review are seven independently buildable, independently deployable Quarkus
modules under [examples]({{ site.repo_tree }}/examples) — there is no shared "data" module or central team
in the path between a service owning its schema and a consumer reading it.
All seven currently run in one shared
`datamesh` Kubernetes namespace rather than one namespace per domain (see
[base]({{ site.repo_tree }}/k8s/base)), a simplification for demo clarity; namespace-level isolation
is still appropriate in a production mesh.

## Data products that are "inert"

The principle's author warns about this failure mode most strongly. A *data product* is supposed to be an autonomous unit — it serves
its data, governs it, describes itself, makes itself discoverable, and
carries everything it needs to do its job. The reduction is to strip all of
that away and call a renamed table, a view, or a row in a registry a "data
product." Those are static datasets with a label. They don't serve
themselves, can't enforce their own policies, and have no lifecycle — and
because there's nowhere to embed governance *in* them, federated
computational governance has no home and gets dropped too. The downgrade of
data products cascades: lose autonomy, and you lose the governance model
with it.

The recognizable symptom is a "data product" you can't deploy, version, or
call — you can only query the table it points at. A data product has
ports, a contract, a version, and an owner; an inert one has a name in a
registry.

*In this build:* each service *is* its data product — `order-service` owns
the `Order` entity end to end (its Panache repository, its REST surface, the
`order.placed` Avro event it emits), not a table another team reads
out-of-band. The [Building data products]({{ '/parts/data-products/' | relative_url }})
part is about exactly this autonomy.

## Governance as an afterthought or as bureaucracy

Governance fails in two opposite directions. Bolt it on from outside — a
separate team, a separate process, run after products are already built —
and it never quite fits; quality, lineage, and access rules become things
that happen *to* a product rather than properties *of* it. Over-correct, and
governance becomes a heavyweight approval bureaucracy that bottlenecks
everything, which is just centralization again.

The target the principles name is *federated computational governance*: a
small set of global rules the platform enforces automatically, embedded in
each product rather than administered by a committee. The interesting design
question for any mesh is which rules are global (so products can
interoperate — shared identifiers, contract formats, naming conventions)
versus which are left to domains. Get that line wrong in either direction and
you get either a free-for-all where nothing joins up, or a bottleneck where
nothing ships.

*In this build:* every Kafka event — `order.placed`, `payment.captured`,
`shipment.dispatched` — is Avro against the shared Apicurio Schema Registry,
a global rule every producer and consumer follows by using the
`contracts` module, with no manual review step in between. A regression test backs it:
`OrderPlacedAvroWireIT` in `order-service` produces an event through the
application's own serializer and asserts the Avro magic byte is on the
wire, so a silent regression to JSON fails the build instead of surfacing in
production. The enforcement is partial: this build does not yet
configure Apicurio's compatibility rules to reject a breaking schema change
automatically, so the "federated *computational*" half of governance here
is still just "federated," with the "computational" enforcement
open.

## Unclear ownership and fuzzy domain boundaries

A mesh is only as good as the clarity of who owns what. Two related failures
show up here. The first is the ownership vacuum: a dataset nobody is
responsible for, so its quality drifts, nobody fields questions
about it, and trust erodes until consumers route around it. The second is
fuzzy domain boundaries: domains that overlap or are ill-defined, so the same
concept is modeled three different ways by three teams, changes ripple
across services that should have been independent, and consumers get
conflicting versions of what's nominally the same data.

Both come down to bounded contexts — the same discipline that makes
microservices work. Without clear, agreed domain boundaries and an explicit
owner per data product, the mesh degrades into the distributed mess the
principles were meant to prevent. The remedy is unglamorous: map the
domains, write down who owns each product, and revisit the boundaries as the
organization changes.

*In this build:* each service has a single clear responsibility and an
owner-by-construction — `inventory-service` owns stock levels in its own
`Stock` entity and answers `CheckStock` over gRPC, `order-service` owns
orders in its own `Order` entity and never reaches into inventory's database
directly. Neither service imports the other's entity class, and there is no
shared "domain model" module reintroducing the coupling a split
database was supposed to remove. The service boundary *is* the domain
boundary.

## The open loop: no feedback

Data mesh is meant to close the loop between the operational systems that
produce data and the analytical uses that consume it, organized by domain.
The degraded version is an *open loop*: static analytical products built
downstream from a batch extract, disconnected from the operational systems
and from their own consumers. There's no feedback path — neither the
operational-to-analytical loop that keeps products current with the running
business, nor the consumer-feedback loop that tells a product owner whether
the product is useful. Without feedback, products go stale, the
long lead time between an application change and its analytical impact never
shrinks, and the mesh delivers little more than the warehouse it replaced.

The tell is a data product nobody monitors for use and nobody updates in
response to how it's consumed — published once, then frozen.

*In this build:* `notification-service` and `review-service` react to
`order.placed` and related events over Kafka as they happen, through Quarkus
Reactive Messaging, not from a nightly extract. The
[Building data products]({{ '/parts/data-products/' | relative_url }}) part
covers why the event backbone, not a batch job, keeps the loop
closed.

## Hype-driven and wrong-fit adoption

A final category concerns *whether* to build a mesh at all. Data mesh is not
for every organization; its complexity pays off in large organizations with many data domains, many consumers,
and the organizational maturity to operate products and standards across
teams. For a small organization, the overhead of decentralization can cost
more than the bottleneck it removes. Related traps in this family: chasing
more data products as an end in itself (the right number is what the
organization can consume, not the maximum it can produce); analysis
paralysis, where teams plan the perfect mesh for months instead of standing
up one product and learning from it; and adopting the whole paradigm
because it is fashionable when adopting a single principle — say, self-serve
platform infrastructure — would have served better.

The practical move before committing is to weigh data size, organizational
complexity, existing tooling, and culture, and to be willing to conclude that
a full mesh is not the right fit, or that only some of its principles are.

*In this build:* this project is a *learning* implementation: a
small, runnable mesh across six services and a GraphQL gateway, sized to
show the shape on one workstation. The Quarkus-vs-Spring-Boot comparison in
[The Quarkus deep-dive]({{ '/parts/quarkus-deep-dive/' | relative_url }})
sits alongside it. One reference implementation is not an argument for running a mesh, or
Quarkus, in production.

## Recognizing them early

None of these are exotic. They follow from taking a
paradigm about ownership, autonomy, and feedback and
implementing only its visible technical surface. The recurring lesson in
accounts of failed efforts is that the architecture
diagram is the smallest part of the work. What is not on the diagram (who
owns what, how governance is enforced, whether the loop is closed, whether
the organization needed a mesh at all) decides whether efforts succeed.

The final chapter in this part matches each of the four principles against
the pieces in this repo that implement it.

---

*Verification status: <span class="status status--verified">verified</span>. The "in this build" factual callouts (seven domain-service modules, the shared `datamesh` namespace, Avro-via-Apicurio from day one) are confirmed by the passing multi-module Maven build and the committed manifests.*
