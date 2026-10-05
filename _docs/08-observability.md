---
title: "Observability"
order: 9
part: Operating the mesh
marker: "09"
description: "Metrics, distributed traces, and the live mesh view — the LGTM stack and OpenTelemetry wiring this repo installs, and a verified cross-service trace."
duration: 30 minutes
---

The [previous chapter](/docs/07-elastic-and-resilient/) ended on scaling and recovery —
the platform responding automatically to demand and failure. Automation is only
reassuring if you can see it happening.
This chapter covers observability as this repo ships it: the LGTM stack
([setup-lgtm.sh]({{ site.repo_blob }}/scripts/setup-lgtm.sh)) that collects metrics, traces, and logs; the demo
([demo-tracing.sh]({{ site.repo_blob }}/demos/demo-tracing.sh)) that was run against a live backend and produced a verified
cross-service trace; and Kiali as the live view of traffic moving through the mesh.

{% include excalidraw.html file="08-reference-architecture" alt="Reference architecture diagram showing the full datamesh stack: data products behind the Istio mesh, KEDA-driven autoscaling, and every signal flowing through the OpenTelemetry Collector into the Grafana LGTM stack and Kiali" caption="Figure 8.1 — the full reference architecture: mesh, scaling, and observability together" %}

Figure 8.1 combines the pieces from the last three chapters. The data products from earlier chapters sit behind the selectively-meshed
Istio data plane from [Chapter 6](/docs/06-progressive-delivery-mtls/), and KEDA
watches and scales two of them from [Chapter 7](/docs/07-elastic-and-resilient/).
Every one of those moving parts — the mesh's sidecars, the scalers' activations, the
services' own request handling — is a source of telemetry, and all of it lands in the
same place: the Collector and LGTM stack described here. Those mechanisms are
observable together only through this stack.

## The three signals and why a mesh needs all of them

Observability conventionally rests on three kinds of signal, and a mesh of
independently-owned products has a distinct use for each. **Metrics** are aggregate
numbers over time — request rates, error rates, consumer lag, replica counts — the
kind of signal that shows the [KEDA](/docs/07-elastic-and-resilient/) scaler
waking a replica. **Traces** follow one request as it crosses product boundaries, which
is the only way to see that a slow GraphQL query was slow because the gRPC call it made
downstream was slow — no single product's own logs would reveal that. **Logs** are the
detailed per-event record you reach for once metrics and traces have told you *where*
to look. A request that touches `graphql-gateway`, `order-service`, and
`inventory-service` is one user-facing operation spread across three independently
owned products; understanding it means correlating signals that no single product owns
in full.

{% include excalidraw.html file="08-three-signals" alt="Diagram of the three observability signal types — metrics, traces, and logs — and what each one answers for a request crossing graphql-gateway, order-service, and inventory-service" caption="Figure 8.2 — metrics, traces, and logs: what each signal answers" %}

None of the three signals substitutes for the others, and the order you reach for them
in practice usually runs in one direction: a metric (a replica count that climbed, an
error-rate panel that spiked) tells you *something* changed and roughly *when*; a trace
for a request in that window tells you *which* products were involved and where the
time went; a log line from the specific span that looks slow tells you *why* —
the exception, the SQL statement, the retry. Skipping straight to logs without a trace
to narrow the search means grepping three services' logs for a needle with no idea
which haystack it's in; that is the cost of a mesh without tracing,
and the cost this stack is built to avoid.

## Installing the stack: [setup-lgtm.sh]({{ site.repo_blob }}/scripts/setup-lgtm.sh)

Every component runs in **monolithic / single-binary mode**, because this is a
single-node local Kubernetes cluster (`minikube`). Production deployments would run each backend's distributed
mode (separate ingester/distributor/querier processes), which pays off only once
there are nodes to spread the load across:

```bash
helm upgrade --install loki grafana/loki \
    --version 6.16.0 --namespace observability \
    --set deploymentMode=SingleBinary \
    --set 'loki.storage.type=filesystem'

helm upgrade --install tempo grafana/tempo \
    --version 1.10.0 --namespace observability \
    --set 'tempo.storage.trace.backend=local'

helm upgrade --install mimir grafana/mimir-distributed \
    --version 5.4.0 --namespace observability \
    --set 'mimir.structuredConfig.common.storage.backend=filesystem'

helm upgrade --install grafana grafana/grafana \
    --version 8.5.0 --namespace observability \
    --set 'sidecar.datasources.enabled=true' \
    --set 'sidecar.dashboards.enabled=true'
```

