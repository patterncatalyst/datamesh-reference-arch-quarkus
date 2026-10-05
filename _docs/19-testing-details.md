---
title: "Testing, in detail: the full pyramid and the single-entry runner"
order: 19
part: Appendices
description: "A ground-up walk through this project's test pyramid — @QuarkusTest unit tests, failsafe *IT integration tests on self-provisioned Testcontainers, the Newman functional collection, and hey/ghz load passes — tied together by scripts/run-all-tests.sh."
duration: 35 minutes
marker: "19"
---

Every other chapter in this tutorial shows one capability at a time and
verifies it with a demo script. This appendix steps back and looks at
*testing itself* as a cross-cutting concern: what kind of test this project
uses for which kind of claim, which of those tests can run with nothing but
a JDK and a Docker daemon, which need a live, fully-wired stack listening on
real host ports, which are deliberately gated off because they depend on a
local LLM, and how
[run-all-tests.sh]({{ site.repo_blob }}/scripts/run-all-tests.sh) sequences all of it into one
command instead of leaving a contributor to remember the right order of
`mvn`, `docker compose`, Newman, and two load scripts.

{% include excalidraw.html file="19-testing-pyramid" alt="A four-tier test pyramid for the datamesh-reference-arch-quarkus reactor. Base tier: unit tests, @QuarkusTest classes compiled and run by maven-surefire-plugin under mvn test, no Docker required, Quarkus Dev Services not invoked. Second tier: integration tests, classes named *IT such as OrderPlacedAvroWireIT and InventoryCheckStockWireIT, run by maven-failsafe-plugin under mvn verify, each self-provisioning its own Testcontainers (Kafka, Apicurio Registry) or running as a packaged @QuarkusIntegrationTest process, no standing compose stack needed. Third tier: functional tests, the Newman/Postman collection in tooling/newman/datamesh.postman_collection.json exercising order-service, inventory-service, graphql-gateway, and review-service over real HTTP against a live stack. Top tier: load tests, hey driving HTTP traffic at order-service and ghz driving gRPC traffic at inventory-service's CheckStock RPC, both reading throughput and latency percentiles from their own summaries. Alongside the pyramid, a vertical strip shows scripts/run-all-tests.sh's phases in order: PREFLIGHT, UNIT+IT (mvn verify), TWIN (spring-boot-compare), STACK-UP, FUNCTIONAL, LOAD, REPORT, with a note that STACK-UP only happens after every mvn phase completes to avoid port collisions." caption="Figure A4.1 — The test pyramid and the run-all-tests.sh phases" %}

## The pyramid, bottom to top

### Unit tests: `@QuarkusTest`, plain `mvn test`

The base of the pyramid is the ordinary Quarkus unit test: a class
annotated `@QuarkusTest` (or a plain JUnit 5 test with no Quarkus
annotation at all), compiled and executed by `maven-surefire-plugin` when
you run `mvn -f examples/pom.xml test`. The reactor
[pom.xml]({{ site.repo_blob }}/examples/pom.xml)'s
`pluginManagement` pins `maven-surefire-plugin` (and `maven-failsafe-plugin`)
to the same version property, `surefire-plugin.version` (3.5.2), and adds
one reactor-wide system property to both: `user.timezone=UTC`, which exists
to prevent a real failure mode — the `postgres:18` Dev Services container
this project's `@QuarkusTest` classes implicitly start rejects legacy Olson
zone IDs (e.g. `US/Eastern`) that `pgjdbc` forwards from the host's default
timezone, failing container boot with
`invalid value for parameter "TimeZone"`. Pinning the test JVM to UTC
sidesteps that regardless of host or CI-runner timezone.

A `@QuarkusTest` for a service that talks to Postgres, Kafka, or Apicurio
doesn't need any of those already running: Quarkus Dev Services detects the
missing connection properties at test-boot time and starts its own
ephemeral Testcontainers for the duration of the test run, then tears them
down. That's what makes this tier "CI-headless-capable" in
`run-all-tests.sh`'s own vocabulary — more on exactly what that means later
in this chapter.

By Maven/Surefire-Failsafe convention (not anything this project had to
configure specially), Surefire's default include pattern only picks up
`*Test`-suffixed classes; a class named `*IT` is compiled by Surefire's
`test-compile` phase but never *executed* by `mvn test`. That naming split
is exactly how this project keeps unit tests fast and dependency-light: a
plain `mvn test` run never pays the cost of spinning up a Kafka or Apicurio
container for a class written specifically to exercise one.

