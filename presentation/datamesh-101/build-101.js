// build-101.js — Datamesh 101 deck: data-mesh principles from first
// principles, demonstrated on Quarkus and Kubernetes — no Quarkus experience assumed.
// Run from presentation/datamesh-101/:  node build-101.js
// Requires: deck-lib.js (Red Hat design system), dpng/ + dpng/dims.json
const {
  pres, titleSlide, divider, contentSlide, diagramSlide, C,
} = require("./deck-lib.js");

// divider() in deck-lib.js does not add speaker notes itself (unlike the
// other slide helpers) — wrap it so every slide in this deck still gets one.
function dividerWithNotes(opts) {
  const { notes, ...rest } = opts;
  const s = divider(rest);
  if (notes) s.addNotes(notes);
  return s;
}

/* ============================ 1 · TITLE ============================ */
titleSlide({
  eyebrow: "Data Mesh · 101",
  title: "Building a Datamesh using Quarkus and Kubernetes",
  subtitle: "From data-mesh principles to a running platform on Quarkus and Kubernetes — no Quarkus experience assumed",
  breadcrumb: "Data Mesh · 101",
  notes: "Welcome. This talk teaches the data-mesh principles from first principles and doubles as a showroom for Quarkus — no prior Quarkus experience needed; Quarkus is the vehicle we'll demonstrate with, not a prerequisite for following along. The destination is a data mesh running on Kubernetes, and the principles we cover apply regardless of runtime. We'll start with the landscape of data architectures that came before the mesh, define the mesh precisely through its four principles, then show why Quarkus and Kubernetes are a natural pairing for building one. By the end you should be able to explain what a data mesh is, when it's the right answer, and where to go deeper if you want to see one actually running.",
});

/* ============================ 2 · DIVIDER 01 ============================ */
dividerWithNotes({
  num: "01",
  title: "The landscape",
  sub: "Four data architectures — what each pattern solves and the limitation it leaves behind.",
  notes: "Before we can appreciate what a data mesh is, we need to see what came before it. Every pattern in this section — pipelines, warehouses, lakes — solved a real problem for its era. None of them is wrong. The mesh isn't a replacement for all of them; it's a response to a specific organizational scaling problem that none of them fully solves. We'll walk through each pattern quickly, then see how they led to the mesh.",
});

/* ---- Pipelines ---- */
diagramSlide({
  eyebrow: "Data architectures",
  title: "Data pipelines — the plumbing",
  image: "01-data-pipeline-architecture",
  caption: "Extract-transform-load: each source-destination pair needs its own pipeline, and the total grows as the product of sources and destinations.",
  notes: "The oldest data architecture problem is movement: operational systems produce data, analytical systems consume it, and something has to get it from one to the other. A pipeline is that something — ETL or ELT, it doesn't matter which, both are linear, bespoke, point-to-point flows from a known source to a known destination. The limitation is pipeline sprawl: each new source or destination doesn't add one pipeline, it adds as many as there are things on the other side. Nobody owns the data flowing through a pipeline — it's plumbing, not a product. That's the seed of everything that follows.",
});

/* ---- Warehouse ---- */
diagramSlide({
  eyebrow: "Data architectures",
  title: "Data warehouses — many sources, one team, one store",
  image: "01-data-warehouse-architecture",
  caption: "A centralized, governed analytical store — and the central team that owns it becomes the single point of contention.",
  notes: "The warehouse solved the truth problem pipeline sprawl created: instead of every consumer building its own understanding from raw pipeline output, everyone queries the same curated, schema-on-write model. The limitation is organizational, not technical — a central data team owns all the data but understands none of the domains it came from. Every schema change, every new source funnels through that one team, and as the organization grows, the queue becomes the bottleneck. This is the bottleneck a data mesh exists to remove — not by building a better warehouse, but by changing who owns the data.",
});

