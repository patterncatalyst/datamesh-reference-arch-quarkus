---
title: "The data planes"
order: 6
part: Building data products
description: "The asynchronous Kafka backbone and the synchronous GraphQL read layer that federates REST and gRPC — two planes, and why Camel's EIPs are the right lens for the routing logic inside each."
duration: 30 minutes
marker: "06"
---

The previous chapter covered how service contracts are registered and enforced. This
chapter covers how data moves between services — the planes the mesh runs on. There are
two: an **asynchronous event backbone** on Kafka, and a **synchronous read
layer** where a GraphQL gateway composes REST and gRPC calls into one
response. Both are running code in this project, and both can be read
through Apache Camel's enterprise integration patterns (EIPs), which is where this
project's Camel-on-Quarkus work appears.

The code is in [order-service]({{ site.repo_tree }}/examples/order-service) (the producer side, already built
in the first chapter of this part), [notification-service]({{ site.repo_tree }}/examples/notification-service), and
[graphql-gateway]({{ site.repo_tree }}/examples/graphql-gateway). [demo-kafka.sh]({{ site.repo_blob }}/demos/demo-kafka.sh), [demo-graphql.sh]({{ site.repo_blob }}/demos/demo-graphql.sh),
and [demo-grpc.sh]({{ site.repo_blob }}/demos/demo-grpc.sh) exercise each piece; [demo-camel-integration.sh]({{ site.repo_blob }}/demos/demo-camel-integration.sh)
exercises the Camel route this chapter closes with.

Figure 5.1 previews the chapter: four protocols, each chosen for the job it fits
rather than by house-wide mandate.

| Protocol | Job it fits | Contract type | Quarkus extension |
|---|---|---|---|
| REST | client-facing edge | OpenAPI | `quarkus-rest` |
| gRPC | service-to-service calls | Protobuf | `quarkus-grpc` |
| GraphQL | composing reads across domains | GraphQL SDL | `quarkus-smallrye-graphql` |
| Events | asynchronous reactions | Avro | Reactive Messaging |

The rest of this chapter builds the async and sync halves in running code, returns to
the fitness argument, and closes with Camel's EIPs for the routing logic inside either
half.

{% include excalidraw.html file="05-api-implementations" alt="Diagram of four protocols — REST, gRPC, GraphQL, and events — each matched to the job it fits best, its contract type, and the Quarkus extension that implements it" caption="Figure 5.1 — Four protocols, four contracts, each by fitness" %}

## The async backbone: domains reacting to events

The read layer, covered below, is request-and-response: a consumer asks, a
service answers, the caller waits. The event backbone is the opposite shape,
and it lets order-service avoid calling every interested domain
synchronously. `order-service`'s `OrderEventProducer` (built in the previous
chapter) publishes `order.placed` after an order is committed and does not
know who is listening. `notification-service` is a consumer with no
inbound API of its own:

```java
@ApplicationScoped
public class OrderPlacedConsumer {

    @Inject
    OpenConnections wsConnections;

    @Incoming("order-placed")
    @Transactional
    public void consume(OrderPlaced event) {
        String orderId = event.getOrderId();
        if (Notification.findByOrderId(orderId) != null) {
            LOG.infof("skipping duplicate delivery for order %s", orderId);
            return;
        }

        Notification notification = new Notification();
        notification.orderId = orderId;
        notification.eventType = event.getEventType();
        notification.customerId = event.getCustomerId();
        notification.itemSku = event.getItemSku();
        notification.quantity = event.getQuantity();
        notification.amount = parseAmount(event.getAmount());
        notification.status = event.getStatus();
        notification.createdAt = parseCreatedAt(event.getCreatedAt());
        notification.persist();

        wsConnections.listAll().forEach(connection -> connection.sendTextAndAwait(notification));
    }
}
```

`@Incoming("order-placed")` is SmallRye Reactive Messaging's counterpart to
`OrderEventProducer`'s `@Channel("order-placed")` — the same logical channel
name, mapped in each service's own `application.properties` to the same
physical `order.placed` Kafka topic, with each side free to use a different
local channel-to-topic mapping if it needed to. `@Transactional` does
double duty: it gives the Hibernate write a transaction boundary, and, because
SmallRye Reactive Messaging treats a `@Transactional` message
handler as blocking, it lets this method
do a blocking Panache write without a separate `@Blocking`
annotation, the same concern `InventoryGrpcService.checkStock` addressed
explicitly with `@Blocking` in the previous chapter.

