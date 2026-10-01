---
title: Observability
order: 9
part: Operating the mesh
description: "Metrics, distributed traces, and the live mesh view — the real LGTM stack and OpenTelemetry wiring this repo installs, and a verified cross-service trace."
duration: 30 minutes
marker: "08"
---

The [previous chapter](/docs/07-elastic-and-resilient/) ended on scaling and recovery —
the platform doing things automatically in response to demand and failure. "The
platform does things automatically" is only reassuring if you can *see* it happening.
This chapter covers observability as this repo actually ships it: the LGTM stack
(`scripts/setup-lgtm.sh`) that collects metrics, traces, and logs; the one demo
(`demos/demo-tracing.sh`) that was run against a real backend and produced a verified
cross-service trace; and Kiali as the live view of traffic moving through the mesh.

{% include excalidraw.html file="08-reference-architecture" alt="Reference architecture diagram showing the full datamesh stack: data products behind the Istio mesh, KEDA-driven autoscaling, and every signal flowing through the OpenTelemetry Collector into the Grafana LGTM stack and Kiali" caption="Figure 8.1 — the full reference architecture: mesh, scaling, and observability together" %}

Figure 8.1 is the shape of everything the last three chapters have been building
toward, drawn as one picture: the data products from earlier chapters sit behind the
selectively-meshed Istio data plane from [Chapter 6](/docs/06-progressive-delivery-mtls/),
KEDA watches and scales two of them from [Chapter 7](/docs/07-elastic-and-resilient/),
and every one of those moving parts — the mesh's sidecars, the scalers' activations,
the services' own request handling — is a source of telemetry that lands in the same
place: the Collector and LGTM stack this chapter describes. None of the earlier
chapters' mechanisms are observable in isolation; this chapter is what makes the whole
picture legible at once.

## The three signals, and why a mesh needs all of them

Observability conventionally rests on three kinds of signal, and a mesh of
independently-owned products has a distinct use for each. **Metrics** are aggregate
numbers over time — request rates, error rates, consumer lag, replica counts — the
kind of signal that shows the [KEDA](/docs/07-elastic-and-resilient/) scaler actually
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
time actually went; a log line from the specific span that looks slow tells you *why* —
the exception, the SQL statement, the retry. Skipping straight to logs without a trace
to narrow the search means grepping three services' logs for a needle with no idea
which haystack it's in; that's the specific cost a mesh pays for not wiring up tracing,
and the specific cost this chapter's stack is built to avoid.

## Installing the stack: `scripts/setup-lgtm.sh`

Every component runs in **monolithic / single-binary mode**, because this is a
single-node minikube — production deployments would run each backend's distributed
mode (separate ingester/distributor/querier processes), which only pays off once
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
sidecar pattern so it auto-picks-up any ConfigMap labeled `grafana_datasource: "1"` or
`grafana_dashboard: "1"`, rather than needing a manual provisioning step per dashboard.

{% include excalidraw.html file="08-observability-stack" alt="Diagram of the four LGTM backends — Loki, Tempo, Mimir, Grafana — each running filesystem-backed and single-replica in the observability namespace, fed by one shared OpenTelemetry Collector" caption="Figure 8.3 — the LGTM stack: four backends, one Collector, one Grafana" %}

### Everything through one Collector

Applications don't talk to Loki, Tempo, or Mimir directly. They emit OTLP to a single
OpenTelemetry Collector, and `scripts/otel-collector-config.yaml` is the routing table
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

Three pipelines, one shared `otlp` receiver (gRPC on `4317`, HTTP on `4318`), and each
pipeline runs the batch through the same two processors before exporting:
`memory_limiter` is back-pressure sized against the Collector pod's own memory limit
(not host memory) so a signal spike degrades gracefully instead of OOM-killing the
pod, and `resource` stamps every signal with a `cluster: minikube` attribute — useful
the moment more than one cluster reports into the same Grafana. The payoff of routing
everything through one Collector rather than wiring each service to each backend
directly: adding tail sampling, label redaction, or cardinality control later is a
change to this one file, not to every service that emits telemetry. It also means the
three application services never need to know Mimir uses a remote-write push model
while Tempo and Loki take OTLP-native exports directly — each pipeline's `exporters`
list hides that backend-specific detail behind the one `otlp` receiver every service
actually talks to, so a backend swap (Tempo for a different tracing store, say) is a
change to one exporter block, not to any service's configuration.

### Mimir plays double duty as "Prometheus"

`scripts/grafana-datasources.yaml` registers Mimir **twice** — once as itself, once
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

The comment in the file names this plainly: "Mimir replaces Prometheus and pretends to
be it." Mimir exposes a Prometheus-compatible query API, so anything written to expect
a datasource literally named `prometheus` — a dashboard JSON exported from elsewhere, a
PromQL query pasted from documentation — works unmodified, while Mimir is the only
metrics backend actually running. The same Prometheus-compatible endpoint is exactly
what lets Kiali (below) treat Mimir as its metrics source with no separate Prometheus
install.