/* ---- Lake ---- */
diagramSlide({
  eyebrow: "Data architectures",
  title: "Data lakes — flexible on the way in, swamp risk on the way out",
  image: "01-data-lake-architecture",
  caption: "Raw, curated, refined zones accept any format — but without governance the lake becomes a swamp, and the central-team bottleneck remains.",
  notes: "The lake solved the warehouse's format rigidity — it accepts structured, semi-structured, unstructured, and streaming data, and defers schema decisions to the point of consumption, schema-on-read instead of schema-on-write. Zone-based organization — raw, curated, refined — is how well-run lakes stay usable. But without active curation, the lake becomes a data swamp: undocumented, stale, duplicated datasets nobody trusts. And notice what didn't change — a central team still owns the bucket. The lake fixed the format problem, not the organizational one.",
});

/* ---- Operational vs analytical ---- */
diagramSlide({
  eyebrow: "Data architectures",
  title: "The seam a mesh addresses: operational vs. analytical",
  image: "01-operational-vs-analytical",
  caption: "Traditionally two separate technology layers joined by pipelines — the mesh reorganizes the same distinction by domain instead.",
  notes: "One more distinction underlies everything before we get to the mesh itself. Operational data is the current-state data behind a domain's running services — the rows a microservice reads and writes to do its job. Analytical data is the historical, aggregated view used for decisions and models. Traditionally these live in separate worlds joined by a tangle of ETL on a delay — all operational data here, all analytical data there, pipelines between. A data mesh doesn't erase that distinction, but reorganizes it by domain rather than by technology layer: each domain owns both its operational systems and the analytical products derived from them. That's the seam the rest of this talk is about closing.",
});

/* ---- Decentralized mesh ---- */
diagramSlide({
  eyebrow: "Data architectures",
  title: "The mesh — decentralized, domain-owned data products",
  image: "01-data-mesh-decentralized",
  caption: "Each domain owns its data as a product, on a shared platform under federated governance — the organizational answer.",
  notes: "This is the pivot. All three prior patterns — pipelines, warehouses, lakes — centralize data and hand ownership to a single team; the technology improves generation by generation but the organizational shape stays the same. The mesh changes the axis: instead of building a better center, decentralize ownership to the domains that produce the data. Each domain owns its data as a product — discoverable, addressable, trustworthy, self-describing — talking to other domains directly. A shared self-serve platform provides the infrastructure underneath, and federated computational governance keeps the independently-owned products interoperable. Notice there's no 'central data team' card on this diagram at all — that's the point.",
});

/* ---- Evolution ---- */
diagramSlide({
  eyebrow: "Data architectures",
  title: "The evolution — from pipelines to mesh",
  image: "01-architecture-evolution",
  caption: "Each pattern solved the problem the previous one left; the mesh solves the organizational scaling problem they all share.",
  notes: "The synthesis slide. Pipelines solved the movement problem but left sprawl and no ownership model. Warehouses solved the truth problem but left a central-team bottleneck. Lakes solved the flexibility problem but left swamp risk and the same organizational bottleneck. The mesh solves the organizational scaling problem directly — decentralized ownership — but it requires organizational maturity to pull off. This isn't 'each is strictly better than the last' — it's 'each solves a different problem.' A pipeline is still the right answer when movement is the problem. The mesh is the right answer when the bottleneck is organizational.",
});

/* ============================ 9 · DIVIDER 02 ============================ */
dividerWithNotes({
  num: "02",
  title: "The four principles",
  sub: "Domain ownership, data as a product, self-serve platform, federated computational governance.",
  notes: "With the landscape in place, let's define data mesh precisely. Zhamak Dehghani coined the term in 2019 and formalized it in her 2022 O'Reilly book. It rests on four interlocking principles that depend on each other — implement one without the others and you get a distributed mess, not a mesh. We'll look at all four together, then at the analogy that makes them concrete for anyone who has lived through a monolith-to-microservices transition: the same decomposition, applied to data ownership instead of application code.",
});

