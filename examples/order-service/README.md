# order-service

The order data product for the Quarkus DataMesh reference architecture --
the Quarkus counterpart to the Python reference's
`services/order-service` (REST + Postgres, gRPC stock check,
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
  Apicurio Schema Registry serializer (Avro on the wire,
  never JSON).
- **`OrderResource`** -- wires the above: check stock, persist, emit,
  respond.

## Verified Quarkus configuration (checked on 3.39.5; builds on 3.40.1)

Checked with `quarkus_searchDocs` against this project's pinned Quarkus
version:

```properties
# gRPC stub generation from a dependency jar's packaged .proto
quarkus.generate-code.grpc.scan-for-proto=com.patterncatalyst.datamesh:contracts

# gRPC client used by @GrpcClient("inventory")
# Env-overridable so compose/K8s can point at the real inventory-service
# without a code change; 9000 matches inventory-service's server default --
# do NOT reintroduce 9001 (the old mismatch that broke %prod/K8s).
quarkus.grpc.clients.inventory.host=${INVENTORY_GRPC_HOST:localhost}
quarkus.grpc.clients.inventory.port=${INVENTORY_GRPC_PORT:9000}

# Kafka outgoing channel -> order.placed topic, Avro via Apicurio
mp.messaging.outgoing.order-placed.connector=smallrye-kafka
mp.messaging.outgoing.order-placed.topic=order.placed
mp.messaging.outgoing.order-placed.apicurio.registry.auto-register=true
```

The Avro serializer itself
(`io.apicurio.registry.serde.avro.AvroKafkaSerializer`) is set explicitly
as `mp.messaging.outgoing.order-placed.value.serializer` in
`application.properties` instead of relying on autodetection. This build
pulls an older `apicurio-registry-serdes-avro-serde` transitively alongside
the expected serde (the build's
`io.quarkus.arc.deployment.SplitPackageProcessor` warns about
`io.apicurio.registry.serde.avro`), which makes Quarkus's serializer
autodetection (`kafka-schema-registry-avro.adoc`,
"serialization-autodetection") unreliable. The unconfigured build logged
"Generating Jackson serializer for type capstone.order.v1.OrderPlaced",
a silent fallback to JSON that breaks the Avro-only contract. Setting
`value.serializer` explicitly avoids the fallback.

Kafka and the Apicurio Schema Registry are both provided by Quarkus Dev
Services (Testcontainers) automatically in dev/test; inventory-service must
be running separately at `quarkus.grpc.clients.inventory.host`/`.port`
above (`localhost:9000` locally, overridable via `INVENTORY_GRPC_HOST`/
`INVENTORY_GRPC_PORT`) for `POST /orders` to succeed end to end.

## Building and running

```bash
# from the repo root
mvn -pl order-service package -f examples/pom.xml

# dev loop (needs inventory-service reachable for POST /orders to succeed)
mvn -pl order-service quarkus:dev -f examples/pom.xml
```

## Testing

`OrderResourceTest` is a `@QuarkusTest` (Dev Services provides Postgres;
`InventoryClient` is mocked with `@InjectMock` so the test doesn't require a
running inventory-service). `@QuarkusTest` suites are not run by this
module's own `-DskipTests` build; run them serially across the project to
avoid Dev Services / Testcontainers resource contention between sibling
modules built concurrently.

### Avro wire-format check: `OrderPlacedAvroWireIT`

`OrderPlacedAvroWireIT` is a plain JUnit integration test that verifies
`order.placed` is Avro on the wire and not JSON. It starts its own
Testcontainers Kafka (`apache/kafka-native:4.3.1`) and Apicurio Registry
(`quay.io/apicurio/apicurio-registry:3.3.3`), so it does not need
`docker compose up`.

- It produces a real `capstone.order.v1.OrderPlaced` with
  `AvroKafkaSerializer`, the serializer the application configures.
- It reads the record back with a byte-level `KafkaConsumer<byte[], byte[]>`
  that has no Avro deserializer, and asserts `value[0] == 0x00` (the Avro
  magic byte), `value[0] != 0x7B` (`{`, which would indicate JSON), and room
  for the schema id that follows.
- It runs in the default `mvn verify` through the failsafe plugin.

Avro 1.12's `ClassSecurityValidator` refuses to build a writer for any
generated record class whose package is not trusted, unless a Quarkus
application is running. Because this test bootstraps no Quarkus runtime, the
failsafe execution in `pom.xml` sets
`org.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1`. Without it the
test fails with `SecurityException: Forbidden capstone.order.v1.OrderPlaced!`.
The setting is scoped to this module's test JVM.

The serializer is pinned explicitly (see above) because autodetection was
unreliable with two Avro serdes on the classpath; this test fails if that
pinning regresses to the JSON fallback.