### Integration tests: failsafe `*IT`, self-provisioned Testcontainers

The second tier is the integration test — a class named `*IT`, bound into
`maven-failsafe-plugin`'s `integration-test`/`verify` goals, which only run
under `mvn -f examples/pom.xml verify`. Several of this project's modules
(for example `order-service`) have to bind that execution explicitly in
their own `pom.xml`, because the parent reactor pom's `pluginManagement`
only *pins the version* and the UTC system property; it binds no execution.
order-service's
[pom.xml]({{ site.repo_blob }}/examples/order-service/pom.xml) spells this out in its own comment: "Without this
execution, `*IT` classes are compiled by `test-compile` but failsafe never
runs them under `mvn verify`." The same block also documents a second,
unrelated gotcha this module's integration tests hit: Avro 1.12.x's
`ClassSecurityValidator` refuses to build a `SpecificDatumWriter` for a
generated record class whose package isn't explicitly trusted unless a
Quarkus application is actually running — `OrderPlacedAvroWireIT` is a
plain JUnit test with no `@QuarkusTest` bootstrap driving a raw
`KafkaProducer`, so without an explicit trusted-package system property it
failed with `SecurityException: Forbidden capstone.order.v1.OrderPlaced!`
(confirmed, per the comment, by actually running the IT and hitting it).

What distinguishes this tier from the live-stack functional/load tiers is
that an `*IT` is still self-contained: it either spins up its own
Testcontainers directly, or — for `@QuarkusIntegrationTest` classes —
Quarkus packages the application once and launches it as a real separate
process, again without anything pre-existing on the host. No
`docker compose up` is required for any test in this tier.

[**`OrderPlacedAvroWireIT`**]({{ site.repo_blob }}/examples/order-service/src/test/java/com/patterncatalyst/datamesh/order/OrderPlacedAvroWireIT.java)
is the sharpest example of why this tier exists. A `@QuarkusTest` for
order-service's REST endpoint could pass even if the Kafka producer
silently fell back from Avro to Quarkus's autodetected Jackson/JSON
serialization — the HTTP response wouldn't change. So this test
deliberately bypasses the application's own Reactive Messaging wiring and
drives a raw `KafkaProducer`/`KafkaConsumer` pair directly against two
self-provisioned Testcontainers: a `KafkaContainer("apache/kafka-native:4.2.0")`
and a `GenericContainer` running `quay.io/apicurio/apicurio-registry:3.1.7`
(configured with `APICURIO_STORAGE_KIND=sql` / `APICURIO_STORAGE_SQL_KIND=h2`,
since Apicurio 3.1.7 removed the plain in-memory `mem` storage kind older
3.0.x images supported). It produces one `capstone.order.v1.OrderPlaced`
record through the exact same `io.apicurio.registry.serde.avro.AvroKafkaSerializer`
the real application uses, then reads the raw bytes back with a vanilla
`KafkaConsumer<byte[], byte[]>` with *no* Avro deserializer configured at
all. The assertions are at the byte level:

```java
assertTrue(rawValue.length > 5,
        "record value too short to carry an Apicurio/Confluent Avro schema id: " + rawValue.length + " bytes");
assertEquals((byte) 0x0, rawValue[0],
        "expected Apicurio/Confluent Avro wire-format magic byte 0x0 as the first byte");
assertTrue(rawValue[0] != 0x7B,
        "record value starts with '{' (0x7B) -- serde has regressed to JSON (Avro wire format expected)");
```

The first byte of an Apicurio/Confluent-framed Avro record is a fixed magic
byte, `0x0`; a JSON payload, by contrast, starts with `{` (`0x7B`). Checking
both — the positive assertion that the magic byte is present *and* the
negative assertion that the first byte definitely isn't `{` — means a
regression to the JSON fallback fails loudly with an assertion message that
names the exact architectural decision it violates — Avro on the wire,
never a silent JSON fallback — rather than failing some unrelated way
downstream. Only after that byte-level proof does the test do an "optional"
round trip: deserializing the same bytes with the real
`AvroKafkaDeserializer` and asserting every field survived the Avro
encoding intact.

