---
title: "Progressive delivery and mTLS"
order: 7
part: Operating the mesh
description: "Evolving a data product's contract in the open with an Istio v1→v2 canary over the real mesh substrate, and the decision to mesh selectively rather than enable sidecar injection namespace-wide."
duration: 30 minutes
marker: "07"
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

Installing the mesh, opting a service into it, enforcing mTLS, and routing a v1/v2
canary split are now all real, runnable substrate in this repo: `scripts/setup-istio.sh`
installs Istio via Helm, `k8s/base/order-service.yaml` is the Deployment the canary
targets, and `k8s/istio/` — mirroring `k8s/keda/`'s shape as a sibling overlay directory
with its own `kustomization.yaml` — holds the injection patches, the namespace-wide
`PeerAuthentication`, the `order-service-v2` Deployment, and the `DestinationRule`/
`VirtualService` pair that splits traffic between the two. Applying that overlay
(`kubectl apply -k k8s/istio`) is the opt-in this chapter describes, start to finish.

The one thing still conceptual: a genuinely different `v2` *build* of order-service —
one that actually adds a `currency` field to `OrderDto` and serves it. `order-service-v2`
runs the *same image* as `order-service`, distinguished only by a `version: v2` pod
label, so the exercise stays focused on the traffic-management and mTLS mechanism
rather than a second image pipeline. That simplification, and why it doesn't change the
Istio mechanics, is covered later in this chapter.

`k8s/README.md`'s own "Mesh (Istio) decision" section states the current ground truth
plainly: Istio + Kiali are installed cluster-wide by 9a, but the `datamesh` namespace is
**not** labeled for sidecar auto-injection, so mesh membership is per-Deployment opt-in
rather than automatic for everything in the namespace. `k8s/base/order-service.yaml`,
`notification-service.yaml`, and `graphql-gateway.yaml` all still ship unmeshed by
default — the `k8s/istio/` overlay is what brings them in, and it does so without
editing `k8s/base` itself. The architecture default keeps Istio and Kiali installed but
makes mesh membership a per-service opt-in, rather than either ripping the mesh out or
defaulting every workload into it. This chapter is about what changes, and what doesn't,
the day a team decides a specific product is ready to opt in — and, as of this revision,
what opting in actually required to work.

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
`istiod`'s injection webhook actually matches pods. `istiod` registers a
`MutatingWebhookConfiguration` that intercepts Pod admission cluster-wide; its
`object.sidecar-injector.istio.io` webhook entry carries an `objectSelector` matching
`sidecar.istio.io/inject In ["true"]`. A Kubernetes **webhook `objectSelector` is
always evaluated against the admitted object's *labels* — never its annotations.**
That's not an Istio-specific quirk; it's how `objectSelector` works for any
`MutatingWebhookConfiguration`. With the `datamesh` namespace deliberately left
unlabeled for namespace-wide injection (the next section covers why), the *only* way
left to satisfy that `objectSelector` for a given pod is a pod-template label matching
it exactly. The same key set as an **annotation** is never evaluated by an
`objectSelector` at all, so it silently injects nothing — no error, no event, the pod
just comes up unmeshed, looking identical to any other unmeshed pod.

This was confirmed live on the cluster: setting `sidecar.istio.io/inject: "true"` as a
pod-template **annotation** on a Deployment in the unlabeled `datamesh` namespace
produced no sidecar at all. Setting the exact same key as a pod-template **label**
instead did inject the native sidecar (`istio-init` + `istio-proxy`), with no other
change. `k8s/base/order-service.yaml` as shipped carries neither — its own header
comment explains the label-vs-annotation distinction and points at the
`k8s/istio/` overlay (`inject-order-service.yaml`) as where the opt-in label actually
gets added, without editing the base manifest itself. The same pattern applies to
`notification-service` and `graphql-gateway` via their own patch files in that overlay.

That label takes effect at Pod admission, not at `kubectl apply` time on the
Deployment. When a new Pod is created, the webhook's `objectSelector` is evaluated
against that Pod's labels and, if it matches, the webhook mutates the Pod spec on the
way in to add the `istio-proxy` sidecar before the API server ever persists the
object. One consequence follows directly: the label only affects newly admitted pods.
Adding it to a Deployment that already has running pods changes nothing about those
existing pods — they keep running unmeshed until something recreates them, whether
that's `kubectl rollout restart deployment/order-service -n datamesh` or a routine
eviction. `k8s/istio/README.md` calls this out explicitly, since `kubectl apply -k
k8s/istio` only changes the Deployment objects' pod *templates* — it doesn't by itself
force existing pods to roll. This is the same two-step shape every Kubernetes
mutating-admission mechanism has: label the template, then force a new generation of
pods to pick it up. A pod that keeps running unmeshed right after the label is added
has not failed — it is simply waiting for that rollout.