/* ---- Four principles ---- */
diagramSlide({
  eyebrow: "The four principles",
  title: "Domain ownership, data as a product, self-serve platform, federated governance",
  image: "01-data-mesh-four-principles",
  caption: "The four principles depend on each other — implement one without the others and you get a distributed mess, not a mesh.",
  notes: "Domain ownership: data is owned end to end by the domain team that produces it — no central team 'owns the warehouse.' Data as a product: a data product is held to the same bar as any software product — discoverable, addressable, trustworthy, self-describing — not a renamed table. Self-serve data platform: domain teams shouldn't each build their own event streaming, observability, or registry; the platform provides that as shared infrastructure. Federated computational governance: standards are enforced computationally, by the platform, automatically — not by review meetings. All four together are what make a mesh a mesh rather than just a lot of disconnected microservices each hoarding their own data.",
});

/* ---- Monolith to mesh ---- */
diagramSlide({
  eyebrow: "The four principles",
  title: "Domain ownership, made real: monolith to mesh",
  image: "01-monolith-to-mesh",
  caption: "The same monolith-to-microservices transition most engineers have lived through, applied to data ownership instead of application code.",
  notes: "This is the analogy that tends to land well for anyone who has lived through a monolith-to-microservices transition. Just as a monolithic application gets refactored into bounded contexts owned by domain teams — the microservices transition many engineers have already lived through — a monolithic data platform gets refactored into bounded data products owned by those same domain teams. The mesh is the network of those products plus the platform and standards that let them interoperate. The hard part was never drawing the boxes; it was deciding where one bounded context ends and the next begins, and then living with the contract at that boundary. Decomposing a data platform into data products is the identical exercise, one layer up — the boundary is now a versioned data contract instead of a REST endpoint.",
});

/* ============================ 12 · DIVIDER 03 ============================ */
dividerWithNotes({
  num: "03",
  title: "Why Quarkus, why Kubernetes",
  sub: "Quarkus as the developer lens on the four principles; Kubernetes as the substrate underneath them.",
  notes: "Now let's bring this back to the room. Why build a data mesh on Quarkus and Kubernetes specifically? Because Quarkus gives a single, coherent developer experience across every protocol a domain service needs — REST, gRPC, GraphQL, Kafka — without ten disconnected quickstarts, and Kubernetes's primitives map onto the four principles unusually cleanly: namespaces for domain ownership, Deployments and CRDs for data as a product, operators for the self-serve platform, and mesh/admission policy for federated governance. This section is a fast teaser — the depth lives in the 201.",
});

/* ---- Capability tour teaser ---- */
diagramSlide({
  eyebrow: "Why Quarkus",
  title: "Quarkus as the developer lens",
  image: "11-capability-tour",
  caption: "REST, gRPC, GraphQL, Kafka, reactive and imperative in one JVM, fast boot, low memory — one coherent toolchain across every data-product surface.",
  notes: "This reference build uses Quarkus to implement every domain service — order, inventory, payment, shipping, notification, review — and exercises Panache for persistence, gRPC for typed inter-domain calls, GraphQL for a federated gateway, Reactive Messaging for Kafka-backed events, and WebSockets.Next for live pushes, all sharing one Vert.x reactor whether the handler is reactive or imperative. Add fast boot and low memory footprint, and Quarkus becomes the practical reason a domain team can stand up a well-behaved data product without first becoming distributed-systems experts. This is a teaser — the full capability tour, side by side with a Spring Boot twin service for a real comparison, is the centerpiece of the 201.",
});

/* ---- Orchestration styles teaser ---- */
diagramSlide({
  eyebrow: "Why Quarkus",
  title: "Choreography vs. orchestration — one domain, three coordination engines",
  image: "13-orchestration-styles",
  caption: "The same order-to-shipment domain coordinated three ways: Kafka choreography, a Camel route, and a declarative Quarkus Flow workflow.",
  notes: "Every event-driven system eventually has to answer one question: when multiple steps need to happen in sequence, who decides the sequence? This build runs three answers side by side over the same shipping/order domain. Kafka choreography: no one is in charge — order-service publishes order.placed and has never heard of payment-service or shipping-service; each service only knows 'when I see event X, I do Y and emit Z.' Camel orchestration: one route explicitly sequences every step, imperative code you read top to bottom. Quarkus Flow orchestration: the same two steps expressed declaratively, as a workflow document rather than hand-written control flow — the same shape, two different engines. This exact comparison, with the keywords choreography and orchestration used precisely, is the centerpiece of the 201.",
});

