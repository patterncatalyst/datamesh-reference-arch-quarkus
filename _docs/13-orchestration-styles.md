---
title: "Orchestration styles: choreography vs. two kinds of orchestration"
order: 14
part: The Quarkus deep-dive
description: "Three coordination engines over the same shipping/order domain — Kafka choreography, a Camel route, and a declarative Quarkus Flow workflow — teaching when decentralized reaction beats a named coordinator, and when it doesn't."
duration: 50 minutes
marker: "14"
---

Every event-driven system eventually has to answer one question: when
multiple steps need to happen in sequence, who decides the sequence? This
project runs three different answers side by side, over the same
shipping/order domain, so the distinction can be shown rather than just
defined. Two of the three are "orchestration" by name, but they are not the
same engine, and seeing both makes clear that "orchestration" describes a
*shape* (a coordinator exists), not a specific technology.

The code is in `examples/order-service/`, `examples/payment-service/`,
`examples/shipping-service/`, `examples/notification-service/` (the
choreography leg), and `examples/ai-rules-service/` (both orchestration
legs); `demos/demo-orchestration-styles.sh` runs all three legs back to
back (see "Build, run, observe" below for what each act checks).

## Choreography: no central coordinator

**Choreography** means every participant reacts to events on its own terms,
with no central process telling it when to run. `order-service` publishes
`order.placed` to Kafka and has never heard of `payment-service` or
`shipping-service` — it doesn't know they exist, doesn't call them, and
doesn't wait for anything from them. `payment-service` independently
subscribes to `order.placed`; when one arrives, it captures payment and
publishes `payment.captured`. `shipping-service` independently subscribes to
`payment.captured`; when one arrives, it dispatches a shipment and publishes
`shipment.dispatched`. `notification-service` *also* independently
subscribes to `order.placed` — a fourth reaction to the same original event,
running in parallel with the payment/shipping chain, not after it.

```text
order-service --order.placed--> [Kafka] --> payment-service --payment.captured--> [Kafka] --> shipping-service --shipment.dispatched--> [Kafka]
                                         \-> notification-service (reacts to order.placed directly, in parallel)
```

No service holds a reference to "the whole sequence." Each one only knows
one rule: *when event X arrives, do Y and emit Z* (or, for
`notification-service`, *when event X arrives, do Y* — it emits nothing
further). `demos/demo-orchestration-styles.sh`'s first act proves this by
placing one real order and then reading the raw bytes back off each
downstream topic with `kcat` — a byte-level Kafka consumer, no Avro
deserializer involved on the read side. It asserts the Apicurio/Confluent
wire-format magic byte (`0x00`) is the first byte of each record, which is
the demo's proof that these are genuine Avro-encoded events on Kafka, not a
simulated chain. It also queries `shipping-service`'s own Postgres table
directly (`shippingdb.shipment`) and `notification-service`'s REST surface,
confirming each service's own persisted state independently reflects the
event it reacted to.

The cost of choreography is that there is no single place to read "what
happens when an order is placed" — you have to go find every subscriber.
Its benefit is exactly the same fact stated positively: adding a fifth
reaction to `order.placed` (say, an analytics service) requires zero changes
to `order-service`, `payment-service`, or `shipping-service`. That
loose-coupling property is why event-driven architectures reach for
choreography by default for cross-service reactions — and why the next two
sections exist to show what you gain, and give up, by introducing a
coordinator instead.

## Orchestration: a Camel route

**Orchestration** means a single process explicitly sequences the steps and
knows the whole flow. `ai-rules-service` exposes `POST /api/orders/triage`,
backed by `OrderTriageRoute`
(`examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/OrderTriageRoute.java`):

```java
from("direct:triage")
    .routeId("triage-order")
    .log("Triaging order (Camel): ${body}")
    .unmarshal().json(JsonLibrary.Jackson, OrderCreate.class)
    .bean(triageService, "classify")
    .log("Classification result: ${body}")
    .bean(triageService, "decide")
    .marshal().json(JsonLibrary.Jackson);
```

This route is the coordinator. It explicitly names every step in order:
unmarshal the request, call `classify`, log the intermediate result, call
`decide`, marshal the response. Nothing about this sequence is implicit or
discoverable only at runtime — reading the route top to bottom *is* reading
the business process. `classify` and `decide` are both plain methods on
`TriageService`
(`examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/TriageService.java`):
`classify` sends a single-shot prompt to an injected `langchain4j` `ChatModel`
(backed by Ollama) and parses the category/priority/riskSignal JSON it
returns; `decide` inserts those classified fields as a fact into a Drools
`KieSession` and fires the rules in
`examples/ai-rules-service/src/main/resources/rules/order-triage.drl` to
produce a `FRAUD_HOLD`, `EXPEDITE`, or `ROUTE_TO_WAREHOUSE` decision. The
route coordinates; it does not decide — Drools does.

## Orchestration: a Quarkus Flow workflow

The *same* two-step sequence is orchestrated a second way by
`OrderTriageWorkflow`
(`examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/OrderTriageWorkflow.java`),
reached via `POST /api/orders/triage-flow`:

