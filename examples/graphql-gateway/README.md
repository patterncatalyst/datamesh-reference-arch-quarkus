# graphql-gateway

SmallRye GraphQL federation gateway for the shipping/order domain. Mirrors
the Strawberry gateway in `datamesh-reference-arch-python`
(`services/graphql-gateway/app/schema.py` + `app/clients.py`): a client asks
one GraphQL question and gets a response stitched from two downstream
services over two different protocols (CAP-012's protocol comparison, made
concrete).

This module owns no data. It federates reads by calling:

- **order-service** over REST — `GET /orders/{id}`.
- **inventory-service** over gRPC — `CheckStock` RPC
  (`capstone.inventory.v1.InventoryService`, defined in the `contracts`
  module).

## Schema

```graphql
type Query {
  order(id: String): OrderView
}

type OrderView {
  id: String
  customerId: String
  itemSku: String
  quantity: Int
  amount: BigDecimal
  status: OrderStatus
  createdAt: String
  stock: StockView
}

type StockView {
  sku: String
  quantityOnHand: Int
  available: Boolean
}
```

`stock` is a `@Source`-resolved field (`GatewayApi.stock(OrderView)`) — it is
only fetched from inventory-service when a client's query selects
it, not on every `order` lookup.

GraphiQL is enabled by default in dev/test at `/q/graphql-ui`
(`%dev.quarkus.smallrye-graphql.ui.always-include=true` in
`application.properties` makes that default explicit).

## Downstream wiring

| Downstream | Protocol | Config keys |
|---|---|---|
| order-service | REST (`@RegisterRestClient(configKey = "order-service")`) | `quarkus.rest-client.order-service.url`, `.connect-timeout`, `.read-timeout` |
| inventory-service | gRPC (`@GrpcClient("inventory")`) | `quarkus.grpc.clients.inventory.host`, `.port` |

gRPC stubs (`InventoryServiceGrpc`, `CheckStockRequest`, `CheckStockResponse`
in package `capstone.inventory.v1`) are generated at build time from the
`.proto` packaged inside the `contracts` dependency jar, via:

```properties
quarkus.generate-code.grpc.scan-for-proto=com.patterncatalyst.datamesh:contracts
```

No `.proto` file is duplicated in this module — see `contracts/README.md`.

## order-service contract

order-service is a fully implemented module in this reactor (Panache
persistence, gRPC stock check, `order.placed` Avro event emission — see
`examples/order-service/README.md`). `OrderRestClient` and
`GatewayApi.order(id)` federate against its `GET /orders/{id}`
endpoint, which returns:

- `200` with a JSON body whose fields match
  `com.patterncatalyst.datamesh.domain.OrderDto`'s record components
  (`orderId`, `customerId`, `itemSku`, `quantity`, `amount`, `status`,
  `createdAt`) — the same DTO domain-model documents as "used across
  REST/GraphQL responses."
- `404` for an unknown order id, mapped to a `null` GraphQL result (no
  `ResponseExceptionMapper` needed — `GatewayApi.order` reads the raw
  `Response` status directly).

## Local run

```properties
# defaults target port-forwards / local processes; override per environment.
# order-service runs on 8091 in this reactor's demos/compose stack --
# 8081 is already taken by the Apicurio Schema Registry's compose host port
# (infra/.env's APICURIO_PORT), so don't reuse it here.
ORDER_SERVICE_URL=http://localhost:8091
INVENTORY_GRPC_HOST=localhost
INVENTORY_GRPC_PORT=9000
```

```bash
mvn -pl graphql-gateway -am quarkus:dev -f examples/pom.xml
```

## Tests

`GatewayApiTest` (`@QuarkusTest`) mocks both `OrderRestClient`
(`@InjectMock @RestClient`) and the `inventory` gRPC blocking stub
(`@InjectMock @GrpcClient("inventory")`) and asserts the federated response
via REST Assured against `/graphql` — it exercises the gateway's own
stitching logic in isolation, with the order-service and inventory-service
calls mocked rather than run against live downstream services.