Four backends, one convention each: Loki for logs, Tempo for traces, Mimir for
metrics — all filesystem-backed, all single-replica — and Grafana wired with the
sidecar pattern so it picks up any ConfigMap labeled `grafana_datasource: "1"` or
`grafana_dashboard: "1"` without a manual provisioning step per dashboard.

{% include excalidraw.html file="08-observability-stack" alt="Diagram of the four LGTM backends — Loki, Tempo, Mimir, Grafana — each running filesystem-backed and single-replica in the observability namespace, fed by one shared OpenTelemetry Collector" caption="Figure 8.3 — the LGTM stack: four backends, one Collector, one Grafana" %}

### Everything through one Collector

Applications don't talk to Loki, Tempo, or Mimir directly. They emit OTLP to a single
OpenTelemetry Collector, and [otel-collector-config.yaml]({{ site.repo_blob }}/scripts/otel-collector-config.yaml) is the routing table
that decides where each signal goes:

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [otlphttp/loki]
```

Three pipelines share one `otlp` receiver (gRPC on `4317`, HTTP on `4318`), and each
pipeline runs its batch through the same two processors before exporting.
`memory_limiter` is back-pressure sized against the Collector pod's own memory limit
(not host memory), so a signal spike degrades gracefully instead of OOM-killing the
pod. `resource` stamps every signal with a `cluster: minikube` attribute, useful once
more than one cluster reports into the same Grafana. Routing everything
through one Collector, instead of wiring each service to each backend,
concentrates future changes in one place: adding tail sampling, label redaction, or
cardinality control later is a change to this one file, not to every service that
emits telemetry. The application services also need not know that
Mimir uses a remote-write push model while Tempo and Loki take OTLP-native exports.
Each pipeline's `exporters` list hides that detail behind
the one `otlp` receiver every service talks to, so a backend swap — Tempo for
a different tracing store, say — is a change to one exporter block, not to any
service's configuration.

### Mimir registered as both itself and Prometheus

[grafana-datasources.yaml]({{ site.repo_blob }}/scripts/grafana-datasources.yaml) registers Mimir **twice** — once as itself, once
aliased as `Prometheus` — both pointing at the same URL
(`http://mimir-nginx.observability.svc.cluster.local:80/prometheus`):

```yaml
datasources:
  - name: Mimir
    type: prometheus
    url: http://mimir-nginx.observability.svc.cluster.local:80/prometheus
    isDefault: true
  - name: Prometheus
    type: prometheus
    url: http://mimir-nginx.observability.svc.cluster.local:80/prometheus
    isDefault: false
```

Per the file's comment, Mimir replaces Prometheus here.
Mimir exposes a Prometheus-compatible query API, so anything written to expect
a datasource named `prometheus` — a dashboard JSON exported from elsewhere, a
PromQL query pasted from documentation — works unmodified, while Mimir is the only
metrics backend running. The same Prometheus-compatible endpoint
lets Kiali (below) treat Mimir as its metrics source with no separate Prometheus
install.

### Dashboards ship as code

[grafana-dashboards]({{ site.repo_tree }}/scripts/grafana-dashboards) holds four dashboard ConfigMaps
([dashboard-overview.yaml]({{ site.repo_blob }}/scripts/grafana-dashboards/dashboard-overview.yaml), [dashboard-loki.yaml]({{ site.repo_blob }}/scripts/grafana-dashboards/dashboard-loki.yaml), [dashboard-tempo.yaml]({{ site.repo_blob }}/scripts/grafana-dashboards/dashboard-tempo.yaml),
[dashboard-mimir.yaml]({{ site.repo_blob }}/scripts/grafana-dashboards/dashboard-mimir.yaml)), each labeled `grafana_dashboard: "1"` so Grafana's sidecar
mounts them automatically — no manual "import dashboard" step. The overview dashboard's
first row is a trio of ingest-rate stats, one per backend:

```json
{
  "title": "Metrics ingest rate (Mimir, samples/s)",
  "targets": [{ "expr": "sum(rate(cortex_ingester_ingested_samples_total[1m]))" }]
},
{
  "title": "Trace ingest rate (Tempo, spans/s)",
  "targets": [{ "expr": "sum(rate(tempo_distributor_spans_received_total[1m]))" }]
}
```

Its header comment states the design: "Top-row panels show
whether each of the four backends is receiving signal; lower rows let you drill into
traces, logs, or metrics from one place" — a single landing page that answers "is
anything broken in the observability pipeline itself" before you go looking for an
application problem.

## A verified cross-service trace

[demo-tracing.sh]({{ site.repo_blob }}/demos/demo-tracing.sh) was run against a live
backend (the docker-compose LGTM baseline, not Kubernetes) and produced the trace it
describes. It is the one demo in this part verified by execution and observation
instead of code review.

The trace it produces follows a single `POST /orders` across two services:
`order-service` handles the REST request and calls `inventory-service`'s
`CheckStock` over gRPC — the same cross-service hop `OrderResource.placeOrder`
performs for every order. Neither service has `quarkus-opentelemetry` on its
classpath (confirmed by grepping every `examples/*/pom.xml` for "opentelemetry" —
nothing), and that extension is a build-time dependency, not something a runtime flag
can retrofit onto an already-packaged jar. So the demo takes the zero-pom-touch path:
it attaches the upstream OpenTelemetry Java auto-instrumentation agent as a
`-javaagent:` flag to both already-built `quarkus-run.jar` processes, which
auto-instruments JAX-RS, the gRPC client and server, and JDBC with no source changes.

The agent is not vendored into the repo; the demo downloads it once from the
upstream `opentelemetry-java-instrumentation` project's `latest` GitHub release, and
caches it outside the repo tree at `~/.cache/datamesh-demos/opentelemetry-javaagent.jar`
so subsequent runs skip the download entirely. A file-exists test checks the cache first, and if the download fails (an offline host, a GitHub
outage) the script fails with the exact `curl` command to fetch the jar
manually, so it never skips instrumentation and passes while tracing nothing:

```bash
java -javaagent:"$AGENT_JAR" \
    -Dquarkus.http.port="$INVENTORY_PORT" \
    -Dquarkus.grpc.server.port="$INVENTORY_GRPC_PORT" \
    -jar target/quarkus-app/quarkus-run.jar
```

with `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, and
`OTEL_TRACES_EXPORTER=otlp` set per-process so each service's spans arrive at the
compose stack's Collector tagged with the right `service.name`. After `POST /orders`
succeeds, the demo queries Tempo's HTTP
API and parses the answer:

```bash
curl "${TEMPO_BASE}/api/search?tags=service.name%3Dorder-service&limit=20"
curl "${TEMPO_BASE}/api/traces/${TRACE_ID}"
```

and asserts three specific things against the parsed trace: at least five spans
(the REST entry span, the gRPC client/server pair, and Postgres spans from both
services, at minimum), a span whose `service.name` resource attribute is
`order-service`, and a span whose `service.name` is `inventory-service` — confirming W3C
trace-context propagated across the gRPC call instead of producing two
disconnected traces. It also asserts that the `CheckStock` gRPC span is present, not
just some gRPC span. That makes this a verification rather than a smoke test: it shows
that this cross-service call produced one connected trace.

One API-shape detail was found empirically: this Tempo build answers `GET /api/traces/<id>` with the older
Jaeger-style `batches`/`scopeSpans` shape, not the newer OTLP-JSON `resourceSpans`
shape some current docs describe. The demo's `jq` parses both.

## The live mesh view

Metrics and traces are queried after the fact. Kiali adds a *live* picture of the
mesh topology: which products are talking to which, with health and traffic rate on
each edge. [setup-kiali.sh]({{ site.repo_blob }}/scripts/setup-kiali.sh) installs it against the **existing** LGTM stack
instead of a separate Prometheus:

```bash
PROM_URL="http://mimir-nginx.observability.svc.cluster.local:80/prometheus"
TEMPO_URL="http://tempo.observability.svc.cluster.local:3200"

