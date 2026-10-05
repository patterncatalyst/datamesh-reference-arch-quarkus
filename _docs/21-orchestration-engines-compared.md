---
title: "Appendix: the three orchestration engines, compared in depth"
order: 21
part: Appendices
description: "Kafka choreography, Camel orchestration, and Quarkus Flow orchestration compared over the same order-triage domain: coupling, failure handling, debuggability, where logic lives, testing, and operational cost."
duration: 40 minutes
marker: "21"
---

[Chapter 13]({{ '/docs/13-orchestration-styles/' | relative_url }}) introduced the terms:
**choreography** (Kafka — no coordinator, every participant reacts on its
own) versus **orchestration** (Camel and Quarkus Flow — a single component
sequences the steps), and showed that two things can both be
"orchestration" while disagreeing sharply on whether that sequence is
written as imperative code or declared as data. This appendix takes the same three engines and the same code and covers
the dimensions Chapter 13 only touched: who knows the sequence when
something goes wrong in production, what failure handling looks like in
each engine as this repo builds it, what debugging each one involves, where
the business logic lives versus where the coordination lives, how each
shape is tested, and what each costs to operate. It assumes the
three-mechanism model from Chapter 13.

{% include excalidraw.html file="21-three-engines-compare" alt="Three-column comparison of Kafka choreography, Camel orchestration, and Quarkus Flow across who owns the sequence, coupling, failure handling, debugging, and where logic lives." caption="Figure A6.1 — Choreography vs. two shapes of orchestration, compared" %}

The implementations behind every claim in this appendix:
`order-service`, `payment-service`, `shipping-service`, and
`notification-service` for the choreography leg (each one's
`@Incoming`/`@Outgoing` reactive-messaging methods), and
[`OrderTriageRoute.java`]({{ site.repo_blob }}/examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/OrderTriageRoute.java)
and
[`OrderTriageWorkflow.java`]({{ site.repo_blob }}/examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/OrderTriageWorkflow.java)
(plus its `OrderTriageFlowRunner` bridge) for the two orchestration legs.

## Who knows the sequence

In the choreography chain, no file in the repo contains the string
"order.placed, then payment.captured, then shipment.dispatched" as a
single artifact. `PaymentProcessor.process` in
[`PaymentProcessor.java`]({{ site.repo_blob }}/examples/payment-service/src/main/java/com/patterncatalyst/datamesh/payment/PaymentProcessor.java)
is annotated `@Incoming(Topics.ORDER_PLACED_CHANNEL)` /
`@Outgoing(Topics.PAYMENT_CAPTURED_CHANNEL)` — it knows it consumes one
topic and produces another, and nothing more. `ShipmentProcessor.process`
in
[`ShipmentProcessor.java`]({{ site.repo_blob }}/examples/shipping-service/src/main/java/com/patterncatalyst/datamesh/shipping/ShipmentProcessor.java)
is annotated the
mirror image, `@Incoming(Topics.PAYMENT_CAPTURED_CHANNEL)` /
`@Outgoing(Topics.SHIPMENT_DISPATCHED_CHANNEL)`. Each method's own code is
a complete description of what *it* does; that these two methods
happen to chain into a three-hop saga is a fact about the system, not a
fact recorded in either method, or in `OrderEventProducer` (which only
knows it publishes `order.placed` after an order commits), or anywhere
else. `notification-service`'s `OrderPlacedConsumer.consume` subscribes to
the same `order-placed` channel `PaymentProcessor` does — a second,
independent reaction to the same event, running in parallel with the
payment/shipping chain, not after it. Reconstructing "what happens when an
order is placed" means reading four files in four Maven modules and
mentally joining them by topic name; the system has that knowledge, no
single artifact in it does.

