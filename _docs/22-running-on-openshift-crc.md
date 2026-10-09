---
title: "Appendix: running on OpenShift Local (CRC)"
order: 22
part: Appendices
description: "The seven Quarkus services, Kafka, Postgres and Apicurio on OpenShift Local: images built inside the cluster with quarkus-openshift, AMQ Streams from OperatorHub, restricted-v2 pods, edge-TLS Routes, and a teardown that leaves the cluster clean."
duration: 40 minutes
marker: "22"
---

[Chapter 2]({{ '/docs/02-kubernetes-substrate/' | relative_url }}) put the
mesh on minikube: Docker Engine, containerd, NodePorts published on
`127.0.0.1`, and images loaded straight into the node. That is a real
Kubernetes deployment, but OpenShift is not plain Kubernetes. It refuses a
pod that asks for a fixed UID, it exposes services through Routes rather
than NodePorts, it ships its own image registry and build system, and it
installs operators through OperatorHub. A chart that runs on OpenShift has
to be built around those four things.

This appendix runs the core of the mesh on **OpenShift Local (CRC)**, a
single-node OpenShift 4.22 cluster in a local VM. The core is the seven
Quarkus services (order, inventory, payment, shipping, notification,
review and the GraphQL gateway) plus Kafka, Postgres and Apicurio. It is
optional: nothing else in the tutorial depends on it, and it is the Red Hat
counterpart to the minikube path rather than a replacement for it.

Everything lives under [`openshift/`](https://github.com/patterncatalyst/datamesh-reference-arch-quarkus/tree/main/openshift):
five scripts, two infra manifests and one Helm chart. The decisions behind
them are DRQ-018 to DRQ-022 in `_plans/decisions.md`.

![The datamesh project on OpenShift Local: seven services, Kafka, Postgres and Apicurio under restricted-v2, with two edge-TLS Routes]({{ '/assets/diagrams/22-crc-openshift-topology.svg' | relative_url }})

## Scope

| In this appendix | Not in this appendix |
|---|---|
| The 7 services, built in the cluster | LGTM observability (Grafana, Loki, Tempo, Mimir) |
| Kafka via the AMQ Streams operator | Istio (OpenShift Service Mesh 3) and KEDA (Custom Metrics Autoscaler) |
| Postgres 16 and Apicurio 3.2.4 | The AI services (Ollama, MCP, rules triage) |
| Routes, health, GraphQL, the Kafka choreography | A native build |

The mesh and autoscaling operators are available in OperatorHub on CRC 4.22
(`servicemeshoperator3` and `openshift-custom-metrics-autoscaler-operator`
were both present when this appendix was written), but they are not wired
up here.

## Prerequisites

Supported hosts are Fedora or RHEL, on bare metal or in a VM with nested
virtualisation. You need:

- **OpenShift Local 2.64** (`crc`) and a pull secret from a free Red Hat
  Developer account. The pull secret lets the cluster pull from
  `registry.redhat.io`, which the Postgres image needs.
- **`oc`**, which `crc` ships: `eval "$(crc oc-env)"` puts it on `PATH`.
- **`helm`**, **`jq`**, and **Maven 3.9 with JDK 25**, the same toolchain the
  rest of the tutorial uses.

You do not need a container engine. The images are built inside the
cluster.

Size the VM before its first start. This appendix was verified with 6 vCPUs,
20 GiB and an 80 GB disk:

```bash
crc config set cpus 6
crc config set memory 20480
crc config set disk-size 80
crc setup
crc start --pull-secret-file ~/pull-secret.txt
eval "$(crc oc-env)"
```

Run one cluster at a time: stop the minikube profile first
(`minikube stop -p datamesh`). Two clusters on one host compete for memory.

### No password in any script

`crc start` prints the `kubeadmin` password. You do not need it. `crc start`
also writes a `crc-admin` context into your kubeconfig, and every script in
`openshift/` switches to that context through `require_crc` in `openshift/lib.sh`:

```bash
oc config use-context "$OCP_CONTEXT" >/dev/null 2>&1 \
    || fail "kubeconfig context $OCP_CONTEXT not found (crc start writes it)"
api="$(oc whoami --show-server 2>/dev/null)" || fail "cannot reach the OpenShift API"
[[ "$api" == *api.crc.testing* ]] || fail "context $OCP_CONTEXT points at $api, not OpenShift Local"
```

The last check makes the scripts refuse any cluster other than OpenShift
Local, so a stale context cannot point them at something else.

## What changes on OpenShift

| | minikube (Chapter 2) | OpenShift Local |
|---|---|---|
| Images | `docker build`, then `minikube image load` | `quarkus-openshift` binary S2I build in the cluster |
| Base image | `ubi10/openjdk-25` + `-runtime`, multi-stage Containerfile | `ubi10/openjdk-25:1.24-15` S2I builder |
| Host access | NodePorts published on `127.0.0.1` | Edge-TLS Routes on `*.apps-crc.testing` |
| Kafka | Strimzi 0.51.0 via Helm | AMQ Streams 3.2.1 via OperatorHub |
| Postgres | CloudNativePG, PostgreSQL 18.6 | StatefulSet, `rhel10/postgresql-16` |
| Pod identity | `runAsUser: 185` | `restricted-v2` assigns a UID from the namespace range |

The env contract does not change. The chart's ConfigMap carries the same
keys as `k8s/base/config.yaml` (`KAFKA_BOOTSTRAP_SERVERS`,
`APICURIO_REGISTRY_URL`, `JDBC_URL`, `INVENTORY_GRPC_HOST`/`PORT`), and the
Service and Secret names match minikube's (`datamesh-kafka-bootstrap`,
`datamesh-postgres-rw`, `datamesh-postgres-app`). The services' `%prod`
configuration works as it is, and no `application.properties` file changes.

