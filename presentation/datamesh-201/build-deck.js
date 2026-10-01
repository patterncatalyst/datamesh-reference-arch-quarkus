// Build the Datamesh 201 deep-dive deck — Quarkus + Kubernetes.
// Mirrors the structure of the sibling Python "Data Mesh on OpenShift" deck:
// section dividers, diagram-forward content, code slides where code is the
// lesson, one slide per demo, speaker notes on every slide, large appendix.
const L = require("./deck-lib.js");
const { pres, C, F, PW, PH, titleSlide, agendaSlide, divider, contentSlide, diagramSlide, codeSlide } = L;
const code = (s) => s.replace(/\t/g, "  ");

pres.title = "Building a Datamesh using Quarkus and Kubernetes";

// ---- local helper: two diagrams side by side (for parking unused figures
// in the appendix without giving each one a full-width slide) ----
function twoUpDiagramSlide({ eyebrow, title, images, captions, note, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, eyebrow, title);
  const gap = 0.4, totalW = PW - 1.4, colW = (totalW - gap) / 2, maxH = 3.85;
  const y0 = 1.85;
  images.forEach((img, i) => {
    const d = L.DIMS[img];
    let w = colW, h = w * (d.h / d.w);
    if (h > maxH) { h = maxH; w = h * (d.w / d.h); }
    const colX = 0.7 + i * (colW + gap);
    const x = colX + (colW - w) / 2;
    const y = y0 + (maxH - h) / 2;
    s.addImage({ path: L.IMG(img), x, y, w, h });
    if (captions && captions[i]) {
      s.addText(captions[i], { x: colX, y: y0 + maxH + 0.08, w: colW, h: 0.4, fontSize: 10.5, color: C.gray, fontFace: F.body, italic: true, align: "center", valign: "top", margin: 0 });
    }
  });
  if (note) s.addText(note, { x: 0.8, y: PH - 0.85, w: PW - 1.6, h: 0.4, fontSize: 11, color: C.gray, fontFace: F.body, italic: true, align: "center", valign: "top", margin: 0 });
  L.footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

/* ============================ TITLE ============================ */
titleSlide({
  eyebrow: "Data Mesh · 201",
  title: "Building a Datamesh using Quarkus and Kubernetes",
  subtitle: "From the four principles to a running platform on Quarkus + Kubernetes — capability tour, three orchestration engines, AI+rules triage, and live demos; no prior Quarkus experience required.",
  tagline: "The deep-dive, not the pitch",
  breadcrumb: "Data Mesh · 201",
  notes: "Welcome to the 201 deep-dive. This is not the conceptual case for data mesh — that's the 101 deck. This is the running system: a Quarkus-and-Kubernetes reference architecture, built on the shipping/order domain, with eighteen real demo scripts behind it. No prior Quarkus experience is assumed — every capability is demonstrated from first principles as it comes up, so this deck doubles as a Quarkus showroom for newcomers to the framework as well as a data-mesh deep dive for anyone who's seen the 101. Set expectations up front: this is a long walk, deliberately diagram-forward, with code where the code is the lesson, and an honest accounting of what works, what's opt-in, and the one thing (DEF-001) that's documented as broken rather than hidden.",
});

/* ============================ AGENDA ============================ */
agendaSlide({
  left: [
    { text: "00 · From principles to platform" },
    { text: "01 · Quarkus capability tour" },
    { text: "02 · Data as a product" },
    { text: "03 · The three engines" },
    { text: "04 · AI + rules triage" },
    { text: "05 · Quarkus vs. Spring Boot" },
  ],
  right: [
    { text: "06 · Platform: self-serve, elastic, resilient" },
    { text: "07 · Governance, mesh, observability" },
    { text: "08 · Security" },
    { text: "09 · Native" },
    { text: "10 · The whole picture" },
    { text: "11 · Appendices" },
    { text: "Appendix", italic: true },
  ],
  notes: "Thirteen sections. The spine is the same four data-mesh principles the 101 deck introduced, but every section here is anchored to real Quarkus code and a runnable demo script, not a conceptual diagram alone. Section 03 is the centerpiece this deck adds over the Python sibling — three different coordination engines over the same domain. Section 04 is the second centerpiece — AI classification feeding a deterministic rules engine, with an honest caveat about what doesn't work. The appendix is large on purpose: every diagram gets a home, every decision gets a citation, and the matrix of all eighteen demos lives there in one place.",
});

/* ====================== 00 · FROM PRINCIPLES TO PLATFORM ====================== */
(() => {
  const s = divider({ num: "00", title: "From principles to platform", sub: "The four principles, the reference architecture we build toward, and how the pieces map onto Quarkus and Kubernetes." });
  s.addNotes("Orientation. Three diagrams: the four principles recapped, the reference architecture this whole deck assembles piece by piece, and the principles-to-Kubernetes-primitives map. Keep it brisk — this is the map, not the territory. Everything in this section already appeared in the 101 deck; the point here is simply to re-anchor before we go deep on Quarkus specifics.");
})();

diagramSlide({ eyebrow: "From principles to platform", title: "Four principles, recapped",
  image: "01-data-mesh-four-principles",
  caption: "Domain ownership, data as a product, self-serve data platform, federated computational governance — interlocking, not sequential.",
  notes: "Straight from the 101 deck, deliberately, so the two decks connect. The four principles don't layer on top of each other — they interlock. Implement data-as-a-product without a self-serve platform and every domain reinvents its own Kafka; implement governance without domain ownership and you've rebuilt the central bottleneck under new vocabulary. Everything from here on is 'here is where Quarkus and Kubernetes put each of these four.'" });

diagramSlide({ eyebrow: "From principles to platform", title: "The reference architecture we build toward",
  image: "08-reference-architecture",
  caption: "Data products behind the Istio mesh, KEDA-driven autoscaling, and every signal flowing through the OpenTelemetry Collector into Grafana LGTM and Kiali.",
  notes: "The centerpiece we return to assembled in section 10. For now, just orient: data products in the middle, the selectively-meshed Istio data plane around them, KEDA watching two of them from outside the mesh, and the Collector fanning every signal — metrics, traces, logs — into one observability stack. Promise the audience: by the end, every box here will have had its own demo." });

diagramSlide({ eyebrow: "From principles to platform", title: "From principles to Kubernetes and Quarkus pieces",
  image: "02-principles-to-pieces",
  caption: "The four principles mapped to concrete primitives — namespaces, Deployments and CRDs, operators, admission/mesh policy — the vocabulary the rest of this deck uses by name.",
  notes: "This is the deck's whole structure in one picture. Domain ownership maps to namespace/Project boundaries; data as a product maps to a Deployment+Service+contract per domain; self-serve platform maps to operators (Strimzi, CloudNativePG, KEDA); federated governance maps to the mesh and admission policy. Every later section is one column of this picture, built out with real Quarkus code and a demo." });

/* ====================== 01 · QUARKUS CAPABILITY TOUR ====================== */
(() => {
  const s = divider({ num: "01", title: "Quarkus capability tour", sub: "Nine capabilities, each demonstrated by a real endpoint or route already running in this reactor — not a toy snippet." });
  s.addNotes("Nine capabilities across Panache, gRPC, GraphQL, Reactive Messaging, WebSockets.Next, unified Vert.x reactive/imperative execution, continuous testing, native compilation, OIDC, and JBang. Read this section left to right as a map, not a sequence — nothing here depends on anything else running first. The two capabilities the rest of the deck leans on by name are Reactive Messaging (section 03's choreography leg republishes the exact OrderEventProducer shown here) and plain orchestration over bean calls (sections 03 and 04).");
})();

diagramSlide({ eyebrow: "Quarkus capability tour", title: "Nine capabilities, nine real services",
  image: "11-capability-tour",
  caption: "Panache and Vert.x unification in inventory-service; gRPC between inventory-service and the gateway; GraphQL federation; Reactive Messaging and WebSockets.Next; continuous testing and native compilation; OIDC; JBang prototyping.",
  notes: "Walk the map once. inventory-service carries the most capabilities at once (Panache, gRPC, REST, the reactive/imperative split) because it's the smallest aggregate with the richest protocol surface. order-service carries continuous testing and native compilation because it's the cleanest REST+Panache service in the reactor. review-service got OIDC because it's the smallest module — one protected endpoint, zero cross-service calls, nothing to distract from the capability. JBang stands alone, deliberately — it needs no other service running." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "demo-order.sh — Panache + REST, the template product",
  image: "03-data-product-anatomy",
  caption: "order-service IS this picture: a Panache entity as its own repository, REST input/output ports, a gRPC call out, an event published on commit.",
  notes: "DEMO 1 of 18. What it does: POST /orders calls inventory-service's CheckStock over gRPC to validate stock, persists the Order via Hibernate ORM Panache, then publishes order.placed to Kafka (best-effort here; the Avro wire-format proof is demo-kafka.sh's job, not this one's). Presenter cue: place an order, GET it back by id, then query Postgres directly to show the row is really there — three independent confirmations, not one green checkmark. Infra tier: compose (docker compose up -d; postgres + kafka + apicurio baseline). Fallback: a recorded transcript of the 201/200/404 status codes and the row dump, narrated the same way live." });

codeSlide({ eyebrow: "Quarkus capability tour", title: "Panache: the entity IS the repository",
  lang: "Java · Hibernate ORM Panache",
  note: "Active record, not repository-plus-DAO: Order.findById(id) and order.persist() are the whole data-access layer. OrderResource calls Order directly — no OrderRepository interface, no mapper, no @Autowired DAO standing between the REST layer and the row.",
  code: code(`@Entity
@Table(name = "orders")
public class Order extends PanacheEntityBase {

	@Id
	@Column(length = 36, nullable = false, updatable = false)
	public String id;

	@Column(name = "customer_id", nullable = false)
	public String customerId;
	// itemSku, quantity, amount, status, createdAt ...

	public static Order create(String customerId, String itemSku,
			int quantity, BigDecimal amount) {
		Order order = new Order();
		order.id = UUID.randomUUID().toString();
		return order;
	}
}

// OrderResource — no repository bean in between:
Order order = Order.findById(id);
order.persist();`),
  notes: "The trade-off is real: your entity now depends on a Panache base class, and active record doesn't suit every team's layering preference. But for a reference architecture built around one aggregate per service, it removes an entire layer of indirection with nothing lost — inventory-service's StockResource calls Stock.findBySku(...) the same way, directly from a JAX-RS resource method." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "demo-grpc.sh — a typed contract, generated at build time",
  image: "05-api-implementations",
  caption: "REST at the edge, gRPC between services, GraphQL to compose, events to decouple — each protocol's Quarkus extension and contract type, by fitness.",
  notes: "DEMO 2 of 18. What it does: inventory-service answers capstone.inventory.v1.InventoryService/CheckStock over gRPC; InventoryService itself is generated at build time from contracts/.../inventory.proto, not hand-written. @GrpcService registers the bean; @Blocking tells Vert.x this handler does blocking Panache work and should run on a worker thread even though its signature is the fully reactive Uni<CheckStockResponse>. Presenter cue: drive it DIRECTLY with grpcurl against the real .proto — a genuine gRPC client over HTTP/2, not a REST call in disguise, so there's no ambiguity about which protocol actually ran. Infra tier: compose. Fallback: recorded grpcurl JSON response showing available/quantityOnHand." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "demo-graphql.sh — one query, two downstream protocols",
  bullets: [
    { text: "graphql-gateway's GatewayApi federates two protocols behind one /graphql endpoint: order(id) resolves over REST from order-service; the nested stock field resolves over gRPC from inventory-service." },
    { text: "MicroProfile GraphQL's @Source marks stock as a field resolver — SmallRye GraphQL only calls it when a client query actually selects that field.", lvl: 1 },
    { text: "That laziness matters: a client asking only for order(id) { customerId } never triggers the gRPC call at all. One request, two backend protocols, stitched into one response shape — opt-in per query, not per endpoint.", lvl: 1 },
    { head: true, text: "Presenter cue" },
    { text: "Place a real order, then query the gateway and assert both the REST-sourced order fields and the gRPC-sourced nested stock fields land in one .data.order payload with no .errors." },
    { head: true, text: "Infra tier · fallback" },
    { text: "compose (docker compose up -d). Fallback: recorded .data.order JSON showing both REST- and gRPC-sourced fields together.", color: C.ink },
  ],
  notes: "DEMO 3 of 18. The thing to land: the domain services were NOT changed to support GraphQL — they keep their plain REST and gRPC interfaces. The gateway is doing the composing. This is gateway orchestration of reads, not true subgraph federation, but it's the right-sized answer for five services." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "demo-reactive-vertx.sh — one reactor, two execution models",
  bullets: [
    { text: "inventory-service answers the SAME stock table through two execution models at once, on the same Vert.x reactor, in the same JVM." },
    { text: "Reactive: the gRPC CheckStock handler, a Uni<CheckStockResponse>, with its blocking Panache lookup offloaded via @Blocking.", lvl: 1 },
    { text: "Imperative: StockResource, a classic thread-per-request JAX-RS method, no Uni anywhere.", lvl: 1 },
    { text: "They don't even compute the same thing — gRPC's available is request-dependent (quantity > 0 && onHand >= quantity); REST's available is a static snapshot (quantityOnHand > 0).", lvl: 1 },
    { head: true, text: "Presenter cue · infra tier · fallback" },
    { text: "Fire three gRPC and three REST calls concurrently against one running process; assert every response is correct and uncorrelated. Infra: compose. Fallback: recorded six-call transcript, all six correct.", color: C.ink },
  ],
  notes: "DEMO 4 of 18. The textbook Quarkus/Vert.x claim — 'unified reactive and imperative, one reactor' — exercised under genuine concurrent load, not just asserted in prose. The framework, not the developer, decides which thread pool a given request lands on, based on @Blocking and the handler's declared return type. No migration, no second event loop spun up for the imperative side." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "demo-websocket.sh — pushing an already-committed event",
  bullets: [
    { text: "notification-service's /ws/notifications endpoint (WebSockets.Next) is deliberately thin — its only job is to acknowledge a connection." },
    { text: "The real push happens from OrderPlacedConsumer, the same Reactive Messaging consumer that reacts to order.placed, right after it persists a Notification row.", lvl: 1 },
    { text: "Design decision worth noticing: the push happens AFTER the transaction commits, not before — a client only ever sees an event that is already durable, never a speculative one that might roll back.", lvl: 1 },
    { head: true, text: "Presenter cue · infra tier · fallback" },
    { text: "A real JDK java.net.http.WebSocket client (via JBang), connected BEFORE an order is placed, asserts the second message it receives matches the order's orderId/customerId/itemSku exactly. Infra: compose. Fallback: recorded socket transcript.", color: C.ink },
  ],
  notes: "DEMO 5 of 18. WebSockets.Next and Reactive Messaging compose naturally — a Kafka consumer can push to every open socket connection the moment it commits, with no polling. OpenConnections is WebSockets.Next's injectable registry of live connections; listAll().forEach(...).sendTextAndAwait(...) does the fan-out." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "demo-jbang-prototype.sh — prototyping without a Maven module",
  bullets: [
    { text: "demos/jbang/HelloRoute.java is a complete Camel route with no pom.xml and no Maven reactor module." },
    { text: "jbang camel@apache/camel run HelloRoute.java resolves Camel's runtime straight from Maven Central and runs the route directly.", lvl: 1 },
    { text: "The 'sketch an idea before committing to a module' workflow — useful for trying a route shape, an EIP combination, or a component configuration before paying the cost of a full Maven module.", lvl: 1 },
    { head: true, text: "Presenter cue · infra tier · fallback" },
    { text: "Assert the exact transformed marker string (JBANG_PROTOTYPE_OK: ...) appears in the route's log output — not just that the process exited zero. Infra: bare (JDK 25 + jbang on PATH; no docker compose needed). Fallback: recorded log line.", color: C.ink },
  ],
  notes: "DEMO 6 of 18. The lightest-weight demo in the reactor by design — no Maven, no containers, just jbang resolving Camel. jbang transparently installs/trusts the camel@apache/camel app-catalog entry on first use." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "demo-continuous-testing.sh — tests that run themselves",
  bullets: [
    { text: "mvn quarkus:dev with quarkus.test.continuous-testing=enabled re-runs a module's tests automatically on every save." },
    { text: "Dev Services provisions the Testcontainers (Postgres, Kafka, Apicurio) those tests need with zero docker compose and zero .env.", lvl: 1 },
    { text: "The demo watches order-service's own dev-mode log for the literal Quarkus 3.39.5 pass banner and parses it for passing/run counts, asserting passing == run.", lvl: 1 },
    { text: "If the banner never appears, the demo does NOT silently treat 'the app came up' as a pass — a demo that can't observe its target capability should fail, not quietly narrow its claim.", color: C.ink },
    { head: true, text: "Infra tier · fallback" },
    { text: "bare (JDK 25 + Maven only; Dev Services spins its own containers). Fallback: recorded 'All 4 tests are passing (0 skipped), 4 tests were run in 8318ms.' banner line.", color: C.ink },
  ],
  notes: "DEMO 7 of 18. Continuous testing and native compilation sit at opposite ends of the feedback-loop spectrum — instant, infra-provisioned reruns on one end, a multi-minute ahead-of-time compile on the other. Dev Services only applies to the former." });

/* ====================== 02 · DATA AS A PRODUCT ====================== */
(() => {
  const s = divider({ num: "02", title: "Data as a product", sub: "Contracts, the registry, and the catalog — a data product held to the standard of any software product." });
  s.addNotes("Data as a product is the principle this section is about. The teaching spine: a runtime contract (Avro, load-bearing on the hot path) is a different kind of thing from a discovery contract (OpenAPI/Protobuf/SDL, descriptive); conflating the two is the most common confusion in this space. DRQ-009 is the governing decision: every Kafka event in this reactor uses Avro via Apicurio from day one — no JSON shortcut, even in early phases.");
})();

diagramSlide({ eyebrow: "Data as a product", title: "Where analytical sourcing would plug in",
  image: "05-ingestion-streaming-sourcing",
  caption: "Ingestion, streaming, and CDC sourcing for analytical consumers — conceptual in this reactor, not built; shown so the picture of 'data as a product' stays complete.",
  notes: "This diagram is explicitly conceptual — this reactor doesn't ship a built analytical-sourcing layer or Debezium-style CDC. It's included because a complete 'data as a product' story has an analytical half as well as an operational one, and the shape is worth seeing even though we didn't build it here." });

diagramSlide({ eyebrow: "Data as a product", title: "demo-kafka.sh — Avro on the wire, proven byte by byte",
  image: "04-contract-flow",
  caption: "The runtime path (serialize, publish, fetch schema, deserialize) vs. the discovery path (OpenAPI/Protobuf/SDL/Avro contracts for a catalog to ingest).",
  notes: "DEMO 8 of 18. DRQ-009: every Kafka event in this reactor uses Avro against the Apicurio Schema Registry from the start — no JSON shortcut, ever. order-service pins AvroKafkaSerializer EXPLICITLY in application.properties, because Quarkus's connector-serializer autodetection was proven to silently fall back to a Jackson/JSON serializer here (two Avro serdes on the classpath creates ambiguity). Presenter cue: place a real order, then read the RAW bytes back off the real compose Kafka broker with a plain byte-level consumer and assert the Apicurio/Confluent wire-format magic byte (0x00) is the first byte — proof this is genuine Avro, not JSON (0x7B) masquerading as an event. Infra tier: compose. Fallback: recorded byte dump showing 0x00 + schema id." });

diagramSlide({ eyebrow: "Data as a product", title: "Runtime vs. discovery contracts — and the catalog gap",
  image: "04-contracts-registry-catalog",
  caption: "Runtime contracts (Avro, filled) vs. discovery contracts (OpenAPI/Protobuf/SDL, hollow) — all registered in Apicurio; a catalog downstream would ingest them into a lineage graph.",
  notes: "The conceptual heart of contracts, stated precisely: a RUNTIME contract (Avro) is load-bearing — the event literally won't serialize without it, so the registry can reject a breaking change at publish time, computational governance in action. A DISCOVERY contract (OpenAPI, GraphQL SDL, Protobuf) is descriptive — source of truth for humans and CI, but nothing fails at runtime if it's stale. This reactor registers both kinds in Apicurio; a full catalog (OpenMetadata) ingesting them into lineage is the conceptual next step, not built here." });

codeSlide({ eyebrow: "Data as a product", title: "The runtime contract: a registered Avro schema",
  lang: "Avro · Apicurio Schema Registry",
  note: "Illustrative of the contracts module's shape (capstone.order.v1.OrderPlaced). AvroKafkaSerializer is pinned EXPLICITLY in application.properties on the producer side — autodetection proved unreliable here with two Avro serdes on the classpath (DRQ-009).",
  code: code(`{
  "type": "record",
  "namespace": "capstone.order.v1",
  "name": "OrderPlaced",
  "fields": [
    { "name": "eventType",   "type": "string" },
    { "name": "orderId",     "type": "string" },
    { "name": "customerId",  "type": "string" },
    { "name": "itemSku",     "type": "string" },
    { "name": "quantity",    "type": "int" },
    { "name": "amount",      "type": "double" }
  ]
}
# registry: schema registered at publish time via
# apicurio-registry-avro; producer pins AvroKafkaSerializer explicitly`),
  notes: "Shown because the contract IS the lesson. order-service's OrderEventProducer builds this record via emitter.send(...); the consumer side (notification-service's OrderPlacedConsumer) is the mirror image, @Incoming('order-placed') on a plain @Transactional method — no manual Kafka client code on either side." });

diagramSlide({ eyebrow: "Data as a product", title: "The full contract picture, capstone view",
  image: "04-capstone-contracts",
  caption: "Every protocol's contract type feeding into Apicurio Registry, with a catalog downstream building lineage from the registry and the running data stores.",
  notes: "The closer for this section. Every protocol in this reactor — REST's OpenAPI, gRPC's Protobuf, GraphQL's SDL, Kafka's Avro — has a contract, and all of them register in one place (Apicurio). A mesh's premise is consumers finding and trusting products WITHOUT a central team; without a usable registry/catalog, they fall back to asking someone, and the bottleneck returns." });

/* ====================== 03 · THE THREE ENGINES (DRQ-015) ====================== */
(() => {
  const s = divider({ num: "03", title: "The three engines", sub: "DRQ-015: three coordination mechanisms over the SAME shipping/order domain — choreography, and two shapes of orchestration." });
  s.addNotes("The centerpiece this deck adds. Every event-driven system eventually answers one question: when multiple steps need to happen in sequence, who decides the sequence? This reactor runs three different answers side by side so the distinction can be SHOWN, not just defined. Terminology discipline, exact: Kafka is choreography; Camel and Quarkus Flow are both orchestration — they differ in HOW the sequence is expressed (imperative route vs. declarative workflow document), not in whether a coordinator exists. Don't let 'orchestration' collapse into 'a specific technology.'");
})();

diagramSlide({ eyebrow: "The three engines", title: "Three coordination shapes, one domain",
  image: "13-orchestration-styles",
  caption: "Decentralized Kafka choreography; a Camel route explicitly sequencing steps; a declarative Quarkus Flow workflow document expressing the same two tasks.",
  notes: "Trace the three boxes with your finger. The choreography box has no single arrow entering from 'the top' — no node labeled coordinator, because there isn't one. The two orchestration boxes both have exactly one entry point and one thing that owns the sequence, but draw that ownership differently: the Camel box is a straight line of named steps (a route IS a sequence of method calls); the Quarkus Flow box is a small graph of declared tasks (a workflow document describes WHAT must happen before WHAT, and leaves HOW to the engine). That distinction — code that calls things in order vs. data that declares an order — is worth more teaching time than 'orchestration vs. choreography' itself." });

contentSlide({ eyebrow: "The three engines", title: "Engine 1 — Kafka choreography: no one is in charge",
  bullets: [
    { text: "order-service publishes order.placed and has never heard of payment-service or shipping-service — doesn't know they exist, doesn't call them, doesn't wait on them." },
    { text: "payment-service independently subscribes to order.placed; on arrival it captures payment and publishes payment.captured.", lvl: 1 },
    { text: "shipping-service independently subscribes to payment.captured; on arrival it dispatches and publishes shipment.dispatched.", lvl: 1 },
    { text: "notification-service ALSO independently subscribes to order.placed — a fourth, parallel reaction to the same original event, not a step after the chain.", lvl: 1 },
    { head: true, text: "Cost and benefit, stated as the same fact" },
    { text: "No single place reads 'what happens when an order is placed' — you have to go find every subscriber. But adding a fifth reaction (say, analytics) costs zero changes to any existing service. That loose coupling is why event-driven systems reach for choreography by default.", color: C.ink },
  ],
  notes: "No service holds a reference to 'the whole sequence.' Each one knows exactly one rule: when I see event X, I do Y and emit Z (or, for notification-service, just do Y). This is the baseline the next two engines contrast against." });

codeSlide({ eyebrow: "The three engines", title: "Engine 2 — Camel orchestration: the route IS the coordinator",
  lang: "Java · Camel route · POST /api/orders/triage",
  note: "One route explicitly sequences every step — unmarshal, classify, decide, marshal. Reading it top to bottom IS reading the business process. classify (Ollama) and decide (Drools) are plain bean methods; the route coordinates, it does not decide.",
  code: code(`from("direct:triage")
    .routeId("triage-order")
    .unmarshal().json(JsonLibrary.Jackson, OrderCreate.class)
    .bean(triageService, "classify")
    .bean(triageService, "decide")
    .marshal().json(JsonLibrary.Jackson);`),
  notes: "ai-rules-service exposes this at POST /api/orders/triage. Orchestration means a single process explicitly sequences the steps and knows the whole flow — nothing about this sequence is implicit or discoverable only at runtime." });

codeSlide({ eyebrow: "The three engines", title: "Engine 3 — Quarkus Flow: the same two steps, declared",
  lang: "Java · Quarkus Flow (CNCF Serverless Workflow) · POST /api/orders/triage-flow",
  note: "A declarative coordinator: a workflow DOCUMENT, structurally the same shape as a CNCF Serverless Workflow YAML/JSON file, not imperative route code. Both classify and decide are the IDENTICAL TriageService methods Engine 2 calls — same logic, different coordination shape.\n\nWhen to reach for which: choreography for independent reactions and a growing/unknown subscriber set; Camel when the process needs full imperative control (branching, EIPs, code review as the artifact); Quarkus Flow when that same fixed process is better reviewed, versioned, or edited as a document than as a Java release.",
  code: code(`return FlowWorkflowBuilder.workflow("order-triage")
    .tasks(
        FlowDSL.function("classify", triageService::classify),
        FlowDSL.function("decide", triageService::decide))
    .build();`),
  notes: "This is the leg that breaks a common misconception: learners new to this space tend to conflate 'a coordinator exists' with 'the coordinator is a hand-written imperative function.' Quarkus Flow exists specifically to show a coordinator can be declared as data instead. Both /triage and /triage-flow delegate to the exact same TriageService.classify/decide — Drools still makes the one decision that matters, in both paths." });

contentSlide({ eyebrow: "The three engines", title: "demo-orchestration-styles.sh — all three, back to back",
  bullets: [
    { text: "Act 1 (choreography): places one real order, polls each downstream Kafka topic with a byte-level consumer, and asserts the Avro wire-format magic byte on every hop — plus a direct Postgres row check and a REST lookup corroborating independently." },
    { text: "Act 2 (Camel orchestration): posts to /triage and asserts a strict decision (ROUTE_TO_WAREHOUSE) for a pre-validated, stable low-risk input." },
    { text: "Act 3 (Quarkus Flow orchestration): posts the IDENTICAL input to /triage-flow and asserts the IDENTICAL decision — proof the two orchestration shapes drive the same underlying logic." },
    { text: "Honest limit: the three acts share a domain and a comparison, not one literal order flowing through all three end to end — Act 1's order was never run through the classifier-stability trial Acts 2/3 require.", color: C.ink },
    { head: true, text: "Infra tier · fallback" },
    { text: "compose baseline for Act 1 (five services); Act 2/3 require the compose ollama profile, opt-in via --with-ollama (Ollama-backed classification). Fallback: recorded narration transcript of all three acts.", color: C.ink },
  ],
  notes: "DEMO 9 of 18. This is the showcase demo for DRQ-015. The script's own header is explicit about the honest limit above — don't claim more continuity between the acts than the demo itself claims." });

/* ====================== 04 · AI + RULES TRIAGE ====================== */
(() => {
  const s = divider({ num: "04", title: "AI + rules triage", sub: "DRQ-012/014: an LLM extracts structured fields; a deterministic Drools rule set makes the business decision." });
  s.addNotes("The strict division of labor this reactor teaches: the LLM classifies, Drools decides. An LLM is good at reading a loosely-structured order description and pulling out a few categorical fields; it is a poor choice to make a decision you need to audit, replay deterministically, or explain to a compliance reviewer. This section also carries the DEF-001 caveat — a separate, genuinely broken capability (in-process multi-turn tool-calling) in a DIFFERENT service, documented honestly rather than hidden.");
})();

diagramSlide({ eyebrow: "AI + rules triage", title: "Ollama classifies, Drools decides",
  image: "14-ai-rules-triage",
  caption: "classify (Ollama qwen2.5:3b) produces category/priority/riskSignal; decide (a Drools KieSession firing order-triage.drl) returns FRAUD_HOLD, EXPEDITE, or ROUTE_TO_WAREHOUSE. A separate DEF-001 branch shows where in-process tool-calling breaks, and where the embedded MCP server path works.",
  notes: "Read the diagram as two halves. Top half: one LLM call feeding one deterministic rule engine, reached by two orchestration shapes (section 03) that both terminate in the identical TriageService methods. Bottom half: the cautionary half — the same local model, wired into a STRUCTURALLY DIFFERENT capability (multi-turn tool-calling) in a DIFFERENT service (ai-mcp-service), where one path is broken for a documented upstream reason while a second, structurally separate path works perfectly. The fact that an LLM call succeeds in one part of this reactor is not evidence a structurally different LLM call succeeds elsewhere — that's this section's whole second half." });

contentSlide({ eyebrow: "AI + rules triage", title: "demo-ai-classify.sh — single-shot classification, immune to DEF-001",
  bullets: [
    { text: "ai-mcp-service's OrderClassifierRoute exposes POST /api/orders/classify, a langchain4j-chat single-shot call (CHAT_SINGLE_MESSAGE_WITH_PROMPT) — not an agent, not tool calling." },
    { text: "Structurally immune to DEF-001: the deferral lives entirely in the tool-calling path (OrderLookupToolRoute/OrderAssistantRoute), neither of which this demo touches.", lvl: 1 },
    { text: "The capability itself needed its own fix, separate from DEF-001: a misnamed prompt-template header plus the endpoint's default operation mode silently made the model chat about the order instead of classifying it — fixed by correcting the header name and setting the single-message operation explicitly.", lvl: 1 },
    { head: true, text: "Presenter cue · infra tier · fallback" },
    { text: "Assert the classify endpoint returns one of the defined category labels. Infra: compose + ollama profile. Fallback: recorded category label response.", color: C.ink },
  ],
  notes: "DEMO 10 of 18. Worth stating plainly: single-shot classification (this demo, and TriageService.classify) is a reliable shape to build on, as long as you defensively parse its output — it is categorically different from multi-turn tool-calling, which is where DEF-001 lives." });

contentSlide({ eyebrow: "AI + rules triage", title: "demo-ai-triage.sh — the showcase (DRQ-012/DRQ-014)",
  bullets: [
    { text: "Both POST /api/orders/triage (Camel) and POST /api/orders/triage-flow (Quarkus Flow) run the identical classify-then-decide pipeline: Ollama (qwen2.5:3b) classifies, a Drools KieSession fires order-triage.drl and makes the ONE decision that matters." },
    { text: "Three salience-guarded, mutually-exclusive rules: FRAUD_HOLD (HIGH risk signal), EXPEDITE (amount ≥ 1000 with LOW risk), ROUTE_TO_WAREHOUSE (default). The model never makes the business call directly.", lvl: 1 },
    { text: "Three pre-validated inputs — sampled repeatedly against the live model until their classification was shown STABLE, not just plausible — assert the exact expected decision (not merely 'one of three valid values') on both endpoints.", lvl: 1 },
    { text: "Both endpoints return the identical decision for the identical input: proof the two orchestration shapes drive the same underlying logic, not two independently-tuned copies of it.", color: C.ink },
    { head: true, text: "Infra tier · fallback" },
    { text: "compose + ollama profile (host Ollama with qwen2.5:3b already pulled, or the compose ollama profile). Fallback: recorded three-decision table across both endpoints.", color: C.ink },
  ],
  notes: "DEMO 11 of 18. This is the primary AI demo in the whole reactor. It sidesteps DEF-001 entirely by design — Drools, not langchain4j tool-calling, makes the decision, so no in-process agent round trip is required for the demo to work end to end." });

contentSlide({ eyebrow: "AI + rules triage", title: "demo-camel-integration.sh — the EIP logic, proven independent of DEF-001",
  bullets: [
    { text: "Subject: OrderLookupToolRoute, a textbook Content-Based Router EIP (.choice()/.when()×3/.otherwise()) that inspects an orderId and routes to one of four distinct, statically-defined response bodies." },
    { text: "Reached through the same MCP server surface demo-ai-mcp.sh uses — asserts all four branches, including the .otherwise() fallback for an unrecognized order id.", lvl: 1 },
    { text: "The point: this proves the routing logic itself is correct, entirely independent of whether in-process tool-calling (DEF-001) works.", color: C.ink },
    { head: true, text: "Infra tier · fallback" },
    { text: "compose + ollama profile. Fallback: recorded four-branch response transcript (ORD-001/002/003 plus the unrecognized-id fallback).", color: C.ink },
  ],
  notes: "DEMO 12 of 18. A deliberately Camel/EIP-focused demo, distinct from the AI-capability demos around it — it's here to isolate 'does the route logic work' from 'does the AI tool-calling work', because those are two different questions this reactor answers separately." });

contentSlide({ eyebrow: "AI + rules triage", title: "demo-ai-mcp.sh — DEF-001: asserts ONLY the MCP-server path",
  bullets: [
    { text: "MANDATORY CAVEAT: in-process langchain4j agent tool-calling does NOT fire on this stack. Root cause: camel-quarkus-support-langchain4j unconditionally sets the global langchain4j.http.clientBuilderFactory system property for EVERY dev.langchain4j model — there is no toggle — so the hand-built OllamaChatModel's configured base-url is never honored by the transport that sends the request." },
    { text: "This demo never calls POST /api/assistant/chat and never treats a non-empty chat response as evidence tool-calling succeeded. It prints an explicit banner before running anything.", color: C.ink },
    { text: "What DOES work: the embedded Camel MCP server, a structurally SEPARATE code path with no langchain4j-agent involved — real MCP Streamable HTTP, real JSON-RPC 2.0: initialize → tools/list → tools/call(order-status) for ORD-001/002/003.", lvl: 1 },
    { head: true, text: "Infra tier · fallback" },
    { text: "compose + ollama profile. Fallback: recorded MCP JSON-RPC transcript (handshake, tool list, three deterministic lookups).", color: C.ink },
  ],
  notes: "DEMO 13 of 18. Diagnosed as a transport-wiring defect in camel-quarkus-support-langchain4j, not a model-capability problem (a direct Ollama /api/chat call WITH a tools array does return tool_calls) and not a tool-registration problem (tags line up correctly). Tracked as DEF-001, an open upstream deferral — full root cause is in the appendix. Demonstrating a known limitation honestly, with a banner and a demo that deliberately never calls the broken endpoint, is more useful than hiding it." });

/* ====================== 05 · QUARKUS VS. SPRING BOOT ====================== */
(() => {
  const s = divider({ num: "05", title: "Quarkus vs. Spring Boot", sub: "DRQ-006: the same order-service data product, rebuilt as a Spring Boot twin, measured side by side — JVM only." });
  s.addNotes("The only chapter in this deck that steps outside Quarkus entirely. One runnable Spring Boot 4.0.8 twin, same JDK 25, feature-matched dependency surface (REST, Panache-equivalent JPA, Kafka/Avro, gRPC client) — built so the numbers reflect the framework, not a difference in scope. No demo-springboot.sh exists; this section is a diagram-and-script story, not a live demo.");
})();

diagramSlide({ eyebrow: "Quarkus vs. Spring Boot", title: "Same workload, same JVM, two startup paths",
  image: "12-quarkus-vs-spring-boot",
  caption: "order-service (Quarkus, build-time metaprogramming) and spring-boot-compare (Spring Boot 4.0.8, classpath scanning and reflection at startup) booting against the same throwaway postgres:18 container under identical JVM flags, each measured via its own self-reported started-log line.",
  notes: "The twin reuses the project's framework-agnostic jars unmodified — the same domain-model DTOs and the same generated Avro OrderPlaced class both services serialize — so there is zero schema or DTO drift between the two. The one genuine code difference is the persistence idiom: Panache active record vs. a derived Spring Data JPA repository. Everything else the two services DO is identical." });

contentSlide({ eyebrow: "Quarkus vs. Spring Boot", title: "The numbers — and the honesty that keeps them trustworthy",
  bullets: [
    { head: true, text: "One real run, both services under their packaged/prod profile" },
    { text: "order-service (Quarkus): 1.54 s self-reported startup · 314 MB resident memory (RSS).", color: C.ink },
    { text: "spring-boot-compare (Spring Boot): 3.21 s self-reported startup · 494 MB resident memory (RSS).", color: C.ink },
    { text: "Quarkus starts in roughly half the time and boots into roughly two-thirds the memory of a Spring Boot service carrying the identical REST + JPA + Kafka/Avro + gRPC surface — the payoff of build-time metaprogramming vs. startup-time classpath scanning and reflection.", lvl: 1 },
    { head: true, text: "What this is NOT — honesty is mandatory here" },
    { text: "JVM-to-JVM only: no native image on either side (Quarkus's native story is a separate axis — section 09)." },
    { text: "Indicative, not a benchmark: a single run on one developer machine via scripts/compare-quarkus-springboot.sh, unverified, no JIT warm-up or averaging across runs — your absolute numbers will differ." },
    { text: "The write paths are mocked in unit tests, not in this measurement — the measurement boots the REAL wiring (gRPC channel + Kafka producer both initialize)." },
  ],
  notes: "Measured by watching each framework's own self-reported 'boot complete' log line, not an aggregate health check — the script points KAFKA_BOOTSTRAP_SERVERS at a dead port on purpose for both services, so a health-based wait would time out on both sides and prove nothing. Every cell the script couldn't actually measure prints the literal placeholder <measured-on-run> rather than a fabricated number. When to reach for which: Quarkus's footprint matters most where you pay for it repeatedly — scale-to-zero, dense multi-tenant deployments, serverless; Spring Boot's ecosystem and team familiarity are real, countervailing advantages." });

/* ====================== 06 · PLATFORM: SELF-SERVE, ELASTIC, RESILIENT ====================== */
(() => {
  const s = divider({ num: "06", title: "Platform: self-serve, elastic, resilient", sub: "KEDA scales two real products to demand, and to zero — the self-serve platform in action." });
  s.addNotes("A domain that needs elastic scaling asks for a ScaledObject — it does not learn to operate the Kubernetes autoscaler internals. KEDA is the mechanism: it doesn't replace the HPA, it DRIVES one, and it covers the one thing the HPA fundamentally cannot do on its own — the zero-to-one transition.");
})();

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "The three planes of the platform",
  image: "02-platform-planes",
  caption: "External clients, the service-mesh plane running the domain services, and the self-serve platform plane underneath — protocols labeled on every flow between them.",
  notes: "A domain interacts with the higher planes by declaration, not raw infrastructure. The point isn't to memorize the plane names — it's that 'platform' is layered, and the layers below are exactly what sections 06 and 07 build out with real Kubernetes pieces." });

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "The stock HPA vs. KEDA's two-tier model",
  image: "07-hpa-vs-keda",
  caption: "The stock Kubernetes HPA scales on CPU/memory; KEDA drives an HPA from external signals (Kafka lag, HTTP rate) and handles the zero-to-one activation the HPA cannot do alone.",
  notes: "KEDA doesn't replace the HPA — a KEDA ScaledObject is consumed by the KEDA operator, which creates and manages a STANDARD Kubernetes HorizontalPodAutoscaler behind the scenes, fed by an external.metrics.k8s.io server KEDA itself runs. From 1 replica upward, the ordinary HPA control loop does the scaling on a Kafka-lag or HTTP-rate metric instead of CPU. The part the HPA fundamentally cannot do — minReplicas: 0 — is where KEDA's own operator polls the trigger source directly and does the 0-to-1 jump itself." });

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "Elastic products: scale on lag, even to zero",
  image: "07-keda-lag",
  caption: "The KEDA Kafka-lag scaler polls consumer-group lag on order.placed and scales notification-service from zero to N replicas once lag crosses the threshold, then back to zero after cooldown.",
  notes: "Why not CPU: a consumer idling at 0% CPU with a 10,000-message backlog SHOULD scale up, and CPU can't see that — lag can. scripts/setup-keda.sh installs KEDA core 2.19.0 via Helm. Scale-to-zero makes 'elastic data product' real economics: it costs nothing while idle." });

contentSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "demo-keda-kafka.sh — lag-driven scaling, on the real substrate",
  bullets: [
    { text: "KEDA core scales notification-service 0 → N on Kafka consumer-group lag, using the REAL step-9 minikube substrate — k8s/base/notification-service.yaml, k8s/keda/consumer-scaledobject.yaml, nothing invented." },
    { text: "Asserted: replica count climbs from zero on a lag burst and returns to zero as the backlog drains.", lvl: 1 },
    { head: true, text: "Presenter cue · infra tier · fallback" },
    { text: "Opt-in — minikube (requires the Phase C substrate: minikube with Istio, KEDA, Strimzi, CloudNativePG bootstrapped, kubectl context pointed at it). Fallback: recorded replica-count timeline (0 → N → 0).", color: C.ink },
  ],
  notes: "DEMO 14 of 18. Not required for the core compose-based demo set — this one specifically exercises the minikube/Kubernetes substrate from Phase C, not just docker compose." });

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "The KEDA HTTP add-on, as a system",
  image: "07-keda-http-addon",
  caption: "The interceptor proxy buffers requests to graphql-gateway and reports request rate to the external scaler, which drives the HTTPScaledObject's zero-to-N activation.",
  notes: "The HTTP add-on is itself a small system, not a single component — an interceptor proxy sits in front of the scaled Deployment, buffering requests while the Deployment is at zero and reporting rate to an external scaler. Pinned to 0.15.0 (full rationale in the appendix): v0.14.0 shipped a panic that 0.15.0 fixes, and 0.15.0 also adds HTTP/2 and gRPC support." });

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "Elastic reads: scaling on request volume",
  image: "07-keda-http",
  caption: "demo-keda-http.sh drives a request burst through the interceptor with the Host header set, polling graphql-gateway's replica count until it climbs off baseline within the 240-second budget.",
  notes: "Design point: HTTP scaling goes on graphql-gateway, deliberately NOT order-service — order-service carries the canary (section 07), and HTTP-scaling a service whose traffic is split by weight would have the two mechanisms fight over the same pods. Fit the mechanism to the workload." });

contentSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "demo-keda-http.sh — scale-to-zero on HTTP, on the real substrate",
  bullets: [
    { text: "KEDA HTTP add-on scales graphql-gateway from zero on inbound HTTP request rate — k8s/base/graphql-gateway.yaml, k8s/keda/gateway-httpscaledobject.yaml (http.keda.sh/v1alpha1, add-on 0.15.0)." },
    { text: "The interceptor's default wait timeout (20s) is shorter than a cold JVM boot, so it's raised to 180s — otherwise a wake-up request 502s with 'context deadline exceeded' before a replica is ready.", lvl: 1 },
    { text: "Asserted: a scaled-to-zero deployment wakes to ≥1 replica in response to an inbound HTTP request through the interceptor, within a 240-second scale-up budget.", lvl: 1 },
    { head: true, text: "Presenter cue · infra tier · fallback" },
    { text: "Opt-in — minikube, same substrate as demo-keda-kafka.sh. Fallback: recorded scale-up timeline showing the replica count climbing off baseline within budget.", color: C.ink },
  ],
  notes: "DEMO 15 of 18. A scaled-to-zero workload reports 'unknown' health until the first request — expected, not a bug, and worth pre-empting the question before someone in the audience asks it." });

/* ====================== 07 · GOVERNANCE, MESH, OBSERVABILITY ====================== */
(() => {
  const s = divider({ num: "07", title: "Governance, mesh, observability", sub: "Standards enforced by the platform — mTLS by default, three correlated signals, and a trust path from contract to runtime." });
  s.addNotes("Federated computational governance: a small set of global rules the platform enforces automatically, at the boundary — not a review board after the fact. This section covers the mesh (selective, not namespace-wide, and why), observability as governance made visible, and the trusted supply chain underneath every data product.");
})();

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "Istio: control plane in, selective injection",
  image: "06-istio-mesh",
  caption: "The Istio control plane installed cluster-wide via Helm (1.29.0); the datamesh namespace is deliberately left UNlabeled for auto-injection — sidecar membership is opted in per Deployment.",
  notes: "scripts/setup-istio.sh installs istio-base + istiod via helm upgrade --install, then gates on kubectl rollout status deployment/istiod actually reaching Available — not just trusting Helm's own --wait. The script's own header explains the selective-injection decision: namespace-wide injection breaks Job pods (the sidecar never exits, the job hangs at 1/2 forever) and collides with CloudNativePG's own Postgres TLS. Inject per-Deployment instead, via the sidecar.istio.io/inject: \"true\" pod annotation — and remember that mutation happens at POD ADMISSION time, not kubectl apply time, so an existing running pod needs a rollout restart to pick it up." });

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "mTLS between meshed services — and what stays outside",
  image: "06-service-mesh",
  caption: "Meshed data-mesh services communicate over automatic mutual TLS between Istio sidecars; Postgres and batch jobs deliberately remain outside the mesh.",
  notes: "IMPORTANT: canary / progressive-delivery traffic-splitting is SUBSTRATE-ONLY in this repo, not a runnable demo. Istio and Kiali are installed cluster-wide; order-service's Deployment carries no sidecar-inject annotation by default (Phase C default is out of the mesh for every app Deployment, to keep the substrate simple); a v2 build of order-service and the DestinationRule/VirtualService pair that would actually split traffic do not exist yet in this tree. The canary mechanism is real and documented conceptually against the real install, but there is no demo-canary.sh and none should be implied." });

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "The LGTM stack: four backends, one Collector",
  image: "08-observability-stack",
  caption: "Loki, Tempo, Mimir, and Grafana — filesystem-backed, single-replica, fed by one shared OpenTelemetry Collector (grafana/otel-lgtm:0.8.1).",
  notes: "DRQ-011: LGTM observability is an ALWAYS-ON baseline in this reactor's compose stack, deliberately not profile-gated (unlike the lgtm-docker-stack skill's own default template) — docker compose up -d with no flag already brings it up. The whole platform's automatic behavior (autoscaling, mesh routing, retries) is only reassuring if you can watch it happen; this is what makes it visible." });

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "Three signals, correlated across a domain",
  image: "08-three-signals",
  caption: "Metrics, traces, and logs — what each answers for a request crossing graphql-gateway, order-service, and inventory-service.",
  notes: "Metrics say something is wrong and roughly when; traces say WHERE across product boundaries; logs say exactly WHAT happened. A request touching three independently-owned products is one user-facing operation spread across three services — understanding it means correlating signals no single product owns in full. That's the argument for needing all three, together, not any one alone." });

