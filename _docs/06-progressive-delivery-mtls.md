---
title: "Progressive delivery and mTLS"
order: 7
part: Operating the mesh
description: "Evolving a data product's contract in the open with an Istio v1→v2 canary on a local Kubernetes cluster, and the decision to mesh selectively rather than enable sidecar injection namespace-wide."
duration: 30 minutes
marker: "07"
---

Data products evolve. A product whose contract can never change is one nobody builds
on for long, but a product that changes its contract carelessly breaks every consumer
downstream. This chapter covers evolving safely: shifting live traffic gradually
between an old and a new version of a product's response shape, with the service mesh
both routing the split and securing the traffic underneath it. It also records the
architectural decision the earlier chapters set up — to mesh **selectively**, not
namespace-wide — and ties it to how
[setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh) installs the mesh in this repo.

## What is implemented and what is conceptual

Installing the mesh, opting a service into it, enforcing mTLS, and routing a v1/v2
canary split are all runnable in this repo: [setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh)
installs Istio via Helm, [order-service.yaml]({{ site.repo_blob }}/k8s/base/order-service.yaml) is the Deployment the canary
targets, and [istio]({{ site.repo_tree }}/k8s/istio) — mirroring [keda]({{ site.repo_tree }}/k8s/keda)'s shape as a sibling overlay directory
with its own [kustomization.yaml]({{ site.repo_blob }}/k8s/istio/kustomization.yaml) — holds the injection patches, the namespace-wide
`PeerAuthentication`, the `order-service-v2` Deployment, and the `DestinationRule`/
`VirtualService` pair that splits traffic between the two. Applying that overlay
(`kubectl apply -k k8s/istio`) is the opt-in this chapter describes, start to finish.

Still conceptual: a different `v2` *build* of order-service that adds a `currency`
field to `OrderDto` and serves it. `order-service-v2` runs the *same image* as
`order-service`, distinguished only by a `version: v2` pod label, which keeps the
exercise on traffic management and mTLS instead of a second image pipeline. The
simplification does not change the Istio mechanics; it is covered later in this chapter.

The "Mesh (Istio) decision" section of [README.md]({{ site.repo_blob }}/k8s/README.md) records the current state:
Istio and Kiali are installed cluster-wide, but the `datamesh` namespace is
**not** labeled for sidecar auto-injection, so mesh membership is a per-Deployment opt-in. [order-service.yaml]({{ site.repo_blob }}/k8s/base/order-service.yaml),
[notification-service.yaml]({{ site.repo_blob }}/k8s/base/notification-service.yaml), and [graphql-gateway.yaml]({{ site.repo_blob }}/k8s/base/graphql-gateway.yaml) all still ship unmeshed by
default — the [istio]({{ site.repo_tree }}/k8s/istio) overlay is what brings them in, and it does so without
editing [base]({{ site.repo_tree }}/k8s/base) itself. Istio and Kiali stay installed, and
mesh membership is a per-service opt-in; the mesh is neither removed nor applied to
every workload by default. When a team decides a specific product is ready to opt in, this chapter covers what
changes, what doesn't, and what the opt-in requires.

## Installing the mesh: [setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh)

The control plane is installed the same way every other operator in this stack is —
`helm upgrade --install`, no `istioctl` dependency. Istio 1.31 is not published to
the `istio-release` Helm repository, so the script downloads the pinned 1.31.1
release tarball once, checks it against the published `.sha256`, and installs the
`base` and `istiod` charts the release ships:

```bash
ISTIO_HOME=~/.local/share/istio-1.31.1     # unpacked by setup-istio.sh

helm upgrade --install istio-base "$ISTIO_HOME/manifests/charts/base" \
    --namespace istio-system --create-namespace \
    --set defaultRevision=default

helm upgrade --install istiod "$ISTIO_HOME/manifests/charts/istio-control/istio-discovery" \
    --namespace istio-system \
    --wait --timeout 5m
```

Two checks run alongside: if an `istioctl` is on `PATH`, its client version must
match 1.31.1 or the script warns and points at `$ISTIO_HOME/bin/istioctl`; and an
`istiod` more than one minor version behind (for example 1.29) is refused, because
Istio upgrades in place one minor version at a time.

