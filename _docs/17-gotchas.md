---
title: "Gotchas and things to look out for"
order: 17
part: Appendices
description: "Eight pitfalls hit while building this project, each with its symptom, root cause, and the fix applied in this repository's code."
duration: 30 minutes
marker: "17"
---

This appendix covers eight failures this project hit: timezone rejections,
a security validator throwing from a packaged JVM, a port that did not match
between two services, and a test client that dropped a header it was told to
send. Each entry gives the **Symptom** (what you see), the **Root cause**,
and the **Fix** (the change, with the file and config key). Each claim is
backed by a file path, a `git log` entry, or a code comment in this
repository; the verification footer says which fixes are covered by tests.

{% include excalidraw.html file="17-gotchas" alt="A grid of eight gotcha cards, each showing a symptom on top (an error message or a silent false pass) and a fix below it (a one-line config key or code change): postgres:18 rejecting a legacy Olson timezone id fixed by -Duser.timezone=UTC and TZ=UTC/PGTZ=UTC; Avro 1.12's ClassSecurityValidator throwing SecurityException fixed by org.apache.avro.SERIALIZABLE_PACKAGES on both producer and consumer JVMs; a gRPC port mismatch (9001 vs 9000) between order-service and inventory-service fixed by converging on canonical port 9000; a @QuarkusIntegrationTest's separate process not inheriting the test JVM's timezone fixed by quarkus.test.arg-line; import.sql silently not loading under %prod fixed by self-seeding over REST; a class-level @Consumes(APPLICATION_JSON) 415ing a bodyless GET fixed by an explicit @Consumes(WILDCARD), paired with RestAssured silently dropping a Content-Type header on a bodyless GET and masking the bug, fixed by switching the regression test to java.net.http.HttpClient; Avro serde autodetection falling back to silent JSON because two Apicurio artifacts share a package, fixed by pinning value.serializer explicitly; and a general caution card about a persisted postgres named volume surviving a Hibernate DDL change, fixed by docker compose down -v" caption="Figure A2.1 — Gotchas, their symptoms, and their fixes" %}

## 1. postgres:18 rejects the host's legacy timezone id

**Symptom.** A `mvn verify` or Dev Services boot fails with Postgres
refusing to start the connection:

```text
FATAL: invalid value for parameter "TimeZone": "US/Eastern"
```

**Root cause.** pgjdbc forwards the JVM's `user.timezone` to the server as a
session parameter at connection time. On a host whose default timezone is a
legacy Olson zone id (`US/Eastern` rather than `America/New_York`),
`postgres:18`'s stricter timezone-name validation rejects it outright,
where older Postgres versions tolerated it — the reason `compose.yaml` sets
`TZ=UTC`/`PGTZ=UTC` on the container:

```yaml
# TZ=UTC / PGTZ=UTC avoid the US/Eastern boot failure: postgres:18 rejects
# legacy Olson zone ids like US/Eastern forwarded by pgjdbc from a non-UTC
# host.
postgres:
  environment:
    - TZ=UTC
    - PGTZ=UTC
```

Fixing the container side alone isn't enough: `mvn verify` talks to a
Postgres Dev Services/Testcontainers instance from the *test JVM*, which
forwards whatever timezone it resolved from the host — the container's own
`TZ` env var doesn't change what the client sends.

**Fix.** The parent POM ([pom.xml]({{ site.repo_blob }}/examples/pom.xml)) pins `user.timezone`
on both `maven-surefire-plugin` and `maven-failsafe-plugin` so every test
JVM in the project connects as UTC regardless of host locale:

```xml
<plugin>
  <artifactId>maven-surefire-plugin</artifactId>
  <configuration>
    <systemPropertyVariables>
      <!-- Force UTC for the test JVM. The postgres:18 Dev Services
           container rejects legacy Olson zone ids (e.g. US/Eastern)
           that pgjdbc forwards from the host default, failing boot
           with: invalid value for parameter "TimeZone". -->
      <user.timezone>UTC</user.timezone>
    </systemPropertyVariables>
  </configuration>
</plugin>
```

