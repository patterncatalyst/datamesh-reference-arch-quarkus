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
- `GET /q/health`, `/q/health/live`, `/q/health/ready` -- SmallRye Health
  probes (liveness/readiness; readiness includes the Postgres datasource
  check registered automatically by `quarkus-agroal`).

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
# from examples/pom.xml (reactor)
mvn -pl review-service test -f ../pom.xml
```

`ReviewResourceTest` (`@QuarkusTest`) covers: successful creation, rating
validation (`400` for `rating < 1` or `rating > 5`), listing, and the `sku`
filter.
