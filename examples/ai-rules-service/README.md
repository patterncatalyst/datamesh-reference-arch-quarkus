# DataMesh :: AI Rules Service

DRQ-012 showcase: **the LLM classifies, Drools decides.** Camel-on-Quarkus
combines a single-shot `langchain4j-chat` classification (Ollama,
`qwen2.5:3b`) with a plain embedded Drools 10.2.0 rule set that makes the
actual order-triage business decision.

```
POST /api/orders/triage  (order JSON)
        │
        ▼
  direct:triage
        │  single-shot langchain4j-chat classify
        │  (category / priority / riskSignal JSON)
        ▼
  OrderTriageFact (merged order + classification)
        │  KieSession.insert + fireAllRules
        ▼
  TriageDecision JSON  (FRAUD_HOLD | EXPEDITE | ROUTE_TO_WAREHOUSE)
```

## How this sidesteps DEF-001

`ai-mcp-service` (the sibling AI example in this reactor) demonstrates
langchain4j **tool-calling**: an agent that decides, on its own, to invoke an
`ai-tool` route. That round trip is the subject of **DEF-001** (open,
documented in `_plans/decisions.md`): `camel-quarkus-support-langchain4j`
unconditionally enforces the Quarkiverse JAX-RS HTTP client transport, and
the in-process tool-calling round trip never fires on this stack.

This module makes **no** agent-mediated business decision at all. The LLM's
only job is a single-shot classify call (`langchain4j-chat`) — the exact
same proven, DEF-001-free pattern as ai-mcp-service's `OrderClassifierRoute`
— with a tightly constrained prompt that asks for a small, closed JSON
shape (three string enums). The actual business decision (fraud hold vs.
expedite vs. route-to-warehouse) is made entirely by the embedded Drools
rule set in `rules/order-triage.drl`, evaluating the classified fields as a
plain Java fact. There is no in-process tool-calling round trip to fail, so
this module structurally cannot regress into DEF-001 — it has no
`camel-quarkus-ai-tool`, `camel-quarkus-langchain4j-agent`, or
`camel-quarkus-mcp-server` dependency at all.

## Drools 10.2.0 + drools-mvel

This module uses **plain embedded Drools as a library** — `drools-engine` +
a `KieBase` built once at startup via `KieHelper` from a classpath `.drl`
resource, with a short-lived `KieSession` minted per request. This is **not**
the Kogito/KIE Quarkus extension; no Kogito platform, no KIE process/flow/
BPMN engine is used or planned (see DRQ-012 in `_plans/decisions.md` — KIE
is explicitly not a roadmap item for this reactor). Orchestration is done by
Quarkus + Camel, which is the point of the demo.

`drools-mvel` is a **required** runtime dependency, not optional: it supplies
the MVEL-backed `ConstraintBuilder` SPI that Drools' `PatternBuilder` needs
when compiling DRL pattern constraints. Without it on the classpath,
`KieHelper#build()` throws `UnsupportedOperationException` from
`PatternBuilder` at rule-compile time. Both `org.drools:drools-engine` and
`org.drools:drools-mvel` are version-managed in **this module's own**
`<dependencyManagement>` (importing `org.drools:drools-bom:10.2.0`) — Drools
is deliberately *not* added to the parent reactor's BOM management, since no
other module needs it.

## Why there's an explicit `ChatModel` producer

`ChatModelProducer` builds an `OllamaChatModel` directly and exposes it as a
CDI bean, rather than relying on quarkus-langchain4j-ollama's own synthetic
`ChatModel` bean. That synthetic bean is only synthesized
(`io.quarkiverse.langchain4j.deployment.BeansProcessor#handleProviders`)
when something in the application has a *static*, build-time-visible
injection point for `ChatModel` (an `@Inject ChatModel` field, or a
`@RegisterAiService` interface) -- a *runtime* CDI type lookup, which is all
Camel's `langchain4j-chat:` component does to autowire its `chatModel`
property, is invisible to that build step. ai-mcp-service's classifier route
is unaffected by this because that module also depends on
`camel-quarkus-langchain4j-agent`, whose `Agent` wiring happens to create
such an injection point; this module deliberately depends on neither (see
above), so without this explicit producer the route fails to start with
`chatModel must be specified`. The producer also sets
`.responseFormat(ResponseFormat.JSON)`, which makes Ollama itself constrain
decoding to valid JSON syntax -- it does not enforce the specific
category/priority/riskSignal schema, so `OrderTriageRoute` still defensively
extracts the `{...}` substring before unmarshalling (small local models
sometimes wrap the answer in a ` ```json ` fence despite being told not to)
and `ClassificationResult` is `@JsonIgnoreProperties(ignoreUnknown = true)`
in case the model pads its answer with extra fields. If the model omits one
of the three expected fields entirely, that field lands `null` and simply
fails to match any Drools condition that tests it, falling through to the
`ROUTE_TO_WAREHOUSE` default rule rather than throwing.

## Rules (`rules/order-triage.drl`)

Exactly one decision is produced per request:

| Condition | Decision |
|---|---|
| `riskSignal == HIGH` | `FRAUD_HOLD` |
| `amount >= 1000 && riskSignal == LOW` | `EXPEDITE` |
| (anything else) | `ROUTE_TO_WAREHOUSE` |

Every rule guards on `decision == null` and writes its outcome back onto the
same fact via `modify()`; because `modify()` re-evaluates the fact's
remaining pending activations, once one rule fires, every other rule's
match is invalidated for that fact. `salience` additionally fixes a
deterministic firing order. See the comments in the `.drl` file for the full
reasoning.

## Run instructions

```bash
# Start Ollama as infra (opt-in compose profile; see infra/README.md and
# demos/README.md — DEF-001 keeps Ollama opt-in across this reactor):
docker compose --profile ollama up -d
docker exec -it ollama ollama pull qwen2.5:3b   # first run only

cd examples/ai-rules-service
mvn quarkus:dev                   # or: mvn quarkus:dev -f ../pom.xml -pl ai-rules-service

curl -X POST http://localhost:8089/api/orders/triage \
  -H 'Content-Type: application/json' \
  -d '{"customerId":"CUST-42","itemSku":"LAPTOP-15","quantity":1,"amount":1899.99}'
```

Port **8089** is used deliberately — `ai-mcp-service` (the sibling AI
example) uses **8088**, so both modules can run side by side without a port
clash.

## Tests

- `OrderTriageDrlTest` (`*Test`, plain JUnit, no Quarkus bootstrap, no
  Ollama) — builds the `KieBase` directly from `rules/order-triage.drl` and
  fires all three decision branches (`FRAUD_HOLD`, `EXPEDITE`,
  `ROUTE_TO_WAREHOUSE`) from hand-built `OrderTriageFact` instances. Runs
  under the default `mvn verify`.
- `OrderTriageRouteTest` (`*Test`, `@QuarkusTest`) — wiring test: asserts
  the `triage-order` Camel route is registered/started and the `KieBase` CDI
  producer works, without calling Ollama. Runs under the default
  `mvn verify`.
- `OrderTriageRouteIT` (`*IT`, opt-in) — end-to-end behavioral test that
  posts a real order to `/api/orders/triage` and asserts Drools returned one
  of the three valid decisions. Requires a live Ollama server and is gated
  behind `-Dollama.tests.enabled=true`; Surefire's default include patterns
  skip `*IT` classes and failsafe is not bound in this module, so the
  default `mvn verify` never runs it and never needs Ollama. Run with:

  ```bash
  mvn test -Dollama.tests.enabled=true -Dtest=OrderTriageRouteIT \
    -f examples/pom.xml -pl ai-rules-service
  ```