The same block is repeated for `maven-failsafe-plugin`. Belt-and-suspenders:
the container is forced to UTC
([compose.yaml]({{ site.repo_blob }}/compose.yaml)), the test JVM is forced to
UTC (parent `pom.xml`, above), and the server itself is told `timezone=UTC` via
its own `-c` flag — three independent layers, since any one being wrong
reproduces the failure on a host whose locale differs from the author's.

## 2. Avro 1.12's `ClassSecurityValidator` blocks a packaged JVM — on both ends

**Symptom.** `POST /orders` still returns `201` — order placement looks
fine — but nothing ever shows up on the `order.placed` topic, and
`notification-service` never reacts to it. The failure is invisible unless
you read logs, where you'd find:

```text
SecurityException: Forbidden capstone.order.v1.OrderPlaced!
```

**Root cause.** Avro 1.12 added a `ClassSecurityValidator` that only trusts
a short, hardcoded allowlist of packages for (de)serializing
`SpecificRecord` classes unless told otherwise. A Quarkus-bootstrapped
dev/test JVM trusts the application's own packages implicitly; a
`java -jar quarkus-run.jar` packaged/`%prod` JVM does not.
`OrderEventProducer.publish` swallows publish failures by design — "a
publish failure must never fail the already-committed order" — which is
why this defect was invisible at the HTTP layer: the order succeeds, the
event silently never leaves the JVM. This affected the producer side. A
second instance hit the consumer side: `notification-service` is the only
service that deserializes `OrderPlaced` back into a `capstone.order.v1`
`SpecificRecord`, and its packaged JVM throws the identical
`SecurityException` without the same property set on its own process.

**Fix.** `-Dorg.apache.avro.SERIALIZABLE_PACKAGES=<package>` has to be set
on every JVM that encodes or decodes that Avro type outside a
Quarkus-bootstrapped test/dev context — both producer and consumer. In
this repo it's baked into each service's container image rather than
passed at the command line, so it's present regardless of how the image is
launched:

```dockerfile
# examples/order-service/src/main/docker/Containerfile.multistage
ENV JAVA_TOOL_OPTIONS="-Dorg.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1"
```

`payment-service`'s image trusts two packages
(`capstone.order.v1,capstone.payment.v1`) and `shipping-service`'s trusts
`capstone.payment.v1,capstone.shipping.v1` — each service lists exactly the
Avro types it touches, not a blanket wildcard.
[OrderPlacedAvroWireIT]({{ site.repo_blob }}/examples/order-service/src/test/java/com/patterncatalyst/datamesh/order/OrderPlacedAvroWireIT.java),
the byte-level regression test for this, needs the identical system property on
its own failsafe execution (order-service's
[pom.xml]({{ site.repo_blob }}/examples/order-service/pom.xml)) for the same
reason: it's a plain JUnit/Testcontainers test with no Quarkus bootstrap to
auto-trust the package either.

## 3. A gRPC port that quietly didn't match between two services

**Symptom.** `order-service` and `inventory-service` both start cleanly in
isolation — health checks pass, nothing logs an error — but
`POST /orders` against the real packaged pair fails closed:

```text
503 inventory-service unreachable: UNAVAILABLE: io exception
```

**Root cause.** This was a wiring mismatch between two services: `order-service` pinned `quarkus.grpc.clients.inventory.port=9001`
while `inventory-service`'s gRPC server defaulted to port `9000`, and the
[base]({{ site.repo_tree }}/k8s/base) manifests set no explicit inventory
`Service`/env to reconcile the two.
Two Quarkus apps starting without error tells you nothing about whether
their *cross-service* wiring agrees; each one only validates its own
config in isolation.

**Fix.** Converge both sides on one canonical, env-overridable port
(9000) instead of a value hardcoded differently per service:

```properties
# examples/inventory-service/src/main/resources/application.properties
quarkus.grpc.server.port=${INVENTORY_GRPC_PORT:9000}

# examples/order-service/src/main/resources/application.properties
quarkus.grpc.clients.inventory.port=${INVENTORY_GRPC_PORT:9000}
```

[config.yaml]({{ site.repo_blob }}/k8s/base/config.yaml) sets `INVENTORY_GRPC_PORT: "9000"` once, and
[inventory-service.yaml]({{ site.repo_blob }}/k8s/base/inventory-service.yaml) exposes `containerPort: 9000` under the
same name — a single source of truth both sides read, instead of two
numbers kept in sync by hand. The lesson generalizes past gRPC: any value
repeated across file-disjoint config (a port, a topic name, a package)
needs one authoritative source, since file-disjointness alone doesn't
guarantee the copies stay consistent — this exact drift also happened at
the demo-script level (a stale `9001` override lingering after the
service-level default moved to `9000`), caught and corrected separately.

