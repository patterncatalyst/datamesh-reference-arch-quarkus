package com.patterncatalyst.datamesh.gateway;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.is;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;

import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.junit.jupiter.api.Test;

import capstone.inventory.v1.Inventory.CheckStockResponse;
import capstone.inventory.v1.InventoryServiceGrpc;

import com.patterncatalyst.datamesh.domain.OrderDto;
import com.patterncatalyst.datamesh.domain.OrderStatus;

import io.quarkus.grpc.GrpcClient;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.ws.rs.core.Response;

/**
 * Exercises the federated {@code order(id)} query end to end through
 * /graphql, with the downstream order-service REST call and
 * inventory-service gRPC call mocked -- this test asserts the gateway's own
 * stitching behavior, not the (not-yet-built) downstream services.
 *
 * NOTE: written for review only, per the executor's instructions -- not run
 * as part of this batch.
 */
@QuarkusTest
class GatewayApiTest {

    @InjectMock
    @RestClient
    OrderRestClient orderRestClient;

    @InjectMock
    @GrpcClient("inventory")
    InventoryServiceGrpc.InventoryServiceBlockingStub inventoryClient;

    @Test
    void resolvesOrderWithNestedStockOverGrpc() {
        OrderDto dto = new OrderDto(
                "order-1",
                "customer-1",
                "SKU-1",
                2,
                new BigDecimal("19.99"),
                OrderStatus.PLACED,
                "2026-09-30T00:00:00Z");
        when(orderRestClient.getOrder("order-1")).thenReturn(Response.ok(dto).build());
        when(inventoryClient.checkStock(any())).thenReturn(CheckStockResponse.newBuilder()
                .setAvailable(true)
                .setQuantityOnHand(42)
                .build());

        String query = "{ \"query\": \"{ order(id: \\\"order-1\\\") { id customerId itemSku quantity status "
                + "stock { sku quantityOnHand available } } }\" }";

        given()
                .contentType(ContentType.JSON)
                .body(query)
                .when()
                .post("/graphql")
                .then()
                .statusCode(200)
                .body("data.order.id", is("order-1"))
                .body("data.order.itemSku", is("SKU-1"))
                .body("data.order.stock.sku", is("SKU-1"))
                .body("data.order.stock.quantityOnHand", is(42))
                .body("data.order.stock.available", is(true));
    }

    @Test
    void returnsNullWhenOrderNotFoundInOrderService() {
        when(orderRestClient.getOrder("missing"))
                .thenReturn(Response.status(Response.Status.NOT_FOUND).build());

        String query = "{ \"query\": \"{ order(id: \\\"missing\\\") { id } }\" }";

        given()
                .contentType(ContentType.JSON)
                .body(query)
                .when()
                .post("/graphql")
                .then()
                .statusCode(200)
                .body("data.order", is((Object) null));
    }
}
