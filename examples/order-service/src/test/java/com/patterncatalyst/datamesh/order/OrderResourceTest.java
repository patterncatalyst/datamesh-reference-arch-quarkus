package com.patterncatalyst.datamesh.order;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;

import capstone.inventory.v1.Inventory.CheckStockResponse;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;

/**
 * REST-level tests for {@link OrderResource}. {@link InventoryClient} is
 * mocked so these tests don't depend on a running inventory-service; Postgres
 * and Kafka/Apicurio are still provided by Quarkus Dev Services (Testcontainers).
 *
 * <p><b>Not run as part of this module's build</b> ({@code -DskipTests} on
 * the per-module {@code mvn package} check) -- @QuarkusTest suites across the
 * reactor are run serially in a later batch to avoid Dev Services /
 * Testcontainers port and resource contention between concurrently building
 * sibling modules. Written here so that batch has something to run.
 */
@QuarkusTest
class OrderResourceTest {

    @InjectMock
    InventoryClient inventoryClient;

    @Test
    void placeOrder_persistsAndReturns201_whenStockAvailable() {
        when(inventoryClient.checkStock("sku-1", 2))
                .thenReturn(CheckStockResponse.newBuilder()
                        .setAvailable(true)
                        .setQuantityOnHand(10)
                        .build());

        given()
                .contentType("application/json")
                .body("{\"customerId\":\"cust-1\",\"itemSku\":\"sku-1\",\"quantity\":2,\"amount\":19.99}")
                .when().post("/orders")
                .then()
                .statusCode(201)
                .body("customerId", equalTo("cust-1"))
                .body("itemSku", equalTo("sku-1"))
                .body("status", equalTo("PLACED"));
    }

    @Test
    void placeOrder_returns409_whenStockUnavailable() {
        when(inventoryClient.checkStock("sku-2", 100))
                .thenReturn(CheckStockResponse.newBuilder()
                        .setAvailable(false)
                        .setQuantityOnHand(0)
                        .build());

        given()
                .contentType("application/json")
                .body("{\"customerId\":\"cust-2\",\"itemSku\":\"sku-2\",\"quantity\":100,\"amount\":5.00}")
                .when().post("/orders")
                .then()
                .statusCode(409);
    }

    @Test
    void getOrder_returns404_whenMissing() {
        given()
                .when().get("/orders/does-not-exist")
                .then()
                .statusCode(404);
    }

    @Test
    void listOrders_returnsOk() {
        given()
                .when().get("/orders")
                .then()
                .statusCode(200);
    }
}
