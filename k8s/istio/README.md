# k8s/istio — mesh opt-in, mTLS, and the order-service canary

The manifests that `_docs/06-progressive-delivery-mtls.md` describes. The
Istio control plane is installed cluster-wide by `scripts/setup-istio.sh`,
which leaves the `datamesh` namespace **unlabeled** for auto-injection. This
directory is the per-Deployment opt-in: applying it brings `order-service`,
`notification-service`, and `graphql-gateway` into the mesh, enforces mTLS,
and adds a v1/v2 traffic split on `order-service`.

**`inventory-service` and all infra (Postgres, Kafka, Apicurio) are
excluded.** See the header comment in `scripts/setup-istio.sh` for why
namespace-wide injection would break them: CloudNativePG's own TLS collides
with an injected sidecar. `inventory-service` has no technical reason to be
excluded; it is outside the canary example.

## Files

| File | Kind | Purpose |
|---|---|---|
| `inject-order-service.yaml` | strategic-merge patch | adds pod-template labels `sidecar.istio.io/inject: "true"` and `version: v1` to `order-service` |
| `inject-notification-service.yaml` | strategic-merge patch | adds `sidecar.istio.io/inject: "true"` to `notification-service` |
| `inject-graphql-gateway.yaml` | strategic-merge patch | adds `sidecar.istio.io/inject: "true"` to `graphql-gateway` |
| `order-service-v2.yaml` | `Deployment` | the v2 canary subset — same image as `order-service`, pod labels `version: v2` + inject |
| `peer-authentication.yaml` | `PeerAuthentication` (`security.istio.io/v1`) | namespace-wide `STRICT` mTLS for `datamesh` |
| `destination-rule-order-service.yaml` | `DestinationRule` (`networking.istio.io/v1`) | defines `v1`/`v2` subsets on `order-service`, keyed on the `version` pod label |
| `virtual-service-order-service.yaml` | `VirtualService` (`networking.istio.io/v1`) | 90/10 weighted split between the two subsets |
| `kustomization.yaml` | — | `resources: [../base, ...]` + the three patches, for a single `kubectl apply -k k8s/istio` |

## Injection opt-in: label, not annotation

Istio's sidecar-injection `MutatingWebhookConfiguration` has a webhook entry
(`object.sidecar-injector.istio.io`) whose `objectSelector` matches
`sidecar.istio.io/inject In ["true"]`. A webhook `objectSelector` is
evaluated against the admitted object's labels, never its annotations.
Because `datamesh` is unlabeled for namespace-wide injection
(`scripts/setup-istio.sh`), only a pod-template **label** can satisfy that
`objectSelector` for a given pod. That is what `inject-order-service.yaml`,
`inject-notification-service.yaml`, and `inject-graphql-gateway.yaml` add
under `spec.template.metadata.labels`.

The same key as a pod **annotation** (`spec.template.metadata.annotations`)
is never evaluated by an `objectSelector`, so it silently injects nothing in
an unlabeled namespace. On the cluster, the annotation form produced no
`istio-proxy` sidecar, while the label form did (`istio-init` + `istio-proxy`,
Istio 1.29's native-sidecar shape; check the init containers as well as
`.spec.containers`). This overlay uses the label form everywhere.

The base manifests in `k8s/base/` do not carry this label, since that would
mesh them unconditionally. This overlay's patches are the opt-in; `k8s/base`
on its own stays unmeshed.

## Apply

```bash
kubectl apply -k k8s/istio
```

This overlay includes `../base` directly, so it can be applied standalone
(it does not require `k8s/overlays/minikube` to be applied first).
Applying both is idempotent — they resolve the same base resources, and
`k8s/istio` only adds labels/new resources on top.

Because the injection label only takes effect at pod admission, existing
`order-service`/`notification-service`/`graphql-gateway` pods that were
already running before this overlay is applied do not pick up a sidecar
until they are recreated:

```bash
kubectl rollout restart deployment/order-service -n datamesh
kubectl rollout restart deployment/notification-service -n datamesh
kubectl rollout restart deployment/graphql-gateway -n datamesh
```

`order-service-v2` is a new Deployment, so its pods pick up the inject label
at creation and need no restart.

## Verifying injection

A meshed pod still reports `2/2 Ready` under Istio 1.29's native sidecars,
but the proxy is an **initContainer**, not a regular container:

```bash
kubectl get pod -n datamesh -l app.kubernetes.io/name=order-service \
  -o jsonpath='{.items[0].spec.initContainers[*].name} {.items[0].spec.containers[*].name}{"\n"}'
# expect: istio-init istio-proxy  order-service
```

`inventory-service` and the operator-managed infra pods should show no
`istio-proxy` anywhere in their spec, which confirms the opt-in is selective.

## mTLS (`peer-authentication.yaml`)