```java
@ApplicationScoped
public class OrderTriageWorkflow extends Flow {

    @Inject
    TriageService triageService;

    @Override
    public Workflow descriptor() {
        return FlowWorkflowBuilder.workflow("order-triage")
            .tasks(
                FlowDSL.function("classify", triageService::classify),
                FlowDSL.function("decide", triageService::decide))
            .build();
    }
}
```

This is a **declarative** coordinator: instead of imperative route code
calling one bean method after another, it's a workflow *document* — built
here with `quarkus-flow`'s Java DSL, but structurally the same shape as a
CNCF Serverless Workflow YAML/JSON document — that declares two tasks,
`classify` then `decide`, and lets the Quarkus Flow engine's default
behavior (each task's input is the prior task's output) wire them together.
`OrderTriageFlowRunner`
(`examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/OrderTriageFlowRunner.java`)
bridges this back to the REST layer:

```java
public TriageDecision run(OrderCreate order) {
    return workflow.startInstance(order)
        .onItem().transform(model -> model.as(TriageDecision.class).orElseThrow())
        .await().atMost(Duration.ofSeconds(120));
}
```

`startInstance(order)` returns a `Uni` (Flow instances run asynchronously);
`.await().atMost(Duration.ofSeconds(120))` blocks the calling thread until the
workflow completes (with a bounded timeout rather than an unbounded wait, so a
stuck instance fails the request instead of hanging it), then
`.as(TriageDecision.class)` unwraps the workflow's final
model back into the exact same response shape `/triage` returns. Both
endpoints call the identical `TriageService.classify`/`decide` methods — the
workflow does not reimplement any part of the classify-or-decide logic as,
say, a Flow `switchCase`; Drools still makes the one decision that matters,
in both paths.

{% include codetabs.html langs="Kafka choreography|Camel orchestration|Quarkus Flow orchestration" %}
```yaml
# Kafka choreography — order-service publishes; nothing it calls, nothing calls it back.
# No single file "is" this flow — it is the union of three services' independent
# @Incoming/@Outgoing channel bindings (application.properties), shown here as one
# diagram of what actually happens on the wire:

order-service:
  publishes: order.placed          # OrderEventProducer, Avro via Apicurio

payment-service:
  consumes: order.placed           # reacts on its own; order-service never calls it
  publishes: payment.captured

shipping-service:
  consumes: payment.captured       # reacts on its own; payment-service never calls it
  publishes: shipment.dispatched

notification-service:
  consumes: order.placed           # a FOURTH, independent reaction to the same event
```
```java
// Camel orchestration — OrderTriageRoute.java
// One route explicitly sequences every step; this IS the coordinator.
from("direct:triage")
    .routeId("triage-order")
    .unmarshal().json(JsonLibrary.Jackson, OrderCreate.class)
    .bean(triageService, "classify")
    .bean(triageService, "decide")
    .marshal().json(JsonLibrary.Jackson);
```
```java
// Quarkus Flow orchestration — OrderTriageWorkflow.java
// Same two steps, declared instead of sequenced imperatively.
return FlowWorkflowBuilder.workflow("order-triage")
    .tasks(
        FlowDSL.function("classify", triageService::classify),
        FlowDSL.function("decide", triageService::decide))
    .build();
```

{% include excalidraw.html file="13-orchestration-styles" alt="Three coordination shapes over the same shipping/order domain: decentralized Kafka choreography across order-service, payment-service, shipping-service and notification-service with no central caller; a Camel route in ai-rules-service explicitly sequencing classify then decide; and a declarative Quarkus Flow workflow document expressing the same two tasks" caption="Figure 13.1 — Choreography and two orchestration shapes, side by side" %}

The three boxes in that diagram carry the entire argument of this chapter,
and are worth examining closely before reading further. The choreography box has no single arrow entering from "the
top" — every service subscribes to a topic and publishes to another, and
the diagram has no node labeled "coordinator" because there isn't one. The
two orchestration boxes both have exactly one entry point and one box that
owns the sequence, but they draw that ownership differently: the Camel box
is a straight line of named steps, because a route *is* a sequence of
method calls. The Quarkus Flow box is a small graph of tasks with declared
dependencies, because a workflow document describes *what* must happen
before what, and leaves *how* to call it to the engine. That distinction —
code that calls things in order versus data that declares an order — is
the one this chapter spends the most effort separating from "orchestration
versus choreography." Learners who are new to this space tend to conflate
"a coordinator exists" with "the coordinator is a hand-written imperative
function," and the Quarkus Flow leg exists specifically to break that
assumption.

## When to reach for which

| | Kafka choreography | Camel orchestration | Quarkus Flow orchestration |
|---|---|---|---|
| Who knows the whole sequence | No one — each service knows only its own reaction | The route — read top to bottom | The workflow document — read declaratively |
| Adding a new participant | Zero changes to existing services (just subscribe) | Edit the route to add a step | Edit the workflow document to add a task |
| Where to look when something's wrong | Every subscriber's own logs/topic | One route's log output | One workflow instance's task history |
| Best fit | Independent reactions to a domain event, unknown/growing set of subscribers, no step needs to wait on another's result before proceeding | A fixed, code-reviewed business process where the sequence itself is the valuable artifact, and you want full imperative control (branching, error handling, EIPs) | The same kind of fixed business process, but you want the sequence expressed as data (a workflow document) rather than code — useful when the process itself needs to be inspected, versioned, or edited independently of a Java release |
| Coupling | Loosest — publishers and subscribers never reference each other | Tighter — the route references every participant bean directly | Tighter, same as Camel — but the reference is a task graph, not imperative calls |

