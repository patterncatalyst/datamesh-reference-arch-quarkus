# k8s — kustomize app manifests

Step 9b of the minikube substrate. This directory holds the **application** manifests (order-service,
notification-service, graphql-gateway) that run on top of the substrate
step 9a's `scripts/bootstrap.sh` brings up (Istio, KEDA, Strimzi/Kafka,
CloudNativePG/Postgres, Apicurio — all in the `datamesh` namespace, except
LGTM which lives in `observability`).

KEDA `ScaledObject`s (Kafka-lag on notification-service, HTTP on
graphql-gateway) are step 9c's job, not this one — this step only ships the
Deployments/Services they will target.

## Layout

```
k8s/
  base/
    config.yaml                # ConfigMap: shared %prod env contract
    order-service.yaml         # Deployment + Service (producer)
    notification-service.yaml  # Deployment + Service (Kafka-lag consumer, KEDA target in 9c)
    graphql-gateway.yaml       # Deployment + Service (HTTP scale target in 9c)
    kustomization.yaml
  overlays/
    minikube/
      kustomization.yaml       # ../../base + image tags, no registry
```

## Build images into minikube's own Docker daemon (no registry)

Images are built locally straight into minikube's Docker daemon —
there is no image registry in this stack. From the repo root, with the
minikube profile (`datamesh`) already running:

```bash
eval $(minikube docker-env -p datamesh)

docker build -f examples/order-service/src/main/docker/Containerfile.multistage \
  -t datamesh/order-service:latest .

docker build -f examples/notification-service/src/main/docker/Containerfile.multistage \
  -t datamesh/notification-service:latest .

docker build -f examples/graphql-gateway/src/main/docker/Containerfile.multistage \
  -t datamesh/graphql-gateway:latest .
```

Build context is the **repo root** for all three (not `examples/<svc>`) —
each Containerfile's builder stage copies the whole `examples/` Maven
reactor so `domain-model` and `contracts` resolve as reactor dependencies
(see the comment block at the top of each `Containerfile.multistage`).

Because `eval $(minikube docker-env)` points your shell's `docker` CLI at
the VM's own Docker daemon, the image lands directly in the place the
kubelet looks. Every Deployment in `k8s/base/*.yaml` sets
`imagePullPolicy: IfNotPresent`, and the image names
(`datamesh/order-service`, etc.) carry no registry host — so as long as the
exact `name:tag` already exists in that daemon, the kubelet never attempts
an external pull. Rebuilding with the same tag (`latest`) and then doing
`kubectl rollout restart deployment/<svc> -n datamesh` is the update loop
until 9c/9d wire up anything fancier.

## Apply

```bash
kubectl apply -k k8s/overlays/minikube
```

Rendering was verified with `kubectl kustomize k8s/overlays/minikube`
(kustomize v5.7.1, bundled in kubectl v1.35.3) — no cluster required for
that check, it's pure manifest templating.

## Env contract

All three Deployments pull the shared, non-secret env vars from the
`datamesh-app-config` ConfigMap (`k8s/base/config.yaml`) via `envFrom`. The
values are the **actual in-cluster service DNS names emitted by step 9a's
scripts**, not invented ones:

| Env var | Value | Source (9a script) |
|---|---|---|
| `KAFKA_BOOTSTRAP_SERVERS` | `datamesh-kafka-bootstrap.datamesh.svc.cluster.local:9092` | `scripts/setup-kafka-operator.sh` (Kafka CR name `datamesh` → Strimzi Service `<name>-kafka-bootstrap`) |
| `APICURIO_REGISTRY_URL` | `http://apicurio.datamesh.svc.cluster.local:8080/apis/registry/v3` | `scripts/setup-apicurio.sh` (Service `apicurio`, v3 API) |
| `JDBC_URL` / `QUARKUS_DATASOURCE_JDBC_URL` | `jdbc:postgresql://datamesh-postgres-rw.datamesh.svc.cluster.local:5432/datamesh` | `scripts/setup-postgres-operator.sh` (Cluster CR `datamesh-postgres` → CNPG Service `<name>-rw`, db `datamesh`) |
| `JAVA_OPTS_APPEND` | `-Duser.timezone=UTC` | UTC convention (the postgres timezone fix) |
| `QUARKUS_PROFILE` | `prod` | production profile |

