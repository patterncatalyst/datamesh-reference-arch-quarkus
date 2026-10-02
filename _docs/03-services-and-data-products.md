---
title: "Services & data products"
order: 4
part: Building data products
description: "The anatomy of a data product, order-service as the template built end to end, and inventory/review as further products that demonstrate the pattern varying by role."
duration: 30 minutes
marker: "04"
---

A data mesh's central claim is that a domain team ships data the same way it
ships a service: as an independently deployable, independently owned unit
with its own storage, its own API, and its own contract. This chapter makes
that claim concrete in Quarkus. It builds one service, order-service, all
the way through — entity, REST resource, a synchronous call to another
service, an event publish — as the template the rest of the mesh repeats,
then shows two more services, inventory-service and review-service, that
reuse the same shape while varying the protocol surface to fit their role.

The code is in `examples/order-service/`, `examples/inventory-service/`, and
`examples/review-service/`. `demos/demo-order.sh` builds and runs
order-service and inventory-service together and drives a real order through
them; its narration in the script header covers what it proves and the
sharp edges hit wiring it up.

## What a data product looks like here

In the abstract, a data product is the *architectural quantum* of a data
mesh: the smallest independently deployable unit that carries everything it
needs to do its job — input ports where data comes in, output ports where it
serves data out, the transformation between them, and enough self-description
that another domain can find it, understand its shape, and depend on it
safely.

Figure 3.1 draws that quantum exactly as the data mesh literature does: input
and output ports where data crosses the product's boundary, three structural
pieces doing the work inside — code (pipelines, APIs, policy-as-code), data &
metadata (polyglot storage, schema, SLOs), and infrastructure (build, deploy,
run, serve) — and a control port layered on top carrying governance, SLOs,
and access policy, plus the checklist a product is expected to satisfy:
discoverable, addressable, understandable, trustworthy, natively accessible,
interoperable, valuable on its own, and secure.

{% include excalidraw.html file="03-data-product-anatomy" alt="Diagram of a data product's architectural quantum: input and output ports, the code, data and infrastructure components inside, and a governance control port on top" caption="Figure 3.1 — The data product architectural quantum" %}

In this project, that abstraction is concrete: **each domain service *is* a
data product.** It owns a slice of Postgres (its internal state), serves
data through its REST/gRPC endpoints (output ports), optionally accepts
synchronous calls or Kafka events as input, and — from the next chapter on —
publishes a versioned contract so other domains can depend on its shape
without reading its source. The service boundary and the data-product
boundary are the same boundary, which is what keeps domain ownership real
instead of aspirational.

| Service | Owns | Surface |
|---|---|---|
| `order-service` | the `orders` table, the order lifecycle | REST in (`POST/GET /orders`), gRPC out to inventory-service, publishes `order.placed` |
| `inventory-service` | the `stock` table | gRPC server (`CheckStock`), plus a REST demo surface (`/stock`) for seeding and inspection |
| `review-service` | product reviews, keyed by SKU | REST only (`/reviews`), with one admin-only endpoint protected by OIDC |
| `notification-service` | notifications, derived from events | Kafka consumer only, pushes to WebSocket clients |
| `payment-service` / `shipping-service` | payments / shipments | Kafka consumer → processor → Kafka producer, no externally callable API at all |
| `graphql-gateway` | nothing of its own | GraphQL only, composing REST + gRPC from other services |

The variation is deliberate, not accidental: **a service exposes the
protocols its role needs, not a uniform surface.** `notification-service`
and the payment/shipping pair are event-only because their job is to react,
not to be called; `review-service` is REST-only because it has no
cross-service synchronous dependency; `order-service` needs both REST (for
clients) and a gRPC client (to validate stock before committing). The
reasoning behind *which* protocol fits which job is the subject of the next
two chapters — contracts, then the data planes themselves.

