# payment-service

Event-driven choreography processor for the DataMesh reference
architecture (Avro + Apicurio Schema Registry rather than JSON;
the runtime contract is choreography, not direct calls). It is the choreography
counterpart to `order-service`: it never receives a direct call from
`order-service`, it reacts to the event `order-service` publishes.

## What it does

`PaymentProcessor` is a single Reactive Messaging processor method:

```java
@Incoming(Topics.ORDER_PLACED_CHANNEL)
@Outgoing(Topics.PAYMENT_CAPTURED_CHANNEL)
public PaymentCaptured process(OrderPlaced orderPlaced) { ... }
```

- **Consumes** `OrderPlaced` (Avro, namespace `capstone.order.v1`) from the
  `order.placed` Kafka topic.
- For every order, **captures a payment** with simple, deterministic logic: a
  freshly generated `pay-<uuid>` payment id, status always `CAPTURED`,
  amount/customer mirrored from the order. (Payment gateway integration and a
  decline/retry path are out of scope for this example.)
- **Produces** `PaymentCaptured` (Avro, namespace `capstone.payment.v1`) to
  the `payment.captured` Kafka topic.
- Records each capture in `PaymentStore`, a minimal in-memory
  (`ConcurrentHashMap`) bookkeeping structure, not a
  database. The choreography (Kafka in/out) is the required part of this
  module's runtime contract; this store just gives the module something to
  inspect beyond the outgoing event.

Both Avro records come from the `contracts` module (`order-placed.avsc`,
`payment-captured.avsc`) -- this module never redefines the wire schema.
Channel names come from `domain-model`'s
`com.patterncatalyst.datamesh.domain.Topics` (`ORDER_PLACED_CHANNEL` =
`order-placed`, `PAYMENT_CAPTURED_CHANNEL` = `payment-captured`), which also
owns the physical topic name constants (`order.placed`, `payment.captured`).

## Apicurio Avro wiring (`application.properties`)

```properties
mp.messaging.incoming.order-placed.connector=smallrye-kafka
mp.messaging.incoming.order-placed.topic=order.placed
mp.messaging.incoming.order-placed.value.deserializer=io.apicurio.registry.serde.avro.AvroKafkaDeserializer
mp.messaging.incoming.order-placed.apicurio.registry.use-specific-avro-reader=true

mp.messaging.outgoing.payment-captured.connector=smallrye-kafka
mp.messaging.outgoing.payment-captured.topic=payment.captured
mp.messaging.outgoing.payment-captured.value.serializer=io.apicurio.registry.serde.avro.AvroKafkaSerializer
mp.messaging.outgoing.payment-captured.apicurio.registry.auto-register=true
```

- `value.deserializer` / `value.serializer` are set explicitly here for
  clarity; Quarkus can also autodetect
  `io.apicurio.registry.serde.avro.AvroKafkaSerializer` /
  `AvroKafkaDeserializer` from the method's Avro-generated parameter/return
  type and the presence of the Apicurio Registry libraries (verified via
  `quarkus_searchDocs`, `kafka-schema-registry-avro.adoc`).
- `apicurio.registry.use-specific-avro-reader=true` makes the deserializer
  produce the generated `OrderPlaced` `SpecificRecord` class instead of a
  schema-less `GenericRecord`.
- `apicurio.registry.auto-register=true` registers the `PaymentCaptured`
  schema with the registry on first publish if it isn't already there
  (verified via `quarkus_searchDocs`, same guide, "The `Movie` producer"
  section).
- Neither `apicurio.registry.url` nor `kafka.bootstrap.servers` is set: Dev
  Services for Kafka (`quarkus-kafka-client`, pulled in transitively by
  `quarkus-messaging-kafka`) and Dev Services for Apicurio Registry
  (`quarkus-apicurio-registry-avro`) both auto-start in dev/test mode and
  wire themselves together, per the `apicurio-registry-dev-services.adoc`
  and `kafka-dev-services.adoc` guides. A production deployment sets these
  per-channel or via `mp.messaging.connector.smallrye-kafka.*`.

## Health

`quarkus-smallrye-health` is included; once the app is running,
`/q/health`, `/q/health/live`, and `/q/health/ready` are available.

## Testing

`PaymentProcessorTest` (`@QuarkusTest`) calls `PaymentProcessor.process(...)`
directly as a plain CDI method invocation -- a fast, broker-free unit test of
the transform (build an `OrderPlaced`, assert the returned
`PaymentCaptured`'s fields and status, assert the record lands in
`PaymentStore`). It does not exercise the Kafka/Apicurio wiring itself; that
end-to-end path is what Dev Services stand up when the module is run
(`mvn quarkus:dev`, `mvn quarkus:test`, or a future integration-test module).
This test is **written, not run**, as part of this build batch.

## Build

```bash
mvn -q -pl payment-service -DskipTests package -f examples/pom.xml
```