### Dashboards ship as code

`scripts/grafana-dashboards/` holds four dashboard ConfigMaps
(`dashboard-overview.yaml`, `dashboard-loki.yaml`, `dashboard-tempo.yaml`,
`dashboard-mimir.yaml`), each labeled `grafana_dashboard: "1"` so Grafana's sidecar
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

Its own header comment explains the design intent directly: "Top-row panels show
whether each of the four backends is receiving signal; lower rows let you drill into
traces, logs, or metrics from one place" — a single landing page that answers "is
anything broken in the observability pipeline itself" before you go looking for an
application problem.

## A verified cross-service trace

Unlike most of this part, `demos/demo-tracing.sh` was actually run against a real
backend (the docker-compose LGTM baseline, not minikube) and produced the effect it
claims — this is the one place in this part where "verified" means something beyond
"the code should work."

The trace it produces follows a single `POST /orders` across two services:
`order-service` handles the REST request and calls `inventory-service`'s
`CheckStock` over gRPC — the same cross-service hop `OrderResource.placeOrder`
performs for every real order. Neither service has `quarkus-opentelemetry` on its
classpath (confirmed by grepping every `examples/*/pom.xml` for "opentelemetry" —
nothing), and that extension is a build-time dependency, not something a runtime flag
can retrofit onto an already-packaged jar. So the demo takes the zero-pom-touch path:
it attaches the upstream OpenTelemetry Java auto-instrumentation agent as a
`-javaagent:` flag to both already-built `quarkus-run.jar` processes, which
auto-instruments JAX-RS, the gRPC client and server, and JDBC with no source changes.

The agent itself isn't vendored into the repo — the demo downloads it once, from the
upstream `opentelemetry-java-instrumentation` project's `latest` GitHub release, and
caches it outside the repo tree at `~/.cache/datamesh-demos/opentelemetry-javaagent.jar`
so subsequent runs skip the download entirely. That cache check is a plain file-exists
test before anything else runs, and if the download fails — an offline host, a GitHub
outage — the script fails loudly with the exact `curl` command to fetch the jar
manually, rather than silently skipping instrumentation and producing a demo that looks
like it passed but traced nothing:

```bash
java -javaagent:"$AGENT_JAR" \
    -Dquarkus.http.port="$INVENTORY_PORT" \
    -Dquarkus.grpc.server.port="$INVENTORY_GRPC_PORT" \
    -jar target/quarkus-app/quarkus-run.jar
```

with `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, and
`OTEL_TRACES_EXPORTER=otlp` set per-process so each service's spans arrive at the
compose stack's Collector tagged with the right `service.name`. After `POST /orders`
succeeds, the demo doesn't just trust that tracing worked — it queries Tempo's own HTTP
API and parses the answer:

```bash
curl "${TEMPO_BASE}/api/search?tags=service.name%3Dorder-service&limit=20"
curl "${TEMPO_BASE}/api/traces/${TRACE_ID}"
```

and asserts three specific things against the parsed trace: at least five spans
(the REST entry span, the gRPC client/server pair, and Postgres spans from both
services, at minimum), a span whose `service.name` resource attribute is
`order-service`, and a span whose `service.name` is `inventory-service` — proving W3C
trace-context actually propagated across the real gRPC call rather than producing two
disconnected, same-looking traces. It goes one step further and asserts the specific
`CheckStock` gRPC span is present by name, not just that *some* gRPC span exists. That
specificity is what makes this a verification rather than a smoke test: the claim isn't
"tracing is configured," it's "this exact cross-service call produced this exact
connected trace, and here's the query that proves it."

One API-shape detail the demo had to discover empirically rather than assume from
documentation: this Tempo build answers `GET /api/traces/<id>` with the older
Jaeger-style `batches`/`scopeSpans` shape, not the newer OTLP-JSON `resourceSpans`
shape some current docs describe — the demo's `jq` parses both defensively rather than
betting on one.

## The live mesh view

Metrics and traces are recorded and queried after the fact. The other thing worth
having alongside them is a *live* picture of the mesh topology — which products are
talking to which, right now, with health and traffic rate on each edge. That's Kiali's
job, and `scripts/setup-kiali.sh` installs it wired to the **existing** LGTM stack
rather than standing up a separate Prometheus of its own:

```bash
PROM_URL="http://mimir-nginx.observability.svc.cluster.local:80/prometheus"
TEMPO_URL="http://tempo.observability.svc.cluster.local:3200"

helm upgrade --install kiali-server kiali/kiali-server \
    --namespace istio-system --version 2.23.0 \
    --set external_services.prometheus.url="$PROM_URL" \
    --set external_services.tracing.provider=tempo \
    --set external_services.tracing.internal_url="$TEMPO_URL"
