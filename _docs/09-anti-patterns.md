---
title: "Anti-patterns"
order: 10
part: Lessons & close
marker: "10"
description: "The conceptual and organizational ways data-mesh efforts go wrong, drawn from the literature, for recognizing them early."
duration: 15 minutes
---

## Learning objectives

By the end of this chapter you can:

- Recognize the "tool will solve it" trap, and distinguish a mesh substrate (a registry, an event stream) from the operating-model change a mesh actually requires.
- Identify the shapes centralization takes under a new name: a proxy platform team, approval-gate governance, shadow data teams, and name the fix the literature points to for each.
- Distinguish an autonomous data product from an "inert" renamed table or registry row, and explain why inert products take federated governance down with them.
- Evaluate a mesh's governance design on the spectrum between afterthought and bureaucracy, and name what federated computational governance targets instead.
- Apply this chapter's fit criteria to decide whether a given organization is actually a good candidate for a data mesh.

## Why this matters

Earlier chapters cover what to build and how. This one covers what goes wrong.
Not the implementation gaps in this build (a shared namespace instead of one
per domain, no automated schema compatibility gate yet, an Istio control
plane installed but not injected by default), but the *conceptual and
organizational* failure modes that recur across data-mesh efforts generally.
Most don't show up on an architecture diagram. They become obvious only
months in, once they've calcified.

A data mesh is a **socio-technical** system. The technical pieces, a schema
registry, event streams, autoscaling, a service mesh, are the easy part, and
this tutorial spends most of its pages on them because they're concrete and
runnable. But the literature is nearly unanimous: data-mesh efforts fail for
*organizational* reasons far more often than technical ones. The
anti-patterns below are mostly organizational, stated generally, with a note
on where each one touched this build.

## The tool will solve it

The most common trap: treating data mesh as something you buy or install. A
team adopts a registry product, relabels its database tables as "data
products," and declares the mesh delivered. But the principles a mesh rests
on (domain ownership, product thinking, self-serve infrastructure, federated
governance) concern *how people and teams work*, not which software is
running. Practitioners writing about failed adoptions put this first,
consistently: a data mesh is a shift in operating model, and no tool
delivers that shift on its own. Software can *support* the principles or
undermine them. It can't substitute for the cultural and structural change
underneath.

The tell: a project plan that's entirely a tooling rollout, with no mention
of team boundaries, ownership, or incentives. If the only thing changing is
the software, you get the old centralized model with a new dashboard.

*In this build:* every component it runs (Apicurio, Strimzi for Kafka,
CloudNativePG for Postgres, KEDA, Istio) is a *substrate* the services build
on, not a turnkey mesh. None of them makes anything a data product by
itself; `order-service` still has to define its own entity, emit its own
event, and own its own contract on top of that substrate. The
[Foundations]({{ '/parts/foundations/' | relative_url }}) part frames each
one as serving a principle.

## Centralization under a new name

Data mesh exists to break the bottleneck of a single central data team that
owns all the data but none of the domains. The failure mode is recreating
that bottleneck under a new name, and it takes a few recognizable shapes. A
central team stays the *proxy* for every domain, still the only group that
can ship a data product, just renamed a "platform team." Or governance
re-centralizes as a manual approval gate: every schema change, every
deployment, every contract waits on a review board, and the lead times data
mesh was meant to eliminate come back. Or domains, lacking support, spin up
*shadow* data teams of their own, and you end up with silos again, only more
of them.

The common thread: decentralization is the whole point, and any structure
that funnels decisions back through one team, whether for control, for
"consistency," or for governance, reintroduces the original problem. The fix
the literature points to is the same every time. Push ownership and the
ability to ship out to the domains, and make governance *automated and
policy-driven* instead of approval-driven.

