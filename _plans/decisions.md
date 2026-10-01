---
title: Decision Log
description: Architecture and tooling decisions for the Quarkus DataMesh reference architecture
---

# Decision Log — datamesh-reference-arch-quarkus

Records the settled decisions (DRQ-NNN) for this build. Convert relative dates to absolute.

## Version matrix (DRQ-001)

| Component | Version | Notes |
|-----------|---------|-------|
| Quarkus | **3.39.5** | Current latest **stable** (4.0.0 is Beta only). User's pin confirmed correct. |
| JDK | **25** (`25-tem`) | Supported on Quarkus 3.39.x; seed pom already compiles source/target 25. |
| Camel | **platform-aligned** | Import `quarkus-camel-bom:3.39.5`; do NOT pin standalone Camel. |
| langchain4j (Quarkiverse) | **1.7.4** | Reverted to the seed's version (was briefly 1.14.1). Gives a converged, seed-identical classpath (dev.langchain4j 1.11.0) with no manual pin. Version is NOT the cause of the tool-calling failure — see DEF-001. |
| Maven | 3.9.x | |
| Base images | UBI (`ubi10/openjdk-25` builder + `-runtime`) | Multi-stage; docker toolchain, NOT podman. |

## Settled decisions

- **DRQ-002 — Repo creation:** Build locally first. GitHub remote (github.com/patterncatalyst/datamesh-reference-arch-quarkus, **PUBLIC**) created + pushed ONLY after user approval.
- **DRQ-003 — Container toolchain:** New skill `lgtm-docker-stack` (docker, docker compose, Testcontainers/Dev Services, devcontainers, minikube). No podman. Multi-stage images, prefer UBI.
- **DRQ-004 — Quarkus/JDK:** Latest stable Quarkus (3.39.5) + JDK 25.
- **DRQ-005 — OIDC demo:** Attempt live (Keycloak Dev Service); if laptop budget too tight, document conceptually + log deferral here (mirrors python CAP-047 pattern).
- **DRQ-006 — Spring Boot comparison:** Ship ONE runnable Spring Boot twin service for real side-by-side startup/memory/native numbers, plus comparison chapter + slides.
- **DRQ-007 — lgtm-quarkus skill:** Already targets latest stable Quarkus + JDK 25 (no retarget). Optional ancillary pin refresh (Maven 3.9.9→3.9.16; evaluate Citrus 4.10.3→5.0.2) is low priority.
- **DRQ-008 — Domain:** Same shipping/order domain used across the user's repos (order/inventory/payment/shipping/notification/review + GraphQL gateway).

- **DRQ-009 — Event serialization (Avro + Apicurio, up front):** ALL Kafka events use Avro with the Apicurio Schema Registry from the start — NOT JSON. Rationale: user directive — do it up front so we never have to retrofit serialization later (historically missed if deferred). `contracts` module owns the `.avsc` schemas (`order-placed.avsc`, `payment-captured.avsc`, `shipment-dispatched.avsc`); Quarkus Avro codegen generates the record classes; producers/consumers use `apicurio-registry-avro` serde. Apicurio registry provided via Quarkus Dev Services (Testcontainers) in dev/test; standalone in Docker Compose (Phase C). Supersedes the planner's Phase-B JSON shortcut.
- **DRQ-010 — payment/shipping services:** Real event-driven choreography processors (NOT the Python stubs). `order.placed` → payment-service emits `payment-captured` → shipping-service emits `shipment-dispatched`. Each Avro over Kafka per DRQ-009.