contentSlide({ eyebrow: "Governance, mesh, observability", title: "demo-tracing.sh — one request, a real multi-service trace",
  bullets: [
    { text: "POST /orders on order-service calls inventory-service over gRPC (CheckStock) — the same cross-service hop demo-order.sh exercises for Panache." },
    { text: "This demo rides that same request and proves it produces one real, queryable, multi-service trace in Tempo: order-service's REST span is the trace root, with a CheckStock gRPC span plus Postgres spans from BOTH services as children.", lvl: 1 },
    { text: "Proven against the real compose otel-lgtm stack's Tempo backend — DRQ-011's always-on observability baseline means this infra is already up with no profile flag.", lvl: 1 },
    { head: true, text: "Infra tier · fallback" },
    { text: "compose (baseline — LGTM is always on). Fallback: recorded span-tree dump showing root + gRPC child + two Postgres children.", color: C.ink },
  ],
  notes: "DEMO 16 of 18. The one observability demo in this reactor that was run against a real backend and produced a verified cross-service trace — the proof that 'the platform does things automatically' is actually visible, not just asserted." });

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "The trusted supply chain",
  image: "10-trusted-supply-chain",
  caption: "The trust path from a contract defined once, through registration and wire-format verification, to runtime observability.",
  notes: "Closes the loop between the contract work in section 02, the mesh's admission-time enforcement, and the observability this section just built out: a thread of trust runs from 'the schema is registered' through 'the wire format is verified' to 'the running system is observable end to end.'" });

