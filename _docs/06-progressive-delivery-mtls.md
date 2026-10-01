---
title: "Progressive delivery and mTLS"
order: 7
part: Operating the mesh
description: "Evolving a data product's contract in the open with an Istio v1→v2 canary over the real mesh substrate, and the decision to mesh selectively rather than enable sidecar injection namespace-wide."
duration: 30 minutes
marker: "06"
---

Data products evolve. A product whose contract can never change is one nobody builds
on for long, but a product that changes its contract carelessly breaks every consumer
downstream. This chapter is about evolving safely: shifting live traffic gradually
between an old and a new version of a product's response shape, with the service mesh
both routing the split and securing the traffic underneath it. It is also where the
build makes a real architectural decision the earlier chapters have been setting up —
to mesh **selectively**, not namespace-wide — and grounds it in exactly how
`scripts/setup-istio.sh` installs the mesh in this repo.

## What's real here, and what's conceptual

Everything about *installing* the mesh and *opting a service into it* is real,
runnable substrate already in this repo: `scripts/setup-istio.sh` installs Istio via
Helm, and `k8s/base/order-service.yaml` is the Deployment a canary would target. What
is **not** yet built, as of this chapter, is a second (`v2`) build of order-service and
the `DestinationRule`/`VirtualService` pair that would split traffic between them —
unlike `k8s/keda/`, there is no `k8s/istio/` directory with canary manifests in this
tree yet. So this chapter walks the canary mechanism conceptually, against the real
install this repo ships, rather than citing files that don't exist. Where a YAML
snippet below is illustrative rather than a path in this repo, it's labeled as such.

`k8s/README.md`'s own "Mesh (Istio) decision" section states the current ground truth
plainly, and it's worth quoting rather than paraphrasing: "Istio + Kiali are installed
cluster-wide by 9a but the `datamesh` namespace is **not** labeled for sidecar
auto-injection... None of these three Deployments carry the
`sidecar.istio.io/inject: "true"` pod annotation, so **none of them are in the mesh**
for Phase C." That's `order-service`, `notification-service`, and `graphql-gateway` —
every application Deployment this repo ships, today, running outside the mesh by
deliberate default. The decision record behind that default is `_plans/decisions.md`'s
DRQ-011, which settles "Istio + Kiali: ON" as a kept-but-selective capability rather
than either ripping the mesh out or defaulting every workload into it. This chapter is
about what changes, and what doesn't, the day a team decides a specific product is
ready to opt in.

## Installing the mesh: `scripts/setup-istio.sh`

The control plane is installed the same way every other operator in this stack is —
`helm upgrade --install`, no `istioctl` dependency:

```bash
helm upgrade --install istio-base istio/base \
    --namespace istio-system --create-namespace \
    --version 1.29.0 --set defaultRevision=default

helm upgrade --install istiod istio/istiod \
    --namespace istio-system --version 1.29.0 \
    --wait --timeout 5m
```

The script runs a short preflight before either `helm upgrade` fires: it checks that
`kubectl config current-context` actually matches the `datamesh` minikube profile, and
if it doesn't, it warns and asks for confirmation rather than silently installing into
whatever cluster happens to be current. That matters more for Istio than for most of
the operators this stack installs, because `istio-base` lands cluster-scoped CRDs —
installing against the wrong context doesn't just misconfigure one namespace, it can
leave CRDs behind in a cluster nobody meant to touch. After `istiod` comes up, the
script runs `kubectl rollout status deployment/istiod --timeout=5m` as an explicit
gate — not just trusting Helm's own `--wait`, but confirming the control plane's
Deployment actually reaches `Available` before declaring the step done. Both `helm
upgrade --install` invocations are idempotent, so re-running the script against an
already-installed mesh is a safe no-op rather than an error.

Two decisions in that script matter for everything that follows in this chapter:

- **Scope: control plane only.** No ingress gateway is installed — the comment in
  the script defers that to whenever this stack actually needs an external entry
  point, consistent with the minimal-substrate approach the rest of the build takes.
