# infra/ — standalone docker compose stack

Support configs for the repo-root `compose.yaml` (DRQ-011, Phase C step
8a). `docker compose up -d` from the repo root brings up the baseline
infrastructure; see `CLAUDE.md`'s "Build / test commands" section.

```
infra/
  db/init/00-init.sql      # per-service Postgres databases (docker-entrypoint-initdb.d)
  otelcol/config.yaml      # OTel Collector config for the `lgtm` service
  grafana/datasources.yaml # Grafana datasource provisioning for the `lgtm` service
  README.md                # this file
```

## What's always on vs. opt-in

| Service | Profile | Notes |
|---|---|---|
| `postgres` | (none — baseline) | `postgres:18`, one DB per service |
| `kafka` | (none — baseline) | KRaft mode, two listeners |
| `apicurio` | (none — baseline) | Schema Registry v3 API, in-memory H2 |
| `lgtm` | (none — baseline) | Grafana + Loki + Tempo + Mimir + OTel Collector, **always-on per DRQ-011** (user choice — NOT profile-gated, unlike the lgtm-docker-stack skill's generic `compose-full.yaml` template where observability ships alongside a profiled Kafka/Postgres/Apicurio) |
| `kafka-ui` | `tools` | `docker compose --profile tools up -d` |
| `ollama` | `ollama` | `docker compose --profile ollama up -d` — opt-in, heaviest piece (DEF-001) |

```bash
cp .env.example .env                   # first time only — .env is gitignored
docker compose up -d                   # postgres + kafka + apicurio + lgtm
docker compose --profile tools up -d   # + kafka-ui
docker compose --profile ollama up -d  # + ollama
docker compose down                    # stop, keep volumes
docker compose down -v                 # stop AND wipe volumes
```

> `.env` holds throwaway local-dev credentials and is **gitignored**; copy it
> from the committed `.env.example` template. Change the Postgres credentials
> for anything beyond local development.

## Image tags — the wire-compat crux (DRQ-011)

**Requirement:** `POSTGRES_IMAGE`, `KAFKA_IMAGE`, and `APICURIO_IMAGE` in
`.env` (repo root) MUST equal the exact tags Quarkus 3.39.5 Dev Services
pulls by default, so `mvn verify` (Testcontainers/Dev Services) and this
standalone compose stack exercise identical broker/registry/database
behavior. Step 8b's service Containerfiles/`application.properties` should
pin the SAME tags into `quarkus.*.devservices.image-name` where relevant.

| Component | Pinned tag | Quarkus 3.39.5 Dev Services default | Confirmed by |
|---|---|---|---|
| Postgres | `docker.io/library/postgres:18` | same | see below |
| Kafka | `docker.io/apache/kafka-native:4.2.0` | same (provider `upstream-kafka-native`, the default) | see below |
| Apicurio Registry | `quay.io/apicurio/apicurio-registry:3.1.7` | same | see below |

### How each tag was confirmed

Live Maven dependency resolution against this project's actual
`io.quarkus:quarkus-bom:3.39.5` (not guessed, not web-searched) — the
build-time config classes for each Dev Services processor were pulled from
Maven Central and disassembled to read their compiled-in default image
constants directly:

```bash
cd examples/order-service

# Postgres: default image selector
mvn -q dependency:get -Dartifact=io.quarkus:quarkus-devservices-postgresql:3.39.5:jar
unzip -p ~/.m2/repository/io/quarkus/quarkus-devservices-postgresql/3.39.5/*.jar \
  | strings | grep 'default.image='
# -> default.image=docker.io/library/postgres:18   (also confirms pgvector/postgis variants, unused here)

# Kafka: provider + image constants live in quarkus-kafka-client-deployment
unzip -p ~/.m2/repository/io/quarkus/quarkus-kafka-client-deployment/3.39.5/*.jar \
  | strings | grep -E 'apache/kafka|upstream-kafka-native'
# -> confirms provider default = upstream-kafka-native; image = docker.io/apache/kafka-native:4.2.0
# Cross-checked against quarkus_searchDocs (quarkus-kafka-client, "Dev Services for Kafka"):
#   "upstream-kafka-native (default) uses the official Apache Kafka native image"

# Apicurio Registry: the devservices processor is a separate artifact,
# NOT quarkus-apicurio-registry-*-deployment (those only carry the
# extension/serde build steps). Found by grepping the whole local Maven
# repo for the image string:
unzip -p ~/.m2/repository/io/quarkus/quarkus-schema-registry-devservice-deployment/3.39.5/*.jar \
  | strings | grep 'default.image='
# -> default.image=quay.io/apicurio/apicurio-registry:3.1.7
# Cross-checked against quarkus_searchDocs (quarkus-apicurio-registry-avro,
# "Dev Services for Apicurio Registry"): "uses apicurio/apicurio-registry
# images... in-memory h2 database by default" — matches 3.1.7's supported
# storage kinds (see the APICURIO_STORAGE_KIND note below).
```

`order-service`'s own `mvn dependency:tree` (compile scope) additionally
shows `io.apicurio:apicurio-registry-*:3.1.7` client/serde libraries
pulled in transitively via `quarkus-apicurio-registry-avro:3.39.5` —
consistent with the devservice defaulting to the same 3.1.7 release line.

None of the three tags were run-mode-dependent guesses: `quarkus:dev` was
not used to observe live Testcontainers (the task's "preferred method"),
because directly disassembling the pinned 3.39.5 deployment jars gives the
exact compiled-in default with no risk of a stale/cached image from an
earlier dev run skewing the observation. All three tags were then **pulled
and actually run** (`docker pull` + `docker run`) as part of writing
`compose.yaml`, not just read as strings — see "Validation" below.

## Kafka listeners

`kafka:9094` is the in-network listener (other compose services, and the
same name/port a `Service` object would use in the minikube-stack handoff
— K8s parity per DRQ-011). `localhost:9092` is the host listener for
`kcat`/`kafkacat`, IDE plugins, and CLI tools run directly on the laptop.
Both were verified live with `kafkacat -L` (see "Validation").

`apache/kafka-native` is a from-scratch GraalVM-native build of the Kafka
broker on Alpine/busybox — no JVM, no `kafka-broker-api-versions.sh`, no
`curl`/`wget`. `bash` IS present and supports `/dev/tcp`, which is what the
`kafka` service's healthcheck uses instead.

## Apicurio Registry storage

`APICURIO_STORAGE_KIND=mem` (the lgtm-docker-stack skill's generic
template value, valid on older 3.0.x Apicurio images) fails hard on
3.1.7 with `IllegalStateException: No Registry storage variant defined
for value mem` — confirmed by actually running the pinned image. Fixed to
`APICURIO_STORAGE_KIND=sql` + `APICURIO_STORAGE_SQL_KIND=h2`: an embedded,
in-memory H2 database, functionally equivalent (ephemeral, wiped on
restart) to the removed `mem` variant.

## LGTM (`lgtm` service) gotchas found while validating

Two issues surfaced only by actually running `grafana/otel-lgtm:0.8.1`,
not by reading the lgtm-docker-stack skill's generic templates:

1. **Collector exporter endpoints.** The base `otelcol-collector-base.yaml`
   skill template targets Tempo's query API (`:3200`) and Mimir's
   remote-write path (`/api/v1/write`) directly — both wrong for this
   image. The image's own internal `run-all.sh` startup script blocks
   forever on a `otelcol_process_uptime_total` metric appearing in
   Mimir/Prometheus before marking anything ready, which requires the
   collector to (a) export traces to Tempo's OTLP ingest port `4418`
   (not 3200), (b) export metrics to Mimir's OTLP ingest path
   `/api/v1/otlp` via the `otlphttp` exporter (not
   `prometheusremotewrite` at `/api/v1/write`), and (c) scrape its own
   `:8888` self-metrics endpoint into the same metrics pipeline. Diagnosed
   by dumping the image's own shipped default config (`docker run
   --entrypoint sh grafana/otel-lgtm:0.8.1 -c "cat
   /otel-lgtm/otelcol-config.yaml"`) and matching `infra/otelcol/config.yaml`
   to it. Fully documented inline in that file.
2. **Grafana datasource provisioning file name collision.** The image
   ships its own `grafana-datasources.yaml` in the same provisioning
   directory with the same `tempo`/`loki`/`prometheus` UIDs. Mounting
   `infra/grafana/datasources.yaml` under a *different* filename
   (`datasources.yaml`) let both files load — Grafana's file-based
   provisioning applies every `*.yaml` in the directory in lexical order,
   and the built-in `grafana-datasources.yaml` sorted after and silently
   won on UID collision, so the custom trace/log correlation settings
   never took effect (confirmed via `GET /api/datasources` showing the
   built-in `jsonData` shape, not ours). Fixed by mounting over the exact
   same filename (`grafana-datasources.yaml`) so there is only one file.
3. **Healthcheck tool.** The generic skill template's `lgtm` healthcheck
   uses `wget`; this image (RHEL 9-based) doesn't ship `wget`, only
   `curl` — confirmed via `docker exec ... command -v wget` returning
   nothing. Healthcheck test switched to `curl -sf`.

**No service emits OTLP yet.** Quarkus OTel instrumentation lands in
Phase D (see `_plans/build-plan.md`). Until then, Grafana's application
dashboards are empty — the collector's *own* self-monitoring metrics
(`otelcol_*`) DO show up, since the stack scrapes itself for the readiness
probe above, but there is no application trace/log/metric data. This is
expected, not a bug: `OTEL_EXPORTER_OTLP_ENDPOINT=http://lgtm:4318` is the
env var a Phase D service will set to start sending data through this
exact, already-validated pipeline with zero further config changes here.

## Postgres

`postgres:18` changed its on-disk layout: it expects a single volume
mount at `/var/lib/postgresql` (it creates its own major-version
subdirectory underneath), not `/var/lib/postgresql/data` as in `postgres:16`
and earlier — mounting at the old path fails immediately with "these
Docker images are configured to store database data in a format which is
compatible with pg_ctlcluster" (confirmed by running the pinned image).
`compose.yaml` mounts the named volume at the new path.

`TZ=UTC` / `PGTZ=UTC` env vars plus `-c timezone=UTC` on the server
command avoid the US/Eastern boot failure documented in
`_plans/decisions.md` ("Test/build notes" — `postgres:18` Dev Services
containers reject legacy Olson zone ids like `US/Eastern` forwarded by
pgjdbc from a non-UTC host).

### Per-service databases

One Postgres instance, one database per service that carries
`quarkus-jdbc-postgresql`/`quarkus-hibernate-orm` (`order-service`,
`inventory-service`, `notification-service`, `review-service`,
`shipping-service` — confirmed by grepping each module's `pom.xml`):
`orderdb`, `inventorydb`, `notificationdb`, `reviewdb`, `shippingdb`. All
owned by the single bootstrap login role (`POSTGRES_USER`/
`POSTGRES_PASSWORD` in `.env`) — only the database name differs between
each service's `%prod` `${JDBC_URL}` (DRQ-011's single env-driven
profile). The default `POSTGRES_DB` (`appdb`) is left as a generic/shared
database for ad hoc `psql` exploration. See `infra/db/init/00-init.sql`.

## Validation performed

All of the following were run live in this environment (Docker Engine
29.8.1 available), not just config-parsed:

- `docker compose config` — parses with no error, no warnings.
- `docker compose up -d` (no profile flags) — `postgres`, `kafka`,
  `apicurio`, and `lgtm` all reach `healthy` status.
- `docker exec datamesh-postgres psql ... \l` — confirms `orderdb`,
  `inventorydb`, `notificationdb`, `reviewdb`, `shippingdb` all exist,
  owned by `appuser`; `SHOW timezone` returns `UTC`.
- `kafkacat -b kafka:9094 -L` (run from a container on the `datamesh`
  network) and `kafkacat -b localhost:9092 -L` (run with `--network
  host`) — both list broker 1 and successfully round-trip topic metadata
  (auto-create-topics produced a 3-partition topic matching
  `KAFKA_NUM_PARTITIONS=3`), confirming both advertised listeners work
  from their respective sides.
- `curl http://localhost:8081/apis/registry/v3/system/info` — HTTP 200,
  confirms the v3 API path required by the `AvroKafka{Serializer,
  Deserializer}` config in DRQ-009.
- `curl http://localhost:3000/api/datasources` — confirms Tempo/Loki/
  Prometheus datasources are provisioned with the custom trace↔log
  correlation `jsonData`, not the image's built-in defaults.
- `docker compose --profile tools up -d kafka-ui` — reached a running
  state; `GET /api/clusters` shows the `datamesh` cluster online, 1
  broker, `SCHEMA_REGISTRY` feature detected (reaches Apicurio's
  Confluent-compatible API); then stopped and removed (profile-only
  service, not part of the baseline).
- `docker compose --profile tools --profile ollama config` — parses with
  no error (the `ollama` profile itself was NOT brought up — it requires
  an 8 GB image pull and is opt-in by design; config-level validation was
  judged sufficient for a profile nothing in Phase C depends on).

Not verified: end-to-end Avro produce/consume through this stack from an
actual example service (that requires step 8b's `%prod` wiring) and the
`ollama` profile's runtime behavior.