### restricted-v2 picks the UID

The minikube manifests pin `runAsUser: 185`, the UID the UBI OpenJDK images
use. On OpenShift the default SCC, `restricted-v2`, rejects a pod that asks
for a UID outside the namespace's range. The chart therefore sets no
`runAsUser` at all, only what restricted-v2 requires:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

On the verified run every pod, including Kafka and Postgres, ran under
`restricted-v2` with UID `1000700000`, the first UID in that project's range
`1000700000/10000`. Every image used here tolerates an arbitrary UID: the UBI
OpenJDK image, the Red Hat Postgres image and Apicurio.

### Routes instead of NodePorts

The chart creates two Routes, both edge-terminated with HTTP redirected to
HTTPS:

| Route | Host |
|---|---|
| `graphql-gateway` | `graphql-gateway-datamesh.apps-crc.testing` |
| `apicurio` | `apicurio-datamesh.apps-crc.testing` |

`crc setup` makes `*.apps-crc.testing` resolve on the host. The router's
certificate is signed by the cluster's own ingress CA, so the evidence script
fetches that CA and passes it to curl rather than turning verification off:

```bash
oc get configmap default-ingress-cert -n openshift-config-managed \
    -o jsonpath='{.data.ca-bundle\.crt}' > "$CA"
curl --cacert "$CA" "https://graphql-gateway-datamesh.apps-crc.testing/q/health/ready"
```

The other services have no Route. The verification steps that need them
(seeding stock, creating an order) run `curl` inside the service's own pod
with `oc exec`; the UBI OpenJDK image includes `curl`.

## Building the images inside the cluster

![Maven packages on the host; a binary S2I build on ubi10/openjdk-25 runs in the cluster and pushes an ImageStream tag the Deployment pulls]({{ '/assets/diagrams/22-crc-image-build.svg' | relative_url }})

Each service pom has an `openshift` profile that adds one extension:

```xml
<profile>
  <id>openshift</id>
  <dependencies>
    <dependency>
      <groupId>io.quarkus</groupId>
      <artifactId>quarkus-openshift</artifactId>
    </dependency>
  </dependencies>
</profile>
```

The profile only takes effect with `-Popenshift`, so `mvn verify` and the
minikube images are unchanged. `openshift/build-images.sh` builds all seven
in one Maven reactor run:

```bash
mvn -B -q -pl "$modules" -am package -DskipTests -Popenshift \
    -Dquarkus.container-image.build=true \
    -Dquarkus.container-image.tag=v1 \
    -Dquarkus.openshift.version=v1 \
    -Dquarkus.openshift.base-jvm-image=registry.access.redhat.com/ubi10/openjdk-25:1.24-15 \
    -Dquarkus.kubernetes-client.namespace=datamesh \
    -Dquarkus.kubernetes.deploy=false
```

For each service, Maven builds the fast-jar (`target/quarkus-app`) on the
host. The extension then creates a BuildConfig (Source strategy, binary
input) and two ImageStreams, and uploads the fast-jar. OpenShift runs the
S2I assemble script of `ubi10/openjdk-25` on it inside the cluster and pushes
the result to the internal registry as `<service>:v1`.
`quarkus.kubernetes.deploy=false` limits the extension to building and
pushing; the Helm chart owns the Deployments.

The cluster never runs Maven and never pulls from Maven Central. The host
never runs a container engine. Each in-cluster build took 14 to 20 seconds,
and the whole reactor took about three minutes.

Three settings matter, and the run below found each the hard way:

- **`quarkus-openshift`, not `quarkus-container-image-openshift`.** The
  container-image extension alone builds nothing. It logs
  `No OpenShift manifests were generated so no OpenShift build process will be taking place`,
  because the BuildConfig and ImageStreams come from the manifest generator
  in `quarkus-openshift`.
- **`quarkus.openshift.version` sets the tag.** With only
  `quarkus.container-image.tag=v1`, the BuildConfig's output stayed at
  `order-service:1.0.0-SNAPSHOT`, the project version. The OpenShift manifest
  generator takes the output tag from `quarkus.openshift.version`.
- **The base image.** The extension's default is `ubi9/openjdk-25:1.24`. This
  project uses UBI 10 everywhere, so the profile overrides it with a pinned
  tag that carries the S2I labels (`io.openshift.s2i.scripts-url=image:///usr/libexec/s2i`).

### The S2I image starts the app differently

The minikube image's Containerfile ends with
`ENTRYPOINT ["java", "-jar", "quarkus-run.jar"]` and sets
`JAVA_TOOL_OPTIONS` itself. The S2I image instead starts the app with
`run-java.sh`, which never reads that Containerfile. The chart therefore
supplies two things the Containerfile used to:

- **The Avro allow-list.** Avro 1.12 refuses to deserialise classes outside
  `org.apache.avro.SERIALIZABLE_PACKAGES` ([Chapter 17]({{ '/docs/17-gotchas/' | relative_url }})),
  so each Kafka service gets its packages as `JAVA_TOOL_OPTIONS`
  (`avroPackages` in `values.yaml`).
- **Heap sizing.** `run-java.sh` sets `-XX:MaxRAMPercentage` from
  `JAVA_MAX_MEM_RATIO`, and the default is 80. At 80% of a 640 MiB limit,
  metaspace, threads and Netty buffers have little room left, so the chart
  sets 50. The variable is `JAVA_MAX_MEM_RATIO`; the image ignores
  `JAVA_MAX_RAM_RATIO`.

## Kafka from OperatorHub

`openshift/install-infra.sh` installs AMQ Streams, Red Hat's build of
Strimzi, through OLM, then creates the Kafka cluster.

The Subscription pins one version. With `installPlanApproval: Manual` and a
`startingCSV`, OLM proposes exactly that CSV, and the script approves only
the InstallPlan that names it:

```yaml
spec:
  name: amq-streams
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  channel: amq-streams-3.2.x
  startingCSV: amqstreams.v3.2.1-14
  installPlanApproval: Manual
```

It goes into `openshift-operators`, where the default `global-operators`
OperatorGroup makes it watch every namespace.

One timing quirk: just after `crc start`, the `redhat-operators` catalog
reports `READY` while serving no packages for about a minute. The script
therefore waits for the `amq-streams` packagemanifest itself, not for the
catalog's status.

The Kafka CR keeps the minikube shape: a cluster named `datamesh`, one KRaft
node with both roles, and a plain listener on 9092. That keeps the bootstrap
address the services already use. It differs from minikube in three ways:

- it uses the `kafka.strimzi.io/v1` API, because AMQ Streams 3.2 warns that
  v1beta2 is deprecated;
- it has no entity operator, so topics auto-create on first use, as in the
  compose stack;
- it sets explicit resources to fit the 20 GiB VM.

## Postgres, Apicurio and the chart

`openshift/helm/datamesh` uses one data-driven template for all seven
services. `values.yaml` has a `services:` map, and each entry declares only
what is specific to that service:

```yaml
services:
  order-service:
    db: true
    avroPackages: capstone.order.v1
    resources: {requests: {cpu: 150m, memory: 320Mi}, limits: {cpu: 750m, memory: 640Mi}}
  inventory-service:
    db: true
    grpcPort: 9000
  review-service:
    db: true
    env:
      QUARKUS_OIDC_TENANT_ENABLED: "false"
  graphql-gateway:
    env:
      ORDER_SERVICE_URL: http://order-service:8080
```

The full map also sets resources for every service. In the template:

- `db: true` mounts the Postgres credentials and adds a `wait-for-postgres`
  init container;
- `grpcPort` adds a container port and a Service port;
- `avroPackages` becomes `JAVA_TOOL_OPTIONS`.

Images come from the internal registry
(`image-registry.openshift-image-registry.svc:5000/datamesh/<service>:v1`).

**Postgres** is a StatefulSet on
`registry.redhat.io/rhel10/postgresql-16:10.2-1791491499`. That image is
designed for arbitrary UIDs, and its probes call the image's own
`/usr/libexec/check-container`. Minikube runs PostgreSQL 18.6 under
CloudNativePG; nothing in the services depends on 18-only features. The
password is generated by Helm on the first install and kept on upgrades
through `lookup`. It never appears in `values.yaml`, a file or the evidence.

**Apicurio** is `quay.io/apicurio/apicurio-registry:3.2.4` with in-memory
storage, the same version as minikube.

**review-service** needs one change. It has `quarkus-oidc` on its classpath
for the authenticated `DELETE /reviews/{id}` demo, and Dev Services supplies
Keycloak in dev and test. In the prod build no OIDC provider exists, and
startup fails:

```
'quarkus.oidc.auth-server-url' property must be configured
```

The chart sets `QUARKUS_OIDC_TENANT_ENABLED=false`. The service starts,
`DELETE /reviews/{id}` answers 401, and every other endpoint works (DRQ-022).

## Running it

```bash
./openshift/install-infra.sh      # project, AMQ Streams, Kafka            ~50 s
./openshift/build-images.sh       # 7 in-cluster builds -> <service>:v1    ~3 min
./openshift/deploy.sh             # helm upgrade --install, wait for rollout ~35 s
./openshift/capture-evidence.sh   # 7 checks -> openshift/evidence/<date>/  ~15 s
```

`deploy.sh` checks that Kafka is Ready and all seven ImageStream tags exist.
It then runs `helm upgrade --install` and waits for `oc rollout status` on
every Deployment. It waits on rollout status rather than
`condition=Available`, because on an upgrade the old ReplicaSet stays
Available until the new pods are Ready.

## Verifying it

`capture-evidence.sh` fails on the first check that misses and writes what
it saw to `openshift/evidence/<date>/`:

1. **Builds.** Seven Complete builds, seven ImageStream tags `v1`.
2. **Pods.** All Ready, all `restricted-v2`, and all UIDs from the namespace range.
3. **Gateway Route.** `/q/health/ready` answers 200 over edge TLS.
4. **GraphQL.** One query returns the order from order-service (REST) and
   its stock from inventory-service (gRPC):

   ```json
   {"order":{"id":"9cded459-…","customerId":"crc-evidence","itemSku":"CRC-WIDGET-7028",
             "quantity":1,"status":"PLACED",
             "stock":{"sku":"CRC-WIDGET-7028","quantityOnHand":12,"available":true}}}
   ```

5. **Kafka choreography.** For the same order ID, payment-service logs the
   capture, a row appears in the `shipment` table, and notification-service
   lists the `order.placed` notification. No service calls another; each one
   reacts to the event before it ([Chapter 13]({{ '/docs/13-orchestration-styles/' | relative_url }})).
