---
title: "A Quarkus capability tour"
order: 12
part: The Quarkus deep-dive
description: "Twelve Quarkus and JDK 25 capabilities, each anchored to code or a demo script in this project: Panache, gRPC, GraphQL, Reactive Messaging, WebSockets.Next, Vert.x reactive and imperative execution, continuous testing, native image and the JDK AOT cache, OIDC, JBang, and Panama FFM."
duration: 60 minutes
marker: "12"
---

Every chapter so far has used Quarkus as plumbing. This one looks at the
plumbing itself: twelve capabilities, each backed by code or a demo script in
this project. The scope is breadth across REST, RPC, messaging, testing,
startup, security, and tooling. Chapters 13 and 14 build on two of them
(Reactive Messaging and plain bean calls), and chapter 12 measures a third (the
JDK AOT cache).

The code is in [notification-service]({{ site.repo_tree }}/examples/notification-service), [inventory-service]({{ site.repo_tree }}/examples/inventory-service),
[order-service]({{ site.repo_tree }}/examples/order-service), [review-service]({{ site.repo_tree }}/examples/review-service), and
[graphql-gateway]({{ site.repo_tree }}/examples/graphql-gateway). Each section names its demo script. The
script builds, starts, and exercises the capability, and the service's
`README.md` (where one exists) describes how to drive it by hand.

{% include excalidraw.html file="11-capability-tour" alt="Twelve Quarkus and JDK 25 capabilities in a six-by-two grid, each labeled with where it is demonstrated: Panache in order-service, gRPC in inventory-service, GraphQL in graphql-gateway, Reactive Messaging in order-service, WebSockets.Next in notification-service, Vert.x Uni and imperative in inventory-service, continuous testing in order-service, native image in demo-native.sh, JDK AOT cache in compare-quarkus-springboot.sh --aot, OIDC in review-service, JBang in demos/jbang, and Panama FFM in demo-panama.sh" caption="Figure 11.1 — The twelve capabilities and where each is demonstrated" %}

The capabilities are independent; read them in any order. The two that later
chapters depend on are Reactive Messaging (chapter 13's choreography leg
republishes the `OrderEventProducer` shown below) and the orchestration shapes
built on plain bean calls (chapters 13 and 14).

## Panache: the entity is the repository

Hibernate ORM with Panache removes the separate repository layer by default.
`order-service`'s `Order` entity
([Order.java]({{ site.repo_blob }}/examples/order-service/src/main/java/com/patterncatalyst/datamesh/order/Order.java))
extends `PanacheEntityBase` and exposes its columns as public fields:

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

`Order.create(...)` builds the row and `order.persist()`, called from the REST
resource, writes it. Static finders read it back: `inventory-service`'s `Stock`
entity defines `findBySku(String sku)` as `find("sku", sku).firstResult()`,
and [StockResource.java]({{ site.repo_blob }}/examples/inventory-service/src/main/java/com/patterncatalyst/datamesh/inventory/StockResource.java)
calls `Stock.findBySku(request.sku())` straight from the JAX-RS method. Public
fields are safe here because Panache rewrites field access into getter and
setter calls at build time, so Hibernate still sees property access.

{% include excalidraw.html file="11-panache-patterns" alt="Two persistence patterns side by side. Active record, used in this project: the REST resource calls Order.findById and order.persist on the entity, which talks to the database. Repository: the REST resource calls an injected OrderRepository that implements PanacheRepository of Order, which operates on the Order entity and the database. Both use the same Hibernate ORM and SQL." caption="Figure 11.2 — Panache active record (this project) and the repository pattern" %}

### Active record or repository

Panache supports two styles over the same Hibernate ORM and the same SQL:

| | Active record | Repository |
|---|---|---|
| Entity extends | `PanacheEntityBase` (or `PanacheEntity`) | plain JPA entity |
| Queries live in | static methods on the entity | a `PanacheRepository<T>` bean |
| Caller depends on | the entity class | an injected repository |
| Test seam | static calls: use a real database (Dev Services) or mock statics | mock or stub the injected bean |
| Code volume | least | one extra class per aggregate |

Active record fits a service with one aggregate per bounded context and a thin
resource layer, which is how every service in this project is shaped. The
repository style fits teams that enforce layering, want persistence behind an
interface, or keep entities free of framework base classes. An illustrative
repository version of the same lookup (not code from this repo, which uses
active record throughout):

