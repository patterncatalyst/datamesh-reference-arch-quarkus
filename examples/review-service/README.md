# review-service

A DataMesh reference architecture data product: product reviews/ratings.
Mirrors the Python capstone's `review-service` one-for-one (see
`datamesh-reference-arch-python/examples/lgtm-datamesh/services/review-service`),
rebuilt on Quarkus + Panache.

Owns the `Review` table exclusively (per-service data ownership) -- no other
module in the reactor writes to it.

## Endpoints

- `POST /reviews` -- create a review. Body: `{"sku", "rating" (1..5),
  "reviewer", "comment"}`. Returns `201` with the created review, or `400`
  if `rating` is outside `1..5` (Bean Validation on the request DTO).
- `GET /reviews` -- list all reviews, newest first is not guaranteed (no
  explicit order clause yet); supports `?sku=...` to filter by product SKU.
- `GET /reviews/{id}` -- fetch one review by its generated id; `404` if not
  found.
- `DELETE /reviews/{id}` -- admin-only moderation; `204` on success, `404`
  if not found. Protected by OIDC bearer-token RBAC (`@RolesAllowed("admin")`):
  no token -> `401`, a token without the `admin` role -> `403`. This is the
  reactor's live OIDC + Keycloak Dev Service demo (DRQ-005; see
  `demos/demo-oidc.sh`) -- see "Security (OIDC)" below.
- `GET /q/health`, `/q/health/live`, `/q/health/ready` -- SmallRye Health
  probes (liveness/readiness; readiness includes the Postgres datasource
  check registered automatically by `quarkus-agroal`).

## Security (OIDC)

`quarkus-oidc` is on the classpath with no `quarkus.oidc.*` config set, so
in dev/test Quarkus Dev Services auto-provisions a disposable Keycloak
container: realm `quarkus`, client `quarkus-app`/`secret`, and the builtin
users `alice`/`alice` (roles `admin`+`user`) and `bob`/`bob` (role `user`
only). `DELETE /reviews/{id}` is the only protected endpoint; everything
else is unauthenticated, unchanged.

```bash
# from examples/review-service/ (mvn quarkus:dev running on the default port 8080)
# The Keycloak Dev Service binds a RANDOM host port -- find it from the
# `quarkus:dev` startup log ("Dev Services for Keycloak started") or the Dev
# UI; KC_PORT below stands in for whatever that turns out to be.
TOKEN=$(curl -s -X POST "http://localhost:${KC_PORT}/realms/quarkus/protocol/openid-connect/token" \
  --user quarkus-app:secret \
  -d 'username=alice&password=alice&grant_type=password' | jq -r .access_token)

curl -s -o /dev/null -w '%{http_code}\n' -X DELETE localhost:8080/reviews/1                       # 401 (no token)
curl -s -o /dev/null -w '%{http_code}\n' -X DELETE localhost:8080/reviews/1 -H "Authorization: Bearer $TOKEN"  # 204/404
```

See `demos/demo-oidc.sh` for the scripted version, including how it
discovers that random Keycloak port automatically (`docker port` against the
container id Testcontainers logs).

## Storage

Postgres via Hibernate ORM with Panache (active record). In dev and test
mode, Quarkus Dev Services starts a disposable Postgres container
automatically -- no local Postgres or connection config needed. Schema is
created via `drop-and-create` in dev/test and `create` in `%prod` (a real
deployment would use Flyway/Liquibase instead; out of scope for this
example).

## Run

```bash
# from examples/review-service/
mvn quarkus:dev
```

```bash
curl -s -X POST localhost:8080/reviews \
  -H 'content-type: application/json' \
  -d '{"sku":"SKU-ABC-42","rating":5,"reviewer":"cust-1001","comment":"Solid, would buy again."}'

curl -s 'localhost:8080/reviews?sku=SKU-ABC-42'
```

## Test

```bash
# from the repo root
mvn -pl review-service test -f examples/pom.xml
```

`ReviewResourceTest` (`@QuarkusTest`) covers: successful creation, rating
validation (`400` for `rating < 1` or `rating > 5`), listing, and the `sku`
filter.