The general rule this project teaches: reach for **choreography** when you
have a domain event other parts of the system might react to today or in
the future, and you don't want the publisher to know or care who's
listening. Reach for **orchestration** when a specific business process has
to produce one determinate outcome and you need the sequence itself to be
an explicit, inspectable artifact — and then choose **imperative**
(Camel route) vs. **declarative** (Quarkus Flow) based on whether that
artifact is better reviewed as code or as a document.

## A deliberate limit: these three legs don't share one literal order

It's tempting to picture a single order flowing through all three engines
end to end — placed via Kafka, then triaged via Camel, then triaged again
via Flow. That is not what `demo-orchestration-styles.sh` does, and the
script's own header is explicit about why: the triage endpoints
(`/triage`, `/triage-flow`) only accept an order's line-item fields — they
don't persist anything and don't publish an event. The Kafka leg's order
payload was never run through a classifier-stability trial; the specific
order used for the choreography leg wasn't chosen to produce a deterministic
triage decision. What genuinely *is* shared across all three legs is the
**domain** (the same shipping/order concepts: customer, SKU, quantity,
amount) and the **comparison** this chapter exists to teach: one
decentralized mechanism versus two differently-shaped centralized ones,
coordinating the same *kind* of step. This chapter does not claim more
continuity between the legs than that, and the demo does not either.

The reason the demo picked a *pre-validated* input for Act 2 and Act 3,
rather than reusing whatever order Act 1 happened to place, is itself a
lesson about mixing a deterministic coordinator with a non-deterministic
step. Chapter 14 shows that `/triage` and `/triage-flow` both delegate their
actual classification to a small local LLM (`qwen2.5:3b` via Ollama) before
Drools ever sees a fact. An LLM classification is not guaranteed to repeat
identically on every input, so asserting a *specific* decision
(`ROUTE_TO_WAREHOUSE`, not merely "one of three valid decisions") requires
an input whose classification has already been shown stable across repeated
trials. Act 1's order was never put through that trial, because Act 1 isn't
testing classification at all. It's testing whether four independently
deployed services correctly react to Kafka events — a question that has
nothing to do with what the order's fields happen to be. Keeping the three
acts' test inputs deliberately uncoupled, rather than threading one order
through all three for narrative tidiness, lets each act make a strict
assertion.

## Build, run, observe

```bash
cd demos && ./demo-orchestration-styles.sh
```

This single script stands up `order-service`, `inventory-service`,
`payment-service`, `shipping-service`, and `notification-service` for the
choreography act, and `ai-rules-service` (with Ollama via the compose
`ollama` profile) for both orchestration acts, against the compose baseline.
Act 1 places one order and polls each downstream Kafka topic with `kcat`,
asserting the Avro wire-format magic byte on each hop and corroborating with
a direct Postgres row check and a REST lookup. Act 2 posts to `/triage` and
asserts a strict decision (`ROUTE_TO_WAREHOUSE`, for the pre-validated
stable low-risk input used here). Act 3 posts the identical input to
`/triage-flow` and asserts the identical decision. A closing recap narrates
the three mechanisms side by side.

## What you learned

- **Choreography** (Kafka): decentralized, no coordinator, participants only
  know "react to event X, emit event Z"; adding a subscriber costs nothing
  to existing services.
- **Orchestration** (Camel, Quarkus Flow): a named coordinator sequences
  explicit steps; the two orchestration engines here differ in *how* the
  sequence is expressed — imperative route code vs. a declarative workflow
  document — not in whether a coordinator exists.
- The choice between choreography and orchestration is about who needs to
  see the whole sequence and how loosely coupled the participants should
  be, not about which is universally "better."
- The three legs of this demo share a domain and a comparison, not one
  literal order flowing through all three — don't overstate the continuity.

The next chapter goes deeper into one of these two orchestration legs — the
AI-assisted triage itself — including where its in-process LLM tool-calling
genuinely does and doesn't work.

---

*Verification status: <span class="status status--unverified">unverified</span>.
The highest-risk things to confirm on a real run: that `payment-service` and
`shipping-service` actually react to their respective upstream events within
the demo's 45-second polling budget (`demo-orchestration-styles.sh`'s Act 1);
that the Ollama-backed classification of the pre-validated `TRIAGE_ORDER`
input still yields a deterministic `ROUTE_TO_WAREHOUSE` for both `/triage`
and `/triage-flow` (LLM classification drift is the single biggest risk to
the "same decision, two engines" claim); and that every hop's
`org.apache.avro.SERIALIZABLE_PACKAGES` system property is set correctly, since
a missing one on any single downstream service fails only that hop silently.*
