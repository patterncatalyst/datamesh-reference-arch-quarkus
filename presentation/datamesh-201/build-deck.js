// Build the Datamesh 201 deep-dive deck — Quarkus + Kubernetes (r1.1).
// Mirrors the structure of the sibling Python "Data Mesh on OpenShift" deck:
// section dividers, diagram-forward content, code slides where code is the
// lesson, one slide per demo, speaker notes on every slide, large appendix.
const L = require("./deck-lib.js");
const { pres, C, F, PW, PH, titleSlide, agendaSlide, divider, contentSlide, diagramSlide, codeSlide, tableSlide, glossarySlide } = L;
const code = (s) => s.replace(/\t/g, "  ");

pres.title = "Building a Datamesh using Quarkus and Kubernetes";

// ---- local helper: two diagrams side by side (for background figures in the
// appendix without giving each one a full-width slide) ----
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

// ---- local helper: diagram on the left (~55%), bold-lead bullets on the right ----
function diagramBulletsSlide({ eyebrow, title, image, bullets, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, eyebrow, title);
  const d = L.DIMS[image];
  const maxW = (PW - 1.4) * 0.55, maxH = 4.5;
  let w = maxW, h = w * (d.h / d.w);
  if (h > maxH) { h = maxH; w = h * (d.w / d.h); }
  s.addImage({ path: L.IMG(image), x: 0.7, y: 1.95 + (maxH - h) / 2, w, h });
  const bx = 0.7 + maxW + 0.4;
  L.addBullets(s, bullets, { x: bx, y: 1.95, w: PW - 0.7 - bx, h: 4.6, fontSize: 14 });
  L.footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

/* ============================ TITLE ============================ */
titleSlide({
  eyebrow: "Data Mesh · 201",
  title: "Building a Datamesh using Quarkus and Kubernetes",
  subtitle: "From the four principles to a running platform on Quarkus and Kubernetes: a capability tour, three orchestration engines, AI and rules triage, and live demos. No prior Quarkus experience required.",
  breadcrumb: "Data Mesh · 201 · r1.1",
  notes: "Welcome to the 201 deep-dive. The 101 deck makes the conceptual case for data mesh; this deck covers the running system: a Quarkus and Kubernetes reference architecture built on the shipping and order domain, with nineteen demo scripts behind it. No prior Quarkus experience is assumed. Each capability is introduced as it comes up, so the deck works as a Quarkus introduction as well as a data-mesh deep dive for anyone who has seen the 101. Expectations: a long walk, diagram-forward, with code where the code is the lesson. It states what works, what is opt-in, and the one capability documented as broken (in-process LLM tool calling).",
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
    { text: "Appendix: reference material", italic: true },
  ],
  notes: "Twelve numbered sections (00 to 11) plus a reference appendix. The thread is the four data-mesh principles from the 101 deck, and every section is tied to Quarkus code and a runnable demo script. The three-engines section is the main addition over the Python sibling: three coordination engines over one domain. The AI and rules section is the second: LLM classification feeding a deterministic rules engine, with the known limitation stated. The Quarkus section covers twelve capabilities, including the JDK 25 AOT cache and the Panama foreign function API. The appendix holds the full demo matrix, a glossary, and the background diagrams.",
});

/* ====================== 00 · FROM PRINCIPLES TO PLATFORM ====================== */
(() => {
  const s = divider({ num: "00", title: "From principles to platform", sub: "The four principles, the reference architecture we build toward, and how the pieces map onto Quarkus and Kubernetes." });
  s.addNotes("Orientation with three diagrams: the four principles recapped, the reference architecture the deck assembles piece by piece, and the map from principles to Kubernetes primitives. Keep it brisk. The principles already appeared in the 101 deck; this section re-anchors before the Quarkus detail.");
})();

diagramSlide({ eyebrow: "From principles to platform", title: "Four principles, recapped",
  image: "01-data-mesh-four-principles",
  caption: "Domain ownership, data as a product, self-serve data platform, federated computational governance: interlocking, not sequential.",
  notes: "Taken from the 101 deck so the two decks connect. The principles interlock rather than stack. Data as a product without a self-serve platform means every domain builds its own Kafka. Governance without domain ownership rebuilds the central bottleneck under a new name. Everything that follows shows where Quarkus and Kubernetes put each of the four." });

diagramSlide({ eyebrow: "From principles to platform", title: "The reference architecture we build toward",
  image: "08-reference-architecture",
  caption: "Data products behind the Istio mesh, KEDA-driven autoscaling, and every signal flowing through the OpenTelemetry Collector into Grafana LGTM and Kiali.",
  notes: "This diagram returns in assembled form near the end. For now: data products in the middle, the selectively meshed Istio data plane around them, KEDA watching two of them from outside the mesh, and the Collector fanning metrics, traces, and logs into one observability stack. By the end of the deck, each box here has a demo or a verified manifest behind it." });

diagramSlide({ eyebrow: "From principles to platform", title: "From principles to Kubernetes and Quarkus pieces",
  image: "02-principles-to-pieces",
  caption: "Each principle maps to Kubernetes building blocks: namespaces, Deployments and CRDs, operators, and mesh and admission policy.",
  notes: "This picture is the deck's structure. Domain ownership maps to namespace boundaries; data as a product maps to a Deployment, Service, and contract per domain; the self-serve platform maps to operators (Strimzi, CloudNativePG, KEDA); federated governance maps to the mesh and admission policy. Each later section builds out one column of this picture with Quarkus code and a demo." });

/* ====================== 01 · QUARKUS CAPABILITY TOUR ====================== */
(() => {
  const s = divider({ num: "01", title: "Quarkus capability tour", sub: "Twelve capabilities, each backed by running code in this project." });
  s.addNotes("Twelve capabilities: Panache, gRPC, GraphQL, Reactive Messaging, WebSockets.Next, Vert.x with Uni and imperative handlers, continuous testing with Dev Services, native image, the JDK AOT cache, OIDC, JBang, and Panama FFM. Read the section as a map; no capability depends on another running first. Reactive Messaging and plain bean orchestration are the two the later sections build on: the choreography leg republishes the OrderEventProducer shown here, and the orchestration legs call the same bean methods.");
})();

diagramSlide({ eyebrow: "Quarkus capability tour", title: "Twelve capabilities demonstrated",
  image: "11-capability-tour",
  caption: "Each capability is anchored to one service, script, or directory in this project.",
  notes: "Walk the map once. inventory-service carries the most capabilities: Panache, gRPC, REST, and the Uni versus imperative handlers, because it is the smallest aggregate with the richest protocol surface. order-service carries Panache, Reactive Messaging, continuous testing, and the native image because it is the cleanest REST and Panache service. review-service carries OIDC because it is the smallest module: one protected endpoint, no cross-service calls. notification-service carries WebSockets.Next. JBang, the AOT cache comparison, and Panama FFM are tied to scripts and directories rather than services, and need no other service running." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "Panache and REST: the template data product",
  subtitle: "One entity, one resource, one gRPC call, one event",
  demoRef: "demos/demo-order.sh",
  image: "03-data-product-anatomy",
  caption: "order-service follows this shape: a Panache entity as its own repository, REST ports in and out, a gRPC call out, an event published on commit.",
  notes: "DEMO 1 of 19. What it does: POST /orders calls inventory-service's CheckStock over gRPC to validate stock, persists the Order through Hibernate ORM Panache, then publishes order.placed to Kafka (best-effort here; demo-kafka.sh proves the Avro wire format). What to show: place an order, GET it back by id, then query Postgres directly to confirm the row. That gives three independent confirmations. Infra: compose (docker compose up -d; postgres, kafka, apicurio baseline). Fallback: a recorded transcript of the 201, 200, and 404 status codes and the row dump." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "Panache: active record or repository",
  image: "11-panache-patterns",
  caption: "Same Hibernate ORM and SQL under both patterns; they differ in layering and in how much code they need.",
  notes: "Panache offers two styles. Active record (used in this project): the entity extends PanacheEntityBase, and Order.findById(id) and order.persist() are the data-access layer. Repository: a PanacheRepository<Order> bean is injected into the resource, which makes mocking and layering easier at the cost of an extra class per aggregate. Both produce the same Hibernate ORM calls and SQL. Active record means less code; the repository suits teams that want strict layering. The Spring Boot twin uses a Spring Data JPA repository, which is the repository equivalent. The repository example on this diagram is illustrative; only active record runs in this project." });

