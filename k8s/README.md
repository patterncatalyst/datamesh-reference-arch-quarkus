# k8s — kustomize app manifests

Application manifests (order-service, notification-service, graphql-gateway)
for a local single-node Kubernetes cluster (`minikube`). They run on the
platform that `scripts/bootstrap.sh` brings up: Istio, KEDA, Strimzi/Kafka,
CloudNativePG/Postgres and Apicurio in the `datamesh` namespace, and LGTM in
`observability`.

The KEDA `ScaledObject`s (Kafka lag on notification-service, HTTP on
graphql-gateway) live in `k8s/keda`. This directory ships the
Deployments and Services they target.

## Layout

```
k8s/
  base/
    config.yaml                # ConfigMap: shared %prod env contract
    order-service.yaml         # Deployment + Service (producer)
    notification-service.yaml  # Deployment + Service (Kafka-lag consumer, KEDA target)
    graphql-gateway.yaml       # Deployment + Service (HTTP scale target)
    kustomization.yaml
  overlays/
    minikube/
      kustomization.yaml       # ../../base + image tags, no registry
```

## Build images into the cluster's Docker daemon (no registry)

Images are built directly into the cluster's Docker daemon; this stack has
no image registry. From the repo root, with the `minikube` profile
(`datamesh`) running:

```bash
eval $(minikube docker-env -p datamesh)

docker build -f examples/order-service/src/main/docker/Containerfile.multistage \
  -t datamesh/order-service:latest .

docker build -f examples/notification-service/src/main/docker/Containerfile.multistage \
  -t datamesh/notification-service:latest .

docker build -f examples/graphql-gateway/src/main/docker/Containerfile.multistage \
  -t datamesh/graphql-gateway:latest .
```

The build context is the **repo root** for all three, not `examples/<svc>`:
each Containerfile's builder stage copies the whole `examples/` Maven
reactor so `domain-model` and `contracts` resolve as reactor modules
(see the comment block at the top of each `Containerfile.multistage`).

`eval $(minikube docker-env)` points the shell's `docker` CLI at the
cluster node's Docker daemon, so the image lands where the kubelet looks.
Every Deployment in `k8s/base/*.yaml` sets `imagePullPolicy: IfNotPresent`
and the image names (`datamesh/order-service`, etc.) carry no registry host,
so as long as the exact `name:tag` exists in that daemon the kubelet never
pulls externally. The update loop is to rebuild with the same tag (`latest`)
and run `kubectl rollout restart deployment/<svc> -n datamesh`.

## Apply

```bash
kubectl apply -k k8s/overlays/minikube
```

Rendering was verified with `kubectl kustomize k8s/overlays/minikube`
(kustomize v5.7.1, bundled in kubectl v1.35.3). The check is client-side
templating and needs no cluster.

## Env contract

All three Deployments pull the shared, non-secret env vars from the
`datamesh-app-config` ConfigMap (`k8s/base/config.yaml`) via `envFrom`. The
values are the in-cluster service DNS names created by the platform setup
scripts:

| Env var | Value | Source script |
|---|---|---|
| `KAFKA_BOOTSTRAP_SERVERS` | `datamesh-kafka-bootstrap.datamesh.svc.cluster.local:9092` | `scripts/setup-kafka-operator.sh` (Kafka CR name `datamesh` → Strimzi Service `<name>-kafka-bootstrap`) |
| `APICURIO_REGISTRY_URL` | `http://apicurio.datamesh.svc.cluster.local:8080/apis/registry/v3` | `scripts/setup-apicurio.sh` (Service `apicurio`, v3 API) |
| `JDBC_URL` / `QUARKUS_DATASOURCE_JDBC_URL` | `jdbc:postgresql://datamesh-postgres-rw.datamesh.svc.cluster.local:5432/datamesh` | `scripts/setup-postgres-operator.sh` (Cluster CR `datamesh-postgres` → CNPG Service `<name>-rw`, db `datamesh`) |
| `JAVA_OPTS_APPEND` | `-Duser.timezone=UTC` | UTC convention (the postgres timezone fix) |
| `QUARKUS_PROFILE` | `prod` | production profile |

