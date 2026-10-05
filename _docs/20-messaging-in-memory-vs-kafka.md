---
title: "In-memory (Vert.x) messaging vs. Kafka"
order: 20
part: Appendices
description: "Vert.x in-memory messaging and Kafka compared: the SmallRye Reactive Messaging in-memory connector used in tests and the Kafka connector used in %prod run the same @Incoming/@Outgoing code over two transports, with the limits of what the in-memory connector can stand in for."
duration: 25 minutes
marker: "20"
---

Every reactive-messaging method in this project — `ShipmentProcessor.process`,
the various `@Incoming`/`@Outgoing` consumers across `order-service`,
`payment-service`, `shipping-service`, and `notification-service` — is
written once, against the MicroProfile Reactive Messaging API, with no
reference anywhere in the method body to Kafka, a broker address, or a
serialization format. What moves a `PaymentCaptured` record from a
producer method to a consumer method is decided entirely in configuration:
`smallrye-kafka` in `application.properties` for every environment this
project ships to, and SmallRye's in-memory connector (`InMemoryConnector`)
for the test JVM, which it does not ship to. This chapter shows both wiring
paths with code from
[shipping-service]({{ site.repo_tree }}/examples/shipping-service) and where
the in-memory connector's resemblance to Kafka ends.

## Vert.x in-memory messaging on its own

Before comparing the two transports, it helps to see what in-memory messaging
is on its own. Quarkus runs on Vert.x: a small set of **event-loop threads**
(by default about twice the number of cores) handle non-blocking work, and a
separate **worker pool** runs blocking work such as `@Blocking` methods. The
Vert.x **event bus** connects components inside one JVM with three
patterns: *send* (point-to-point to one consumer), *publish* (to every
consumer of an address), and *request-reply*.

{% include excalidraw.html file="20-vertx-in-memory" alt="One JVM containing event-loop threads and a worker pool. Producers (Emitter or @Outgoing methods) hand messages to the Vert.x event bus, which supports send, publish and request-reply. Consumers (@Incoming or @ConsumeEvent methods) receive them on an event loop or a worker thread. Callouts: scales up with cores, no network hop or wire serialization, back-pressure through Mutiny. Limits: one JVM, not durable, no replay." caption="Figure A5.1 — Vert.x in-memory messaging inside one JVM" %}

Delivery is a method call within the process: no network hop, no wire
serialization, and throughput grows with the cores available to the event
loops and worker pool. Back-pressure comes from the Mutiny/Reactive Streams
plumbing between producer and consumer. The limits follow from the same
design: the messages live in one JVM's memory, so they are not durable, a
crash loses whatever was in flight, and there is no replay for a late or
restarted consumer.

The Quarkus event bus API looks like this. This snippet is illustrative and
does not exist in this repository, which uses the in-memory *connector*
below rather than direct event-bus calls:

```java
// Illustrative only: not in this repository.
@ApplicationScoped
public class GreetingService {

    @ConsumeEvent("greeting")          // point-to-point address
    public String greet(String name) { // return value is the reply
        return "Hello " + name;
    }
}

// Caller side:
//   bus.<String>request("greeting", "world")   -> request-reply (Uni)
//   bus.send("greeting", "world")              -> one consumer, no reply
//   bus.publish("greeting", "world")           -> every consumer
```

This repository reaches the same in-memory machinery through the
Reactive Messaging API: `smallrye-in-memory` is a connector that swaps in
for Kafka on a channel, which is what the rest of this chapter uses.

## Kafka messaging on its own

Kafka adds a durable, partitioned log between producers and consumers.
Producers append to topic **partitions**; a **consumer group** divides the
partitions among its members, so each record is processed by one member per
group, while a second group reads the same topic independently (fan-out).
Offsets record each group's position, and retention keeps records after they
are read, so a consumer can replay from an earlier offset. Schemas for the
records live in Apicurio Registry.

{% include excalidraw.html file="20-kafka-messaging" alt="Producers append to a topic with partitions P0 to P3. Consumer group A has replicas that each own some partitions. Consumer group B reads the same topic independently, which is fan-out. Retention and offsets allow replay. Apicurio Registry holds the schemas. Scale out by adding consumers up to the partition count; KEDA scales on consumer lag." caption="Figure A5.2 — Kafka: partitions, consumer groups, and replay" %}

Throughput scales out by adding consumers to a group, up to the number of
partitions; beyond that, extra members sit idle. In this project KEDA scales
`notification-service` on consumer lag (see Chapter 16). The cost is the
network hop, serialization, and operating a broker. Chapter 16 shows the same
mechanism used the other way: a per-replica group gives every replica every
event.

