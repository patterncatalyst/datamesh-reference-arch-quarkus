# shipping-service

Real event-choreography saga participant for the order → payment → shipment
flow (Avro events, choreography-based runtime contract). Upgrades the Python reference architecture's
shipping-service stub to a running Quarkus service.

## What it does

`ShipmentProcessor` consumes `PaymentCaptured` (Avro, `capstone.payment.v1`)
from the `payment.captured` Kafka topic, creates a shipment, persists a
minimal local `Shipment` record, and produces `ShipmentDispatched` (Avro,
`capstone.shipping.v1`) on the `shipment.dispatched` topic:

```java
@Incoming(Topics.PAYMENT_CAPTURED_CHANNEL)
@Outgoing(Topics.SHIPMENT_DISPATCHED_CHANNEL)
@Blocking
@Transactional
public ShipmentDispatched process(PaymentCaptured paymentCaptured) { ... }
```

Carrier, tracking number, item SKU, and quantity are derived
**deterministically** from the order id (via `UUID.nameUUIDFromBytes` /
hashing), rather than randomly — the same order always dispatches
identically, which keeps demos and tests reproducible. `PaymentCaptured`
doesn't carry line-item detail, so `itemSku`/`quantity` are simulated the
same deterministic way; a production system would enrich this step via an
order-details lookup or carry those fields through the saga.

## Wire contracts

Both Avro schemas live in the `contracts` module and are consumed as
generated `SpecificRecord` classes:

| Direction | Channel | Topic | Avro record |
|---|---|---|---|
| `@Incoming` | `payment-captured` | `payment.captured` | `capstone.payment.v1.PaymentCaptured` |
| `@Outgoing` | `shipment-dispatched` | `shipment.dispatched` | `capstone.shipping.v1.ShipmentDispatched` |

Channel/topic names come from `domain-model`'s `Topics` constants class —
never hardcoded string literals in `ShipmentProcessor`.

## Serialization: Apicurio Avro

Both channels serialize through `io.apicurio.registry.serde.avro.*` (via the
`quarkus-apicurio-registry-avro` extension), not JSON. `value.serializer` /
`value.deserializer` and `apicurio.registry.use-specific-avro-reader` are all
set **explicitly** in `application.properties`, not left to Quarkus's
autodetection. order-service empirically proved that autodetection silently
falls back to a Jackson (JSON) serializer here: two Apicurio artifacts
(`apicurio-registry-avro-serde-kafka` + `apicurio-registry-serde-common-avro`)
share the `io.apicurio.registry.serde.avro` package (flagged by the build's
own `SplitPackageProcessor` warning), which breaks Quarkus's serde
autodetection (`kafka-schema-registry-avro.adoc`,
"serialization-autodetection"). Explicit keys are required here to keep
events Avro on the wire. `apicurio.registry.auto-register=true` is
also set on the outgoing channel, so the `ShipmentDispatched` schema
registers itself with Apicurio on first publish.

In dev and test mode, both Kafka and the Apicurio Registry are started
automatically via Dev Services — no local broker or registry needed.

## Optional local record

`Shipment` (a `PanacheEntity`) persists one row per dispatched shipment via
`quarkus-hibernate-orm-panache` + `quarkus-jdbc-postgresql`. Postgres also
starts via Dev Services with zero configuration. This is intentionally
minimal — the required part of this module is the choreography step, not the
data store.

## Health

`quarkus-smallrye-health` exposes `/q/health`, `/q/health/live`, and
`/q/health/ready`. `quarkus-messaging-kafka` automatically contributes
readiness checks for the configured Kafka channels; no custom `HealthCheck`
was added.

## Testing

`ShipmentProcessorTest` is a `@QuarkusTest` that switches both channels to
the in-memory connector (via `InMemoryChannelsTestResource`, following the
Quarkus Kafka reference guide's "Testing without a broker" pattern) so the
choreography logic can be exercised without a running Kafka broker or
Apicurio Registry. It has been **written but not run** as part of this build
batch.

```bash
mvn -q -pl shipping-service -DskipTests package -f examples/pom.xml   # build check
mvn -pl shipping-service test -f examples/pom.xml                     # run tests (not done here)
```