The idempotency check (`Notification.findByOrderId(orderId) != null`) is
there because Kafka's delivery guarantee here is **at-least-once**: the same
`order.placed` message can be redelivered (after a consumer restart mid-batch,
for instance), and without this guard a redelivery would create a duplicate
notification. Checking for an existing row first and returning early makes
the write **idempotent** — the Javadoc on this class notes that this
mirrors the Python reference's `ON CONFLICT DO NOTHING` behavior, expressed as an
application-level check instead of a database constraint.

The last line — pushing the freshly persisted `Notification` to every open
WebSocket connection via `OpenConnections` (Quarkus WebSockets.Next) — turns
this from a consumer that writes rows into a live notification
feed: a client connected to `/ws/notifications` sees the notification when
this method commits it, not on the next poll. The push is
best-effort: a client that isn't connected misses it, with no retry or queued
delivery. That suits a live feed and not anything needing guaranteed
delivery, which belongs to the Kafka topic, not this fan-out.

Figure 5.2 names the seam `OrderPlacedConsumer` crosses on every message:
`OrderPlaced` is an immutable event — a fact that an order *was* placed — and the
`Notification` row it becomes is a stateful entity, queryable and updatable. The
diagram continues the refinement into aggregates and a published analytical view; this
project stops at the entity step. Nothing here aggregates or republishes
notifications for analytical consumption, and no CDC or streaming ingestion
layer — Figure 5.3's territory — exists in this repository to pick up raw
change data from `orders` or `notifications`; both diagrams describe the target shape
of an analytical plane that this project's operational services would feed, not code
that runs today.

{% include excalidraw.html file="05-analytical-data-composition" alt="Diagram showing operational data refined through events and entities into a published data product that analytics consumes" caption="Figure 5.2 — How analytical data is composed from operational events and entities" %}

{% include excalidraw.html file="05-ingestion-streaming-sourcing" alt="Diagram of an ingestion layer sourcing analytical data from operational microservices via messaging events and Debezium-style change-data-capture" caption="Figure 5.3 — Ingestion, streaming, and CDC sourcing (conceptual; not built in this project)" %}

This same flow extends into the full choreography this project models:
inventory-service and payment-service also react to `order.placed`, and
shipping-service reacts to `payments.processed` — each consumer added
independently, with no change required to the producer that emits the event
it reacts to.

## The sync read layer: a gateway that composes

A client that wants an order *and* its current stock level shouldn't have
to call two services and join the results by hand. `graphql-gateway` solves
that by exposing one GraphQL query whose resolvers call order-service over
REST and inventory-service over gRPC side by side:

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

`@Query("order")` publishes `order(id: ID!): OrderView` in the generated
GraphQL schema; SmallRye GraphQL wires the method directly as the resolver.
`order(...)` calls order-service's REST endpoint through `OrderRestClient`
(a `@RegisterRestClient` interface, config-driven rather than
hard-coded to a host — see its `configKey = "order-service"`), and maps the
shared `OrderDto` wire shape onto the gateway's own `OrderView` GraphQL type
via `OrderView.from(dto)`.

`stock(@Source OrderView order)` is the federated field, and `@Source` makes it lazy:
this method runs only when a client's query selects `order { stock { ... } } }` —
MicroProfile GraphQL treats any method taking `@Source T` as a resolver for
a field named after the method on type `T`, invoked lazily per-field. A
query for `order(id: "...") { id customerId }` alone never calls
inventory-service at all; the gRPC call only happens when `stock` is
selected. This makes "one query, two protocols" an optimization: the
gateway does not pay for both backends regardless of what the client asked for.

The query sent over the wire by [demo-graphql.sh]({{ site.repo_blob }}/demos/demo-graphql.sh) shows the
composition:

```graphql
{ order(id: "ORDER_ID") { id customerId itemSku quantity status stock { sku quantityOnHand available } } }
```

One `POST /graphql` request; `order` resolves over REST, `stock` resolves
over gRPC, and SmallRye GraphQL assembles both into one JSON response under
`.data.order`.