Istio 1.29+ (the version this script pins) uses **native sidecars**: `istio-proxy`
runs as an `initContainer` with `restartPolicy: Always`, not as a second ordinary
container. This changes how you check mesh membership. A meshed pod still shows
`2/2 Ready` in `kubectl get pods`, but a membership check that only inspects
`.spec.containers` will miss it; it has to look at `.spec.initContainers` too. Native
sidecars also change pod startup ordering: because `istio-proxy` is an init
container — one with `restartPolicy: Always`, so it never blocks the pod the way a
normal init container would — kubelet starts it before the application container. The
proxy's own readiness gate then holds the Pod back from `Ready` until the proxy itself
has established its listeners, so a meshed pod's `startupProbe` is effectively racing
against the proxy coming up too, not just the JVM.

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

The mechanism is the standard Istio trio, and these are now real files —
`k8s/istio/destination-rule-order-service.yaml` and
`k8s/istio/virtual-service-order-service.yaml` — against the real `order-service`
Deployment/Service from `k8s/base/`:

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
**90% v1 / 10% v2**. Shifting the canary forward is just re-applying the
`VirtualService` with new weights — 90/10, then 50/50, then 0/100 — so the whole
progressive rollout is a sequence of one-line weight edits, and rolling back is the
same edit in reverse. `kubectl apply -k k8s/istio` lands all of it in one step: the
`version: v1` label patch onto the existing order-service pods, the new
`order-service-v2` Deployment, and the `DestinationRule`/`VirtualService` pair — see
`k8s/istio/README.md` for the full file list and how to verify each piece.

One simplification, carried over from the pattern this build mirrors, and the reason
`order-service-v2` is a true second Deployment rather than a `currency`-bearing
rebuild: v1 and v2 run the *same image* (`datamesh/order-service:latest`), with only
the `version` pod label differing, rather than two images from two separate builds.
A genuinely different v2 contract (adding `currency` to `OrderDto`) is out of scope for
this manifest-level step — it's a Java/build change, not a Kubernetes-manifest one —
but the Istio routing mechanics shown here are identical either way: the
`DestinationRule`/`VirtualService` pair doesn't know or care what's inside the two
subsets' pods, only which `version` label each pod carries.

One known rough edge in `order-service-v2`'s wiring, worth naming rather than hiding:
its own `Deployment.spec.selector` (`{app.kubernetes.io/name: order-service, version:
v2}`) is, in raw label-selector terms, also matched by the base `order-service`
Deployment's unchanged selector (`{app.kubernetes.io/name: order-service}` alone —
left untouched because Deployment selectors are immutable against an object that may
already be running in-cluster). Kubernetes controllers only adopt pods with no existing
controller `ownerReference`, so this doesn't cause an actual pod-adoption fight in
practice, but it's a looser safety margin than Istio's own `bookinfo` sample achieves
for the equivalent `reviews-v1`/`v2`/`v3` pattern (there, every version's Deployment
pins `version` in its *own* selector, making all of them mutually disjoint). See
`k8s/istio/README.md`'s "Known, accepted caveat" section for the full reasoning.

What makes each weight step safe to advance, rather than a blind five-minute timer, is
having something to look at between steps. This repo's observability substrate — the
[next-but-one chapter](/docs/08-observability/) covers it in full — is exactly that:
Kiali's live mesh graph would show the v1/v2 split as two weighted edges out of
`order-service`, and a Grafana dashboard sourced from the same Mimir backend would show
whether the v2 subset's error rate or latency looks any different from v1's before the
next weight bump. A canary with no way to observe its own subsets provides little
benefit over a single flag-day cutover; the mesh's routing and this repo's observability
stack are meant to be read together, not in isolation.

## mTLS without application code

The same mesh that routes the canary also secures it, with no code written for it.
When two services are both in the mesh, Istio establishes mutual TLS between their
sidecars automatically — each proxy authenticates the other, and the traffic between
them is encrypted end to end, without an application ever handling a certificate. That
is the **federated computational governance** principle made concrete: "traffic
between products is authenticated and encrypted" becomes a property the platform
enforces uniformly, not a checklist item each team implements (or forgets to) in its
own service. A data product's author writes no TLS code; the mesh provides it at the
network boundary the moment the product opts in.

{% include excalidraw.html file="06-service-mesh" alt="Diagram of meshed data-mesh services communicating over automatic mutual TLS between Istio sidecars, alongside unmeshed workloads such as Postgres and batch jobs that remain outside the mesh" caption="Figure 6.2 — mTLS between meshed services, and what deliberately stays outside the mesh" %}

It's easy to assume mTLS becomes mandatory the instant two sidecars exist, but Istio's
default mesh-wide mTLS mode is `PERMISSIVE`: a meshed service's sidecar accepts *both*
mTLS and plaintext connections on the same port, and Istio auto-detects which protocol
an inbound connection is using. That default exists specifically for mixed
environments — exactly this repo's situation, where only some Deployments opt into the
mesh at a time — because it lets a service be added to the mesh without every one of
its existing non-meshed callers breaking on day one. Mutual TLS only becomes
*mandatory* for a given workload once a `PeerAuthentication` resource explicitly sets
`mtls.mode: STRICT` for it.