codeSlide({ eyebrow: "Quarkus capability tour", title: "Panache active record in order-service",
  lang: "Java · Hibernate ORM Panache",
  note: "Order.findById(id) and order.persist() are the whole data-access layer; OrderResource calls Order directly.",
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
  notes: "The trade-off: the entity depends on a Panache base class, and active record does not suit every team's layering preference. For a reference architecture with one aggregate per service it removes a layer of indirection. inventory-service's StockResource calls Stock.findBySku(...) the same way, directly from a JAX-RS resource method. No OrderRepository interface, no mapper, and no injected DAO sit between the REST layer and the row." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "gRPC typed contracts",
  subtitle: "Generated at build time",
  demoRef: "demos/demo-grpc.sh",
  image: "05-api-implementations",
  caption: "REST at the edge, gRPC between services, GraphQL to compose, events to decouple: each protocol's Quarkus extension and contract type.",
  notes: "DEMO 2 of 19. What it does: inventory-service answers capstone.inventory.v1.InventoryService/CheckStock over gRPC. The InventoryService base is generated at build time from the inventory.proto contract, not hand-written. @GrpcService registers the bean; @Blocking tells Vert.x the handler does blocking Panache work and must run on a worker thread, even though its signature is the reactive Uni<CheckStockResponse>. What to show: call it with grpcurl against the .proto, a gRPC client over HTTP/2, so the protocol that ran is unambiguous. Infra: compose. Fallback: a recorded grpcurl JSON response showing available and quantityOnHand." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "GraphQL: one query, two protocols",
  subtitle: "REST and gRPC resolved behind one endpoint",
  demoRef: "demos/demo-graphql.sh",
  bullets: [
    { lead: "graphql-gateway's", text: "GatewayApi serves one /graphql endpoint: order(id) resolves over REST from order-service; the nested stock field resolves over gRPC from inventory-service." },
    { text: "MicroProfile GraphQL's @Source marks stock as a field resolver. It runs only when a query selects that field, so order(id) { customerId } never triggers the gRPC call.", lvl: 1 },
    { text: "One request, two backend protocols, one response shape. The choice is made per query, not per endpoint.", lvl: 1 },
  ],
  notes: "DEMO 3 of 19. What it does: order(id) resolves over REST from order-service; the nested stock field resolves lazily over gRPC from inventory-service; both land in one /graphql response. The domain services did not change to support GraphQL; they keep their REST and gRPC interfaces and the gateway composes. This is gateway orchestration of reads, not subgraph federation, which is the right size for five services. What to show: place an order, query the gateway, and assert both the REST-sourced order fields and the gRPC-sourced stock fields appear in one .data.order payload with no .errors. Infra: compose (docker compose up -d). Fallback: recorded .data.order JSON with both sets of fields." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "Uni and imperative handlers",
  image: "11-uni-vs-imperative",
  caption: "The method signature and @Blocking or @NonBlocking choose the thread; the same JVM runs both.",
  notes: "A Uni<T> is Mutiny's lazy single-value asynchronous result: nothing runs until something subscribes, and operators such as onItem().transform() and onFailure().retry() compose it. An imperative method (StockDto get(sku)) runs on a worker thread, where blocking is fine. A method returning Uni runs on the Vert.x event loop, where blocking is forbidden; @Blocking moves it to a worker, and @RunOnVirtualThread is the third option. Quarkus picks the thread from the signature and the annotations, so one service can mix both styles over the same Panache entity. The next demo exercises exactly this with concurrent gRPC and REST calls." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "Reactive and imperative on one reactor",
  subtitle: "Two execution models in the same JVM",
  demoRef: "demos/demo-reactive-vertx.sh",
  bullets: [
    { lead: "inventory-service", text: "answers the same stock table through two execution models at once, on one Vert.x reactor in one JVM." },
    { text: "Reactive: the gRPC CheckStock handler returns Uni<CheckStockResponse>, with its blocking Panache lookup offloaded by @Blocking.", lvl: 1 },
    { text: "Imperative: StockResource is a thread-per-request JAX-RS method with no Uni.", lvl: 1 },
    { text: "The two compute different things: gRPC available depends on the requested quantity; REST available is a static snapshot (quantityOnHand > 0).", lvl: 1 },
  ],
  notes: "DEMO 4 of 19. What it does: tests the claim that Quarkus unifies reactive and imperative code on one Vert.x reactor, under concurrent load. The framework, not the developer, chooses the thread pool for each request from @Blocking and the handler's return type. No migration is needed and no second event loop is started for the imperative side. What to show: three gRPC and three REST calls fired concurrently at one running process; every response correct and uncorrelated. The gRPC rule is quantity > 0 and onHand >= quantity; the REST rule is quantityOnHand > 0. Infra: compose. Fallback: recorded six-call transcript, all six correct. 'Reactor' here means the Vert.x event loop." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "WebSockets.Next vs. Jakarta WebSockets",
  image: "11-websockets-next",
  caption: "Annotated endpoints with an injectable OpenConnections, on Vert.x, against the callback-style Jakarta WebSocket extension.",
  notes: "Left: the legacy quarkus-websockets extension implements Jakarta WebSocket on Undertow, with @ServerEndpoint, a Session, and a callback API. Right: quarkus-websockets-next on Vert.x, with @WebSocket(path), @OnOpen and @OnTextMessage methods that return values or Uni and Multi, an execution model inferred from the signature, an injectable OpenConnections registry, and @WebSocketClient for outbound sockets. Bottom band: this project's push path. A Kafka @Incoming consumer calls OpenConnections.listAll() and sendText to every open socket, and each replica has its own consumer group so every replica sees every event." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "WebSocket push from Kafka",
  subtitle: "Clients receive only committed events",
  demoRef: "demos/demo-websocket.sh",
  bullets: [
    { lead: "notification-service's", text: "/ws/notifications endpoint (WebSockets.Next) is thin: it only acknowledges a connection." },
    { text: "The push comes from the Reactive Messaging consumer for order.placed, right after it persists a Notification row.", lvl: 1 },
    { text: "The push happens after the transaction commits, so a client never sees an event that might still roll back.", lvl: 1 },
  ],
  notes: "DEMO 5 of 19. What it does: WebSockets.Next and Reactive Messaging compose. A Kafka consumer pushes to every open socket right after it commits, with no polling. OpenConnections is the injectable registry of live connections; listAll().forEach(...).sendTextAndAwait(...) does the fan-out. What to show: a JDK java.net.http.WebSocket client run through JBang, connected before an order is placed, asserts that the second message it receives matches the order's orderId, customerId, and itemSku. Infra: compose. Fallback: recorded socket transcript." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "JBang as environment tooling",
  image: "11-jbang-tooling",
  caption: "One .java file with //DEPS and //JAVA directives; JBang resolves dependencies, finds or downloads a JDK, and caches the build.",
  notes: "JBang runs a single Java source file with inline dependency directives: //DEPS for Maven coordinates and //JAVA 25 for the JDK. It resolves from Maven Central, downloads a JDK if none matches, and caches the compiled result. Tools install the same way from pinned Maven coordinates, for example the Camel CLI from org.apache.camel:camel-launcher:4.22.1. The project avoids catalog aliases such as camel@apache/camel, which fetch unpinned scripts from GitHub and prompt the user to trust the source. This project uses it for HelloRoute.java (a Camel route), WsNotificationClient.java (the WebSocket test client), and PanamaFfm.java (the Panama demo). It matters for the demos because they need no Maven module." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "Prototyping with JBang",
  subtitle: "A Camel route without a Maven module",
  demoRef: "demos/demo-jbang-prototype.sh",
  bullets: [
    { lead: "demos/jbang/HelloRoute.java", text: "is a complete Camel route with no pom.xml and no Maven module." },
    { lead: "jbang demos/jbang/HelloRoute.java", text: "resolves pinned Camel 4.22.1 dependencies from Maven Central and runs the route directly.", lvl: 1 },
    { text: "Use it to try a route shape, an EIP combination, or a component configuration before committing to a module.", lvl: 1 },
  ],
  notes: "DEMO 6 of 19. What it does: the lightest demo in the set; no Maven and no containers, only JBang resolving pinned Camel 4.22.1 dependencies from Maven Central. The route file is local and nothing is fetched from GitHub, so JBang never asks for trust. What to show: the exact transformed marker string (JBANG_PROTOTYPE_OK: ...) in the route's log output, not only a zero exit code. Infra: bare (JDK 25 and jbang on PATH; no docker compose). Fallback: the recorded log line." });

contentSlide({ eyebrow: "Quarkus capability tour", title: "Continuous testing",
  subtitle: "Tests rerun on every save, against Dev Services",
  demoRef: "demos/demo-continuous-testing.sh",
  bullets: [
    { lead: "mvn quarkus:dev", text: "with quarkus.test.continuous-testing=enabled reruns a module's tests on every save." },
    { lead: "Dev Services", text: "starts the Testcontainers those tests need (Postgres, Kafka, Apicurio) with no docker compose and no .env.", lvl: 1 },
    { text: "The demo parses the Quarkus 3.39.5 pass banner in order-service's dev log and asserts passing == run. A missing banner fails the demo.", lvl: 1 },
  ],
  notes: "DEMO 7 of 19. What it does: continuous testing and native compilation sit at opposite ends of the feedback-loop spectrum: instant, infra-provisioned reruns on one end and a multi-minute ahead-of-time compile on the other. Dev Services applies only to the former. A demo that cannot observe its target capability should fail rather than claim less than it set out to, so a missing banner fails this one. What to show: the banner line 'All 4 tests are passing (0 skipped), 4 tests were run in 8318ms.' Infra: bare (JDK 25 and Maven only; Dev Services starts its own containers). Fallback: the recorded banner line." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "Three ways to start a Java service",
  image: "11-startup-paths",
  caption: "Plain JVM, JVM with the JDK 25 AOT cache, and native image: what each costs to build and what each gives at startup.",
  notes: "Three startup paths. Plain JVM: load, link, interpret, then JIT warm-up. JVM with the AOT cache (JDK 25, Project Leyden, JEPs 483, 514, and 515): a training run with -XX:AOTCacheOutput writes app.aot, and production runs with -XX:AOTCache; it is the same jar on a full JVM with the JIT still active. Native image (GraalVM or Mandrel): a closed-world build that takes minutes and needs reflection configuration, and it produces an executable with no JVM. The diagram is qualitative; measured numbers for the JVM and AOT paths appear in the Spring Boot comparison, and native is exercised by its own demo." });

diagramSlide({ eyebrow: "Quarkus capability tour", title: "Panama: native calls without JNI",
  image: "11-panama-ffm",
  caption: "Java resolves a libc symbol, builds a downcall handle from a FunctionDescriptor, and passes off-heap memory owned by an Arena.",
  notes: "The Foreign Function and Memory API (Project Panama, final in JDK 22) calls native libraries from Java without JNI. Linker.nativeLinker() gives the platform linker, defaultLookup() resolves symbols from libc, and downcallHandle(FunctionDescriptor) produces a MethodHandle. An Arena allocates off-heap MemorySegments, such as a C string, and frees them when it closes. JNI needs C glue, generated headers, and a separate native build; FFM needs none of those. JDK 25 warns unless --enable-native-access is set, which the demo passes. The default lookup covers libc on Linux and macOS." });

codeSlide({ eyebrow: "Quarkus capability tour", title: "Panama FFM in practice",
  subtitle: "getpid() and strlen() from libc",
  demoRef: "demos/demo-panama.sh",
  lang: "Java · demos/jbang/PanamaFfm.java",
  note: "Output: PANAMA_GETPID equals the JVM pid; PANAMA_STRLEN equals the UTF-8 byte length.",
  code: code(`Linker linker = Linker.nativeLinker();
SymbolLookup libc = linker.defaultLookup();

// int getpid(void)
MethodHandle getpid = linker.downcallHandle(
    libc.find("getpid").orElseThrow(),
    FunctionDescriptor.of(JAVA_INT));

// size_t strlen(const char *s)
MethodHandle strlen = linker.downcallHandle(
    libc.find("strlen").orElseThrow(),
    FunctionDescriptor.of(JAVA_LONG, ADDRESS));

try (Arena arena = Arena.ofConfined()) {
    MemorySegment cString = arena.allocateFrom(text);
    long nativeLen = (long) strlen.invokeExact(cString);
}`),
  notes: "DEMO 8 of 19. What it does: a JBang script (JDK 25, no Maven module) calls getpid() and strlen() in libc through the FFM API and checks both results against Java's own values. What to show: the two output lines, PANAMA_GETPID=<n> JVM_PID=<n> and PANAMA_STRLEN=<n> JAVA_LENGTH=<n>, with each pair equal. Recorded run (JDK 25.0.3, jbang 0.138.0): PANAMA_GETPID=867684 JVM_PID=867684 and PANAMA_STRLEN=31 JAVA_LENGTH=31. The test string is 'data mesh on Quarkus — héllo'; strlen counts UTF-8 bytes, so the Java side compares against the UTF-8 byte length, not the character count. Infra: bare (JDK 25 and jbang). Fallback: the recorded output above." });

/* ====================== 02 · DATA AS A PRODUCT ====================== */
(() => {
  const s = divider({ num: "02", title: "Data as a product", sub: "Contracts, the registry, and the catalog: a data product held to the standard of any software product." });
  s.addNotes("This section covers the data-as-a-product principle. Two kinds of contract: a runtime contract (Avro, on the hot path) and a discovery contract (OpenAPI, Protobuf, SDL, which are descriptive). Conflating the two is the most common confusion in this area. The governing decision in this project: every Kafka event uses Avro through Apicurio from the start, with no JSON shortcut.");
})();

diagramSlide({ eyebrow: "Data as a product", title: "Where analytical sourcing would plug in",
  image: "05-ingestion-streaming-sourcing",
  caption: "Ingestion, streaming, and CDC sourcing for analytical consumers. Conceptual in this project; not built.",
  notes: "This diagram is conceptual. The project does not ship an analytical-sourcing layer or Debezium-style CDC. It is included because a complete data-as-a-product picture has an analytical half as well as an operational one." });