```java
// Illustrative: the repository style. Not part of this project.
@Entity
@Table(name = "orders")
public class Order {              // plain JPA entity, no Panache base class
    @Id public String id;
    // ...
}

@ApplicationScoped
public class OrderRepository implements PanacheRepository<Order> {
    public List<Order> findByCustomer(String customerId) {
        return list("customerId", customerId);
    }
}

@Path("/orders")
public class OrderResource {
    @Inject OrderRepository orders;   // injected, so a test can replace it

    @POST
    @Transactional
    public Response create(OrderRequest request) {
        Order order = Order.create(request.customerId(), request.itemSku(),
                request.quantity(), request.amount());
        orders.persist(order);
        return Response.status(Status.CREATED).entity(order).build();
    }
}
```

The Spring Boot twin ([chapter 12]({{ '/docs/12-quarkus-vs-spring-boot/' | relative_url }})) uses Spring Data JPA, which is the
repository pattern: a `JpaRepository` interface whose query methods are
derived from their names. Both services read and write the identical `orders`
table.

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

`InventoryService` is not hand-written. It is the Mutiny service interface
generated at build time from [inventory.proto]({{ site.repo_blob }}/examples/contracts/src/main/proto/capstone/inventory/v1/inventory.proto).
The `contracts` module is a dependency jar, and
`quarkus.generate-code.grpc.scan-for-proto` tells Quarkus to generate from a
proto packaged inside a dependency as well as from this module's
`src/main/proto`. `@GrpcService` registers the bean as the server's
implementation. `@Blocking` moves this handler to a worker thread because the
Panache lookup is blocking JDBC; the section on Vert.x below explains why the
signature and the annotation are both needed. [demo-grpc.sh]({{ site.repo_blob }}/demos/demo-grpc.sh) drives the
service with `grpcurl` against the `.proto` file (server reflection is also
demonstrated), issuing a unary RPC over HTTP/2.

## GraphQL: one query, two downstream protocols

`graphql-gateway`'s [GatewayApi.java]({{ site.repo_blob }}/examples/graphql-gateway/src/main/java/com/patterncatalyst/datamesh/gateway/GatewayApi.java)
combines two protocols behind a single `/graphql` endpoint:

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

`order(id)` is the top-level query, resolved through a MicroProfile REST
Client call to `order-service`. `stock(...)` is a field resolver:
MicroProfile GraphQL's `@Source` marks it as the resolver for `OrderView`'s
`stock` field, and SmallRye GraphQL calls it only when the query selects that
field. A client asking for `order(id) { customerId }` never triggers the gRPC
call to `inventory-service`. One request spans REST and gRPC, and the second
call is paid per query, not per endpoint. [demo-graphql.sh]({{ site.repo_blob }}/demos/demo-graphql.sh) places an
order, queries the gateway, and asserts that the REST-sourced order fields and
the gRPC-sourced nested `stock` fields arrive in one `.data.order` payload with
no `.errors`.

## Reactive Messaging: Avro events

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

`@Channel("order-placed")` binds the emitter to the Kafka configuration in
[application.properties]({{ site.repo_blob }}/examples/order-service/src/main/resources/application.properties) (topic name, serializer). Reactive Messaging
turns the typed `Emitter<OrderPlaced>.send(...)` call into a Kafka produce, and
the `OrderPlaced` record is serialized as Avro against the Apicurio Schema
Registry. The project sets the Avro serializer explicitly instead of relying
on Quarkus's connector autodetection; chapter 13's choreography leg drives this
producer and reads the Apicurio wire-format magic byte back off the topic. On
the consumer side, `notification-service`'s `OrderPlacedConsumer` uses
`@Incoming("order-placed")` on a `@Transactional` method. Neither side contains
Kafka client code.

## WebSockets.Next: pushing committed events

`notification-service` exposes `/ws/notifications` through [OrderNotificationSocket.java]({{ site.repo_blob }}/examples/notification-service/src/main/java/com/patterncatalyst/datamesh/notification/OrderNotificationSocket.java):

```java
@WebSocket(path = "/ws/notifications")
public class OrderNotificationSocket {

    @OnOpen
    public String onOpen() {
        return "{\"type\":\"connected\"}";
    }
}
```