- **DRQ-011 — Phase C infrastructure choices (user-gated):**
  - **Docker (step 8):** BOTH standalone `docker compose` (standing infra for humans/services) AND Testcontainers (self-provisioning ITs). Root `compose.yaml`; support configs under `infra/`. Config wiring via a single `%prod` env-driven profile (`${KAFKA_BOOTSTRAP_SERVERS}`/`${APICURIO_REGISTRY_URL}`/`${JDBC_URL}`) so the same image serves compose and K8s. Multi-stage UBI Containerfiles (`ubi10/openjdk-25`) under each module `src/main/docker/`. **LGTM observability stack: always-on baseline** (user choice — not profile-gated). Ollama remains `--profile ollama` opt-in (DEF-001 stays opt-in).
  - **Image tags pinned once** in `.env` == Quarkus 3.39.5 Dev Services tags == the DEF-002 IT Testcontainers tags (wire-compat crux). Postgres/app containers run `TZ=UTC` + JVM `-Duser.timezone=UTC` (no US/Eastern regression).
  - **DEF-002 home:** `order-service` module — Testcontainers failsafe IT (`OrderPlacedAvroWireIT`) asserts Avro magic byte `0x0` + schema id, fails if JSON. Runs in default `mvn verify` (self-provisions; no compose needed). Failsafe `integration-test`+`verify` execution wired in order-service.
  - **Minikube (step 9):** raw manifests + kustomize (base + minikube overlay) for apps; Helm only for operators (Strimzi, CNPG, KEDA). **Istio + Kiali: ON** (user choice — keep mesh). KEDA HTTP add-on pinned 0.12.2. **Kafka-lag KEDA scaler drives notification-service** (consumes `order.placed`). HTTP scaler on graphql-gateway. **Images built locally into minikube's docker** (`minikube docker-env`), no registry.
  - Phase C lands the KEDA scalers (substrate); the `demo-keda-*.sh` demos come in Phase D.

## Phase D decisions

- **DRQ-012 — real-world AI+rules scenario — ACCEPTED (primary AI demo, Phase D step 10).**
  Compose Ollama with a Quarkus + Camel + **Drools** (business-rules) flow:
  order triage where Camel routes an incoming order, Ollama classifies/extracts
  intent, and a Drools rule set makes the deterministic business decision (fraud
  hold, expedite, route-to-warehouse) on the shipping/order domain. This is the
  **showcase AI demo** — Drools (not langchain4j tool-calling) makes the business
  decision, so it **sidesteps DEF-001**: no in-process agent tool-calling round
  trip is required for the demo to work end to end. Keep it one focused demo (not
  speculative infra per scope-discipline). Scope/depth settled in the Phase D
  step-10 plan.

  **Engine decision (user directive):** use **plain embedded Drools** — the rule
  engine as a library (`org.drools` `drools-core`/`drools-compiler`, a
  `KieContainer` built at app startup in a CDI bean) — NOT the Kogito/KIE Quarkus
  extension. **KIE is explicitly not a roadmap item**; no Kogito platform, no KIE
  process/flow/BPMN. Orchestration is done by **Quarkus + Camel** (the point of the
  demo). This removes the KIE-extension compatibility spike; the only early check
  is a light probe that embedded `drools-core` compiles and runs a trivial `.drl`
  on Quarkus 3.39.5 / JDK 25. ai-rules-service is JVM-mode (native is not a goal
  for this module).
- **DRQ-013 — Phase D breadth — staged (demos first).** Phase D is sequenced:
  plan + build step 10 (demos 1:1 with slides, incl. DRQ-012) first, reassess
  before steps 11–13 (tutorial chapters, diagrams, deck). Demos are the
  hardest-to-fake artifact and feed the chapters and deck downstream.

## Deferrals