`OrderTriageRoute` is the opposite extreme on this axis. The `from("direct:triage")`
route is eleven lines, and those eleven lines *are* the sequence:
unmarshal, call `classify`, log, call `decide`, marshal. A reviewer reading
that route top to bottom has read the entire business process for that
endpoint, in order, with nothing elided. `OrderTriageWorkflow`'s
`descriptor()` method occupies the same conceptual slot but answers "what's
the sequence" with a *document* instead of a *trace*: `FlowWorkflowBuilder.workflow("order-triage").tasks(...)`
builds a `Workflow` object — the same shape, structurally, as a CNCF
Serverless Workflow document — that a human or a tool can inspect without
executing it. The Camel route's sequence knowledge lives in control flow;
the Flow workflow's sequence knowledge lives in a data structure that
is interpreted by an engine. Both beat choreography on "where
do I even look," but they beat it in different senses: the Camel route is
"knowable by reading code," the Flow workflow is "knowable by reading (or
diffing, or versioning) data."

## Coupling

Coupling in this repo is best measured by asking: what has to change, and
where, when a step is added? Adding a fifth reaction to `order.placed` —
say, an analytics service — costs `order-service` nothing. It doesn't
import a client for the new service, doesn't add a call, doesn't even know
it exists; `OrderEventProducer.publish` is unchanged. The *new* service
pays the entire cost of wiring itself up, exactly as `notification-service`
already does today by independently subscribing to `order-placed` with its
own `@Incoming` method. This is runtime coupling pushed down to "shared
schema" (the `OrderPlaced` Avro type in `capstone.order.v1`, from the
`contracts` module) and nothing else — no participant holds a reference to
another participant's class, bean, or network address.

`OrderTriageRoute` holds a direct `@Inject TriageService triageService`
reference and calls `.bean(triageService, "classify")` — the route is
compiled against `TriageService`'s method signatures. Adding a step means
editing this route: a third `.bean(...)` call, in the right place, in a
file that also contains every other step. `OrderTriageWorkflow` holds the
identical `@Inject TriageService triageService` reference, and its
`FlowDSL.function("classify", triageService::classify)` is a method
reference against the same bean — the coupling to `TriageService` is as tight as Camel's. What differs is the *shape* of what changes
when a third step joins: in Camel you insert a line into a fluent method
chain; in Flow you add an entry to the `.tasks(...)` list the `Workflow`
descriptor returns. Both are edits to one file, reviewed by one diff, at
one deploy — closer to each other on this axis than either is to
choreography, despite the declarative-versus-imperative distinction that dominates
Chapter 13.

## Failure handling and compensation

This dimension is easy to overclaim, so the sections below describe what
this repo implements, not what the engines can do. Each engine can do more
than this repo exercises (Camel's EIPs, Flow's spec-level retry and
compensation), but engine capability is not behavior in this code.

**Choreography's failure handling is per-hop, at-least-once, and
idempotent — not compensating.** `PaymentProcessor.process` and
`ShipmentProcessor.process` both guard against redelivery: `PaymentProcessor`
calls `paymentStore.findByOrderId(orderId)` and returns the existing
`PaymentCaptured` record rather than minting a second payment if the same
`OrderPlaced` event is redelivered; `ShipmentProcessor` does the identical
check against `Shipment.findByOrderId(orderId)`. `OrderPlacedConsumer` in
notification-service mirrors the same guard before inserting a
`Notification` row. That is failure handling, and it is what makes
at-least-once Kafka delivery safe to build on, but there is no
compensation:
there is no code anywhere in this project that reacts to a *failed*
payment by emitting a compensating event that un-dispatches a shipment, or
reacts to a failed shipment by refunding a captured payment. `PaymentProcessor`'s
own Javadoc notes this: every order is captured immediately, and a
production payment service would call a payment gateway that could decline
a capture; that branching is out of scope for this example. If
`payment-service` throws partway through processing an `OrderPlaced`
event, the message's redelivery (driven by Kafka consumer group semantics,
not application code) is the only safety net this repo wires up — there is
no saga orchestrator, no dead-letter topic config visible in any of the
four services' `application.properties`, and no compensating-transaction
logic to walk the chain backwards. That is a reasonable scope for a reference
architecture, but a reader building a production saga needs to add that
layer.

