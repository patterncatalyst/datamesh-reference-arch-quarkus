---
title: "AI-assisted rules triage: Ollama classifies, Drools decides"
order: 15
part: The Quarkus deep-dive
description: "An LLM extracts structured fields from an order; a deterministic Drools rule set makes the actual business decision — plus a clear account of where in-process langchain4j tool-calling does and doesn't work on this stack."
duration: 45 minutes
marker: "15"
---

The previous chapter used `ai-rules-service`'s two triage endpoints as the
example for orchestration *shape*. This chapter opens up what they actually
do: an LLM is good at reading a loosely-structured description and pulling
out a few categorical fields, but it is a poor choice to make a business
decision you need to audit, replay deterministically, or explain to a
compliance reviewer. This project's answer is a strict division of labor —
**the LLM classifies, Drools decides** — demonstrated two ways, plus a
second, separate service (`ai-mcp-service`) showing where a related but
different capability, in-process LLM tool-calling, currently does not work
on this stack.

The code is in [ai-rules-service]({{ site.repo_tree }}/examples/ai-rules-service) (`TriageService`,
[order-triage.drl]({{ site.repo_blob }}/examples/ai-rules-service/src/main/resources/rules/order-triage.drl), `OrderTriageRoute`, `OrderTriageWorkflow`,
`ChatModelProducer`, `OrderTriageFact`, `TriageDecision`) and
[ai-mcp-service]({{ site.repo_tree }}/examples/ai-mcp-service) (`OrderClassifierRoute`, `OrderLookupToolRoute`,
`AgentProducers`, `OrderAssistantRoute`); the demo scripts named in each
section build/set up and run the pieces they cover.

{% include excalidraw.html file="14-ai-rules-triage" alt="The classify-then-decide pipeline: an order flows into TriageService.classify, which calls Ollama's qwen2.5:3b model to produce category, priority, and riskSignal; those fields become an OrderTriageFact handed to a Drools KieSession, which fires order-triage.drl and returns one of FRAUD_HOLD, EXPEDITE, or ROUTE_TO_WAREHOUSE; a separate branch shows ai-mcp-service's in-process langchain4j agent failing to reach the order-status tool while the embedded MCP server reaches the same tool successfully" caption="Figure 14.1 — Ollama classifies, Drools decides, and where the in-process agent path breaks" %}

Read the diagram as two halves. The top half is the pipeline this chapter
spends most of its words on: one LLM call feeding one deterministic rule
engine, reached by two different orchestration shapes (Camel, Quarkus Flow)
that both terminate in the identical `TriageService` methods. The bottom
half is the cautionary half: the same local model, wired into a
structurally different capability — multi-turn tool-calling rather than
single-shot classification — in a *different* service (`ai-mcp-service`),
where one specific path is broken for a documented, upstream reason while a
second path that looks superficially similar works perfectly. Keeping those
two halves visually separate is deliberate: the fact that an LLM call
succeeds in one part of this project is not evidence that a structurally
different LLM call succeeds somewhere else, and this chapter's second half
exists specifically to stop that generalization before a reader makes it.

## The split: classify (LLM), then decide (Drools)

[TriageService.java]({{ site.repo_blob }}/examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/TriageService.java)
is the single source of truth both orchestration paths from Chapter 13 call
into. Its `classify` method does exactly one LLM call:

```java
public ClassificationResult classify(OrderCreate order) {
    String prompt = buildClassifyPrompt(order);
    String response = chatModel.chat(prompt);
    String json = extractJsonObject(response);

    RawClassification raw = objectMapper.readValue(json, RawClassification.class);

    return new ClassificationResult(
        raw.category(), raw.priority(), raw.riskSignal(),
        order.customerId(), order.itemSku(), order.quantity(), order.amount());
}
```

