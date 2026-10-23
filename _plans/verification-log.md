# Verification log

Per-chapter verification-status notes moved here from the chapter footers (the reader-facing site no longer shows them). Each entry is the footer text verbatim as it last stood on the site.

## 00-index.md

*Verification status: <span class="status status--verified">verified</span>. The site builds with `bundle exec jekyll build` (0 errors), and every chapter link in this index resolves to a rendered page.*

## 02-kubernetes-substrate.md

*Verification status: <span class="status status--verified">verified</span>. `scripts/bootstrap.sh` was driven end to end on a local `minikube` cluster (24 GB / 16 CPU; the first run used the podman driver), bringing up all eight tiers healthy: the cluster itself, Istio, CloudNativePG + Postgres, Strimzi + Kafka, KEDA, the full LGTM stack, Kiali, and Apicurio (50/50 pods Running). The bring-up surfaced and fixed three bootstrap bugs along the way: the Strimzi Kafka CR pinned an unsupported Kafka version, Mimir rejected overlapping filesystem data dirs, and Apicurio's readiness probe used a health path its image doesn't serve. Re-run on 2026-10-06 with the docker driver on Docker Engine (provided by Docker Desktop on the authoring host; 8 CPUs, so `MINIKUBE_CPUS=8`): all eight tiers came up with 50 pods Running after one fix, setup scripts that matched Helm repository names by prefix (an existing `grafana-community` repo hid a missing `grafana` repo). The service images then had to be built and loaded with `scripts/load-images.sh`; the cluster runs containerd, so the `minikube docker-env` route described in earlier revisions does not apply. Host access re-verified on 2026-10-09 (minikube v1.38.1, docker driver + containerd, Docker Engine provided by Docker Desktop on the authoring host, `MINIKUBE_CPUS=8 MINIKUBE_MEMORY=24g`): the profile was recreated with all eight NodePorts published on 127.0.0.1 and none on 0.0.0.0, a LAN request was refused, `bootstrap.sh` finished green, `show-endpoints.sh` reported all eight endpoints reachable, and the bindings survived `minikube stop`/start. The run fixed three pre-existing gaps: the Tempo chart ignored `service.nodePort`, Kiali ignored `deployment.node_port` (both now patched after install), and the in-cluster Tempo URL pointed at 3200 instead of the chart's HTTP port 3100. Versions moved on 2026-10-09 to Kubernetes v1.36.5, Istio 1.31.1, KEDA 2.21.0 / HTTP add-on 0.16.0, Strimzi 1.2.0 (Kafka 4.3.1), CloudNativePG 1.30.1 and the newest LGTM charts; this chapter is not yet re-verified on those pins.* <!-- forbidden-ok -->

## 03-services-and-data-products.md

*Verification status: <span class="status status--verified">verified</span>. `mvn verify` is green (`OrderResourceTest`, `InventoryGrpcServiceTest`, `OrderPlacedAvroWireIT`, `InventoryCheckStockWireIT`), and `demo-order.sh` and `demo-grpc.sh` passed end to end against a freshly started compose stack.*

## 04-contracts-and-catalog.md

*Verification status: <span class="status status--verified">verified</span>. `demo-kafka.sh`'s raw-byte magic-byte assertion passed and `OrderPlacedAvroWireIT` is green. One item remains unexercised: a backward-incompatible Avro schema change being rejected by Apicurio at publish time is still not covered by any demo.*

## 05-data-planes.md

*Verification status: <span class="status status--verified">verified</span>. `demo-graphql.sh` and `demo-grpc.sh` passed, and `OrderPlacedConsumerTest` confirms `@Transactional` alone makes the consumer blocking. One item remains unrun: the Camel YAML DSL route variant (only the Java DSL path has been exercised, via the Camel demo).*

## 06-progressive-delivery-mtls.md

*Verification status: <span class="status status--verified">verified</span>. Driven end to end on a local Kubernetes cluster (`minikube`). The injection fix is confirmed: Istio's `object.sidecar-injector.istio.io` webhook has an `objectSelector` matching `sidecar.istio.io/inject In ["true"]`, which is evaluated against pod *labels*, never annotations, so the pod-annotation form this chapter originally specified injected nothing in the unlabeled `datamesh` namespace, while the pod-template *label* form injects the native sidecar (`istio-init` + `istio-proxy`). `kubectl apply -k k8s/istio` applied cleanly: `order-service`, `notification-service`, and `graphql-gateway` came up meshed (2/2) while the operator-managed infra (Postgres, Kafka, Apicurio) stayed unmeshed. mTLS was enforced: a meshed client reached `order-service` with every request reported `connection_security_policy=mutual_tls` (20/20 `200`s), while a non-meshed plaintext client was rejected by the `STRICT` `PeerAuthentication` (`http_code=000`, connection reset), and unmeshed infra kept working. The canary split was observed at the Envoy layer as 63 requests to `v1` and 7 to `v2` out of 70, matching the `VirtualService`'s 90/10 weighting. Versions moved on 2026-10-09 to Kubernetes v1.36.5, Istio 1.31.1, KEDA 2.21.0 / HTTP add-on 0.16.0, Strimzi 1.2.0 (Kafka 4.3.1), CloudNativePG 1.30.1 and the newest LGTM charts; this chapter is not yet re-verified on those pins.*

