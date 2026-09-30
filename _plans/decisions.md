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
| langchain4j (Quarkiverse) | **1.14.1** | Bump from seed's 1.7.4; re-validate Ollama tool-calling path. |
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

## Deferrals

- **DEF-001 — langchain4j version skew (ai-mcp-service) — RESOLVED (compile/pin); behavioral test pending Ollama.** Was: `langchain4j-core` mediated to 1.19.3 while `langchain4j-ollama` stayed 1.20.2 (not converged). **Fix landed:** imported `dev.langchain4j:langchain4j-bom:1.20.2` FIRST in parent `<dependencyManagement>` so it wins mediation over Camel's transitives; `dependency:tree` now shows core/ollama/http-client all 1.20.2 (beta modules 1.20.2-beta30). ai-mcp-service still compiles. **Still open:** the opt-in Ollama `toolExecutions`-non-empty test (`OrderAssistantRouteIT`, `-Dollama.tests.enabled=true`) has NOT been run — Ollama was not running on localhost:11434 during validation. Run it once Ollama is up to close behaviorally.
- **DEF-002 — Avro-on-the-wire — RESOLVED (byte-asserted, Phase C).** Was: config-proven only; no test read a raw record off a real broker. **Fix landed:** `OrderPlacedAvroWireIT` (order-service, Testcontainers Kafka `apache/kafka-native:4.2.0` + Apicurio `apicurio-registry:3.1.7`) produces a real `capstone.order.v1.OrderPlaced` with `AvroKafkaSerializer`, consumes with a vanilla `KafkaConsumer<byte[],byte[]>`, and asserts `value[0]==0x0` (Avro magic byte) + `value[0]!=0x7B` (not JSON) + schema id present; optional round-trip via `AvroKafkaDeserializer`. Proven to fail loudly if serde regresses to JSON. Runs in the default `mvn verify` (self-provisioning; no compose needed), failsafe execution bound in order-service. Note: Avro 1.12.x `ClassSecurityValidator` required `org.apache.avro.SERIALIZABLE_PACKAGES=capstone.order.v1` on the IT's failsafe execution (plain JUnit, no Quarkus bootstrap to auto-trust the package).

## Test/build notes

- **Timezone:** parent pom pins `user.timezone=UTC` for surefire+failsafe. The `postgres:18` Dev Services container rejects legacy Olson zone ids (e.g. `US/Eastern`) forwarded by pgjdbc from the host default, failing boot with `invalid value for parameter "TimeZone"`. Pin keeps `mvn verify` green on any host.
