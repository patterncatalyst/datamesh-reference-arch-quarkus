---
title: "Anti-patterns"
order: 10
part: Lessons & close
marker: "10"
description: "The conceptual and organizational ways data-mesh efforts go wrong, drawn from the literature — so you can recognize them early."
duration: 15 minutes
---

Everything else in this set is about what to build and how. This page is about
what goes wrong — not the implementation potholes this reactor hit along the
way (a shared namespace instead of one per domain, no automated schema
compatibility gate yet, an Istio control plane installed but not injected by
default), but the *conceptual and organizational* failure modes that show up
again and again in real data-mesh efforts. They're worth knowing before you
start, because most of them are invisible at the architecture-diagram level
and only become obvious months in, once they've calcified.

A useful framing first: a data mesh is a **socio-technical** system. The
technical pieces — a schema registry, event streams, autoscaling, a service
mesh — are the easy part, and this tutorial spends most of its pages there
because they're concrete and runnable. But the literature is nearly unanimous
that data-mesh efforts fail for *organizational* reasons far more often than
technical ones. The anti-patterns below are mostly organizational, stated
generally the way they'd apply to anyone, with a note on where each one
touched this build.

## The tool will solve it

The most common trap is treating data mesh as something you buy or install. A
team adopts a registry product, relabels its database tables as "data
products," and declares the mesh delivered. But the principles a mesh rests
on — domain ownership, product thinking, self-serve infrastructure, federated
governance — are mostly about *how people and teams work*, not which software
is running. Practitioners writing about failed adoptions consistently put
this first: a data mesh is a shift in operating model, and no tool delivers
an operating-model change on its own. The software can *support* the
principles or quietly undermine them, but it can't substitute for the
cultural and structural change underneath.

The tell is a project plan that's entirely a tooling rollout with no mention
of team boundaries, ownership, or incentives. If the only thing changing is
the software, what you'll have at the end is the old centralized model with a
new dashboard.

*In this build:* every component this reactor runs — Apicurio, Strimzi
(Kafka), CloudNativePG (Postgres), KEDA, Istio — is deliberately a
*substrate* the services build on, not a turnkey mesh. None of them,
installed alone, makes anything a data product; `order-service` still has
to define its own entity, emit its own event, and own its own contract on
top of that substrate. The [Foundations]({{ '/parts/foundations/' | relative_url }})
part frames each one as serving a principle rather than being the point.

## Centralization wearing a new name

Data mesh exists to break the bottleneck of a single central data team that
owns all the data but none of the domains. The failure mode is recreating
that bottleneck under new vocabulary. It takes a few recognizable shapes. A
central team stays the *proxy* for every domain — still the only group that
can actually ship a data product, just now called a "platform team." Or
governance re-centralizes as a manual approval gate: every schema change,
every deployment, every contract waits on a review board, and the lead times
data mesh was supposed to eliminate quietly return. Or domains, lacking
support, spin up *shadow* data teams of their own, and you end up with silos
again — just more of them.

The common thread is that decentralization is the whole point, and any
structure that funnels decisions back through one team — for control, for
"consistency," for governance — reintroduces the original problem. The fix
the literature points to is the same in every case: push real ownership and
the ability to ship to the domains, and make governance *automated and
policy-driven* rather than approval-driven.

*In this build:* order, inventory, payment, shipping, notification, and
review are seven independently buildable, independently deployable Quarkus
modules under `examples/` — there is no shared "data" module or central team
in the path between a service owning its schema and a consumer reading it.
Worth naming plainly, though: all seven currently run in one shared
`datamesh` Kubernetes namespace rather than one namespace per domain (see
`k8s/base/`), a simplification this build made for demo clarity, not a claim
that namespace-level isolation is unnecessary in a real mesh.

## Data products that are "dumb"

This is the failure mode that the principle's own author warns about most
sharply. A *data product* is supposed to be an autonomous unit — it serves
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
call — you can only query the table it points at. A real data product has
ports, a contract, a version, and an owner; a dumb one has a name in a
registry.

*In this build:* each service *is* its data product — `order-service` owns
the `Order` entity end to end (its Panache repository, its REST surface, the
`order.placed` Avro event it emits), not a table another team reads
out-of-band. The [Building data products]({{ '/parts/data-products/' | relative_url }})
part is about exactly this autonomy.

## Governance as an afterthought — or as bureaucracy

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
a global rule every producer and consumer opts into by using the
`contracts` module, with no manual review step in between. It's enforced
hard enough to have a regression test behind it, not just a convention:
`OrderPlacedAvroWireIT` in `order-service` produces a real event through the
application's own serializer and then asserts the Avro magic byte is on the
wire, so a silent regression to JSON fails a build instead of fails quietly
in production. That's real, but it's also partial: this build does not yet
configure Apicurio's compatibility rules to reject a breaking schema change
automatically, so the "federated *computational*" half of governance here
is still, plainly, just "federated," with the "computational" enforcement
piece open. Naming that gap plainly is the point of this page.

