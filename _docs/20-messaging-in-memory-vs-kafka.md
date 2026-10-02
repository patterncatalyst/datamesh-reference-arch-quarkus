---
title: "In-memory (Vert.x) messaging vs. Kafka"
order: 20
part: Appendices
description: "The SmallRye Reactive Messaging in-memory connector used in tests vs. the Kafka connector used in %prod — same @Incoming/@Outgoing code, two transports, and a clear accounting of what the in-memory connector can and cannot stand in for."
duration: 25 minutes
marker: "20"
---

Every reactive-messaging method in this project — `ShipmentProcessor.process`,
the various `@Incoming`/`@Outgoing` consumers across `order-service`,
`payment-service`, `shipping-service`, and `notification-service` — is
written once, against the MicroProfile Reactive Messaging API, with no
reference anywhere in the method body to Kafka, a broker address, or a
serialization format. What actually moves a `PaymentCaptured` record from a
producer method to a consumer method is decided entirely in configuration:
`smallrye-kafka` in `application.properties` for every environment this
project actually ships to, and SmallRye's in-memory connector
(`InMemoryConnector`) for the one environment it deliberately does not ship
to — the test JVM. This chapter looks at both wiring paths with real code
from `examples/shipping-service`, and is direct about where the in-memory
connector's resemblance to Kafka ends.

{% include excalidraw.html file="20-inmemory-vs-kafka" alt="Two columns side by side. Left column, labeled 'In-memory (Vert.x) connector — tests': a single JVM box containing an InMemorySource, the ShipmentProcessor.process method annotated @Incoming/@Outgoing, and an InMemorySink, all connected by in-process method calls with no network hop and no broker. Right column, labeled 'Kafka connector — %prod': two separate JVM boxes (payment-service and shipping-service) each talking over the network to a Kafka broker box in the middle holding the payment.captured and shipment.dispatched topics with partitions and an Apicurio Schema Registry box beside it for Avro schemas. Below both columns, a trade-off table with rows for latency, coupling, durability, ordering guarantees, back-pressure, and testing ergonomics, with the in-memory column marked fast/tightly-coupled/non-durable/single-JVM-only and the Kafka column marked network-latency/decoupled/durable/partition-ordered/broker-mediated-back-pressure." caption="Figure A5.1 — In-memory vs. Kafka: same code, different connector" %}

## The code that doesn't change

`ShipmentProcessor`
(`examples/shipping-service/src/main/java/com/patterncatalyst/datamesh/shipping/ShipmentProcessor.java`)
is the saga participant that continues the `order.placed` -> `payment.captured`
-> `shipment.dispatched` choreography. Its entire contract with the messaging
layer is two annotations and a return value:

```java
@Incoming(Topics.PAYMENT_CAPTURED_CHANNEL)
@Outgoing(Topics.SHIPMENT_DISPATCHED_CHANNEL)
@Blocking
@Transactional
public ShipmentDispatched process(PaymentCaptured paymentCaptured) {
    // look up Shipment by orderId, derive carrier/tracking/sku/quantity,
    // persist, and return the ShipmentDispatched payload
    ...
}
```

`Topics.PAYMENT_CAPTURED_CHANNEL` and `Topics.SHIPMENT_DISPATCHED_CHANNEL`
(`examples/domain-model/.../Topics.java`) resolve to the plain strings
`"payment-captured"` and `"shipment-dispatched"` — logical Reactive Messaging
*channel ids*, not topic names. Channel ids are the one piece of vocabulary
shared by both connectors: `@Incoming("payment-captured")` just means "give
me whatever `mp.messaging.incoming.payment-captured.connector` is configured
to deliver," and the method has no way to tell, short of reading its own
configuration, whether that delivery came from a Kafka consumer poll loop or
from an in-process list someone appended to a moment ago. That indifference
is the entire point of the MicroProfile Reactive Messaging specification:
the channel id is the seam, the connector is a configuration value, and
`@Blocking`/`@Transactional` behave identically either way because they're
Quarkus/Vert.x concerns, not connector concerns.