diagramSlide({ eyebrow: "Data as a product", title: "Avro on the wire",
  subtitle: "Verified at the byte level",
  demoRef: "demos/demo-kafka.sh",
  image: "04-contract-flow",
  caption: "The runtime path (serialize, publish, fetch schema, deserialize) and the discovery path (OpenAPI, Protobuf, SDL, and Avro contracts for a catalog to ingest).",
  notes: "DEMO 9 of 19. What it does: every Kafka event uses Avro against the Apicurio Schema Registry from the start. order-service pins AvroKafkaSerializer in application.properties because Quarkus's connector-serializer autodetection silently fell back to a Jackson JSON serializer here; two Avro serdes on the classpath make the choice ambiguous. What to show: place an order, read the raw bytes back from the compose Kafka broker with a byte-level consumer, and assert the Apicurio and Confluent wire-format magic byte (0x00) is the first byte. A JSON payload would start with 0x7B. Infra: compose. Fallback: a recorded byte dump showing 0x00 and the schema id. The same check runs automatically in OrderPlacedAvroWireIT." });

diagramSlide({ eyebrow: "Data as a product", title: "Runtime vs. discovery contracts",
  image: "04-contracts-registry-catalog",
  caption: "Runtime contracts (Avro, filled) and discovery contracts (OpenAPI, Protobuf, SDL, hollow) are registered in Apicurio; a catalog downstream would ingest them into a lineage graph.",
  notes: "A runtime contract (Avro) is required to publish: the event does not serialize without it, so the registry can reject a breaking change at publish time. That is computational governance in action. A discovery contract (OpenAPI, GraphQL SDL, Protobuf) is descriptive. It is the source of truth for people and CI, but nothing fails at runtime if it goes stale. This project registers both kinds in Apicurio. A catalog such as OpenMetadata that ingests them into lineage is the next step and is not built." });

codeSlide({ eyebrow: "Data as a product", title: "The runtime contract: a registered Avro schema",
  lang: "Avro · Apicurio Schema Registry",
  note: "Illustrative of the contracts module's shape (capstone.order.v1.OrderPlaced). The producer pins AvroKafkaSerializer in application.properties.",
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
  notes: "The contract is the lesson here. order-service's OrderEventProducer builds this record and calls emitter.send(...). The consumer side, notification-service's OrderPlacedConsumer, mirrors it: @Incoming('order-placed') on a @Transactional method, with no Kafka client code on either side. Details behind the pin: autodetection proved unreliable with two Avro serdes on the classpath, in both Quarkus and the Spring Boot twin. OrderPlacedAvroWireIT (Testcontainers Kafka and Apicurio) produces an OrderPlaced with AvroKafkaSerializer, consumes it with a byte-level KafkaConsumer, and asserts value[0] == 0x00 and value[0] != 0x7B. Avro 1.12's ClassSecurityValidator needs org.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1 on that test's failsafe execution; the order-service README records both." });

diagramSlide({ eyebrow: "Data as a product", title: "The full contract picture",
  image: "04-capstone-contracts",
  caption: "Every protocol's contract type feeds Apicurio Registry; a catalog downstream builds lineage from the registry and the running data stores.",
  notes: "Every protocol in the project has a contract: OpenAPI for REST, Protobuf for gRPC, SDL for GraphQL, and Avro for Kafka. All of them register in Apicurio. A mesh depends on consumers finding and trusting products without a central team. Without a usable registry and catalog they fall back to asking someone, and the bottleneck returns." });

/* ====================== 03 · THE THREE ENGINES ====================== */
(() => {
  const s = divider({ num: "03", title: "The three engines", sub: "Three ways to coordinate the same order-to-shipment domain: choreography, and two shapes of orchestration." });
  s.addNotes("The main addition over the Python sibling. Every event-driven system answers one question: when several steps happen in sequence, who decides the sequence? This project runs three answers side by side. Terminology: Kafka is choreography. Camel and Quarkus Flow are both orchestration; they differ in how the sequence is expressed (an imperative route or a declarative workflow document), not in whether a coordinator exists. Keep 'orchestration' from collapsing into one technology.");
})();

diagramSlide({ eyebrow: "The three engines", title: "Three coordination shapes, one domain",
  image: "13-orchestration-styles",
  caption: "Decentralized Kafka choreography; a Camel route that sequences steps; a declarative Quarkus Flow workflow expressing the same two tasks.",
  notes: "Trace the three boxes. The choreography box has no coordinator node, because none exists. The two orchestration boxes each have one entry point and one owner of the sequence, drawn differently: the Camel box is a straight line of named steps (a route is a sequence of method calls), and the Quarkus Flow box is a small graph of declared tasks (a workflow document says what must happen before what and leaves the how to the engine). Code that calls things in order versus data that declares an order is the more useful distinction than orchestration versus choreography." });

contentSlide({ eyebrow: "The three engines", title: "Engine 1: Kafka choreography",
  subtitle: "No single service owns the sequence",
  bullets: [
    { lead: "order-service", text: "publishes order.placed and does not know payment-service or shipping-service exist. It does not call them or wait on them." },
    { lead: "payment-service", text: "subscribes to order.placed, captures payment, and publishes payment.captured. shipping-service subscribes to that and publishes shipment.dispatched.", lvl: 1 },
    { lead: "notification-service", text: "also subscribes to order.placed, as a parallel reaction to the same event rather than a step after the chain.", lvl: 1 },
    { head: true, text: "Trade-off" },
    { text: "No single place describes what happens when an order is placed; you find every subscriber. Adding a fifth reaction, such as analytics, changes no existing service.", color: C.ink },
  ],
  notes: "No service holds a reference to the whole sequence. Each follows one rule: when I see event X, I do Y and emit Z (notification-service only does Y). This is the baseline the next two engines contrast against. The coupling is loose, through topics, and failure handling relies on idempotent redelivery. The cost is discoverability: reading one service tells you nothing about the end-to-end flow, so tracing and a catalog matter more here than in the orchestrated styles." });

codeSlide({ eyebrow: "The three engines", title: "Engine 2: Camel orchestration",
  subtitle: "The route is the coordinator",
  lang: "Java · Camel route · POST /api/orders/triage",
  note: "One route sequences every step; reading it top to bottom is reading the business process.",
  code: code(`from("direct:triage")
    .routeId("triage-order")
    .unmarshal().json(JsonLibrary.Jackson, OrderCreate.class)
    .bean(triageService, "classify")
    .bean(triageService, "decide")
    .marshal().json(JsonLibrary.Jackson);`),
  notes: "ai-rules-service exposes this at POST /api/orders/triage. Orchestration means one process sequences the steps and knows the whole flow; nothing about the sequence is implicit or visible only at runtime. classify (Ollama) and decide (Drools) are bean methods. The route coordinates but does not make the business decision." });

codeSlide({ eyebrow: "The three engines", title: "Engine 3: Quarkus Flow",
  subtitle: "The same two steps, declared",
  lang: "Java · Quarkus Flow (CNCF Serverless Workflow) · POST /api/orders/triage-flow",
  note: "A declarative coordinator: a workflow definition shaped like a CNCF Serverless Workflow document, not imperative route code.",
  code: code(`return FlowWorkflowBuilder.workflow("order-triage")
    .tasks(
        FlowDSL.function("classify", triageService::classify),
        FlowDSL.function("decide", triageService::decide))
    .build();`),
  notes: "This engine separates two ideas that are often conflated: that a coordinator exists, and that the coordinator is a hand-written imperative function. Quarkus Flow declares the coordinator as data. classify and decide are the same TriageService methods Engine 2 calls: same logic, different coordination shape. Drools still makes the decision in both paths." });

tableSlide({ eyebrow: "The three engines", title: "When to reach for which",
  headers: ["Engine", "Reach for it when"],
  rows: [
    ["Choreography", "Reactions are independent and the set of subscribers is growing or unknown."],
    ["Camel orchestration", "The process needs full imperative control: branching, EIPs, code review as the artifact."],
    ["Quarkus Flow", "The same fixed process is better reviewed, versioned, or edited as a document than as a Java release."],
  ],
  note: "All three paths reach the same TriageService.classify and decide methods; Drools makes the business decision.",
  notes: "A decision guide for the three engines. No engine is strictly better; the point is to match the coordination shape to how the process is owned, reviewed, and changed over time." });

contentSlide({ eyebrow: "The three engines", title: "All three engines, back to back",
  subtitle: "Choreography, Camel, and Quarkus Flow on one domain",
  demoRef: "demos/demo-orchestration-styles.sh",
  bullets: [
    { lead: "Act 1 — choreography:", text: "places one order, polls each downstream topic with a byte-level consumer, and asserts the Avro magic byte on every hop." },
    { lead: "Act 2 — Camel:", text: "posts to /triage and asserts the strict decision ROUTE_TO_WAREHOUSE for a pre-validated, stable low-risk input." },
    { lead: "Act 3 — Quarkus Flow:", text: "posts the same input to /triage-flow and asserts the same decision, showing both shapes drive the same logic." },
    { lead: "Known limit:", text: "the acts share a domain and a comparison, not one order flowing through all three.", color: C.ink },
  ],
  notes: "DEMO 10 of 19. What it does: runs all three coordination engines back to back over one domain. Act 1 also checks a direct Postgres row and a REST lookup. What to show: the Avro magic byte on every Act 1 hop, and matching strict decisions in Acts 2 and 3. Infra: compose baseline for Act 1 (five services); Acts 2 and 3 need the compose ollama profile, opt-in through --with-ollama. Fallback: the recorded narration transcript of all three acts. This is the showcase demo for the three-engines story. The known limit: Act 1's order never went through the classifier-stability trial that Acts 2 and 3 require, and the script header says so; do not claim more continuity than the demo does." });

/* ====================== 04 · AI + RULES TRIAGE ====================== */
(() => {
  const s = divider({ num: "04", title: "AI + rules triage", sub: "An LLM extracts structured fields; a deterministic Drools rule set makes the business decision." });
  s.addNotes("The division of labor: the LLM classifies and Drools decides. An LLM reads a loosely structured order description and extracts a few categorical fields reliably. It is a poor choice for a decision that must be audited, replayed deterministically, or explained to a compliance reviewer. This section also carries a known limitation: in-process multi-turn tool calling is broken in a different service, for a documented upstream reason.");
})();

diagramSlide({ eyebrow: "AI + rules triage", title: "Ollama classifies, Drools decides",
  image: "14-ai-rules-triage",
  caption: "classify (Ollama qwen2.5:3b) produces category, priority, and riskSignal; decide (a Drools KieSession firing order-triage.drl) returns FRAUD_HOLD, EXPEDITE, or ROUTE_TO_WAREHOUSE. A separate branch shows where in-process tool calling breaks and where the MCP server path works.",
  notes: "Two halves. Top: one LLM call feeding one deterministic rule engine, reached by two orchestration shapes that end in the same TriageService methods. Bottom: the same local model in a different capability, multi-turn tool calling in ai-mcp-service, where one path is broken for a documented upstream reason and a structurally separate path works. A successful LLM call in one part of the project is no evidence that a different kind of LLM call succeeds elsewhere." });

contentSlide({ eyebrow: "AI + rules triage", title: "Single-shot classification",
  subtitle: "One LLM call, outside the tool-calling limitation",
  demoRef: "demos/demo-ai-classify.sh",
  bullets: [
    { lead: "ai-mcp-service's", text: "OrderClassifierRoute exposes POST /api/orders/classify, a single-shot langchain4j chat call (CHAT_SINGLE_MESSAGE_WITH_PROMPT). It is not an agent and does not call tools." },
    { text: "The tool-calling limitation lives in a separate path (OrderLookupToolRoute and OrderAssistantRoute) that this demo never touches.", lvl: 1 },
    { text: "It needed its own fix: a misnamed prompt-template header and the default operation mode made the model chat about the order instead of classifying it.", lvl: 1 },
  ],
  notes: "DEMO 11 of 19. What it does: a single-shot langchain4j chat call that classifies an order. The fix was to correct a misnamed prompt-template header and set the single-message operation explicitly. What to show: the classify endpoint returns one of the defined category labels. Infra: compose plus the ollama profile. Fallback: a recorded category-label response. Single-shot classification is a reliable shape as long as the output is parsed defensively. It is a different thing from multi-turn tool calling, which is where the known limitation lives." });

