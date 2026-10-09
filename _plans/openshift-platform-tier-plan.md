# Plan: OpenShift Local platform tier (follow-up to #53)

User, 2026-10-09: the CRC appendix must also cover service mesh, autoscaling, observability, the AI services, a native build and GitOps. Branch `feat/openshift-platform-tier`, cut from main 119e121.

## Rules (unchanged from the core appendix)
- CRC is dedicated to datamesh; `teardown.sh` must also remove everything this tier adds (operators, CSVs, CRDs, namespaces), then `crc stop`.
- No password handling: `crc-admin` context only. Evidence passes the secret scrub.
- Pinned versions only. No port-forward or tunnels; Routes or `oc exec`. Fedora/RHEL only. No container engine on the host. <!-- forbidden-ok -->
- Every item live-verified on CRC before it is documented as verified.

## Sizing
CRC 32 GiB / 12 vCPU / 80 GB (host: 16 cores, 62 GiB). Set while stopped.

## Design
| Item | Approach | Verify |
|---|---|---|
| Service mesh | OSSM 3 (`servicemeshoperator3`, Sail): `Istio` + `IstioCNI` CRs, namespace label `istio.io/rev`, chart `mesh.enabled` adds sidecars; `PeerAuthentication` STRICT; Kiali via `kiali-ossm` with a Route | sidecars 2/2, mTLS STRICT enforced (plaintext from a non-mesh pod refused), traffic still flows; Kiali graph API lists the services |
| Autoscaling | Custom Metrics Autoscaler (`openshift-custom-metrics-autoscaler-operator`): `KedaController`, chart `keda.enabled` adds the Kafka-lag `ScaledObject` for notification-service (same trigger as `k8s/keda/consumer-scaledobject.yaml`) | replicas 0 -> N on an order burst, back to 0 after cooldown |
| Observability | Red Hat build of OpenTelemetry operator: `Instrumentation` CR (Java agent injected by annotation, so no pom or image change, matching the minikube/compose agent approach); backend `grafana/otel-lgtm:0.8.1` (the compose image) with a Route for Grafana | one trace in Tempo spanning order-service and inventory-service; Grafana Route 200 |
| AI services | `ollama/ollama:0.35.1` Deployment + PVC, model `qwen2.5:3b` pulled by a Job; ai-mcp-service and ai-rules-service built by build-images.sh and deployed by the chart (`ai.enabled`) | the compose demos' checks: classify, triage, MCP tool list/call |
| Native | `quarkus.native.sources-only=true` on the host (no native-image locally), then an in-cluster Docker-strategy binary build: `ubi10-quarkus-mandrel-builder-image` runs native-image, runtime on `ubi10-quarkus-micro-image`; order-service only | native pod Ready, startup time and RSS vs JVM, same GraphQL/choreography checks |
| GitOps | OpenShift GitOps operator; an Argo CD `Application` for `openshift/helm/datamesh` on main; namespace label `argocd.argoproj.io/managed-by` | Application Synced/Healthy; a values change via git rolls the release |

Each item gets its own script under `openshift/platform/` and a chart flag defaulting to false, so the core path is unchanged.

## Waves
0. Probes on CRC: packagemanifests (servicemeshoperator3, kiali-ossm, openshift-custom-metrics-autoscaler-operator, opentelemetry-product, openshift-gitops-operator) and their pinned CSVs; image imports (otel-lgtm 0.8.1, ollama 0.35.1, ubi10 mandrel builder, ubi10 micro image); otel-lgtm and ollama under restricted-v2 or not.
1. Mesh, then autoscaling, then observability, then AI, then native, then GitOps; each scripted, live-verified, committed.
2. Evidence extended; teardown extended and verified to return CRC to clean.
3. Chapter 22 sections, diagram update, deck A7 slides, DRQ entries, PR.

## Status (resume here)
- 2026-10-09: all six items scripted under `openshift/platform/` and live-verified individually on CRC (12 vCPU / 32 GiB):
  - mesh: STRICT enforced (plaintext reset), canary 91/9 and 94/6 of 100 in two runs, Kiali MTLS_ENABLED + graph with 10-11 workloads (Prometheus = otel-lgtm scraping :15020);
  - keda: 0 -> 1 -> 0 (FQDN bootstrap fix);
  - tracing: one trace gateway -> order (REST) -> inventory (gRPC), Grafana Route 200;
  - AI: classify x3, triage x6 (Camel + Flow), MCP list/call;
  - native: in-cluster Mandrel build ~2.5 min, 0.075-0.077 s / 29-31 MiB vs JVM 8-12.7 s / 200-325 MiB across runs (Avro allow-list as native build arg);
  - GitOps: Synced/Healthy, self-heal 2-3 s, password preserved.
  - `capture-evidence.sh` runs all platform sections (`platform/evidence.sh`); full pass in one capture.
  - Teardown: removes everything; fix added for the GitOps default instance (DISABLE_DEFAULT_ARGOCD_INSTANCE) after a stuck finalizer in the first run.
- Full clean cycle done: teardown 213s, install-infra 50s, build-images 179s, deploy 33s, install-platform 837s, capture-evidence 418s (all core + platform checks, scrub clean), teardown 266s with "CRC is clean" and crc stop. Final numbers (in the chapter, deck, diagram): canary 91/9, Kiali 10 workloads, KEDA 0->1 in 16s and back to 0 at 181s, native 0.077s/29MiB vs JVM 7.97s/200MiB, self-heal 2s.
- Next: validate and open the PR.
