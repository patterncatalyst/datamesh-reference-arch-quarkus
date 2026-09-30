# contracts

Single source of the wire contracts shared by every producer and consumer
service in the reference architecture. Per **DRQ-009**, all Kafka events are
Avro-serialized against the Apicurio Schema Registry from the start (not
JSON).

This module is a plain, framework-agnostic jar: it depends only on
`org.apache.avro:avro` (version managed by the parent's `quarkus-bom`
import), never on Quarkus itself, so any JVM consumer can use it.

## Avro schemas (`src/main/avro/*.avsc`)

Generated via the `org.apache.avro:avro-maven-plugin` `schema` goal, bound to
`generate-sources`. Generated Java (`SpecificRecord`) classes land under
`target/generated-sources/avro` and are compiled straight into this jar.

| Schema | Namespace | Record | Kafka topic |
|---|---|---|---|
| `order-placed.avsc` | `capstone.order.v1` | `OrderPlaced` | `order.placed` |
| `payment-captured.avsc` | `capstone.payment.v1` | `PaymentCaptured` | `payment.captured` |
| `shipment-dispatched.avsc` | `capstone.shipping.v1` | `ShipmentDispatched` | `shipment.dispatched` |

Topic name constants live in `domain-model`'s
`com.patterncatalyst.datamesh.domain.Topics`.

Each service configures the Apicurio Avro serde itself (e.g.
`io.quarkus:quarkus-apicurio-registry-avro` + the relevant
`mp.messaging.[incoming|outgoing].<channel>.*` properties) — that
configuration is NOT part of this module.

## gRPC proto (`src/main/proto/capstone/inventory/v1/inventory.proto`)

Ported verbatim from the Python reference architecture. `InventoryService`
exposes a single `CheckStock` RPC used by order-service when placing an
order.

This module does **not** generate gRPC stubs itself. The `.proto` file is
packaged as a plain resource (see the `<resources>` block in `pom.xml`) so
it ships inside the `contracts` jar at
`capstone/inventory/v1/inventory.proto`. Each consuming Quarkus service
generates its own stubs from it at build time by adding the `quarkus-grpc`
extension and pointing the standard multi-module scan-for-proto property at
this module's coordinates in its `application.properties`:

```properties
quarkus.generate-code.grpc.scan-for-proto=com.patterncatalyst.datamesh:contracts
```

The property value is a comma-separated list of `groupId:artifactId`
coordinates (default `none`); `scan-for-proto-include`/`-exclude` glob
patterns are also available per-dependency if a consumer only wants a subset
of the proto files packaged here. See the Quarkus gRPC code generation
reference guide, "Configuring gRPC code generation for dependencies".