contentSlide({ eyebrow: "AI + rules triage", title: "The AI and rules showcase",
  subtitle: "The same decision from both orchestration paths",
  demoRef: "demos/demo-ai-triage.sh",
  bullets: [
    { lead: "POST /api/orders/triage", text: "(Camel) and /triage-flow (Quarkus Flow) run the same pipeline: Ollama classifies, a Drools KieSession fires order-triage.drl and decides." },
    { text: "Three salience-guarded rules: FRAUD_HOLD (HIGH risk signal), EXPEDITE (amount ≥ 1000 with LOW risk), ROUTE_TO_WAREHOUSE (default). The model never makes the business call.", lvl: 1 },
    { text: "Three inputs, sampled against the live model until their classification was stable, assert the exact expected decision on both endpoints.", lvl: 1 },
  ],
  notes: "DEMO 12 of 19. What it does: runs the same classify-then-decide pipeline through both orchestration shapes and asserts the exact expected decision on three pre-validated inputs. Both endpoints return the same decision for the same input, which shows the two shapes drive the same logic and are not two separately tuned copies. What to show: the three-decision table across both endpoints. Infra: compose plus the ollama profile (host Ollama with qwen2.5:3b pulled, or the compose ollama profile). Fallback: the recorded three-decision table. This is the primary AI demo. It avoids the tool-calling limitation by design: Drools, not langchain4j tool calling, makes the decision, so no in-process agent round trip is needed." });

contentSlide({ eyebrow: "AI + rules triage", title: "Camel EIP routing, tested in isolation",
  subtitle: "Content-based router verified independently of tool calling",
  demoRef: "demos/demo-camel-integration.sh",
  bullets: [
    { lead: "OrderLookupToolRoute", text: "is a Content-Based Router EIP (.choice(), three .when(), .otherwise()) that inspects an orderId and returns one of four static response bodies." },
    { text: "The demo reaches it through the same MCP server surface as demo-ai-mcp.sh and asserts all four branches, including the .otherwise() fallback for an unknown id.", lvl: 1 },
    { text: "The routing logic is correct regardless of whether in-process tool calling works.", color: C.ink },
  ],
  notes: "DEMO 13 of 19. What it does: a Camel and EIP-focused demo that isolates two questions the project answers separately: does the route logic work, and does AI tool calling work. What to show: all four branches, including the fallback. Infra: compose plus the ollama profile. Fallback: the recorded four-branch transcript (ORD-001, ORD-002, ORD-003, and the unrecognized-id fallback)." });

contentSlide({ eyebrow: "AI + rules triage", title: "Tool calling through the MCP server",
  subtitle: "The working path alongside a known limitation",
  demoRef: "demos/demo-ai-mcp.sh",
  bullets: [
    { lead: "Known limitation:", text: "in-process langchain4j agent tool calling does not fire on this stack. The cause is a transport-wiring defect in camel-quarkus-support-langchain4j, not model capability." },
    { lead: "The demo", text: "never calls POST /api/assistant/chat and prints a banner before running anything.", lvl: 1 },
    { lead: "What works:", text: "the embedded Camel MCP server, a separate code path with no langchain4j agent. It speaks MCP Streamable HTTP and JSON-RPC 2.0: initialize, tools/list, tools/call(order-status) for ORD-001, 002, 003.", lvl: 1 },
  ],
  notes: "DEMO 14 of 19. What it does: demonstrates the working MCP-server tool-calling path and refuses to call the broken in-process agent path. What to show: the MCP JSON-RPC handshake, the tool list, and three deterministic lookups. Infra: compose plus the ollama profile. Fallback: the recorded MCP JSON-RPC transcript. Diagnosis: a transport-wiring defect in camel-quarkus-support-langchain4j, not model capability (a direct Ollama /api/chat call with a tools array returns tool_calls) and not tool registration (the tags match). It is an open upstream deferral; the appendix has the root cause. A demo that states the limitation with a banner and avoids the broken endpoint is more useful than omitting it." });

/* ====================== 05 · QUARKUS VS. SPRING BOOT ====================== */
(() => {
  const s = divider({ num: "05", title: "Quarkus vs. Spring Boot", sub: "The same order-service data product, rebuilt as a Spring Boot twin and measured side by side on the JVM, with and without the AOT cache." });
  s.addNotes("The one section that steps outside Quarkus. A runnable Spring Boot 4.0.8 twin on the same JDK 25, with a matched dependency surface (REST, JPA as the Panache equivalent, Kafka and Avro, gRPC client), so the numbers reflect the framework and not a difference in scope. No demo-springboot.sh exists. The comparison is run by scripts/compare-quarkus-springboot.sh, with an --aot mode for the JDK 25 AOT cache.");
})();

diagramSlide({ eyebrow: "Quarkus vs. Spring Boot", title: "Same workload, same JVM, two startup paths",
  image: "12-quarkus-vs-spring-boot",
  caption: "order-service (Quarkus, build-time processing) and spring-boot-compare (Spring Boot 4.0.8, classpath scanning and reflection at startup) boot against the same throwaway postgres:18 container under identical JVM flags, each measured by its own started-log line.",
  notes: "The twin reuses the project's framework-agnostic jars unmodified: the same domain-model DTOs and the same generated Avro OrderPlaced class. There is no schema or DTO drift between the two. The one code difference is the persistence idiom: Panache active record in Quarkus and a derived Spring Data JPA repository in Spring Boot. Everything else the two services do is identical." });

tableSlide({ eyebrow: "Quarkus vs. Spring Boot", title: "The numbers on the plain JVM",
  headers: ["Metric", "Quarkus order-service", "Spring Boot twin"],
  rows: [
    ["Startup (self-reported)", "2.045 s", "4.018 s"],
    ["Resident memory (RSS)", "337 MB", "548 MB"],
    ["Native image", "separate axis", "n/a"],
    ["Persistence idiom", "Panache active record", "Spring Data JPA"],
  ],
  note: "Quarkus starts in about half the time and uses about 60% of the memory of the Spring Boot service on the same REST, JPA, Kafka/Avro, and gRPC surface.",
  notes: "One run (Temurin 25.0.3, 2026-10-05; the JVM columns of the AOT comparison that follows) with both services under their packaged profile. Scope: JVM to JVM, with no native image on either side (native is a separate axis, covered in its own section). Treat the numbers as indicative: a single run on one developer machine through scripts/compare-quarkus-springboot.sh (measured, single run, indicative), with no averaging across runs, so absolute numbers will differ. The measurement boots the real wiring: the gRPC channel and the Kafka producer both initialize. Each framework's own self-reported 'boot complete' log line is the signal, because the script points KAFKA_BOOTSTRAP_SERVERS at a dead port for both services, so a health-based wait would time out on both. A cell the script cannot measure prints the placeholder <measured-on-run> in place of a number. The next slide adds the JDK 25 AOT cache to both services and brings startup to parity. Reach for Quarkus's footprint where it is paid repeatedly: scale to zero, dense multi-tenant deployments, serverless. Spring Boot's ecosystem and team familiarity are real advantages." });

tableSlide({ eyebrow: "Quarkus vs. Spring Boot", title: "With the JDK 25 AOT cache on both",
  demoRef: "scripts/compare-quarkus-springboot.sh --aot",
  headers: ["Metric", "Quarkus JVM", "Spring Boot JVM", "Quarkus + AOT", "Spring Boot + AOT"],
  rows: [
    ["Startup (self-reported)", "2.045 s", "4.018 s", "0.992 s", "1.021 s"],
    ["Startup (wall clock)", "2.22 s", "4.45 s", "1.21 s", "1.21 s"],
    ["Resident memory (RSS)", "337 MB", "548 MB", "372 MB", "446 MB"],
    ["AOT cache size", "n/a", "n/a", "103 MB", "123 MB"],
  ],
  note: "Single run on Temurin JDK 25.0.3, same JDK flags on both frameworks. Indicative, not a benchmark.",
  notes: "What it shows: the same order-service and Spring Boot twin, run once on the plain JVM and once with a JDK 25 AOT cache (Project Leyden). A training run with -XX:AOTCacheOutput writes the cache when the application exits; the measured run uses -XX:AOTCache with -XX:AOTMode=on, which fails loudly if the cache is unusable instead of silently falling back. Spring Boot runs from its extracted layout because nested jars cannot be cached. Reading the table: startup on both frameworks drops to about one second, so the AOT cache narrows the gap to parity. Quarkus's memory rises (337 to 372 MB) while Spring Boot's falls (548 to 446 MB); the cache is memory-mapped and counts toward RSS, and the cache files are 103 MB and 123 MB. Quarkus is still faster and smaller on the plain JVM. Caveats: single run on Temurin 25.0.3 on 2026-10-05, same JDK and classpath required for the cache, indicative only. Both services were measured with identical flags; Quarkus's own AOT integration was not used, to keep the comparison symmetric." });

diagramSlide({ eyebrow: "Quarkus vs. Spring Boot", title: "How the AOT cache is trained and used",
  subtitle: "Same jar, same JDK: a training run, then a production run",
  demoRef: "scripts/compare-quarkus-springboot.sh --aot",
  image: "11-aot-cache-build",
  caption: "The training run writes the cache at exit; the production run maps it and fails fast if it is stale.",
  notes: "How the AOT comparison numbers were produced. mvn package builds quarkus-run.jar as usual; there is no special packaging. The training run starts that jar with -XX:AOTCacheOutput, waits for the started log line, and sends SIGTERM, because the JVM writes the cache when it exits. The cache holds classes already loaded and linked (JEP 483) and method profiles (JEP 515); JEP 514 is what makes this a single training step. For order-service it is 103 MB. The production run starts the same jar on the same JDK with -XX:AOTCache and -XX:AOTMode=on; without AOTMode=on, a stale or mismatched cache is silently ignored and the measurement would be wrong. Startup went from 2.045 s to 0.992 s, with the full JVM and JIT still active. Spring Boot gets the same treatment from its extracted layout, because classes inside nested jars cannot be cached. Single run on Temurin 25.0.3, 2026-10-05." });

