---
title: "A Quarkus capability tour"
order: 12
part: The Quarkus deep-dive
description: "Panache, gRPC, GraphQL, Reactive Messaging, WebSockets.Next, unified Vert.x reactive/imperative execution, continuous testing, native compilation, OIDC, and JBang — each anchored to a real endpoint or demo in this project."
duration: 45 minutes
marker: "12"
---

Every chapter so far has used Quarkus as plumbing. This one stops and looks
at the plumbing itself: nine capabilities, each demonstrated by a real
endpoint or route already running somewhere in this project, not a toy
snippet written just for this page. The point is breadth — what does Quarkus
actually hand you, out of the box, across REST, RPC, messaging, testing, and
packaging — so that later chapters (especially 13 and 14, which lean on two
of these capabilities hard) have a named vocabulary to build on.

The code is in [notification-service]({{ site.repo_tree }}/examples/notification-service), [inventory-service]({{ site.repo_tree }}/examples/inventory-service),
[order-service]({{ site.repo_tree }}/examples/order-service), [review-service]({{ site.repo_tree }}/examples/review-service), and
[graphql-gateway]({{ site.repo_tree }}/examples/graphql-gateway); each section below names its own demo script —
the run script there builds/sets up and runs it; its `README.md` (where one
exists) covers what it does and how to drive it.

{% include excalidraw.html file="11-capability-tour" alt="Nine Quarkus capabilities arranged around the services that demonstrate them: Panache and Vert.x unification in inventory-service, gRPC between inventory-service and the gateway, GraphQL federation in graphql-gateway, Reactive Messaging and WebSockets.Next between order-service and notification-service, continuous testing and native compilation in order-service, OIDC in review-service, and JBang prototyping standalone" caption="Figure 11.1 — The nine capabilities and the services that demonstrate them" %}

Read it left to right as a map, not a sequence: nothing here depends on
anything else in this tour running first, and the only two capabilities the
rest of the book leans on by name are Reactive Messaging (chapter 13's
choreography leg republishes the exact `OrderEventProducer` shown below) and
the orchestration shapes built on top of plain bean calls (chapters 13 and
14). Everything else is read independently, a capability at a time.

## Panache: the entity *is* the repository

Hibernate ORM with Panache collapses the repository layer into the entity
itself. `order-service`'s `Order` entity
([Order.java]({{ site.repo_blob }}/examples/order-service/src/main/java/com/patterncatalyst/datamesh/order/Order.java))
extends `PanacheEntityBase` and exposes its columns as plain public fields:

```java
@Entity
@Table(name = "orders")
public class Order extends PanacheEntityBase {

    @Id
    @Column(length = 36, nullable = false, updatable = false)
    public String id;

    @Column(name = "customer_id", nullable = false)
    public String customerId;
    // ...

    public static Order create(String customerId, String itemSku, int quantity, BigDecimal amount) {
        Order order = new Order();
        order.id = UUID.randomUUID().toString();
        // ...
        return order;
    }
}
```

There is no `OrderRepository` interface, no `@Autowired` DAO, no mapper
between a JPA entity and a domain object — `Order.create(...)` builds the row,
`order.persist()` (called from the REST layer) writes it, and static finders
like `Stock.findBySku(...)` (the same pattern, used by `inventory-service`'s
`Stock` entity) read it back. This is Panache's **active record** style: the
entity owns both its data and its persistence operations. The trade-off is
real — your entity classes now depend on a Panache base class, and the active
record style doesn't suit every team's layering preference — but for a
reference architecture built around one aggregate per service, it removes an
entire layer of indirection with nothing lost: `inventory-service`'s
[StockResource.java]({{ site.repo_blob }}/examples/inventory-service/src/main/java/com/patterncatalyst/datamesh/inventory/StockResource.java)
calls `Stock.findBySku(request.sku())` directly from a JAX-RS resource method,
no repository bean in between.

## gRPC: a typed contract, generated at build time

`inventory-service` answers `capstone.inventory.v1.InventoryService/CheckStock`
over gRPC, implemented by [InventoryGrpcService.java]({{ site.repo_blob }}/examples/inventory-service/src/main/java/com/patterncatalyst/datamesh/inventory/InventoryGrpcService.java):

```java
@GrpcService
public class InventoryGrpcService implements InventoryService {

    @Override
    @Blocking
    public Uni<CheckStockResponse> checkStock(CheckStockRequest request) {
        return Uni.createFrom().item(() -> {
            Stock stock = Stock.findBySku(request.getSku());
            int onHand = stock != null ? stock.quantityOnHand : 0;
            boolean available = request.getQuantity() > 0 && onHand >= request.getQuantity();
            return CheckStockResponse.newBuilder()
                    .setAvailable(available)
                    .setQuantityOnHand(onHand)
                    .build();
        });
    }
}
```