`KAFKA_BOOTSTRAP_SERVERS` and `APICURIO_REGISTRY_URL` need no
`application.properties` changes; they land on Quarkus's own
`kafka.bootstrap.servers` and `apicurio.registry.url` config keys via
relaxed env-var binding. `QUARKUS_DATASOURCE_JDBC_URL` likewise needs no
properties change (it is a first-class Quarkus datasource property). `JDBC_URL`
is also set, matching the env-var name the services' `application.properties` expect, and is
wired in both `order-service`'s and `notification-service`'s
`application.properties` (`%prod.quarkus.datasource.jdbc.url=${JDBC_URL:...}`,
`order-service` line 51 / `notification-service` line 36), so the ConfigMap
value takes effect against the `%prod` datasource.

**DB username/password** come from the **CloudNativePG-managed Secret**
`datamesh-postgres-app` (auto-created in the `datamesh` namespace by the
`Cluster` CR in `scripts/setup-postgres-operator.sh`'s `bootstrap.initdb`,
keys `username`/`password`/... ) — referenced directly via `secretKeyRef` in
each Deployment. `k8s/base/config.yaml` does **not** define a
second Secret with a copy of those credentials: CNPG owns and rotates that
Secret, and a hand-authored duplicate would need a guessed password
or create two sources of truth for the same identity. See the
comment block at the top of `config.yaml`.

## Namespace

Everything in `k8s/base` targets `datamesh` — both via explicit
`metadata.namespace` on each resource and via `kustomization.yaml`'s
`namespace: datamesh` transformer (matches `NS="datamesh"` in
`scripts/bootstrap.sh` and the platform setup scripts).

## Mesh (Istio) decision

Istio and Kiali are installed cluster-wide, but the `datamesh` namespace
is **not** labeled for sidecar auto-injection; membership is a per-Deployment
opt-in. None of these three Deployments carry the
`sidecar.istio.io/inject: "true"` pod **label**, so none of them are in the
mesh in the base configuration. The mesh is added by the `k8s/istio` overlay.

Opt-in is a pod-template **label**, not an annotation: Istio's
sidecar-injection `MutatingWebhookConfiguration` matches pods via an
`objectSelector` (`sidecar.istio.io/inject In ["true"]`), and a webhook
`objectSelector` is evaluated against the pod's labels, never its
annotations — so in this unlabeled namespace, an annotation of the same key
silently injects nothing (confirmed on the cluster). `k8s/istio/` is
the overlay that adds that label to these three Deployments —
`kubectl apply -k k8s/istio` — without editing `k8s/base` itself (Istio 1.29+ injects as a native `initContainer`, so mesh-membership checks
must look at `.spec.initContainers`, not `.spec.containers` — see the
`lgtm-minikube-stack` skill's `known-issues.md`). That same overlay also
ships the namespace-wide `PeerAuthentication` (STRICT mTLS) and the
`order-service` v1/v2 canary (`DestinationRule`/`VirtualService` +
`order-service-v2` Deployment) — see `k8s/istio/README.md`.

## Replicas and KEDA

All three Deployments ship with `replicas: 1` in base, including
notification-service. Without KEDA applied, `replicas: 0` would leave a
dead consumer. Once the `ScaledObject` (Kafka-lag trigger,
`minReplicaCount: 0`) is applied, the HPA it creates takes over
notification-service's replica count and this field becomes advisory.

## Health probes

`order-service` and `notification-service` both depend on
`quarkus-smallrye-health` (confirmed in their `pom.xml`s), so they get
`startupProbe` (`/q/health/started`), `readinessProbe`
(`/q/health/ready`), and `livenessProbe` (`/q/health/live`) checks.

`graphql-gateway` does **not** depend on `quarkus-smallrye-health` (checked
`examples/graphql-gateway/pom.xml`: only `quarkus-smallrye-graphql`,
`quarkus-rest-client[-jackson]`, `quarkus-grpc`, `quarkus-arc`,
`domain-model`, `contracts`) — `/q/health/*` would 404 there, so its probes
use `tcpSocket` on the HTTP port instead. This is a weaker check: it proves
the HTTP listener is up, not that GraphQL execution works. The fix is to
add `quarkus-smallrye-health` to `examples/graphql-gateway/pom.xml` and
switch to `httpGet` probes on `/q/health/*`; that is a `pom.xml` change
outside this manifests directory.

## Resource sizing (single-node cluster)

| Service | requests | limits |
|---|---|---|
| order-service | 150m CPU / 320Mi | 750m CPU / 640Mi |
| notification-service | 100m CPU / 256Mi | 500m CPU / 512Mi |
| graphql-gateway | 100m CPU / 256Mi | 500m CPU / 512Mi |

Sized for JVM-mode Quarkus fast-jars on a single-node dev cluster, not for
production capacity planning.