## Both connectors sit on the same Vert.x execution model

It's worth being precise about what "unified" means here, because it is
easy to overstate. Quarkus's Vert.x event loop and worker-thread pools are
the single execution substrate underneath *every* reactive-messaging
channel, Kafka or in-memory: SmallRye Kafka's consumer records are delivered
onto that same Vert.x context, and `@Blocking` methods like
`ShipmentProcessor.process` are dispatched to the same Vert.x worker-thread
pool regardless of which connector produced the incoming message. What
*differs* is everything upstream of that dispatch point — whether the bytes
arriving at the channel came off a real TCP socket to a broker (Kafka) or
were handed directly from one Java list to another inside the same JVM
(in-memory). The execution model is shared; the transport, the wire format,
and the failure modes are not.

## In-memory: `InMemoryConnector` in `shipping-service`'s tests

`shipping-service` has exactly one place that uses the in-memory connector:
`ShipmentProcessorTest`
(`examples/shipping-service/src/test/java/com/patterncatalyst/datamesh/shipping/ShipmentProcessorTest.java`),
wired in by a `QuarkusTestResourceLifecycleManager` named
`InMemoryChannelsTestResource`
(`examples/shipping-service/src/test/java/com/patterncatalyst/datamesh/shipping/InMemoryChannelsTestResource.java`).
The resource's entire job is to override two configuration keys before the
test's Quarkus instance boots, as shown in the codetabs comparison at the
end of this chapter.
`switchIncomingChannelsToInMemory`/`switchOutgoingChannelsToInMemory` are
SmallRye test helpers that don't hand-edit `application.properties` at all —
they generate the equivalent `mp.messaging.[incoming|outgoing].<channel>.connector=smallrye-in-memory`
properties programmatically and inject them as environment overrides for
the duration of the test. `ShipmentProcessorTest` then injects the connector
itself and drives both ends directly:

```java
@Inject
@Connector("smallrye-in-memory")
InMemoryConnector connector;

InMemorySource<PaymentCaptured> paymentsIn = connector.source(Topics.PAYMENT_CAPTURED_CHANNEL);
InMemorySink<ShipmentDispatched> shipmentsOut = connector.sink(Topics.SHIPMENT_DISPATCHED_CHANNEL);

paymentsIn.send(paymentCaptured);

await().until(shipmentsOut::received, received -> received.size() == 1);
```

`paymentsIn.send(...)` calls directly into the same JVM's reactive-messaging
machinery — there is no serialization, no network round trip, and no broker
process anywhere in this test. `InMemorySink.received()` accumulates every
`Message<ShipmentDispatched>` the processor has emitted since the connector
was last cleared, which is why the test file's own Javadoc flags a real
gotcha: the sink is scoped to the `@QuarkusTest` instance's lifetime, not to
one `@Test` method, so `ShipmentProcessorTest` has to explicitly
`connector.sink(...).clear()` in a `@BeforeEach` — otherwise
`redeliveryOfSameOrderIsIdempotent`'s second test method would see the
leftover `ShipmentDispatched` from the first method's run and assert on the
wrong message count. That's a sharp edge specific to the in-memory
connector's test-scoped state, with no Kafka analogue (a fresh consumer
group against a fresh topic doesn't carry state between JUnit methods the
same way).

The comment on `InMemoryChannelsTestResource` is explicit about why this
exists: it lets `ShipmentProcessorTest` exercise `ShipmentProcessor`'s
choreography logic — consume `PaymentCaptured`, derive and persist a
`Shipment`, emit `ShipmentDispatched`, and specifically the idempotent-
redelivery guard — "without a running Kafka broker or Apicurio Registry."
No Testcontainers, no Dev Services startup for Kafka, no schema
registration round trip. The test still needs Postgres (via Dev Services)
for the `Shipment` persistence inside `process`, so it is not broker-free
*and* database-free — only broker-free.