/* ====================== 08 · SECURITY ====================== */
(() => {
  const s = divider({ num: "08", title: "Security", sub: "DRQ-005: quarkus-oidc, attempted live on the smallest module in the reactor." });
  s.addNotes("DRQ-005's own rule: attempt a live demo of OIDC; defer only if the laptop-scale budget can't support it. It could — review-service is the smallest module in the reactor (three plain REST endpoints, Postgres as its only other Dev Services dependency, no cross-service calls), so this is the smallest viable OIDC demo rather than a deferred one.");
})();

contentSlide({ eyebrow: "Security", title: "demo-oidc.sh — live bearer tokens, not a mocked header",
  bullets: [
    { text: "review-service added quarkus-oidc with ZERO quarkus.oidc.* configuration — Dev Services auto-provisions a disposable Keycloak container (realm quarkus, client quarkus-app/secret, two builtin accounts: alice with admin+user roles, bob with only user)." },
    { text: "One endpoint, DELETE /reviews/{id}, is annotated @RolesAllowed(\"admin\"); every other endpoint is untouched.", lvl: 1 },
    { text: "Three real password-grant token requests against the live, randomly-ported Keycloak Dev Service prove three outcomes: no token → 401; Bob's token (valid, no admin role) → 403 — a genuine RBAC check, not just 'has a token'; Alice's token → 204, and a follow-up GET on the same id returns 404.", lvl: 1 },
    { head: true, text: "Presenter cue · infra tier · fallback" },
    { text: "(DRQ-005, feasibility-gated — conditional/skippable if the environment can't run a live Keycloak Dev Service.) Infra: compose. Fallback: conceptual — narrate the three outcomes (401 / 403 / 204-then-404) without a live token exchange.", color: C.ink },
  ],
  notes: "DEMO 17 of 18. Token port discovery uses docker port against the Keycloak Dev Service container id, since Testcontainers binds it to a random host port — the one piece of plumbing most likely to be environment-sensitive, which is exactly why this demo is marked conditional/skippable rather than hard-required." });

/* ====================== 09 · NATIVE ====================== */
(() => {
  const s = divider({ num: "09", title: "Native", sub: "A separate axis from the JVM-only Spring Boot comparison — Quarkus with no JVM in the process at all." });
  s.addNotes("Deliberately kept out of section 05's comparison table so that table compares like with like (JVM to JVM). No native build was run for this project — the commonly cited native figures (sub-100ms startup, tens of MB of RSS) are general Quarkus numbers, not something measured here. Native is covered as an opt-in, long-running demo (demo-native.sh) rather than folded into the Spring Boot numbers.");
})();