`InventoryService` itself is not hand-written — it's generated at build time
from [inventory.proto]({{ site.repo_blob }}/examples/contracts/src/main/proto/capstone/inventory/v1/inventory.proto) (the
`contracts` module is a dependency jar, and `quarkus.generate-code.grpc.scan-for-proto`
tells Quarkus to generate from a proto packaged inside a dependency rather
than only from `src/main/proto` in this module). `@GrpcService` registers the
bean as the gRPC server's implementation; `@Blocking` tells Vert.x this
particular handler does blocking JDBC/Panache work and should run on a
worker thread rather than the event loop, even though its public signature
(`Uni<CheckStockResponse>`) is the fully reactive, non-blocking shape every
caller sees. [demo-grpc.sh]({{ site.repo_blob }}/demos/demo-grpc.sh) drives this directly with `grpcurl` against
the real `.proto` (not server reflection as the primary path, though
reflection is also demonstrated) — a genuine gRPC client issuing a unary RPC
over HTTP/2, not merely a REST call over a different protocol.

## GraphQL: one query, two downstream protocols

`graphql-gateway`'s [GatewayApi.java]({{ site.repo_blob }}/examples/graphql-gateway/src/main/java/com/patterncatalyst/datamesh/gateway/GatewayApi.java)
federates two protocols behind a single `/graphql` endpoint:

```java
@GraphQLApi
@ApplicationScoped
public class GatewayApi {

    @RestClient
    OrderRestClient orderRestClient;

    @GrpcClient("inventory")
    InventoryServiceGrpc.InventoryServiceBlockingStub inventoryClient;

    @Query("order")
    public OrderView order(@Name("id") String id) {
        try (Response response = orderRestClient.getOrder(id)) {
            OrderDto dto = response.readEntity(OrderDto.class);
            return OrderView.from(dto);
        }
    }

    public StockView stock(@Source OrderView order) {
        CheckStockResponse response = inventoryClient.checkStock(CheckStockRequest.newBuilder()
                .setSku(order.itemSku())
                .setQuantity(order.quantity())
                .build());
        return new StockView(order.itemSku(), response.getQuantityOnHand(), response.getAvailable());
    }
}
```

`order(id)` is the top-level query, resolved over a plain MicroProfile REST
Client call to `order-service`. `stock(...)` is a **field resolver** —
MicroProfile GraphQL's `@Source` annotation marks it as the resolver for
`OrderView`'s `stock` field, and SmallRye GraphQL only calls it when a client
query actually selects that field. That laziness matters: a client asking
only for `order(id) { customerId }` never triggers the gRPC call to
`inventory-service` at all. One client request, two backend protocols (REST
and gRPC), stitched into one response shape — and the second protocol call is
opt-in per query, not per endpoint. [demo-graphql.sh]({{ site.repo_blob }}/demos/demo-graphql.sh) places a real
order, then queries the gateway and asserts both the REST-sourced order
fields and the gRPC-sourced nested `stock` fields land in one `.data.order`
payload with no `.errors`.

## Reactive Messaging: Avro events, not raw bytes

`order-service`'s [OrderEventProducer.java]({{ site.repo_blob }}/examples/order-service/src/main/java/com/patterncatalyst/datamesh/order/OrderEventProducer.java)
publishes `order.placed` through an injected `Emitter`:

```java
@ApplicationScoped
public class OrderEventProducer {

    @Inject
    @Channel("order-placed")
    Emitter<OrderPlaced> emitter;

    public CompletionStage<Void> publish(Order order) {
        OrderPlaced event = OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId(order.id)
                // ...
                .build();
        return emitter.send(event);
    }
}
```

`@Channel("order-placed")` binds this emitter to Kafka configuration in
[application.properties]({{ site.repo_blob }}/examples/order-service/src/main/resources/application.properties) (topic name, serializer); MicroProfile Reactive
Messaging turns a typed `Emitter<OrderPlaced>.send(...)` call into a Kafka
produce, with the `OrderPlaced` Avro record serialized against the Apicurio
Schema Registry rather than as raw JSON — this repo pins the Avro serializer
explicitly rather than trusting Quarkus's connector autodetection (see
Chapter 13's choreography leg, which drives this same producer and reads the
Apicurio wire-format magic byte back off the real topic as proof). On the
consumer side, `notification-service`'s `OrderPlacedConsumer` is the mirror
image: `@Incoming("order-placed")` on a plain `@Transactional` method, no
manual Kafka client code either direction.

## WebSockets.Next: pushing a real, already-committed event

`notification-service` exposes `/ws/notifications` via [OrderNotificationSocket.java]({{ site.repo_blob }}/examples/notification-service/src/main/java/com/patterncatalyst/datamesh/notification/OrderNotificationSocket.java):

