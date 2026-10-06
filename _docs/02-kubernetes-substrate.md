---
title: "Kubernetes as the substrate"
order: 3
part: Foundations
description: "Why Kubernetes is a natural substrate for a data mesh, how the four principles map onto namespaces, operators, and RBAC, and the Docker-built local Kubernetes substrate this build stands up."
duration: "25 min"
marker: "03"
---

The four data-mesh principles map onto Kubernetes primitives almost directly. This
chapter makes that mapping explicit, then walks the substrate this build stands up on a
local single-node Kubernetes cluster (`minikube`). Figure 2.1, the full-project diagram
for this part, shows the destination: the data mesh this build runs, domain services and
platform tier together, on the single `minikube` profile
[bootstrap.sh]({{ site.repo_blob }}/scripts/bootstrap.sh) stands up.

{% include excalidraw.html file="02-capstone-data-mesh" alt="The complete data mesh reference architecture running on a local Kubernetes cluster — domain services, the service mesh, and the self-serve platform tier underneath them" caption="Figure 2.1 — Full project example: a data mesh on Kubernetes" %}

## Why Kubernetes and the mesh align

Kubernetes was designed around multi-tenancy, declarative resources, an extensible type
system, and operators that turn operational knowledge into software. Those are exactly
the capabilities a data mesh needs — a place for each domain to own its slice, a way to
express a data product as a deployable artifact with a contract, a shared platform layer
domains consume without building it themselves, and a boundary where standards get
enforced automatically. A data mesh does not require Kubernetes, and Kubernetes does not
imply a mesh, but each principle has a natural home in primitives you already know.

## The four principles, mapped to primitives

Figure 2.2 pairs each principle with the Kubernetes primitives that implement it; the
detail below walks each pairing.

{% include excalidraw.html file="02-principles-to-pieces" alt="The four data mesh principles mapped to their corresponding Kubernetes primitives — namespaces, Deployments and CRDs, operators, and admission/mesh policy" caption="Figure 2.2 — From principles to Kubernetes pieces" %}

**Domain ownership → namespaces, ServiceAccounts, RBAC, quotas.** The unit of tenancy in
Kubernetes is the namespace, and it carries its own identities (ServiceAccounts), its own
permissions (Roles and RoleBindings), and its own resource budget (quotas). That is
the boundary a domain needs: a place it owns, with access it controls and a budget it
lives within, isolated from other domains by default. In this build every domain service
lands in the single `datamesh` namespace (a simplification for a single-node cluster; a
multi-team deployment would split it further), while the observability stack gets its own
`observability` namespace.

**Data as a product → Deployments, Services, and CRDs.** A data product is a deployable
artifact that exposes a contract — which is what a Deployment plus a Service
provides. The Deployment runs the product; the Service is its stable address. And because
Kubernetes lets you extend its own type system with Custom Resource Definitions, the
platform can offer domain-specific types — a Kafka `Topic`, a Postgres `Cluster` — that a
domain declares the same way it declares a Deployment. The data product becomes a declarable resource instead of an informal collection of scripts.

**Self-serve data platform → operators and shared cluster infrastructure.** This is
the clearest of the four mappings. An *operator* packages the knowledge of
how to run a complex stateful system — Kafka, Postgres, autoscaling, a service mesh —
into a controller that reconciles a simple declarative request into a running system. A
domain team that needs Kafka doesn't learn to operate Kafka; it asks the platform's Kafka
operator for a cluster and gets one. In this build the event backbone (Strimzi), the
database (CloudNativePG), autoscaling (KEDA), the service mesh (Istio), and the
observability stack (the LGTM stack — Loki, Grafana, Tempo, Mimir) are all shared
platform infrastructure the domains consume by declaration.

**Federated computational governance → admission control, mesh policy, CRD validation,
and the schema registry.** Governance in a mesh is supposed to be enforced by the
platform, automatically, at the boundary — not by review meetings after the fact.
Kubernetes has several boundaries where that enforcement lives: service-mesh
authorization and mutual-TLS policies that govern traffic between products, the schema
validation built into every CRD, and — one layer up the stack, running *on* this
substrate — the Apicurio schema registry rejecting an incompatible Avro contract change
at publish time. The rules become code that runs at the edge of the system, which is
what "computational governance" means.

## The substrate this build stands up

Everything above is the general case. Concretely, this build's substrate is a single
`minikube` profile, brought up tier by tier by
[bootstrap.sh]({{ site.repo_blob }}/scripts/bootstrap.sh), with a health gate
between each tier so a failure in one doesn't cascade silently into the next:

```bash
./scripts/bootstrap.sh
```

The script is linear and idempotent — every step is `helm upgrade
--install`, `kubectl apply`, or `kubectl wait`, so re-running it after an interrupted run
resumes rather than fails. Reading top to bottom, it builds the platform tier in
dependency order:

1. **The `minikube` profile itself** ([setup-profile.sh]({{ site.repo_blob }}/scripts/setup-profile.sh)), driven by
   `minikube start --driver=docker` — **Docker, not Podman**. This repo standardizes on
   Docker for every container and compose workflow, so the `docker` driver flag is the
   only container toolchain decision the substrate makes, and it is made once, at the
   bottom.
