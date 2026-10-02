# k8s/istio — mesh opt-in, mTLS, and the order-service canary

Part of the minikube substrate, and the manifests `_docs/06-progressive-delivery-mtls.md`
describes. The Istio control plane itself is installed cluster-wide by
`scripts/setup-istio.sh` (step 9a) with the `datamesh` namespace deliberately
**unlabeled** for auto-injection. This directory is the per-Deployment
opt-in step 9a's own design defers to: applying it is what actually brings
`order-service`, `notification-service`, and `graphql-gateway` into the
mesh, enforces mTLS, and wires up a v1/v2 traffic split on `order-service`.

**`inventory-service` and all infra (Postgres, Kafka, Apicurio) are
deliberately left out** — see `scripts/setup-istio.sh`'s header comment for
why namespace-wide injection would break them (Job-style churn isn't a
concern for Deployments, but CloudNativePG's own TLS colliding with an
injected sidecar is; inventory-service is simply out of scope for this
chapter's canary, not excluded for a technical reason).

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

## The mechanism this overlay corrects: label, not annotation

Istio's sidecar-injection `MutatingWebhookConfiguration` has a webhook entry
(`object.sidecar-injector.istio.io`) whose `objectSelector` matches
`sidecar.istio.io/inject In ["true"]`. **A webhook `objectSelector` is
evaluated against the admitted object's LABELS, never its annotations.**
With `datamesh` intentionally left unlabeled for namespace-wide injection
(`scripts/setup-istio.sh`), the *only* thing that can satisfy that
`objectSelector` for a given pod is a pod-template **label** matching it —
which is exactly what `inject-order-service.yaml`,
`inject-notification-service.yaml`, and `inject-graphql-gateway.yaml` add,
under `spec.template.metadata.labels`.

The earlier version of this repo (and of `_docs/06-progressive-delivery-mtls.md`)
specified the same key as a pod **annotation**
(`spec.template.metadata.annotations`). That form is never evaluated by an
`objectSelector`, so it silently injects nothing in an unlabeled namespace —
confirmed live on the cluster: the annotation form produced no `istio-proxy`
sidecar, while the label form did (`istio-init` + `istio-proxy`, Istio 1.29's
native-sidecar shape — see the init containers, not just
`.spec.containers`). This overlay uses the label form everywhere.

The base manifests in `k8s/base/` are **not** changed to carry this label —
that would mesh them unconditionally. This overlay's patches are the opt-in;
`k8s/base` on its own stays fully unmeshed.

## Apply

```bash
kubectl apply -k k8s/istio
```

This overlay includes `../base` directly, so it can be applied standalone
(it does not require `k8s/overlays/minikube` to have been applied first).
Applying both is idempotent — they resolve the same base resources, and
`k8s/istio` only adds labels/new resources on top.

Because the injection label only takes effect at pod admission, existing
`order-service`/`notification-service`/`graphql-gateway` pods that were
already running before this overlay is applied do **not** pick up a sidecar
until something recreates them:

```bash
kubectl rollout restart deployment/order-service -n datamesh
kubectl rollout restart deployment/notification-service -n datamesh
kubectl rollout restart deployment/graphql-gateway -n datamesh
```

(`order-service-v2` is a brand-new Deployment, so its first-ever pods are
created fresh and pick up the inject label immediately — no restart needed
for it.)

## Verifying injection actually happened

A meshed pod still reports `2/2 Ready` under Istio 1.29's native sidecars,
but the proxy is an **initContainer**, not a regular container:

```bash
kubectl get pod -n datamesh -l app.kubernetes.io/name=order-service \
  -o jsonpath='{.items[0].spec.initContainers[*].name} {.items[0].spec.containers[*].name}{"\n"}'
# expect: istio-init istio-proxy  order-service
```

`inventory-service` and the operator-managed infra pods should show no
`istio-proxy` anywhere in their spec — confirming the opt-in stayed
selective.

## mTLS (`peer-authentication.yaml`)

A single namespace-wide `PeerAuthentication` named `default` (the name
Istio requires for a namespace-scoped default policy to take effect), mode
`STRICT`, no selector. This is safe to apply mesh-wide in `datamesh` even
though Postgres/Kafka/Apicurio aren't meshed: `PeerAuthentication` is
enforced by the receiving Envoy sidecar, and pods without a sidecar have no
enforcement point — they keep accepting their own operator's TLS/plaintext
exactly as before. Only the three meshed Deployments (and `order-service-v2`)
are actually affected: they reject non-mTLS inbound traffic once their
sidecar is up. See the comment block in `peer-authentication.yaml` for the
full reasoning and the Istio 1.29 API-version check (`security.istio.io/v1`
is stable, unchanged from 1.22+).

Check with:

```bash
kubectl get peerauthentication -n datamesh
istioctl authn tls-check order-service.datamesh.svc.cluster.local   # if istioctl is available
```

## The order-service canary

`destination-rule-order-service.yaml` + `virtual-service-order-service.yaml`
are the standard Istio trio against the real `order-service` Service — no
longer illustrative. `order-service-v2.yaml` is the second Deployment the
chapter said didn't exist yet: same image
(`datamesh/order-service:latest`), same `imagePullPolicy: IfNotPresent`, pod
labels `version: v2` + the inject label. `inject-order-service.yaml` adds
`version: v1` to the existing order-service pods so both subsets exist
side by side behind the one Service.

Current split: **90% v1 / 10% v2** (`virtual-service-order-service.yaml`).
Advancing the canary is a weight edit and re-apply — 90/10, then 50/50,
then 0/100 — nothing else changes. Watch it with:

```bash
kubectl get pods -n datamesh -l app.kubernetes.io/name=order-service -L version
kubectl get virtualservice,destinationrule -n datamesh
```

Once Kiali (`scripts/setup-kiali.sh`) is installed, its live traffic graph
draws the v1/v2 split as two weighted edges out of `order-service` — the
same graph the chapter's "decision" section points to.

### Known, accepted caveat: selector overlap between order-service and order-service-v2

`order-service`'s `Deployment.spec.selector` is **not** touched by this
overlay (it stays `{app.kubernetes.io/name: order-service}` — selectors are
immutable on an object that may already be running in-cluster, and patching
it here risks a `kubectl apply` failure against a live Deployment).
`order-service-v2`'s own selector is `{app.kubernetes.io/name:
order-service, version: v2}` — necessarily a superset match of the base
selector, because its pods must carry `app.kubernetes.io/name: order-service`
for the shared Service to route to them.

In raw label-selector terms this means order-service's selector also
"matches" order-service-v2's pods. This does **not** cause an actual
pod-adoption fight: Kubernetes controllers only adopt pods/ReplicaSets that
have no existing controller `ownerReference`, and every `order-service-v2`
pod is already owned by its own ReplicaSet/Deployment. It is, however, a
looser safety margin than Istio's own `bookinfo` sample achieves (there,
`reviews-v1`/`v2`/`v3` each pin `version` in their *own* selector too, so
the selectors are fully disjoint rather than merely owner-ref-safe) — that
stronger form isn't retrofittable onto `order-service` here without risking
an immutable-selector apply error against a Deployment this repo's earlier
steps may have already created live.

## Validation performed for this step

No cluster access and no `kubectl`/`helm` invocation of any kind were used
while authoring this overlay (explicitly out of scope for this step — the
caller verifies on the live cluster separately). What *was* checked:

1. **YAML well-formedness** of every file in this directory via
   `python3 -c "import yaml; yaml.safe_load(...)"` (no cluster needed).
2. **Field-level schema correctness**, reasoned against the actual Istio
   1.29 CRDs and Kubernetes `apps/v1` `Deployment` schema: `PeerAuthentication`
   `security.istio.io/v1` `mtls.mode: STRICT`; `DestinationRule`/
   `VirtualService` `networking.istio.io/v1` shapes match the fields already
   used in `_docs/06-progressive-delivery-mtls.md`'s own (now real)
   DestinationRule/VirtualService; `Deployment.spec.selector.matchLabels` is
   a subset of `spec.template.metadata.labels` in both `order-service-v2`
   (checked) and the three inject patches (which only add template labels,
   never touch `selector`).
3. **Kustomize patch targeting**: each patch file fully identifies its
   target (`apiVersion`/`kind`/`metadata.name`/`metadata.namespace`
   matching the corresponding `k8s/base/*.yaml` resource exactly), which
   kustomize v5+ resolves without a separate `target:` block — not run
   through the `kubectl kustomize`/`kustomize build` binary itself in this
   step (that's a `kubectl` invocation, out of scope here), so this is
   reasoned correctness, not a verified render. The caller should run
   `kubectl kustomize k8s/istio` (pure client-side templating, no cluster
   required — same check `k8s/keda/README.md` documents) before
   `kubectl apply -k k8s/istio`.

## Unverified (left for the caller, on the live cluster)

- That `kubectl apply -k k8s/istio` renders and applies cleanly end to end —
  reasoned through above, not executed.
- That the injection label actually produces `istio-init`/`istio-proxy` on
  these three specific Deployments (the CRITICAL FINDING this overlay is
  built on was verified live separately, but not against these exact
  manifests).
- The selector-overlap caveat above: expected to be inert in practice
  (owner-ref-gated adoption), but not exercised against a real
  `order-service` Deployment that was already running before this overlay
  was applied.
- `PeerAuthentication` `STRICT` actually rejecting plaintext once sidecars
  are up, and the 90/10 `VirtualService` split actually producing a
  roughly-90/10 observed request distribution — both need a live cluster
  and traffic to confirm.