contentSlide({ eyebrow: "Native", title: "demo-native.sh — no JVM at all",
  bullets: [
    { text: "Compiles order-service — the smallest clean REST+Panache service in the reactor — to a native executable: first checks for a local GraalVM/Mandrel native-image, falls back to a Docker-based Mandrel builder image, and fails LOUDLY rather than silently building a JVM jar and calling it native if neither toolchain is available." },
    { text: "Runs the produced *-runner binary directly — no java, no quarkus-run.jar — against a real throwaway Postgres container (native mode gets no Dev Services; %prod expects a real, reachable database).", lvl: 1 },
    { text: "Asserts GET /orders returns a real JSON array through the full REST + Hibernate ORM + Panache stack with zero JVM in the process.", lvl: 1 },
    { text: "Deliberately separate from the Spring Boot comparison (section 05): that chapter is JVM-only by design, and this is the only place native compilation appears.", color: C.ink },
    { head: true, text: "Presenter cue · infra tier · fallback" },
    { text: "Opt-in — long-running (several minutes; longer the first time a 1-2 GB builder image has to be pulled). Infra: bare native toolchain + one throwaway Postgres container. Fallback: recorded native-binary boot log + a real GET /orders response.", color: C.ink },
  ],
  notes: "DEMO 18 of 18 — all eighteen demos in the matrix now covered. This is the only demo not wired into walkthrough.sh's default acts, specifically because of its runtime cost." });

/* ====================== 10 · THE WHOLE PICTURE ====================== */
(() => {
  const s = divider({ num: "10", title: "The whole picture", sub: "The reference architecture, assembled — and the four principles' value, realized on Quarkus and Kubernetes." });
  s.addNotes("Synthesis. Return to the reference architecture now that every box has had a demo behind it; show the four value-closer diagrams from the 101 deck's vocabulary, now backed by real code; walk demos/walkthrough.sh as the five-act presenter script; close with honest adoption guidance.");
})();

diagramSlide({ eyebrow: "The whole picture", title: "The reference architecture, assembled",
  image: "08-reference-architecture",
  caption: "Every piece in its place: data products behind the Istio mesh, KEDA-driven autoscaling, and every signal flowing through the Collector into Grafana LGTM and Kiali — the mesh, complete.",
  notes: "Callback to section 00. The audience has now seen a real demo behind nearly every box in this picture — the eighteen demos, the three orchestration engines, the AI+rules showcase, the Spring Boot comparison, the KEDA scalers, the mesh, the tracing. The promise from the start is kept." });

diagramSlide({ eyebrow: "The whole picture", title: "Domain ownership, realized",
  image: "10-value-domain-ownership",
  caption: "Each domain owning its own service, data, and contract boundary end to end, with no central team in the path.",
  notes: "order-service, inventory-service, payment-service, shipping-service, notification-service, review-service — six services, six owners, each a Quarkus module with its own storage, its own API, its own contract. No central team sits in the path of any of them shipping a change." });

diagramSlide({ eyebrow: "The whole picture", title: "Data as a product, realized",
  image: "10-value-data-product",
  caption: "A data product as discoverable, addressable, trustworthy, and self-describing, backed by a versioned Avro contract and the Apicurio Schema Registry.",
  notes: "Every event in this reactor is Avro against Apicurio from day one (DRQ-009) — not a retrofit. demo-kafka.sh proved the wire format byte by byte, not just by configuration review." });

diagramSlide({ eyebrow: "The whole picture", title: "Self-serve platform, realized",
  image: "10-value-self-serve",
  caption: "Domains declaring their infrastructure needs — topics, databases, scaling policies — and the platform's operators fulfilling them automatically.",
  notes: "Strimzi, CloudNativePG, and KEDA are the operators doing the fulfilling; notification-service and graphql-gateway both scale to zero and back without either service's own code knowing anything about autoscaling." });

diagramSlide({ eyebrow: "The whole picture", title: "Federated computational governance, realized",
  image: "10-value-governance",
  caption: "Global rules — contract format, security, observability — enforced automatically at the platform boundary while domains keep independent ownership.",
  notes: "The registry enforces contract compatibility computationally; the mesh enforces mTLS automatically between meshed services; the Collector makes every signal observable without per-service instrumentation effort. None of these required a review board." });

contentSlide({ eyebrow: "The whole picture", title: "demos/walkthrough.sh — the five-act presenter script",
  bullets: [
    { text: "ACT 1 — Data products & protocols (default): order, grpc, graphql, kafka, tracing, websocket, reactive-vertx, oidc." },
    { text: "ACT 2 — Three orchestration styles (DRQ-015, gated): orchestration-styles." },
    { text: "ACT 3 — AI / Camel / Drools / MCP (gated): ai-classify, ai-mcp, camel-integration, ai-triage." },
    { text: "ACT 4 — Developer experience & native: jbang-prototype, continuous-testing (default), native (gated)." },
    { text: "ACT 5 — Platform autoscaling (gated): keda-kafka, keda-http." },
    { head: true, text: "How it runs" },
    { text: "Each demo runs as its own child process via run_act — the orchestrator never double-manages a demo's own compose_up/compose_down. Gated acts are gated PER DEMO, not per act, behind --with-ollama/--with-native/--with-minikube — cleanly SKIPPED, not failed, when a flag is absent. Supports --only/--skip, --no-preflight, --no-pause/--auto, and prints a final pass-fail-skip tally.", color: C.ink },
  ],
  notes: "This is the orchestrator over all eighteen demos just covered. It's the single script a presenter actually runs end to end, with Enter-to-advance pauses for a live audience or --auto for CI/self-test." });

contentSlide({ eyebrow: "The whole picture", title: "Adoption: start small",
  bullets: [
    { text: "You don't adopt a mesh — or this reactor's full stack — all at once. The principles are independent enough to land incrementally." },
    { text: "Start with one domain and one product — order-service's shape (entity, REST resource, one synchronous call out, one event published) is the template to copy first.", lvl: 1 },
    { text: "Add self-serve platform pieces (Kafka, the registry, KEDA) as the second and third products need them, not before.", lvl: 1 },
    { text: "Introduce computational governance once there are products to govern — the registry before the catalog, mTLS before admission policy.", lvl: 1 },
    { head: true, text: "Let the architecture correct against reality" },
    { text: "Each piece in this deck is independently verifiable — stand one up, confirm it with its own demo, then add the next. That's the same incremental discipline this reactor itself was built with, verification status footers and all.", color: C.ink },
  ],
  notes: "Practical close. The honest answer to 'where do I start' is: not all at once, and not by copying the whole appendix on day one. One domain, one product, one demo proving each piece before the next is added." });