[**`InventoryCheckStockWireIT`**]({{ site.repo_blob }}/examples/inventory-service/src/test/java/com/patterncatalyst/datamesh/inventory/InventoryCheckStockWireIT.java)
tests a different layer — gRPC, not Kafka — and uses a different mechanism:
`@QuarkusIntegrationTest`, which boots the already-packaged
`quarkus-run.jar` as a genuinely separate OS process rather than running
in-JVM. That matters because there's no CDI container in the *test's* own
JVM to inject a `@GrpcClient` into, so the test instead builds a plain
`io.grpc.ManagedChannel` plus the generated `InventoryServiceGrpc` blocking
stub pointed at `localhost:9000`. The more interesting detail is in its
`@BeforeAll`: because the packaged app under test boots with the `prod`
profile, `import.sql` — the seed data the demos and Newman collection rely
on in dev mode — never loads. Rather than depend on seed data that won't be
there, the test seeds its own fixtures over the REST surface first:

```java
seedStock("WIDGET-1", 50);
seedStock("WIDGET-2", 12);
```

...posting directly to `POST /stock` via `java.net.http.HttpClient`, using
the `test.url` system property Quarkus sets for the launched
integration-test process (falling back to `http://localhost:8081` — see
the port-collision note below). Only after that self-seed does it open the
gRPC channel and exercise three branches of `CheckStock`: enough stock
(`WIDGET-1`, quantity 10 against 50 on hand → `available=true`), *not*
enough stock (`WIDGET-2`, quantity 100 against 12 on hand →
`available=false`), and a SKU never seeded at all (`DOES-NOT-EXIST` →
`available=false`, `quantityOnHand=0`). The pattern — self-seed, then
exercise the real wire protocol, with no dependency on dev-mode fixtures or
a standing stack — is deliberate; the class Javadoc calls it out explicitly
as "consistent with how the other wire-level ITs set up their own
fixtures."

Worth noting: a third `*IT` in this same tier does
*not* currently run:
[`OrderChoreographyChainIT`]({{ site.repo_blob }}/examples/order-service/src/test/java/com/patterncatalyst/datamesh/order/OrderChoreographyChainIT.java)
is written and compiles — it would produce one `order.placed` Avro event
and assert a `PaymentCaptured` record appears on `payment.captured`
followed by a `ShipmentDispatched` record on `shipment.dispatched` — but it
is annotated `@Disabled`. Its own Javadoc explains why: proving that full
choreography chain needs `payment-service`'s and `shipping-service`'s real
Reactive Messaging consumers actually running and consuming/producing
against the same broker, and neither module currently has a container
image or any other independently-launchable artifact in this project. The
class is kept fully written specifically so that re-enabling it later is a
one-line `@Disabled` removal once those two services have a real way to
run standalone in CI, rather than something a future reader has to
reconstruct from scratch. That's a useful pattern in its own right: a
disabled test with a dated, specific reason beats either deleting the
intent or leaving a silently-skipped test with no explanation.

### The TWIN phase: the standalone Spring Boot comparison

`run-all-tests.sh` folds in a fourth, less obvious tier between IT and the
live-stack phases: the **TWIN** phase, which builds `domain-model` and
`contracts` (`mvn -pl domain-model,contracts -am install -DskipTests`) and
then runs `mvn test` against spring-boot-compare's
[pom.xml]({{ site.repo_blob }}/examples/spring-boot-compare/pom.xml) — the
one runnable Spring Boot twin service this project ships for a real
side-by-side comparison. Per the script's own header comment,
`OrderControllerTest` in that module uses `@ServiceConnection` plus
Testcontainers, which needs a reachable Docker daemon the same way IT does,
but — like IT — needs no standing compose stack. That's why TWIN is grouped
with UNIT and IT as "CI-headless-capable" rather than with the live-stack
phases below it.

### Functional tests: the Newman/Postman collection