**Camel's failure handling is also unexercised beyond default behavior in
this route.** `OrderTriageRoute`'s `triage-order` route has no
`.onException(...)` clause and no custom `errorHandler(...)` — if
`triageService.classify` throws (for instance, because `TriageService.classify`'s
own Jackson parse of the LLM's output fails), Camel's default error
handler propagates the exception back through the REST binding as an
error response. (EIPs like `.doTry()/.doCatch()`, dead-letter-channel error
handlers, and redelivery policies with backoff are the first-class Camel
features this route doesn't reach for.) What Camel does provide automatically,
and what this route relies on implicitly, is that any exception thrown
mid-route stops that route's execution at the point of failure — there's
no risk of `decide` running against a `classify` that silently returned
garbage, because an exception out of `.bean(triageService, "classify")`
never reaches the next step.

**Quarkus Flow's failure handling is, in this repo, the same as Camel's:
unexercised.** `OrderTriageWorkflow`'s descriptor declares two
`FlowDSL.function` tasks and nothing else — no retry policy, no declared
compensation task, no `switchCase` for an error branch. `OrderTriageFlowRunner.run`
calls `workflow.startInstance(order)` and `.await().atMost(Duration.ofSeconds(120))`
on the resulting `Uni` — a timeout exists at the *caller* boundary (120
seconds, not indefinite), but that's HTTP-call hygiene, not workflow-level
compensation. (The CNCF Serverless Workflow specification that
`quarkus-flow` implements does have retries and compensating actions as
first-class document constructs — the nuance Chapter 13 did not cover: Flow's declarative shape makes compensation
*expressible as data* in a way Camel's imperative shape doesn't naturally
offer — but `OrderTriageWorkflow` doesn't use that vocabulary. "Flow supports retries as data" does not mean this workflow has
retries.)

In summary: today, all three legs lean on idempotency and at-least-once
delivery (choreography) or exception propagation (both orchestration legs)
rather than any compensating-transaction logic. The difference is *where you would add it*: in choreography you'd add
a new consumer reacting to a failure event (itself published as a new
event, keeping the pattern decentralized); in Camel you'd add
`.onException()` clauses to the one route; in Flow you'd add
retry/compensation nodes to the one workflow document — three different
answers to "where does the fix go," none of which this repo needs to
answer today because none of the three legs implements compensation yet.

## Debuggability

A production incident forces a specific question: where do you put your
eyes first? For the choreography chain, the answer is "it depends which
hop is slow or silent," and the diagnostic path is per-service: check
`order-service`'s logs and the `order.placed` topic to confirm the publish
happened, then `payment-service`'s logs and the `payment.captured` topic,
then `shipping-service`'s. Chapter 13's own demo
([demo-orchestration-styles.sh]({{ site.repo_blob }}/demos/demo-orchestration-styles.sh)) shows this: its Act 1
polls each downstream topic with `kcat` one hop at a time and
queries `shipping-service`'s own Postgres table directly, because there's
no single place that reports "did the whole chain finish." That's the
debugging cost of choreography's loose coupling, paid every time.

`OrderTriageRoute`'s debugging story is a single log stream — the route's
own `.log(...)` calls narrate the request linearly, one request, one
thread, one place to look. `OrderTriageWorkflow`'s is structurally
different: because the workflow is declared as a graph of named tasks
(`"classify"`, `"decide"`), a given instance's progress is inspectable
task-by-task rather than only as an undifferentiated log stream — an
advantage over Camel's route for long-running or branching workflows,
though in this particular two-task, synchronous-from-the-caller's-perspective
workflow (`OrderTriageFlowRunner` blocks on `.await()`) that advantage is mostly theoretical in this project's demo.

## Where the business logic lives

In all three legs, coordination and decision-making are separate
responsibilities. In choreography, `PaymentProcessor.process` and
`ShipmentProcessor.process` *are* the business logic — there's no separate
"coordinator" to strip logic out of, because choreography has no
coordinator. In both orchestration legs, by contrast, the coordinator
(`OrderTriageRoute` / `OrderTriageWorkflow`) contains no business
logic — both delegate every substantive decision to `TriageService.classify`
(one LLM call) and `TriageService.decide` (one Drools
`KieSession.fireAllRules()` call, against
[order-triage.drl]({{ site.repo_blob }}/examples/ai-rules-service/src/main/resources/rules/order-triage.drl)).
This is why Chapter 14 can say "the route coordinates; it does not decide
— Drools does" and have it apply unchanged to the Flow leg: the test for
"did I put a decision in the wrong layer" is the same regardless of
whether the coordinator is a route or a workflow document — if a `.choice()`
EIP or a Flow `switchCase` started encoding `riskSignal == "HIGH"`, that
decision would be leaking out of Drools and into the coordinator, which
neither does today.

{% include codetabs.html langs="Kafka choreography|Camel orchestration|Quarkus Flow" %}
```java
// Kafka choreography — PaymentProcessor.java: reacts to order.placed,
// knows nothing about shipping-service or notification-service downstream.
@Incoming(Topics.ORDER_PLACED_CHANNEL)
@Outgoing(Topics.PAYMENT_CAPTURED_CHANNEL)
public PaymentCaptured process(OrderPlaced orderPlaced) {
    String orderId = orderPlaced.getOrderId();
    PaymentCaptured existing = paymentStore.findByOrderId(orderId);
    if (existing != null) {
        return existing; // idempotent on redelivery, not a compensation
    }
    // ... build and persist PaymentCaptured, return it ...
}
```
```java
// Camel orchestration — OrderTriageRoute.java: one route, no onException,
// imperative top-to-bottom sequencing.
from("direct:triage")
    .routeId("triage-order")
    .unmarshal().json(JsonLibrary.Jackson, OrderCreate.class)
    .bean(triageService, "classify")
    .bean(triageService, "decide")
    .marshal().json(JsonLibrary.Jackson);
```
```java
// Quarkus Flow orchestration — OrderTriageWorkflow.java + OrderTriageFlowRunner.java:
// same two steps, declared as a task graph; the runner awaits with a bounded timeout.
return FlowWorkflowBuilder.workflow("order-triage")
    .tasks(
        FlowDSL.function("classify", triageService::classify),
        FlowDSL.function("decide", triageService::decide))
    .build();

// OrderTriageFlowRunner.run:
return workflow.startInstance(order)
    .onItem().transform(model -> model.as(TriageDecision.class).orElseThrow())
    .await().atMost(Duration.ofSeconds(120));
```

## Testing

The test suites expose the same shape difference the production code does.
Choreography can only be *unit*-tested one participant at a time inside
this project:
[`OrderChoreographyChainIT.java`]({{ site.repo_blob }}/examples/order-service/src/test/java/com/patterncatalyst/datamesh/order/OrderChoreographyChainIT.java)
is `@Disabled`, and its Javadoc explains why — proving the
full `order.placed -> payment.captured -> shipment.dispatched` chain
requires `payment-service`'s and `shipping-service`'s Reactive Messaging
consumers to be running against the same broker, and neither
service has a container image or any other already-built,
independently-launchable artifact here, so there's no way to stand up the
full chain from a single module's test. Each service's own
consumer *is* unit-testable in isolation (feed it an `OrderPlaced`, assert
the `PaymentCaptured` it returns), but the end-to-end saga is only provable
by the live demo script (`demo-orchestration-styles.sh`), not by the
automated test suite — a structural cost of choreography's
decentralization to weigh against its coupling benefits.

`OrderTriageRouteTest` (in the
[airules]({{ site.repo_tree }}/examples/ai-rules-service/src/test/java/com/patterncatalyst/datamesh/airules)
test package) shows the opposite: because the whole sequence lives in one `CamelContext`,
a single `@QuarkusTest` can assert `camelContext.getRoute("triage-order")`
is registered and started, and a second test asserts the sibling
`"triage-flow-order"` route (the thin bridge to the Flow runner) is also
registered — both without ever calling Ollama. The behavioral assertions
(does `/triage` produce `ROUTE_TO_WAREHOUSE` for a given input)
live in separate, opt-in integration tests gated behind a live Ollama
server, because that part of the pipeline is non-deterministic and
shouldn't gate every build. The dividing line in both orchestration legs
matches the production code: wiring is fast, synchronous, and always-on;
behavior (did Ollama and Drools jointly produce the right decision) is
slower, non-deterministic, and opt-in. Choreography doesn't get to draw
that same line as cleanly, because "is the chain correctly assembled"
already requires multiple live services to answer.

## Operational cost

Running choreography in production means running, monitoring, and
independently scaling and deploying four services plus a Kafka cluster
plus a schema registry — `order-service`, `payment-service`,
`shipping-service`, and `notification-service` are four separate Maven
modules, each with its own `application.properties`, database, and failure
domain. The payoff is that those four things fail, deploy, and scale
independently: a slow `notification-service` never backs up
`payment-service`, since they share nothing but a topic. Both
orchestration legs run inside a *single* service (`ai-rules-service`) —
one JVM, one deployment, one `application.properties` to tune. That's
cheaper to operate at this scale, but it also means `OrderTriageRoute` and
`OrderTriageWorkflow` share fate: if `ai-rules-service` is down, both
`/api/orders/triage` and `/api/orders/triage-flow` are down together, and
if Ollama (the shared `ChatModel` both call through `TriageService`) is
slow, both feel it identically, since they delegate to the identical bean.
Operational cost, in other words, tracks coupling almost exactly:
choreography's loosest coupling buys the most independent operability at
the highest service-count cost; both orchestration legs buy operational
simplicity at the cost of shared fate for everything that coordinator
touches.

## Reach for which when

| | Kafka choreography | Camel orchestration | Quarkus Flow orchestration |
|---|---|---|---|
| Who knows the sequence | No one artifact — reconstructed from four independent `@Incoming`/`@Outgoing` methods joined by topic name | One route, read top to bottom | One workflow document, read as a declared task graph |
| Failure handling present today | Per-hop idempotency on redelivery (`findByOrderId` guards); no cross-hop compensation | None beyond Camel's default exception propagation; no `.onException()` in this route | None beyond a caller-side timeout (`atMost(120s)`); no retry/compensation task declared |
| Where you'd add compensation | A new consumer reacting to a new failure event | `.onException()` / `.doTry()`-`.doCatch()` on the existing route | A retry/compensation task added to the workflow document (the spec supports it; this workflow doesn't use it) |
| Debuggability | Per-service logs + per-topic inspection; no single "did it finish" answer | One log stream, one thread, one route trace | Per-instance, per-task history — most valuable for long-running or branching workflows |
| Where business logic lives | Inside each participant's own handler method (no separate coordinator exists) | Nowhere in the route — entirely in `TriageService`/Drools | Nowhere in the workflow descriptor — entirely in `TriageService`/Drools |
| Testing | Unit-testable per participant; full-chain IT disabled in this repo for lack of a multi-service test harness | Wiring test (route registered/started) separate from opt-in, Ollama-gated behavioral test | Same split as Camel — wiring vs. opt-in behavioral — plus a mocked-classify unit test the Camel leg doesn't have an equivalent of in this repo |
| Operational cost | Four independently deployed/scaled services + Kafka + schema registry | One service; shared fate with everything else `ai-rules-service` hosts | One service; identical shared fate, same host as the Camel leg |
| Best fit | An event other parts of the system react to, now or later, where the publisher shouldn't know or care who's listening | A fixed process where the sequence is the valuable, reviewable artifact and you want full imperative control (branching, EIPs, try/catch) | The same kind of fixed process, but where you want the sequence as an inspectable/versionable document, and you want the engine's own retry/compensation vocabulary available if you grow into needing it |

This appendix sharpens Chapter 13's rule rather than replacing it. The
comparison is not which style is better but which failures are visible
today versus only *possible to make visible* with a feature neither
orchestration leg currently uses. Camel's imperative route and Flow's declarative document
land in nearly the same place on coupling, logic placement, and today's
failure handling — they differ in *how* you would extend
each one: edit a method chain, or edit a task graph. Choose choreography when you want that question not to arise, since there is
no central artifact to extend.

---

*Verification status: <span class="status status--verified">verified</span>. The orchestration code is exercised green (`OrderTriageRouteTest`, `OrderTriageFlowTest`, `OrderTriageDrlTest`), and `OrderChoreographyChainIT` is confirmed `@Disabled` for the documented reason. The live choreography chain and the Camel/Flow orchestration demos call the local LLM and need the Ollama profile, which was not run.*
