# order-service

The order data product for the Quarkus DataMesh reference architecture --
the Quarkus counterpart to the Python reference's
`services/order-service` (r21 REST + Postgres, r23 gRPC stock check, r25
`order.placed` event emission).

order-service owns the `Order` aggregate exclusively (CAP-003 per-service
data ownership); other services only ever observe order state via the
`order.placed` Kafka event, never this service's database.

## Endpoints

| Method | Path | Behavior |
|---|---|---|
| `POST` | `/orders` | Checks inventory (`CheckStock` over gRPC); `409` if unavailable, `503` if inventory-service is unreachable; otherwise persists with status `PLACED` and publishes `order.placed`, returning `201`. |
| `GET` | `/orders` | Lists orders, most recently created first. |
| `GET` | `/orders/{id}` | Fetches one order; `404` if it doesn't exist. |

Ops endpoints from `quarkus-smallrye-health`: `/q/health`, `/q/health/live`,
`/q/health/ready` (includes datasource and Reactive Messaging channel
checks with zero extra config).

## Architecture

- **`Order`** -- Panache active-record entity (`String` UUID id,
  `customerId`, `itemSku`, `quantity`, `amount` as `BigDecimal`, `status` as
  `domain-model`'s `OrderStatus`, `createdAt`). Persisted with
  `quarkus-hibernate-orm-panache` + `quarkus-jdbc-postgresql` (Dev Services
  auto-starts Postgres in dev/test, zero datasource config needed).
- **`InventoryClient`** -- wraps the `@GrpcClient("inventory")` call to
  inventory-service's `CheckStock` RPC. The `InventoryService` stub is
  generated at build time from the `.proto` packaged inside the `contracts`
  dependency jar (`capstone/inventory/v1/inventory.proto`), not
  regenerated or hand-written here -- see
  `quarkus.generate-code.grpc.scan-for-proto` below.
- **`OrderEventProducer`** -- `@Channel("order-placed") Emitter<OrderPlaced>`
  publishing the Avro `OrderPlaced` record (generated in the `contracts`
  module from `order-placed.avsc`) to the `order.placed` Kafka topic via the
  Apicurio Schema Registry serializer (DRQ-009 -- Avro from the start, never
  JSON).
- **`OrderResource`** -- wires the above: check stock, persist, emit,
  respond.

## Verified Quarkus 3.39.5 configuration

Confirmed via `quarkus_searchDocs` against this project's pinned Quarkus
version (not guessed):

```properties
# gRPC stub generation from a dependency jar's packaged .proto
quarkus.generate-code.grpc.scan-for-proto=com.patterncatalyst.datamesh:contracts

# gRPC client used by @GrpcClient("inventory")
quarkus.grpc.clients.inventory.host=localhost
quarkus.grpc.clients.inventory.port=9001

# Kafka outgoing channel -> order.placed topic, Avro via Apicurio
mp.messaging.outgoing.order-placed.connector=smallrye-kafka
mp.messaging.outgoing.order-placed.topic=order.placed
mp.messaging.outgoing.order-placed.apicurio.registry.auto-register=true
```

The Avro serializer itself
(`io.apicurio.registry.serde.avro.AvroKafkaSerializer`) is **not** set
explicitly -- Quarkus autodetects it from the `@Channel("order-placed")
Emitter<OrderPlaced>` declaration (`OrderPlaced` is an Avro
`SpecificRecord`) plus the presence of `quarkus-apicurio-registry-avro` on
the classpath. This is the documented behavior (`kafka-schema-registry-avro.adoc`,
"The Movie producer"), not an omission.

Kafka and the Apicurio Schema Registry are both provided by Quarkus Dev
Services (Testcontainers) automatically in dev/test; inventory-service must
be running separately at `quarkus.grpc.clients.inventory.host`/`.port`
above (`localhost:9001` locally) for `POST /orders` to succeed end to end.

## Building and running

```bash
# from the examples/ reactor root
mvn -pl order-service package -f pom.xml

# dev loop (needs inventory-service reachable for POST /orders to succeed)
mvn -pl order-service quarkus:dev -f pom.xml
```

## Testing

`OrderResourceTest` is a `@QuarkusTest` (Dev Services provides Postgres;
`InventoryClient` is mocked with `@InjectMock` so the test doesn't require a
running inventory-service). It is **not** run as part of this module's own
build (`-DskipTests`); `@QuarkusTest` suites across the reactor are run
serially in a later batch to avoid Dev Services / Testcontainers resource
contention between concurrently building sibling modules.