## Kafka: `shipping-service` and `payment-service` in `%prod`

The same two channel ids that `ShipmentProcessorTest` redirects to memory
are, in `shipping-service/src/main/resources/application.properties`, wired
to `smallrye-kafka` with explicit Avro (de)serializers and commit/offset
settings (shown in full in the codetabs comparison at the end of this
chapter).

Note the topic name (`payment.captured`, dot-separated) is deliberately a
different string from the channel id (`payment-captured`, hyphenated) — the
channel id is local vocabulary for this service's wiring; the topic name is
the shared, physical, cross-service contract, defined once in
`Topics.PAYMENT_CAPTURED_TOPIC`
(`examples/domain-model/.../Topics.java`) and referenced the same way by
`payment-service`'s outgoing side
(`examples/payment-service/src/main/resources/application.properties`):

```properties
mp.messaging.outgoing.payment-captured.connector=smallrye-kafka
mp.messaging.outgoing.payment-captured.topic=payment.captured
mp.messaging.outgoing.payment-captured.value.serializer=io.apicurio.registry.serde.avro.AvroKafkaSerializer
mp.messaging.outgoing.payment-captured.apicurio.registry.auto-register=true
```

`payment-service` and `shipping-service` are two separate Quarkus
applications, each with its own JVM, each independently deployable, that
agree on nothing except the topic name, the Avro schema registered in
Apicurio, and the fact that both point `kafka.bootstrap.servers` at the
same broker. In dev and test mode, neither service sets
`kafka.bootstrap.servers` or `apicurio.registry.url` at all — Quarkus Dev
Services starts an ephemeral `apache/kafka-native:4.2.0` broker and an
`apicurio/apicurio-registry:3.1.7` container automatically and wires both
services to it. The `%prod` profile is where the real cross-process
contract becomes explicit, in both services' `application.properties`:

```properties
%prod.kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVERS:kafka:9094}
%prod.mp.messaging.connector.smallrye-kafka.apicurio.registry.url=${APICURIO_REGISTRY_URL:http://apicurio:8080/apis/registry/v3}
```

That one line separates "two methods calling each other in a test JVM" from
"two independently deployed services agreeing on a wire protocol": a real
TCP connection to a named broker host — one image, its broker target
supplied by an environment variable, so the same build serves Compose and
Kubernetes. Explicit Avro
(de)serializer classes are set on every channel rather than left to
connector autodetection; the comment in `shipping-service`'s properties
file documents why — `order-service` found empirically that Apicurio's
split-package layout across `apicurio-registry-avro-serde-kafka` and
`apicurio-registry-serde-common-avro` breaks Quarkus's serde
autodetection and silently falls back to JSON, which would put a
non-Avro payload on a topic every other consumer expects to be Avro.

## Comparing the two connectors

**Latency.** In-memory delivery is a direct method call plus whatever
Vert.x context-switching Quarkus does internally — no network hop, no TCP
handshake, no broker-side fsync, and no consumer poll interval to wait out.
Kafka delivery crosses a real socket to a broker process, is appended to a
partition's log, and is picked up by a poll loop on the consumer side; it's
reliably slower and variable under broker load, replication, or
consumer-group rebalancing. Neither `ShipmentProcessorTest` nor this repo's
`application.properties` files measure or assert a latency number for
either path — take this as a structural reason to expect one to be faster,
not a benchmark.

**Coupling.** The in-memory connector couples producer and consumer to the
same JVM, by construction — `InMemoryConnector.switchIncomingChannelsToInMemory`
only makes sense inside one `@QuarkusTest` instance where a single process
owns both ends of the channel. `payment-service` and `shipping-service`
over Kafka have no such requirement: they don't share a JVM, a deployment,
or even a release cadence beyond the topic contract and the Avro schema
registered in Apicurio. That decoupling is the entire reason this project
uses Kafka for anything cross-service in the first place — it's a
precondition for domain-owned services in a data-mesh architecture, not an
incidental detail.

