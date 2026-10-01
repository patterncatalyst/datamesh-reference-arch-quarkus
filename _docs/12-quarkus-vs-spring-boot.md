---
title: "Quarkus vs. Spring Boot"
order: 13
part: The Quarkus deep-dive
description: "The same order-service data product, rebuilt as a Spring Boot twin, measured side by side on the JVM — startup time and resident memory, with an honest account of what is and isn't being compared."
duration: 25 minutes
marker: "12"
---

Every claim about a framework is cheap until you run the same workload on
both. This chapter does exactly that: it takes `order-service` — the data
product you met in [chapter 3]({{ '/docs/03-services-and-data-products/' | relative_url }})
— and stands a **Spring Boot twin** next to it that does the same job, then
measures both on the JVM.

The twin lives at `examples/spring-boot-compare/`. It is deliberately *not*
a second mesh: it is one service, built to be a fair mirror of one Quarkus
service, so the numbers reflect the framework and not a difference in scope.

## What the twin is

A standalone Spring Boot **4.0.x** project on the **same JDK 25** the rest of
the repo targets. It is intentionally kept out of the Quarkus Maven reactor
(`examples/pom.xml`) — Spring Boot wants its own `spring-boot-starter-parent`,
so mixing the two parents in one module would only create dependency-management
friction. It reuses the project's framework-agnostic jars rather than copying
anything: the shared `domain-model` DTOs (`OrderDto`, `OrderStatus`, `Topics`)
and the `contracts` module's generated Avro `capstone.order.v1.OrderPlaced`
are the *identical* classes both services use, so there is zero schema or DTO
drift between the two.

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
pre-persist `CheckStock` guard. The gRPC client is included on purpose: the
synchronous internal call to `inventory-service` is central to how this
architecture works, so leaving it out of the twin would understate Spring's
real dependency surface and flatter its numbers unfairly.

## The one real code difference: persistence idiom

Everything the two services *do* is the same; the one place the code genuinely
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

## The numbers

Captured by `scripts/compare-quarkus-springboot.sh`, which builds both
services, boots each under its packaged/`prod` profile against one shared
throwaway `postgres:18`, and records two things per service: wall-clock time
from process launch to the framework's own "started" log line, and resident
set size (RSS) sampled immediately after startup. Both JVMs run with identical
flags (`-Duser.timezone=UTC`, `-Dorg.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1`).

| Service | Startup (self-reported) | Startup (wall-clock) | Resident memory (RSS) |
|---|---|---|---|
| **order-service** (Quarkus) | **1.54 s** | 1.63 s | **314 MB** |
| **spring-boot-compare** (Spring Boot) | 3.21 s | 3.66 s | 494 MB |

On this run, the Quarkus service starts in roughly **half the time** and
boots into roughly **two-thirds the resident memory** of the Spring Boot twin
carrying the same REST + JPA + Kafka/Avro + gRPC surface. That gap is the
practical payoff of Quarkus's build-time metaprogramming: work that Spring
does by classpath scanning and reflection at startup, Quarkus does once at
build time.

## What this comparison is *not*

Being precise about the boundaries is what keeps the numbers honest:

- **JVM only.** This is a JVM-to-JVM comparison — no native image on either
  side. Quarkus's native story (sub-100 ms startup, tens of MB of RSS) is a
  separate axis covered in [chapter 11]({{ '/docs/11-quarkus-capability-tour/' | relative_url }})
  via `demo-native.sh`; it is deliberately kept out of this chapter so the
  table compares like with like.
- **Indicative, not a benchmark.** These are single-run measurements on one
  developer machine, with no JIT warm-up or averaging across runs. They show a
  clear directional difference; they are not a statistically rigorous
  benchmark, and your absolute numbers will differ.
- **The write paths are mocked in tests, not the measurement.** The twin's
  unit test mocks the gRPC `StockChecker` and the Kafka producer (the same way
  the Quarkus side's unit tests do), so neither project's *test suite* proves
  the live gRPC round-trip or a real Avro publish — those are exercised by the
  demos, not the test. The startup/RSS measurement above boots the *real*
  wiring (both the gRPC channel and the Kafka producer initialize), so the
  dependency surface in the numbers is genuine.
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
familiarity behind it are real, countervailing advantages. The honest reading
of this table is narrow and useful: *for the same data product, on the JVM,
Quarkus starts faster and uses less memory* — weigh that against everything
else you already know about both frameworks.

---
*Verification status: <span class="status status--unverified">unverified</span>. The numbers in this chapter are a single-run capture on one machine via `scripts/compare-quarkus-springboot.sh`; confirm on a real run that both services build and boot, that the "started" log lines are detected for each, and that the RSS/startup figures reproduce directionally (Quarkus faster + lighter). The twin's live gRPC `CheckStock` and real Avro publish are exercised by the demos, not its unit test.*
