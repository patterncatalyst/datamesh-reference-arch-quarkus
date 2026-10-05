---
title: "Elastic and resilient"
order: 8
part: Operating the mesh
description: "Scaling two real data products to demand — and to zero — with KEDA, the manifests and demos that prove it, and the recoverability Kubernetes gives a product automatically."
duration: 30 minutes
marker: "08"
---

A data product's demand is not constant. An event consumer has work only when events
are flowing; a read gateway is busy only while consumers are querying it. Provisioning
either for its peak, all the time, wastes resources; provisioning for the average means
falling over at the peak. This chapter covers the platform handling that
automatically — scaling two real products in this repo to match demand, including down
to **zero** when there is none — and the other half of operating under real conditions:
recovering when something fails. Both are **self-serve platform** capabilities: a
domain team gets elasticity and resilience from the platform instead of building them
itself.

## Scaling to demand — and to zero — with KEDA

The stock Kubernetes autoscaler (the HPA) scales on CPU and memory, which is a poor
proxy for what a data product is actually waiting on. A consumer's load is *messages
waiting to be processed*; a gateway's load is *requests arriving*. KEDA — Kubernetes
Event-Driven Autoscaling — scales on those real signals instead, and it can scale a
workload all the way to **zero** when the signal is absent, then back up the moment it
returns.

KEDA doesn't replace the HPA — it drives one. A KEDA `ScaledObject` is consumed by
the KEDA operator, which creates and manages a standard Kubernetes `HorizontalPodAutoscaler`
on the target Deployment behind the scenes, fed by an `external.metrics.k8s.io` metrics
server that KEDA itself runs. From `1` replica upward, the familiar HPA control
loop is doing the scaling, just on a Kafka-lag or HTTP-rate metric instead of CPU. The
HPA fundamentally cannot do the zero-to-one transition on its own: a
`HorizontalPodAutoscaler` has never been able to target `minReplicas: 0`, because
nothing would ever ask it to wake back up once there were no pods left to measure.
KEDA's operator sits outside that loop specifically to cover this gap. It polls the
trigger source directly — Kafka consumer-group lag, an HTTP request-rate signal — even
while the Deployment is at zero replicas, and the moment that signal crosses the
activation threshold, KEDA itself scales the Deployment from `0` to `1`. At that point
the ordinary HPA it created takes back over for `1` through `maxReplicaCount`. In
short, KEDA drives an HPA for the `1`-to-`N` range; its operator alone handles
`0`-to-`1`. Both scalers in this repo ride that same two-tier shape.

{% include excalidraw.html file="07-hpa-vs-keda" alt="Diagram comparing the stock Kubernetes HPA scaling on CPU/memory with KEDA driving an HPA from external signals (Kafka lag, HTTP rate) and handling the zero-to-one activation the HPA cannot do on its own" caption="Figure 7.1 — the stock HPA vs. KEDA's two-tier scale-to-zero model" %}

[setup-keda.sh]({{ site.repo_blob }}/scripts/setup-keda.sh) installs both pieces this build uses: KEDA core and
the KEDA HTTP add-on, pinned to `2.19.0` and `0.15.0` respectively —

```bash
helm upgrade --install keda kedacore/keda \
    --version 2.19.0 --namespace keda --create-namespace --wait

helm upgrade --install keda-add-ons-http kedacore/keda-add-ons-http \
    --version 0.15.0 --namespace keda \
    --set interceptor.replicas.waitTimeout=180s --wait
```

That `waitTimeout=180s` override is not a default left alone — the script's own
comment explains why it was raised: the add-on's default (20s) is shorter than a cold
JVM boot (image pull + Quarkus startup + `startupProbe`), so without the override, a
request to a scaled-to-zero service would 502 with "context deadline exceeded" before a
replica ever came up, and that starved KEDA of the pending-request pressure it needs to
activate promptly in the first place.