- **No namespace label.** The script explicitly does **not** run
  `kubectl label namespace datamesh istio-injection=enabled`. That's the selective-
  injection decision this chapter is about, and it's load-bearing enough that the
  script's own header comment explains why before installing anything:

  > IMPORTANT — mesh selectively, not namespace-wide: this script does NOT label the
  > `datamesh` namespace for automatic sidecar injection. Namespace-wide injection
  > breaks Job pods (hang at 1/2 forever — the sidecar never exits) and
  > CloudNativePG's Postgres pods (mTLS collides with the operator's own TLS). Inject
  > per-Deployment instead, when a given service actually joins the mesh.

{% include excalidraw.html file="06-istio-mesh" alt="Diagram of the Istio control plane installed cluster-wide via Helm, with the datamesh namespace left unlabeled for auto-injection and sidecar membership opted in per Deployment" caption="Figure 6.1 — Istio control-plane install and selective sidecar injection" %}

Opting a specific Deployment into the mesh is one annotation, added under
`spec.template.metadata`:

```yaml
spec:
  template:
    metadata:
      annotations:
        sidecar.istio.io/inject: "true"
```

`k8s/base/order-service.yaml` as shipped does **not** carry that annotation — its own
header comment says so explicitly ("Mesh: NOT injected... Phase C default is OUT of
the mesh for every app Deployment, to keep the substrate demo simple"). Adding it to
`order-service`'s Deployment is the first real step toward the canary this chapter
describes.

Worth understanding is *how* that one annotation actually takes effect, because it
explains a trap that's easy to hit in practice: `istiod` registers a
`MutatingWebhookConfiguration` that intercepts Pod admission cluster-wide. When a new
Pod is created, the webhook inspects it for the `sidecar.istio.io/inject` annotation
(or the namespace label, when that path is used) and, if present and true, mutates the
Pod spec on the way in to add the `istio-proxy` container before the API server ever
persists the object. That mutation happens at **Pod admission time**, not at
`kubectl apply` time on the Deployment. Concretely: adding the annotation to a
Deployment that already has running pods changes nothing about those existing pods —
they keep running unmeshed until something recreates them, whether that's
`kubectl rollout restart deployment/order-service -n datamesh` or a routine eviction.
This is the same two-step shape every Kubernetes mutating-admission mechanism has
(annotate the template, then force a new generation of pods to pick it up), and it's
worth remembering specifically here because "I added the annotation and nothing
happened" is the single most common way to think injection is broken when it's
actually just waiting for a rollout.

One version detail that changes how you check mesh membership: Istio 1.29+ (the
version this script pins) uses **native sidecars** — `istio-proxy` runs as an
`initContainer` with `restartPolicy: Always`, not as a second ordinary container. A
meshed pod still shows `2/2 Ready` in `kubectl get pods`, but a membership check that
only inspects `.spec.containers` will miss it; it has to look at
`.spec.initContainers` too. Native sidecars also change pod startup ordering in a way
worth calling out: because `istio-proxy` is an init container (just one with
`restartPolicy: Always`, so it never blocks the pod the way a normal init container
would), kubelet starts it before the application container, and the proxy's own
readiness gate holds the Pod back from `Ready` until the proxy itself has established
its listeners — so a meshed pod's `startupProbe` is effectively racing against the
proxy coming up too, not just the JVM.

## Canarying a contract, not just a binary

The interesting thing to canary in a data mesh isn't a new build of the same service —
it's a new version of the *contract*. Look at order-service's actual response shape,
`OrderDto` (`examples/domain-model/.../OrderDto.java`):

```java
public record OrderDto(
        String orderId,
        String customerId,
        String itemSku,
        int quantity,
        BigDecimal amount,
        OrderStatus status,
        String createdAt) {
}
```

A canonical "evolve the contract without breaking clients" change would be a `v2` that
adds a `currency` field to that record (defaulting to `"USD"` for existing rows), while
`v1`'s shape — the one above, exactly as it ships today — keeps serving unchanged.
Istio would split live `GET /orders/{id}` traffic between the two versions by weight,
so a consumer base moves from all-v1 to all-v2 gradually, with a window at each step to
watch for trouble before advancing, rather than a single flag-day cutover.

The mechanism is the standard Istio trio, illustrated here (not a file in this repo
yet) against the real `order-service` Deployment/Service from `k8s/base/`:

```yaml
# Illustrative — not a file in this repo. Subsets select pods by the `version`
# label; order-service's current Deployment has no such label, so a real v1/v2
# split needs that label added to both the existing and a new Deployment.
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: order-service
  namespace: datamesh
spec:
  host: order-service.datamesh.svc.cluster.local
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: order-service
  namespace: datamesh
spec:
  hosts:
    - order-service.datamesh.svc.cluster.local
  http:
    - route:
        - destination:
            host: order-service.datamesh.svc.cluster.local
            subset: v1
          weight: 90
        - destination:
            host: order-service.datamesh.svc.cluster.local
            subset: v2
          weight: 10
```

The `DestinationRule` defines the v1 and v2 *subsets* by a `version` pod label; the
`VirtualService` routes a weighted split across those subsets. Shifting the canary
forward is just re-applying the `VirtualService` with new weights — 90/10, then
50/50, then 0/100 — so the whole progressive rollout is a sequence of one-line weight
edits, and rolling back is the same edit in reverse. A real v1/v2 split on this
substrate needs two things this repo doesn't ship yet: a second Deployment running the
`currency`-bearing build with `version: v2` (the existing Deployment would be relabeled
`version: v1`), and the two manifests above, in a `k8s/istio/` directory alongside
`k8s/base/` and `k8s/keda/`.

A simplification worth naming up front, carried over from the pattern this build
mirrors: v1 and v2 would run the *same image* with an environment toggle and a
different `version` label, rather than two images from two separate commits — that
keeps the exercise focused on the traffic-management mechanism rather than an image
pipeline, and the Istio mechanics are identical either way.

What makes each weight step safe to advance, rather than a blind five-minute timer, is
having something to look at between steps. This repo's observability substrate — the
[next-but-one chapter](/docs/08-observability/) covers it in full — is exactly that:
Kiali's live mesh graph would show the v1/v2 split as two weighted edges out of
`order-service`, and a Grafana dashboard sourced from the same Mimir backend would show
whether the v2 subset's error rate or latency looks any different from v1's before the
next weight bump. A canary with no way to observe its own subsets is just a slower
flag-day cutover with extra YAML; the mesh's routing and this repo's observability
stack are meant to be read together, not in isolation.

## mTLS for free

The same mesh that would route the canary also secures it, with no code written for it.
When two services are both in the mesh, Istio establishes mutual TLS between their
sidecars automatically — each proxy authenticates the other, and the traffic between
them is encrypted end to end, without an application ever handling a certificate. That
is the **federated computational governance** principle made concrete: "traffic
between products is authenticated and encrypted" becomes a property the platform
enforces uniformly, not a checklist item each team implements (or forgets to) in its
own service. A data product's author writes no TLS code; the mesh provides it at the
network boundary the moment the product opts in.

{% include excalidraw.html file="06-service-mesh" alt="Diagram of meshed data-mesh services communicating over automatic mutual TLS between Istio sidecars, alongside unmeshed workloads such as Postgres and batch jobs that remain outside the mesh" caption="Figure 6.2 — mTLS between meshed services, and what deliberately stays outside the mesh" %}

One nuance worth being precise about, because it's easy to assume mTLS becomes
mandatory the instant two sidecars exist: Istio's default mesh-wide mTLS mode is
**PERMISSIVE**, meaning a meshed service's sidecar accepts *both* mTLS and plaintext
connections on the same port. Istio auto-detects which protocol an inbound connection
is using and handles either. That default exists specifically for mixed environments —
exactly this repo's situation, where only some Deployments opt into the mesh at a
time — because it lets a service be added to the mesh without every one of its
existing non-meshed callers breaking on day one. Mutual TLS only becomes *mandatory*
for a given workload once a `PeerAuthentication` resource explicitly sets
`mtls.mode: STRICT` for it; this repo ships no such policy as of this chapter, which
is consistent with Phase C's "every app Deployment starts outside the mesh" default —
there's nothing to make strict yet. The practical implication for whoever eventually
canaries `order-service`: opting it into the mesh gets it encrypted, authenticated
traffic with any other meshed caller immediately, under PERMISSIVE, with no risk of
locking out callers that haven't opted in yet; moving to STRICT is a deliberate,
separate decision for once enough of the call graph is meshed that plaintext fallback
is no longer wanted.

## The decision: mesh selectively, not namespace-wide

Istio offers a one-label shortcut — label a namespace `istio-injection=enabled` and
every pod created there gets a sidecar automatically. One label, whole-namespace mTLS,
nothing to configure per workload. `scripts/setup-istio.sh` deliberately does not take
that shortcut, and the reason is concrete, not theoretical: the `datamesh` namespace in
this stack holds more than mesh-appropriate services.

Three categories of workload in this exact stack would break under namespace-wide
injection:

- **Batch jobs that are supposed to finish.** A meshed Job gets a sidecar that never
  exits on its own — the proxy keeps running after the job's work is done, so the pod
  never reaches a completed state and the Job hangs at `1/2` forever. Any ingestion or
  one-shot job in this namespace would hit exactly this.
- **Operator-managed infrastructure with its own TLS.** CloudNativePG's Postgres pods
  (`scripts/setup-postgres-operator.sh`) run their own TLS on their internal ports;
  wrapping an injected sidecar around that collides with the operator's own encrypted
  channels, and the pod crash-loops. Infrastructure that already secures itself doesn't
  want a second TLS layer forced onto it.
- **Anything where the sidecar's overhead or coupling buys nothing.** Every sidecar
  consumes CPU/memory and couples the workload's startup to the mesh control plane
  being reachable. For a pod doing no mesh-managed traffic, that is cost with zero
  benefit.

There is a systemic reason beyond those three, too: with namespace-wide injection,
*every* pod creation in the namespace now depends on the sidecar-injection webhook
being reachable. If the mesh control plane has a bad moment, you cannot create a
database pod, a job, or anything else in that namespace — workloads with nothing to do
with the mesh become coupled to its health. Per-Deployment opt-in (the
`sidecar.istio.io/inject: "true"` annotation shown above) contains that blast radius:
only the workloads that actually declare mesh participation depend on the mesh being
up.

The trade-off is real, and worth stating plainly rather than glossing over: namespace-
wide injection is genuinely simpler to reason about, and gets you blanket mTLS with one
`kubectl label`. Selective injection is more configuration — a per-Deployment decision,
every time — in exchange for not coupling Postgres, batch jobs, and anything else that
doesn't belong in the mesh to the mesh's own health. `scripts/setup-istio.sh` takes that
configuration cost on purpose.

Seeing the effect of that decision doesn't require guessing at pod specs: Kiali's live
traffic graph, installed by `scripts/setup-kiali.sh` and covered in full in the
[observability chapter](/docs/08-observability/), only draws an edge for traffic it
actually observes passing through meshed sidecars. With every app Deployment currently
outside the mesh, that graph is quiet by design — not broken, just accurately
reporting that nothing in `datamesh` has opted in yet. The day `order-service` gains
the injection annotation and the canary above starts routing real weight, that same
graph is where the v1/v2 split becomes visible as two live edges rather than something
inferred from `kubectl describe`.

## Why this belongs to the mesh chapter

Progressive delivery and mTLS are two sides of the same capability: a service mesh
sitting between products, routing their traffic and securing it. The canary mechanism
is the routing side — moving consumers from one contract version to the next without a
flag day. mTLS is the security side — authenticated, encrypted traffic as a platform
property, not a line item in each service's code. And the selective-injection decision
baked into `scripts/setup-istio.sh` is what keeps the mesh an asset in this stack
rather than a liability: applied to the Deployments that benefit from it, kept away
from the Postgres cluster and any batch job that would break under it.

Next, the other half of operating a mesh under real conditions: matching product
capacity to demand — including scaling all the way down to zero — with KEDA.

---

*Verification status: <span class="status status--unverified">unverified</span>. No
live minikube cluster was available while writing this chapter, so none of this was
run: `scripts/setup-istio.sh` has not been executed against a real cluster in this
environment, the native-sidecar (`initContainer`) membership behavior described above
is documented Istio 1.29+ behavior rather than something observed here, and the
`DestinationRule`/`VirtualService` pair is illustrative YAML, not a manifest that has
been applied or rendered. Confirm on a real run: that `helm upgrade --install istiod`
actually succeeds at the pinned `1.29.0` against this minikube setup, that a pod
annotated with `sidecar.istio.io/inject: "true"` actually comes up `2/2` with the
proxy as an `initContainer`, that the PERMISSIVE mTLS default is actually what this
install ships (rather than a chart-level override changing it), and — once a `v2`
order-service build and the Istio manifests above exist — that a weighted
`VirtualService` split actually lands traffic in the stated proportions.*