## No clear owner, or fuzzy domain boundaries

A mesh is only as good as the clarity of who owns what. Two related failures
show up here. The first is the ownership vacuum: a dataset nobody is
actually responsible for, so its quality drifts, nobody fields questions
about it, and trust erodes until consumers route around it. The second is
fuzzy domain boundaries: domains that overlap or are ill-defined, so the same
concept is modeled three different ways by three teams, changes ripple
across services that should have been independent, and consumers get
conflicting versions of what's nominally the same data.

Both come down to bounded contexts — the same discipline that makes
microservices work. Without clear, agreed domain boundaries and an explicit
owner per data product, the mesh degrades into the distributed mess the
principles were meant to prevent. The remedy is unglamorous: actually map the
domains, write down who owns each product, and revisit the boundaries as the
organization changes.

*In this build:* each service has a single clear responsibility and an
owner-by-construction — `inventory-service` owns stock levels in its own
`Stock` entity and answers `CheckStock` over gRPC, `order-service` owns
orders in its own `Order` entity and never reaches into inventory's database
directly. Neither service imports the other's entity class, and there is no
shared "domain model" module quietly reintroducing the coupling a split
database was supposed to remove. The service boundary *is* the domain
boundary.

## The open loop — no feedback

Data mesh is meant to close the loop between the operational systems that
produce data and the analytical uses that consume it, organized by domain.
The degraded version is an *open loop*: static analytical products built
downstream from a batch extract, disconnected from the operational systems
and from their own consumers. There's no feedback path — neither the
operational-to-analytical loop that keeps products current with the running
business, nor the consumer-feedback loop that tells a product owner whether
the product is actually useful. Without feedback, products go stale, the
long lead time between an application change and its analytical impact never
shrinks, and the mesh delivers little more than the warehouse it replaced.

The tell is a data product nobody monitors for use and nobody updates in
response to how it's consumed — published once, then frozen.

*In this build:* `notification-service` and `review-service` react to
`order.placed` and related events over Kafka as they happen, through Quarkus
Reactive Messaging — not from a nightly extract. The
[Building data products]({{ '/parts/data-products/' | relative_url }}) part
covers why the event backbone, not a batch job, is what keeps the loop
closed.

## Hype-driven and wrong-fit adoption

Finally, a category that's less about *how* you build a mesh and more about
*whether* you should. Data mesh is not for every organization. It earns its
complexity in large organizations with many data domains, many consumers,
and the organizational maturity to operate products and standards across
teams. For a small organization, the overhead of decentralization can cost
more than the bottleneck it removes. Related traps in this family: chasing
more data products as an end in itself (the right number is what the
organization can actually consume, not the maximum it can produce); analysis
paralysis, where teams plan the perfect mesh for months instead of standing
up one real product and learning from it; and adopting the whole paradigm
because it's fashionable when adopting a single principle — say, self-serve
platform infrastructure — would have served better.

The practical move before committing is to weigh data size, organizational
complexity, existing tooling, and culture, and to be willing to conclude that
a full mesh isn't the right fit — or that only some of its principles are.

*In this build:* this reactor is deliberately a *learning* implementation — a
small, runnable mesh across six services and a GraphQL gateway that makes the
principles concrete. It's sized to teach the shape on a laptop, alongside a
second lesson (the Quarkus-vs-Spring-Boot comparison in
[The Quarkus deep-dive]({{ '/parts/quarkus-deep-dive/' | relative_url }})),
not to argue that every reader should run a mesh — or Quarkus — in
production on the strength of one reference alone.

## Recognizing them early

None of these are exotic. They're the predictable result of taking a
paradigm that's fundamentally about ownership, autonomy, and feedback and
implementing only its visible technical surface. The recurring lesson across
everyone who's written about failed efforts is the same: the architecture
diagram is the easy part, and the parts that aren't on the diagram — who
owns what, how governance is enforced, whether the loop is closed, whether
the organization needed a mesh at all — are where efforts actually succeed
or fail.

The next and final chapter in this part turns from what goes wrong to what
went right here: the four principles, one more time, each matched against
the actual pieces in this repo that realize it.

---

*Verification status: <span class="status status--unverified">unverified</span>.
This chapter is conceptual and cites no runnable code, but the "in this
build" callouts assert facts about the repo's current state (seven
independent service modules, shared `datamesh` namespace, Avro-via-Apicurio
on all three events, no configured compatibility rule) — confirm those
against the actual `k8s/`, `examples/contracts/`, and Apicurio configuration
if this reactor's shape changes before publication.*