**Durability.** `InMemorySink`'s `received()` list lives in heap memory for
the lifetime of the `@QuarkusTest` instance and is explicitly cleared by
`InMemoryConnector.clear()` in `InMemoryChannelsTestResource.stop()`;
nothing about it is written to disk or survives a JVM restart, and nothing
in this project claims otherwise. A Kafka topic persists its log to disk,
replicates it (configuration permitting), and lets a consumer recover a
backlog after a restart by re-polling from a committed offset —
`shipping-service`'s `enable.auto.commit=false` plus
`auto.offset.reset=earliest` is specifically there so a restarted consumer
with no committed offset replays from the start of the topic rather than
silently skipping backlog, a concern that has no in-memory equivalent
because there is no backlog once the test JVM exits.

**Ordering guarantees.** Kafka guarantees order only within a partition, not
across an entire topic — a detail this project's single-partition dev/test
topics don't surface, but a real partitioned production topic would. The
in-memory connector has no partition concept at all: `InMemorySource.send`
calls are delivered in the order they're invoked, which is simpler than
Kafka's model but is not evidence that the same ordering will hold once the
channel is reconfigured onto a multi-partition Kafka topic keyed across
several orders.

**Back-pressure.** Both connectors participate in the same Reactive Streams
back-pressure protocol that MicroProfile Reactive Messaging specifies, but
what's behind that protocol differs: Kafka's consumer applies back-pressure
by controlling its poll rate against the broker, with the broker itself
buffering independently; the in-memory connector's back-pressure is
whatever the in-process `Multi`/`Processor` plumbing between
`InMemorySource` and the subscribing method does, with no broker-side
buffer behind it at all. A test that floods an `InMemorySource` with sends
faster than `@Blocking`-dispatched processing can keep up is exercising a
materially different queueing behavior than a real Kafka consumer under the
same load.

**Testing ergonomics.** This is where the in-memory connector is most
useful: `ShipmentProcessorTest` asserts the choreography
logic — idempotent redelivery, deterministic shipment derivation — in a
plain JUnit test with `Awaitility`, no Testcontainers startup, no Kafka
broker, no Apicurio Registry, no Avro schema to register before the first
assertion can run. That's a real, measurable simplification in test
startup time and moving parts, and it's exactly the trade `shipping-service`
makes deliberately for this one test class. It is not, however, a
replacement for an integration test against a real broker: it cannot catch
a serializer misconfiguration (the exact `order-service` Avro-vs-JSON bug
the properties-file comment documents), a topic name mismatch between
`payment-service` and `shipping-service`, a schema-compatibility break in
Apicurio, or a consumer-group rebalance edge case, because none of those
failure modes exist in a path that never touches a serializer, a topic
name, a schema registry, or a consumer group.

## What this project actually does — and doesn't — use in-memory for