`KAFKA_BOOTSTRAP_SERVERS` and `APICURIO_REGISTRY_URL` work with **zero**
`application.properties` changes — they land on Quarkus's own
`kafka.bootstrap.servers` and `apicurio.registry.url` config keys via
relaxed env-var binding. `QUARKUS_DATASOURCE_JDBC_URL` likewise needs no
properties change (it's a first-class Quarkus datasource property). `JDBC_URL`
is also set, matching the literal env-var name the services' `application.properties` expect, and is
wired in both `order-service`'s and `notification-service`'s
`application.properties` (`%prod.quarkus.datasource.jdbc.url=${JDBC_URL:...}`,
`order-service` line 51 / `notification-service` line 36), so the ConfigMap
value takes effect against the real `%prod` datasource with no further
follow-up needed.

**DB username/password** come from the **CloudNativePG-managed Secret**
`datamesh-postgres-app` (auto-created in the `datamesh` namespace by the
`Cluster` CR in `scripts/setup-postgres-operator.sh`'s `bootstrap.initdb`,
keys `username`/`password`/... ) — referenced directly via `secretKeyRef` in
each Deployment. `k8s/base/config.yaml` deliberately does **not** mint a
second Secret with a copy of those credentials: CNPG owns and rotates that
Secret, and a hand-authored duplicate would either need a guessed password
or create two conflicting sources of truth for the same identity. See the
comment block at the top of `config.yaml` for the full rationale.

## Namespace

Everything in `k8s/base` targets `datamesh` — both via explicit
`metadata.namespace` on each resource and via `kustomization.yaml`'s
`namespace: datamesh` transformer (matches `NS="datamesh"` in
`scripts/bootstrap.sh` and all three step-9a setup scripts).

## Mesh (Istio) decision

Istio + Kiali are installed cluster-wide by 9a but the `datamesh` namespace
is **not** labeled for sidecar auto-injection (9a's own design — per-
Deployment opt-in, not namespace-wide). None of these three Deployments
carry the `sidecar.istio.io/inject: "true"` pod annotation, so **none of
them are in the mesh** for this stage. This is the deliberate default per the
task brief: keep this stage simple, defer the mesh demo to a later phase. To
add a service to the mesh later, add that annotation under
`spec.template.metadata.annotations` for that Deployment (remember: Istio
1.29+ injects as a native `initContainer`, so mesh-membership checks must
look at `.spec.initContainers`, not `.spec.containers` — see the
`lgtm-minikube-stack` skill's `known-issues.md`).

## replicas vs. KEDA (9c)

All three Deployments ship with `replicas: 1` in base — including
notification-service. KEDA is not wired up yet (that's step 9c); setting
`replicas: 0` now would leave the substrate with a dead consumer until 9c
lands. Once 9c's `ScaledObject` (Kafka-lag trigger, `minReplicaCount: 0`)
is applied, the HPA it creates takes over notification-service's replica
count and this field becomes advisory.

## Health probes

`order-service` and `notification-service` both depend on
`quarkus-smallrye-health` (confirmed in their `pom.xml`s), so they get real
`startupProbe` (`/q/health/started`), `readinessProbe`
(`/q/health/ready`), and `livenessProbe` (`/q/health/live`) checks.

`graphql-gateway` does **not** depend on `quarkus-smallrye-health` (checked
`examples/graphql-gateway/pom.xml`: only `quarkus-smallrye-graphql`,
`quarkus-rest-client[-jackson]`, `quarkus-grpc`, `quarkus-arc`,
`domain-model`, `contracts`) — `/q/health/*` would 404 there, so its probes
use `tcpSocket` on the HTTP port instead. This is a weaker check (proves the
HTTP listener is up, not that GraphQL execution works) and is called out as
an unmet acceptance criterion in the handback report. Recommended follow-up:
add `quarkus-smallrye-health` to `examples/graphql-gateway/pom.xml` and
switch back to `httpGet` probes on `/q/health/*` — left undone here because
it's a Java/pom.xml change outside a manifests-only step.

## Resource sizing (single-node minikube)

| Service | requests | limits |
|---|---|---|
| order-service | 150m CPU / 320Mi | 750m CPU / 640Mi |
| notification-service | 100m CPU / 256Mi | 500m CPU / 512Mi |
| graphql-gateway | 100m CPU / 256Mi | 500m CPU / 512Mi |

Sized for JVM-mode Quarkus fast-jars on a single-node dev cluster, not for
production capacity planning.