```java
@WebSocket(path = "/ws/notifications")
public class OrderNotificationSocket {

    @OnOpen
    public String onOpen() {
        return "{\"type\":\"connected\"}";
    }
}
```

This endpoint is deliberately thin — its only job is to acknowledge a new
connection. The actual push happens from [OrderPlacedConsumer.java]({{ site.repo_blob }}/examples/notification-service/src/main/java/com/patterncatalyst/datamesh/notification/OrderPlacedConsumer.java),
the same Reactive Messaging consumer from the previous section, right after
it persists a `Notification` row:

```java
@Inject
OpenConnections wsConnections;

@Incoming("order-placed")
@Transactional
public void consume(OrderPlaced event) {
    // ... find-or-create and persist the Notification ...
    wsConnections.listAll().forEach(connection -> connection.sendTextAndAwait(notification));
}
```

`OpenConnections` is WebSockets.Next's injectable registry of every live
socket connection; `listAll()` iterates them and `sendTextAndAwait(...)`
serializes the entity to JSON the same way the REST layer would (Jackson)
and pushes it. The design decision worth noticing: the push happens *after*
`notification.persist()` commits, not before — a client only ever sees an
event that is already durable, never a speculative one that might later roll
back. [demo-websocket.sh]({{ site.repo_blob }}/demos/demo-websocket.sh) proves this with a real JDK
`java.net.http.WebSocket` client (run via JBang, see below), connected
*before* an order is placed, and asserts the second message it receives over
the live socket matches the order's `orderId`/`customerId`/`itemSku` exactly
— not merely that a message arrived.

## Vert.x reactive + imperative, one JVM, one reactor

`inventory-service` answers the *same* `stock` table through two different
execution models at once: `InventoryGrpcService.checkStock` (above) is a
reactive `Uni<CheckStockResponse>` endpoint with its blocking Panache lookup
safely offloaded via `@Blocking`; [StockResource.java]({{ site.repo_blob }}/examples/inventory-service/src/main/java/com/patterncatalyst/datamesh/inventory/StockResource.java)
is a classic imperative JAX-RS resource, thread-per-request, no `Uni`
anywhere:

```java
@GET
@Path("/{sku}")
public StockDto get(@PathParam("sku") String sku) {
    Stock stock = Stock.findBySku(sku);
    if (stock == null) {
        throw new NotFoundException("No stock recorded for sku=" + sku);
    }
    return toDto(stock);
}
```

The two paths compute different results: the gRPC path's `available` is
request-dependent (`quantity > 0 && onHand >= quantity`), while the REST
path's `available` is a static snapshot (`quantityOnHand > 0`) — asking for
more stock than is on hand can report `available=false` over gRPC for a SKU
that REST still calls available. [demo-reactive-vertx.sh]({{ site.repo_blob }}/demos/demo-reactive-vertx.sh) proves both
independently, *and* fires three gRPC calls and three REST calls
concurrently against the one running process, asserting every response
comes back correct and uncorrelated — the textbook Quarkus/Vert.x claim
("unified reactive and imperative, one reactor") exercised under genuine
concurrent load, not just asserted in prose.

This matters beyond the demo: most real services in this build are not
purely one style or the other. `inventory-service` picked reactive for its
gRPC surface because that's the idiomatic shape `quarkus-grpc` generates,
and imperative for its REST surface because the handler is a two-line
lookup with no benefit from `Uni` wrapping — there was no migration, no
"reactive-ification" effort, and no second event loop spun up to host the
imperative side. Both styles are just method bodies registered with the
same Vert.x instance; the framework, not the developer, decides which
thread pool a given request lands on based on `@Blocking` and the handler's
declared return type.

## Continuous testing + Dev Services: tests that run themselves, against real infra

`mvn quarkus:dev` with `quarkus.test.continuous-testing=enabled` re-runs a
module's tests automatically on every save, and Dev Services provisions the
Testcontainers (Postgres, Kafka, Apicurio) those tests need with zero
`docker compose` and zero `.env` — [demo-continuous-testing.sh]({{ site.repo_blob }}/demos/demo-continuous-testing.sh) starts
`order-service` this way and watches its own dev-mode log for the literal
pass banner Quarkus 3.39.5 prints:

```text
All 4 tests are passing (0 skipped), 4 tests were run in 8318ms.
```

The demo parses that line for the passing/run counts and asserts
`passing == run` — and if the banner never appears (say, a future Quarkus
release rewords it), it does **not** silently treat "the app came up" as a
pass; continuous testing reporting a result is the capability under test,
and "the HTTP listener started" alone doesn't prove it. That degrade-loudly
behavior is itself worth learning from: a demo that can't observe its
target capability should fail, not quietly narrow its own claim.

## Native compilation: no JVM at all