6. **Apicurio Route.** Three artifacts are registered: `order.placed-value`,
   `payment.captured-value` and `shipment.dispatched-value`.
7. **Secret scrub.** The script reads the database password into a shell
   variable without printing it. It then fails if that password, an
   OpenShift token (`sha256~…`) or a private key appears anywhere in the
   evidence.

One detail in the shipment row can look like a bug. Its SKU and quantity
differ from the order's, because `PaymentCaptured` carries no line items, so
shipping-service derives them deterministically from the order ID
(`ShipmentProcessor`). It behaves the same way on compose and minikube.

## What broke on the live run

| Symptom | Cause | Fix |
|---|---|---|
| Maven succeeded in 13 s and no image appeared | `quarkus-container-image-openshift` alone generates no BuildConfig | Use `quarkus-openshift` |
| ImageStream tag `1.0.0-SNAPSHOT` instead of `v1` | The output tag follows `quarkus.openshift.version` | Set `-Dquarkus.openshift.version=v1` |
| Heap at 80% of the limit | The image reads `JAVA_MAX_MEM_RATIO`, not `JAVA_MAX_RAM_RATIO` | Rename; set 50 |
| Five services restarted once or twice on install | Hibernate connects at boot, before Postgres accepts connections | A `wait-for-postgres` init container (bash `/dev/tcp`, same image, nothing extra pulled) |
| ConfigMap change did not reach running pods | Env from a ConfigMap is read at pod start | A `checksum/config` annotation on the pod template |
| `deploy.sh` reported success while new pods were starting | `condition=Available` was satisfied by the old ReplicaSet | `oc rollout status` per Deployment |
| Deprecation warnings on apply | AMQ Streams 3.2 deprecates `kafka.strimzi.io/v1beta2` | Move the CRs to `kafka.strimzi.io/v1` |
| review-service would not start | No OIDC provider in prod | `QUARKUS_OIDC_TENANT_ENABLED=false` |

After these fixes, a fresh install from an empty cluster comes up with zero
restarts.

## Tearing it down

This CRC instance is meant for this workshop alone, so teardown removes
everything the other scripts added, not just the Helm release:

```bash
./openshift/teardown.sh                  # clean up, then crc stop
./openshift/teardown.sh --keep-running   # clean up, leave CRC running
```

In order, it does the following:

1. uninstalls the Helm release;
2. deletes the Kafka cluster while the operator can still process its
   finalizers;
3. deletes the `datamesh` project, which takes the builds, ImageStreams and
   PVCs with it;
4. removes the AMQ Streams Subscription, CSV and InstallPlans;
5. deletes the Strimzi CRDs;
6. reports any Subscription or namespace that is still left;
7. stops CRC, unless `--keep-running` was given.

The order matters. If the project is deleted first, any KafkaTopic keeps a
`strimzi.io/topic-operator` finalizer that nothing is left to remove, and
the namespace hangs in `Terminating`. This happened while this appendix was
prepared, on a namespace left behind by another workshop.

## The whole cycle

From an empty CRC, the full cycle ran without intervention:

| Step | Time |
|---|---|
| `teardown.sh --keep-running` (from a running deployment) | 46 s |
| `install-infra.sh` | 50 s |
| `build-images.sh` | 182 s |
| `deploy.sh` | 33 s |
| `capture-evidence.sh` | 13 s |

---

*Verification status: <span class="status status--verified">verified</span>. On 2026-10-09 the full cycle above ran on OpenShift Local 2.64.0 (OpenShift 4.22.14, Kubernetes 1.35.6) with 6 vCPUs and 20 GiB: AMQ Streams `amqstreams.v3.2.1-14`, Kafka 4.2.0, seven in-cluster builds on `ubi10/openjdk-25:1.24-15`, all pods Ready under `restricted-v2` with zero restarts, the gateway Route healthy, GraphQL stitching order and stock, the order to payment to shipment choreography for one order ID, and three Apicurio artifacts. The secret scrub passed. Evidence is in `openshift/evidence/2026-10-09/`. Teardown returned the cluster to clean and stopped it. Single run; the service mesh, autoscaling, observability and native tiers are not covered.*