The endpoint only acknowledges a new connection. The push comes from a Kafka
consumer, [OrderPlacedConsumer.java]({{ site.repo_blob }}/examples/notification-service/src/main/java/com/patterncatalyst/datamesh/notification/OrderPlacedConsumer.java),
the same one from the previous section, after it persists a `Notification` row:

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

`OpenConnections` is WebSockets.Next's injectable registry of live connections.
`listAll()` iterates them and `sendTextAndAwait(...)` serializes the entity to
JSON (Jackson, as the REST layer does) and sends it. The push follows
`notification.persist()` and the transaction commit, so a client never sees an
event that later rolls back. [demo-websocket.sh]({{ site.repo_blob }}/demos/demo-websocket.sh) connects a JDK
`java.net.http.WebSocket` client (run through JBang, see below) before an order
is placed and asserts that the second message on the socket carries the
order's `orderId`, `customerId`, and `itemSku`.

{% include excalidraw.html file="11-websockets-next" alt="Two WebSocket stacks compared. Legacy quarkus-websockets implements the Jakarta WebSocket API on Undertow: a ServerEndpoint class with a Session parameter and callback methods. quarkus-websockets-next runs on Vert.x: a WebSocket annotation with a path, OnOpen and OnTextMessage methods that return values, Uni or Multi, an execution model derived from the method signature, an injectable OpenConnections registry, and a WebSocketClient. A bottom band shows a Kafka Incoming consumer calling OpenConnections.listAll and sendText, with one consumer group per replica." caption="Figure 11.3 — WebSockets.Next compared with the legacy Jakarta WebSocket extension" %}

### Next versus the legacy extension

Quarkus ships two WebSocket extensions. The legacy `quarkus-websockets`
implements the Jakarta WebSocket specification on Undertow: a class annotated
`@ServerEndpoint`, callback methods that receive a `Session`, and message
sending through `session.getAsyncRemote()`. `quarkus-websockets-next` is built
on Vert.x and the Quarkus build-time model:

- `@WebSocket(path = ...)` declares the endpoint, and `@OnOpen`,
  `@OnTextMessage`, and `@OnClose` mark handlers.
- A handler may return a value, a `Uni`, or a `Multi`; the framework sends
  the result back to the client. `onOpen()` above returns a `String` and sends
  it as the first frame.
- The signature selects the thread, as in the next section: a handler that
  returns a plain value is treated as blocking and runs on a worker thread,
  and one that returns `Uni` or `Multi` runs on the event loop. `@Blocking`,
  `@NonBlocking`, and `@RunOnVirtualThread` override it.
- `OpenConnections` is injectable, so code outside the endpoint (a Kafka
  consumer, a scheduled job) can reach every open socket.
- `@WebSocketClient` generates a client from an annotated interface.

### Scaling push across replicas

`OpenConnections` lists only the sockets open in its own JVM. With two
replicas of `notification-service`, an event consumed by replica 1 would not
reach a client connected to replica 2 if both used the shared consumer group
that `OrderPlacedConsumer` uses to split partitions for persistence. The
project adds a second consumer, `OrderPlacedPushConsumer`, on channel
`order-placed-push` with a per-replica group id,
`notification-push-${HOSTNAME}`. A group of one receives every record, so
every replica sees every event and pushes it to its own `OpenConnections`.
Chapter 16 ([Appendix: scaling WebSocket push with Kafka]({{ '/docs/16-websocket-scaling/' | relative_url }})) covers the design, the two-replica verification on Kubernetes, and
what happens when a replica fails.

## Vert.x: reactive and imperative in one JVM

`inventory-service` serves the same `stock` table through two execution models
at once. `InventoryGrpcService.checkStock` (above) returns
`Uni<CheckStockResponse>`, with its blocking Panache lookup moved to a worker
by `@Blocking`. [StockResource.java]({{ site.repo_blob }}/examples/inventory-service/src/main/java/com/patterncatalyst/datamesh/inventory/StockResource.java)
is an imperative JAX-RS resource with no `Uni` anywhere:

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

The two paths compute different results. The gRPC path's `available` depends
on the request (`quantity > 0 && onHand >= quantity`), while the REST path's
`available` is a snapshot (`quantityOnHand > 0`). Asking for more stock than
is on hand can return `available=false` over gRPC for a SKU that REST reports
as available. [demo-reactive-vertx.sh]({{ site.repo_blob }}/demos/demo-reactive-vertx.sh) checks both paths
independently, then fires three gRPC calls and three REST calls concurrently
at the one process and asserts that every response is correct and uncorrelated.