[demo-native.sh]({{ site.repo_blob }}/demos/demo-native.sh) compiles `order-service` to a native executable —
first checking for a local GraalVM/Mandrel `native-image`, falling back to
`-Dquarkus.native.container-build=true` (a Docker-based Mandrel builder
image) if none is found, and failing loudly rather than silently building a
JVM jar and calling it native if neither toolchain is available. Once built,
the demo runs the produced `*-runner` binary directly — no `java`, no
`quarkus-run.jar` — against a real throwaway Postgres container (native mode
gets no Dev Services; `order-service`'s `%prod` profile expects a real,
reachable database), and asserts `GET /orders` returns a real JSON array
through the full REST + Hibernate ORM + Panache stack with zero JVM in the
process. This is the only chapter in this tour where native compilation
appears — it is specifically *not* covered in the Spring Boot comparison
chapter, where only a JVM-mode comparison is made.

## OIDC: live bearer tokens, not a mocked header

`review-service` added `quarkus-oidc` with **zero** `quarkus.oidc.*`
configuration — with no `auth-server-url` set, Quarkus Dev Services
auto-provisions a disposable Keycloak container in dev/test (realm
`quarkus`, client `quarkus-app`/`secret`, and two builtin accounts: `alice`
with `admin`+`user` roles, `bob` with only `user`). One endpoint,
`DELETE /reviews/{id}`, is annotated `@RolesAllowed("admin")`; every other
endpoint is untouched. [demo-oidc.sh]({{ site.repo_blob }}/demos/demo-oidc.sh) drives three real password-grant
token requests against the live, randomly-ported Keycloak Dev Service
container (discovered via `docker port`, since Testcontainers binds it to a
random host port) and proves all three outcomes:

1. No bearer token → `401`.
2. Bob's token (valid, but no `admin` role) → `403` — a genuine RBAC check,
   not just "has *a* token".
3. Alice's token (`admin` role) → `204`, and a follow-up `GET` on the same
   id returns `404` — the delete actually took effect, not just returned a
   success code.

This is deliberately the smallest viable OIDC demo in the project — one
module, one protected endpoint — chosen because the capability was judged
worth demonstrating live rather than deferred (this project's convention is
to attempt a live demo and only defer if a laptop-scale budget can't support
it; here it could).

## JBang: prototyping without a Maven module

[demo-jbang-prototype.sh]({{ site.repo_blob }}/demos/demo-jbang-prototype.sh) runs [HelloRoute.java]({{ site.repo_blob }}/demos/jbang/HelloRoute.java) — a
complete Camel route with no `pom.xml` and no Maven reactor module:

```java
public class HelloRoute extends RouteBuilder {
    @Override
    public void configure() throws Exception {
        from("timer:prototype?repeatCount=1")
            .setBody(constant("hello from a jbang prototype"))
            .process(exchange -> {
                String body = exchange.getIn().getBody(String.class);
                exchange.getIn().setBody("JBANG_PROTOTYPE_OK: " + body.toUpperCase());
            })
            .to("log:prototype?showBody=true&showHeaders=false");
    }
}
```

`jbang camel@apache/camel run HelloRoute.java` resolves Camel's runtime
straight from Maven Central and runs the route directly — no `mvn package`,
no project scaffolding. This is the "sketch an idea before committing to a
module" workflow: useful for trying out a route shape, an EIP combination,
or a component configuration before paying the cost of a full Maven module.
The demo asserts the exact transformed marker string appears in the route's
log output, not just that the process exited zero.

## What you learned

- Panache collapses the repository layer into the entity (active record);
  gRPC, GraphQL, and Reactive Messaging each generate or wire their
  boilerplate (stub classes, resolver dispatch, channel binding) so the
  handler code is almost entirely domain logic.
- WebSockets.Next and Reactive Messaging compose naturally — a Kafka
  consumer can push to every open socket connection the moment it commits,
  with no polling.
- Quarkus's reactive and imperative execution models share one Vert.x
  reactor in the same JVM; `@Blocking` is the seam between them, not a
  separate runtime.
- Continuous testing and native compilation sit at opposite ends of the
  feedback-loop spectrum — instant, infra-provisioned test reruns on one
  end, a multi-minute ahead-of-time compile to a JVM-free binary on the
  other — and Dev Services only applies to the former.

The next chapter puts one of these capabilities, native compilation's JVM
twin, head to head against Spring Boot on the numbers that actually matter
for a side-by-side comparison.

---

*Verification status: <span class="status status--verified">verified</span>. `demo-reactive-vertx.sh` (concurrent reactive + imperative calls), `demo-continuous-testing.sh` (6/6), `demo-jbang-prototype.sh`, `demo-oidc.sh` (live Keycloak Dev Service), and the gRPC/GraphQL/REST demos all passed. Native compilation is the one capability not exercised here (no GraalVM/Mandrel in this environment).*