{% include excalidraw.html file="20-inmemory-vs-kafka" alt="Two columns side by side. Left column, labeled 'In-memory (Vert.x) connector — tests': a single JVM box containing an InMemorySource, the ShipmentProcessor.process method annotated @Incoming/@Outgoing, and an InMemorySink, all connected by in-process method calls with no network hop and no broker. Right column, labeled 'Kafka connector — %prod': two separate JVM boxes (payment-service and shipping-service) each talking over the network to a Kafka broker box in the middle holding the payment.captured and shipment.dispatched topics with partitions and an Apicurio Schema Registry box beside it for Avro schemas. Below both columns, a trade-off table with rows for latency, coupling, durability, ordering guarantees, back-pressure, and testing ergonomics, with the in-memory column marked fast/tightly-coupled/non-durable/single-JVM-only and the Kafka column marked network-latency/decoupled/durable/partition-ordered/broker-mediated-back-pressure." caption="Figure A5.3 — In-memory vs. Kafka: same code, different connector" %}

## The code that doesn't change

[`ShipmentProcessor`]({{ site.repo_blob }}/examples/shipping-service/src/main/java/com/patterncatalyst/datamesh/shipping/ShipmentProcessor.java)
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
([`Topics.java`]({{ site.repo_blob }}/examples/domain-model/src/main/java/com/patterncatalyst/datamesh/domain/Topics.java)) resolve to the plain strings
`"payment-captured"` and `"shipment-dispatched"` — logical Reactive Messaging
*channel ids*, not topic names. Channel ids are the one name
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

"Unified" has a limited meaning here. Quarkus's Vert.x event loop and worker-thread pools are
the single execution substrate underneath *every* reactive-messaging
channel, Kafka or in-memory: SmallRye Kafka's consumer records are delivered
onto that same Vert.x context, and `@Blocking` methods like
`ShipmentProcessor.process` are dispatched to the same Vert.x worker-thread
pool regardless of which connector produced the incoming message. What
*differs* is everything upstream of that dispatch point — whether the bytes
arriving at the channel came off a TCP socket to a broker (Kafka) or
were handed directly from one Java list to another inside the same JVM
(in-memory). The execution model is shared; the transport, the wire format,
and the failure modes are not.

## In-memory: `InMemoryConnector` in `shipping-service`'s tests

`shipping-service` has exactly one place that uses the in-memory connector:
[`ShipmentProcessorTest`]({{ site.repo_blob }}/examples/shipping-service/src/test/java/com/patterncatalyst/datamesh/shipping/ShipmentProcessorTest.java),
wired in by a `QuarkusTestResourceLifecycleManager` named
[`InMemoryChannelsTestResource`]({{ site.repo_blob }}/examples/shipping-service/src/test/java/com/patterncatalyst/datamesh/shipping/InMemoryChannelsTestResource.java).
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
was last cleared, which is why the test file's Javadoc flags a
gotcha: the sink is scoped to the `@QuarkusTest` instance's lifetime, not to
one `@Test` method, so `ShipmentProcessorTest` has to explicitly
`connector.sink(...).clear()` in a `@BeforeEach` — otherwise
`redeliveryOfSameOrderIsIdempotent`'s second test method would see the
leftover `ShipmentDispatched` from the first method's run and assert on the
wrong message count. That's a sharp edge specific to the in-memory
connector's test-scoped state, with no Kafka analogue (a fresh consumer
group against a fresh topic doesn't carry state between JUnit methods the
same way).

The comment on `InMemoryChannelsTestResource` explains why it exists: it lets `ShipmentProcessorTest` exercise `ShipmentProcessor`'s
choreography logic — consume `PaymentCaptured`, derive and persist a
`Shipment`, emit `ShipmentDispatched`, and specifically the idempotent-
redelivery guard — "without a running Kafka broker or Apicurio Registry."
No Testcontainers, no Dev Services startup for Kafka, no schema
registration round trip. The test still needs Postgres (via Dev Services)
for the `Shipment` persistence inside `process`, so it is not broker-free
*and* database-free — only broker-free.

## Kafka: `shipping-service` and `payment-service` in `%prod`

The same two channel ids that `ShipmentProcessorTest` redirects to memory
are, in shipping-service's
[application.properties]({{ site.repo_blob }}/examples/shipping-service/src/main/resources/application.properties), wired
to `smallrye-kafka` with explicit Avro (de)serializers and commit/offset
settings (shown in full in the codetabs comparison at the end of this
chapter).