(() => {
  const s = pres.addSlide();
  s.addImage({ path: L.ILLUS, x: 0, y: 0, w: PW, h: PH, sizing: { type: "cover", w: PW, h: PH } });
  const rx = PW * 0.42, rw = PW - rx - 0.7;
  s.addText("Eighteen demos, three orchestration engines,", { x: rx, y: 2.5, w: rw, h: 0.9, fontSize: 27, color: "FFFFFF", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("one honest accounting of what works and what doesn't.", { x: rx, y: 3.3, w: rw, h: 1.2, fontSize: 27, color: "FFD9D9", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("Quarkus and Kubernetes are where the four principles find a home.", { x: rx, y: 4.85, w: rw, h: 0.6, fontSize: 14.5, color: "FFFFFF", fontFace: F.body, italic: true, valign: "top", margin: 0 });
  const lw = 1.25, lh = lw / L.LOGO_AR;
  s.addImage({ path: L.LOGO_LIGHT, x: PW - 0.6 - lw, y: PH - 0.3 - lh, w: lw, h: lh });
  L.pageNumOnly(s, { dark: true });
  s.addNotes("Closing slide before the appendix. The one-sentence summary: eighteen real demos, three coordination engines over one domain, and an honest accounting of what works (the MCP server path) and what doesn't yet (in-process tool-calling, DEF-001) rather than a glossed-over success story. Open for questions here if this is the end of the live session — the appendix that follows is reference material, not more narrative.");
})();

/* ====================== 11 · APPENDICES ====================== */
(() => {
  const s = divider({ num: "11", title: "Appendices", sub: "Six optional deep-dives — reference material that goes further than the main narrative on one topic each." });
  s.addNotes("These mirror the six appendix chapters on the site (16-21). They're reference depth, not part of the main arc: scaling the WebSocket push, the gotchas, agentic-development recommendations, testing detail, in-memory vs Kafka messaging, and the three engines compared. Pull up whichever one a question lands on.");
})();

diagramSlide({ eyebrow: "Appendices", title: "A1 — Scaling WebSocket push with Kafka",
  image: "16-websocket-scaling",
  caption: "What the single-instance push does today, and the Kafka fan-out a multi-replica deployment would need — every replica consuming the topic and pushing to its own local sockets.",
  notes: "Honest framing: the repo runs single-instance push today. Across replicas a socket pins to one replica while a shared consumer group splits partitions — backwards for a push that needs every replica to see every event. The fix is a per-replica unique group.id (broadcast) feeding each replica's own local connection registry, with KEDA scale-to-zero made socket-aware. All of that is recommended, not deployed." });

diagramSlide({ eyebrow: "Appendices", title: "A2 — Gotchas",
  image: "17-gotchas",
  caption: "Eight real pitfalls hit building this reactor — timezone, Avro, gRPC ports, integration-test wiring, serde autodetection — each with its symptom and the fix that landed.",
  notes: "Every cell maps to a committed fix: postgres:18's Olson-timezone rejection, Avro 1.12's ClassSecurityValidator, the gRPC 9001/9000 mismatch, @QuarkusIntegrationTest's separate-process timezone, import.sql skipped in %prod, @Consumes 415 on bodyless GET plus RestAssured's false pass, the Avro serde JSON fallback, and the stale-volume reset. Be honest about the last one — a general operating caution, investigated and ruled out as an actual defect, not a build-specific incident." });

diagramSlide({ eyebrow: "Appendices", title: "A3 — Agentic recommendations",
  image: "18-agentic-recommendations",
  caption: "A plan / execute / validate relay — strong model plans and validates, fast model executes — grounded in MCP tooling, with the diff verified independently.",
  notes: "Non-hype guidance: agentic help works for bounded, well-specified changes grounded in real code and MCP tooling (camel-mcp, quarkus-agent); it does not substitute for architecture decisions or for verification. A subagent's report is a claim, not evidence. The full build case study lives in the repo doc _plans/agentic-relay.md." });

diagramSlide({ eyebrow: "Appendices", title: "A4 — Testing, in detail",
  image: "19-testing-pyramid",
  caption: "The test pyramid — unit @QuarkusTest at the base, failsafe integration tests above, functional (Newman) and load (hey/ghz) at the top — and the phases run-all-tests.sh walks.",
  notes: "Unit tests run under surefire with Dev Services auto-provisioning infra; failsafe *IT tests (OrderPlacedAvroWireIT's byte-level Avro assertion, InventoryCheckStockWireIT's self-seed-then-gRPC) self-provision Testcontainers; functional and load sit on top. scripts/run-all-tests.sh walks the whole pyramid, with flags to select tiers. Ollama-gated ITs are skipped unless their flag is set." });

diagramSlide({ eyebrow: "Appendices", title: "A5 — In-memory vs. Kafka messaging",
  image: "20-inmemory-vs-kafka",
  caption: "The same @Incoming/@Outgoing code over two connectors: in-memory Vert.x for fast, deterministic tests, and Kafka for the durable, partitioned production transport.",
  notes: "Only the connector configuration changes between the two — the application code is identical. In-memory is for proving messaging logic in tests without a broker; it is not a production transport. The trade-offs are across latency, durability, coupling, ordering, back-pressure, and testing ergonomics." });

diagramSlide({ eyebrow: "Appendices", title: "A6 — The three engines, compared",
  image: "21-three-engines-compare",
  caption: "Kafka choreography versus two shapes of orchestration (a Camel route, a Quarkus Flow document), compared across who owns the sequence, coupling, failure handling, debuggability, and where the logic lives.",
  notes: "Deeper than section 03's tour. Terminology stays exact: Kafka is choreography (no central coordinator, each participant reacts to events); Camel and Quarkus Flow are both orchestration (a single component sequences the steps). Failure handling in the repo today is idempotency and exception propagation, not saga compensation — stated honestly rather than implied." });

/* ====================== APPENDIX ====================== */
(() => {
  const s = divider({ num: "—", title: "Appendix", sub: "The full demo matrix, the decision ledger, DEF-001 in full, wiring detail, and a home for every diagram." });
  s.addNotes("Reference material, not more narrative. This is where a reader goes after the talk to check a specific demo's infra tier, a specific decision's rationale, or the exact root cause behind DEF-001 — and where diagrams that didn't fit the main story (but still deserve a home) are parked.");
})();

contentSlide({ eyebrow: "Appendix · demo matrix", title: "All 18 demos, by infra tier (1 of 2): bare & compose",
  bullets: [
    { head: true, text: "bare — JVM / Dev Services only, no compose, no cluster" },
    { text: "demo-jbang-prototype.sh — JBang/Camel CLI prototyping, no Maven module." },
    { text: "demo-continuous-testing.sh — quarkus:dev continuous testing + Dev Services." },
    { text: "demo-native.sh (opt-in, native) — GraalVM/Mandrel native build + boot." },
    { head: true, text: "compose — infra baseline (docker compose up -d)" },
    { text: "demo-order.sh · demo-grpc.sh · demo-graphql.sh · demo-kafka.sh · demo-tracing.sh · demo-websocket.sh · demo-reactive-vertx.sh." },
    { text: "demo-oidc.sh (feasibility-gated, DRQ-005 — may be skipped).", color: C.ink },
  ],
  notes: "Mirrors demos/README.md's own matrix exactly. 'bare' needs JDK 25, Maven 3.9.x, jbang on PATH, and GraalVM/Mandrel for native — no docker compose at all. 'compose' needs docker + the Compose v2 plugin, cp .env.example .env, and docker compose up -d from the repo root (postgres, kafka-native, apicurio, otel-lgtm — no profile flag needed)." });

contentSlide({ eyebrow: "Appendix · demo matrix", title: "All 18 demos, by infra tier (2 of 2): ollama, minikube, orchestrator",
  bullets: [
    { head: true, text: "compose + --profile ollama — opt-in, heaviest infra (8g mem budget)" },
    { text: "demo-ai-classify.sh · demo-ai-mcp.sh · demo-camel-integration.sh · demo-ai-triage.sh (showcase, DRQ-012/014)." },
    { head: true, text: "minikube — reuses the step-9 Kubernetes substrate" },
    { text: "demo-keda-kafka.sh (opt-in) · demo-keda-http.sh (opt-in)." },
    { head: true, text: "Orchestrator" },
    { text: "walkthrough.sh — five-act presenter script over all 18 demos; gated per demo via --with-ollama/--with-native/--with-minikube; --only/--skip/--no-preflight/--no-pause/--auto; final pass-fail-skip tally." },
    { text: "Opt-in summary: ollama → classify/mcp/camel-integration/triage; native → demo-native.sh; minikube → keda-kafka/keda-http; feasibility-gated → demo-oidc.sh.", color: C.ink },
  ],
  notes: "Everything NOT in this opt-in summary (bare and compose minus demo-oidc.sh) is the default, always-runnable demo set — the core of a laptop-scale run with no extra flags." });

contentSlide({ eyebrow: "Appendix · DEF-001", title: "DEF-001 — full root cause",
  bullets: [
    { head: true, text: "Symptom" },
    { text: "OrderAssistantRouteIT sends a chat message asking for an order's status and asserts the agent invoked the order-status tool. It fails: the model answers in one round trip, the tool route is never invoked, the tool-executions header is absent." },
    { head: true, text: "Root cause (upstream, not this repo's code)" },
    { text: "camel-quarkus-support-langchain4j's enforceJaxRsHttpClient() unconditionally sets the global system property langchain4j.http.clientBuilderFactory to a Quarkiverse JAX-RS client factory for EVERY dev.langchain4j model on the classpath — no toggle exists. The hand-built OllamaChatModel's own base-url is never honored by the transport that sends the request." },
    { head: true, text: "Ruled out by diagnosis" },
    { text: "Model capability (a direct Ollama /api/chat call WITH a tools array DOES return tool_calls for qwen2.5:3b and qwen2.5:7b-instruct); tool registration/tag matching (tags line up correctly); langchain4j version (reproduces across every combination tried, including the seed-matched classpath)." },
    { text: "Two levers a caller actually has — a hand-built OllamaChatModel with an explicit base-url, and an explicit httpClientBuilder(new JdkHttpClientBuilder()) override — were both tried and neither changed the outcome, because the global system property is set before either bean is constructed.", color: C.ink },
  ],
  notes: "Classpath side is RESOLVED: quarkus-langchain4j-bom:1.7.4 is imported first so the whole dev.langchain4j family converges at 1.11.0 with no manual pin — the behavioral defect is independent of that cleanup. Does not block the build: the IT is named *IT (Surefire skips it), gated behind -Dollama.tests.enabled=true, and failsafe isn't bound in ai-mcp-service, so mvn verify never needs Ollama. Options to revisit: a newer camel-quarkus/quarkus-langchain4j train where the enforcement differs; filing upstream against camel-quarkus-support-langchain4j; continuing to demonstrate tool-calling via the embedded MCP server path instead (which is what this deck does)." });

contentSlide({ eyebrow: "Appendix · decision ledger", title: "DRQ decisions this deck is built on",
  bullets: [
    { text: "DRQ-006 — Spring Boot comparison: ship ONE runnable Spring Boot twin for real side-by-side startup/memory numbers (section 05), not a hand-waved comparison." },
    { text: "DRQ-009 — Event serialization: ALL Kafka events use Avro + Apicurio from the start, never JSON, so there is no later retrofit (section 02)." },
    { text: "DRQ-012 — AI+rules showcase ACCEPTED: Ollama classifies, Drools decides, deliberately sidestepping DEF-001 (no in-process tool-calling round trip required). Engine decision: plain embedded Drools (drools-core/drools-compiler, a KieContainer in a CDI bean) — explicitly NOT the Kogito/KIE Quarkus extension; KIE is not a roadmap item." },
    { text: "DRQ-014 — Quarkus Flow ACCEPTED as the second orchestration shape: the CNCF Open/Serverless Workflow spec, low-dependency, native-friendly, and crucially does NOT pull in Kogito/KIE/Drools." },
    { text: "DRQ-015 — \"Three engines, different orchestration styles\" is a REQUIRED narrative (docs + deck), with exact terminology discipline: Kafka is choreography; Camel and Quarkus Flow are both orchestration.", color: C.ink },
  ],
  notes: "These five decisions are the backbone of sections 02–05 of this deck. Full text lives in _plans/decisions.md; this slide is the condensed, presenter-facing version." });

contentSlide({ eyebrow: "Appendix · wiring detail", title: "Avro / Apicurio wiring, in detail",
  bullets: [
    { text: "AvroKafkaSerializer is pinned EXPLICITLY in application.properties on the producer side, on BOTH the Quarkus order-service and the Spring Boot twin — autodetection was proven unreliable with two Avro serdes on the classpath, in both frameworks, for different underlying reasons." },
    { text: "DEF-002 — RESOLVED: OrderPlacedAvroWireIT (Testcontainers Kafka apache/kafka-native:4.2.0 + Apicurio apicurio-registry:3.1.7) produces a real OrderPlaced with AvroKafkaSerializer, consumes with a vanilla byte-level KafkaConsumer, and asserts value[0]==0x00 (Avro magic byte) AND value[0]!=0x7B (not JSON) plus a schema id — proven to fail loudly if the serde regresses to JSON.", lvl: 1 },
    { text: "Runs in the default mvn verify (self-provisioning; no compose needed), failsafe-bound in order-service.", lvl: 1 },
    { text: "Avro 1.12.x's ClassSecurityValidator required org.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1 on the IT's failsafe execution — plain JUnit has no Quarkus bootstrap to auto-trust the package.", color: C.ink },
  ],
  notes: "This is the wire-compat crux behind demo-kafka.sh's byte-level assertion in section 02 — the same magic-byte check the demo does live, first proven in an automated integration test." });

contentSlide({ eyebrow: "Appendix · wiring detail", title: "KEDA HTTP add-on — the 0.15.0 pin, in detail",
  bullets: [
    { text: "KEDA core pinned to 2.19.0; the HTTP add-on pinned to 0.15.0 — both installed via helm upgrade --install in scripts/setup-keda.sh." },
    { text: "Why 0.15.0 specifically: v0.14.0 shipped a panic (upstream issue #1668) that 0.15.0 fixes; 0.15.0 also adds HTTP/2 and gRPC support.", lvl: 1 },
    { text: "interceptor.replicas.waitTimeout is raised to 180s from the add-on's 20s default — the default is shorter than a cold JVM boot (image pull + Quarkus startup + startupProbe), so without the override a wake-up request 502s with 'context deadline exceeded' before a replica is ready, starving KEDA of the pending-request pressure it needs to activate promptly.", lvl: 1 },
    { text: "The Kafka-lag scaler targets notification-service; the HTTP scaler targets graphql-gateway — never order-service, which carries the (substrate-only) canary.", color: C.ink },
  ],
  notes: "This slide is the detail behind section 06's two KEDA demos — the exact version pins and the one non-default override that makes the HTTP add-on viable against a JVM workload's real cold-start time." });

contentSlide({ eyebrow: "Appendix · infra", title: "compose.yaml services and .env image tags",
  bullets: [
    { head: true, text: "Baseline services (no --profile flag needed)" },
    { text: "postgres (postgres:18, TZ=UTC/PGTZ=UTC) · kafka (apache/kafka-native:4.2.0, KRaft mode, PLAINTEXT + INTERNAL listeners) · apicurio (apicurio-registry:3.1.7) · lgtm (grafana/otel-lgtm:0.8.1, always-on per DRQ-011)." },
    { head: true, text: "Opt-in profiles" },
    { text: "--profile tools → kafka-ui (provectuslabs/kafka-ui) · --profile ollama → ollama (ollama/ollama)." },
    { head: true, text: "The wire-compat crux" },
    { text: "Every image tag in .env MUST equal the exact tag Quarkus 3.39.5 Dev Services pulls by default, confirmed by inspecting the build-time config classes inside the cached deployment jars — so behavior never drifts between quarkus:dev/mvn verify (Dev Services) and this standalone compose stack.", color: C.ink },
    { text: "postgres:18 rejects legacy Olson timezone ids (e.g. US/Eastern) forwarded from a non-UTC host — TZ=UTC/PGTZ=UTC on the container, plus -Duser.timezone=UTC on every JVM, is what keeps mvn verify green on any host.", color: C.ink },
  ],
  notes: "This is the exact standing-infra picture behind every 'compose' tier demo in this deck. docker compose up -d from the repo root, after cp .env.example .env, is the one command that brings up the whole baseline." });

contentSlide({ eyebrow: "Appendix · determinism", title: "ai-rules-service: how determinism was established",
  bullets: [
    { text: "ai-rules-service's pom.xml was missing the quarkus-maven-plugin <build> binding its sibling modules have — without it, mvn quarkus:dev silently no-ops and mvn package produces only a thin jar, not a runnable quarkus-run.jar. Fixed for ai-rules-service specifically (the same gap exists, unfixed, in ai-mcp-service, notification-service, and payment-service)." },
    { text: "This module has no health/actuator endpoint, so the shared demo harness's wait_http (which needs a 2xx/3xx) can't be used — the demo waits for ANY HTTP response (connection-refused → connected) as its readiness signal instead.", lvl: 1 },
    { text: "The three demo-ai-triage.sh inputs were chosen by sampling the live qwen2.5:3b classification repeatedly against the exact TriageService prompt, until riskSignal/amount combinations classified STABLY (not just plausibly) across trials.", lvl: 1 },
    { text: "Because Drools' decision is a deterministic function of the classified fields (not of the LLM's prose), a stable classification guarantees a stable decision — so the demo asserts the EXACT expected decision on every call, stronger than the module's own opt-in integration tests, which only assert membership.", color: C.ink },
  ],
  notes: "Re-running the demo twice in a row against the live model reproduced the same three decisions on both endpoints both times — the empirical basis for trusting the strict assertion in section 04's showcase demo." });

contentSlide({ eyebrow: "Appendix · glossary", title: "Glossary (1 of 2)",
  bullets: [
    { text: "Choreography — every participant reacts to events on its own terms; no central process knows the whole sequence." },
    { text: "Orchestration — a single process explicitly sequences the steps; this reactor shows two shapes (imperative Camel route, declarative Quarkus Flow document)." },
    { text: "Data product / architectural quantum — the smallest independently deployable unit carrying everything it needs: input/output ports, transformation, metadata, and a governance control port." },
    { text: "Panache — Hibernate ORM's active-record style; the entity is its own repository (static finders, instance persist())." },
    { text: "Avro / Apicurio Registry — Avro is the binary, schema-based runtime event format; Apicurio is the registry that stores and enforces compatibility on it." },
    { text: "Dev Services — Quarkus's automatic Testcontainers provisioning for dev/test, with zero manual docker compose." },
    { text: "KEDA / HPA — KEDA drives a standard HorizontalPodAutoscaler from external signals (Kafka lag, HTTP rate) and adds the zero-to-one activation the HPA alone cannot do." },
  ],
  notes: "First half of the glossary, grouped by the sections that introduce each term: orchestration styles (03), data products and Panache (01/02), and self-serve platform (06)." });

contentSlide({ eyebrow: "Appendix · glossary", title: "Glossary (2 of 2)",
  bullets: [
    { text: "Istio / sidecar / mTLS — the service mesh; a sidecar is the Envoy proxy injected beside an app container; mTLS is the mutual-certificate encryption the mesh establishes automatically between sidecars." },
    { text: "OTLP / OpenTelemetry — the wire protocol and SDK standard for exporting metrics and traces to a collector." },
    { text: "MCP (Model Context Protocol) — a wire protocol (Streamable HTTP, JSON-RPC 2.0) for an external client to discover and call tools exposed by a server; structurally separate from in-process LLM agent tool-calling." },
    { text: "langchain4j — the Java LLM-integration library this reactor uses for both single-shot chat (classify) and agent tool-calling (the DEF-001 path)." },
    { text: "Drools / KieSession / KieBase — the embedded rules engine; a KieBase is the compiled rule set (built once, reused); a KieSession is per-request working memory (minted and disposed each call)." },
    { text: "CNCF Serverless Workflow — the open workflow specification Quarkus Flow implements; a workflow document declares tasks and their dependencies rather than imperative call order." },
    { text: "OIDC — OpenID Connect; bearer-token authentication, demonstrated here against a live Dev-Services-provisioned Keycloak." },
    { text: "UBI (Universal Base Image) — Red Hat's freely redistributable, enterprise-maintained container base image used for every multi-stage build in this reactor." },
  ],
  notes: "Second half of the glossary, covering the mesh/observability vocabulary (07), the AI/rules vocabulary (04), and the base-image convention referenced throughout the infra appendix slides." });

twoUpDiagramSlide({ eyebrow: "Appendix · parked diagrams", title: "From pipelines to warehouses: the earlier architectures",
  images: ["01-data-pipeline-architecture", "01-data-warehouse-architecture"],
  captions: ["A linear ETL/ELT pipeline moving data from an operational source through transformation to an analytical destination.", "Multiple operational sources feeding a centralized, schema-on-write warehouse owned by a central team."],
  note: "101-deck context diagrams, parked here so every diagram has a home — not referenced in the 201 main narrative.",
  notes: "These two diagrams set up the architectural history the 101 deck argues against. They aren't needed again here because this deck assumes that argument is already won and goes straight to building the mesh — but they're parked here rather than discarded, since every one of the 36 shipped diagrams should have a home somewhere in this deck." });

twoUpDiagramSlide({ eyebrow: "Appendix · parked diagrams", title: "The data lake, and the shift to decentralization",
  images: ["01-data-lake-architecture", "01-data-mesh-decentralized"],
  captions: ["A data lake organized into raw, curated, and refined zones, accepting structured, semi-structured, and unstructured data.", "Multiple domain teams each owning a data product, connected by a shared self-serve platform instead of a central team."],
  note: "101-deck context diagrams, parked here so every diagram has a home — not referenced in the 201 main narrative.",
  notes: "The data lake diagram is the third centralized architecture the 101 deck walks through before introducing the mesh; the decentralized diagram is the conceptual target this entire 201 deck then builds, piece by piece, in Quarkus." });

twoUpDiagramSlide({ eyebrow: "Appendix · parked diagrams", title: "The monolith-to-mesh refactor, and its timeline",
  images: ["01-monolith-to-mesh", "01-architecture-evolution"],
  captions: ["A monolithic application and its monolithic data platform both decomposing into domain-owned services and domain-owned data products.", "The progression from pipelines to warehouses to lakes to mesh, with the problem each pattern solved."],
  note: "101-deck context diagrams, parked here so every diagram has a home — not referenced in the 201 main narrative.",
  notes: "The monolith-to-mesh analogy (the same refactor microservices applied to applications, applied to data) does a lot of work in the 101 deck; the evolution timeline is the one-slide history of why each prior architecture eventually hit a wall. Both are assumed knowledge by the time this 201 deck starts." });

twoUpDiagramSlide({ eyebrow: "Appendix · parked diagrams", title: "Operational vs. analytical, and the full minikube capstone",
  images: ["01-operational-vs-analytical", "02-capstone-data-mesh"],
  captions: ["Operational and analytical data shown first as separate layers joined by pipelines, then reorganized so each domain owns both planes.", "The complete data mesh reference architecture running on minikube — domain services, the service mesh, and the self-serve platform tier underneath."],
  note: "101-deck context diagram (left) and the Python sibling repo's capstone (right) — parked here; this deck's own capstone is section 10's reference-architecture diagram.",
  notes: "02-capstone-data-mesh is the Python sibling repository's own minikube capstone illustration; it's visually similar to but not identical to this repo's 08-reference-architecture (section 10's closer), so it's parked here rather than presented as this deck's own capstone." });

diagramSlide({ eyebrow: "Appendix · parked diagrams", title: "How analytical data is composed (conceptual)",
  image: "05-analytical-data-composition",
  caption: "Operational data refined through events and entities into a published data product that analytics consumes — conceptual in this reactor, not built.",
  notes: "The last of the 36 shipped diagrams. Paired conceptually with section 02's ingestion-streaming-sourcing diagram — together they sketch the analytical half of 'data as a product' that this reactor documents but does not implement, since the built demos here are all operational-domain services." });

/* ============================ WRITE ============================ */
pres.writeFile({ fileName: "Datamesh-201-Quarkus-r1.0.pptx" }).then((f) => console.log("WROTE", f));
