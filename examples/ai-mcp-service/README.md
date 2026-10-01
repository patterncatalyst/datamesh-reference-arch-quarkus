# DataMesh :: AI MCP Service

Camel-on-Quarkus example combining `langchain4j-chat`, `ai-tool`, `langchain4j-agent`,
and the embedded Camel MCP server. Ported from
[`enterprise-integration-patterns-with-camel/examples/42-ai-mcp/quarkus`](https://github.com/patterncatalyst)
onto this reactor's pinned BOMs:

| BOM | Seed | This module |
|---|---|---|
| `quarkus-camel-bom` | 3.39.3 | **3.39.5** (parent-pinned) |
| `quarkus-langchain4j-bom` | 1.7.4 | **1.7.4** (parent-pinned, seed-matched) |

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

## langchain4j versions (seed-matched, converged)

The parent pins `quarkus-langchain4j-bom:1.7.4` and imports it **first** in
`dependencyManagement`, which yields a clean, fully converged classpath that
matches the seed exactly:

```
io.quarkiverse.langchain4j:quarkus-langchain4j-*  -> 1.7.4
dev.langchain4j:langchain4j-* (core/ollama/http-client/mcp/...) -> 1.11.0
org.apache.camel:camel-langchain4j-agent(-api)    -> 4.22.0
org.apache.camel.quarkus:camel-quarkus-langchain4j-agent -> 3.39.0
```

No manual `dev.langchain4j-bom` pin is needed — the import order alone keeps the
whole family at 1.11.0 (a brief 1.14.1 experiment required a forced
`dev.langchain4j-bom:1.20.2` to converge a split core/ollama graph and is not
used). The `OllamaChatModel` / `Agent` / `AgentConfiguration` /
`AgentWithoutMemory` APIs this module uses are stable across these versions and
compile as-is. See `../pom.xml` for the load-bearing BOM import order and
`_plans/decisions.md` (DRQ-001) for the version matrix.

## DEF-001: Ollama tool calling does not fire on this stack (open deferral)

The behavioral test `OrderAssistantRouteIT` asserts the agent actually invokes
the `order-status` ai-tool (a non-empty `CamelLangChain4jAgentToolExecutions`
header). **It currently fails**: the model answers in a single round trip and
the `order-lookup-tool` route is never called.

After exhaustive diagnosis this is an **upstream integration issue, not a bug in
this module**. `camel-quarkus-support-langchain4j` unconditionally enforces the
Quarkiverse JAX-RS HTTP client factory globally
(`SupportQuarkusLangchain4jProcessor.enforceJaxRsHttpClient()` →
`langchain4j.http.clientBuilderFactory` system property), so the hand-built
`OllamaChatModel`'s transport and `base-url` are not honoured and the agent's
tool-calling round trip never fires. Ruled out: model capability (a direct
`/api/chat` curl with a `tools` array returns `tool_calls`), tool/tag
registration, langchain4j version (reproduces on all; classpath matches the
seed, which ships no test asserting this), and an explicit JDK HTTP client.

The IT is `*IT` (Surefire skips it), gated behind `-Dollama.tests.enabled=true`,
and failsafe is **not** bound in this module, so the default `mvn verify` never
runs it and the reactor build stays green. Full write-up, ruled-out hypotheses,
and revisit options are in `_plans/decisions.md` (DEF-001) and the
`AgentProducers` class javadoc.

## Running with Ollama

```bash
ollama pull qwen2.5:3b
ollama serve                      # http://localhost:11434 by default

cd examples/ai-mcp-service
mvn quarkus:dev                   # or, from the repo root: mvn -pl ai-mcp-service quarkus:dev -f examples/pom.xml

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
  include patterns, and additionally gated behind `-Dollama.tests.enabled=true`)
  — the real behavioral test. It sends a question about `ORD-001` to
  `direct:assistant-chat` via `ProducerTemplate` and asserts the
  `CamelLangChain4jAgentToolExecutions` exchange header is present and non-empty.
  A non-empty response body is deliberately **not** treated as proof of tool
  calling. **This test currently fails — see DEF-001 above.** It is opt-in and
  not part of the default build:

  ```bash
  # from the repo root
  mvn failsafe:integration-test failsafe:verify \
    -Dollama.tests.enabled=true -f examples/pom.xml -pl ai-mcp-service
  ```