`chatModel.chat(prompt)` is a **single-shot** call — one prompt in, one
response out, no multi-turn conversation and no tool calling. The prompt
(`buildClassifyPrompt`) asks for exactly three fields (`category`,
`priority`, `riskSignal`) as JSON, with a worked example embedded in the
prompt text, because — per the method's own comment — the small local model
used here (`qwen2.5:3b`) reliably classifies against a concrete example but
drifts into echoing the order back verbatim or writing free prose without
one. `extractJsonObject` is a defensive second line of resistance: even
though the prompt explicitly says "no markdown fences," the model sometimes
wraps its answer in a ```` ```json ```` fence anyway, so this method takes
the substring between the first `{` and the last `}` before handing it to
Jackson, rather than trusting the model's formatting discipline outright.
[ChatModelProducer.java]({{ site.repo_blob }}/examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/ChatModelProducer.java)
goes one step further on reliability by forcing Ollama's native JSON output
mode (`.responseFormat(ResponseFormat.JSON)`) at the model level — this
constrains *decoding* to valid JSON syntax, though it does not enforce the
specific three-key schema, which is why `extractJsonObject` and the
exception-throwing parse in `classify` still exist as fallbacks.

Classification done, `decide` hands a merged fact to Drools and lets the
*rules*, not the model, make the call:

```java
public TriageDecision decide(ClassificationResult classification) {
    OrderTriageFact fact = new OrderTriageFact();
    fact.setCustomerId(classification.customerId());
    // ... copy every classified + original field onto the fact ...

    KieSession kieSession = orderTriageKieBase.newKieSession();
    try {
        kieSession.insert(fact);
        kieSession.fireAllRules();
    } finally {
        kieSession.dispose();
    }

    return new TriageDecision(
        TriageDecision.Decision.valueOf(fact.getDecision()),
        fact.getReason(), fact.getCategory(), fact.getPriority(), fact.getRiskSignal(),
        fact.getCustomerId(), fact.getItemSku(), fact.getQuantity(), fact.getAmount());
}
```

[OrderTriageFact.java]({{ site.repo_blob }}/examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/OrderTriageFact.java)
is a plain mutable JavaBean — not a record — because Drools' MVEL-backed rule
compilation reads fields via getters and writes the decision back via
`modify()`, which needs a mutable target. `orderTriageKieBase` (the compiled
rule set) is built once at startup and reused across requests, but a fresh
`KieSession` is minted per request and disposed immediately after firing —
`KieSession` is stateful working memory, not safe to share or reuse across
concurrent requests the way the immutable `KieBase` is.

The rules themselves, in
[order-triage.drl]({{ site.repo_blob }}/examples/ai-rules-service/src/main/resources/rules/order-triage.drl), are
three guarded, mutually-exclusive outcomes:

```text
rule "Fraud hold on high risk"
    salience 30
    when
        $fact : OrderTriageFact(decision == null, riskSignal == "HIGH")
    then
        modify($fact) { setDecision("FRAUD_HOLD"), setReason("Classifier flagged a HIGH fraud/risk signal") }
end

rule "Expedite large trusted order"
    salience 20
    when
        $fact : OrderTriageFact(decision == null, amount != null, amount >= 1000, riskSignal == "LOW")
    then
        modify($fact) { setDecision("EXPEDITE"), setReason("Order amount >= 1000 with a LOW risk signal") }
end

rule "Default route to warehouse"
    salience 10
    when
        $fact : OrderTriageFact(decision == null)
    then
        modify($fact) { setDecision("ROUTE_TO_WAREHOUSE"), setReason("No fraud-hold or expedite condition matched; standard fulfillment") }
end
```

Every rule's left-hand side guards on `decision == null`. Because `modify()`
re-evaluates the fact against every rule's condition, the instant one rule
fires and sets a non-null decision, every other rule's still-pending
activation for that fact loses its guard and never fires — so exactly one
rule's consequence runs per request, and `salience` (30, 20, 10) only fixes
a deterministic firing order for readability, not correctness. This is the
whole point of the split: the LLM's job ends at `riskSignal`/`amount`
classification; from there, the decision is a pure, deterministic function
of those fields, reproducible outside the model entirely, auditable by
reading three `when`/`then` blocks, and immune to the model answering
slightly differently on a re-run as long as its classification lands in the
same bucket.

{% include codetabs.html langs="Camel route|Quarkus Flow" %}
```java
// Camel route — OrderTriageRoute.java: explicit, imperative sequencing.
from("direct:triage")
    .routeId("triage-order")
    .unmarshal().json(JsonLibrary.Jackson, OrderCreate.class)
    .bean(triageService, "classify")
    .bean(triageService, "decide")
    .marshal().json(JsonLibrary.Jackson);
```
```java
// Quarkus Flow — OrderTriageWorkflow.java: the same two TriageService calls,
// declared as workflow tasks instead of route steps.
return FlowWorkflowBuilder.workflow("order-triage")
    .tasks(
        FlowDSL.function("classify", triageService::classify),
        FlowDSL.function("decide", triageService::decide))
    .build();