## 07-elastic-and-resilient.md

*Verification status: <span class="status status--verified">verified</span>. Observed directly on a local Kubernetes cluster (`minikube`): both ScaledObjects drive their targets to zero at rest (`notification-service` and `graphql-gateway` sit at 0 replicas), and `notification-service` scales up from zero on Kafka consumer-group lag: placing valid orders emits `order.placed`, lag crosses the threshold, and KEDA activates the ScaledObject and scales the deployment 0→1. Driving this surfaced a bug in `demo-keda-kafka.sh` (it posted orders for an unseeded SKU, so order placement 409'd and produced no events), now fixed by seeding stock before the burst. Re-run on 2026-10-06 through `demos/walkthrough.sh --from act5 --with-minikube`: both demos passed. `demo-keda-kafka` scaled `notification-service` 0→1 on lag from 60 orders and drained back to 0 after the cooldown; `demo-keda-http` scaled `graphql-gateway` 0→1 through the interceptor, and all 120 GraphQL requests returned 200, including the first, held during the cold start. That run fixed three demo bugs: the HTTP load targeted the interceptor proxy on port 80 instead of 8080, it sent a bare GET that the gateway answers with 405, and both demos started from one running replica, which drained the burst before KEDA's 15 s poll saw any load. Each demo now scales its target to zero and waits out KEDA's scale-down window before the burst. Single run. Versions moved on 2026-10-09 to Kubernetes v1.36.5, Istio 1.31.1, KEDA 2.21.0 / HTTP add-on 0.16.0, Strimzi 1.2.0 (Kafka 4.3.1), CloudNativePG 1.30.1 and the newest LGTM charts; this chapter is not yet re-verified on those pins.*

## 08-observability.md

*Verification status: <span class="status status--verified">verified</span>. `demo-tracing.sh` passed, recording the cross-service trace against the compose otel-lgtm backend. The mesh/Kiali view is covered by the Kubernetes chapters, which still require a live cluster. Host access through NodePorts published on 127.0.0.1 was re-verified on 2026-10-09: Grafana (3000), Loki (3100), Tempo (3200), Mimir (9009), OTLP (4317/4318), Kiali (20001) and Apicurio (8084) all answered on loopback, and Grafana's Tempo datasource now points at Tempo's HTTP port 3100. On 2026-10-09 the compose backend moved to otel-lgtm 0.36.0 (stack healthy, Tempo trace API unchanged) and the cluster stack to the newest charts, where Tempo's HTTP port is 3200 again; the cluster side is not yet re-verified on those pins.*

## 09-anti-patterns.md

*Verification status: <span class="status status--verified">verified</span>. The "in this build" factual callouts (seven domain-service modules, the shared `datamesh` namespace, Avro-via-Apicurio from day one) are confirmed by the passing multi-module Maven build and the committed manifests.*

## 10-summary.md

*Verification status: <span class="status status--verified">verified</span>. The architectural claims (module/database boundaries, Apicurio as the registry, the KEDA ScaledObject/HTTPScaledObject targets, Istio injection being opt-in, the absence of an admission policy) are confirmed by the passing build and the committed `k8s/` manifests. The runtime behaviors they summarize are exercised in the progressive-delivery and elasticity chapters, which still require a live cluster.*

## 11-quarkus-capability-tour.md

*Verification status: <span class="status status--verified">verified</span>. `demo-reactive-vertx.sh` (concurrent reactive and imperative calls), `demo-continuous-testing.sh` (6/6), `demo-jbang-prototype.sh`, `demo-oidc.sh` (live Keycloak Dev Service), `demo-panama.sh` (JDK 25.0.3, JBang 0.138.0: `getpid` and `strlen` results match the JVM's own), and the gRPC, GraphQL, and REST demos passed. The AOT cache numbers are measured in chapter 12 from a single run. `demo-native.sh` passed on 2026-10-06 with the Mandrel builder container (136 s build, 141 MB binary, 0.081 s startup, `GET /orders` served with no JVM); that is also a single run. Figures 11.2 through 11.10 are explanatory diagrams; the illustrative `PanacheRepository` example is not run code.*

## 12-quarkus-vs-spring-boot.md

*Verification status: <span class="status status--verified">verified</span>. Both services build and boot, the twin's `mvn verify` passed (OrderControllerTest 4/4), and `scripts/compare-quarkus-springboot.sh` was run on JDK 25.0.3 (Temurin) on 2026-10-05 in default JVM mode and with `--aot`: both exited 0, the default JVM table and the AOT table above come from that single run (Quarkus 2.05 s / 337 MB against Spring Boot 4.02 s / 548 MB on the plain JVM), and the `--aot` run used `-XX:AOTMode=on`. Each figure is a single run. Native image is outside this JVM-to-JVM comparison; chapter 11 records its own run (`demo-native.sh`, 2026-10-06).*

## 13-orchestration-styles.md

*Verification status: <span class="status status--verified">verified</span>. The Flow, Drools, and route unit tests pass under `mvn verify`, and `demo-orchestration-styles.sh` ran end to end against the compose stack with the Ollama profile and a live `qwen2.5:3b`. All three coordination styles (Kafka choreography, the Camel route, and the Quarkus Flow workflow) ran over the same order-to-shipment domain and passed. Re-run on 2026-10-06 (walkthrough act 2): passed after the demo was changed to pull `qwen2.5:3b` into the compose volume when it is missing, as the act 3 demos already did.*

## 14-ai-rules-triage.md

*Verification status: <span class="status status--verified">verified</span>. Run against the compose stack with the Ollama profile and a live `qwen2.5:3b`: `demo-ai-classify.sh`, `demo-ai-mcp.sh`, `demo-camel-integration.sh`, and `demo-ai-triage.sh` all passed. The triage showcase returned the exact expected decisions (ROUTE_TO_WAREHOUSE / EXPEDITE / FRAUD_HOLD) for all three inputs on both the Camel `/api/orders/triage` and the Quarkus Flow `/api/orders/triage-flow` endpoints the LLM classifies, Drools decides. The in-process tool-calling defect remains documented as before; the MCP-server path is the one exercised. Re-run on 2026-10-06 through `demos/walkthrough.sh --with-ollama`: all four demos passed again. `demo-ai-triage.sh` now uses a host Ollama when one answers on port 11434 and otherwise starts the compose `ollama` profile itself; this run used the compose profile.*

## 16-websocket-scaling.md

*Verification status: <span class="status status--verified">verified</span> for the fan-out and for replica failure and client reconnect. On 2026-10-06, `tooling/ws-failover/verify-ws-failover.sh` held two replicas, received order A over the first connection as a push, deleted the replica holding the socket (`WS_CLOSED code=1000`), reconnected after a jittered 979 ms backoff, re-fetched 183 notifications with no new or duplicate order, and received order B as a push from the surviving replica. Single run. The multi-replica fan-out was driven on a local Kubernetes cluster (`minikube`) with two `notification-service` replicas. Each replica's push consumer registered its own unique Kafka group (`notification-push-${HOSTNAME}` resolved to the two distinct pod names, confirmed alongside the shared `notification-service` persistence group), so every replica received every `order.placed` record. A WebSocket client was connected to each replica; a single order was placed, and both clients independently received the push for that same order id, the Kafka-backed broadcast across per-replica consumer groups behaving as described. (`OrderPlacedConsumer` persists on the shared group; `OrderPlacedPushConsumer` pushes on the per-replica group.) The single-replica `demo-websocket.sh` passed on 2026-10-06 after a fix: the demo isolates each run on its own Kafka topic, and it now overrides the push channel (`order-placed-push`) as well as the persistence channel, so the pushed message reaches the socket.*

## 17-gotchas.md

*Verification status: <span class="status status--verified">verified</span>. The committed fixes are re-run green by `mvn verify`: `OrderPlacedAvroWireIT` covers the Avro serde / SERIALIZABLE_PACKAGES fixes, `InventoryCheckStockWireIT` covers the gRPC-port, import.sql self-seed, and integration-test timezone fixes, and `OrderResourceTest` covers the `@Consumes` fix.*

## 19-testing-details.md

*Verification status: <span class="status status--verified">verified</span>. The automated tiers run green: `mvn verify` across the project (unit + integration with self-provisioning Testcontainers), the Spring Boot twin build, and continuous testing (6/6). The live tiers ran on 2026-10-06 through `scripts/run-all-tests.sh --load` (compose stack plus order, inventory, gateway, and review services): the Newman collection passed 49/49 assertions (newman 6.2.2); `load-orders.sh` (hey v0.1.5, `GET /orders`, 10 workers, 20 s) returned 359,551 responses, all 200, at about 18,000 requests/s with a 99th percentile of 1.3 ms; `load-checkstock.sh` (ghz v0.121.0, gRPC `CheckStock`, 10 workers, 20 s) completed 241,014 OK calls at about 12,000 calls/s with a 99th percentile of 2.1 ms, plus 8 `Unavailable` and 1 `Canceled`. Single run on one workstation; the numbers show the harness works, not a benchmark.*

## 20-messaging-in-memory-vs-kafka.md

*Verification status: <span class="status status--verified">verified</span>. `ShipmentProcessorTest` passes against the in-memory connector under `mvn verify`, with the sink-clearing `@BeforeEach` preventing cross-test bleed. The new Vert.x event-bus material (`@ConsumeEvent`, send/publish/request-reply) and the Kafka scaling description (partition-count limit, KEDA on lag) are <span class="status status--conceptual">conceptual</span> or illustrative and were not run here.*

## 21-orchestration-engines-compared.md

*Verification status: <span class="status status--verified">verified</span>. The orchestration code is exercised green (`OrderTriageRouteTest`, `OrderTriageFlowTest`, `OrderTriageDrlTest`), and `OrderChoreographyChainIT` is confirmed `@Disabled` for the documented reason. The live choreography chain and the Camel/Flow orchestration demos call the local LLM; on 2026-10-06 `demo-orchestration-styles.sh` and `demo-ai-triage.sh` both passed against the compose Ollama profile with `qwen2.5:3b` (walkthrough acts 2 and 3, single run).*

## 22-running-on-openshift-crc.md

*Verification status: <span class="status status--verified">verified</span>. On 2026-10-09 both cycles above ran on OpenShift Local 2.64.0 (OpenShift 4.22.14, Kubernetes 1.35.6), with Quarkus 3.39.5, `rhel10/postgresql-16`, Apicurio 3.2.4, otel-lgtm 0.8.1 and Ollama 0.35.1. Later that day the pins moved to Quarkus 3.40.1, `rhel10/postgresql-18`, Apicurio 3.3.3, otel-lgtm 0.36.0 and Ollama 0.40.2; those are not yet re-verified on CRC, and the operator CSV pins are re-checked at the next run.*

*The core run used AMQ Streams `amqstreams.v3.2.1-14`, Kafka 4.2.0 and seven in-cluster builds on `ubi10/openjdk-25:1.24-15`. All pods were Ready under `restricted-v2` with zero restarts, the gateway Route was healthy, GraphQL stitched order and stock, the order went through payment and shipping for one order ID, and Apicurio held three artifacts.*

*The platform run, on the same core, recorded:*

- *the mesh rejecting plaintext under STRICT mTLS, a 91/9 canary split for 90/10, and Kiali reporting the namespace `MTLS_ENABLED` with 10 workloads in its graph;*
- *notification-service scaling 0 to 1 to 0;*
- *one trace across the gateway and inventory-service (the native order-service carries no agent);*
- *classify, triage and MCP matching the compose demos;*
- *the native order-service starting in 0.077 s at 29 MiB against 8.0 s and 200 MiB for the JVM pod;*
- *Argo CD Synced, restoring a deleted ConfigMap in 2 s.*

*The secret scrub passed, evidence is in `openshift/evidence/2026-10-09/`, and teardown removed every operator, CRD and namespace, then stopped CRC. Single run of each. Not covered: OpenShift's own monitoring stack, and Tekton pipelines.*

<!-- conceptual-status footers (chapters not live-verified) -->

## 01-concepts.md

*Status: <span class="status status--conceptual">conceptual</span>. This chapter is
conceptual framing with no code or commands to run. The
mapping of each principle to a specific piece of this build (Apicurio for the registry,
Istio for mTLS, KEDA for autoscaling) describes the intended architecture; confirm each
claim against the chapter that implements it (04, 06, 07), since
this chapter asserts them ahead of the hands-on chapters that prove them out.*

## 01-data-architectures.md

*Status: <span class="status status--conceptual">conceptual</span>. This
chapter is stack-agnostic conceptual framing with no code or commands to run; the
main item to confirm is that the terminology here (pipeline sprawl, schema-on-write
vs. schema-on-read, data swamp) stays consistent with how later, hands-on chapters use the
same terms once they're written.*

## 18-agentic-recommendations.md

*Status: <span class="status status--conceptual">conceptual</span>.
This chapter is a distillation of recommendations rather than a runnable
example, so there is no build or demo to execute against it. The claims
to re-check independently: that the known upstream defect in
`camel-quarkus-support-langchain4j`'s HTTP client override (breaking
in-process agent tool-calling) still reproduces against this repo's pinned
langchain4j/Camel versions, since an upstream fix would make that example
stale; and that the cited defect catalog and pull request references still match
the repository history, since this chapter was written from that record
rather than by re-deriving its claims.*

