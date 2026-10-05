---
title: "AI-assisted rules triage: Ollama classifies, Drools decides"
order: 15
part: The Quarkus deep-dive
description: "An LLM extracts structured fields from an order; a deterministic Drools rule set makes the business decision. The chapter also covers where in-process langchain4j tool-calling works and where it does not on this stack."
duration: 45 minutes
marker: "15"
---

The previous chapter used `ai-rules-service`'s two triage endpoints as the
example for orchestration *shape*. This chapter covers what they do: an LLM is good at reading a loosely-structured description and pulling
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

The top half is the pipeline: one LLM call feeding one deterministic rule
engine, reached by two orchestration shapes (Camel, Quarkus Flow) that both end
in the same `TriageService` methods. The bottom half shows the same local
model in a structurally different capability, multi-turn tool-calling instead
of single-shot classification, in a different service (`ai-mcp-service`). One
path there is broken for a documented upstream reason, and a second path that
looks similar works. An LLM call that succeeds in one part of the project says
nothing about a structurally different call elsewhere, so the halves are kept
separate.

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
one. `extractJsonObject` is a second line of defense: although the prompt says "no markdown fences," the model sometimes
wraps its answer in a ```` ```json ```` fence anyway, so this method takes
the substring between the first `{` and the last `}` before handing it to
Jackson.
[ChatModelProducer.java]({{ site.repo_blob }}/examples/ai-rules-service/src/main/java/com/patterncatalyst/datamesh/airules/ChatModelProducer.java)
also forces Ollama's native JSON output mode
(`.responseFormat(ResponseFormat.JSON)`) at the model level. That constrains
decoding to valid JSON syntax but does not enforce the three-key schema, so
`extractJsonObject` and the exception-throwing parse in `classify` remain as
fallbacks.

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
is a plain mutable JavaBean, not a record, because Drools' MVEL-backed rule
compilation reads fields via getters and writes the decision back via
`modify()`, which needs a mutable target. `orderTriageKieBase` (the compiled
rule set) is built once at startup and reused across requests, but a fresh
`KieSession` is minted per request and disposed immediately after firing —
`KieSession` is stateful working memory, not safe to share or reuse across
concurrent requests the way the immutable `KieBase` is.

The rules themselves, in
[order-triage.drl]({{ site.repo_blob }}/examples/ai-rules-service/src/main/resources/rules/order-triage.drl), are
three guarded, mutually exclusive outcomes:

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
the firing order for readability, not correctness. This is the point of the
split: the LLM's job ends at the `riskSignal` and `amount` classification, and
the decision is then a deterministic function of those fields. It is
reproducible without the model, auditable by reading three `when`/`then`
blocks, and unaffected by the model answering slightly differently on a re-run
as long as the classification lands in the same bucket.

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
validated against the live model across repeated trials to find
classifications stable enough for strict assertions (the exact decision, not
one of three valid values): a low-value ordinary item (expect
`ROUTE_TO_WAREHOUSE`), a high-value order from a trusted-looking customer
(expect `EXPEDITE`), and a fraud-signalling item description at high volume
(expect `FRAUD_HOLD`). It asserts that `/triage` and `/triage-flow` return the
same decision for the same input, which shows both orchestration shapes drive
the same logic.

## The tool-calling caveat: in-process tool-calling does not fire here

`ai-mcp-service` is a different module built around a related but separate
capability: letting an LLM call a tool mid-conversation (langchain4j "agent"
tool-calling) instead of classifying in one shot. The sections below cover
what works and what does not, including the broken path.

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
wired to do that: `OrderAssistantRoute`'s in-process
langchain4j-agent, and the embedded MCP server. Only the MCP server works.

**What doesn't work: the in-process agent.** [OrderAssistantRoute.java]({{ site.repo_blob }}/examples/ai-mcp-service/src/main/java/com/patterncatalyst/datamesh/aimcp/OrderAssistantRoute.java)
wires a `langchain4j-agent:` endpoint to the `order-status` tool via the
`shipping` tag, backed by an `Agent` bean `AgentProducers` builds from a
hand-constructed `OllamaChatModel`
([AgentProducers.java]({{ site.repo_blob }}/examples/ai-mcp-service/src/main/java/com/patterncatalyst/datamesh/aimcp/AgentProducers.java)).
That agent's tool-calling round trip **does not fire** on this stack. The
root cause, documented in `AgentProducers`'s Javadoc, is upstream and not a
bug in this module: `camel-quarkus-support-langchain4j`
unconditionally sets the global `langchain4j.http.clientBuilderFactory`
system property to a Quarkiverse JAX-RS HTTP client factory for *every*
`dev.langchain4j` model on the classpath — there is no toggle for it — so
the hand-built `OllamaChatModel`'s own configured `base-url` is never
honored by the transport that sends the request, and an explicit
`httpClientBuilder(new JdkHttpClientBuilder())` override doesn't change it
either. This was ruled out as a model-capability problem (a direct Ollama
`/api/chat` call with a tools array *does* return `tool_calls` for both
`qwen2.5:3b` and `qwen2.5:7b-instruct`) and as a tool-registration or
tag-matching problem (the tags line up correctly) — it is specifically a
transport-wiring defect in `camel-quarkus-support-langchain4j`, a known open
upstream issue that cannot be fixed locally.

The practical consequence: [demo-ai-mcp.sh]({{ site.repo_blob }}/demos/demo-ai-mcp.sh) **never calls**
`POST /api/assistant/chat` and never treats a non-empty chat response as
evidence that tool-calling succeeded, since a model can answer without
calling the tool. The script prints a banner stating the limitation before it
runs anything.

**What does work: the embedded MCP server.** Instead, `demo-ai-mcp.sh`
demonstrates the tool-calling-adjacent path that works end to end: `camel-quarkus-mcp-server` (wrapping the Quarkiverse
`quarkus-mcp-server-http` extension) publishes the same `order-status`
`ai-tool:` route to **external** MCP clients over the MCP Streamable HTTP protocol. It is a
separate code path from the broken in-process agent, with no
`langchain4j-agent` involved. The demo is a minimal MCP client over `curl` and
`jq`, speaking JSON-RPC 2.0:

1. `POST /mcp {"method":"initialize"}` → a handshake that returns a
   protocol version and an `Mcp-Session-Id` header.
2. `POST /mcp {"method":"tools/list"}` (with that session) → lists a tool
   named `order-status`.
3. `POST /mcp {"method":"tools/call", params: {name: "order-status", ...}}`
   for `ORD-001`/`ORD-002`/`ORD-003` → the exact deterministic lookup body
   `OrderLookupToolRoute` hardcodes for each id.

[demo-camel-integration.sh]({{ site.repo_blob }}/demos/demo-camel-integration.sh) reaches the same route through the same MCP server
surface and asserts all four branches of its Content-Based Router
(`.choice()`, `.when()`, `.otherwise()`), including the `.otherwise()` fallback
for an unrecognized order id. That verifies the EIP logic independently of the
tool-calling defect.

[demo-ai-classify.sh]({{ site.repo_blob }}/demos/demo-ai-classify.sh) exercises
[OrderClassifierRoute.java]({{ site.repo_blob }}/examples/ai-mcp-service/src/main/java/com/patterncatalyst/datamesh/aimcp/OrderClassifierRoute.java),
a `langchain4j-chat:` single-shot classification endpoint — structurally the
same shape as `TriageService.classify` above, no agent, no tool calling —
so the agent tool-calling defect does not affect it. It had its own bug (a misnamed prompt-template header, `CamelLangChain4jChatPrompt`
instead of `CamelLangChain4jChatPromptTemplate`, combined with the
endpoint never being switched off its default single-message operation)
that made the model chat about the order instead of classifying
it, fixed by correcting the header name and setting
`chatOperation=CHAT_SINGLE_MESSAGE_WITH_PROMPT`.

## Trusting an LLM in a pipeline

Together the demos show three things. Single-shot classification (`classify`,
`OrderClassifierRoute`) is reliable enough to build on if the output is parsed
defensively. A deterministic rules engine (Drools) should make any decision
that must be reproduced, audited, or explained. In-process multi-step
tool-calling is a different and currently less reliable capability on this
stack, with a diagnosed upstream cause. Knowing which of the three an endpoint
relies on is what makes the system predictable.

`AgentProducers` already tried the two levers a caller has: a
hand-built `OllamaChatModel` with an explicit `base-url`, and an explicit
`httpClientBuilder(new JdkHttpClientBuilder())` override. Neither
changed the outcome, because `camel-quarkus-support-langchain4j` sets that
system property JVM-wide before either bean is constructed. A property set
at that layer wins over any per-model builder argument, so no caller-side
override is available. That is why this is logged as a defect against the
extension instead of being worked around with a classpath exclusion or a
shaded client. The fix has to come from `camel-quarkus-support-langchain4j`
making that property conditional or honoring a per-agent client override.

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

- Split the LLM's job (extract structured fields) from the decision (Drools
  fires deterministic rules on those fields). The model never makes the
  business call.
- A JavaBean-shaped fact plus a short-lived `KieSession` per request is the
  standard Drools integration pattern; the compiled `KieBase` is reused,
  the session is not.
- `camel-quarkus-support-langchain4j`'s global HTTP client override breaks
  in-process agent tool-calling independent of model capability
  or tool registration — the embedded MCP server is a structurally separate
  path that is unaffected and does work.
- A demo can document a known limitation: `demo-ai-mcp.sh` prints a banner and
  never calls the broken endpoint, so a passing run cannot be mistaken for
  working tool-calling.

This closes the Quarkus deep dive. The comparison against Spring Boot
(Chapter 12) measures startup and memory.

---

*Verification status: <span class="status status--verified">verified</span>. Run against the compose stack with the Ollama profile and a live `qwen2.5:3b`: `demo-ai-classify.sh`, `demo-ai-mcp.sh`, `demo-camel-integration.sh`, and `demo-ai-triage.sh` all passed. The triage showcase returned the exact expected decisions (ROUTE_TO_WAREHOUSE / EXPEDITE / FRAUD_HOLD) for all three inputs on both the Camel `/api/orders/triage` and the Quarkus Flow `/api/orders/triage-flow` endpoints the LLM classifies, Drools decides. The in-process tool-calling defect remains documented as before; the MCP-server path is the one exercised.*