*In this build:* order, inventory, payment, shipping, notification, and
review are seven independently buildable, independently deployable Quarkus
modules under [examples]({{ site.repo_tree }}/examples). There's no shared
"data" module and no central team in the path between a service owning its
schema and a consumer reading it. All seven currently run in one shared
`datamesh` Kubernetes namespace rather than one namespace per domain (see
[base]({{ site.repo_tree }}/k8s/base)); that's a simplification for demo
clarity, and namespace-level isolation is still appropriate in a production
mesh.

## Data products that are "inert"

The principle's author warns about this failure mode most strongly. A *data
product* is supposed to be an autonomous unit: it serves its data, governs
it, describes itself, makes itself discoverable, and carries everything it
needs to do its job. The reduction strips all of that away and calls a
renamed table, a view, or a row in a registry a "data product." Those are
static datasets with a label. They can't serve themselves, can't enforce
their own policies, and have no lifecycle, and because there's nowhere to
embed governance *in* them, federated computational governance has no home
either and gets dropped too. The downgrade cascades: lose autonomy and you
lose the governance model with it.

The recognizable symptom: a "data product" you can't deploy, version, or
call. You can only query the table it points at. A real data product has
ports, a contract, a version, and an owner. An inert one has a name in a
registry.

*In this build:* each service *is* its data product. `order-service` owns
the `Order` entity end to end (its Panache repository, its REST surface, the
`order.placed` Avro event it emits), not a table another team reads
out-of-band. The [Building data products]({{ '/parts/data-products/' | relative_url }})
part is about exactly this autonomy.

## Governance as an afterthought or as bureaucracy

Governance fails in two opposite directions. Bolt it on from outside (a
separate team, a separate process, run after products are already built)
and it never quite fits; quality, lineage, and access rules become things
that happen *to* a product rather than properties *of* it. Over-correct the
other way, and governance becomes a heavyweight approval bureaucracy that
bottlenecks everything, which is just centralization again.

The target the principles name is *federated computational governance*: a
small set of global rules the platform enforces automatically, embedded in
each product rather than administered by a committee. The interesting design
question for any mesh is which rules are global (shared identifiers,
contract formats, naming conventions, so products can interoperate) versus
which are left to domains. Get that line wrong in either direction and you
get a free-for-all where nothing joins up, or a bottleneck where nothing
ships.

*In this build:* every Kafka event (`order.placed`, `payment.captured`,
`shipment.dispatched`) is Avro against the shared Apicurio Schema Registry.
That's a global rule every producer and consumer follows just by using the
`contracts` module, with no manual review step in between. A regression test
backs it up: `OrderPlacedAvroWireIT` in `order-service` produces an event
through the application's own serializer and asserts the Avro magic byte is
on the wire, so a silent regression to JSON fails the build instead of
surfacing in production. The enforcement is partial, though: this build
doesn't yet configure Apicurio's compatibility rules to reject a breaking
schema change automatically, so the "federated *computational*" half of
governance here is still just "federated," with the computational
enforcement left open.

## Unclear ownership and fuzzy domain boundaries

A mesh is only as good as the clarity of who owns what, and two related
failures show up here. The first is the ownership vacuum: a dataset nobody's
responsible for, so its quality drifts, nobody fields questions about it,
and trust erodes until consumers route around it. The second is fuzzy
domain boundaries: domains that overlap or are ill-defined, so the same
concept gets modeled three different ways by three teams, changes ripple
across services that should've been independent, and consumers get
conflicting versions of what's nominally the same data.

Both come down to bounded contexts, the same discipline that makes
microservices work. Without clear, agreed domain boundaries and an explicit
owner per data product, the mesh degrades into the distributed mess the
principles were meant to prevent. The remedy is unglamorous: map the
domains, write down who owns each product, and revisit the boundaries as the
organization changes.

*In this build:* each service has a single clear responsibility and an
owner by construction. `inventory-service` owns stock levels in its own
`Stock` entity and answers `CheckStock` over gRPC; `order-service` owns
orders in its own `Order` entity and never reaches into inventory's database
directly. Neither service imports the other's entity class, and there's no
shared "domain model" module reintroducing the coupling a split database was
supposed to remove. The service boundary *is* the domain boundary.