Each service owns its own Postgres schema/database in the shared compose
stack (`orderdb`, `inventorydb`, and so on — see `infra/db/init` and each
service's `application.properties`). One cluster, one database per service
is what makes "per-service data ownership" real without running a fleet of
database instances for a learning project.

## order-service: the template, built end to end

Rather than build all the services a layer at a time, the template is built
all the way through first: entity → persistence → a synchronous dependency
on another service → an event publish. Once that spine is proven, the
remaining services are the same shape with different payloads.

### The entity: `Order`

```java
@Entity
@Table(name = "orders")
public class Order extends PanacheEntityBase {

    @Id
    @Column(length = 36, nullable = false, updatable = false)
    public String id;

    @Column(name = "customer_id", nullable = false)
    public String customerId;

    @Column(name = "item_sku", nullable = false)
    public String itemSku;

    @Column(nullable = false)
    public int quantity;

    @Column(nullable = false, precision = 12, scale = 2)
    public BigDecimal amount;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    public OrderStatus status;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    public static Order create(String customerId, String itemSku, int quantity, BigDecimal amount) {
        Order order = new Order();
        order.id = UUID.randomUUID().toString();
        order.customerId = customerId;
        order.itemSku = itemSku;
        order.quantity = quantity;
        order.amount = amount;
        order.status = OrderStatus.PLACED;
        order.createdAt = Instant.now();
        return order;
    }
}
```

This is Hibernate ORM with Panache in its **active-record** style: the
entity extends `PanacheEntityBase` and carries its own persistence
operations (`persist()`, `findById()`, `listAll()`) rather than routing
through a separate repository class. `PanacheEntityBase` (not the shorter
`PanacheEntity`) is the right base here because the primary key is a
`String` UUID the application assigns itself (`UUID.randomUUID()`), not the
auto-generated `Long id` that `PanacheEntity` bakes in — order-service needs
control over its own id generation so the id can be returned to the client
immediately, before any round trip, and so it can later travel unchanged
into the `order.placed` event as `order_id`.

`status` is a Java enum (`OrderStatus`) persisted with
`@Enumerated(EnumType.STRING)` rather than `ORDINAL`. Storing the name
(`"PLACED"`) instead of the ordinal position (`0`) means adding a new status
later, or reordering the enum, can't silently reinterpret existing rows as
the wrong status — a real risk with `ORDINAL` that costs nothing to avoid up
front.

The `create(...)` static factory is the one place an `Order` gets built: it
assigns the id, defaults `status` to `PLACED`, and stamps `createdAt` —
centralizing those decisions so `OrderResource` only ever calls `create(...)`
and `persist()`, never assembles a half-initialized `Order` by hand.

### The REST resource: validate, persist, publish

```java
@Path("/orders")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class OrderResource {

    @Inject
    InventoryClient inventoryClient;

    @Inject
    OrderEventProducer eventProducer;

    @POST
    @Transactional
    public Response placeOrder(OrderCreate payload) {
        CheckStockResponse stock;
        try {
            stock = inventoryClient.checkStock(payload.itemSku(), payload.quantity());
        } catch (StatusRuntimeException e) {
            return Response.status(Response.Status.SERVICE_UNAVAILABLE)
                    .entity("inventory-service unreachable: " + e.getMessage())
                    .build();
        }

        if (!stock.getAvailable()) {
            return Response.status(Response.Status.CONFLICT)
                    .entity("insufficient stock for %s (%d on hand)"
                            .formatted(payload.itemSku(), stock.getQuantityOnHand()))
                    .build();
        }

        Order order = Order.create(payload.customerId(), payload.itemSku(), payload.quantity(), payload.amount());
        order.persist();

        eventProducer.publish(order).exceptionally(ex -> {
            LOG.warnf(ex, "failed to publish order.placed for %s", order.id);
            return null;
        });

        return Response.status(Response.Status.CREATED).entity(toDto(order)).build();
    }

    @GET
    public List<OrderDto> listOrders() {
        return Order.<Order>listAll(Sort.by("createdAt").descending())
                .stream()
                .map(OrderResource::toDto)
                .toList();
    }

    @GET
    @Path("/{id}")
    public Response getOrder(@PathParam("id") String id) {
        Order order = Order.findById(id);
        if (order == null) {
            return Response.status(Response.Status.NOT_FOUND).build();
        }
        return Response.ok(toDto(order)).build();
    }
}
```

`placeOrder` is the whole data-product transformation in one method, and
the order of its three steps is load-bearing, not incidental:

1. **Check stock first, over gRPC, before touching Postgres.** `checkStock`
   is a blocking call into `InventoryClient` (covered next), and a failure
   there — `StatusRuntimeException`, meaning inventory-service is
   unreachable or erroring — returns `503` immediately. No row is written.
   This is a deliberate **fail-closed** choice: the method would rather
   refuse an order it can't validate than persist one it isn't sure about.
   If stock comes back but isn't `available`, that's a `409 Conflict`, not a
   `503` — the dependency answered, it just said no.
2. **Persist only after the gRPC call succeeds.** `Order.create(...)` builds
   the aggregate and `order.persist()` writes it, inside the method's
   `@Transactional` boundary (Quarkus's CDI interceptor-backed
   `jakarta.transaction.Transactional`, which wraps the method in a JTA
   transaction and commits on normal return). By the time `persist()`
   returns inside that boundary, the order is durably committed.
3. **Publish the event only after persistence, and never let a publish
   failure undo or fail the request.** `eventProducer.publish(order)`
   returns a `CompletionStage<Void>`; `.exceptionally(...)` attaches a
   logging-only handler and the method does not `await` the publish at all.
   The order has already been committed by the time publish is attempted, so
   a broker outage must not turn into a failed `POST` for work that already
   succeeded. The cost of that choice — a window where the order is
   committed but the event never arrives — is the **dual-write gap**, and
   the comment in `OrderEventProducer` names its production answer plainly:
   the outbox pattern, which this template does not implement. That's a
   fragile edge worth seeing clearly.

`listOrders` and `getOrder` are the read side: `listAll(Sort.by(...))` is
Panache's query builder returning rows newest-first, and `findById` returns
`null` on a miss rather than throwing, which is why `getOrder` checks for
`null` and maps it to a `404` explicitly instead of catching an exception.

### The one synchronous dependency: `InventoryClient`

```java
@ApplicationScoped
public class InventoryClient {

    private static final Duration CALL_TIMEOUT = Duration.ofSeconds(3);

    @GrpcClient("inventory")
    InventoryService inventoryService;

    public CheckStockResponse checkStock(String sku, int quantity) {
        CheckStockRequest request = CheckStockRequest.newBuilder()
                .setSku(sku)
                .setQuantity(quantity)
                .build();
        return inventoryService.checkStock(request)
                .await().atMost(CALL_TIMEOUT);
    }
}
```

`@GrpcClient("inventory")` wires `quarkus-grpc` to inject a client stub for
the channel named `inventory` (configured in `application.properties`,
pointed at inventory-service's gRPC port). `InventoryService` here is not
hand-written — it's the **Mutiny-flavored service interface quarkus-grpc
generates at build time** from `capstone/inventory/v1/inventory.proto`,
which order-service never defines itself; it's scanned out of the
`contracts` module's packaged jar (more on that mechanism in the next
chapter). Because the generated interface is Mutiny-based, the call returns
a `Uni<CheckStockResponse>`, and `.await().atMost(CALL_TIMEOUT)` is what
turns that reactive, non-blocking call into the plain blocking return value
`OrderResource`'s worker-thread method needs — with a hard 3-second ceiling
so a hung inventory-service can't hang an order request indefinitely. An
`await()` with no timeout at all would trade that bounded failure for an
unbounded one; the timeout is what keeps "inventory-service is slow" from
becoming "order-service is slow."

### Publishing the event

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
                .setCustomerId(order.customerId)
                .setItemSku(order.itemSku)
                .setQuantity(order.quantity)
                .setAmount(order.amount.toPlainString())
                .setStatus(order.status.name())
                .setCreatedAt(DateTimeFormatter.ISO_INSTANT.format(order.createdAt))
                .build();
        return emitter.send(event);
    }
}
```

`@Channel("order-placed")` binds this `Emitter<OrderPlaced>` to the outgoing
channel configured in `application.properties`, which maps `order-placed` to
the real `order.placed` Kafka topic and — critically — pins
`value.serializer` **explicitly** to Apicurio's Avro serializer rather than
leaving Quarkus to autodetect one. The code comment on this class documents
exactly why that explicitness matters: two Apicurio artifacts share the
`io.apicurio.registry.serde.avro` package, a split-package situation that
was proven to defeat Quarkus's autodetection and silently fall back to a
JSON serializer instead — which would quietly break the Avro-on-the-wire
guarantee the next chapter depends on. `OrderPlaced` itself is a generated
Avro `SpecificRecord`, not hand-written either; it comes from the
`contracts` module, which is where the next chapter picks up. `emitter.send`
returns the `CompletionStage<Void>` that `OrderResource` treats as
best-effort, closing the loop back to the publish-after-commit ordering
above.

## Further products: inventory-service and review-service

`inventory-service` and `review-service` repeat the exact same shape —
Panache entity, REST (and here, gRPC) resource — while exposing a different
surface because their role is different.

`inventory-service`'s `Stock` entity is a plain auto-increment `Long` id
(`PanacheEntityBase` again, but note the business key is `sku`, looked up
via an active-record finder):

```java
@Entity
@Table(name = "stock", uniqueConstraints = @UniqueConstraint(columnNames = "sku"))
public class Stock extends PanacheEntityBase {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    public Long id;