/* ====================== 06 · PLATFORM: SELF-SERVE, ELASTIC, RESILIENT ====================== */
(() => {
  const s = divider({ num: "06", title: "Platform: self-serve, elastic, resilient", sub: "KEDA scales two data products to demand, and to zero: the self-serve platform in action." });
  s.addNotes("A domain that needs elastic scaling asks for a ScaledObject; it does not operate the Kubernetes autoscaler internals. KEDA is the mechanism. It drives an HPA instead of replacing it, and it covers the one thing the HPA cannot do alone: the zero-to-one transition.");
})();

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "The three planes of the platform",
  image: "02-platform-planes",
  caption: "External clients, the service-mesh plane running the domain services, and the self-serve platform plane underneath, with protocols labeled on every flow.",
  notes: "A domain interacts with the higher planes by declaration, not by touching infrastructure. The plane names matter less than the layering: the planes below are what the next two sections build out with Kubernetes components." });

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "The stock HPA vs. KEDA's two-tier model",
  image: "07-hpa-vs-keda",
  caption: "The stock Kubernetes HPA scales on CPU and memory; KEDA drives an HPA from external signals (Kafka lag, HTTP rate) and handles the zero-to-one activation the HPA cannot do alone.",
  notes: "A KEDA ScaledObject is consumed by the KEDA operator, which creates and manages a standard HorizontalPodAutoscaler, fed by an external.metrics.k8s.io server that KEDA runs. From one replica upward, the ordinary HPA control loop scales on a Kafka-lag or HTTP-rate metric instead of CPU. The HPA cannot do minReplicas: 0, so KEDA's own operator polls the trigger source and makes the 0-to-1 jump itself." });

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "Elastic products: scale on lag, even to zero",
  image: "07-keda-lag",
  caption: "The KEDA Kafka-lag scaler polls consumer-group lag on order.placed and scales notification-service from zero to N replicas once lag crosses the threshold, then back to zero after the cooldown.",
  notes: "Why not CPU: a consumer idling at 0% CPU with a 10,000-message backlog should scale up, and CPU cannot see that; lag can. scripts/setup-keda.sh installs KEDA core 2.19.0 through Helm. Scale to zero means an elastic data product costs nothing while idle." });

contentSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "Scaling on Kafka lag",
  subtitle: "Zero to N replicas and back on Kubernetes",
  demoRef: "demos/demo-keda-kafka.sh",
  bullets: [
    { lead: "KEDA core", text: "scales notification-service from zero to N on Kafka consumer-group lag, using the manifests k8s/base/notification-service.yaml and k8s/keda/consumer-scaledobject.yaml." },
    { text: "Asserted: the replica count climbs from zero on a lag burst and returns to zero as the backlog drains.", lvl: 1 },
  ],
  notes: "DEMO 15 of 19. What it does: scales notification-service from zero on Kafka consumer-group lag, on the local Kubernetes cluster that scripts/bootstrap.sh builds. What to show: the replica count climbing from zero on a lag burst and returning to zero as the backlog drains. Infra: opt-in local Kubernetes cluster; it needs the platform bootstrapped (Istio, KEDA, Strimzi, CloudNativePG) with the kubectl context pointed at it, and runs through walkthrough.sh with --with-minikube. Fallback: a recorded replica-count timeline (0, N, 0). This demo is verified on the cluster. It is outside the core compose-based demo set because it exercises the Kubernetes platform and not docker compose." });

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "The KEDA HTTP add-on, as a system",
  image: "07-keda-http-addon",
  caption: "The interceptor proxy buffers requests to graphql-gateway and reports request rate to the external scaler, which drives the HTTPScaledObject's zero-to-N activation.",
  notes: "The HTTP add-on is a small system, not one component: an interceptor proxy sits in front of the scaled Deployment, buffers requests while the Deployment is at zero, and reports rate to an external scaler. It is pinned to 0.15.0 because v0.14.0 shipped a panic (upstream issue #1668) that 0.15.0 fixes, and 0.15.0 adds HTTP/2 and gRPC support. The interceptor's default wait timeout of 20 s is shorter than a cold JVM boot, so interceptor.replicas.waitTimeout is raised to 180 s; without that, a wake-up request returns 502 with 'context deadline exceeded' before a replica is ready. The k8s/keda README records both details." });

diagramSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "Elastic reads: scaling on request volume",
  image: "07-keda-http",
  caption: "demo-keda-http.sh drives a request burst through the interceptor with the Host header set and polls graphql-gateway's replica count until it climbs off baseline within the 240-second budget.",
  notes: "HTTP scaling goes on graphql-gateway and not on order-service: order-service carries the canary, and HTTP-scaling a service whose traffic is split by weight would put two mechanisms in conflict over the same pods. Fit the mechanism to the workload. The Kafka-lag scaler targets notification-service and the HTTP scaler targets graphql-gateway." });

contentSlide({ eyebrow: "Platform: self-serve, elastic, resilient", title: "Scale to zero on HTTP",
  subtitle: "The KEDA HTTP add-on wakes graphql-gateway on demand",
  demoRef: "demos/demo-keda-http.sh",
  bullets: [
    { lead: "KEDA HTTP add-on", text: "scales graphql-gateway from zero on inbound request rate: k8s/base/graphql-gateway.yaml and k8s/keda/gateway-httpscaledobject.yaml (http.keda.sh/v1alpha1, add-on 0.15.0)." },
    { text: "The interceptor's wait timeout is raised from 20 s to 180 s to cover a cold JVM boot.", lvl: 1 },
    { text: "Asserted: a scaled-to-zero deployment reaches at least one replica within a 240-second budget.", lvl: 1 },
  ],
  notes: "DEMO 16 of 19. What it does: scales graphql-gateway from zero on inbound HTTP request rate through the KEDA HTTP add-on's interceptor. What to show: a scaled-to-zero deployment reaching at least one replica within budget. Infra: opt-in local Kubernetes cluster, the same platform as demo-keda-kafka.sh. Fallback: a recorded scale-up timeline. Status: verified 2026-10-06; graphql-gateway scaled 0 to 1 and all 120 GraphQL requests through the interceptor returned 200, single run. A scaled-to-zero workload reports 'unknown' health until the first request; that is expected, and worth answering before someone asks." });

/* ====================== 07 · GOVERNANCE, MESH, OBSERVABILITY ====================== */
(() => {
  const s = divider({ num: "07", title: "Governance, mesh, observability", sub: "Standards enforced by the platform: mTLS by default, three correlated signals, and a trust path from contract to runtime." });
  s.addNotes("Federated computational governance: a small set of global rules that the platform enforces automatically at the boundary, not a review board after the fact. This section covers the mesh (selective, not namespace-wide, and why), observability as governance made visible, and the trusted supply chain under every data product.");
})();

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "Istio: control plane in, selective injection",
  image: "06-istio-mesh",
  caption: "The Istio control plane is installed cluster-wide through Helm (1.29.0). The datamesh namespace is left unlabeled for auto-injection; sidecar membership is opted in per Deployment.",
  notes: "scripts/setup-istio.sh installs istio-base and istiod with helm upgrade --install, then waits for kubectl rollout status deployment/istiod to reach Available instead of trusting Helm's --wait. Injection is selective: namespace-wide injection breaks Job pods (the sidecar never exits, so the job hangs at 1/2) and collides with CloudNativePG's own Postgres TLS. Each Deployment opts in through the sidecar.istio.io/inject: \"true\" label on its pod template. Mutation happens at pod admission, not at kubectl apply, so a running pod needs a rollout restart to pick it up." });

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "mTLS between meshed services, and what stays outside",
  image: "06-service-mesh",
  caption: "Meshed data-mesh services communicate over automatic mutual TLS between Istio sidecars; Postgres and batch jobs stay outside the mesh.",
  notes: "Progressive delivery manifests exist and are verified. The k8s/istio directory holds order-service-v2.yaml and the DestinationRule and VirtualService pair that split traffic by weight between v1 and v2 of order-service, and the split was checked on the cluster. There is no demo-canary.sh; the canary is a manifest-level capability and not a scripted demo. Istio and Kiali install cluster-wide. Application Deployments are outside the mesh unless they opt in: order-service, notification-service, and graphql-gateway opt in through the k8s/istio patches, and inventory-service stays out. Postgres and batch jobs stay outside for the reasons on the Istio slide." });

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "The LGTM stack: four backends, one Collector",
  image: "08-observability-stack",
  caption: "Loki, Tempo, Mimir, and Grafana, filesystem-backed and single-replica, fed by one shared OpenTelemetry Collector (grafana/otel-lgtm:0.8.1).",
  notes: "LGTM is part of the always-on compose baseline and is not profile-gated, unlike the lgtm-docker-stack skill's default template: docker compose up -d with no flag brings it up. Automatic platform behavior (autoscaling, mesh routing, retries) is only reassuring if you can watch it happen, and this stack makes it visible." });

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "Three signals, correlated across a domain",
  image: "08-three-signals",
  caption: "Metrics, traces, and logs: what each answers for a request crossing graphql-gateway, order-service, and inventory-service.",
  notes: "Metrics show that something is wrong and roughly when. Traces show where, across product boundaries. Logs show exactly what happened. A request that touches three independently owned products is one user-facing operation spread over three services, and understanding it means correlating signals that no single product owns in full. That is the argument for needing all three." });

contentSlide({ eyebrow: "Governance, mesh, observability", title: "One request, one distributed trace",
  subtitle: "REST, gRPC, and Postgres spans in Tempo",
  demoRef: "demos/demo-tracing.sh",
  bullets: [
    { lead: "POST /orders", text: "on order-service calls inventory-service over gRPC (CheckStock), the same hop demo-order.sh exercises for Panache." },
    { text: "The demo checks that this request yields one multi-service trace in Tempo: order-service's REST span is the root, with a CheckStock gRPC span and Postgres spans from both services as children.", lvl: 1 },
    { text: "It runs against the compose otel-lgtm stack, which is always on, so no profile flag is needed.", lvl: 1 },
  ],
  notes: "DEMO 17 of 19. What it does: follows the order-to-inventory gRPC hop and checks that it produces one queryable, multi-service trace in Tempo. What to show: the span tree, with the root span, the gRPC child, and two Postgres children. Infra: compose baseline (LGTM is always on). Fallback: a recorded span-tree dump with the same shape. It is the one observability demo that has been run against a real backend and produced a verified cross-service trace, which shows that the platform's automatic behavior is visible." });

diagramSlide({ eyebrow: "Governance, mesh, observability", title: "The trusted supply chain",
  image: "10-trusted-supply-chain",
  caption: "The trust path from a contract defined once, through registration and wire-format verification, to runtime observability.",
  notes: "This closes the loop between the contract work in the data-as-a-product section, the mesh's admission-time enforcement, and the observability just covered. Trust runs from 'the schema is registered' through 'the wire format is verified' to 'the running system is observable end to end'." });

/* ====================== 08 · SECURITY ====================== */
(() => {
  const s = divider({ num: "08", title: "Security", sub: "quarkus-oidc, run live against Keycloak on the smallest module in this project." });
  s.addNotes("The rule for this section was to attempt a live OIDC demo and defer only if the single-machine budget could not support it. It could. review-service is the smallest module (three REST endpoints, Postgres as the only other Dev Services dependency, no cross-service calls), which makes this the smallest viable OIDC demo.");
})();

diagramSlide({ eyebrow: "Security", title: "How OIDC protects review-service",
  image: "11-oidc-token-flow",
  caption: "Dev Services starts Keycloak; the client obtains a JWT and calls DELETE /reviews/{id}; quarkus-oidc verifies it and @RolesAllowed(\"admin\") decides.",
  notes: "Dev Services starts Keycloak with realm quarkus (alice has admin and user roles; bob has user only) and sets auth-server-url, so review-service needs no quarkus.oidc configuration. Flow: the client POSTs to the token endpoint (password grant, client quarkus-app), receives a JWT access token, and calls DELETE /reviews/{id} with an Authorization: Bearer header. quarkus-oidc verifies the signature against Keycloak's JWKS, the issuer, and expiry, and then @RolesAllowed(\"admin\") applies. Outcomes: no token gives 401, bob gives 403, alice gives 204 and a follow-up GET gives 404. The password grant is for the demo only; browser applications use the authorization code flow." });