Quarkus runs both styles on one Vert.x instance. `inventory-service` uses a
reactive signature for gRPC because that is the shape `quarkus-grpc`
generates, and an imperative one for REST because the handler is a two-line
lookup that gains nothing from `Uni`. Neither needed a migration or a second
event loop. The framework chooses the thread for each request from the handler
signature and the annotations on it.

### Uni and imperative: what the signature tells Quarkus

`Uni<T>` is Mutiny's type for a single asynchronous result: an item or a
failure, delivered later. It is lazy. Building a `Uni` describes work, and
nothing runs until a subscriber arrives (Quarkus subscribes when it handles the
call). Operators such as `onItem().transform(...)` and `onFailure().retry()`
extend the description without running it. `Uni.createFrom().item(supplier)`
above defers the supplier until subscription.

Vert.x runs a small number of event-loop threads, about twice the CPU count by
default. They multiplex many connections, so any blocking call on one stalls
every request that shares it. Blocking work belongs on the worker pool. Quarkus
picks the thread from the signature:

| Handler | Runs on | Rule |
|---|---|---|
| `StockDto get(String sku)` (REST, plain return) | worker thread | blocking calls are safe |
| `Uni<CheckStockResponse> checkStock(...)` (gRPC) | event loop | must not block |
| the same, plus `@Blocking` | worker thread | blocking calls are safe |
| `@NonBlocking` on a plain return | event loop | opt in to the event loop |
| `@RunOnVirtualThread` | virtual thread | blocking calls are safe and cheap to park |

`checkStock` returns `Uni` because the gRPC interface is generated in Mutiny
form, and it calls Panache's blocking API, so it carries `@Blocking`. Without
the annotation the Panache call would run on the event loop, and Quarkus
rejects it with `BlockingOperationNotAllowedException`; this project hit
exactly that before adding `@Blocking`.
`StockResource.get` needs no annotation: a plain return type already selects a
worker thread.

{% include excalidraw.html file="11-uni-vs-imperative" alt="Two lanes. Imperative lane: StockDto get(sku) runs on a worker thread where blocking is fine. Reactive lane: Uni of CheckStockResponse checkStock(request) runs on the event loop and must not block; adding Blocking moves it to a worker thread. A note explains that a Uni is a lazy single asynchronous result that runs when subscribed, with onItem transform and onFailure retry operators." caption="Figure 11.4 — The handler signature selects the thread" %}

## Continuous testing and Dev Services

`mvn quarkus:dev` with `quarkus.test.continuous-testing=enabled` reruns a
module's tests on every save. Dev Services provisions the Testcontainers those
tests need (Postgres, Kafka, Apicurio) without `docker compose` or a `.env`
file. [demo-continuous-testing.sh]({{ site.repo_blob }}/demos/demo-continuous-testing.sh) starts `order-service`
this way and watches the dev-mode log for the pass banner Quarkus 3.39.5 prints:

```text
All 4 tests are passing (0 skipped), 4 tests were run in 8318ms.
```

The demo parses the passing and run counts and asserts `passing == run`. If the
banner never appears, for example because a later Quarkus release rewords it,
the demo fails. The capability under test is continuous testing reporting a
result, and the HTTP listener starting does not show that.

## Startup: native image and the JDK AOT cache

A JVM service spends its first seconds loading and linking classes, running
them in the interpreter, and compiling hot methods. Three options reduce that
cost, with different trade-offs.

{% include excalidraw.html file="11-startup-paths" alt="Three startup lanes. Plain JVM: load, link, interpret, then JIT warm-up. JVM with AOT cache on JDK 25: a training run with -XX:AOTCacheOutput writes app.aot, production runs with -XX:AOTCache, same jar, full JVM, JIT still active. Native image with GraalVM or Mandrel: a closed-world build that takes minutes, no JVM at runtime, reflection requires configuration. Rows compare build cost, startup, memory, compatibility, and peak throughput qualitatively." caption="Figure 11.5 — Three ways to start a Java service" %}