This project uses **gateway orchestration** rather than GraphQL
subgraph federation: one stateless gateway owns the whole schema and
its resolvers call each domain's *existing* REST/gRPC interface directly,
with no GraphQL added to order-service or inventory-service.
Federation, where each domain exposes its own GraphQL subgraph and a
gateway plans queries across them, is the production-scale pattern because
it preserves each domain's ownership of its slice of the graph; here,
the gateway must know how to reach each domain directly. Orchestration
demonstrates what GraphQL adds (one client query,
multiple backends, a response shaped by the caller) with one new service and
no changes to the domain services. It is also why
`graphql-gateway` is not a data product in the service table from
the first chapter of this part: it composes
products it doesn't own and has no data of its own.

## Protocols by fitness, not by hierarchy

Across both planes, this project uses four protocols rather than forcing every
interaction through one, because each suits a different job: REST at the edge (clients
calling `order-service`, universal and cacheable); gRPC between services
internally (`InventoryClient` → `InventoryGrpcService`, fast and strongly
typed from the shared proto); GraphQL for composing reads across domains
(`GatewayApi`, one query shaped by the caller); and events for everything
asynchronous (`OrderEventProducer` → `OrderPlacedConsumer`, so a producer
never blocks on, or even knows about, its consumers). `GatewayApi` shows
the contrast in one class: its resolvers call REST and gRPC side by side.

## Camel's EIPs: the lens for the routing logic inside either plane

Neither plane above contains *conditional routing logic*: order-service always
publishes to the same topic, and the gateway always calls the same two backends. Where
this project's data flow branches on content, it uses the Camel enterprise integration
pattern **Content-Based Router**. [ai-mcp-service]({{ site.repo_tree }}/examples/ai-mcp-service)'s
`OrderLookupToolRoute` is reached through Camel's `ai-tool:` component (the
only HTTP-reachable path into it is the embedded MCP server's `tools/call`
method — see [demo-camel-integration.sh]({{ site.repo_blob }}/demos/demo-camel-integration.sh)'s header comment for why),
and its body is a `.choice()/.when()/.otherwise()` chain routing on an
incoming `orderId` header to one of four fixed responses:

{% include codetabs.html langs="Quarkus|YAML DSL" %}

```java
from("ai-tool:order-status"
        + "?tags=shipping"
        + "&description=Look up the status of a shipping order by order ID"
        + "&parameter.orderId=string"
        + "&parameter.orderId.description=The order identifier, for example ORD-001"
        + "&parameter.orderId.required=true"
        + "&readOnlyHint=true")
    .routeId("order-lookup-tool")
    .log("Tool call — looking up order: ${header.orderId}")
    .choice()
        .when(simple("${header.orderId} == 'ORD-001'"))
            .setBody(constant("{\"orderId\":\"ORD-001\",\"status\":\"SHIPPED\",\"carrier\":\"FedEx\",\"eta\":\"2026-07-20\"}"))
        .when(simple("${header.orderId} == 'ORD-002'"))
            .setBody(constant("{\"orderId\":\"ORD-002\",\"status\":\"PROCESSING\",\"warehouse\":\"West Coast Hub\"}"))
        .when(simple("${header.orderId} == 'ORD-003'"))
            .setBody(constant("{\"orderId\":\"ORD-003\",\"status\":\"DELIVERED\",\"deliveredAt\":\"2026-07-15\"}"))
        .otherwise()
            .setBody(constant("{\"error\":\"Order not found\"}"))
    .end()
    .log("Tool response: ${body}");
```

```yaml
- route:
    id: order-lookup-tool
    from:
      uri: "ai-tool:order-status"
      parameters:
        tags: shipping
        description: "Look up the status of a shipping order by order ID"
        parameter.orderId: string
        parameter.orderId.description: "The order identifier, for example ORD-001"
        parameter.orderId.required: true
        readOnlyHint: true
      steps:
        - log:
            message: "Tool call — looking up order: {% raw %}${header.orderId}{% endraw %}"
        - choice:
            when:
              - simple: "{% raw %}${header.orderId}{% endraw %} == 'ORD-001'"
                steps:
                  - setBody:
                      constant: '{"orderId":"ORD-001","status":"SHIPPED","carrier":"FedEx","eta":"2026-07-20"}'
              - simple: "{% raw %}${header.orderId}{% endraw %} == 'ORD-002'"
                steps:
                  - setBody:
                      constant: '{"orderId":"ORD-002","status":"PROCESSING","warehouse":"West Coast Hub"}'
              - simple: "{% raw %}${header.orderId}{% endraw %} == 'ORD-003'"
                steps:
                  - setBody:
                      constant: '{"orderId":"ORD-003","status":"DELIVERED","deliveredAt":"2026-07-15"}'
            otherwise:
              steps:
                - setBody:
                    constant: '{"error":"Order not found"}'
        - log:
            message: "Tool response: {% raw %}${body}{% endraw %}"
```