This repo wires up **two** scalers, deliberately of different kinds, on two different
real products — the manifests live in [keda]({{ site.repo_tree }}/k8s/keda) and target Deployments that already
exist in [base]({{ site.repo_tree }}/k8s/base).

### Consumer-lag scaling: `notification-service`

[consumer-scaledobject.yaml]({{ site.repo_blob }}/k8s/keda/consumer-scaledobject.yaml) is a `ScaledObject` (`keda.sh/v1alpha1`,
KEDA core) targeting the `notification-service` Deployment from
[notification-service.yaml]({{ site.repo_blob }}/k8s/base/notification-service.yaml):

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: notification-service-scaledobject
  namespace: datamesh
spec:
  scaleTargetRef:
    name: notification-service
  pollingInterval: 15
  cooldownPeriod: 120
  minReplicaCount: 0
  maxReplicaCount: 10
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: datamesh-kafka-bootstrap.datamesh.svc.cluster.local:9092
        consumerGroup: notification-service
        topic: order.placed
        lagThreshold: "5"
        offsetResetPolicy: earliest
        allowIdleConsumers: "false"
```

Every value here is sourced from a real place, not invented for the manifest:
`bootstrapServers` is the Service Strimzi creates for the Kafka cluster CR named
`datamesh` ([setup-kafka-operator.sh]({{ site.repo_blob }}/scripts/setup-kafka-operator.sh)); `topic` matches
`mp.messaging.incoming.order-placed.topic` in notification-service's
[application.properties]({{ site.repo_blob }}/examples/notification-service/src/main/resources/application.properties); and `consumerGroup` relies on a Quarkus default:
notification-service never sets `group.id`, so its runtime consumer
group id is `quarkus.application.name`, which its own [application.properties]({{ site.repo_blob }}/examples/notification-service/src/main/resources/application.properties) sets to
`notification-service`. If that property is ever overridden with an explicit
`group.id`, this `consumerGroup` value has to change with it, or the scaler watches a
group that no longer exists. `minReplicaCount: 0` is what makes this scale-to-zero:
when there's no backlog, KEDA's HPA holds the Deployment at zero replicas; once lag on
`order.placed` crosses `lagThreshold: 5`, it scales up, and once lag drains back under
threshold and stays there for `cooldownPeriod: 120` seconds, it scales back to zero.
`pollingInterval: 15` is the other half of the activation latency budget: KEDA's
external scaler polls the Kafka consumer-group offsets API for this topic/group pair
every 15 seconds while the Deployment sits at zero, so in the worst case a burst of
messages can sit for close to that long before KEDA even notices lag has crossed the
threshold — a cost accepted here in exchange for not hammering the broker's offset API
every second.

{% include excalidraw.html file="07-keda-lag" alt="Diagram of the KEDA Kafka-lag scaler polling consumer-group lag on the order.placed topic and scaling notification-service from zero to N replicas once lag crosses the threshold, then back to zero after the cooldown period" caption="Figure 7.2 — Kafka consumer-group lag driving notification-service from zero" %}

### HTTP-request scaling: `graphql-gateway`

[gateway-httpscaledobject.yaml]({{ site.repo_blob }}/k8s/keda/gateway-httpscaledobject.yaml) is an `HTTPScaledObject`
(`http.keda.sh/v1alpha1`, the HTTP add-on) targeting `graphql-gateway`:

```yaml
apiVersion: http.keda.sh/v1alpha1
kind: HTTPScaledObject
metadata:
  name: graphql-gateway-httpscaledobject
  namespace: datamesh
spec:
  hosts:
    - graphql-gateway.datamesh.svc.cluster.local
  pathPrefixes:
    - /graphql
  scaleTargetRef:
    name: graphql-gateway
    kind: Deployment
    apiVersion: apps/v1
    service: graphql-gateway
    port: 8080
  replicas:
    min: 0
    max: 10
  scalingMetric:
    requestRate:
      granularity: 1s
      targetValue: 50
      window: 1m