```

[demo-ai-triage.sh]({{ site.repo_blob }}/demos/demo-ai-triage.sh) drives both endpoints with three inputs that were
pre-validated directly against the live model across repeated trials
specifically to find classifications stable enough for *strict* assertions
(exact decision, not just "one of the three valid values"): a low-value
ordinary item (expect `ROUTE_TO_WAREHOUSE`), a high-value order from a
trusted-looking customer (expect `EXPEDITE`), and a deliberately
fraud-signalling item description at high volume (expect `FRAUD_HOLD`). It
asserts both `/triage` and `/triage-flow` return the identical decision for
the identical input — proof the two orchestration shapes drive the same
underlying logic, not two independently-tuned copies of it.

## The tool-calling caveat: in-process tool-calling does not fire here

`ai-mcp-service` is a *different* module built around a related but
genuinely separate capability: letting an LLM call a tool mid-conversation
(langchain4j "agent" tool-calling), rather than classifying in one shot.
It's worth walking through exactly what works and what doesn't, because
documenting the broken path is more useful than a demo that quietly avoids
it.

**What is registered correctly.** [OrderLookupToolRoute.java]({{ site.repo_blob }}/examples/ai-mcp-service/src/main/java/com/patterncatalyst/datamesh/aimcp/OrderLookupToolRoute.java)
registers an order-status lookup as a callable tool via Camel's
framework-neutral `ai-tool:` component:

```java
from("ai-tool:order-status"
        + "?tags=shipping"
        + "&description=Look up the status of a shipping order by order ID"
        + "&parameter.orderId=string"
        + "&parameter.orderId.required=true"
        + "&readOnlyHint=true")
    .routeId("order-lookup-tool")
    .choice()
        .when(simple("${header.orderId} == 'ORD-001'"))
            .setBody(constant("{\"orderId\":\"ORD-001\",\"status\":\"SHIPPED\", ...}"))
        // ... ORD-002, ORD-003 ...
        .otherwise()
            .setBody(constant("{\"error\":\"Order not found\"}"))
    .end();