The two are equivalent route definitions. The Java DSL version is the one running in [ai-mcp-service]({{ site.repo_tree }}/examples/ai-mcp-service)
(it's what [demo-camel-integration.sh]({{ site.repo_blob }}/demos/demo-camel-integration.sh) exercises, asserting all four
branches including the `.otherwise()` fallback), and the YAML DSL block is
the same route in Camel's YAML syntax, which this project does not ship as a running
example. The Content-Based Router pattern reads identically either way: a `.choice()` (or
`choice:` step) evaluates its `.when()` predicates (here, Camel's `simple`
expression language comparing `${header.orderId}` against each known order
id) in order, routes to the first match's steps, and falls through to
`.otherwise()` only if none match. The same EIP terms describe this
chapter's Kafka and GraphQL flows: a Content-Based Router choosing a branch is the
conditional counterpart of a `@Incoming` consumer that always takes the same path, and
GraphQL's `@Source` resolution is a lazy routing decision (fetch from inventory-service
or not) made per field rather than per message.

## Two planes, one mesh

The synchronous and asynchronous planes are complementary. `GatewayApi` composes *current* state on demand, the moment a
client asks. `OrderPlacedConsumer` and its siblings propagate *change* as it
happens, so downstream consumers attach to the live operational flow rather
than a stale snapshot. Where routing logic needs to branch on content inside
either plane, Camel's EIPs are the pattern language this project uses,
with a Content-Based Router running in
[ai-mcp-service]({{ site.repo_tree }}/examples/ai-mcp-service).

## Build, run, observe

```bash
cd demos && ./demo-kafka.sh      # order.placed on the wire, Avro-encoded
cd demos && ./demo-graphql.sh    # one GraphQL query, REST + gRPC fan-out
cd demos && ./demo-grpc.sh       # CheckStock called directly with grpcurl
cd demos && ./demo-camel-integration.sh   # the Content-Based Router, all 4 branches
```

`demo-graphql.sh` is the main demo for this chapter: it
places an order, issues the `{ order(id: ...) { ... stock { ... } } }`
query shown above against the gateway, and asserts the response contains
*both* the REST-sourced order fields and the gRPC-sourced `stock` fields in
one `.data.order` payload with no `.errors` — then repeats the query for a
nonexistent order id as a negative control. `demo-camel-integration.sh`
reaches `OrderLookupToolRoute` through the embedded MCP server's
`tools/call` method (the only HTTP-reachable entry point into an `ai-tool:`
route) and asserts all four branches, including the `.otherwise()` fallback
for an unrecognized order id — the case `demo-ai-mcp.sh`'s own smoke test
does not cover.

## What you learned

- The async backbone (`OrderEventProducer` → `OrderPlacedConsumer`) and the
  sync read layer (`GatewayApi` composing `OrderRestClient` + a gRPC stub)
  are both running planes in this project, each suited to a different
  job — propagating change versus composing current state on demand.
- `@Source`-annotated GraphQL resolvers are lazy: the federated `stock`
  field only triggers inventory-service's gRPC call when a client's query
  selects it, so gateway composition does not always pay for both calls.
- Camel's Content-Based Router EIP describes the conditional routing
  logic in this project: `OrderLookupToolRoute`
  is a `.choice()/.when()/.otherwise()` route reachable through the
  embedded MCP server, shown here with an equivalent YAML DSL expression.

Part 1 has built the data products, their contracts, and the planes that move data
between them: "data as a product" in running Quarkus code.

---

*Verification status: <span class="status status--verified">verified</span>. `demo-graphql.sh` and `demo-grpc.sh` passed, and `OrderPlacedConsumerTest` confirms `@Transactional` alone makes the consumer blocking. One item remains unrun: the Camel YAML DSL route variant (only the Java DSL path has been exercised, via the Camel demo).*
