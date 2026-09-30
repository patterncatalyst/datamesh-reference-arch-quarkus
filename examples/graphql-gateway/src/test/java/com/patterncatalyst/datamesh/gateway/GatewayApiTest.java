package com.patterncatalyst.datamesh.gateway;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.is;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;

import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.junit.jupiter.api.Test;

import com.patterncatalyst.datamesh.domain.OrderDto;
import com.patterncatalyst.datamesh.domain.OrderStatus;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.ws.rs.core.Response;

/**
 * Exercises the federated {@code order(id)} query end to end through
 * /graphql. The downstream order-service REST call is mocked with
 * {@link InjectMock} (a normal-scoped REST client bean), while the
 * inventory-service gRPC call is served by an in-process mock gRPC server
 * ({@link MockInventoryService}) -- the gateway's real {@code @GrpcClient}
 * dials it over the wire, so this exercises the actual gRPC stitching rather
 * than a mocked stub. (The {@code @GrpcClient} blocking stub is a
 * {@code @Singleton}, which neither {@code @InjectMock} nor
 * {@code QuarkusMock.installMockForType} can replace -- only normal-scoped
 * beans are mockable -- so an in-process server is the supported way to
 * substitute the downstream.)
 */
@QuarkusTest
class GatewayApiTest {

    @InjectMock
    @RestClient
    OrderRestClient orderRestClient;

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
                .body("data.order.stock.quantityOnHand", is(MockInventoryService.QUANTITY_ON_HAND))
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