```

This publishes the route into a shared `AiToolRegistry`; any producer
filtering on the `shipping` tag can invoke it. Two different consumers are
wired to do exactly that: `OrderAssistantRoute`'s in-process
langchain4j-agent, and the embedded MCP server. Only one of them actually
works.

**What doesn't work: the in-process agent.** [OrderAssistantRoute.java]({{ site.repo_blob }}/examples/ai-mcp-service/src/main/java/com/patterncatalyst/datamesh/aimcp/OrderAssistantRoute.java)
wires a `langchain4j-agent:` endpoint to the `order-status` tool via the
`shipping` tag, backed by an `Agent` bean `AgentProducers` builds from a
hand-constructed `OllamaChatModel`
([AgentProducers.java]({{ site.repo_blob }}/examples/ai-mcp-service/src/main/java/com/patterncatalyst/datamesh/aimcp/AgentProducers.java)).
That agent's tool-calling round trip **does not fire** on this stack. The
root cause, documented in `AgentProducers`'s own Javadoc after exhaustive
diagnosis, is upstream, not a bug in this module: `camel-quarkus-support-langchain4j`
unconditionally sets the global `langchain4j.http.clientBuilderFactory`
system property to a Quarkiverse JAX-RS HTTP client factory for *every*
`dev.langchain4j` model on the classpath — there is no toggle for it — so
the hand-built `OllamaChatModel`'s own configured `base-url` is never
honored by the transport that actually sends the request, and an explicit
`httpClientBuilder(new JdkHttpClientBuilder())` override doesn't change it
either. This was ruled out as a model-capability problem (a direct Ollama
`/api/chat` call with a tools array *does* return `tool_calls` for both
`qwen2.5:3b` and `qwen2.5:7b-instruct`) and as a tool-registration or
tag-matching problem (the tags line up correctly) — it is specifically a
transport-wiring defect in `camel-quarkus-support-langchain4j`. This is
a known open upstream issue, not a
regression to fix locally.

The practical consequence: [demo-ai-mcp.sh]({{ site.repo_blob }}/demos/demo-ai-mcp.sh) **never calls**
`POST /api/assistant/chat` and never treats a non-empty chat response as
evidence that tool-calling succeeded — doing so would be exactly the kind of
green-washed result this tutorial's verification discipline exists to rule
out. The script prints an explicit banner to this effect before it runs
anything.

**What does work: the embedded MCP server.** Instead, `demo-ai-mcp.sh`
demonstrates the one tool-calling-adjacent path that genuinely works
end to end: `camel-quarkus-mcp-server` (wrapping the Quarkiverse
`quarkus-mcp-server-http` extension) publishes the same `order-status`
`ai-tool:` route to **external** MCP clients over the real MCP Streamable
HTTP wire protocol — a structurally separate code path from the broken
in-process agent, with no `langchain4j-agent` involved anywhere. The demo
is a minimal real MCP client over `curl`/`jq`, speaking actual JSON-RPC 2.0:

1. `POST /mcp {"method":"initialize"}` → a real handshake, returning a
   protocol version and an `Mcp-Session-Id` header.
2. `POST /mcp {"method":"tools/list"}` (with that session) → lists a tool
   literally named `order-status`.
3. `POST /mcp {"method":"tools/call", params: {name: "order-status", ...}}`
   for `ORD-001`/`ORD-002`/`ORD-003` → the exact deterministic lookup body
   `OrderLookupToolRoute` hardcodes for each id.

Separately, [demo-camel-integration.sh]({{ site.repo_blob }}/demos/demo-camel-integration.sh) reaches the *same* route
through the *same* MCP server surface and asserts all four branches of its
Content-Based Router (`.choice()`/`.when()`/`.otherwise()`) — including the
`.otherwise()` fallback for an unrecognized order id — proving the EIP logic
itself routes correctly, independent of the tool-calling defect entirely.

And one level below either of those: [demo-ai-classify.sh]({{ site.repo_blob }}/demos/demo-ai-classify.sh) exercises
[OrderClassifierRoute.java]({{ site.repo_blob }}/examples/ai-mcp-service/src/main/java/com/patterncatalyst/datamesh/aimcp/OrderClassifierRoute.java),
a `langchain4j-chat:` single-shot classification endpoint — structurally the
same shape as `TriageService.classify` above, no agent, no tool calling —
which is why it is **not** affected by the agent tool-calling defect at all; it was its own
separate bug (a misnamed prompt-template header, `CamelLangChain4jChatPrompt`
instead of the real `CamelLangChain4jChatPromptTemplate`, combined with the
endpoint never being switched off its default single-message operation)
that silently made the model chat about the order instead of classifying
it, fixed by correcting the header name and setting
`chatOperation=CHAT_SINGLE_MESSAGE_WITH_PROMPT`.

## What this teaches about trusting an LLM in a pipeline

Put together, these three demos make one argument in three parts: single-shot
classification (`classify`, `OrderClassifierRoute`) is reliable enough to
build on, as long as you defensively parse its output; a deterministic rules
engine (Drools) should make any decision you need to reproduce, audit, or
explain; and in-process multi-step tool-calling is a materially different
and currently less reliable capability on this specific stack, with a named,
diagnosed upstream cause — not a vague "AI is flaky" shrug. Knowing exactly
which of the three you're relying on, in any given endpoint, is the
difference between a system you can reason about and one you can't.

`AgentProducers` already tried the two levers a caller actually has — a
hand-built `OllamaChatModel` with an explicit `base-url`, and an explicit
`httpClientBuilder(new JdkHttpClientBuilder())` override — and neither
changed the outcome, because `camel-quarkus-support-langchain4j` sets that
system property JVM-wide before either bean is constructed. A property set
at that layer wins over any per-model builder argument, so no caller-side
override is available. That is why this is logged as a defect against the
extension rather than worked around with a classpath exclusion or a shaded
client: the fix has to come from `camel-quarkus-support-langchain4j` making
that property conditional, or honoring a per-agent client override, not
from anything `ai-mcp-service` can reasonably do to its own wiring.

## Build, run, observe

```bash
cd demos && ./demo-ai-triage.sh        # classify -> Drools decide, both orchestration paths
cd demos && ./demo-ai-classify.sh      # single-shot classification only (unaffected by the tool-calling defect)
cd demos && ./demo-ai-mcp.sh           # embedded MCP server surface (reads the limitation banner first)
```

`demo-ai-triage.sh` expects a host Ollama already running with `qwen2.5:3b`
pulled; `demo-ai-classify.sh` and `demo-ai-mcp.sh` bring up Ollama themselves
via the compose `ollama` profile.

## What you learned

- Split the LLM's job (extract structured fields) from the decision
  (Drools fires deterministic rules on those fields) — the model never
  makes the business call directly.
- A JavaBean-shaped fact plus a short-lived `KieSession` per request is the
  standard Drools integration pattern; the compiled `KieBase` is reused,
  the session is not.
- `camel-quarkus-support-langchain4j`'s global HTTP client override breaks
  in-process agent tool-calling independent of model capability
  or tool registration — the embedded MCP server is a structurally separate
  path that is unaffected and does work.
- Demonstrating a known limitation openly (an explicit banner, a demo that
  deliberately never calls the broken endpoint) is more useful to a reader
  than hiding it behind a demo that only exercises the working paths.

This closes the Quarkus deep dive. From here, the comparison against Spring
Boot (Chapter 12) puts a number on what all of this costs at startup.

---

*Verification status: <span class="status status--verified">verified</span>. Run against the compose stack with the Ollama profile and a live `qwen2.5:3b`: `demo-ai-classify.sh`, `demo-ai-mcp.sh`, `demo-camel-integration.sh`, and `demo-ai-triage.sh` all passed. The triage showcase returned the exact expected decisions (ROUTE_TO_WAREHOUSE / EXPEDITE / FRAUD_HOLD) for all three inputs on both the Camel `/api/orders/triage` and the Quarkus Flow `/api/orders/triage-flow` endpoints — the LLM classifies, Drools decides. The in-process tool-calling defect remains documented as before; it is the MCP-server path that is exercised, consistent with the chapter.*