2. **Istio** ([setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh)), gated on `kubectl wait --for=condition=Available
   deploy/istiod` — nothing after this tier proceeds until the control plane is
   serving, not merely scheduled.
3. **CloudNativePG** ([setup-postgres-operator.sh]({{ site.repo_blob }}/scripts/setup-postgres-operator.sh)) — operator plus a Postgres
   `Cluster` custom resource, gated on the primary reaching `Ready`.
4. **Strimzi** ([setup-kafka-operator.sh]({{ site.repo_blob }}/scripts/setup-kafka-operator.sh)) — the Kafka operator and cluster CR
   for the event backbone the services publish Avro records to.
5. **KEDA** ([setup-keda.sh]({{ site.repo_blob }}/scripts/setup-keda.sh)), pinned to 0.15.0 — the autoscaling primitives
   `Part 2`'s [elastic & resilient chapter]({{ '/docs/07-elastic-and-resilient/' | relative_url }})
   builds on.
6. **The LGTM observability stack** ([setup-lgtm.sh]({{ site.repo_blob }}/scripts/setup-lgtm.sh)), installed into the
   `observability` namespace rather than `datamesh`, which separates the platform's
   telemetry infrastructure from the domain services it observes.
7. **Kiali** ([setup-kiali.sh]({{ site.repo_blob }}/scripts/setup-kiali.sh)), gated on Istio being enabled, for the live mesh
   topology view.
8. **Apicurio** ([setup-apicurio.sh]({{ site.repo_blob }}/scripts/setup-apicurio.sh)) — the schema registry the contracts chapter
   depends on, installed last.

Every tier is gated behind a boolean (`ENABLE_ISTIO`, `ENABLE_KAFKA`, and so on, each
defaulting to `true`), so a narrower run — say, skipping Istio to save resources on a
smaller machine — is one environment variable, not a script edit:

```bash
ENABLE_ISTIO=false ENABLE_KIALI=false ./scripts/bootstrap.sh
```

