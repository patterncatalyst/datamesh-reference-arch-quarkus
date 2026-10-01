# tooling/

Phase E step 14: operator-facing tooling that exercises the running stack
from the outside — a Postman/Newman API collection and a `hey`-based load
script — as opposed to `demos/`, which are assert-driven narrative scripts
built around one capability each.

```
tooling/
  newman/
    run-newman.sh                     # runs the collection below
    datamesh.postman_collection.json  # requests, grouped into folders
    local.postman_environment.json    # base URLs + variables for local dev
  load/
    load-orders.sh                    # hey-based load generator for POST /orders
```

## Prerequisites

- `newman` on PATH (`npm install -g newman`), or just `npx` — `run-newman.sh`
  falls back to `npx --yes newman@6` automatically if `newman` isn't
  installed.
- `curl`, `jq` on PATH (used for health probing and response parsing).
- `hey` on PATH for the load script — install via `go install
  github.com/rakyll/hey@latest`, or grab a prebuilt binary from the
  [hey releases page](https://github.com/rakyll/hey/releases).

## Bring up the stack first

Both tools assume services are already running — neither brings up
anything itself.

```bash
# one-time: copy the compose env template if you haven't already
cp .env.example .env

# infra baseline (postgres, kafka-native, apicurio, otel-lgtm)
docker compose up -d

# order-service (8091), inventory-service (8092), graphql-gateway (8080)
demos/demo-graphql.sh

# review-service (8098) — separate dev-mode process, Keycloak Dev Service
demos/demo-oidc.sh
```

`demo-graphql.sh` and `demo-oidc.sh` start their services and then run
their own demo assertions before exiting — the services stay up in the
background (dev-mode JVM processes) once the script completes, which is
what the tooling here then targets.

## Run the Newman collection

```bash
./tooling/newman/run-newman.sh
```

This health-probes order-service, inventory-service, and graphql-gateway
(and review-service, unless `--folder` restricts the run to a non-Review
folder) before invoking Newman, and fails loud with the exact bring-up
command if anything required is down — it will not let Newman grind
through a wall of connection-refused errors.

Run a single folder if you only have part of the stack up:

```bash
./tooling/newman/run-newman.sh --folder Health
./tooling/newman/run-newman.sh --folder Inventory
./tooling/newman/run-newman.sh --folder Order
./tooling/newman/run-newman.sh --folder GraphQL
./tooling/newman/run-newman.sh --folder Review
```

## Run the load script

```bash
./tooling/load/load-orders.sh                       # GET /orders, 10 workers, 20s (default)
./tooling/load/load-orders.sh -c 25 -z 60s           # heavier ramp, GET
./tooling/load/load-orders.sh -n 2000 --mode post    # fixed count, POST /orders (seeds inventory first)
```

`--mode get` (default) only reads; `--mode post` seeds `WIDGET-1` stock on
inventory-service first so the ramp doesn't 409 on insufficient stock, then
ramps real `POST /orders` traffic. The script health-gates order-service
(`/q/health`) before starting and lets `hey`'s own summary print — read
`Requests/sec` and the percentile breakdown for the capacity story. Sample
output (20s run, GET mode, warm JVM dev-mode order-service):

```
Summary:
  Total:        20.0053 secs
  Slowest:      0.0734 secs
  Fastest:      0.0019 secs
  Average:      0.0091 secs
  Requests/sec: 1098.4231

Response time histogram:
  0.002 [1]     |
  0.009 [9821]  |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.016 [1230]  |■■■■■
  0.023 [73]    |

Latency distribution:
  10% in 0.0062 secs
  50% in 0.0088 secs
  90% in 0.0141 secs
  99% in 0.0219 secs

Status code distribution:
  [200] 21987 responses
```

## Exclusions — not covered by this tooling

- **503 inventory-unreachable path.** Forcing order-service's gRPC call to
  inventory-service to fail (stop inventory-service mid-request) is a
  manual check, not something the collection or load script automates.
- **Authenticated `DELETE /reviews/{id}` → 204.** The default collection
  run only asserts the **401** unauthenticated-protection case for this
  endpoint. A real 204 delete needs a live Keycloak bearer token (see
  `demos/demo-oidc.sh` for how one is obtained via the Dev Service's
  password grant) — out of scope for an unattended Newman run.
- **gRPC `CheckStock` and the notification WebSocket.** Neither is an HTTP
  endpoint, so neither Newman nor `hey` can reach it. If gRPC load testing
  is ever wanted, reach for [`ghz`](https://ghz.sh/) instead.