To be direct about scope: the in-memory connector appears in exactly one
place in this codebase, `shipping-service`'s test tree, and nowhere in any
`main` source set. Every `%prod` and Docker Compose deployment path runs on
`smallrye-kafka` against a real broker, every cross-service contract is a
Kafka topic plus an Apicurio-registered Avro schema, and nothing here
treats the in-memory connector as a lightweight production transport — it
isn't one, and the SmallRye project doesn't position it as one either. For
your own service, the pairing above still holds: unit-test the *business
logic* a `@Incoming`/`@Outgoing` method expresses in-memory, and keep a
real-broker test (Dev Services' Testcontainers-backed Kafka, which
`shipping-service`'s other, non-in-memory tests already get automatically) for
anything that depends on serialization, partitioning, or cross-process
delivery actually working.

{% include codetabs.html langs="In-memory (tests)|Kafka (%prod)" %}
```java
// InMemoryChannelsTestResource.java — redirects both channels to the
// in-memory connector before the @QuarkusTest instance boots.
public class InMemoryChannelsTestResource implements QuarkusTestResourceLifecycleManager {

    @Override
    public Map<String, String> start() {
        Map<String, String> env = new HashMap<>();
        env.putAll(InMemoryConnector.switchIncomingChannelsToInMemory(Topics.PAYMENT_CAPTURED_CHANNEL));
        env.putAll(InMemoryConnector.switchOutgoingChannelsToInMemory(Topics.SHIPMENT_DISPATCHED_CHANNEL));
        return env;
    }

    @Override
    public void stop() {
        InMemoryConnector.clear();
    }
}
```
```properties
# shipping-service/src/main/resources/application.properties — the same
# two channel ids, wired to Kafka with explicit Avro serde and a %prod
# bootstrap-servers override for the real broker.
mp.messaging.incoming.payment-captured.connector=smallrye-kafka
mp.messaging.incoming.payment-captured.topic=payment.captured
mp.messaging.incoming.payment-captured.value.deserializer=io.apicurio.registry.serde.avro.AvroKafkaDeserializer
mp.messaging.incoming.payment-captured.apicurio.registry.use-specific-avro-reader=true
mp.messaging.incoming.payment-captured.enable.auto.commit=false
mp.messaging.incoming.payment-captured.auto.offset.reset=earliest

mp.messaging.outgoing.shipment-dispatched.connector=smallrye-kafka
mp.messaging.outgoing.shipment-dispatched.topic=shipment.dispatched
mp.messaging.outgoing.shipment-dispatched.value.serializer=io.apicurio.registry.serde.avro.AvroKafkaSerializer
mp.messaging.outgoing.shipment-dispatched.apicurio.registry.auto-register=true

{% raw %}%prod.kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVERS:kafka:9094}
%prod.mp.messaging.connector.smallrye-kafka.apicurio.registry.url=${APICURIO_REGISTRY_URL:http://apicurio:8080/apis/registry/v3}{% endraw %}
```

## What you learned

- `@Incoming`/`@Outgoing` application code is connector-agnostic; the
  channel id is the seam, and `smallrye-in-memory` vs. `smallrye-kafka` is
  a configuration choice, not a code difference.
- `shipping-service`'s `ShipmentProcessorTest` uses
  `InMemoryConnector.switchIncomingChannelsToInMemory`/
  `switchOutgoingChannelsToInMemory` via `InMemoryChannelsTestResource` to
  unit-test `ShipmentProcessor`'s choreography logic without a broker or
  schema registry — and has to manually clear the sink between tests
  because it's scoped to the `@QuarkusTest` instance, not the test method.
- `%prod` configuration in `shipping-service` and `payment-service` points
  the same channel ids at `smallrye-kafka`, a real broker address, Avro
  (de)serializers, and Apicurio Registry — the only path this project
  actually deploys.
- The in-memory connector is faster and simpler to test against precisely
  because it skips everything that makes Kafka a durable, decoupled,
  cross-process transport — serialization, partitioning, broker-side
  persistence, and consumer-group coordination — none of which an
  in-memory test can validate.

This closes the appendices in this project.

---

*Verification status: <span class="status status--unverified">unverified</span>.
The highest-risk things to confirm on a real run: that
`ShipmentProcessorTest` passes against the pinned SmallRye Reactive
Messaging version with the sink-clearing `@BeforeEach` actually preventing
cross-test bleed (per its own Javadoc, omitting it was observed to leak a
count of 3 instead of 1); that `shipping-service`'s explicit Avro
serializer/deserializer keys are still necessary workarounds for the
Apicurio split-package autodetection issue the properties file documents,
rather than a since-fixed upstream default; and that the `%prod`
`kafka.bootstrap.servers`/`apicurio.registry.url` overrides resolve
correctly against whatever Compose or Kubernetes service names this
project's infrastructure ultimately ships with.*