The script runs a short preflight before either `helm upgrade` fires: it checks that
`kubectl config current-context` matches the `datamesh` `minikube` profile (a local
single-node Kubernetes cluster), and
if it doesn't, it warns and asks for confirmation instead of silently installing into
whatever cluster is current. That matters more for Istio than for most of
the operators this stack installs, because `istio-base` lands cluster-scoped CRDs —
installing against the wrong context doesn't just misconfigure one namespace, it can
leave CRDs behind in a cluster nobody meant to touch. After `istiod` comes up, the
script runs `kubectl rollout status deployment/istiod --timeout=5m` as an explicit
gate: beyond Helm's own `--wait`, it confirms the control plane's
Deployment reaches `Available` before declaring the step done. Both `helm
upgrade --install` invocations are idempotent, so re-running the script against an
already-installed mesh is a safe no-op.

Two decisions in that script matter for everything that follows in this chapter:

- **Scope: control plane only.** No ingress gateway is installed — the comment in
  the script defers that until this stack needs an external entry
  point, consistent with the minimal approach used elsewhere in the build.
- **No namespace label.** The script explicitly does **not** run
  `kubectl label namespace datamesh istio-injection=enabled`. That is the selective-
  injection decision, and the script's header comment explains why before
  installing anything:

  > IMPORTANT — mesh selectively, not namespace-wide: this script does NOT label the
  > `datamesh` namespace for automatic sidecar injection. Namespace-wide injection
  > breaks Job pods (hang at 1/2 forever — the sidecar never exits) and
  > CloudNativePG's Postgres pods (mTLS collides with the operator's own TLS). Inject
  > per-Deployment instead, when a given service joins the mesh.

{% include excalidraw.html file="06-istio-mesh" alt="Diagram of the Istio control plane installed cluster-wide via Helm, with the datamesh namespace left unlabeled for auto-injection and sidecar membership opted in per Deployment" caption="Figure 6.1 — Istio control-plane install and selective sidecar injection" %}

Opting a specific Deployment into the mesh is one pod-template **label**, added under
`spec.template.metadata`:

```yaml
spec:
  template:
    metadata:
      labels:
        sidecar.istio.io/inject: "true"
```

That has to be a label, not an annotation, and the reason is specific to how
`istiod`'s injection webhook matches pods. `istiod` registers a
`MutatingWebhookConfiguration` that intercepts Pod admission cluster-wide; its
`object.sidecar-injector.istio.io` webhook entry carries an `objectSelector` matching
`sidecar.istio.io/inject In ["true"]`. A Kubernetes **webhook `objectSelector` is
always evaluated against the admitted object's *labels* — never its annotations.**
That is not Istio-specific; it is how `objectSelector` works for any
`MutatingWebhookConfiguration`. With the `datamesh` namespace left
unlabeled for namespace-wide injection (the next section covers why), the *only* way
left to satisfy that `objectSelector` for a given pod is a pod-template label matching
it exactly. The same key set as an **annotation** is never evaluated by an
`objectSelector` at all, so it silently injects nothing — no error, no event, the pod
just comes up unmeshed, looking identical to any other unmeshed pod.

Confirmed on the cluster: setting `sidecar.istio.io/inject: "true"` as a
pod-template **annotation** on a Deployment in the unlabeled `datamesh` namespace
produced no sidecar at all. Setting the exact same key as a pod-template **label**
instead did inject the native sidecar (`istio-init` + `istio-proxy`), with no other
change. [order-service.yaml]({{ site.repo_blob }}/k8s/base/order-service.yaml) as shipped carries neither — its own header
comment explains the label-vs-annotation distinction and points at the
[istio]({{ site.repo_tree }}/k8s/istio) overlay ([inject-order-service.yaml]({{ site.repo_blob }}/k8s/istio/inject-order-service.yaml)) as where the opt-in label
gets added, leaving the base manifest unedited. The same pattern applies to
`notification-service` and `graphql-gateway` via their own patch files in that overlay.

That label takes effect at Pod admission, not at `kubectl apply` time on the
Deployment. When a new Pod is created, the webhook's `objectSelector` is evaluated
against that Pod's labels and, if it matches, the webhook mutates the Pod spec on the
way in to add the `istio-proxy` sidecar before the API server ever persists the
object. One consequence follows directly: the label only affects newly admitted pods.
Adding it to a Deployment that already has running pods changes nothing about those
existing pods — they keep running unmeshed until something recreates them, whether
that's `kubectl rollout restart deployment/order-service -n datamesh` or a routine
eviction. [README.md]({{ site.repo_blob }}/k8s/istio/README.md) calls this out, since `kubectl apply -k
k8s/istio` only changes the Deployment objects' pod *templates* — it doesn't by itself
force existing pods to roll. Every Kubernetes mutating-admission mechanism has this two-step shape: label the
template, then force a new generation of pods to pick it up. A pod that keeps running unmeshed right after the label is added
has not failed; it is waiting for that rollout.