```

The script's own header names the point directly: "this project has no standalone
Prometheus — Mimir ... exposes a Prometheus-compatible query API at `/prometheus`,
exactly like the Grafana datasource already does." Kiali is pointed at the same Mimir
endpoint Grafana already uses, rather than installing and maintaining a second metrics
pipeline that would eventually drift from the first.

Kiali's graph is quiet by default — its own script output says so plainly: "the live
traffic graph only shows edges while traffic is flowing — the mesh graph is quiet
until a service is opted into the mesh (see `setup-istio.sh`) and is receiving
traffic." That ties directly back to the [previous chapter's](/docs/06-progressive-delivery-mtls/)
selective-injection decision: a product has to actually carry the
`sidecar.istio.io/inject: "true"` annotation before Kiali has anything to draw for it.
Once `order-service` is meshed and a [canary](/docs/06-progressive-delivery-mtls/) is
running, the same graph is where you'd watch the v1/v2 traffic split happen live,
rather than inferring it from logs.

## Reaching the stack: NodePort + SSH tunnel, never `port-forward`

Every backend above is installed as a `NodePort` Service at a fixed port — Grafana at
`30300`, Tempo at `30320`, Mimir at `30009`, OTLP at `30417`/`30418`, Kiali at
`30201` — and `scripts/tunnel-services.sh` is the one way this repo reaches them from
the host, deliberately not `kubectl port-forward`:

```bash
tunnel 3000 30300 "Grafana: http://localhost:3000 (admin/admin)"
tunnel 3200 30320 "Tempo:   http://localhost:3200"
tunnel 9009 30009 "Mimir:   http://localhost:9009"
```

`tunnel()` opens a backgrounded SSH forward through the minikube node's own SSH server
rather than relying on `kubectl port-forward`'s kept-alive HTTP/2 stream, which this
repo's other scripts note drops under load or after an idle timeout. Getting that SSH
connection parameterized correctly is its own small piece of plumbing worth
understanding: the script resolves the private key with `minikube ssh-key -p datamesh`
and the forwarded port with `docker port datamesh 22/tcp` — because on the `docker`
driver, the "minikube node" is itself a Docker container, so its SSH daemon is reached
through whatever host port Docker happens to have mapped to that container's `22/tcp`,
not a fixed port. Each `tunnel` call is one `ssh -L <local>:localhost:<node_port> -N -f`
invocation against that resolved key and port, backgrounded with `-f` and kept alive
with `ServerAliveInterval=30`/`ServerAliveCountMax=3` so a momentarily quiet tunnel
isn't mistaken for a dead one and dropped. Re-running the script kills any previous
tunnels first (`pkill -f 'ssh.*docker@127.0.0.1'`) before opening fresh ones, which is
what makes it safe to re-run after a minikube restart changes the underlying SSH port.
The same NodePort convention is what every `--set service.type=NodePort` in
`setup-lgtm.sh` and `setup-kiali.sh` exists to set up — this script is simply the one
place all of those fixed ports get turned into stable `localhost` URLs in one command.

## What it all adds up to

Put the pieces together and the mesh becomes legible end to end, with the one piece
actually proven end to end being the cross-service trace: a single `POST /orders`
produces a parsed, multi-span trace spanning `order-service` and `inventory-service`,
queryable from Tempo's own API. The metrics side shows the Collector's `resource`
processor stamping every signal, Mimir answering as both itself and "Prometheus," and a
dashboard that watches the three backends' own ingest rates before you ever look at an
application metric. The live mesh view is Kiali, wired to that same Mimir and Tempo
rather than a second pipeline, quiet until a product opts into the mesh and starts
producing traffic worth drawing. None of this is the system — these are the instruments
through which a mesh too distributed for any single vantage point becomes something you
can actually watch run.

That completes this part. This build has the substrate for a running data mesh:
services that own their data, a service mesh that can route and secure traffic between
product versions, elastic and self-healing scaling, and the observability to see all of
it working.

---

*Verification status: <span class="status status--unverified">unverified</span>, with
one exception. `demos/demo-tracing.sh`'s cross-service trace is the one claim in this
chapter that was actually driven and observed (an 11-span trace spanning both services
was recorded against the compose `otel-lgtm` backend, per the demo's own header
comment) — everything about the **minikube** LGTM install (`scripts/setup-lgtm.sh`,
`scripts/setup-kiali.sh`, the NodePort values, the dashboard JSON) has not been applied
to a live cluster in this environment. Confirm on a real run: that every `--set` key
in `setup-lgtm.sh` and `setup-kiali.sh` matches its chart's actual values schema at the
pinned version (both scripts flag this as unverified in their own headers); that the
four dashboard ConfigMaps actually render in Grafana via the sidecar rather than
failing silently; and that Kiali's graph populates once a service is meshed per
Chapter 6's annotation and receiving live traffic.*
