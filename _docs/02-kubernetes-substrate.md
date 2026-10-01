---
title: "Kubernetes as the substrate"
order: 3
part: Foundations
description: "Why Kubernetes is a natural substrate for a data mesh, how the four principles map onto namespaces, operators, and RBAC, and the Docker-built minikube substrate this build stands up."
duration: "25 min"
marker: "03"
---

The [previous chapter]({{ '/docs/01-concepts/' | relative_url }}) ended on a claim worth
taking seriously: a data mesh is a pattern, not a tool, and the tools are expressions of
it. So why build this reference on Kubernetes at all? Because the four principles map
onto Kubernetes primitives unusually cleanly — cleanly enough that "implement a data mesh
on Kubernetes" stops feeling like a translation exercise and starts feeling like the
primitives were waiting for it. This chapter makes that mapping explicit, then walks the
actual substrate this build stands up on minikube. Figure 2.1, the capstone diagram for
this part, shows where this chapter is headed — the full data mesh this build runs,
domain services and platform tier together, on top of the single minikube profile
`scripts/bootstrap.sh` stands up.

{% include excalidraw.html file="02-capstone-data-mesh" alt="The complete data mesh reference architecture running on minikube — domain services, the service mesh, and the self-serve platform tier underneath them" caption="Figure 2.1 — The capstone: a data mesh on minikube" %}

## Why the alignment is so good

Kubernetes was designed around multi-tenancy, declarative resources, an extensible type
system, and operators that turn operational knowledge into software. Those are exactly
the capabilities a data mesh needs — a place for each domain to own its slice, a way to
express a data product as a deployable artifact with a contract, a shared platform layer
domains consume without building it themselves, and a boundary where standards get
enforced automatically. You *can* build a data mesh without Kubernetes, and you can
certainly run Kubernetes without building a mesh. But the alignment is strong enough that
each principle has a natural home in Kubernetes primitives you already know.

## The four principles, mapped to primitives

Figure 2.2 lays the four principles directly alongside the Kubernetes primitives that
realize them, as a single reference before the detail below walks each pairing in turn.

{% include excalidraw.html file="02-principles-to-pieces" alt="The four data mesh principles mapped to their corresponding Kubernetes primitives — namespaces, Deployments and CRDs, operators, and admission/mesh policy" caption="Figure 2.2 — From principles to Kubernetes pieces" %}

**Domain ownership → namespaces, ServiceAccounts, RBAC, quotas.** The unit of tenancy in
Kubernetes is the namespace, and it carries its own identities (ServiceAccounts), its own
permissions (Roles and RoleBindings), and its own resource budget (quotas). That's
precisely the boundary a domain needs: a place it owns, with access it controls and a
budget it lives within, isolated from other domains by default. In this build every
domain service lands in the single `datamesh` namespace (a deliberate simplification for
a single-node teaching cluster — a multi-team deployment would split that further), while
the observability stack gets its own `observability` namespace, so the namespace boundary
is already doing real separation work even at this scale.

**Data as a product → Deployments, Services, and CRDs.** A data product is a deployable
artifact that exposes a contract — which is exactly what a Deployment plus a Service
*is*. The Deployment runs the product; the Service is its stable address. And because
Kubernetes lets you extend its own type system with Custom Resource Definitions, the
platform can offer domain-specific types — a Kafka `Topic`, a Postgres `Cluster` — that a
domain declares the same way it declares a Deployment. The data product becomes a
first-class, declarable thing rather than an informal collection of scripts.

**Self-serve data platform → operators and shared cluster infrastructure.** This is
where Kubernetes earns its place most clearly. An *operator* packages the knowledge of
how to run a complex stateful system — Kafka, Postgres, autoscaling, a service mesh —
into a controller that reconciles a simple declarative request into a running system. A
domain team that needs Kafka doesn't learn to operate Kafka; it asks the platform's Kafka
operator for a cluster and gets one. In this build the event backbone (Strimzi), the
database (CloudNativePG), autoscaling (KEDA), the service mesh (Istio), and the
observability stack (the LGTM stack — Loki, Grafana, Tempo, Mimir) are all shared
platform infrastructure the domains consume by declaration. That's the self-serve
principle made literal.