The topic name (`payment.captured`, dot-separated) is a
different string from the channel id (`payment-captured`, hyphenated) — the
channel id is local to this service's wiring; the topic name is
the shared, physical, cross-service contract, defined once in
`Topics.PAYMENT_CAPTURED_TOPIC`
(`Topics.java`, above) and referenced the same way by
payment-service's outgoing side
([application.properties]({{ site.repo_blob }}/examples/payment-service/src/main/resources/application.properties)):

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
services to it. The `%prod` profile makes the cross-process
contract explicit, in both services' `application.properties`:

```properties
%prod.kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVERS:kafka:9094}
%prod.mp.messaging.connector.smallrye-kafka.apicurio.registry.url=${APICURIO_REGISTRY_URL:http://apicurio:8080/apis/registry/v3}
```

That one line separates "two methods calling each other in a test JVM" from
"two independently deployed services agreeing on a wire protocol": a TCP
connection to a named broker host — one image, its broker target
supplied by an environment variable, so the same build serves Compose and
Kubernetes. Explicit Avro
(de)serializer classes are set on every channel rather than left to
connector autodetection; the comment in `shipping-service`'s properties
file documents why — `order-service` found that Apicurio's
split-package layout across `apicurio-registry-avro-serde-kafka` and
`apicurio-registry-serde-common-avro` breaks Quarkus's serde
autodetection and silently falls back to JSON, which would put a
non-Avro payload on a topic every other consumer expects to be Avro.

## Comparing the two connectors

**Latency.** In-memory delivery is a direct method call plus whatever
Vert.x context-switching Quarkus does internally — no network hop, no TCP
handshake, no broker-side fsync, and no consumer poll interval to wait out.
Kafka delivery crosses a socket to a broker process, is appended to a
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
nothing about it is written to disk or survives a JVM restart, and  A Kafka topic persists its log to disk,
replicates it (configuration permitting), and lets a consumer recover a
backlog after a restart by re-polling from a committed offset —
`shipping-service`'s `enable.auto.commit=false` plus
`auto.offset.reset=earliest` is specifically there so a restarted consumer
with no committed offset replays from the start of the topic rather than
silently skipping backlog, a concern that has no in-memory equivalent
because there is no backlog once the test JVM exits.

**Ordering guarantees.** Kafka guarantees order only within a partition, not
across an entire topic — a detail this project's single-partition dev/test
topics don't surface, but a partitioned production topic would. The
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
assertion can run. This reduces test startup time and moving parts, and `shipping-service`
makes that trade for this one test class. It is not, however, a
replacement for an integration test against a real broker: it cannot catch
a serializer misconfiguration (the exact `order-service` Avro-vs-JSON bug
the properties-file comment documents), a topic name mismatch between
`payment-service` and `shipping-service`, a schema-compatibility break in
Apicurio, or a consumer-group rebalance edge case, because none of those
failure modes exist in a path that never touches a serializer, a topic
name, a schema registry, or a consumer group.

## Where this project uses in-memory

The in-memory connector appears in exactly one
place in this codebase, `shipping-service`'s test tree, and nowhere in any
`main` source set. Every `%prod` and Docker Compose deployment path runs on
`smallrye-kafka` against a broker, every cross-service contract is a
Kafka topic plus an Apicurio-registered Avro schema, and the in-memory connector is not used as a production transport, and
SmallRye does not position it as one. For
your own service, the pairing above still holds: unit-test the *business
logic* a `@Incoming`/`@Outgoing` method expresses in-memory, and keep a
broker-backed test (Dev Services' Testcontainers-backed Kafka, which
`shipping-service`'s other, non-in-memory tests already get automatically) for
anything that depends on serialization, partitioning, or cross-process
delivery.

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
  deploys.
- The in-memory connector is faster and simpler to test against because it skips everything that makes Kafka a durable, decoupled,
  cross-process transport — serialization, partitioning, broker-side
  persistence, and consumer-group coordination — none of which an
  in-memory test can validate.



---

*Verification status: <span class="status status--verified">verified</span>. `ShipmentProcessorTest` passes against the in-memory connector under `mvn verify`, with the sink-clearing `@BeforeEach` preventing cross-test bleed. The new Vert.x event-bus material (`@ConsumeEvent`, send/publish/request-reply) and the Kafka scaling description (partition-count limit, KEDA on lag) are <span class="status status--conceptual">conceptual</span> or illustrative and were not run here.*