**Native image.** [demo-native.sh]({{ site.repo_blob }}/demos/demo-native.sh) compiles `order-service` to a
native executable. It first looks for a local GraalVM or Mandrel
`native-image`, falls back to `-Dquarkus.native.container-build=true` (a
Docker-based Mandrel builder), and fails if neither is available instead of
building a JVM jar and calling it native. The result is a `*-runner` binary
with no JVM in the process: fast startup and a small resident set. The
costs are a build that takes minutes, a closed-world assumption (reflection,
resources, and dynamic proxies must be known at build time, which Quarkus
extensions register for you), and different peak-throughput characteristics
because there is no JIT. The demo runs the binary against a throwaway Postgres
container (native mode gets no Dev Services; the `%prod` profile expects a
reachable database) and asserts that `GET /orders` returns a JSON array through
the full REST, Hibernate ORM, and Panache stack.

**JDK AOT cache (Project Leyden).** JDK 25 can record loaded and linked
classes in a training run (`-XX:AOTCacheOutput=app.aot`, JEPs 483 and 514) and
map them at the next launch (`-XX:AOTCache=app.aot`). It is the same jar on
the same JVM with the JIT intact, so compatibility is unchanged and peak
throughput is unaffected; the cache must be built with the same JDK and
classpath it is used with. Chapter 12's section [Like-for-like with the JDK 25 AOT cache (Project Leyden)]({{ '/docs/12-quarkus-vs-spring-boot/' | relative_url }}#like-for-like-with-the-jdk-25-aot-cache-project-leyden)
measures it on both services with `compare-quarkus-springboot.sh --aot`. In a
single run on Temurin 25.0.3, self-reported startup fell from 2.045 s to
0.992 s for Quarkus and from 4.018 s to 1.021 s for Spring Boot, so most of the
gap between the frameworks closes. Resident memory moved the other way for
Quarkus (337 to 372 MB, with the mapped cache counted) and down for Spring (548
to 446 MB). The caches were 103 MB and 123 MB.

Native image removes the JVM and costs the most to build. The AOT cache keeps
the JVM and reduces startup without changing the deployment model. Plain JVM
mode remains the baseline.

## OIDC: bearer tokens against Keycloak

`review-service` uses `quarkus-oidc` with no `quarkus.oidc.*` properties. With
no `auth-server-url` set, Dev Services starts a disposable Keycloak container
in dev and test mode (realm `quarkus`, client `quarkus-app` with secret
`secret`, and two accounts: `alice` with the `admin` and `user` roles, `bob`
with `user` only) and configures the application against it. One endpoint,
`DELETE /reviews/{id}`, carries `@RolesAllowed("admin")`:

```java
@DELETE
@Path("/{id}")
@Consumes(MediaType.WILDCARD)
@Transactional
@RolesAllowed("admin")
public Response delete(@PathParam("id") Long id) {
    Review review = Review.findById(id);
    if (review == null) {
        return Response.status(Status.NOT_FOUND).build();
    }
    review.delete();
    return Response.noContent().build();
}
```

{% include excalidraw.html file="11-oidc-token-flow" alt="Token flow. Dev Services starts Keycloak with realm quarkus and users alice (admin and user) and bob (user). Step 1: the client posts to the token endpoint with the password grant and client quarkus-app. Step 2: Keycloak returns a JWT access token. Step 3: the client calls DELETE /reviews/{id} with an Authorization Bearer header. review-service verifies the signature against the Keycloak JWKS, the issuer, and the expiry, then applies RolesAllowed admin. Outcomes: no token returns 401, bob returns 403, alice returns 204 and a following GET returns 404." caption="Figure 11.6 — How OIDC protects review-service" %}

The flow, as [demo-oidc.sh]({{ site.repo_blob }}/demos/demo-oidc.sh) exercises it against the Keycloak container (found
with `docker port`, because Testcontainers binds a random host port):

1. The client posts to Keycloak's token endpoint
   (`/realms/quarkus/protocol/openid-connect/token`) with the password grant
   for client `quarkus-app`.
2. Keycloak returns a signed JWT access token.
3. The client calls `DELETE /reviews/{id}` with `Authorization: Bearer <token>`.
4. `quarkus-oidc` verifies the signature against Keycloak's published keys
   (JWKS), the issuer, and the expiry. Then `@RolesAllowed("admin")` checks
   the roles in the token.

