---
title: "Quarkus vs. Spring Boot"
order: 13
part: The Quarkus deep-dive
description: "The same order-service data product, rebuilt as a Spring Boot twin, measured side by side on the JVM — startup time and resident memory, and what is and isn't being compared."
duration: 40 minutes
marker: "13"
---

Every claim about a framework is cheap until you run the same workload on
both. This chapter does exactly that: it takes `order-service` — the data
product you met in [chapter 3]({{ '/docs/03-services-and-data-products/' | relative_url }})
— and stands a **Spring Boot twin** next to it that does the same job, then
measures both on the JVM.

The twin lives at [spring-boot-compare]({{ site.repo_tree }}/examples/spring-boot-compare). It is *not*
a second mesh: it is one service, built to be a fair mirror of one Quarkus
service, so the numbers reflect the framework and not a difference in scope.
This chapter is the only place in the deep-dive that steps outside Quarkus
entirely — every other chapter in Part 4 takes Quarkus as a given and shows
what it can do; this one exists to answer a question any reader who's spent
eleven chapters inside one framework will eventually have: what the same
service would have cost to build in the framework most teams already know.

## What the twin is

A standalone Spring Boot **4.1.1** project on the **same JDK 25** the rest of
the repo targets. It is kept out of the Quarkus Maven build
([pom.xml]({{ site.repo_blob }}/examples/pom.xml)'s `<modules>` list runs from `domain-model` through
`ai-rules-service` and does not mention `spring-boot-compare` anywhere) —
Spring Boot wants its own `spring-boot-starter-parent`, so mixing the two
parents in one module would only create dependency-management friction, and
the comparison would measure a Spring Boot project
bent to fit Quarkus's BOM and plugin wiring rather than an idiomatic,
unmodified Spring Boot build. The project's own [pom.xml]({{ site.repo_blob }}/examples/spring-boot-compare/pom.xml) says as much in a
comment at the top of the file: the project ships one runnable twin so the
comparison uses a measured number.

Despite living outside the Maven build, the twin is not a clean-room
reimplementation. It reuses the project's framework-agnostic jars rather than
copying anything: the shared `domain-model` DTOs (`OrderDto`, `OrderStatus`,
`Topics`) and the `contracts` module's generated Avro
`capstone.order.v1.OrderPlaced` are the *identical* classes both services
use. There is zero schema or DTO drift between the two.

Concretely, that means `spring-boot-compare`'s [pom.xml]({{ site.repo_blob }}/examples/spring-boot-compare/pom.xml) declares
`domain-model` and `contracts` as plain `<dependency>` jars at
`${datamesh.domain-contracts.version}`. Those jars have to be `mvn
install`-ed to the local repository before the twin can build, because
`spring-boot-compare` is a standalone Maven project and cannot `-am` build
its siblings the way a module of that build can. Both the README and
[compare-quarkus-springboot.sh]({{ site.repo_blob }}/scripts/compare-quarkus-springboot.sh) run that install step explicitly
before touching the twin at all.

The payoff for that extra step is real: the `OrderPlaced` Avro record the
twin's Kafka producer serializes is the exact same generated class
`order-service` serializes, compiled from the exact same `.proto`/Avro
schema source in `contracts`. There is no hand-copied field list to drift
out of sync as the schema evolves.

Feature parity is the whole point, so the twin carries the **same dependency
surface** as the Quarkus order-service:

| Capability | Quarkus order-service | Spring Boot twin |
|---|---|---|
| REST API (`POST`/`GET /orders`, `GET /orders/{id}`) | `quarkus-rest` + Jackson | `spring-boot-starter-web` |
| Persistence (Postgres, table `orders`) | Hibernate ORM **Panache** (active record) | **Spring Data JPA** (`OrderRepository`) |
| Health | `quarkus-smallrye-health` (`/q/health`) | `spring-boot-starter-actuator` (`/actuator/health`) |
| Event publish (`order.placed`, Avro via Apicurio) | `quarkus-messaging-kafka` + Apicurio Avro | `spring-kafka` + `spring-boot-kafka` + Apicurio Avro |
| Internal API (inventory `CheckStock`) | `quarkus-grpc` `@GrpcClient` | grpc-java client (stubs generated from the same `contracts` proto) |