    @Column(name = "sku", nullable = false, unique = true, length = 64)
    public String sku;

    @Column(name = "quantity_on_hand", nullable = false)
    public int quantityOnHand;

    public static Stock findBySku(String sku) {
        return find("sku", sku).firstResult();
    }
}
```

Its **primary** surface is a gRPC server, not REST, because its only
required consumer is order-service's synchronous `CheckStock` call:

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

`@GrpcService` registers this class as the server-side implementation of the
`InventoryService` contract (the same generated interface order-service
calls as a client). `@Blocking` matters here: the Panache call
(`Stock.findBySku`) is a blocking Hibernate/JDBC call, and without
`@Blocking` quarkus-grpc would invoke this method on its reactive I/O
thread, where a blocking JDBC round trip would stall that thread and
threaten the whole event loop. `@Blocking` tells Quarkus to dispatch this
method onto a worker thread instead, where blocking is safe — the same
concern `InventoryClient`'s bounded `await()` addresses from the other
direction.

`inventory-service` also exposes a small REST surface, `StockResource`
(`POST /stock` to seed, `GET /stock` / `GET /stock/{sku}` to inspect) — but
its own Javadoc is explicit that this is **not part of the cross-service
contract**; it's a demo/test convenience, and the real inter-service
dependency is the gRPC call above. That distinction — a demo-facing REST
endpoint existing beside the real production surface — matters precisely
because it would be easy to mistake a convenience endpoint for
the contract.

`review-service` goes the other direction: REST-only, because it has no
synchronous cross-service dependency to satisfy, plus one endpoint that
doubles as this project's OIDC demo:

```java
@DELETE
@Path("/{id}")
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

