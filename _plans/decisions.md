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
| Base images | UBI (`ubi10/openjdk-25` builder + `-runtime`) | Multi-stage; docker toolchain, NOT podman. | <!-- forbidden-ok -->

## Settled decisions

- **DRQ-002 — Repo creation:** Build locally first. GitHub remote (github.com/patterncatalyst/datamesh-reference-arch-quarkus, **PUBLIC**) created + pushed ONLY after user approval.
- **DRQ-003 — Container toolchain:** New skill `lgtm-docker-stack` (docker, docker compose, Testcontainers/Dev Services, devcontainers, minikube). No podman. Multi-stage images, prefer UBI. <!-- forbidden-ok -->
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
  - **Minikube (step 9):** raw manifests + kustomize (base + minikube overlay) for apps; Helm only for operators (Strimzi, CNPG, KEDA). **Istio + Kiali: ON** (user choice — keep mesh). KEDA HTTP add-on pinned 0.15.0 (matches the python reference; enables HTTP/REST request-rate scaling — v0.14.0 panic #1668 fixed before 0.15.0, which also adds HTTP/2 + gRPC). **Kafka-lag KEDA scaler drives notification-service** (consumes `order.placed`). HTTP scaler on graphql-gateway. **Images built locally into minikube's docker** (`minikube docker-env`), no registry.
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
  process/flow/BPMN. The first cut orchestrates the triage with a **Camel route**
  (`POST /api/orders/triage`); the workflow-engine orchestration is added as a
  contrast by **Quarkus Flow** (see DRQ-014), NOT by KIE. This removes the
  KIE-extension compatibility spike; the only early check is a light probe that
  embedded `drools-core` compiles and runs a trivial `.drl` on Quarkus 3.39.5 /
  JDK 25. ai-rules-service is JVM-mode (native is not a goal for this module).
- **DRQ-014 — Quarkus Flow as the orchestration / workflow-engine showcase — ACCEPTED
  (AI/agentic orchestration framing).** Add the Quarkiverse **Quarkus Flow**
  extension (`io.quarkiverse.flow:quarkus-flow`, via `quarkus-flow-bom`) to
  re-orchestrate the DRQ-012 triage pipeline (receive → Ollama classify → Drools
  decide → route) as a **declarative workflow**, exposed alongside the Camel-route
  version for a direct A/B (candidate: second endpoint `POST /api/orders/triage-flow`
  in `ai-rules-service`, reusing the same fact POJO, `order-triage.drl`, and
  classify prompt). Quarkus Flow implements the CNCF **Open/Serverless Workflow
  Specification** (fluent Java DSL + YAML), is low-dependency and native-friendly,
  and crucially **does NOT pull Kogito/KIE/Drools** — consistent with "KIE is not a
  roadmap item." Built against Quarkus **3.39.0** (same 3.39.x train as our 3.39.5);
  Java 17+ (we run 25). Exact version pinned via a light compat spike (like Drools):
  confirm the `quarkus-flow-bom` version that runs a minimal Java-DSL workflow on
  Quarkus 3.39.5 / JDK 25 AND coexists with camel-quarkus + langchain4j in the
  reactor. Keep it one focused demo (scope-discipline): the contrast, not a second
  product. Docs: https://docs.quarkiverse.io/quarkus-flow/dev/
- **DRQ-015 — "three engines, different orchestration styles" is a required narrative
  (docs + deck) — ACCEPTED (user directive).** The project deliberately demonstrates
  three integration/orchestration mechanisms over the SAME shipping/order domain, and
  this comparison must be explicitly documented in the tutorial chapters (step 11) and
  featured in the presentation deck (step 13):
    - **Kafka** — event-driven **choreography** (decentralized; no central
      coordinator). DRQ-009/010: `order.placed` → payment-service → `payment-captured`
      → shipping-service → `shipment-dispatched`, Avro over Kafka.
    - **Camel** — route/EIP **orchestration** (centralized route coordinates steps).
      ai-rules-service `POST /api/orders/triage` and the Camel EIP demos.
    - **Quarkus Flow** — declarative **workflow-engine orchestration** (CNCF Open/
      Serverless Workflow). DRQ-014: ai-rules-service `POST /api/orders/triage-flow`.
  Terminology discipline for the deck: Kafka is **choreography**, Camel and Quarkus
  Flow are **orchestration** — present the choreography-vs-orchestration distinction
  as the teaching point, framed by the user as "different orchestrations," i.e. three
  engines solving coordination differently. Each engine → at least one demo + one
  slide; include a side-by-side comparison slide (when to reach for which).
- **DRQ-013 — Phase D breadth — staged (demos first).** Phase D is sequenced:
  plan + build step 10 (demos 1:1 with slides, incl. DRQ-012) first, reassess
  before steps 11–13 (tutorial chapters, diagrams, deck). Demos are the
  hardest-to-fake artifact and feed the chapters and deck downstream.
- **DRQ-016 — Host access: NodePorts published on 127.0.0.1 at profile creation.** Status: decided and live-verified 2026-10-09 (Docker Engine provided by Docker Desktop; see reconciliation).
  - **Context.** Host access used SSH tunnels, which disconnect when the cluster idles or is under load. <!-- forbidden-ok -->
  - **Decision.** Every host-facing service is a fixed NodePort, published when the profile is created: `minikube start -p datamesh --ports=127.0.0.1:<host>:<node>,...`. The host:nodePort map lives in `demos/lib/endpoints.sh`. Host ports are unchanged (Grafana stays at `http://127.0.0.1:3000`). Loopback only. `scripts/show-endpoints.sh` prints what is published and reachable. Changing the ports means recreating the profile with `setup-profile.sh --replace`.
  - **Rejected.**
    - Supervised SSH forwarding: keeps the moving part and adds a supervisor. <!-- forbidden-ok -->
    - `kubectl port-forward` loops: they pin one pod and lose the connection between retries. <!-- forbidden-ok -->
    - `minikube tunnel` with LoadBalancer Services: needs a long-running privileged process. <!-- forbidden-ok -->
    - The bare `--ports=a:b` form: binds 0.0.0.0 and exposes the cluster to the network. <!-- forbidden-ok -->
    - Renumbering host ports: breaks every documented URL.
    - Exposing application Services: only platform endpoints are published.
    - Moving the nodePorts to 30000-30085: kept as a fallback if a fixed nodePort collides with a dynamically allocated one.
  - **Consequences.** Recreating the profile wipes loaded images (re-run `scripts/load-images.sh`). `scripts/forbidden-syntax.sh`, run by `.github/workflows/checks.yml`, fails the build on forwarding syntax. <!-- forbidden-ok -->
- **DRQ-017 — Docker Engine on Fedora/RHEL hosts; host scope; compose/cluster exclusivity; devcontainer removed.** Status: decided and live-verified 2026-10-09: compose guard refused while the cluster ran; `walkthrough.sh --with-minikube` ACT 5 started the stopped profile and passed both KEDA demos.
  - Docker Engine is required. Docker Desktop is optional, as an example of a VM-based engine.
  - Supported hosts are Fedora or RHEL, bare metal or VM. No other OS is documented; scan 6 of `scripts/forbidden-syntax.sh` enforces it.
  - `.devcontainer/` is removed: ubuntu base, unpinned "latest" features, and forwardPorts. <!-- forbidden-ok -->
  - Compose and the cluster cannot run together (ports 3000, 3100, 3200, 4317, 4318). Guards: `demos/lib/_demo.sh` `compose_up`, `scripts/run-all-tests.sh` (preflight, for `--load`/`--all`), `tooling/newman/run-newman.sh`, the `demos/walkthrough.sh` preflight, and the `scripts/setup-profile.sh` pre-flight (free host ports, including before starting a stopped profile).
  - Walkthrough ACT 5 (`--with-minikube`) starts the stopped profile.
  - `scripts/load-images.sh` waits for rollouts and for terminating pods.
  - The gRPC resolver lesson from the Python repo (DRA-017/019) does not apply: Quarkus clients use the JDK/Netty resolver, and `INVENTORY_GRPC_HOST` is an FQDN.
  - Deferrals: DEF-003, DEF-004.

- **DRQ-018 — OpenShift Local appendix: scope and tiering.** Status: decided; live-verified 2026-10-09 on CRC 4.22.14 (6 vCPU / 20 GiB).
  - The appendix deploys the 7 core services (order, inventory, payment, shipping, notification, review, graphql-gateway), Postgres, Apicurio and Kafka. LGTM observability and the AI services are documented only; Istio (OSSM 3) and KEDA (CMA) are a phase 2 platform tier.
  - The CRC is dedicated to this workshop: `openshift/teardown.sh` removes the Helm release, Kafka, the project, the AMQ Streams Subscription/CSV/InstallPlans and the Strimzi CRDs, then runs `crc stop`.
  - Access uses the `crc-admin` kubeconfig context that `crc start` writes; no password is typed, printed or stored.
- **DRQ-019 — OpenShift build path: quarkus-openshift binary S2I.** Status: decided; live-verified (7 builds, about 15 s each in-cluster, 154 s for the whole reactor).
  - Each service pom has an `openshift` profile adding `quarkus-openshift`. `quarkus-container-image-openshift` alone generates no BuildConfig ("No OpenShift manifests were generated"), so the full extension is required; `quarkus.kubernetes.deploy=false` keeps it to build-and-push.
  - Base image `registry.access.redhat.com/ubi10/openjdk-25:1.24-15` (the extension's default is ubi9). Output tag comes from `quarkus.openshift.version`; `quarkus.container-image.tag` alone leaves the project version.
  - Rejected: a Docker-strategy BuildConfig running Maven in the VM (the VM would pull from Maven Central), pushing from a host engine to the exposed registry (needs an insecure-registry setting), and podman. <!-- forbidden-ok -->
  - The S2I image starts the app with `run-java.sh`, not the Containerfile entrypoint, so the chart sets `JAVA_TOOL_OPTIONS` (Avro packages) and `JAVA_MAX_MEM_RATIO=50` (the image reads `JAVA_MAX_MEM_RATIO`, not `JAVA_MAX_RAM_RATIO`; the default is 80).
- **DRQ-020 — OpenShift infra.** Status: decided; live-verified.
  - Kafka: AMQ Streams `amqstreams.v3.2.1-14` from redhat-operators, channel `amq-streams-3.2.x`, Manual approval with `startingCSV` (the script approves only that InstallPlan). Kafka CR `datamesh` on the `kafka.strimzi.io/v1` API (v1beta2 is deprecated), Kafka 4.2.0, one KRaft dual-role node, no entity operator (topics auto-create, and teardown has no KafkaTopic finalizers).
  - Postgres: StatefulSet on `registry.redhat.io/rhel10/postgresql-16:10.2-1791491499` under restricted-v2 (minikube runs CNPG with PostgreSQL 18.6; the drift is documented). Service `datamesh-postgres-rw` and Secret `datamesh-postgres-app` keep the minikube names, so the env contract is unchanged. The password is generated once by Helm (`lookup`) and never written down.
  - Apicurio `quay.io/apicurio/apicurio-registry:3.2.4`, in memory, matching minikube.
  - The DB services get a `wait-for-postgres` init container (bash `/dev/tcp`, same image) so they do not restart while Postgres initialises.
- **DRQ-021 — OpenShift host access: Routes, no NodePorts.** Status: decided; live-verified.
  - Edge-TLS Routes for graphql-gateway and Apicurio (`*-datamesh.apps-crc.testing`), HTTP redirected. Evidence uses `curl --cacert` with the cluster's ingress CA, never `--insecure`. Seeding and order creation go through `oc exec` into the service pod.
  - Every pod runs under `restricted-v2` with a UID from the namespace range; the chart never sets `runAsUser`.
- **DRQ-022 — review-service on OpenShift: OIDC tenant disabled.** Status: decided; live-verified.
  - The prod build fails at boot with "'quarkus.oidc.auth-server-url' property must be configured" because no OIDC provider runs there. The chart sets `QUARKUS_OIDC_TENANT_ENABLED=false`; `DELETE /reviews/{id}` answers 401 and every other endpoint works. `application.properties` is unchanged.

- **DRQ-023 — OpenShift platform tier: service mesh.** Status: decided; live-verified 2026-10-09 on CRC 4.22.14 (12 vCPU / 32 GiB).
  - OSSM 3 (`servicemeshoperator3.v3.4.3`, channel `stable-3.4`) with `Istio` and `IstioCNI` pinned to `v1.30.5`. OSSM 3.4.3 offers v1.26 to v1.30, not minikube's 1.29.0, and `v1.30-latest` floats, so it is not used.
  - Pods join with the `istio.io/rev: default` label (chart `mesh.enabled`); `istio-proxy` is a native sidecar ordered before `wait-for-postgres`. Infra stays unmeshed.
  - `PeerAuthentication` STRICT for the namespace, PERMISSIVE for `graphql-gateway` (the Route delivers plaintext).
  - Canary (`mesh.canary.enabled`): `order-service-v2` + DestinationRule + 90/10 VirtualService, mesh-internal (no ingress gateway in OSSM 3).
  - Kiali `kiali-operator.v2.27.5`, anonymous auth (single-user local cluster). Its Prometheus is otel-lgtm's, which scrapes the sidecars' port 15020 when the mesh is on.
- **DRQ-024 — OpenShift platform tier: autoscaling.** Status: decided; live-verified.
  - Custom Metrics Autoscaler `custom-metrics-autoscaler.v2.19.0-4` in `openshift-keda` with a `KedaController`; chart `keda.enabled` adds minikube's Kafka-lag ScaledObject and stops setting `replicas` on notification-service.
  - `bootstrapServers` is fully qualified: KEDA runs in `openshift-keda`, where the short name does not resolve.
  - CMA ships core KEDA only; the gateway's HTTP scaler has no counterpart.
- **DRQ-025 — OpenShift platform tier: tracing.** Status: decided; live-verified.
  - Red Hat build of OpenTelemetry `opentelemetry-operator.v0.158.0-2` injects the OpenTelemetry Java agent (annotation `instrumentation.opentelemetry.io/inject-java`), matching the compose demo's `-javaagent` approach with no pom or image change. Traces only.
  - Backend `grafana/otel-lgtm:0.8.1` (the compose image) under `anyuid` with `runAsUser: 0` and no seccomp profile; Grafana Route.
  - `install-observability.sh` restarts Deployments whose pods missed injection (Helm creates Deployments before the Instrumentation CR).
- **DRQ-026 — OpenShift platform tier: AI services.** Status: decided; live-verified.
  - `ollama/ollama:0.35.1` (compose's pin) under restricted-v2 with `HOME`/`OLLAMA_MODELS` on a 10 Gi PVC; `qwen2.5:3b` pulled by a plain Job (not a Helm hook, so helm does not block on the download).
  - ai-mcp-service and ai-rules-service built in-cluster like the core; TCP probes (no health extension); `QUARKUS_HTTP_PORT=8080`.
- **DRQ-027 — OpenShift platform tier: native build in the cluster.** Status: decided; live-verified.
  - Host: `-Pnative -Dquarkus.native.sources-only=true`. Cluster: Docker-strategy binary build, `native-image` in `ubi10-quarkus-mandrel-builder-image:jdk-25.0.4.1`, runtime `ubi10-quarkus-micro-image:2.0-2026-10-04`, 4-8 GiB build pod. No container engine on the host, no Maven Central from the cluster.
  - Avro's allow-list must be a native build argument (`-J-Dorg.apache.avro.SERIALIZABLE_PACKAGES=...` via `quarkus.native.additional-build-args`): ClassSecurityValidator is initialised at image build time, so a runtime `-D` leaves every send failing with "Forbidden capstone...". `demo-native.sh` never produces to Kafka, so it does not catch this.
  - Native pod not annotated for the Java agent.
- **DRQ-028 — OpenShift platform tier: GitOps.** Status: decided; live-verified.
  - OpenShift GitOps `openshift-gitops-operator.v1.22.1`; the default Argo CD instance manages the project via `argocd.argoproj.io/managed-by`.
  - The Application renders `openshift/helm/datamesh` from GitHub (default `main`) with the release's current values and adopts its resources; automated sync, prune, self-heal.
  - `ignoreDifferences` on `datamesh-postgres-app` `/data/password` with `RespectIgnoreDifferences=true`: under `helm template` the chart's `lookup` returns nothing and would rotate the password on every sync.
  - Teardown deletes the Application first, then removes every platform operator with the CRDs its CSV owns, Istio's CRDs, and the operator namespaces.

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

- **DEF-003 — Bind compose ports on loopback — OPEN.** Compose publishes ports on all interfaces. Binding them to 127.0.0.1 would match DRQ-016 but changes `compose.yaml` for every demo; deferred until the compose path is next revised.
- **DEF-004 — `imagePullPolicy: Never` plus restart — OPEN.** `load-images.sh` keeps `datamesh/<svc>:latest` with `IfNotPresent` and `minikube image load`. Switching to `Never` plus a Deployment restart would fail fast on a missing image; deferred.

## Test/build notes

- **Timezone:** parent pom pins `user.timezone=UTC` for surefire+failsafe. The `postgres:18` Dev Services container rejects legacy Olson zone ids (e.g. `US/Eastern`) forwarded by pgjdbc from the host default, failing boot with `invalid value for parameter "TimeZone"`. Pin keeps `mvn verify` green on any host.