Istio 1.29+ (this script pins 1.31.1) uses **native sidecars**: `istio-proxy`
runs as an `initContainer` with `restartPolicy: Always`, not as a second ordinary
container. This changes how you check mesh membership. A meshed pod still shows
`2/2 Ready` in `kubectl get pods`, but a membership check that only inspects
`.spec.containers` will miss it; it has to look at `.spec.initContainers` too. Native
sidecars also change pod startup ordering: because `istio-proxy` is an init
container — one with `restartPolicy: Always`, so it never blocks the pod the way a
normal init container would — kubelet starts it before the application container. The
proxy's own readiness gate then holds the Pod back from `Ready` until the proxy itself
has established its listeners, so a meshed pod's `startupProbe` is effectively racing
against the proxy coming up as well as the JVM.

## Canarying a contract as well as a binary

In a data mesh the more important thing to canary is a new version of the
*contract*, not a new build of the same service. order-service's response shape is
`OrderDto` ([OrderDto.java]({{ site.repo_blob }}/examples/domain-model/src/main/java/com/patterncatalyst/datamesh/domain/OrderDto.java)):

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

The mechanism is the standard Istio pair, in
[destination-rule-order-service.yaml]({{ site.repo_blob }}/k8s/istio/destination-rule-order-service.yaml) and
[virtual-service-order-service.yaml]({{ site.repo_blob }}/k8s/istio/virtual-service-order-service.yaml), applied to the `order-service`
Deployment and Service from [base]({{ site.repo_tree }}/k8s/base):