`@RolesAllowed("admin")` is Jakarta's standard role-based access-control
annotation; Quarkus's OIDC extension wires it to the bearer token's roles
claim, so a request with no token gets `401`, and one with a token lacking
the `admin` role gets `403` — all before this method body ever runs. It's
the smallest possible illustration that a data product's surface can carry
its own authorization policy, scoped to exactly the operation that needs it
(creating and reading reviews stays open; moderating them doesn't). This is
Figure 3.1's control port made literal: the governance layer the diagram
draws wrapping the product isn't a separate component bolted on here — it's
a single annotation on the one method that needs it.

## Build, run, observe

```bash
cd demos && ./demo-order.sh
```

The script brings up the compose baseline (Postgres, Kafka, Apicurio) and
packages and starts `inventory-service` and `order-service` as packaged JVM
processes against that real infrastructure — deliberately not
`quarkus:dev`, so the `%prod`-profiled config pointing at the compose stack
is what actually runs. It then drives a real order through the stack:

1. Seed a SKU via `POST /stock`.
2. Place an order: `POST /orders` for two `WIDGET-1` units, and confirm
   `201 Created` with `status: PLACED`.
3. `GET` the same order back by id.
4. Confirm `GET /orders` lists it.
5. Query the `orders` table directly with `psql` to confirm the row exists
   independent of the REST layer.

The template also handles two real production-readiness edges that only
surface in a packaged (non-dev) deployment, both wired in by default: the
order-service→inventory-service gRPC call targets a single canonical port
(`9000`, env-overridable on both sides via `INVENTORY_GRPC_HOST` /
`INVENTORY_GRPC_PORT`), and the packaged JVM trusts the Avro event package
via `org.apache.avro.SERIALIZABLE_PACKAGES` set in the container image's
`JAVA_TOOL_OPTIONS` — without which Avro's `ClassSecurityValidator` would
silently drop every `order.placed` publish from a non-dev JVM. Both matter
for any real deployment of this template.

## What you learned

- A data product in this project is a service: its own Postgres schema, its
  own REST/gRPC surface, its own Kafka publish — the service boundary *is*
  the data-product boundary.
- `order-service`'s `placeOrder` shows the load-bearing ordering a data
  product's write path needs: validate a synchronous dependency first
  (fail closed), persist only after that succeeds, and publish only after
  persistence — with a publish failure never undoing or failing the
  already-committed write.
- Each service's protocol surface matches its role rather than a
  house-wide template: `inventory-service` is gRPC-first because that's
  what its one real consumer needs; `review-service` is REST-only with
  endpoint-scoped OIDC authorization because it has no synchronous
  dependency to satisfy.

With real services shipping real data, the next question is how other
domains find them, trust their shape, and know it won't change without
warning — contracts and the catalog.

---

*Verification status: <span class="status status--verified">verified</span>. `mvn verify` is green (`OrderResourceTest`, `InventoryGrpcServiceTest`, `OrderPlacedAvroWireIT`, `InventoryCheckStockWireIT`), and `demo-order.sh` and `demo-grpc.sh` passed end to end against a freshly started compose stack.*