- **DEF-001 — Ollama tool-calling does not fire in ai-mcp-service — OPEN (behavioral), with precise root cause; classpath side RESOLVED.**

  **Symptom.** The opt-in IT `OrderAssistantRouteIT` (`-Dollama.tests.enabled=true`) sends "What is the status of order ORD-001?" to `direct:assistant-chat` and asserts the agent actually invoked the `order-status` ai-tool — a non-empty `CamelLangChain4jAgentToolExecutions` header. It fails: the model returns a plain answer in a single ~30s round trip, the `order-lookup-tool` route is never invoked, and the header is absent (null).

  **Root cause (upstream integration, not our code).** `camel-quarkus-support-langchain4j`'s `SupportQuarkusLangchain4jProcessor.enforceJaxRsHttpClient()` *unconditionally* sets the global system property `langchain4j.http.clientBuilderFactory=io.quarkiverse.langchain4j.jaxrsclient.JaxRsHttpClientBuilderFactory` ("Quarkus LangChain4j detected - enforcing JAX-RS HTTP client factory"). Every `dev.langchain4j` model's transport is therefore Quarkus-controlled: the `base-url` set on the hand-built `OllamaChatModel` is not honoured (requests resolve to the dev-service-detected Ollama on 11434, not a configured override), and the agent's tool-calling round trip never carries/elicits a tool call. There is no toggle for the enforcement.

  **Ruled out by diagnosis (so these are NOT the cause):**
  - *Model capability* — a direct `POST /api/chat` curl with a `tools` array returns a `tool_calls` response from both `qwen2.5:3b` and `qwen2.5:7b-instruct`.
  - *Tool registration / tags* — the ai-tool route is `tags=shipping`, the agent endpoint is `tags=shipping`; the `order-lookup-tool` route starts before the test runs.
  - *langchain4j version* — reproduces on every combination tried. Classpath now matches the seed exactly: Quarkiverse 1.7.4, dev.langchain4j 1.11.0, camel 4.22.0 / camel-quarkus 3.39.0. The seed (`enterprise-integration-patterns-with-camel/examples/42-ai-mcp/quarkus`) ships **no** test asserting tool-calling, so "the seed works" was an assumption, not a verified fact.
  - *Hand-built vs. synthetic model, and explicit JDK HTTP client* — the agent uses our `AgentWithoutMemory` (`AiServices.chatModel(configuration.getChatModel())`); passing `httpClientBuilder(new JdkHttpClientBuilder())` did not change the behaviour (JAX-RS enforcement still wins). Both reverted.

  **Classpath side — RESOLVED.** Reverted the forced `dev.langchain4j-bom:1.20.2` over-pin; `quarkus-langchain4j-bom:1.7.4` is imported FIRST so the whole dev.langchain4j family converges at 1.11.0 with no manual pin (see parent `examples/pom.xml`). Clean, seed-identical, compiles and the default reactor build is green.

  **Why it does not block the build.** The IT is named `*IT` (Surefire skips it), is gated behind `-Dollama.tests.enabled=true`, and failsafe is not bound in ai-mcp-service — so `mvn verify` never runs it and never needs Ollama.

  **Could not capture (needs root).** The decisive remaining datum — the exact JSON body sent to Ollama on 11434, to confirm whether `tools` is serialized at all — requires intercepting 11434. Ollama runs as root (`ollama serve`) and sudo is unavailable in this environment, and the enforced JAX-RS transport ignores a configured proxy port, so the request could not be captured.

  **Options to revisit (Phase D or later):** (a) try a newer camel-quarkus / quarkus-langchain4j train where the JAX-RS enforcement or tool-provider wiring differs; (b) reproduce minimally and file upstream against camel-quarkus-support-langchain4j; (c) demonstrate tool-calling via the embedded MCP server path (external MCP client) instead of the in-process langchain4j-agent; (d) relax the IT to document-only if tool-calling is shown another way. Keep as a documented deferral until one lands.
- **DEF-002 — Avro-on-the-wire — RESOLVED (byte-asserted, Phase C).** Was: config-proven only; no test read a raw record off a real broker. **Fix landed:** `OrderPlacedAvroWireIT` (order-service, Testcontainers Kafka `apache/kafka-native:4.2.0` + Apicurio `apicurio-registry:3.1.7`) produces a real `capstone.order.v1.OrderPlaced` with `AvroKafkaSerializer`, consumes with a vanilla `KafkaConsumer<byte[],byte[]>`, and asserts `value[0]==0x0` (Avro magic byte) + `value[0]!=0x7B` (not JSON) + schema id present; optional round-trip via `AvroKafkaDeserializer`. Proven to fail loudly if serde regresses to JSON. Runs in the default `mvn verify` (self-provisioning; no compose needed), failsafe execution bound in order-service. Note: Avro 1.12.x `ClassSecurityValidator` required `org.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1` on the IT's failsafe execution (plain JUnit, no Quarkus bootstrap to auto-trust the package).

## Test/build notes

- **Timezone:** parent pom pins `user.timezone=UTC` for surefire+failsafe. The `postgres:18` Dev Services container rejects legacy Olson zone ids (e.g. `US/Eastern`) forwarded by pgjdbc from the host default, failing boot with `invalid value for parameter "TimeZone"`. Pin keeps `mvn verify` green on any host.