Once the substrate is up, three more scripts round out the day-to-day loop:
[cluster-status.sh]({{ site.repo_blob }}/scripts/cluster-status.sh) for a health
summary across every tier,
[tunnel-services.sh]({{ site.repo_blob }}/scripts/tunnel-services.sh) for stable
NodePort-plus-SSH-tunnel access to services (not
`kubectl port-forward`, which drops under load and doesn't survive a pod restart), and
[teardown.sh]({{ site.repo_blob }}/scripts/teardown.sh) to tear the whole profile
down.

## The application manifests: kustomize, not raw YAML per environment

The platform tier above is operators and Helm charts; the *application* tier — the
domain services themselves — ships as plain Kubernetes manifests organized with
kustomize, under [k8s]({{ site.repo_tree }}/k8s):

```
k8s/base/
  config.yaml                 # ConfigMap: the shared %prod env contract
  order-service.yaml          # Deployment + Service
  inventory-service.yaml      # Deployment + Service
  notification-service.yaml   # Deployment + Service (KEDA Kafka-lag scale target)
  graphql-gateway.yaml         # Deployment + Service (KEDA HTTP scale target)
  kustomization.yaml           # namespace: datamesh: + the four resources above
k8s/overlays/minikube/
  kustomization.yaml            # ../../base + image tag pins, no registry
k8s/keda/
  consumer-scaledobject.yaml   # Kafka-lag ScaledObject targeting notification-service
  gateway-httpscaledobject.yaml # HTTP ScaledObject targeting graphql-gateway
```

The `base` layer declares the resources; the `minikube` overlay holds the
environment-specific decision, a frequent source of errors: there is **no image registry**
in this stack. Images are built with the host's Docker and loaded into the cluster's own
container runtime —

```bash
./scripts/load-images.sh
# per service, by hand:
docker build -f examples/order-service/src/main/docker/Containerfile.multistage \
  -t datamesh/order-service:latest .
minikube image load datamesh/order-service:latest -p datamesh
```

— so the overlay's `images:` block only ever rewrites the tag (`newTag: latest`), never
the registry host, and every base manifest sets `imagePullPolicy: IfNotPresent`. Get that
pull policy wrong — leave it at the default `Always` — and the kubelet will try to pull
`datamesh/order-service` from Docker Hub, fail (there is no such public image), and the
pod will sit in `ImagePullBackOff` even though the correctly tagged image is in the
cluster. Skip the load step and the result is the same. Loading into the cluster and
setting the pull policy to `IfNotPresent` are coupled; change neither independently. The
profile runs containerd, so `eval $(minikube docker-env)`, which only works with the
Docker runtime, is not an option here.

Build context matters too: every
`Containerfile.multistage` build documented in the k8s
[README.md]({{ site.repo_blob }}/k8s/README.md) runs from the **repo root**, not from
inside `examples/<service>/`. That's because each service's builder stage needs the whole
[examples]({{ site.repo_tree }}/examples) Maven reactor on disk to resolve `domain-model`
and `contracts` as reactor dependencies rather than as published artifacts — building
from inside a single service directory would leave those two modules unreachable and the
build would fail at the Maven step rather than at the Docker step.

The same `base`/`overlay` split also carries the one non-secret configuration contract
every Deployment shares:
[config.yaml]({{ site.repo_blob }}/k8s/base/config.yaml) is a ConfigMap
(`datamesh-app-config`) that every Deployment pulls in wholesale via `envFrom`, rather
than each Deployment listing its own `env:` entries. Its values are the in-cluster DNS names the platform tier's own setup scripts produce,
e.g. `KAFKA_BOOTSTRAP_SERVERS=datamesh-kafka-bootstrap.datamesh.svc.cluster.local:9092`
(from Strimzi's own Service-naming convention off the Kafka CR name in
[setup-kafka-operator.sh]({{ site.repo_blob }}/scripts/setup-kafka-operator.sh)) and
`APICURIO_REGISTRY_URL=http://apicurio.datamesh.svc.cluster.local:8080/apis/registry/v3`
(the v3 API path [setup-apicurio.sh]({{ site.repo_blob }}/scripts/setup-apicurio.sh)
installs). Because Quarkus does relaxed
env-var binding onto its own `kafka.bootstrap.servers` and `apicurio.registry.url`
config keys, those two values need zero `application.properties` changes to take effect
in-cluster — the ConfigMap is the production configuration. This is the self-serve
principle at the manifest layer: a domain service declares that it wants the platform's
Kafka and registry and receives the addresses without hand-wiring. Database credentials
are the one value **not** in that ConfigMap —
they come from the CloudNativePG-managed `datamesh-postgres-app` Secret instead, so the
operator remains the single source of truth for a credential it already owns and rotates,
rather than that secret being duplicated into a ConfigMap a human might forget to update.

## The shape of the system

Figure 2.3 draws the system this build runs as three horizontal planes, the layout the
following chapters assume.

{% include excalidraw.html file="02-platform-planes" alt="Three horizontal planes — external clients, the service-mesh plane running the domain services, and the self-serve platform plane underneath — with protocols labeled on the flows between them" caption="Figure 2.3 — The three planes: clients, mesh, platform" %}

It has three horizontal tiers: **external clients** at the top, the **service mesh**
running the domain services in the middle, and the **self-serve platform** providing
shared infrastructure underneath. REST crosses the ingress between external clients and
services, gRPC flows synchronously between services inside the mesh, GraphQL composes
reads across services through a dedicated gateway, and the Kafka event backbone carries
Avro events asynchronously from producers to consumers — the protocol decisions the
[data planes chapter]({{ '/docs/05-data-planes/' | relative_url }}) develops in full.
Telemetry flows out of every service to the observability stack, the subject of the
[observability chapter]({{ '/docs/08-observability/' | relative_url }}).

Read top to bottom, the system is the four principles again: external clients consume
products through stable contracts (data as a product), the domain services each own
their slice of the mesh (domain ownership), the platform tier underneath is shared and
consumed by declaration (self-serve platform), and the mesh and registry enforce the
rules on the traffic and the contracts between everything (federated governance). The
later chapters elaborate this picture.

## A note on single-node clusters

This build runs on `minikube`, a single-node Kubernetes cluster, which suits learning the
pattern and not production. A single node means every tier shares one machine's
resources, which keeps the whole mesh runnable on one workstation but concentrates failure modes
that a multi-node cluster would spread out. [bootstrap.sh]({{ site.repo_blob }}/scripts/bootstrap.sh)'s own header documents the resource budget this concentration
demands: 32 GB of host RAM recommended (the `minikube` profile itself is sized at 24 GB /
16 vCPUs / 80 GB disk) with roughly 2.9 GiB of idle in-cluster footprint once every tier
is on. Where single-node realities bite beyond raw resource ceilings — node-level decay,
the operational care a long-lived single-node cluster needs — those are operational
gotchas specific to this deployment choice rather than to data mesh, and belong in the
operations chapters of Part 2.

Next, the services themselves: what a data product looks like in this build, the
order-service template the others follow, and how each one is packaged and shipped.

---

*Verification status: <span class="status status--verified">verified</span>. `scripts/bootstrap.sh` was driven end to end on a local `minikube` cluster (podman driver, 24 GB / 16 CPU), bringing up all eight tiers healthy — the cluster itself, Istio, CloudNativePG + Postgres, Strimzi + Kafka, KEDA, the full LGTM stack, Kiali, and Apicurio (50/50 pods Running). The bring-up surfaced and fixed three bootstrap bugs along the way: the Strimzi Kafka CR pinned an unsupported Kafka version, Mimir rejected overlapping filesystem data dirs, and Apicurio's readiness probe used a health path its image doesn't serve. Re-run on 2026-10-06 with the docker driver on Docker Desktop (8 CPUs, so `MINIKUBE_CPUS=8`): all eight tiers came up with 50 pods Running after one fix, setup scripts that matched Helm repository names by prefix (an existing `grafana-community` repo hid a missing `grafana` repo). The service images then had to be built and loaded with `scripts/load-images.sh`; the cluster runs containerd, so the `minikube docker-env` route described in earlier revisions does not apply.*