Three outcomes:

1. No bearer token: `401`, authentication failed.
2. Bob's token (valid, `user` role only): `403`, authenticated but not authorized.
3. Alice's token (`admin`): `204`, and a following `GET` on the same id returns
   `404`, confirming the delete took effect.

The password grant is used here because it needs no browser. Browser
applications use the authorization code flow. The demo is the smallest OIDC
case in the project: one module and one protected endpoint, run live.

## JBang: environment tooling

JBang runs a single `.java` file without a build file. Dependencies and the
required JDK are declared in comment directives at the top of the file:
`//DEPS group:artifact:version` resolves a library from Maven Central, and
`//JAVA 25+` selects the JDK. JBang downloads a matching JDK if none is
installed and caches the compiled result. It also launches catalog apps such as
`camel@apache/camel`, so tools run without a global install.

{% include excalidraw.html file="11-jbang-tooling" alt="A single Java file with DEPS and JAVA 25 directives is run by jbang, which resolves dependencies from Maven Central, downloads a JDK if missing, and caches the build. The app catalog launches camel@apache/camel and the Quarkus CLI. Uses in this project: HelloRoute.java, WsNotificationClient.java, and PanamaFfm.java." caption="Figure 11.7 — JBang as environment tooling" %}

Three scripts in [demos/jbang]({{ site.repo_tree }}/demos/jbang) use it:

| Script | Used by | Purpose |
|---|---|---|
| `HelloRoute.java` | `demo-jbang-prototype.sh` | A Camel route with no Maven module |
| `WsNotificationClient.java` | `demo-websocket.sh` | A dependency-free WebSocket client on the JDK's `java.net.http` |
| `PanamaFfm.java` | `demo-panama.sh` | Native calls through the FFM API (next section) |

[demo-jbang-prototype.sh]({{ site.repo_blob }}/demos/demo-jbang-prototype.sh) runs [HelloRoute.java]({{ site.repo_blob }}/demos/jbang/HelloRoute.java), a complete
Camel route with no `pom.xml`:

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

`jbang camel@apache/camel run HelloRoute.java` resolves Camel from Maven
Central and runs the route with no `mvn package` and no project scaffolding.
That makes it a quick way to try a route shape, an EIP combination, or a
component configuration before creating a module. The demo asserts that the
exact transformed marker string appears in the route's log output.

## Panama: calling native code through the FFM API

The Foreign Function and Memory API (Project Panama, JEP 454, final in JDK 22)
lets Java call C functions and manage off-heap memory with no JNI. JNI requires
a C glue library, a generated header, and a separate native build for each
platform. FFM needs only Java.

{% include excalidraw.html file="11-panama-ffm" alt="Java calls Linker.nativeLinker, whose defaultLookup finds libc symbols. downcallHandle with a FunctionDescriptor produces a method handle for getpid and strlen. An Arena allocates an off-heap MemorySegment holding a C string and frees it when the arena closes. A contrast box notes that JNI needs C glue, headers, and a separate native build. A note mentions the enable-native-access flag." caption="Figure 11.8 — Calling libc through the FFM API" %}

The script [PanamaFfm.java]({{ site.repo_blob }}/demos/jbang/PanamaFfm.java) calls two libc functions:

```java
///usr/bin/env jbang "$0" "$@" ; exit $?
//JAVA 25+
//JAVA_OPTIONS --enable-native-access=ALL-UNNAMED

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;

public class PanamaFfm {

    public static void main(String[] args) throws Throwable {
        Linker linker = Linker.nativeLinker();
        SymbolLookup libc = linker.defaultLookup();

        // int getpid(void)
        MethodHandle getpid = linker.downcallHandle(
                libc.find("getpid").orElseThrow(),
                FunctionDescriptor.of(JAVA_INT));

        // size_t strlen(const char *s)
        MethodHandle strlen = linker.downcallHandle(
                libc.find("strlen").orElseThrow(),
                FunctionDescriptor.of(JAVA_LONG, ADDRESS));

        int nativePid = (int) getpid.invokeExact();
        System.out.println("PANAMA_GETPID=" + nativePid + " JVM_PID=" + ProcessHandle.current().pid());

        String text = "data mesh on Quarkus — héllo";
        // The arena owns the off-heap C string and frees it when it closes.
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment cString = arena.allocateFrom(text);
            long nativeLen = (long) strlen.invokeExact(cString);
            System.out.println("PANAMA_STRLEN=" + nativeLen
                    + " JAVA_LENGTH=" + text.getBytes(StandardCharsets.UTF_8).length);
        }
    }
}
```