contentSlide({ eyebrow: "Security", title: "OIDC with live bearer tokens",
  subtitle: "401, 403, and 204 against a Dev Services Keycloak",
  demoRef: "demos/demo-oidc.sh",
  bullets: [
    { lead: "review-service", text: "added quarkus-oidc with no quarkus.oidc.* configuration. Dev Services starts a disposable Keycloak: realm quarkus, client quarkus-app, accounts alice (admin, user) and bob (user)." },
    { lead: "DELETE /reviews/{id}", text: "is the only endpoint annotated @RolesAllowed(\"admin\"); the others are untouched.", lvl: 1 },
    { text: "Three password-grant token requests show the outcomes: no token gives 401; Bob's valid token without the admin role gives 403; Alice's token gives 204, and a follow-up GET returns 404.", lvl: 1 },
  ],
  notes: "DEMO 18 of 19. What it does: a bearer-token exchange against a Dev Services Keycloak, with three outcomes (401, 403, 204 then 404) in place of a mocked header. The 403 for Bob is an RBAC check: the token is valid and the role is missing. What to show: the three token requests and their responses. Infra: compose; feasibility-gated, so the demo may be skipped when the environment cannot run a live Keycloak Dev Service. Fallback: narrate the three outcomes without a live token exchange. The token port is found with docker port against the Keycloak Dev Service container, because Testcontainers binds a random host port; that is the plumbing most sensitive to the environment, which is why the demo is marked skippable." });

/* ====================== 09 · NATIVE ====================== */
(() => {
  const s = divider({ num: "09", title: "Native", sub: "A separate axis from the JVM comparison: Quarkus with no JVM in the process." });
  s.addNotes("Native stays out of the Spring Boot comparison table so that table compares JVM to JVM. The comparison numbers are JVM only. Native is covered by an opt-in, long-running demo (demo-native.sh); its one recorded run, on 2026-10-06 with the Mandrel builder container, built in 136 s, produced a 141 MB binary, and reported startup in 0.081 s. Native resident memory was not measured.");
})();

contentSlide({ eyebrow: "Native", title: "Native executable: no JVM",
  subtitle: "order-service compiled ahead of time with Mandrel",
  demoRef: "demos/demo-native.sh",
  bullets: [
    { lead: "demo-native.sh", text: "compiles order-service to a native executable, using a local GraalVM or Mandrel native-image or a Docker-based Mandrel builder. It fails if neither exists; it never builds a JVM jar and calls it native." },
    { text: "It runs the *-runner binary directly, with no java and no quarkus-run.jar, against a throwaway Postgres container. Native mode gets no Dev Services, so %prod needs a reachable database.", lvl: 1 },
    { text: "Asserted: GET /orders returns a JSON array through the REST, Hibernate ORM, and Panache stack with no JVM in the process.", lvl: 1 },
  ],
  notes: "DEMO 19 of 19, so all nineteen demos in the matrix are now covered. What it does: compiles and runs order-service as a native executable with no JVM in the process. What to show: the native binary's boot log and a GET /orders response. Infra: opt-in, with a native toolchain and one throwaway Postgres container. It is long-running: several minutes, and longer the first time a 1 to 2 GB builder image is pulled. Fallback: the recorded boot log and GET /orders response. It is the only demo outside walkthrough.sh's default acts, because of its runtime cost. It sits apart from the Spring Boot comparison, which is JVM-only; this is the only place native compilation appears. Recorded run, 2026-10-06: no local native-image, so the Mandrel builder container was used; 136 s build, 141 MB runner binary, startup reported at 0.081 s, GET /orders served with no JVM. Single run, indicative." });

diagramSlide({ eyebrow: "Native", title: "How the native executable is built",
  subtitle: "Quarkus build, then native-image, then a binary with no JVM",
  demoRef: "demos/demo-native.sh",
  image: "11-native-build",
  caption: "Build: Quarkus build steps, then native-image. Run: the binary against a throwaway Postgres, with no Dev Services.",
  notes: "Walk the top row left to right. mvn package -Pnative runs the Quarkus build first: each extension's build steps run at build time, register what needs reflection or resources, and initialize classes, so the work a JVM would do at startup is already done. native-image then runs a points-to analysis over the closed world, snapshots the initialized heap, and compiles only reachable code into one executable. The middle row is where native-image comes from: a local GraalVM or Mandrel, or the Mandrel builder container with quarkus.native.container-build=true, which is what this machine used. If neither exists the demo fails rather than substituting a JVM jar. The bottom row is the run: native mode gets no Dev Services, so the demo starts a throwaway Postgres 18.6 container and passes TZ=UTC and a JDBC_URL to the binary, then asserts GET /orders returns a JSON array. Measured on 2026-10-06: 136 s build, 141 MB binary, startup 0.081 s. Single run, indicative." });

/* ====================== 10 · THE WHOLE PICTURE ====================== */
(() => {
  const s = divider({ num: "10", title: "The whole picture", sub: "The reference architecture assembled, and the four principles in practice on Quarkus and Kubernetes." });
  s.addNotes("Synthesis. Return to the reference architecture now that each box has a demo or verified manifest behind it, show the four value diagrams from the 101 deck backed by running code, walk demos/walkthrough.sh as the five-act presenter script, and close with adoption guidance.");
})();

diagramSlide({ eyebrow: "The whole picture", title: "The reference architecture, assembled",
  image: "08-reference-architecture",
  caption: "Data products behind the Istio mesh, KEDA-driven autoscaling, and every signal flowing through the Collector into Grafana LGTM and Kiali.",
  notes: "A callback to the first section. The audience has now seen a demo or verified manifest behind nearly every box: the nineteen demos, the three orchestration engines, the AI and rules showcase, the Spring Boot comparison with and without the AOT cache, the KEDA scalers, the mesh, and tracing." });

diagramSlide({ eyebrow: "The whole picture", title: "Domain ownership in practice",
  image: "10-value-domain-ownership",
  caption: "Each domain owns its service, data, and contract boundary end to end, with no central team in the path.",
  notes: "order-service, inventory-service, payment-service, shipping-service, notification-service, and review-service: six services with six owners. Each is a Quarkus module with its own storage, API, and contract. No central team sits in the path of any of them shipping a change." });

diagramSlide({ eyebrow: "The whole picture", title: "Data as a product in practice",
  image: "10-value-data-product",
  caption: "A data product is discoverable, addressable, trustworthy, and self-describing, backed by a versioned Avro contract and the Apicurio Schema Registry.",
  notes: "Every event in this project is Avro against Apicurio from the start; it was not retrofitted. demo-kafka.sh verifies the wire format at the byte level, beyond a configuration review." });

diagramSlide({ eyebrow: "The whole picture", title: "Self-serve platform in practice",
  image: "10-value-self-serve",
  caption: "Domains declare their infrastructure needs (topics, databases, scaling policies) and the platform's operators fulfil them.",
  notes: "Strimzi, CloudNativePG, and KEDA are the operators doing the fulfilling. notification-service and graphql-gateway both scale to zero and back without any autoscaling code in either service." });

diagramSlide({ eyebrow: "The whole picture", title: "Federated governance in practice",
  image: "10-value-governance",
  caption: "Global rules for contract format, security, and observability are enforced at the platform boundary while domains keep ownership.",
  notes: "The registry enforces contract compatibility computationally, the mesh enforces mTLS between meshed services, and the Collector makes every signal observable without per-service instrumentation effort. None of these needed a review board." });

contentSlide({ eyebrow: "The whole picture", title: "The five-act walkthrough",
  subtitle: "One presenter script runs every demo",
  demoRef: "demos/walkthrough.sh",
  bullets: [
    { lead: "ACT 1 — Data products & protocols (default):", text: "order, grpc, graphql, kafka, tracing, websocket, reactive-vertx, oidc." },
    { lead: "ACT 2 — Three orchestration styles (gated):", text: "orchestration-styles." },
    { lead: "ACT 3 — AI / Camel / Drools / MCP (gated):", text: "ai-classify, ai-mcp, camel-integration, ai-triage." },
    { lead: "ACT 4 — Developer experience & native:", text: "jbang-prototype, panama, continuous-testing (default); native (gated)." },
    { lead: "ACT 5 — Platform autoscaling (gated):", text: "keda-kafka, keda-http." },
  ],
  notes: "The orchestrator over all nineteen demos. It is the one script a presenter runs end to end, with Enter-to-advance pauses for a live audience or --auto for CI and self-test. Each demo runs as its own child process through run_act, so the orchestrator never double-manages a demo's own compose_up and compose_down. Gating is per demo, not per act, behind --with-ollama, --with-native, and --with-minikube; a missing flag skips the demo cleanly and does not fail it. It supports --only and --skip, --no-preflight, and --no-pause or --auto, and prints a final pass, fail, and skip tally." });

contentSlide({ eyebrow: "The whole picture", title: "Adoption: start small",
  bullets: [
    { lead: "Start with one domain and one product.", text: "order-service's shape (entity, REST resource, one synchronous call out, one event published) is the template to copy first." },
    { lead: "Add platform pieces as products need them:", text: "Kafka, the registry, and KEDA first; then governance once there are products to govern. The registry comes before the catalog, and mTLS before admission policy." },
    { head: true, text: "Verify each piece before adding the next" },
    { text: "Each piece in this deck can be verified on its own: stand it up, confirm it with its own demo, then add the next. The project was built that way, and each chapter ends with a verification status footer.", color: C.ink },
  ],
  notes: "A practical step before the wrap-up. A mesh, or this project's full stack, is not adopted all at once; the principles are independent enough to land incrementally. The answer to where to start is one domain, one product, and one demo that proves each piece before the next is added, and not the whole appendix on day one." });