**Federated computational governance → admission control, mesh policy, CRD validation,
and the schema registry.** Governance in a mesh is supposed to be enforced by the
platform, automatically, at the boundary — not by review meetings after the fact.
Kubernetes has several boundaries where that enforcement lives: service-mesh
authorization and mutual-TLS policies that govern traffic between products, the schema
validation built into every CRD, and — one layer up the stack, running *on* this
substrate — the Apicurio schema registry rejecting an incompatible Avro contract change
at publish time. The rules become code that runs at the edge of the system, which is
exactly what "computational governance" means.

## The substrate this build actually stands up

Everything above is the general case. Concretely, this build's substrate is a single
minikube profile, brought up tier by tier by `scripts/bootstrap.sh`, with a health gate
between each tier so a failure in one doesn't cascade silently into the next:

```bash
./scripts/bootstrap.sh
```

The script is intentionally linear and idempotent — every step is `helm upgrade
--install`, `kubectl apply`, or `kubectl wait`, so re-running it after an interrupted run
resumes rather than fails. Reading top to bottom, it builds the platform tier in
dependency order:

1. **The minikube profile itself** (`scripts/setup-profile.sh`), driven by
   `minikube start --driver=docker` — **Docker, not Podman**. This repo standardized on
   Docker for every container and compose workflow (the `lgtm-docker-stack` skill rather
   than `lgtm-podman-stack`), so the one `docker driver` flag is the only container
   toolchain decision the substrate makes, and it's made once, at the bottom.
2. **Istio** (`scripts/setup-istio.sh`), gated on `kubectl wait --for=condition=Available
   deploy/istiod` — nothing after this tier proceeds until the control plane is actually
   serving, not merely scheduled.
3. **CloudNativePG** (`scripts/setup-postgres-operator.sh`) — operator plus a Postgres
   `Cluster` custom resource, gated on the primary reaching `Ready`.
4. **Strimzi** (`scripts/setup-kafka-operator.sh`) — the Kafka operator and cluster CR
   for the event backbone the services publish Avro records to.
5. **KEDA** (`scripts/setup-keda.sh`), pinned to 0.15.0 — the autoscaling primitives
   `Part 2`'s [elastic & resilient chapter]({{ '/docs/07-elastic-and-resilient/' | relative_url }})
   builds on.
6. **The LGTM observability stack** (`scripts/setup-lgtm.sh`), installed into the
   `observability` namespace rather than `datamesh` — a deliberate boundary between the
   platform's own telemetry infrastructure and the domain services it observes.
7. **Kiali** (`scripts/setup-kiali.sh`), gated on Istio being enabled, for the live mesh
   topology view.
8. **Apicurio** (`scripts/setup-apicurio.sh`) — the schema registry the contracts chapter
   depends on, installed last because it's the one tier that's useful without any
   domain service running yet.

Every tier is gated behind a boolean (`ENABLE_ISTIO`, `ENABLE_KAFKA`, and so on, each
defaulting to `true`), so a narrower run — say, skipping Istio to save resources on a
smaller laptop — is one environment variable, not a script edit:

```bash
ENABLE_ISTIO=false ENABLE_KIALI=false ./scripts/bootstrap.sh
```