The pieces, in the order the code uses them:

- **`Linker.nativeLinker()`** is the linker for the current platform's C calling
  convention. It creates the Java-to-native bridge.
- **`SymbolLookup`** finds a function's address from its name. `defaultLookup()`
  searches the libraries the platform loads by default, which on Linux and
  macOS includes libc. That is why the demo runs on those two systems and not
  on Windows.
- **`FunctionDescriptor`** describes the C signature with value layouts: `getpid`
  takes nothing and returns a `JAVA_INT`, and `strlen` takes an `ADDRESS` (a
  pointer) and returns a `JAVA_LONG` (`size_t`).
- **`downcallHandle`** combines an address and a descriptor into a
  `MethodHandle`. `invokeExact` calls it with the exact static types, hence the
  `(int)` and `(long)` casts.
- **`Arena`** and **`MemorySegment`** manage off-heap memory. `allocateFrom(text)`
  copies the string into a NUL-terminated UTF-8 segment owned by the arena, and
  closing the confined arena frees it. A segment cannot be used after its arena
  closes, so use-after-free is an exception rather than a crash.
- **`--enable-native-access=ALL-UNNAMED`** (set through `//JAVA_OPTIONS`)
  acknowledges that this code performs restricted native operations. Without
  it, JDK 25 prints a warning on the first native call.

The `strlen` result counts UTF-8 bytes, which is why the demo compares it with
the string's UTF-8 byte length, not its character count.
[demo-panama.sh]({{ site.repo_blob }}/demos/demo-panama.sh) runs the script and asserts that both pairs match.
Output from a run on JDK 25.0.3 with JBang 0.138.0:

```text
PANAMA_GETPID=867684 JVM_PID=867684
PANAMA_STRLEN=31 JAVA_LENGTH=31
```

To run it, install JBang and execute `demos/demo-panama.sh` from the repository
root, or run `jbang demos/jbang/PanamaFfm.java` directly.

## What you learned

- Panache's active record style removes the repository layer; the repository
  style (`PanacheRepository`, or Spring Data in the twin) trades extra code for
  an injectable seam. Both use the same Hibernate ORM.
- gRPC, GraphQL, and Reactive Messaging generate or wire their boilerplate
  (stubs, resolver dispatch, channel binding), so handler code is mostly
  domain logic.
- WebSockets.Next replaces the Jakarta/Undertow extension with Vert.x-based
  handlers whose return types set the execution model. A Kafka consumer can
  push through `OpenConnections` after a commit, and one consumer group per
  replica makes the push work across replicas.
- `Uni` is a lazy single asynchronous result. The handler signature and
  `@Blocking`, `@NonBlocking`, or `@RunOnVirtualThread` decide whether code runs
  on the event loop, a worker, or a virtual thread, in one JVM.
- Native image removes the JVM at the cost of a closed-world build. The JDK 25
  AOT cache cuts startup on the same jar with the JIT intact, and chapter 12
  measures both frameworks with it.
- OIDC with Dev Services needs no configuration in dev: bearer token to
  `401`, `403`, or `204` through `@RolesAllowed`.
- JBang is environment tooling for single-file scripts, and the FFM API calls
  native code from Java with no JNI.

The next chapter compares the JVM mode of `order-service` with its Spring Boot
twin on startup and memory, with and without the AOT cache.

---

*Verification status: <span class="status status--verified">verified</span>. `demo-reactive-vertx.sh` (concurrent reactive and imperative calls), `demo-continuous-testing.sh` (6/6), `demo-jbang-prototype.sh`, `demo-oidc.sh` (live Keycloak Dev Service), `demo-panama.sh` (JDK 25.0.3, JBang 0.138.0: `getpid` and `strlen` results match the JVM's own), and the gRPC, GraphQL, and REST demos passed. The AOT cache numbers are measured in chapter 12 from a single run. Native image is not exercised in this pass (no GraalVM or Mandrel in this environment). Figures 11.2 through 11.8 are explanatory diagrams; the illustrative `PanacheRepository` example is not run code.*