// ---- local: wide diagram on top, four bold-lead bullets in two columns below ----
function wideDiagramSlide({ eyebrow, title, image, bullets, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, eyebrow, title);
  const d = L.DIMS[image];
  const maxW = PW - 1.4, maxH = 4.0;
  let w = maxW, h = w * (d.h / d.w);
  if (h > maxH) { h = maxH; w = h * (d.w / d.h); }
  s.addImage({ path: L.IMG(image), x: (PW - w) / 2, y: 1.45, w, h });
  const by = 1.45 + h + 0.1, colW = (PW - 1.4 - 0.4) / 2;
  L.addBullets(s, bullets.slice(0, 2), { x: 0.7, y: by, w: colW, h: 6.75 - by, fontSize: 12 });
  L.addBullets(s, bullets.slice(2), { x: 0.7 + colW + 0.4, y: by, w: colW - 0.3, h: 6.75 - by, fontSize: 12 });
  L.footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

wideDiagramSlide({ eyebrow: "The whole picture", title: "Analytical data: what it is and why it matters",
  image: "05-analytical-data-composition",
  bullets: [
    { lead: "What it is:", text: "historical, integrated, read-optimized views across domains, used for decisions and models." },
    { lead: "How a mesh produces it:", text: "domain-owned analytical data products derived from operational events and published with contracts." },
    { lead: "Value:", text: "trusted, discoverable data for decisions, ML features, and compliance, reused by many consumers without a central bottleneck." },
    { lead: "Here:", text: "the operational half is built; the analytical half is designed (sourcing and composition) and not built." },
  ],
  notes: "Analytical data is the point of the whole exercise, so it closes the main talk. It is the historical, integrated, read-optimized view that analysts and models use, in contrast to the current-state rows behind running services. A mesh produces it as domain-owned analytical data products, derived from operational events and published with the same contract discipline as the operational ones, so consumers find and trust them without a central team. For the organization this is the payoff: trusted, discoverable data for decisions, ML features, and compliance, reused by many consumers without a central bottleneck, which is the data-as-a-product principle applied to analytics. The diagram shows operational data refined through events and entities into a published data product that analytics consumes. Status: the operational services, contracts, and events in this project are built and demonstrated. The analytical sourcing and composition shown here, and the ingestion and streaming picture earlier in the deck, are designed and not built; there is no CDC layer and no catalog ingesting lineage yet." });

(() => {
  const s = pres.addSlide();
  s.addImage({ path: L.ILLUS, x: 0, y: 0, w: PW, h: PH, sizing: { type: "cover", w: PW, h: PH } });
  const rx = PW * 0.42, rw = PW - rx - 0.7;
  s.addText("Nineteen demos. Three orchestration engines.", { x: rx, y: 2.5, w: rw, h: 1.4, fontSize: 27, color: "FFFFFF", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("Every capability backed by code in this project.", { x: rx, y: 3.9, w: rw, h: 0.9, fontSize: 27, color: "FFD9D9", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("Quarkus and Kubernetes give the four principles a working platform.", { x: rx, y: 5.0, w: rw, h: 0.6, fontSize: 14.5, color: "FFFFFF", fontFace: F.body, italic: true, valign: "top", margin: 0 });
  const lw = 1.25, lh = lw / L.LOGO_AR;
  s.addImage({ path: L.LOGO_LIGHT, x: PW - 0.6 - lw, y: PH - 0.3 - lh, w: lw, h: lh });
  L.pageNumOnly(s, { dark: true });
  s.addNotes("Closing slide before the appendix. Summary: nineteen demos, three coordination engines over one domain, and a status for each capability, with the MCP server path working and in-process tool calling still open upstream. Open for questions here if this is the end of the live session. The appendix that follows is reference material, not more narrative.");
})();

/* ====================== 11 · APPENDICES ====================== */
(() => {
  const s = divider({ num: "11", title: "Appendices", sub: "Six optional deep-dives, one topic each." });
  s.addNotes("These mirror the six appendix chapters on the site. They are reference depth outside the main arc: scaling the WebSocket push, the gotchas, agentic-development recommendations, testing detail, in-memory versus Kafka messaging, and the three engines compared. Pull up whichever one a question lands on.");
})();

diagramSlide({ eyebrow: "Appendix A1", title: "Scaling WebSocket push with Kafka",
  image: "16-websocket-scaling",
  caption: "A shared consumer group persists notifications; each replica also consumes the topic under its own group and pushes to its local sockets.",
  notes: "Per-replica fan-out is implemented and verified. OrderPlacedConsumer (a shared consumer group) persists notifications, with one replica per partition. OrderPlacedPushConsumer uses a per-replica group, so every replica receives every event and pushes to the sockets connected to that replica through OpenConnections. This was checked with two replicas on Kubernetes. A shared group alone would split partitions across replicas, which is backwards for a push that needs every replica to see every event, because a socket stays pinned to one replica. Making KEDA scale-to-zero socket-aware remains a recommendation and is not built." });

diagramSlide({ eyebrow: "Appendix A1", title: "Surviving a replica failure",
  image: "16-websocket-failover",
  caption: "The socket closes, the client backs off with jitter, and a reconnect lands on a replica that already receives every event.",
  notes: "Three panels. Normal: the client is connected to replica 2. Replica 2 fails: the socket closes and the client retries with backoff and jitter (1 s, 2 s, 4 s, and so on). Recovery: the Service routes the reconnect to replica 1 or 3, which already receives every event through its own push group, and the client fetches missed events with GET /notifications. Status: verified 2026-10-06 with tooling/ws-failover/verify-ws-failover.sh and the WsReconnectClient: with two replicas, deleting the one holding the socket closed it, the client reconnected after a jittered 979 ms backoff, caught up through GET /notifications with no duplicate, and received the next order from the survivor. Single run." });

diagramSlide({ eyebrow: "Appendix A2", title: "Gotchas",
  image: "17-gotchas",
  caption: "Eight pitfalls hit while building this project, each with its symptom and the fix that landed.",
  notes: "Every cell maps to a committed fix: postgres:18's rejection of Olson timezone ids, Avro 1.12's ClassSecurityValidator, the gRPC 9001 and 9000 port mismatch, @QuarkusIntegrationTest's separate-process timezone, import.sql skipped in %prod, @Consumes returning 415 on a bodyless GET plus RestAssured's false pass, the Avro serde falling back to JSON, and the stale-volume reset. The last one is a general operating caution; it was investigated and ruled out as a defect." });

diagramSlide({ eyebrow: "Appendix A3", title: "Agentic recommendations",
  image: "18-agentic-recommendations",
  caption: "A plan, execute, validate relay: a stronger model plans and validates, a faster model executes, and the diff is verified independently.",
  notes: "Agentic help works for bounded, well-specified changes grounded in the real code and MCP tooling (camel-mcp, quarkus-agent). It does not replace architecture decisions or verification. A subagent's report is a claim, not evidence, so the diff is checked independently." });

diagramSlide({ eyebrow: "Appendix A4", title: "Testing in detail",
  image: "19-testing-pyramid",
  caption: "Unit @QuarkusTest at the base, failsafe integration tests above, functional (Newman) and load (hey, ghz) at the top, and the phases run-all-tests.sh walks.",
  notes: "Unit tests run under surefire with Dev Services provisioning the infrastructure. Failsafe *IT tests provision their own Testcontainers: OrderPlacedAvroWireIT's byte-level Avro assertion, and InventoryCheckStockWireIT, which seeds data and then calls gRPC. Functional and load tests sit on top. scripts/run-all-tests.sh walks the pyramid with flags to select tiers. Ollama-gated tests are skipped unless their flag is set." });

diagramSlide({ eyebrow: "Appendix A5", title: "Vert.x in-memory messaging",
  image: "20-vertx-in-memory",
  caption: "Producers and consumers inside one JVM, over Vert.x's event bus, scaling up with cores. Illustrative; this project uses the in-memory connector in shipping-service tests.",
  notes: "One JVM: event-loop threads (about twice the core count) and a worker pool, with the Vert.x event bus offering send, publish, and request-reply. Producers use Emitter or @Outgoing and consumers use @Incoming or @ConsumeEvent. It scales up with cores, has no network hop or wire serialization, and gets back-pressure from Mutiny. Limits: one JVM, not durable, no replay. This project uses the in-memory connector in shipping-service tests; the event-bus usage on the diagram is illustrative." });

diagramSlide({ eyebrow: "Appendix A5", title: "Kafka messaging",
  image: "20-kafka-messaging",
  caption: "Producers write to partitions; consumer groups read independently, with retention and offsets giving replay and Apicurio holding the schemas.",
  notes: "Producers write to topic partitions P0 to P3. Consumer group A has replicas that each own partitions; group B reads the same topic independently, which is how fan-out works. Retention and consumer offsets allow replay. Apicurio holds the schemas. To scale out, add consumers up to the partition count; KEDA scales on lag." });

diagramSlide({ eyebrow: "Appendix A5", title: "In-memory vs. Kafka, side by side",
  image: "20-inmemory-vs-kafka",
  caption: "The same @Incoming and @Outgoing code over two connectors: in-memory Vert.x for fast, deterministic tests and Kafka for the durable, partitioned production transport.",
  notes: "Only the connector configuration changes between the two; the application code is identical. In-memory proves messaging logic in tests without a broker and is not a production transport. The comparison covers scope, durability, ordering, how each scales (up across cores versus out across partitions and replicas), failure behavior (lost on crash versus replay from an offset), and where each is used here (tests versus %prod)." });

diagramSlide({ eyebrow: "Appendix A6", title: "The three engines, compared",
  image: "21-three-engines-compare",
  caption: "Kafka choreography against two shapes of orchestration (a Camel route and a Quarkus Flow document), compared by sequence ownership, coupling, failure handling, debugging, and where the logic lives.",
  notes: "More detail than the three-engines section. Terminology stays exact: Kafka is choreography, with no central coordinator and each participant reacting to events; Camel and Quarkus Flow are both orchestration, with one component sequencing the steps. Failure handling in this project today is idempotent redelivery and exception propagation, not saga compensation." });

/* ====================== APPENDIX ====================== */
(() => {
  const s = divider({ num: "—", title: "Appendix", sub: "The full demo matrix, a known limitation in detail, infrastructure reference, a glossary, and background diagrams." });
  s.addNotes("Reference material, not more narrative. Use it after the talk to check a demo's infrastructure tier, the root cause behind the tool-calling limitation, or a term in the glossary. The background diagrams are the 101 deck's figures.");
})();

contentSlide({ eyebrow: "Appendix · demo matrix", title: "All 19 demos by infra tier (1 of 2): bare and compose",
  bullets: [
    { head: true, text: "bare: JVM or Dev Services only, no compose, no cluster" },
    { lead: "demo-jbang-prototype.sh", sep: " — ", text: "JBang and Camel CLI prototyping, no Maven module." },
    { lead: "demo-panama.sh", sep: " — ", text: "Panama FFM calls to libc from a JBang script." },
    { lead: "demo-continuous-testing.sh", sep: " — ", text: "quarkus:dev continuous testing with Dev Services." },
    { lead: "demo-native.sh", sep: " — ", text: "GraalVM or Mandrel native build and boot (opt-in)." },
    { head: true, text: "compose: infra baseline (docker compose up -d)" },
    { text: "demo-order.sh · demo-grpc.sh · demo-graphql.sh · demo-kafka.sh · demo-tracing.sh · demo-websocket.sh · demo-reactive-vertx.sh" },
    { lead: "demo-oidc.sh", sep: " — ", text: "feasibility-gated; may be skipped." },
  ],
  notes: "Mirrors the matrix in demos/README.md. 'bare' needs JDK 25, Maven 3.9.x, and jbang on PATH, plus GraalVM or Mandrel for native; no docker compose. 'compose' needs docker and the Compose v2 plugin, cp .env.example .env, and docker compose up -d from the repo root (postgres, kafka-native, apicurio, otel-lgtm; no profile flag)." });

contentSlide({ eyebrow: "Appendix · demo matrix", title: "All 19 demos by infra tier (2 of 2): ollama, Kubernetes",
  bullets: [
    { head: true, text: "compose + --profile ollama: opt-in, heaviest infra (8g memory budget)" },
    { text: "demo-ai-classify.sh · demo-ai-mcp.sh · demo-camel-integration.sh · demo-ai-triage.sh" },
    { head: true, text: "Kubernetes: the local cluster from scripts/bootstrap.sh (opt-in)" },
    { text: "demo-keda-kafka.sh · demo-keda-http.sh" },
    { head: true, text: "Orchestrator" },
    { lead: "walkthrough.sh", sep: " — ", text: "five acts over all 19 demos, gated per demo by --with-ollama, --with-native, and --with-minikube." },
    { text: "Opt-in summary: ollama gates the four AI demos; native gates demo-native.sh; Kubernetes gates the two KEDA demos; demo-oidc.sh is feasibility-gated.", color: C.ink },
  ],
  notes: "Everything outside the opt-in summary (bare and compose, minus demo-oidc.sh) is the default, always-runnable set: the core of a single-machine run with no extra flags. walkthrough.sh also supports --only and --skip, --no-preflight, --no-pause and --auto, and prints a pass, fail, and skip tally." });

contentSlide({ eyebrow: "Appendix · known limitation", title: "Known limitation: in-process LLM tool calling",
  bullets: [
    { head: true, text: "Symptom" },
    { text: "OrderAssistantRouteIT asks for an order's status and asserts the agent invoked the order-status tool. It fails: the model answers in one round trip and the tool route is never invoked." },
    { head: true, text: "Root cause (upstream)" },
    { text: "camel-quarkus-support-langchain4j's enforceJaxRsHttpClient() sets the global property langchain4j.http.clientBuilderFactory for every dev.langchain4j model, with no toggle. A hand-built OllamaChatModel's base-url is never honored.", color: C.ink },
    { head: true, text: "Ruled out" },
    { text: "Model capability, tool registration and tag matching, and the langchain4j version, including the seed-matched classpath.", color: C.ink },
  ],
  notes: "Symptom detail: the tool-executions header is absent. Root cause detail: the property is set before any model bean is constructed, so the two levers a caller has (a hand-built OllamaChatModel with an explicit base-url, and an explicit httpClientBuilder(new JdkHttpClientBuilder()) override) were both tried and neither changed the outcome. Ruled out: a direct Ollama /api/chat call with a tools array returns tool_calls for qwen2.5:3b and qwen2.5:7b-instruct; the tags line up; the defect reproduces across every langchain4j combination tried. The classpath side is resolved: quarkus-langchain4j-bom:1.7.4 is imported first, so the dev.langchain4j family converges at 1.11.0 with no manual pin. The limitation does not block the build: the test is named *IT (surefire skips it), gated behind -Dollama.tests.enabled=true, and failsafe is not bound in ai-mcp-service, so mvn verify never needs Ollama. Options to revisit: a newer camel-quarkus and quarkus-langchain4j train where the enforcement differs, an upstream issue against camel-quarkus-support-langchain4j, and continuing to demonstrate tool calling through the embedded MCP server, which this deck does." });

contentSlide({ eyebrow: "Appendix · infra", title: "compose.yaml services and .env image tags",
  bullets: [
    { head: true, text: "Baseline services (no --profile flag)" },
    { text: "postgres (postgres:18, TZ=UTC) · kafka (apache/kafka-native:4.2.0, KRaft) · apicurio (apicurio-registry:3.1.7) · lgtm (grafana/otel-lgtm:0.8.1, always on)." },
    { head: true, text: "Opt-in profiles" },
    { text: "--profile tools: kafka-ui (kafbat/kafka-ui) · --profile ollama: ollama (ollama/ollama)." },
    { head: true, text: "Image tags" },
    { text: "Each tag in .env equals the tag Quarkus 3.39.5 Dev Services pulls by default, so quarkus:dev, mvn verify, and this compose stack behave the same.", color: C.ink },
    { text: "postgres:18 rejects legacy Olson timezone ids such as US/Eastern from a non-UTC host; TZ=UTC on the container and -Duser.timezone=UTC on every JVM keep mvn verify green.", color: C.ink },
  ],
  notes: "The standing infrastructure behind every compose-tier demo. docker compose up -d from the repo root, after cp .env.example .env, brings up the whole baseline. The Kafka listeners are PLAINTEXT and INTERNAL. The tag match was confirmed by inspecting the build-time config classes inside the cached Dev Services deployment jars." });

contentSlide({ eyebrow: "Appendix · determinism", title: "ai-rules-service: how determinism was established",
  bullets: [
    { lead: "ai-rules-service's pom.xml", text: "lacked the quarkus-maven-plugin <build> binding its siblings have, so mvn quarkus:dev did nothing and mvn package produced only a thin jar. Fixed here; the same gap remains in ai-mcp-service, notification-service, and payment-service." },
    { lead: "The module", text: "has no health endpoint, so the demo waits for any HTTP response as its readiness signal.", lvl: 1 },
    { lead: "The three demo-ai-triage.sh inputs", text: "were sampled against the live qwen2.5:3b model, using the TriageService prompt, until riskSignal and amount classified stably.", lvl: 1 },
    { text: "Drools' decision is a deterministic function of the classified fields, so a stable classification gives a stable decision and the demo asserts the exact decision.", color: C.ink },
  ],
  notes: "Detail: the shared demo harness's wait_http needs a 2xx or 3xx response, which this module cannot give, so readiness is connection-refused to connected. The strict assertion is stronger than the module's own opt-in integration tests, which assert membership in the set of valid decisions. Re-running the demo twice in a row against the live model produced the same three decisions on both endpoints both times, which is the empirical basis for the strict assertion." });

glossarySlide({ eyebrow: "Appendix · glossary", title: "Glossary (1 of 3): data mesh and architecture",
  terms: [
    { term: "Data product", def: "A dataset or service a domain team publishes for other teams, with an owner, a contract, and quality commitments." },
    { term: "Choreography", def: "Services react to events independently; no central process knows the whole sequence." },
    { term: "Orchestration", def: "One component sequences the steps and knows the whole flow, as a Camel route or a Quarkus Flow document." },
    { term: "CNCF Serverless Workflow", def: "An open specification for declaring workflow tasks and their order as a document. Quarkus Flow implements it." },
    { term: "Avro / Apicurio Registry", def: "Avro is the binary, schema-based event format; Apicurio stores the schemas and enforces compatibility." },
    { term: "MCP", def: "Model Context Protocol: a JSON-RPC protocol for a client to discover and call tools that a server exposes." },
    { term: "OIDC", def: "OpenID Connect: token-based authentication on OAuth 2.0. Here, bearer tokens issued by Keycloak." },
  ],
  notes: "First of three glossary slides: data-mesh and architecture terms, grouped by where they appear (data as a product, the three engines, AI and rules, security). Definitions are short; the chapters carry the detail." });

glossarySlide({ eyebrow: "Appendix · glossary", title: "Glossary (2 of 3): Quarkus and the JDK",
  terms: [
    { term: "Panache", def: "A Hibernate ORM layer that removes boilerplate. This project uses active record: the entity carries its own finders and persist()." },
    { term: "Dev Services", def: "Quarkus starts containers (database, Kafka, Keycloak) automatically in dev and test, with no compose file." },
    { term: "Mutiny Uni", def: "Mutiny's lazy single-value asynchronous type; it runs when something subscribes." },
    { term: "WebSockets.Next", def: "The Vert.x-based Quarkus WebSocket extension: annotated endpoints, injectable OpenConnections, and a client API." },
    { term: "JBang", def: "Runs a single Java file with inline dependencies; no project or pom.xml." },
    { term: "Native image (GraalVM / Mandrel)", def: "Compiles the application ahead of time into an executable with no JVM. The build takes minutes." },
    { term: "AOT cache (Project Leyden)", def: "A JDK 25 cache of loaded and linked classes from a training run, used to speed JVM startup." },
    { term: "Panama FFM", def: "The JDK's foreign function and memory API: calls native libraries from Java without JNI." },
  ],
  notes: "Second of three: the Quarkus and JDK terms from the capability tour and the Spring Boot comparison. The AOT cache and native image are different startup strategies: the cache keeps a full JVM with the JIT, and native image removes the JVM." });

glossarySlide({ eyebrow: "Appendix · glossary", title: "Glossary (3 of 3): platform and AI",
  terms: [
    { term: "KEDA / HPA", def: "The HPA scales pods on CPU or memory. KEDA drives an HPA from external signals and adds scale to zero." },
    { term: "Istio, sidecar, mTLS", def: "Istio is a service mesh. A sidecar Envoy proxy sits beside each pod; mTLS authenticates and encrypts calls between sidecars." },
    { term: "OTLP / OpenTelemetry", def: "A vendor-neutral standard and wire protocol for exporting metrics, traces, and logs." },
    { term: "langchain4j", def: "A Java library for LLM integration: chat calls, prompts, and tool calling." },
    { term: "Drools KieBase / KieSession", def: "A KieBase is the compiled rule set, built once. A KieSession is per-request working memory." },
    { term: "UBI", def: "Universal Base Image: Red Hat's redistributable container base image, used by every multi-stage build here." },
  ],
  notes: "Third of three: platform and AI terms from the platform, governance, and AI and rules sections, plus the base-image convention used across the infrastructure slides." });

twoUpDiagramSlide({ eyebrow: "Appendix · background diagrams", title: "From pipelines to warehouses: the earlier architectures",
  images: ["01-data-pipeline-architecture", "01-data-warehouse-architecture"],
  captions: ["A linear ETL or ELT pipeline moving data from an operational source through transformation to an analytical destination.", "Multiple operational sources feeding a centralized, schema-on-write warehouse owned by a central team."],
  note: "Background: earlier data architectures, from pipelines to warehouses.",
  notes: "These two diagrams set up the architectural history the 101 deck argues against. The 201 deck assumes that argument is settled and goes straight to building the mesh, so the figures are kept here for reference." });

twoUpDiagramSlide({ eyebrow: "Appendix · background diagrams", title: "The data lake, and the shift to decentralization",
  images: ["01-data-lake-architecture", "01-data-mesh-decentralized"],
  captions: ["A data lake organized into raw, curated, and refined zones, accepting structured, semi-structured, and unstructured data.", "Multiple domain teams each owning a data product, connected by a shared self-serve platform instead of a central team."],
  note: "Background: the data lake and the shift to decentralization.",
  notes: "The data lake is the third centralized architecture the 101 deck walks through before introducing the mesh. The decentralized diagram is the target that this deck builds piece by piece in Quarkus." });

twoUpDiagramSlide({ eyebrow: "Appendix · background diagrams", title: "The monolith-to-mesh refactor, and its timeline",
  images: ["01-monolith-to-mesh", "01-architecture-evolution"],
  captions: ["A monolithic application and its monolithic data platform both decomposing into domain-owned services and domain-owned data products.", "The progression from pipelines to warehouses to lakes to mesh, with the problem each pattern solved."],
  note: "Background: the monolith-to-mesh refactor and the evolution of data architectures.",
  notes: "The monolith-to-mesh analogy (the refactor microservices applied to applications, applied to data) carries a lot of the 101 deck. The evolution timeline is the one-slide history of why each earlier architecture hit a wall. Both are assumed knowledge by the time the 201 starts." });

diagramSlide({ eyebrow: "Appendix · background diagrams", title: "The full project example on Kubernetes",
  image: "02-capstone-data-mesh",
  caption: "The complete data mesh reference architecture on Kubernetes: domain services, the service mesh, and the self-serve platform tier underneath.",
  notes: "This illustration comes from the Python sibling repository's reference architecture. It is similar to, but not identical to, this project's own reference-architecture diagram shown earlier, so it sits here as background and is not presented as this deck's architecture. The image file keeps its original name, 02-capstone-data-mesh." });

diagramSlide({ eyebrow: "Appendix · background diagrams", title: "Operational vs. analytical data",
  image: "01-operational-vs-analytical",
  caption: "The operational plane runs the business; the analytical plane informs decisions. Pipelines have traditionally bridged them; a mesh keeps both owned by the domain.",
  notes: "The 101 deck's version of the seam a mesh addresses. Traditionally the operational and analytical layers are separate technology stacks joined by pipelines. A mesh keeps the distinction but organizes it by domain: each domain owns its operational systems and the analytical products derived from them. The final slide of the deck covers the analytical half in more detail." });

/* ============================ WRITE ============================ */
L.writeDeck("Datamesh-201-Quarkus-r1.1.pptx").then((f) => console.log("WROTE", f));