## The open loop: no feedback

Data mesh is meant to close the loop between the operational systems that
produce data and the analytical uses that consume it, organized by domain.
The degraded version is an *open loop*: static analytical products built
downstream from a batch extract, disconnected from the operational systems
and from their own consumers. There's no feedback path, neither the
operational-to-analytical loop that keeps products current with the running
business, nor the consumer-feedback loop that tells a product owner whether
the product is useful. Without feedback, products go stale, the long lead
time between an application change and its analytical impact never shrinks,
and the mesh delivers little more than the warehouse it replaced.

The tell: a data product nobody monitors for use and nobody updates in
response to how it's consumed. Published once, then frozen.

*In this build:* `notification-service` and `review-service` react to
`order.placed` and related events over Kafka as they happen, through Quarkus
Reactive Messaging, not from a nightly extract. The
[Building data products]({{ '/parts/data-products/' | relative_url }}) part
covers why the event backbone, not a batch job, keeps the loop
closed.

## Hype-driven and wrong-fit adoption

A final category concerns *whether* to build a mesh at all. Data mesh isn't
for every organization. Its complexity pays off in large organizations with
many data domains, many consumers, and the organizational maturity to
operate products and standards across teams. For a small organization, the
overhead of decentralization can cost more than the bottleneck it removes.
Related traps in this family: chasing more data products as an end in
itself (the right number is what the organization can consume, not the
maximum it can produce); analysis paralysis, where teams plan the perfect
mesh for months instead of standing up one product and learning from it;
and adopting the whole paradigm because it's fashionable, when adopting a
single principle (self-serve platform infrastructure, say) would have
served better.

The practical move before committing: weigh data size, organizational
complexity, existing tooling, and culture, and be willing to conclude that a
full mesh isn't the right fit, or that only some of its principles are.

*In this build:* this project is a *learning* implementation, a small,
runnable mesh across six services and a GraphQL gateway, sized to show the
shape on one workstation. The Quarkus-vs-Spring-Boot comparison in
[The Quarkus deep-dive]({{ '/parts/quarkus-deep-dive/' | relative_url }})
sits alongside it. One reference implementation isn't an argument for
running a mesh, or Quarkus, in production.

## Recognizing them early

None of this is exotic. It follows from taking a paradigm about ownership,
autonomy, and feedback and implementing only its visible technical surface.
The recurring lesson in accounts of failed efforts: the architecture diagram
is the smallest part of the work. What's not on the diagram (who owns what,
how governance is enforced, whether the loop is closed, whether the
organization needed a mesh at all) decides whether efforts succeed.

The final chapter in this part matches each of the four principles against
the pieces in this repo that implement it.

## For deeper coverage

- [*Data Mesh*](https://www.oreilly.com/library/view/data-mesh/9781492092384/) by Zhamak Dehghani: the primary source for the four principles and the failure modes this chapter names when they're only partially adopted.
- [*Cloud Native Anti-Patterns*](https://www.packtpub.com/en-us/product/cloud-native-anti-patterns-9781836200581) by Gerald Bachlmayr et al.: the broader catalog of organizational and technical anti-patterns this chapter's data-mesh-specific list draws the same lesson from.
- [*Learning Domain-Driven Design*](https://www.oreilly.com/library/view/learning-domain-driven-design/9781098100124/) by Vlad Khononov: bounded contexts as the remedy for the fuzzy domain boundaries and ownership vacuums this chapter describes.
- [*Implementing Domain-Driven Design*](https://www.informit.com/store/implementing-domain-driven-design-9780133039894) by Vaughn Vernon: a deeper treatment of context boundaries and ownership for teams applying the fix directly.

---

*Verification status: <span class="status status--verified">verified</span>. The "in this build" factual callouts (seven domain-service modules, the shared `datamesh` namespace, Avro-via-Apicurio from day one) are confirmed by the passing multi-module Maven build and the committed manifests.*