## 4. `@QuarkusIntegrationTest` doesn't inherit the test JVM's `-D` flags

**Symptom.** `mvn verify` passes for every `@QuarkusTest`, but an
`@QuarkusIntegrationTest` fails with the exact same Postgres timezone
error as gotcha #1 — even though the parent POM already sets
`user.timezone=UTC` on the test JVM.

**Root cause.** `@QuarkusIntegrationTest` doesn't run the test inside the
Maven/Surefire test JVM at all — it packages the application and launches
`quarkus-run.jar` as a **separate OS process**, which starts with its own
JVM default timezone resolved from the host, independent of whatever `-D`
flags the launching test JVM was given. Setting `user.timezone=UTC` on the
failsafe execution only affects the process *running the test class*, not
the process *being tested*.
[InventoryCheckStockWireIT]({{ site.repo_blob }}/examples/inventory-service/src/test/java/com/patterncatalyst/datamesh/inventory/InventoryCheckStockWireIT.java)'s
own Javadoc spells this out.

**Fix.** `quarkus.test.arg-line` is the forwarding mechanism Quarkus
provides specifically for this — it passes JVM arguments through to the
launched integration-test process:

```xml
<!-- examples/inventory-service/pom.xml -->
<plugin>
  <artifactId>maven-failsafe-plugin</artifactId>
  <configuration>
    <systemPropertyVariables>
      <!-- InventoryCheckStockWireIT is a @QuarkusIntegrationTest: it
           launches the packaged quarkus-run.jar as a SEPARATE process,
           which does NOT inherit this test JVM's user.timezone=UTC. -->
      <quarkus.test.arg-line>-Duser.timezone=UTC</quarkus.test.arg-line>
    </systemPropertyVariables>
  </configuration>
  <executions>
    <execution>
      <goals><goal>integration-test</goal><goal>verify</goal></goals>
    </execution>
  </executions>
</plugin>
```

A related near-miss: `*IT` classes are compiled by the default
`test-compile` lifecycle binding, but **failsafe itself never runs them**
unless `integration-test`/`verify` are explicitly bound in the module's own
POM — the parent's `pluginManagement` only pins the plugin version and the
timezone property, no executions. Without that explicit `<executions>`
block above, `InventoryCheckStockWireIT` would silently compile and never
run under `mvn verify`, a quieter failure mode than a thrown exception.

## 5. `import.sql` never loads in `%prod` — by design, not by accident

**Symptom.** A freshly packaged `inventory-service` running under `%prod`
starts cleanly, but every stock lookup reports unavailable — the demo SKUs
(`WIDGET-1`, `WIDGET-2`, `GADGET-1`) that exist in dev are not there.

**Root cause.** `inventory-service`'s `%prod` profile sets
`quarkus.hibernate-orm.database.generation=update` rather than
`drop-and-create`, so Hibernate's schema-generation-triggered `import.sql`
loading (which only fires alongside `create`/`drop-and-create`) never runs
outside dev/test. This is intended behavior, not a bug: auto-seeding `%prod`
from a static SQL file would require schema-destructive generation modes,
a default a secure-by-design, data-loss-averse deployment
should refuse. An empty inventory on a fresh production deploy is the
*correct* behavior, not a gap to patch over.

**Fix.** Anything that needs data in a `%prod`-mode service — a demo
script or an integration test — has to seed itself over the real REST
surface rather than assume `import.sql` ran. `InventoryCheckStockWireIT`
does exactly this in its own `@BeforeAll`:

```java
// examples/inventory-service/src/test/java/.../InventoryCheckStockWireIT.java
@BeforeAll
static void setUp() throws Exception {
    // Seed stock over REST (import.sql does not run under the packaged
    // prod profile). The server derives available = quantityOnHand > 0.
    seedStock("WIDGET-1", 50);
    seedStock("WIDGET-2", 12);
    channel = ManagedChannelBuilder.forAddress("localhost", 9000)
            .usePlaintext().build();
    stub = InventoryServiceGrpc.newBlockingStub(channel);
}
```