The third tier moves outside Maven entirely. `tooling/newman/` holds a
Postman collection,
[datamesh.postman_collection.json]({{ site.repo_blob }}/tooling/newman/datamesh.postman_collection.json),
run against a live stack via
[run-newman.sh]({{ site.repo_blob }}/tooling/newman/run-newman.sh). Per
[tooling's README.md]({{ site.repo_blob }}/tooling/README.md), this collection is grouped into five folders —
Health, Inventory, Order, GraphQL, and Review — covering roughly twenty
requests: health probes for all four services; inventory stock seeding,
lookup, and a 404 case; order placement (including a deliberate
insufficient-stock case) and lookup (including a 404 case); one federated
GraphQL query joining order and stock data; and review creation,
validation, lookup, and an unauthenticated-delete-protection check. Each
request carries one or more `pm.test(...)` assertions, so a full run
exercises dozens of them — the exact total Newman reports depends on how
many folders you include (`run-newman.sh --folder <name>` scopes a run to
just one), so this chapter states that qualitatively rather than citing a
number that could go stale the next time a request is added or removed.

`run-newman.sh` doesn't just hand off to Newman blindly — it health-probes
order-service, inventory-service, graphql-gateway, and (unless `--folder`
restricts the run to something other than Review) review-service first,
and fails loud with the exact bring-up command needed if anything is down,
rather than letting Newman grind through a wall of connection-refused
errors that obscures what actually failed. `tooling/README.md` also
documents three things this collection explicitly does **not** cover:
forcing order-service's gRPC call to inventory-service to fail (a manual
check), a real authenticated `DELETE /reviews/{id}` → 204 (which needs a
live Keycloak bearer token — the default run only proves the 401
unauthenticated-protection path), and the notification WebSocket, neither
an HTTP nor a gRPC unary endpoint that Newman, `hey`, or `ghz` can reach.

### Load tests: `hey` for HTTP, `ghz` for gRPC

The top of the pyramid is capacity, not correctness:
[load]({{ site.repo_tree }}/tooling/load) holds
two scripts,
[load-orders.sh]({{ site.repo_blob }}/tooling/load/load-orders.sh) (HTTP, via `hey`) and
[load-checkstock.sh]({{ site.repo_blob }}/tooling/load/load-checkstock.sh)
(gRPC, via `ghz`), both built on the same
[_demo.sh]({{ site.repo_blob }}/demos/lib/_demo.sh) harness
every demo script uses — `require`/`fail`/`step`/`narrate`/`wait_http` — on
the principle, stated in both scripts' headers, that "a load run that
short-circuits before producing a summary must never read as clean."

`load-orders.sh` defaults to a safe, read-only `get` mode
(`GET {{base}}/orders`), but also supports an opt-in `post` mode that first
seeds `WIDGET-1` with a large stock quantity on inventory-service
(`POST /stock`, `quantityOnHand: 100000`) so the ramp of real
`POST /orders` traffic doesn't 409 on insufficient stock.
`tooling/README.md` documents a sample 20-second GET-mode run against a
warm dev-mode order-service reaching roughly 1098 requests/sec with a
99th-percentile latency around 22ms and a clean `[200] 21987 responses`
distribution — illustrative numbers from one run on one machine, not a
performance guarantee, but a sanity check for what "working" load output
looks like.

`load-checkstock.sh` targets `capstone.inventory.v1.InventoryService/CheckStock`
over plaintext HTTP/2 gRPC (`ghz --insecure`, since inventory-service never
terminates TLS here) at inventory-service's canonical gRPC port,
`localhost:9000`. Because gRPC has no easy `curl` probe, the script
health-gates on inventory-service's HTTP `/q/health` instead, reasoning
that a live health endpoint on the same process is strong evidence the
gRPC server started in the same Quarkus boot is also up.
`tooling/README.md`'s sample 20-second run shows `ghz` sustaining roughly
9921 requests/sec with a 99th-percentile latency near 5ms against a warm
dev-mode inventory-service.

Both scripts share one set of named profiles rather than leaving a reader
to guess flag combinations: **smoke** (`-c 5 -z 10s`), **nominal**
(`-c 10 -z 20s`, the default both scripts and `run-all-tests.sh` itself
use), and **stress** (`-c 25 -z 60s`).

## CI-headless vs. live-stack: what needs what

This is the single most load-bearing design decision in the whole runner:
UNIT, IT, and TWIN are all **CI-headless-capable** — a CI runner with
Docker-in-Docker and a JDK can run all three with no other services, no
exposed ports, and no manual bring-up, because Dev Services and
Testcontainers provision and tear down everything each phase needs for
itself. STACK-UP, FUNCTIONAL, and LOAD, by contrast, need a genuinely
**live** stack: compose infra (Postgres, Kafka,
Apicurio) plus order-service (8091), inventory-service (8092 HTTP / 9000
gRPC), graphql-gateway (8080), and review-service (8098) all actually
listening on real host ports at the same time. Those three phases bind real
ports, run considerably longer, and are therefore gated behind `--load` or
`--all` rather than being part of a fast inner-loop check.

## The Ollama-gated integration tests