This repo now ships exactly that policy: `k8s/istio/peer-authentication.yaml`, a single
namespace-wide `PeerAuthentication` named `default` (the name Istio requires for a
namespace-scoped default policy to take effect), `mtls.mode: STRICT`, with no
`selector` — so it's scoped to the `datamesh` namespace as a whole, not to an explicit
list of workloads. That might look like it would break the unmeshed infra sharing that
namespace (Postgres, Kafka, Apicurio), but it doesn't: `PeerAuthentication` is enforced
by the *receiving Envoy sidecar*, and a pod with no sidecar has no component capable of
enforcing — or even seeing — the policy at all. Unmeshed pods keep accepting whatever
traffic they always did, from their own operator-managed clients, entirely outside the
mesh's data path. Only pods that actually have the sidecar (`order-service`,
`notification-service`, `graphql-gateway`, and `order-service-v2`, once the injection
labels from the previous section take effect) are affected: those reject any inbound
connection that isn't mTLS. Istio's automatic mTLS (on by default since Istio 1.5)
handles the client side transparently — a meshed caller's sidecar originates mTLS to a
`STRICT` destination with no explicit `DestinationRule.trafficPolicy.tls` needed, which
is why neither `destination-rule-order-service.yaml` nor any other manifest in this repo
sets one. The practical implication for `order-service`'s canary: both the v1 and v2
subsets get encrypted, authenticated traffic from any meshed caller the moment their
sidecar comes up, with the unmeshed rest of the namespace completely unaffected by the
same `PeerAuthentication` object.

Worth being precise about which "namespace-wide" is being discussed here, because the
next section argues *against* a different one: this `PeerAuthentication`'s namespace
scope is about which workloads an *mTLS policy* applies to, and it's safe exactly
because enforcement only ever engages where a sidecar already exists. That's a separate
axis from namespace-wide *sidecar injection* — the one-label shortcut
(`istio-injection=enabled`) that would put a sidecar on *every* pod in `datamesh`,
including Postgres and batch Jobs, whether or not anything scopes the resulting mTLS
policy. This repo takes the namespace-wide `PeerAuthentication` and rejects
namespace-wide injection at the same time, because only the first one is inert in the
absence of a sidecar — the second isn't.

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
`sidecar.istio.io/inject: "true"` pod-template **label**, applied by the `k8s/istio/`
overlay's patches) contains that blast radius: only the workloads that actually declare
mesh participation depend on the mesh being up.

The trade-off is real: namespace-wide injection is simpler and gives blanket mTLS with
one `kubectl label`, while selective injection costs a per-Deployment decision every
time. `scripts/setup-istio.sh` takes that configuration cost deliberately, to avoid
coupling Postgres, batch jobs, and anything else that doesn't belong in the mesh to the
mesh's own health.

Seeing the effect of that decision doesn't require guessing at pod specs: Kiali's live
traffic graph, installed by `scripts/setup-kiali.sh` and covered in full in the
[observability chapter](/docs/08-observability/), only draws an edge for traffic it
actually observes passing through meshed sidecars. Before `k8s/istio` is applied, with
every app Deployment outside the mesh, that graph is quiet by design — not broken, just
accurately reporting that nothing in `datamesh` has opted in yet. Once `order-service`
gains the injection label and the canary starts routing real weight, the same graph
shows the v1/v2 split as two live edges instead of requiring inference from
`kubectl describe`.

## Why this belongs to the mesh chapter

Progressive delivery and mTLS are two sides of the same capability: a service mesh
that routes traffic between contract versions and secures it with encryption and
authentication as a platform property, not a line item in each service's code. The
selective-injection decision in `scripts/setup-istio.sh` is what keeps the mesh an
asset here rather than a liability — applied to the Deployments that benefit from it,
kept away from Postgres and any batch job that would break under it.

Next, the other half of operating a mesh under real conditions: matching product
capacity to demand — including scaling all the way down to zero — with KEDA.

---

*Verification status: <span class="status status--verified">verified</span>. Driven end to end on the minikube substrate. The injection fix is confirmed: Istio's `object.sidecar-injector.istio.io` webhook has an `objectSelector` matching `sidecar.istio.io/inject In ["true"]`, which is evaluated against pod *labels*, never annotations — so the pod-annotation form this chapter originally specified injected nothing in the unlabeled `datamesh` namespace, while the pod-template *label* form injects the native sidecar (`istio-init` + `istio-proxy`). `kubectl apply -k k8s/istio` applied cleanly: `order-service`, `notification-service`, and `graphql-gateway` came up meshed (2/2) while the operator-managed infra (Postgres, Kafka, Apicurio) stayed unmeshed. mTLS was enforced: a meshed client reached `order-service` with every request reported `connection_security_policy=mutual_tls` (20/20 `200`s), while a non-meshed plaintext client was rejected by the `STRICT` `PeerAuthentication` (`http_code=000`, connection reset), and unmeshed infra kept working. The canary split was observed at the Envoy layer as 63 requests to `v1` and 7 to `v2` out of 70 — the `VirtualService`'s 90/10 weighting.*