```

`hosts` is the in-cluster Service FQDN rather than an external hostname, because this
stack has no Ingress — the comment in the manifest is explicit about that. That has a
real operational consequence: traffic only counts toward this scaler if it goes
*through* the HTTP add-on's own interceptor proxy Service
(`keda-add-ons-http-interceptor-proxy.keda.svc.cluster.local`) with the `Host` header
set to that FQDN. A request sent directly to `graphql-gateway`'s own `ClusterIP`
Service bypasses the interceptor entirely — it is never counted, and it will not wake a
scaled-to-zero Deployment. `scaleTargetRef.service` plus exactly one of `port`/
`portName` is required by the add-on's CRD; both are set here.

The HTTP add-on is itself a small system, not a single component. It has two moving
parts, and both show up in the manifest above and in how the demo below actually
works. The **interceptor** is the proxy every request transits —
it buffers requests to a scaled-to-zero target (rather than failing them immediately)
and reports live request-rate metrics for whatever `host`/`pathPrefix` pair matches.
The **external scaler** is what the HTTPScaledObject's `scalingMetric.requestRate`
section feeds into KEDA core's own external-scaler protocol, translating the
interceptor's observed rate into the activation/deactivation decisions described
above. `pathPrefixes: [/graphql]` matters because the interceptor is matching on route,
not just host — a request to `graphql-gateway.datamesh.svc.cluster.local/q/health/ready`
through the same interceptor would not count toward this scaler's `requestRate`, since
it falls outside the declared prefix.

{% include excalidraw.html file="07-keda-http-addon" alt="Diagram of the KEDA HTTP add-on's interceptor proxy buffering requests to graphql-gateway and reporting request-rate to the external scaler, which drives the HTTPScaledObject's zero-to-N activation" caption="Figure 7.3 — the KEDA HTTP add-on's interceptor and external scaler" %}

### Why the HTTP scaler goes on the gateway, not on order-service

This is a placement decision, not an accident: `graphql-gateway`, not `order-service`,
gets the HTTP scaler. `order-service` is the Deployment that a
[progressive-delivery canary](/docs/06-progressive-delivery-mtls/) would split traffic
across by weight, and HTTP-scaling a service whose traffic is simultaneously being
split by an Istio `VirtualService` would put two control loops fighting over the same
pod count for the same reason — one deciding replica count from request volume, the
other deciding which version each request lands on. `graphql-gateway` is a natural
synchronous-read scaling target with no such conflict. Matching each scaler to the
product that actually needs it — lag-based for the consumer, request-based for the
gateway, neither on the canary candidate — is the same fitting-the-mechanism-to-the-
workload judgment this build applies elsewhere.

## How the demos drive it

[demo-keda-kafka.sh]({{ site.repo_blob }}/demos/demo-keda-kafka.sh) and [demo-keda-http.sh]({{ site.repo_blob }}/demos/demo-keda-http.sh) are the demos that
actually exercise these two `ScaledObject`s against a live cluster. Both do something
notable *before* touching a cluster at all: a static-validation pass with zero cluster
dependency.

```bash
kubectl kustomize "${K8S_DIR}/overlays/minikube" >"$APP_RENDER_LOG"
kubectl kustomize "${K8S_DIR}/keda" >"$KEDA_RENDER_LOG"
```

Both demos render [minikube]({{ site.repo_tree }}/k8s/overlays/minikube) and [keda]({{ site.repo_tree }}/k8s/keda) with `kubectl`'s bundled
kustomize and grep the output for the exact resource names, kinds, and field values the
manifests above declare (the `ScaledObject`/`HTTPScaledObject` kind, the target
Deployment name, the Kafka topic, the `replicas.min: 0` scale-to-zero setting) — proving
the manifests are structurally sound and say what the demo expects *before* it ever
needs a cluster. Only after every one of those checks passes does each script gate on
cluster reachability (`minikube status -p datamesh` and `kubectl cluster-info`) and
fail loudly, with the exact fix command, if no cluster is up.

Once a cluster is confirmed reachable, both demos follow the same shape: apply the real
overlay and scalers (`kubectl apply -k k8s/overlays/minikube`, `kubectl apply -k
k8s/keda`), record the baseline replica count, generate load from a throwaway in-cluster
pod, then poll replica count until it climbs off baseline within a budget generous
enough for a JVM cold start. [demo-keda-kafka.sh]({{ site.repo_blob }}/demos/demo-keda-kafka.sh) additionally asserts the inverse:
that replicas drain back to baseline once the burst ends and `cooldownPeriod` elapses.
That is the stronger, before/after kind of evidence — not just that replicas scaled
up, but that they scaled up *and back down*, on the real trigger, in both directions.

```bash
get_replicas() {
    kubectl get deployment notification-service -n datamesh \
        -o jsonpath='{.spec.replicas}'
}
```

The budgets each script polls against aren't round numbers picked for convenience —
each is sized against a concrete, named cost in the path it's measuring:

- [demo-keda-http.sh]({{ site.repo_blob }}/demos/demo-keda-http.sh) polls for up to `SCALE_UP_BUDGET=240` seconds after its load
  burst, in five-second increments, before failing with a message that points at the
  exact things to check (interceptor logs, the `Host` header match, the
  `HTTPScaledObject`'s own status).
- [demo-keda-kafka.sh]({{ site.repo_blob }}/demos/demo-keda-kafka.sh) polls a `SCALE_UP_BUDGET=180` seconds for the climb off
  baseline, then a separate `SCALE_DOWN_BUDGET=300` seconds — in ten-second
  increments — for the drain back to baseline. That drain budget is deliberately
  wider than `cooldownPeriod: 120`, to leave margin for KEDA's own `pollingInterval`
  and the HPA's downscale stabilization window on top of the manifest's nominal
  cooldown.
- The 180s scale-up budget has to absorb a chain of sequential, not parallel,
  requests: the load generator fires 60 requests one after another, and each one, in
  the worst case, can take as long as `order-service`'s synchronous gRPC call to
  `inventory-service` is willing to wait before giving up. `InventoryClient`'s
  `CALL_TIMEOUT` is 3 seconds, so a budget that only accounted for fast successful
  calls would be too tight the moment any of those 60 requests hits a slow path.

Driving load for [demo-keda-kafka.sh]({{ site.repo_blob }}/demos/demo-keda-kafka.sh) means POSTing to the real `/orders` endpoint on
`order-service`, which performs a synchronous gRPC `CheckStock` against
`inventory-service` before it publishes `order.placed`. That path is wired end-to-end
in-cluster: `order-service` targets `inventory-service` on the canonical gRPC port
`9000` (env-overridable via `INVENTORY_GRPC_HOST` / `INVENTORY_GRPC_PORT`), and
`inventory-service` has its own Deployment + Service under [base]({{ site.repo_tree }}/k8s/base). The packaged
image also trusts the Avro event package, so the publish actually lands. A successful
`POST /orders` therefore emits a real `order.placed` event, giving the KEDA Kafka-lag
scaler genuine application traffic to act on. The demo drives the real endpoint rather
than bypassing it with a raw Kafka producer, so any scale-up you observe is caused by
the actual order flow. The scaler and manifest are correct and complete; a live
scale-up on a real cluster remains the thing to confirm (see the verification note
below).

{% include excalidraw.html file="07-keda-http" alt="Diagram of demo-keda-http.sh driving a request burst through the interceptor proxy with the Host header set, polling graphql-gateway's replica count until it climbs off baseline within the 240-second scale-up budget" caption="Figure 7.4 — demo-keda-http.sh: burst load through the interceptor, polled against the scale-up budget" %}

## Resilience: recoverability as a platform property

Scaling is half of operating under real conditions; the other half is what happens when
something breaks, and on a real system something eventually does. The cloud-native
answer is not to prevent every failure — it is to make recovery cheap and automatic.
Kubernetes gives a Deployment a great deal of this automatically: a crashed container is
restarted according to its `restartPolicy`, a bad rollout can be rolled back, a node's
pods are rescheduled elsewhere, and the reconciliation loop continuously drives the
cluster back toward the declared spec rather than letting it drift. A service deployed
this way is recoverable by construction — the platform brings it back without a human
in the loop.

In this stack specifically, that property compounds across pieces already described in
earlier chapters: CloudNativePG knows how to recover the Postgres cluster it manages,
Strimzi does the same for Kafka, and a consumer that was briefly scaled to zero or
simply down for a moment can catch up on exactly the backlog it missed the moment it
comes back — because KEDA's `minReplicaCount: 0` is not a failure state, it reflects
the system correctly determining there is nothing to do right now. `order-service`'s
own health
probes (`startupProbe`/`readinessProbe`/`livenessProbe` against `quarkus-smallrye-
health`'s `/q/health/started`, `/q/health/ready`, `/q/health/live`, all present in
[order-service.yaml]({{ site.repo_blob }}/k8s/base/order-service.yaml)) are what let the platform tell "still starting" apart
from "actually broken," so it restarts the right thing instead of killing a pod that
just needs another few seconds to boot.

One asymmetry here: `graphql-gateway` does not depend on
`quarkus-smallrye-health` (its [pom.xml]({{ site.repo_blob }}/examples/graphql-gateway/pom.xml) pulls `quarkus-smallrye-graphql`,
`quarkus-rest-client[-jackson]`, `quarkus-grpc`, and `quarkus-arc`, but not the health
extension), so `/q/health/*` would 404 on it. [graphql-gateway.yaml]({{ site.repo_blob }}/k8s/base/graphql-gateway.yaml) falls
back to a `tcpSocket` probe on its HTTP port instead — a weaker check that proves the
listener is up but not that GraphQL execution actually works. That gap is documented
plainly in [README.md]({{ site.repo_blob }}/k8s/README.md) rather than hidden, and the fix (add the health extension,
switch the probes to `httpGet` on `/q/health/*`) is a one-dependency change outside this
chapter's scope.

A single-node minikube cluster, which is what this whole build runs on, makes
recoverability both more visible and more demanding than a multi-node cluster would —
there's nowhere for the platform to shift a workload *to* when the one node has a bad
moment, which concentrates exactly the failure modes a larger cluster would spread out
and absorb. The conceptual point still holds on one node: a platform that continuously
reconciles toward declared state recovers more reliably than one held together by
manual intervention.

## Elastic and resilient, from the platform

Elasticity and recoverability look the same from a domain team's point of view:
capabilities the self-serve platform provides so individual products don't each have to
solve them — `notification-service` scales to its backlog because KEDA scales it, and
`order-service` survives a crashed pod because Kubernetes reconciles it back. The
domain declares what it wants, a `ScaledObject` or a set of health probes, and the
platform delivers the runtime behavior: the self-serve principle applied to a
product's *operational* properties, not just its deployment.

Next, the capability that makes all of this observable: seeing what the mesh is
actually doing — its metrics, its traces, and the live view of traffic moving between
products.

---

*Verification status: <span class="status status--verified">verified</span>. Observed directly on the minikube substrate: both ScaledObjects drive their targets to zero at rest (`notification-service` and `graphql-gateway` sit at 0 replicas), and `notification-service` scales up from zero on real Kafka consumer-group lag — placing valid orders emits `order.placed`, lag crosses the threshold, and KEDA activates the ScaledObject and scales the deployment 0→1. Driving this surfaced a bug in `demo-keda-kafka.sh` (it posted orders for an unseeded SKU, so order placement 409'd and produced no events), now fixed by seeding stock before the burst. The KEDA HTTP add-on scaler (scale-from-zero on request rate) was not separately confirmed in this pass.*