Three `*IT` classes in this project —
`OrderTriageFlowRouteIT` and `OrderTriageRouteIT` in `ai-rules-service`, and
`OrderAssistantRouteIT` in `ai-mcp-service` — depend on a real, locally-
running Ollama model and are **never** run by `run-all-tests.sh`. Each is
annotated:

```java
@EnabledIfSystemProperty(named = "ollama.tests.enabled", matches = "true")
```

`run-all-tests.sh` never sets that property, so a plain `mvn verify` run
already skips all three with no extra exclusion flag needed — this is an
opt-in allowlist, not something the runner has to actively suppress.
Running one deliberately looks like:

```bash
mvn test -Dollama.tests.enabled=true -Dtest=OrderTriageRouteIT \
    -f examples/pom.xml -pl ai-rules-service
```

(ai-rules-service's
[README.md]({{ site.repo_blob }}/examples/ai-rules-service/README.md) and
ai-mcp-service's
[README.md]({{ site.repo_blob }}/examples/ai-mcp-service/README.md) document the
equivalent invocations for the other two classes.) This is the same
`ollama.tests.enabled` gate discussed from the application-behavior side in
Chapter 14, applied here purely as a test-opt-in mechanism: these three
tests need an actual model to talk to, and nobody should discover that by
watching `mvn verify` hang or fail against a daemon that was never started.

## The 8081 port-collision constraint

Two independent facts about port 8081 collide with each other. First,
Quarkus's own default *test* HTTP port is `8081` — what
`InventoryCheckStockWireIT` falls back to
(`System.getProperty("test.url", "http://localhost:8081")`) when no
`test.url` property is set. Second, order-service's own default *dev-mode*
HTTP port is *also* `8081` by Quarkus convention, and that collides with
`APICURIO_PORT=8081` in
[.env.example]({{ site.repo_blob }}/.env.example) — the host port the compose stack's
Apicurio Registry container publishes on.
[demo-graphql.sh]({{ site.repo_blob }}/demos/demo-graphql.sh)'s header
comment documents this: order-service runs with its HTTP port explicitly
overridden to `8091` because its own default collides with compose's
Apicurio host port, and `graphql-gateway`'s `ORDER_SERVICE_URL` is pointed
at `8091` to match.

`run-all-tests.sh`'s own STACK-UP phase follows the same convention,
launching order-service with `-Dquarkus.http.port=8091` explicitly. This is
also the concrete reason the script's header insists on **strict phase
ordering**: UNIT, IT, and TWIN must all run to completion *before*
STACK-UP ever brings up compose or starts a service, since a
`@QuarkusTest`/`*IT` run via Dev Services can itself claim ephemeral ports,
including 8081, that would otherwise collide with a standing stack's
already-bound ports. Running the Maven phases to completion first means
those test runs never have a standing stack to collide with, and the live
stack never has to coexist with a test JVM binding a port out from under
it — an ordering the script's own comment says must not change.

## Walking `run-all-tests.sh`'s phases and flags

`scripts/run-all-tests.sh` ties every tier above into one command, in a
fixed sequence it enforces regardless of which flags you pass:

```bash
scripts/run-all-tests.sh                 # everything (default)
scripts/run-all-tests.sh --unit          # fast inner-loop check, no Docker needed
scripts/run-all-tests.sh --it            # unit + IT + twin, needs Docker
scripts/run-all-tests.sh --load          # live-stack Newman + load pass only
scripts/run-all-tests.sh --all --keep-up # full run, leave the stack up after
```

With no phase flag at all, the script behaves as `--all`, which expands to
`--unit --it --load` together. Passing `--it` alone implies unit coverage
too — the script's own comment is explicit that it "never runs `test` then
`verify` back to back"; when IT is requested, the UNIT+IT phase runs
`mvn verify` once, which already exercises every `@QuarkusTest` as well as
the bound `*IT`s, rather than paying for `mvn test` and then `mvn verify`
separately.

The phases, in the fixed order the script runs and reports them:

1. **PREFLIGHT** — checks `mvn`, `java`, `curl`, and `jq` are on `PATH`,
   and that the Docker daemon is reachable (`docker info`). If `--load` or
   `--all` is set, it additionally checks for `hey`, `ghz`, and either
   `newman` or `npx`. Any failed check aborts the whole run before anything
   else executes, with an actionable fix hint attached to each check (for
   example, `sdk install java 25-tem` for a missing JDK).