This is documented in inventory-service's
[README.md]({{ site.repo_blob }}/examples/inventory-service/README.md)'s "Seeding in
`%prod`" section, and every demo script that touches inventory does the
same `POST /stock` dance before relying on it.

## 6. A class-level `@Consumes` 415s a bodyless GET — and RestAssured hides it

**Symptom.** Under real load (a `hey`/load-test run or a browser's actual
`Accept`/`Content-Type` negotiation), `GET /orders` intermittently returns
`415 Unsupported Media Type` instead of the order list — but the
project's own `@QuarkusTest` suite is green and shows no such failure.

**Root cause.** Two compounding issues. First: `OrderResource`'s
`POST /orders` method declares `@Consumes(MediaType.APPLICATION_JSON)`; if a
sibling bodyless `GET` method doesn't declare its own `@Consumes`, RESTEasy
Reactive can match the GET against that `@Consumes(APPLICATION_JSON)`
constraint and reject any client whose `Content-Type` isn't JSON — including
clients like `hey`, which defaults to `text/html`, even though a GET has no
body to parse. Second, and worse: the *first* regression test written for
this used RestAssured, and it passed even with the bug present, because
RestAssured's underlying Apache HttpClient **silently drops a
`Content-Type` header on a bodyless request** — the header was never
sent, so the test could never have caught the 415 it was written to
catch. The commit message for the fix says: *"Rewrote
OrderResourceTest's regression case to use java.net.http.HttpClient (which
actually sends the header on a bodyless GET; RestAssured strips it, making
the prior test a false pass)."*

**Fix.** Declare `@Consumes(MediaType.WILDCARD)` explicitly on every
bodyless `GET`/`DELETE` method, not only the one that triggered
the bug:

```java
// examples/order-service/src/main/java/.../OrderResource.java
// Explicit WILDCARD so this bodyless GET isn't matched against the
// sibling POST method's @Consumes(APPLICATION_JSON) -- without it,
// RESTEasy Reactive 415s any request whose Content-Type isn't JSON
// (e.g. hey's default text/html) even though GET has no body to parse.
@GET
@Consumes(MediaType.WILDCARD)
public List<OrderDto> listOrders() { /* ... */ }
```

And rewrite the regression test to use a client that actually transmits
what it claims to send:

```java
// examples/order-service/src/test/java/.../OrderResourceTest.java
// NOTE: this must NOT be written with RestAssured's given()/get() --
// confirmed empirically that RestAssured silently drops a Content-Type
// header it's told to send on a bodyless GET ... java.net.http.HttpClient
// sends exactly the headers it's given regardless of body.
HttpRequest request = HttpRequest.newBuilder()
        .uri(URI.create(RestAssured.baseURI + ":" + RestAssured.port + "/orders"))
        .header("Content-Type", "text/html")
        .GET()
        .build();
HttpResponse<Void> response = HttpClient.newHttpClient()
        .send(request, HttpResponse.BodyHandlers.discarding());
assertEquals(200, response.statusCode());
```

The same `@Consumes(WILDCARD)` fix was applied identically to
[StockResource]({{ site.repo_blob }}/examples/inventory-service/src/main/java/com/patterncatalyst/datamesh/inventory/StockResource.java)
and
[ReviewResource]({{ site.repo_blob }}/examples/review-service/src/main/java/com/patterncatalyst/datamesh/review/ReviewResource.java)'s
bodyless methods in the same commit
— the pattern was searched for and fixed everywhere it appeared, not only
at the call site that surfaced it.

## 7. Avro serde autodetection silently falls back to JSON

**Symptom.** Nothing throws. `POST /orders` returns `201`. A consumer
reading the topic gets perfectly readable JSON instead of Avro-encoded
bytes — a regression that passes every test that only checks the record
*deserializes*, because JSON deserializes fine too.

**Root cause.** Quarkus's Reactive Messaging / Kafka Avro integration can
usually autodetect the right serializer class from the emitted payload
type, but it fails to here because two Apicurio artifacts share the same
`io.apicurio.registry.serde.avro` package — a split-package situation that
defeats the classpath scanning autodetection relies on. `OrderEventProducer`'s
own class Javadoc documents exactly this:

> Autodetection silently falls back to a Jackson/JSON serializer here
> because two Apicurio artifacts share the
> `io.apicurio.registry.serde.avro` package (split-package), which defeats
> it.

**Fix.** Set `value.serializer` explicitly rather than trust
autodetection:

```properties
# examples/order-service/src/main/resources/application.properties
mp.messaging.outgoing.order-placed.value.serializer=io.apicurio.registry.serde.avro.AvroKafkaSerializer
```

`OrderPlacedAvroWireIT` catches a regression
here: it produces through the real application serializer, then reads the
raw bytes back with a vanilla `KafkaConsumer<byte[], byte[]>` with no Avro
deserializer configured at all, and asserts the first byte is the Avro
wire-format magic byte `0x0` and explicitly **not** `0x7B` (`{`). The check is at byte level because any test that deserializes
through a tolerant reader wouldn't distinguish Avro from a JSON fallback that happens to match the
schema.

## 8. A persisted Postgres volume can outlive the schema you think it has

Unlike the seven gotchas above, this one is presented as general operating
advice rather than a specific incident. A review of this repo's history
found one related concern — a possible stale postgres-data volume — which
was investigated and ruled out: a fresh `%prod` database worked correctly,
and no stale volume was found to have caused drift. It is therefore not
counted as an incident.

The general caution still stands, though, and it's grounded in how this
compose stack is built. `compose.yaml` mounts a **named volume**
(`postgres-data:/var/lib/postgresql`) for Postgres specifically so data
survives a `docker compose down`/`up` cycle — the entire point of a named
volume over an anonymous one. But durability cuts both ways: if an entity's
mapped schema changes (a new `@Column`, a changed `GenerationType`, a
renamed table) and `quarkus.hibernate-orm.database.generation` is anything
short of `drop-and-create`, the running container keeps the *old* on-disk
schema underneath the *new* application code, and you get drift — missing
columns, default-value surprises, or constraint violations — that a
from-scratch environment would never reproduce, because it has no old
schema to collide with. `compose.yaml`'s own comment on
`docker compose down -v` exists for exactly this reason:

```text
docker compose down -v    # stop AND wipe volumes (Kafka KRaft
                          # cluster-id resets, DBs wiped)
```

**Fix (general practice, not a one-time patch):** after any change to an
`@Entity`'s mapped shape, run `docker compose down -v` before the next
`up` to force Postgres to reinitialize from the current schema, rather
than assuming `update` generation mode will reconcile every kind of change
cleanly — it doesn't handle destructive changes (dropped/renamed columns)
at all, and even additive changes are worth verifying against a clean
volume at least once before trusting them in a shared or longer-lived
environment.

## What you learned

- Timezone handling around `postgres:18` needs three independent fixes: the
  container (`TZ`/`PGTZ`), the test JVM (surefire/failsafe `user.timezone`),
  and the packaged process a `@QuarkusIntegrationTest` launches
  (`quarkus.test.arg-line`) — a different JVM that inherits none of the
  other two.
- A security validator or a serializer silently falling back can leave an
  endpoint returning `201`/`200` while the actual side effect (an event
  publish, an Avro-encoded record) fails or degrades; a fine HTTP
  response is not evidence the whole request succeeded.
- A port, topic name, or any value repeated across file-disjoint config
  needs one authoritative source, not N copies kept in sync by hand — this
  repo's own `git log` has an instance of that drift (gRPC 9001 vs
  9000).
- A regression test is only as good as the client it uses: RestAssured
  dropping a `Content-Type` header on a bodyless GET turned a
  regression test into a false pass until it was rewritten against
  `java.net.http.HttpClient`.
- Not every surprising behavior is a bug — `import.sql` not loading in
  `%prod` and a stale-volume concern that turned out not to reproduce were
  both investigated and resolved as working-as-intended.

---

*Verification status: <span class="status status--verified">verified</span>. The committed fixes are re-run green by `mvn verify` — `OrderPlacedAvroWireIT` covers the Avro serde / SERIALIZABLE_PACKAGES fixes, `InventoryCheckStockWireIT` covers the gRPC-port, import.sql self-seed, and integration-test timezone fixes, and `OrderResourceTest` covers the `@Consumes` fix.*
