# DataMesh :: AI MCP Service

Camel-on-Quarkus example combining `langchain4j-chat`, `ai-tool`, `langchain4j-agent`,
and the embedded Camel MCP server. Ported from
[`enterprise-integration-patterns-with-camel/examples/42-ai-mcp/quarkus`](https://github.com/patterncatalyst)
onto this reactor's pinned BOMs:

| BOM | Seed | This module |
|---|---|---|
| `quarkus-camel-bom` | 3.39.3 | **3.39.5** (parent-pinned) |
| `quarkus-langchain4j-bom` | 1.7.4 | **1.14.1** (parent-pinned) |

All BOM versions come from the parent (`../pom.xml`). This module declares no
`<dependencyManagement>` of its own.

## Routes

- `OrderClassifierRoute` — `POST /api/orders/classify` → `direct:classify-order`
  → `langchain4j-chat:classifier`. Single-shot classification, no tool calling.
- `OrderLookupToolRoute` — `from("ai-tool:order-status?tags=shipping&...")`.
  Registers a fake order-status lookup (hardcoded ORD-001/002/003) as an LLM
  tool in the shared `AiToolRegistry`. Framework-neutral: both the agent below
  and the embedded MCP server can call it.
- `OrderAssistantRoute` — `POST /api/assistant/chat` (`text/plain`) →
  `direct:assistant-chat` → `langchain4j-agent:assistant?agent=#assistantAgent&tags=shipping`.
  The tool-calling assistant.
- `AgentProducers` — CDI producer for the `#assistantAgent` bean the
  `langchain4j-agent:` endpoint above references by name.

The embedded MCP server (`camel-quarkus-mcp-server`) publishes every
`shipping`-tagged `ai-tool` route (i.e. `order-status`) to external MCP
clients; see `quarkus.camel.mcp-server.*` in `application.properties`.

## The langchain4j 1.7.4 → 1.14.1 bump: what changed, what didn't

This was flagged as the top risk for this port because the seed's
`AgentProducers` carries a deliberate workaround: it builds the `OllamaChatModel`
directly instead of injecting the CDI `ChatModel` bean that `quarkus-langchain4j-ollama`
produces, because the injected bean never offered the registered `ai-tool` routes
to the model — `toolExecutions` came back empty. See the class Javadoc for the
full story; it mirrors the Spring Boot variant of the same seed example.

**Result: the code ported unchanged and compiles as-is against 1.14.1.**

- `dev.langchain4j.model.chat.ChatModel` — unchanged interface.
- `dev.langchain4j.model.ollama.OllamaChatModel.builder().baseUrl(...).modelName(...).timeout(...).build()` —
  unchanged builder signature.
- `org.apache.camel.component.langchain4j.agent.api.Agent`,
  `AgentConfiguration#withChatModel(ChatModel)`, and
  `new AgentWithoutMemory(AgentConfiguration)` — unchanged. These types live in
  `camel-langchain4j-agent-api`, which is versioned with **Camel**, not with the
  Quarkiverse langchain4j BOM, so the langchain4j-bom bump (1.7.4 → 1.14.1) does
  not touch this surface at all. The actual underlying Camel version moved from
  the seed's Camel ~4.x (quarkus-camel-bom 3.39.3) to Camel **4.22.0**
  (quarkus-camel-bom 3.39.5) and this API was stable across that range too.
- Confirmed against the platform catalog via the `camel-mcp` MCP tools
  (`camel_catalog_component_doc` for `langchain4j-agent`, `langchain4j-chat`,
  `ai-tool` at `quarkus-camel-bom:3.39.5`) before writing any code — all three
  endpoint URIs, options, and (for `langchain4j-agent`) the
  `CamelLangChain4jAgentToolExecutions` header used by the opt-in behavioral
  test below matched the seed's usage with zero drift.
- `mvn dependency:check` (via `camel_dependency_check`) against the pinned BOMs
  reported zero missing dependencies and zero version conflicts for this pom
  before any Java was written.

**What is NOT unchanged: a real langchain4j version skew inside the dependency tree.**

`mvn dependency:tree -Dincludes=dev.langchain4j -Dverbose=true` shows:

```
+- org.apache.camel.quarkus:camel-quarkus-langchain4j-chat:jar:3.39.0:compile
|  \- ... dev.langchain4j:langchain4j-core:jar:1.19.3:compile ...
+- org.apache.camel.quarkus:camel-quarkus-langchain4j-agent:jar:3.39.0:compile
|  \- ... dev.langchain4j-mcp:1.19.3-beta29, langchain4j-guardrails:1.19.3-beta29 ...
+- io.quarkiverse.langchain4j:quarkus-langchain4j-ollama:jar:1.14.1:compile
|  +- dev.langchain4j:langchain4j-http-client:jar:1.19.3:compile (managed down from 1.20.2)
|  \- dev.langchain4j:langchain4j-ollama:jar:1.20.2:compile   <-- NOT managed down
```

Everything that Camel's `camel-quarkus-support-langchain4j` / `camel-langchain4j-agent`
bring in (`langchain4j-core`, `langchain4j-mcp`, `langchain4j-guardrails`,
`langchain4j-http-client`) resolves uniformly to **1.19.3** (Maven mediation
consistently picks 1.19.3 everywhere, even overriding `quarkus-langchain4j-ollama`'s
own transitive request for `langchain4j-http-client:1.20.2`). The **one**
exception is `dev.langchain4j:langchain4j-ollama` itself, which stays at
**1.20.2** because nothing else in the tree declares a competing version of
that specific artifact for Maven to mediate against.

So there is **not** a single, fully converged langchain4j version: the chat
model implementation (`langchain4j-ollama:1.20.2`) runs one minor version ahead
of the `langchain4j-core:1.19.3` API surface (`ChatModel`, `ToolExecution`,
etc.) that the rest of the stack — including the agent/tool-calling machinery —
is compiled and wired against. This compiled cleanly (`OllamaChatModel`'s
public builder API didn't change between 1.19.3 and 1.20.2), but it is exactly
the kind of skew that can surface as a `NoSuchMethodError`/`AbstractMethodError`
at runtime if `OllamaChatModel` internally calls a `langchain4j-core` method
only added in 1.20.x. **This cannot be fixed from this module** — both BOM
versions are fixed by the parent POM (DRQ-004) and importing a matching
`langchain4j-core` override here would violate the "never re-pin BOMs" rule.
If the opt-in Ollama test below (or manual testing) ever throws a
`NoSuchMethodError`/`AbstractMethodError` out of `OllamaChatModel`, this skew
is the first thing to suspect, and the fix has to happen at the parent/BOM
level (aligning `quarkus-camel-bom` and `quarkus-langchain4j-bom` to versions
whose transitive `dev.langchain4j` graphs actually agree).

## Running with Ollama

```bash
ollama pull qwen2.5:3b
ollama serve                      # http://localhost:11434 by default

cd examples/ai-mcp-service
mvn quarkus:dev -f ../pom.xml -pl ai-mcp-service    # or: mvn quarkus:dev (run from this dir)

curl -X POST http://localhost:8088/api/orders/classify \
  -H 'Content-Type: application/json' \
  -d '{"item":"laptop","quantity":1}'

curl -X POST http://localhost:8088/api/assistant/chat \
  -H 'Content-Type: text/plain' \
  -d 'What is the status of order ORD-001?'
```

## Tests

- `OrderClassifierRouteTest` (`*Test`, runs under plain `mvn test`) — a wiring
  test only. It asserts the three routes (`classify-order`, `order-lookup-tool`,
  `assistant-chat`) are registered and started in the `CamelContext`. It does
  **not** call `langchain4j-chat` or `langchain4j-agent`, so it needs no LLM.
- `OrderAssistantRouteIT` (`*IT`, **not** picked up by Surefire's default
  include patterns, and additionally gated behind
  `-Dollama.tests.enabled=true`) — the real behavioral test. It sends a
  question about `ORD-001` directly to `direct:assistant-chat` via
  `ProducerTemplate` and asserts the
  `CamelLangChain4jAgentToolExecutions` exchange header
  (`org.apache.camel.component.langchain4j.agent.api.Headers#TOOL_EXECUTIONS`)
  is present and non-empty. A 200/non-empty response body is deliberately
  **not** treated as proof of tool calling — the model can answer from its own
  knowledge without invoking the `order-status` tool, which is exactly the
  failure mode (`toolExecutions` empty) the seed's `AgentProducers` workaround
  exists to prevent. Run it explicitly once Ollama is up:

  ```bash
  mvn test -Dollama.tests.enabled=true -Dtest=OrderAssistantRouteIT \
    -f ../pom.xml -pl ai-mcp-service
  ```

## Known blocker: `mvn test` / `@QuarkusTest` currently fails reactor-wide (pre-existing, out of scope)

`@QuarkusTest` (used by both test classes above) bootstraps its "curated
application" by resolving the **entire** Maven reactor workspace (all
`<module>` entries from the root `examples/pom.xml`), not just this module and
its parent chain. Two sibling modules currently have invalid XML comments —
comments containing a literal `--`, which is illegal in XML — that make their
`pom.xml` unparsable:

- `examples/order-service/pom.xml:29` — `"...re-pinned here -- inherited transitively..."`
- `examples/inventory-service/pom.xml:24` — `` "...dependency jar -- see..." ``

This breaks Quarkus's workspace resolution for **every** module in the
reactor, including this one, even though `ai-mcp-service` has no dependency on
either module. Verified independently:

- `cd examples/ai-mcp-service && mvn -q -DskipTests package` → **exit 0**
  (plain Maven build; doesn't touch sibling POMs).
- `cd examples/ai-mcp-service && mvn -q test-compile` → **exit 0** (both test
  classes compile cleanly against the real Camel/langchain4j APIs).
- `cd examples/ai-mcp-service && mvn test` → **fails** with
  `BootstrapMavenException: Failed to load current project` /
  `Failed to load POM from .../order-service/pom.xml`, i.e. before any test in
  this module even runs.
- The literal task-specified command,
  `mvn -q -pl ai-mcp-service -DskipTests package -f examples/pom.xml`, also
  fails for the same reason (full-reactor POM parsing), even with
  `-DskipTests` — Maven itself (not just Quarkus) refuses to compute the
  reactor graph while any module's POM is unparsable. Retried once per
  instructions; failure is deterministic, not transient.

Fixing those two files is outside this task's scope (`ai-mcp-service` only;
no edits to other modules). The one-line fix, for whoever owns those modules,
is to remove or rephrase the `--` inside each offending comment (e.g. replace
`-- ` with `— ` (em dash) or `: `).