Once the substrate is up, three more scripts round out the day-to-day loop:
`scripts/cluster-status.sh` for a health summary across every tier, `scripts/tunnel-services.sh`
for stable NodePort-plus-SSH-tunnel access to services (deliberately not
`kubectl port-forward`, which drops under load and doesn't survive a pod restart), and
`scripts/teardown.sh` to tear the whole profile down.

## The application manifests: kustomize, not raw YAML per environment

The platform tier above is operators and Helm charts; the *application* tier — the
domain services themselves — ships as plain Kubernetes manifests organized with
kustomize, under `k8s/`:

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

The `base` layer declares the resources; the `minikube` overlay is where the
environment-specific decision lives. That decision is worth spelling out because it's
easy to get wrong on a teaching cluster: there is **no image registry** in this stack.
Images are built directly into minikube's own Docker daemon —

```bash
eval $(minikube docker-env -p datamesh)
docker build -f examples/order-service/src/main/docker/Containerfile.multistage \
  -t datamesh/order-service:latest .
```

— so the overlay's `images:` block only ever rewrites the tag (`newTag: latest`), never
the registry host, and every base manifest sets `imagePullPolicy: IfNotPresent`. Get that
pull policy wrong — leave it at the default `Always` — and the kubelet will try to pull
`datamesh/order-service` from Docker Hub, fail (there is no such public image), and the
pod will sit in `ImagePullBackOff` even though the correctly-tagged image is sitting
right there in minikube's own daemon. That coupling between "build into minikube's
daemon" and "pull policy must be `IfNotPresent`" is the one fragile assumption worth
remembering before you change either side of it independently.

Build context matters too, and it's easy to get backwards the first time: every
`Containerfile.multistage` build in `k8s/README.md` runs from the **repo root**, not from
inside `examples/<service>/`. That's because each service's builder stage needs the whole
`examples/` Maven reactor on disk to resolve `domain-model` and `contracts` as reactor
dependencies rather than as published artifacts — building from inside a single service
directory would leave those two modules unreachable and the build would fail at the
Maven step, not at the Docker step, which makes the mistake more confusing than it needs
to be the first time you hit it.

The same `base`/`overlay` split also carries the one non-secret configuration contract
every Deployment shares: `k8s/base/config.yaml` is a ConfigMap (`datamesh-app-config`)
that every Deployment pulls in wholesale via `envFrom`, rather than each Deployment
listing its own `env:` entries. Its values are not placeholders — they're the literal
in-cluster DNS names the platform tier's own setup scripts produce, e.g.
`KAFKA_BOOTSTRAP_SERVERS=datamesh-kafka-bootstrap.datamesh.svc.cluster.local:9092` (from
Strimzi's own Service-naming convention off the Kafka CR name in
`scripts/setup-kafka-operator.sh`) and
`APICURIO_REGISTRY_URL=http://apicurio.datamesh.svc.cluster.local:8080/apis/registry/v3`
(the v3 API path `scripts/setup-apicurio.sh` installs). Because Quarkus does relaxed
env-var binding onto its own `kafka.bootstrap.servers` and `apicurio.registry.url`
config keys, those two values need zero `application.properties` changes to take effect
in-cluster — the ConfigMap *is* the production configuration, which is the self-serve
principle showing up again at the manifest layer: a domain service declares that it
wants the platform's Kafka and registry, and gets the real addresses without hand-wiring
them. Database credentials are the one value deliberately **not** in that ConfigMap —
they come from the CloudNativePG-managed `datamesh-postgres-app` Secret instead, so the
operator remains the single source of truth for a credential it already owns and rotates,
rather than that secret being duplicated into a ConfigMap a human might forget to update.

## The shape of the system

With the mapping and the substrate both in hand, here's the system this build runs.
Figure 2.3 draws it as three horizontal planes, which is the layout worth holding in
mind for every chapter that follows.

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
rules on the traffic and the contracts between everything (federated governance). It's
the picture to return to as the rest of the tutorial works through the parts.

## A note on minikube specifically

This build runs on minikube — a single-node Kubernetes cluster — which is the right
choice for *learning* the pattern and wrong for running it in production. A single node
means every tier shares one machine's resources, which keeps the whole mesh runnable on
a laptop but also concentrates failure modes that a real multi-node cluster would spread
out. `scripts/bootstrap.sh`'s own header documents the resource budget this concentration
demands: 32 GB of host RAM recommended (the minikube profile itself is sized at 24 GB /
16 vCPUs / 80 GB disk) with roughly 2.9 GiB of idle in-cluster footprint once every tier
is on. Where single-node realities bite beyond raw resource ceilings — node-level decay,
the operational care a long-lived single-node cluster needs — those are operational
gotchas particular to this deployment choice rather than to data mesh as a pattern, and
belong in the operations-focused chapters of Part 2 rather than here.

Next, the services themselves: what a data product looks like in this build, the
order-service template the others follow, and how each one is packaged and shipped.

---

*Verification status: <span class="status status--unverified">unverified</span>. The
tier-by-tier walkthrough above is read directly from `scripts/bootstrap.sh` and
`k8s/README.md` as they exist in the repo today, but the sequence has not been driven end
to end on a clean minikube profile in this authoring pass. The highest-risk things to
confirm on a real run: that all eight tiers actually reach their health gates within the
documented resource budget, that the `IfNotPresent` / no-registry image flow behaves as
described the first time (not just on a warm daemon), and that the `ENABLE_*` flag
combinations used as an example here don't hit an undocumented dependency the script's
own sanity checks (e.g. `ENABLE_KIALI` requiring `ENABLE_ISTIO`) don't already catch.*
