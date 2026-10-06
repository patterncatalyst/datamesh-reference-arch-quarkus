# k8s/keda — KEDA scalers

Part of the local Kubernetes platform. This directory holds the two KEDA scaler manifests that turn the
platform installed by `scripts/setup-keda.sh` into autoscaling for the
Deployments in `k8s/base/notification-service.yaml` and
`k8s/base/graphql-gateway.yaml`.

This directory contains the scalers only. The load-generating demos that
exercise them are `demos/demo-keda-kafka.sh` and `demos/demo-keda-http.sh`.

## Files

| File | Kind | Targets | Trigger |
|---|---|---|---|
| `consumer-scaledobject.yaml` | `ScaledObject` (`keda.sh/v1alpha1`, KEDA core) | Deployment `notification-service` | Kafka consumer-group lag on topic `order.placed` |
| `gateway-httpscaledobject.yaml` | `HTTPScaledObject` (`http.keda.sh/v1alpha1`, KEDA HTTP add-on **0.15.0**) | Deployment/Service `graphql-gateway` | HTTP request rate |
| `kustomization.yaml` | — | groups both for `kubectl apply -k k8s/keda` | — |

## Prerequisites

Both KEDA core and the HTTP add-on must already be installed with
`./scripts/setup-keda.sh`, which installs both with helm:

- KEDA core **2.19.0**.
- KEDA HTTP add-on **0.15.0**. v0.14.0 shipped an interceptor panic on
  POST forwarding (kedacore/http-add-on#1668, "invalid concurrent Body.Read
  call"); 0.15.0 fixes it and adds HTTP/2 and gRPC scaling.
- `interceptor.replicas.waitTimeout` is raised from the 20s default to 180s.
  The interceptor holds a request while a scaled-from-zero workload gets a
  Ready replica, and a cold JVM boot (KEDA activation, image pull, Quarkus
  start, startupProbe) exceeds 20s. With the default, requests fail with
  502 "context deadline exceeded" before a backend exists.

The target Deployments/Services must already exist
(`kubectl apply -k k8s/overlays/minikube`).

## Apply

```bash
kubectl apply -k k8s/keda
```

## consumer-scaledobject.yaml — observe scale 0→N on Kafka lag

Values used (see the comment block in the file for full sourcing):

- `bootstrapServers: datamesh-kafka-bootstrap.datamesh.svc.cluster.local:9092`
  (Strimzi Kafka CR `datamesh` in namespace `datamesh`, from
  `scripts/setup-kafka-operator.sh`)
- `consumerGroup: notification-service` (Quarkus's default consumer group
  id = `quarkus.application.name`, which notification-service sets to
  `notification-service`; it does not set an explicit `group.id`)
- `topic: order.placed`
- `lagThreshold: "5"`, `minReplicaCount: 0`, `maxReplicaCount: 10`,
  `pollingInterval: 15`, `cooldownPeriod: 120`

To observe scale-from-zero, run `demos/demo-keda-kafka.sh` or watch manually:

```bash
# Watch replica count
kubectl get deployment notification-service -n datamesh -w

# Watch the HPA KEDA creates for this ScaledObject
kubectl get hpa -n datamesh -w

# Watch the ScaledObject's own status/conditions
kubectl describe scaledobject notification-service-scaledobject -n datamesh

# Produce order.placed records faster than notification-service can consume
# them (demo-keda-kafka.sh automates this) and watch replicas
# climb from 0 as lag exceeds lagThreshold=5, then fall back to 0 after
# cooldownPeriod=120s of lag staying below threshold.
```

## gateway-httpscaledobject.yaml — observe scale 0→N on HTTP load

Values used:

- `scaleTargetRef`: Deployment `graphql-gateway`, Service `graphql-gateway`,
  port `8080` (matches `k8s/base/graphql-gateway.yaml` exactly)
- `hosts: [graphql-gateway.datamesh.svc.cluster.local]`,
  `pathPrefixes: [/graphql]` — routing keys the interceptor proxy matches on
  (no Ingress/external hostname exists yet in this stack)
- `replicas.min: 0`, `replicas.max: 10`
- `scalingMetric.requestRate.targetValue: 50` (per-pod requests/window
  before KEDA scales up), `window: 1m`, `granularity: 1s`

To observe scale-from-zero, run `demos/demo-keda-http.sh` or watch manually:

```bash
# Watch replica count
kubectl get deployment graphql-gateway -n datamesh -w

# Watch the HTTPScaledObject's status (interceptor/target workload)
kubectl get httpscaledobject graphql-gateway-httpscaledobject -n datamesh

# Requests must go through the KEDA HTTP add-on's interceptor proxy Service
# in the keda namespace, with the Host header set to the hosts entry above
# (demo-keda-http.sh automates this), e.g.:
kubectl run -n datamesh curl-test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -H "Host: graphql-gateway.datamesh.svc.cluster.local" \
  http://keda-add-ons-http-interceptor-proxy.keda.svc.cluster.local:8080/graphql
```

## Static validation

These checks ran without a live cluster (`kubectl config
current-context` reported no context, and both `kubectl apply
--dry-run=client -f .` and `kubectl create --dry-run=client
--validate=false -f .` failed with `dial tcp [::1]:8080: connect:
connection refused` — kubectl needs API-server discovery even for
`--dry-run=client` to recognize a CRD kind, so that check cannot run
without a cluster). Four checks were run:

1. **YAML well-formedness**: both files parse as valid YAML
   (`python3 -c "import yaml; yaml.safe_load(open(...))"`, no errors).
2. **`kubectl kustomize k8s/keda`**: succeeded and rendered both resources
   correctly (pure manifest templating, no cluster required) — confirms
   `kustomization.yaml` and both resource files are structurally sound
   enough for kustomize to merge/emit.
3. **Schema correctness against the actual CRDs**: every field was
   checked against the CRD definitions —
   `keda.sh_scaledobjects.yaml` from the `kedacore/keda` `v2.19.0` tag
   (the version `scripts/setup-keda.sh` installs) and
   `http.keda.sh_httpscaledobjects.yaml` from the `kedacore/http-add-on`
   `v0.15.0` tag (the pinned add-on version) — fetched directly from
   GitHub. `scaleTargetRef.service` is required for `HTTPScaledObject`,
   and exactly one of `port`/`portName` must be set, both satisfied here.
4. Names/namespace/ports were copied verbatim from `k8s/base/*.yaml`
   (`k8s/base/*.yaml`).

With a cluster that has the KEDA CRDs installed, the stronger check is:

```bash
kubectl apply --dry-run=server -k k8s/keda
```

## Unverified

- The `notification-service` default consumer-group-id claim
  (`quarkus.application.name`) is documented behavior (Quarkus Kafka
  reference guide); it was not confirmed by inspecting a live consumer's
  group membership on a running broker.
- `lagThreshold: "5"` and `scalingMetric.requestRate.targetValue: 50` are
  demo defaults, not load-tested; tune them against measured throughput.