/* ---- Capstone ---- */
diagramSlide({
  eyebrow: "Where this lands",
  title: "The capstone — a data mesh on minikube",
  image: "02-capstone-data-mesh",
  caption: "Domain services, the service mesh, and the self-serve platform tier, running together on a single minikube profile.",
  notes: "This is where the whole story lands: the complete reference architecture, domain services and platform tier together, running on a single minikube profile this repo's bootstrap script stands up. Every piece you've seen in this talk — the domains owning their own data, the shared platform underneath, the governance enforced at the mesh and registry boundaries — is running code here, not a slide. This is the capstone shape the 201 builds toward in depth.",
});

/* ============================ 16 · FITNESS ============================ */
contentSlide({
  eyebrow: "An honest caveat",
  title: "When each pattern fits",
  bullets: [
    { text: "The choice depends on scale, data landscape, and where the bottleneck sits — not on which pattern is newest. A data mesh is not always the answer." },
    { head: true, text: "Pipelines" },
    { text: "Small number of well-understood integrations, stable flows, no pressing need for cross-domain analytics. The sprawl hasn't started.", lvl: 1 },
    { head: true, text: "Warehouse" },
    { text: "The organization needs a governed analytical view and a central team has the capacity to curate it. The bottleneck is the absence of a single source of truth.", lvl: 1 },
    { head: true, text: "Lake" },
    { text: "Heterogeneous data, ML/AI workloads, scale that exceeds what a warehouse handles. The bottleneck is format rigidity, not ownership.", lvl: 1 },
    { head: true, text: "Mesh" },
    { text: "Many domains, many consumers, and a central team has become the constraint — and the organization has the maturity to operate federated ownership.", color: C.ink },
  ],
  notes: "Not every organization needs a mesh, and telling people when not to use one builds more credibility than pitching it unconditionally. The question to ask is whether the bottleneck is technical — better tools solve it — or organizational — who owns what. Pipelines still fit when the plumbing is simple. A warehouse still fits when the real need is a single governed source of truth and a central team can keep up. A lake still fits when the problem is format flexibility, not ownership. The mesh fits specifically when the organization has outgrown centralized ownership — many domains, many consumers, a central team as the constraint — and has the organizational maturity to operate domain teams that treat data as a product and a platform team that can run self-serve infrastructure. Pick the pattern that matches your actual bottleneck.",
});

/* ============================ 17 · CLOSING ============================ */
(() => {
  const s = divider({
    num: "→",
    title: "Go deeper: the 201",
    sub: "Orchestration styles in full depth, the Quarkus-vs-Spring-Boot numbers, contracts and the catalog, progressive delivery, autoscaling, and observability.",
  });
  s.addNotes("That's the 101: the landscape that led to data mesh, the four principles that define it, and why Quarkus and Kubernetes are a natural pairing for building one. The 201 goes deep on everything we only teased here — the full choreography-versus-orchestration comparison across Kafka, Camel, and Quarkus Flow; the Quarkus-vs-Spring-Boot side-by-side on startup time, memory, and native builds; contracts and the schema catalog; progressive delivery with mutual TLS; elastic autoscaling with KEDA; and the observability stack tying it all together. The reference repository is patterncatalyst/datamesh-reference-arch-quarkus — it's unpublished pending approval, but that's the name to look for. Thanks — happy to take questions.");
})();

/* ============================ WRITE ============================ */
pres.writeFile({ fileName: "Datamesh_101-r1.0.pptx" }).then((f) => console.log("WROTE", f));