A single namespace-wide `PeerAuthentication` named `default` (the name
Istio requires for a namespace-scoped default policy to take effect), mode
`STRICT`, no selector. This is safe to apply mesh-wide in `datamesh` even
though Postgres, Kafka and Apicurio are not meshed: `PeerAuthentication` is
enforced by the receiving Envoy sidecar, and pods without a sidecar have no
enforcement point — they keep accepting their own operator's TLS/plaintext
as before. Only the three meshed Deployments (and `order-service-v2`)
are affected: they reject non-mTLS inbound traffic once their
sidecar is up. See the comment block in `peer-authentication.yaml` for the
full reasoning and the API-version check (`security.istio.io/v1` is stable,
unchanged from 1.22+, and validates against the Istio 1.31.1 CRDs).

Check with:

```bash
kubectl get peerauthentication -n datamesh
# optional, with the pinned istioctl (scripts/setup-istio.sh unpacks it):
~/.local/share/istio-1.31.1/bin/istioctl x describe pod <order-service-pod> -n datamesh
```

## The order-service canary

`destination-rule-order-service.yaml` + `virtual-service-order-service.yaml`
are the standard Istio pair against the `order-service` Service.
`order-service-v2.yaml` is the second Deployment: same image
(`datamesh/order-service:latest`), same `imagePullPolicy: IfNotPresent`, pod
labels `version: v2` + the inject label. `inject-order-service.yaml` adds
`version: v1` to the existing order-service pods so both subsets exist
side by side behind the one Service.

Current split: **90% v1 / 10% v2** (`virtual-service-order-service.yaml`).
Advancing the canary is a weight edit and re-apply (90/10, then 50/50,
then 0/100); nothing else changes. Watch it with:

```bash
kubectl get pods -n datamesh -l app.kubernetes.io/name=order-service -L version
kubectl get virtualservice,destinationrule -n datamesh
```

Once Kiali (`scripts/setup-kiali.sh`) is installed, its live traffic graph
draws the v1/v2 split as two weighted edges out of `order-service`.

### Known caveat: selector overlap between order-service and order-service-v2

`order-service`'s `Deployment.spec.selector` is not changed by this
overlay and stays `{app.kubernetes.io/name: order-service}`. Selectors are
immutable on a running Deployment, and patching one risks a `kubectl apply`
failure.
`order-service-v2`'s selector is `{app.kubernetes.io/name:
order-service, version: v2}`, a superset of the base
selector, because its pods must carry `app.kubernetes.io/name: order-service`
for the shared Service to route to them.

As label selectors, order-service's selector also matches
order-service-v2's pods. This does not cause pod adoption conflicts:
Kubernetes controllers only adopt pods and ReplicaSets that have no
controller `ownerReference`, and every `order-service-v2` pod is already
owned by its own ReplicaSet. The margin is looser than in Istio's `bookinfo`
sample, where `reviews-v1`/`v2`/`v3` each pin `version` in their own
selector so the selectors are disjoint. That form cannot be retrofitted onto
`order-service` without risking an immutable-selector apply error against an
existing Deployment.

## Validation performed

This overlay was authored without cluster access or any `kubectl`/`helm`
invocation; verification on a live cluster is separate. What was checked:

1. **YAML well-formedness** of every file in this directory via
   `python3 -c "import yaml; yaml.safe_load(...)"` (no cluster needed).
2. **Field-level schema correctness** against the Istio CRDs (re-checked
   2026-10-09 by validating the `kubectl kustomize k8s/istio` output against
   the CRDs the Istio 1.31.1 base chart renders) and the Kubernetes `apps/v1`
   `Deployment` schema: `PeerAuthentication`
   `security.istio.io/v1` `mtls.mode: STRICT`; `DestinationRule`/
   `VirtualService` `networking.istio.io/v1` shapes match the fields already
   used in the `DestinationRule` and `VirtualService` in
   `_docs/06-progressive-delivery-mtls.md`; `Deployment.spec.selector.matchLabels` is
   a subset of `spec.template.metadata.labels` in both `order-service-v2`
   (checked) and the three inject patches (which only add template labels,
   never touch `selector`).
3. **Kustomize patch targeting**: each patch file fully identifies its
   target (`apiVersion`/`kind`/`metadata.name`/`metadata.namespace`
   matching the corresponding `k8s/base/*.yaml` resource exactly), which
   kustomize v5+ resolves without a separate `target:` block. It was not
   rendered with `kubectl kustomize` or `kustomize build`, so this is
   reasoned correctness, not a verified render. Run
   `kubectl kustomize k8s/istio` (client-side templating, no cluster
   required; the same check `k8s/keda/README.md` documents) before
   `kubectl apply -k k8s/istio`.

## Unverified (needs a live cluster)

- That `kubectl apply -k k8s/istio` renders and applies cleanly end to end —
  reasoned through above, not executed.
- That the injection label produces `istio-init`/`istio-proxy` on
  these three Deployments (the label-versus-annotation behavior was verified
  on the cluster separately, but not against these manifests).
- The selector-overlap caveat above: expected to be inert in practice
  (adoption is gated on `ownerReference`), but not exercised against an
  `order-service` Deployment already running before this overlay was
  applied.
- `PeerAuthentication` `STRICT` rejecting plaintext once sidecars
  are up, and the 90/10 `VirtualService` split producing a
  roughly 90/10 request distribution. Both need a live cluster
  and traffic to confirm.