```yaml
# k8s/istio/destination-rule-order-service.yaml +
# k8s/istio/virtual-service-order-service.yaml (combined here for readability).
# Subsets select pods by the `version` label. order-service's base Deployment
# carries no such label on its own; k8s/istio/inject-order-service.yaml patches
# version: v1 onto it, and k8s/istio/order-service-v2.yaml ships a second
# Deployment labeled version: v2 — both behind the same order-service Service.
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
`VirtualService` routes a weighted split across those subsets — shipped today at
**90% v1 / 10% v2**. Shifting the canary forward means re-applying the
`VirtualService` with new weights — 90/10, then 50/50, then 0/100 — so the whole
progressive rollout is a sequence of one-line weight edits, and rolling back is the
same edit in reverse. `kubectl apply -k k8s/istio` lands all of it in one step: the
`version: v1` label patch onto the existing order-service pods, the new
`order-service-v2` Deployment, and the `DestinationRule`/`VirtualService` pair — see
[README.md]({{ site.repo_blob }}/k8s/istio/README.md) for the full file list and how to verify each piece.

One simplification: `order-service-v2` is a second Deployment, not a
`currency`-bearing rebuild. v1 and v2 run the *same image*
(`datamesh/order-service:latest`) and differ only in the `version` pod label.
A v2 with a different contract (adding `currency` to `OrderDto`) is out of scope for
the manifest level, since it is a Java and build change. The Istio routing mechanics
are identical either way: the
`DestinationRule`/`VirtualService` pair doesn't know or care what's inside the two
subsets' pods, only which `version` label each pod carries.

One known rough edge in `order-service-v2`'s wiring: its own `Deployment.spec.selector` (`{app.kubernetes.io/name: order-service, version:
v2}`) is, in raw label-selector terms, also matched by the base `order-service`
Deployment's unchanged selector (`{app.kubernetes.io/name: order-service}` alone —
left untouched because Deployment selectors are immutable against an object that may
already be running in-cluster). Kubernetes controllers only adopt pods with no existing
controller `ownerReference`, so this doesn't cause a pod-adoption conflict in
practice, but it's a looser safety margin than Istio's own `bookinfo` sample achieves
for the equivalent `reviews-v1`/`v2`/`v3` pattern (there, every version's Deployment
pins `version` in its *own* selector, making all of them mutually disjoint). See
[README.md]({{ site.repo_blob }}/k8s/istio/README.md)'s "Known, accepted caveat" section for the full reasoning.

Each weight step is safe to advance, as opposed to advancing on a timer, only if
there is something to inspect between steps. This repo's observability stack, covered
in the [observability chapter](/docs/08-observability/), provides it:
Kiali's live mesh graph would show the v1/v2 split as two weighted edges out of
`order-service`, and a Grafana dashboard sourced from the same Mimir backend would show
whether the v2 subset's error rate or latency looks any different from v1's before the
next weight bump. A canary that cannot observe its own subsets offers little
over a flag-day cutover, so the mesh's routing and the observability stack belong together.

## mTLS without application code

The mesh that routes the canary also secures it, with no application code.
When two services are both in the mesh, Istio establishes mutual TLS between their
sidecars automatically — each proxy authenticates the other, and the traffic between
them is encrypted end to end, without an application ever handling a certificate. That
is the **federated computational governance** principle made concrete: "traffic
between products is authenticated and encrypted" becomes a property the platform
enforces uniformly instead of a checklist item each team implements in its
own service. A data product's author writes no TLS code; the mesh provides it at the
network boundary once the product opts in.

{% include excalidraw.html file="06-service-mesh" alt="Diagram of meshed data-mesh services communicating over automatic mutual TLS between Istio sidecars, alongside unmeshed workloads such as Postgres and batch jobs that remain outside the mesh" caption="Figure 6.2 — mTLS between meshed services, and what stays outside the mesh" %}

mTLS does not become mandatory when two sidecars exist: Istio's
default mesh-wide mTLS mode is `PERMISSIVE`: a meshed service's sidecar accepts *both*
mTLS and plaintext connections on the same port, and Istio auto-detects which protocol
an inbound connection is using. That default suits mixed
environments such as this repo, where only some Deployments opt into the
mesh, because it lets a service be added to the mesh without every one of
its existing non-meshed callers breaking on day one. Mutual TLS only becomes
*mandatory* for a given workload once a `PeerAuthentication` resource explicitly sets
`mtls.mode: STRICT` for it.

This repo ships that policy in [peer-authentication.yaml]({{ site.repo_blob }}/k8s/istio/peer-authentication.yaml), a single
namespace-wide `PeerAuthentication` named `default` (the name Istio requires for a
namespace-scoped default policy), `mtls.mode: STRICT`, with no
`selector`, so it applies to the `datamesh` namespace as a whole. That might look like it would break the unmeshed infra sharing that
namespace (Postgres, Kafka, Apicurio), but it doesn't: `PeerAuthentication` is enforced
by the *receiving Envoy sidecar*, and a pod with no sidecar has no component capable of
enforcing — or even seeing — the policy at all. Unmeshed pods keep accepting whatever
traffic they always did, from their own operator-managed clients, entirely outside the
mesh's data path. Only pods that have the sidecar (`order-service`,
`notification-service`, `graphql-gateway`, and `order-service-v2`, once the injection
labels from the previous section take effect) are affected: those reject any inbound
connection that isn't mTLS. Istio's automatic mTLS (on by default since Istio 1.5)
handles the client side transparently — a meshed caller's sidecar originates mTLS to a
`STRICT` destination with no explicit `DestinationRule.trafficPolicy.tls` needed, which
is why neither [destination-rule-order-service.yaml]({{ site.repo_blob }}/k8s/istio/destination-rule-order-service.yaml) nor any other manifest in this repo
sets one. The practical implication for `order-service`'s canary: both the v1 and v2
subsets get encrypted, authenticated traffic from any meshed caller the moment their
sidecar comes up, with the unmeshed rest of the namespace completely unaffected by the
same `PeerAuthentication` object.

Two different things are called "namespace-wide" here, and the
next section argues against only one of them. This `PeerAuthentication`'s namespace
scope determines which workloads an *mTLS policy* applies to, and it is safe
because enforcement only engages where a sidecar already exists. That is separate
from namespace-wide *sidecar injection*, the one-label shortcut
(`istio-injection=enabled`) that would put a sidecar on *every* pod in `datamesh`,
including Postgres and batch Jobs. This repo takes the namespace-wide
`PeerAuthentication` and rejects namespace-wide injection, because only the
`PeerAuthentication` is inert in the absence of a sidecar.

## The decision: mesh selectively, not namespace-wide

Istio offers a one-label shortcut — label a namespace `istio-injection=enabled` and
every pod created there gets a sidecar automatically. One label, whole-namespace mTLS,
nothing to configure per workload. [setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh) does not take
that shortcut: the `datamesh` namespace in this stack holds workloads that do not
belong in the mesh.

Three categories of workload in this stack would break under namespace-wide
injection:

- **Batch jobs that are supposed to finish.** A meshed Job gets a sidecar that never
  exits on its own — the proxy keeps running after the job's work is done, so the pod
  never reaches a completed state and the Job hangs at `1/2` forever. Any ingestion or
  one-shot job in this namespace would hit exactly this.
- **Operator-managed infrastructure with its own TLS.** CloudNativePG's Postgres pods
  ([setup-postgres-operator.sh]({{ site.repo_blob }}/scripts/setup-postgres-operator.sh)) run their own TLS on their internal ports;
  wrapping an injected sidecar around that collides with the operator's own encrypted
  channels, and the pod crash-loops. Infrastructure that already secures itself doesn't
  want a second TLS layer forced onto it.
- **Anything where the sidecar's overhead or coupling buys nothing.** Every sidecar
  consumes CPU/memory and couples the workload's startup to the mesh control plane
  being reachable. For a pod doing no mesh-managed traffic, that is cost with no
  benefit.

There is a systemic reason beyond those three, too: with namespace-wide injection,
*every* pod creation in the namespace now depends on the sidecar-injection webhook
being reachable. If the mesh control plane has a bad moment, you cannot create a
database pod, a job, or anything else in that namespace — workloads with nothing to do
with the mesh become coupled to its health. Per-Deployment opt-in (the
`sidecar.istio.io/inject: "true"` pod-template **label**, applied by the [istio]({{ site.repo_tree }}/k8s/istio)
overlay's patches) contains that blast radius: only the workloads that declare
mesh participation depend on the mesh being up.

The trade-off: namespace-wide injection is simpler and gives blanket mTLS with
one `kubectl label`, while selective injection costs a per-Deployment decision every
time. [setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh) accepts that configuration cost to avoid
coupling Postgres, batch jobs, and anything else that doesn't belong in the mesh to the
mesh's own health.

The effect is visible in Kiali's live
traffic graph, installed by [setup-kiali.sh]({{ site.repo_blob }}/scripts/setup-kiali.sh) and covered in full in the
[observability chapter](/docs/08-observability/), only draws an edge for traffic it
observes passing through meshed sidecars. Before [istio]({{ site.repo_tree }}/k8s/istio) is applied, with
every app Deployment outside the mesh, that graph is quiet by design, reporting that nothing in `datamesh` has opted in yet. Once `order-service`
gains the injection label and the canary starts routing weight, the same graph
shows the v1/v2 split as two live edges instead of requiring inference from
`kubectl describe`.

## Why this belongs to the mesh chapter

Progressive delivery and mTLS are two sides of the same capability: a service mesh
that routes traffic between contract versions and secures it with encryption and
authentication as a platform property instead of code in each service. The
selective-injection decision in [setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh) keeps the mesh an
asset instead of a liability: it is applied to the Deployments that benefit from it,
kept away from Postgres and any batch job that would break under it.

Next, the other half of operating a mesh: matching product
capacity to demand — including scaling all the way down to zero — with KEDA.

---

*Verification status: <span class="status status--verified">verified</span>. Driven end to end on a local Kubernetes cluster (`minikube`). The injection fix is confirmed: Istio's `object.sidecar-injector.istio.io` webhook has an `objectSelector` matching `sidecar.istio.io/inject In ["true"]`, which is evaluated against pod *labels*, never annotations — so the pod-annotation form this chapter originally specified injected nothing in the unlabeled `datamesh` namespace, while the pod-template *label* form injects the native sidecar (`istio-init` + `istio-proxy`). `kubectl apply -k k8s/istio` applied cleanly: `order-service`, `notification-service`, and `graphql-gateway` came up meshed (2/2) while the operator-managed infra (Postgres, Kafka, Apicurio) stayed unmeshed. mTLS was enforced: a meshed client reached `order-service` with every request reported `connection_security_policy=mutual_tls` (20/20 `200`s), while a non-meshed plaintext client was rejected by the `STRICT` `PeerAuthentication` (`http_code=000`, connection reset), and unmeshed infra kept working. The canary split was observed at the Envoy layer as 63 requests to `v1` and 7 to `v2` out of 70 — the `VirtualService`'s 90/10 weighting. Versions moved on 2026-10-09 to Kubernetes v1.36.5, Istio 1.31.1, KEDA 2.21.0 / HTTP add-on 0.16.0, Strimzi 1.2.0 (Kafka 4.3.1), CloudNativePG 1.30.1 and the newest LGTM charts (DRQ-029); this chapter is not yet re-verified on those pins.*
