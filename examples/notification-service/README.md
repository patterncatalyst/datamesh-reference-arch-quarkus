# notification-service

Consumer-only data product for the reference architecture's shipping/order
domain. Mirrors the Python reference architecture's `notification-service`:
it consumes `order.placed` events and persists them, but produces nothing
itself.

## What it does

1. Consumes Avro-encoded `OrderPlaced` events (schema owned by the
   `contracts` module, package `capstone.order.v1`) from the Kafka
   `order.placed` topic via the `order-placed` Reactive Messaging channel.
2. Validates/decodes each message against the Apicurio Schema Registry
   (Avro + Apicurio from the start, not JSON).
3. Maps each event to a `Notification` row and persists it via
   Hibernate ORM with Panache, keyed by `order_id` so at-least-once Kafka
   redelivery is a no-op rather than a duplicate row.
4. Exposes the persisted notifications over `GET /notifications`.

## Module layout

- `Notification` (`Notification.java`) — Panache active-record entity:
  `id`, `orderId`, `eventType`, `customerId`, `itemSku`, `quantity`,
  `amount` (`BigDecimal`), `status`, `createdAt`.
- `OrderPlacedConsumer` (`OrderPlacedConsumer.java`) — `@Incoming("order-placed")`
  `@Transactional` method that maps the incoming `OrderPlaced` Avro record to
  a `Notification` and persists it.
- `NotificationResource` (`NotificationResource.java`) — `GET /notifications`,
  returning all persisted rows.

## Configuration (`application.properties`)

- Postgres: Dev Services auto-starts a container in dev/test mode (no local
  config needed); `quarkus.hibernate-orm.schema-management.strategy=drop-and-create`
  for dev/test.
- Kafka: `mp.messaging.incoming.order-placed.*` maps the `order-placed`
  channel to the `order.placed` topic. Dev Services for Kafka + Apicurio
  Registry auto-start together in dev/test mode (see
  `quarkus-apicurio-registry-avro`'s Dev Services guide) — no
  `bootstrap.servers` / `apicurio.registry.url` needed locally.
- Apicurio Avro deserializer: Quarkus can autodetect
  `io.apicurio.registry.serde.avro.AvroKafkaDeserializer` and
  `apicurio.registry.use-specific-avro-reader=true` from the `OrderPlaced`
  Avro `SpecificRecord` payload type and the presence of
  `quarkus-apicurio-registry-avro`, but both are set explicitly here for
  clarity:
  - `mp.messaging.incoming.order-placed.value.deserializer=io.apicurio.registry.serde.avro.AvroKafkaDeserializer`
  - `mp.messaging.incoming.order-placed.apicurio.registry.use-specific-avro-reader=true`
- `quarkus-smallrye-health` — liveness/readiness at `/q/health`.

## Testing

`OrderPlacedConsumerTest` (`@QuarkusTest`) calls `OrderPlacedConsumer.consume(...)`
directly with a constructed `OrderPlaced` record — this verifies the
Avro-to-`Notification` mapping and the idempotent-write behavior for
redelivery without needing a live Kafka broker in the test. The declarative
Reactive Messaging wiring (topic ↔ channel ↔ Apicurio deserializer) is
exercised against a live Dev Services broker when the service actually runs.

## Running

```bash
mvn quarkus:dev
```

```bash
curl http://localhost:8080/notifications
```