helm upgrade --install kiali-server kiali/kiali-server \
    --namespace istio-system --version 2.23.0 \
    --set external_services.prometheus.url="$PROM_URL" \
    --set external_services.tracing.provider=tempo \
    --set external_services.tracing.internal_url="$TEMPO_URL"
```

The script's header explains: "this project has no standalone
Prometheus — Mimir ... exposes a Prometheus-compatible query API at `/prometheus`,
exactly like the Grafana datasource already does." Kiali is pointed at the same Mimir
endpoint Grafana uses, which avoids a second metrics
pipeline that would drift from the first.

Kiali's graph is quiet by default; the script output says: "the live
traffic graph only shows edges while traffic is flowing — the mesh graph is quiet
until a service is opted into the mesh (see [setup-istio.sh]({{ site.repo_blob }}/scripts/setup-istio.sh)) and is receiving
traffic." That follows from the [selective-injection decision](/docs/06-progressive-delivery-mtls/):
a product must carry the
`sidecar.istio.io/inject: "true"` pod-template label before Kiali has anything to draw for it.
Once `order-service` is meshed and a [canary](/docs/06-progressive-delivery-mtls/) is
running, the same graph is where you can watch the v1/v2 traffic split live
instead of inferring it from logs.

## Reaching the stack: NodePort and SSH tunnel instead of `port-forward`

Every backend above is installed as a `NodePort` Service at a fixed port — Grafana at
`30300`, Tempo at `30320`, Mimir at `30009`, OTLP at `30417`/`30418`, Kiali at
`30201` — and [tunnel-services.sh]({{ site.repo_blob }}/scripts/tunnel-services.sh) is how this repo reaches them from
the host, instead of `kubectl port-forward`:

```bash
tunnel 3000 30300 "Grafana: http://localhost:3000 (admin/admin)"
tunnel 3200 30320 "Tempo:   http://localhost:3200"
tunnel 9009 30009 "Mimir:   http://localhost:9009"
```

`tunnel()` opens a backgrounded SSH forward through the `minikube` node's own SSH
server, rather than relying on `kubectl port-forward`'s kept-alive HTTP/2 stream —
this repo's other scripts note that stream drops under load or after an idle timeout.
Parameterizing that SSH connection correctly takes two lookups: the script resolves
the private key with `minikube ssh-key -p datamesh` and the forwarded port with
`docker port datamesh 22/tcp`. The second lookup is needed because on the `docker`
driver the `minikube` node is itself a Docker container, so its SSH daemon is reached
through whatever host port Docker has mapped to that container's `22/tcp`,
not a fixed port. Each `tunnel` call is then one
`ssh -L <local>:localhost:<node_port> -N -f` invocation against that resolved key and
port, backgrounded with `-f` and kept alive with `ServerAliveInterval=30`/
`ServerAliveCountMax=3`, so a briefly quiet tunnel is not dropped as dead. Re-running the script kills any previous tunnels first
(`pkill -f 'ssh.*docker@127.0.0.1'`) before opening fresh ones, which is what makes it
safe to re-run after a `minikube` restart changes the underlying SSH port. The same
NodePort convention is what every `--set service.type=NodePort` in [setup-lgtm.sh]({{ site.repo_blob }}/scripts/setup-lgtm.sh) and
[setup-kiali.sh]({{ site.repo_blob }}/scripts/setup-kiali.sh) exists to set up; this script turns those
fixed ports into stable `localhost` URLs in one command.

## What it all adds up to

Put together, the mesh becomes legible end to end: a single `POST /orders` produces a
parsed, multi-span trace spanning `order-service` and `inventory-service`, queryable
from Tempo's own API, while the Collector, Mimir, and Kiali provide the metrics and
live-topology views described above. Together these form a running
data mesh: services that own their data, a mesh that can route and secure traffic
between product versions, elastic and self-healing scaling, and the observability to
see all of it working.

---

*Verification status: <span class="status status--verified">verified</span>. `demo-tracing.sh` passed, recording the cross-service trace against the compose otel-lgtm backend. The mesh/Kiali view is covered by the Kubernetes chapters, which still require a live cluster.*