The REST surface matches down to the status codes — `201` on create, `409`
on insufficient stock, `404` on an unknown id, `503` when inventory is
unreachable — because both map to the same `OrderDto` and implement the same
pre-persist `CheckStock` guard. [OrderController.java]({{ site.repo_blob }}/examples/spring-boot-compare/src/main/java/com/patterncatalyst/datamesh/springcompare/OrderController.java)
makes that guard explicit: `placeOrder` calls `stockChecker.check(sku, qty)`
before anything is persisted. It catches
`StockChecker.StockCheckUnavailableException` to return `503` rather than
letting an order through it couldn't validate, and returns `409` when stock
isn't available. Only then does it save the `OrderEntity` and
publish — in that order, so a client never sees an order acknowledged
before it's durable, the same discipline the Quarkus side follows. The gRPC
client is included because the synchronous internal call to
`inventory-service` is central to how this architecture works, so leaving it
out of the twin would understate Spring's real dependency surface and
flatter its numbers unfairly.

[GrpcClientConfig.java]({{ site.repo_blob }}/examples/spring-boot-compare/src/main/java/com/patterncatalyst/datamesh/springcompare/GrpcClientConfig.java)
wires a plain `io.grpc` `ManagedChannel` — plaintext, `@Value`-overridable
host/port with the identical `INVENTORY_GRPC_HOST`/`INVENTORY_GRPC_PORT`
env var names and the same port-9000 default the Quarkus side's
`quarkus.grpc.clients.inventory.*` properties use. The channel talks to stub
classes generated by the `protobuf-maven-plugin` from the *same* `contracts`
proto, not a hand-rolled client. The twin's own `StockChecker` interface is
seamed behind a Spring `@Profile`: `GrpcStockChecker` (the real
implementation, active everywhere except `dev-no-inventory`/`test`) fails
closed on any `StatusRuntimeException`, mapping it to
`StockCheckUnavailableException` (`503`). This mirrors the Quarkus
order-service's handling of the identical exception type, since both
clients sit on the same underlying gRPC library.

Health is the one row where the two frameworks answer differently
rather than just using different package names: Quarkus's
`quarkus-smallrye-health` aggregates readiness from every extension that
registers a check automatically, while Spring Boot's
`spring-boot-starter-actuator` does the same via `HealthIndicator` beans —
functionally equivalent, but neither one was put in the critical path of
this chapter's own measurement, for a reason the methodology section below
explains.

## The one real code difference: persistence idiom

Everything the two services *do* is the same; the one place the code
diverges is how each talks to the database. Quarkus's Panache makes the entity
its own repository (active record); Spring Data derives a repository interface.
Both round-trip the identical `orders` table.

{% include codetabs.html langs="Quarkus|Spring Boot" %}
```java
// order-service — Panache active record: the entity IS the repository.
@Entity
@Table(name = "orders")
public class Order extends PanacheEntityBase {
    @Id @Column(length = 36, nullable = false, updatable = false)
    public String id;
    @Column(name = "customer_id", nullable = false)
    public String customerId;
    // ... itemSku, quantity, amount, status, createdAt ...
}

// OrderResource — query straight off the entity:
Order.<Order>listAll(Sort.by("createdAt").descending());
Order order = Order.findById(id);
```
```java
// spring-boot-compare — JPA entity + a derived Spring Data repository.
@Entity
@Table(name = "orders")
public class OrderEntity {
    @Id @Column(length = 36, nullable = false, updatable = false)
    private String id;
    @Column(name = "customer_id", nullable = false)
    private String customerId;
    // ... itemSku, quantity, amount, status, createdAt + getters ...
}

public interface OrderRepository extends JpaRepository<OrderEntity, String> {
    List<OrderEntity> findAllByOrderByCreatedAtDesc();
}

// OrderController — query through the repository:
orderRepository.findAllByOrderByCreatedAtDesc();
orderRepository.findById(id);
```

Neither idiom is "more correct" — they're two answers to the same design
question (where query logic should live) that each framework's ecosystem has
converged on by default. Panache's active record collapses `OrderRepository`
out of existence entirely: `Order.listAll(...)` and `Order.findById(id)` are
static methods on the entity itself, so `OrderResource` talks directly to
`Order`, with nothing in between. Spring Data JPA keeps the repository as a
named interface — `OrderRepository extends JpaRepository<OrderEntity,
String>` — and derives `findAllByOrderByCreatedAtDesc()` from the method
name alone, no query body written by hand. `OrderController` is constructed
with an `OrderRepository` injected through its constructor rather than
reaching for a static method on `OrderEntity`.

