# openshift/ — datamesh on OpenShift Local (CRC)

The optional Red Hat path for this workshop. The main path is minikube on
Docker Engine (`scripts/bootstrap.sh`); this directory runs the same 7 Quarkus
services on OpenShift Local instead. The walkthrough is the appendix chapter
`_docs/22-running-on-openshift-crc.md`.

Supported hosts: Fedora or RHEL, bare metal or VM. Needs `crc` (with a pull
secret), `oc`, `helm`, `mvn` with JDK 25, and `jq`. No container engine is
used: images are built inside the cluster.

## Run it

Stop minikube first. Run one cluster at a time.

```bash
crc start                         # writes the crc-admin kubeconfig context
eval "$(crc oc-env)"

./openshift/install-infra.sh      # project, AMQ Streams operator, Kafka
./openshift/build-images.sh       # 7 binary S2I builds -> ImageStream tags v1
./openshift/deploy.sh             # Helm chart: services, Postgres, Apicurio, Routes
./openshift/platform/install-platform.sh   # optional: the platform tier (below)
./openshift/capture-evidence.sh   # checks + evidence/<date>/, with a secret scrub
./openshift/teardown.sh           # remove everything above, then crc stop
```

## Platform tier (optional)

Needs CRC at 12 vCPUs and 32 GiB (`crc config set cpus 12`, `crc config set memory 32768`).
Each step is its own script; `install-platform.sh` runs them in this order.

| Script | Adds | Chart flag |
|---|---|---|
| `platform/install-mesh.sh [--canary]` | OSSM 3 (Istio v1.30.5), Kiali, STRICT mTLS, order-service canary 90/10 | `mesh.enabled`, `mesh.canary.enabled` |
| `platform/install-keda.sh` | Custom Metrics Autoscaler; notification-service 0 -> N on Kafka lag | `keda.enabled` |
| `platform/install-observability.sh` | OpenTelemetry operator injects the Java agent; `grafana/otel-lgtm:0.36.0` + Grafana Route | `observability.enabled` |
| `platform/install-ai.sh` | Ollama 0.40.2 + qwen2.5:3b, ai-mcp-service, ai-rules-service | `ai.enabled` |
| `platform/build-native.sh`, then `deploy.sh --set native.enabled=true` | order-service compiled to native inside the cluster | `native.enabled` |
| `platform/install-gitops.sh [revision]` | OpenShift GitOps; an Argo CD Application owns the release | (Application) |

Operators are pinned in `platform/subscriptions/` (Manual approval, `startingCSV`).
The CSV pins resolve only against a running cluster's catalog, so they were not
moved with the 2026-10-09 image bumps (DRQ-029); re-check them at the next CRC run
(`oc get packagemanifest <name> -n openshift-marketplace`). The Istio CR stays at
v1.30.5, the newest version OSSM 3.4.3 offers, and Kafka stays at 4.2.0, the
newest AMQ Streams 3.2 supports.
`capture-evidence.sh` checks whichever of these are installed.

## What is here

| Path | Purpose |
|---|---|
| `lib.sh` | Shared helpers; pins the `crc-admin` context and refuses any other cluster. |
| `infra/amq-streams-subscription.yaml` | AMQ Streams `amqstreams.v3.2.1-14`, Manual approval. |
| `infra/kafka.yaml` | Kafka CR `datamesh` (`kafka.strimzi.io/v1`), Kafka 4.2.0, one KRaft node. |
| `helm/datamesh/` | Chart: 7 Deployments from one `services:` map, PostgreSQL 18, Apicurio 3.3.3, two Routes. |
| `platform/` | The platform tier: one script per feature, pinned subscriptions, `evidence.sh`. |
| `evidence/` | Output of `capture-evidence.sh`. No passwords or tokens; the script checks. |

## Differences from minikube

| | minikube | OpenShift Local |
|---|---|---|
| Images | `docker build` + `minikube image load` | `quarkus-openshift` binary S2I on `ubi10/openjdk-25:1.24-15` |
| Host access | NodePorts published on 127.0.0.1 | Edge-TLS Routes on `*.apps-crc.testing` |
| Kafka | Strimzi 1.2.0 via Helm, Kafka 4.3.1 | AMQ Streams 3.2.1 via OperatorHub, Kafka 4.2.0 |
| Postgres | CloudNativePG, PostgreSQL 18.6 | StatefulSet, `rhel10/postgresql-18` |
| Pod security | `runAsUser: 185` | `restricted-v2`, UID from the namespace range |
| review-service | not deployed | OIDC tenant disabled; `DELETE /reviews/{id}` answers 401 |

The decisions are DRQ-018 to DRQ-028 in `_plans/decisions.md`.