2. **UNIT+IT** — `mvn -f examples/pom.xml verify` (if `--it`/`--all`) or
   `mvn -f examples/pom.xml test` (if only `--unit`). A failure here is
   recorded as FAIL but does **not** abort the rest of the run — the
   comment explains this choice: "continuing so the rest of the pyramid
   still reports," so one broken tier doesn't hide whether downstream tiers
   are healthy.
3. **TWIN** — only runs if `--it`/`--all`: builds `domain-model` and
   `contracts`, then runs `mvn test` against spring-boot-compare's `pom.xml`.
4. **STACK-UP** — only runs if `--load`/`--all`: copies `.env.example` to
   `.env` if missing, runs `docker compose up`, polls Postgres readiness
   for up to 30 seconds, packages order-service/inventory-service/graphql-gateway
   (`mvn -DskipTests package`), then starts all three as background
   processes with explicit, collision-avoiding port overrides, plus
   review-service via `mvn quarkus:dev` (its own Dev Services bring up
   Postgres and Keycloak). Every step gates on a health check
   (`wait_http ".../q/health/live"`) before moving on, and seeds
   `WIDGET-1` stock on inventory-service once it's healthy.
5. **FUNCTIONAL** — only runs if STACK-UP succeeded: invokes
   `tooling/newman/run-newman.sh` with no arguments (the full collection,
   all five folders).
6. **LOAD** — only runs if STACK-UP succeeded: runs both
   `tooling/load/load-orders.sh -c 10 -z 20s` and
   `tooling/load/load-checkstock.sh -c 10 -z 20s` — the "nominal" profile
   from `tooling/README.md`'s table.
7. **REPORT** — always runs, printing a PASS/FAIL/SKIP line for every
   phase regardless of how far the run got, and exiting non-zero if any
   phase shows FAIL.

`--keep-up` changes only the cleanup behavior: the script installs an
`EXIT` trap the moment it's about to bring anything up (the same "this
script owns it" idiom
[demo-order.sh]({{ site.repo_blob }}/demos/demo-order.sh)/`demo-graphql.sh`
use for their own
compose lifecycle), so a Ctrl-C or any later failure still tears the stack
down — unless `--keep-up` is set, leaving compose and the four services
running to poke at manually.

## What you learned

- The four real tiers in this project's pyramid are unit (`@QuarkusTest`,
  Surefire, Dev Services, fully CI-headless), integration (`*IT`, Failsafe,
  self-provisioned Testcontainers or a packaged `@QuarkusIntegrationTest`
  process, also CI-headless), functional (the Newman/Postman collection
  against a live stack), and load (`hey` for HTTP, `ghz` for gRPC) — plus a
  parallel TWIN tier that runs the standalone Spring Boot comparison
  service's own tests under the same CI-headless umbrella as unit and IT.
- `OrderPlacedAvroWireIT` and `InventoryCheckStockWireIT` are the two
  concrete examples of what a wire-level `*IT` actually buys you that a
  `@QuarkusTest` can't: byte-level proof that a Kafka payload is really
  Avro and not a silent JSON fallback, and proof that a packaged,
  separately-running process answers a real gRPC call correctly after
  seeding its own fixtures (since `import.sql` doesn't load under `prod`).
- `OrderChoreographyChainIT` is a fully-written but `@Disabled` test —
  a clear marker of a gap (no launchable payment-service/shipping-service
  artifact exists yet) rather than a silently-skipped or deleted one.
- The Ollama-gated `*IT`s are opt-in by design (`ollama.tests.enabled`),
  not actively excluded, so `run-all-tests.sh` never has to know about them
  at all.
- Port 8081 is both Quarkus's default test HTTP port and order-service's
  default dev-mode port, and it collides with compose's own
  `APICURIO_PORT=8081` — which is why order-service always runs on `8091`
  in this project's demos and in `run-all-tests.sh`'s STACK-UP phase, and
  why the Maven phases must finish completely before any live stack comes
  up.
- One script, `scripts/run-all-tests.sh`, sequences every tier in a fixed
  order a contributor never has to memorize, reports every phase's
  PASS/FAIL/SKIP regardless of where the run stopped, and defaults to
  running everything when given no flags at all.

---

*Verification status: <span class="status status--verified">verified</span>. The automated tiers run green — `mvn verify` across the reactor (unit + integration with self-provisioning Testcontainers), the Spring Boot twin build, and continuous testing (6/6). The Newman functional collection and the hey/ghz load scripts are documented but were not exercised in this pass.*