The practical consequence shows up in the entities themselves: `Order`
extends `PanacheEntityBase` and exposes plain public fields, while
`OrderEntity` is a conventional getter/setter-bearing JPA entity with no
framework base class at all. Spring Data doesn't require (or offer) an
active-record option, so the comparison isn't "Quarkus chose active record,
Spring chose repository." It's closer to "active record is what Panache
*is*, and a derived repository is what Spring Data *is*" — a team adopting
either framework inherits that idiom as a near-default rather than picking
it independently. Both map to the identical `orders` table with the
identical column names and constraints. This is purely a code-organization
difference, not a schema one — the twin's Postgres rows are indistinguishable
from order-service's.

## A Spring Boot 4.0 gotcha the twin had to work around

Reusing `domain-model`'s and `contracts`' jars unmodified meant the twin had
to make Spring Boot's own auto-configuration cooperate with a strongly-typed
`OrderPlaced` producer, and that didn't work out of the box. [KafkaConfig.java]({{ site.repo_blob }}/examples/spring-boot-compare/src/main/java/com/patterncatalyst/datamesh/springcompare/KafkaConfig.java)
exists for exactly one reason, documented in its own Javadoc: Spring Boot's
Kafka auto-configuration only exposes a raw `KafkaTemplate<Object, Object>`,
and that generic type does not satisfy the type-aware autowire `@Autowired
KafkaTemplate<String, OrderPlaced>` would need in `OrderEventProducer` — left
unaddressed, the application context fails to start. The fix is not
to hand-write the whole producer configuration (bootstrap servers,
serializers, the `apicurio.registry.*` passthrough already correctly derived
from [application.properties]({{ site.repo_blob }}/examples/spring-boot-compare/src/main/resources/application.properties)'s `spring.kafka.*` keys) a second time; it's
to reuse the auto-configured `ProducerFactory` bean Spring Boot already built
and re-wrap it in a correctly-typed `KafkaTemplate`:

```java
@Bean
@SuppressWarnings({"unchecked", "rawtypes"})
public KafkaTemplate<String, OrderPlaced> orderPlacedKafkaTemplate(ProducerFactory producerFactory) {
    return new KafkaTemplate<>((ProducerFactory<String, OrderPlaced>) producerFactory);
}
```

Behavior is identical to what auto-configuration would have produced; only
the type is fixed. It's a small, five-line change, but it illustrates a
sharp edge that doesn't show up in a framework's marketing copy: even a twin
built to be as idiomatic as possible still needed one explicit
`@Configuration` class to bridge Spring Boot's generic auto-configuration to
a schema-aware Avro producer, surfacing the first time a real, strongly-typed
event contract meets a generic-erasure-based DI container. [application.properties]({{ site.repo_blob }}/examples/spring-boot-compare/src/main/resources/application.properties)
carries a parallel note about the producer's `value-serializer`: on the
Spring side it's set explicitly for parity and documentation with the
Quarkus side, which has to set the equivalent property explicitly to dodge
an Avro serializer autodetection ambiguity of its own (two Avro serdes on
the classpath, covered in chapter 11's Reactive Messaging section) — two
different frameworks, two different reasons, the same practical lesson:
don't trust Kafka serializer autodetection in either stack once Avro and
dependency management get involved.

## How the numbers were captured

The comparison lives in one script, [compare-quarkus-springboot.sh]({{ site.repo_blob }}/scripts/compare-quarkus-springboot.sh),
and it is worth understanding *how* it measures before trusting *what* it
measured. The script builds both services, then boots them one at a time —
never concurrently, so neither competes with the other for CPU or memory —
against one shared, throwaway `postgres:18` container, with both JVMs
launched under the identical system properties
(`-Dorg.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1
-Duser.timezone=UTC`) so neither gets an unfair head start from JIT-friendly
flags the other lacks.

The unusual part is what it measures startup *against*. The
obvious choice — poll `/q/health` or `/actuator/health` until it returns
`200` — doesn't work here, because the script points
`KAFKA_BOOTSTRAP_SERVERS` at a dead port for both services. Both
frameworks' Kafka reactive-messaging health indicators report `DOWN` for as
long as the broker is unreachable, so the *aggregate* health endpoint would
never turn green regardless of whether the application itself had finished
booting — a health-based wait would time out on both sides and prove
nothing. Instead, `wait_for_started()` polls each service's own log file for
the framework's self-reported "boot complete" line — Quarkus's `started in
X.XXXs. Listening on: ...` and Spring Boot's `Started
SpringBootCompareApplication in X.XXX seconds` — via one regex
(`STARTED_LOG_REGEX`) that matches both phrasings, and `extract_started_in()`
re-parses that same line for the self-reported number in the results table.
Resident memory is sampled the instant that line appears, reading
`/proc/<pid>/status`'s `VmRSS` field (falling back to `ps -o rss=` if `/proc`
isn't readable), and wall-clock time is `date +%s%3N` bracketing the
process launch and the started-line detection. Every cell the script could
not measure prints the placeholder `<measured-on-run>`
rather than a fabricated number — the script's own header is explicit that
it never invents a result, and a boot failure within the 90-second budget is
a hard failure (`fail()`, with the last 60 log lines dumped), not a silently
blank cell.

{% include excalidraw.html file="12-quarkus-vs-spring-boot" alt="Side-by-side startup diagram: order-service (Quarkus, built-time metaprogramming) and spring-boot-compare (Spring Boot 4.0.8, classpath scanning and reflection at startup) both booting against the same throwaway postgres:18 container under identical JVM flags, each measured via its own self-reported started log line rather than an aggregate health check, ending in the 2.05 s / 337 MB versus 4.02 s / 548 MB comparison" caption="Figure 12.1 — Same workload, same JVM, two startup paths measured identically" %}

Results from one run follow.

## The numbers

Both services were built under their packaged/`prod` profile. Single run on JDK 25.0.3 (Temurin), 2026-10-05, with Quarkus 3.39.5 and Spring Boot 4.0.8 (the repo now pins Quarkus 3.40.1 and Spring Boot 4.1.1; re-run `scripts/compare-quarkus-springboot.sh` to refresh these numbers):

| Service | Startup (self-reported) | Startup (wall-clock) | Resident memory (RSS) |
|---|---|---|---|
| **order-service** (Quarkus) | **2.05 s** | 2.22 s | **337 MB** |
| **spring-boot-compare** (Spring Boot) | 4.02 s | 4.45 s | 548 MB |

On this run, the Quarkus service starts in roughly **half the time** and
boots into roughly **60% of the resident memory** of the Spring Boot twin
carrying the same REST + JPA + Kafka/Avro + gRPC surface. That gap is the
practical payoff of Quarkus's build-time metaprogramming: work that Spring
does by classpath scanning and reflection at startup, Quarkus does once at
build time.

## Like-for-like with the JDK 25 AOT cache (Project Leyden)

The table above compares two JVMs that both pay full class loading and linking
at startup, and Quarkus moves much of that work to build time. JDK 25 lets
any application move it too: the AOT cache (JEP 483, with the one-step
workflow from JEP 514 and ergonomics from JEP 515) stores loaded and linked
classes from a training run and maps them at the next launch. Running both
services with it shows how much of the gap is the framework and how much is
JVM class-loading cost that the JDK can remove for either. Chapter 11
([Figure 11.5]({{ '/docs/11-quarkus-capability-tour/' | relative_url }})) draws the startup paths this
adds next to native image, and Figure 11.7 shows how the cache is trained and
used.

`scripts/compare-quarkus-springboot.sh --aot` runs the default JVM
measurement first, then repeats it per service with plain JDK flags and no
framework-specific packaging, so neither side gets an advantage:

1. **Training run.** `java -XX:AOTCacheOutput=<file>.aot -jar ...` boots the
   service against the same Postgres container. At the framework's
   "started" line the script sends `SIGTERM` and waits for the JVM to exit,
   because the cache is assembled at exit. It then asserts the `.aot` file
   exists.
2. **Measured run.** `java -XX:AOTCache=<file>.aot -XX:AOTMode=on -jar ...`.
   `AOTMode=on` makes the JVM fail at startup if the cache cannot be used
   (different JDK, changed classpath), so a stale cache fails the run
   instead of producing a plain-JVM number.
3. **Layout.** Quarkus trains on `quarkus-run.jar` as built. Spring Boot's
   executable jar nests its dependencies, and classes in nested jars cannot
   be cached, so the script first runs
   `java -Djarmode=tools -jar app.jar extract` and trains and runs from the
   extracted `lib/` layout, as the Spring Boot documentation recommends
   for AOT caches.

Results from one run on JDK 25.0.3 (Temurin), 2026-10-05, same machine and
same throwaway `postgres:18` as above:

| Service | Mode | Startup (self-reported) | Startup (wall-clock) | RSS | Cache size |
|---|---|---|---|---|---|
| order-service (Quarkus) | JVM | 2.05 s | 2.22 s | 337 MB | n/a |
| order-service (Quarkus) | JVM + AOT cache | **0.99 s** | 1.21 s | 372 MB | 103 MB |
| spring-boot-compare (Spring Boot) | JVM | 4.02 s | 4.45 s | 548 MB | n/a |
| spring-boot-compare (Spring Boot) | JVM + AOT cache | **1.02 s** | 1.21 s | 446 MB | 123 MB |

With the cache, both services start in about one second, and the startup gap
that the table above shows disappears at this resolution. The cache cuts
Quarkus's startup by about half and Spring Boot's by about three quarters,
so a large share of the earlier Spring Boot gap is class loading and linking
that the JDK can do ahead of time. Memory moves the other way for Quarkus
(337 MB to 372 MB) and down for Spring Boot (548 MB to 446 MB); Quarkus keeps
a smaller footprint without the cache, and the two are 74 MB apart with it.
Quarkus's build-time work remains an advantage in the default packaging and
in memory without a training step; the cache narrows startup for both.

Caveats:

- **Same JDK and classpath.** The cache is valid only for the JDK build and
  the classpath that produced it. Any dependency or JDK change needs a new
  training run, which is why the measured run uses `AOTMode=on`.
- **RSS includes the mapped cache.** The cache is memory-mapped, so pages
  touched at startup count toward resident memory. Quarkus's RSS rose with
  the cache for that reason, and the RSS comparison is not a heap comparison.
- **Single run.** One run per cell on one machine, no averaging. The JVM
  rows repeat the main table; absolute numbers vary between runs, so compare
  ratios.
- **Training coverage.** The training run only boots the service against a
  database and an unreachable Kafka. A longer training run that exercises
  request paths would cache more classes, and was not measured.
- **Quarkus's own AOT packaging is not used.** The comparison uses plain JDK
  flags on both sides so it stays symmetric.

## What this comparison is *not*

Being precise about the boundaries is what keeps the numbers meaningful:

- **JVM only.** The main table is a JVM-to-JVM comparison, with the AOT cache
  section above as the only other mode — no native image on either
  side, and **no native build was run for this project**. Quarkus's native
  story (the commonly cited figures are sub-100 ms startup and tens of MB of
  RSS — general Quarkus numbers, not measured here) is a separate axis you can
  exercise yourself via the opt-in [demo-native.sh]({{ site.repo_blob }}/demos/demo-native.sh) (see
  [chapter 11]({{ '/docs/11-quarkus-capability-tour/' | relative_url }})); it
  is kept out of this chapter so the
  table compares like with like.
- **Indicative, not a benchmark.** These are single-run measurements on one
  developer machine, with no JIT warm-up or averaging across runs. They show a
  clear directional difference; they are not a statistically rigorous
  benchmark, and your absolute numbers will differ.
- **The write paths are mocked in tests, not the measurement.** The twin's
  unit test mocks the gRPC `StockChecker` and the Kafka producer (the same way
  the Quarkus side's unit tests do), so neither project's *test suite* proves
  the live gRPC round-trip or an Avro publish — those are exercised by the
  demos, not the test. The startup/RSS measurement above boots the
  production wiring (both the gRPC channel and the Kafka producer initialize), so the
  numbers include that dependency surface.
- **One idiom differs by design.** Panache (active record) vs Spring Data JPA
  (repository) is a real, intentional idiom difference, not a thing held
  constant. The entity mapping and the `orders` table are identical; only the
  access style differs.

## When to reach for which

The runtime numbers are one input, not the decision. Quarkus's faster startup
and smaller footprint matter most where you pay for them repeatedly — scale-to-zero
and autoscaling (see [chapter 7]({{ '/docs/07-elastic-and-resilient/' | relative_url }}),
where KEDA scales on demand), dense multi-tenant deployments, and short-lived
or serverless workloads. Spring Boot's enormous ecosystem and the team
familiarity behind it are real, countervailing advantages. The accurate reading
of this table is narrow and useful: *for the same data product, on the JVM,
Quarkus starts faster and uses less memory* — weigh that against everything
else you already know about both frameworks.

---
*Verification status: <span class="status status--verified">verified</span>. Both services build and boot, the twin's `mvn verify` passed (OrderControllerTest 4/4), and `scripts/compare-quarkus-springboot.sh` was run on JDK 25.0.3 (Temurin) on 2026-10-05 in default JVM mode and with `--aot`: both exited 0, the default JVM table and the AOT table above come from that single run (Quarkus 2.05 s / 337 MB against Spring Boot 4.02 s / 548 MB on the plain JVM), and the `--aot` run used `-XX:AOTMode=on`. Each figure is a single run. Native image is outside this JVM-to-JVM comparison; chapter 11 records its own run (`demo-native.sh`, 2026-10-06).*
