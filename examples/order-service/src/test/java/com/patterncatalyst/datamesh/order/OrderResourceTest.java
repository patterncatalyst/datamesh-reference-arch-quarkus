package com.patterncatalyst.datamesh.order;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import org.junit.jupiter.api.Test;

import capstone.inventory.v1.Inventory.CheckStockResponse;
import io.grpc.Status;
import io.grpc.StatusRuntimeException;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.RestAssured;

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
    void placeOrder_returns503_whenInventoryUnreachable() {
        // Finding L6: InventoryClient#checkStock propagates a
        // StatusRuntimeException uncaught when inventory-service is
        // unreachable/times out; OrderResource must fail closed (503)
        // rather than place an order it couldn't validate -- see
        // OrderResource#placeOrder's try/catch and InventoryClient's class
        // Javadoc.
        when(inventoryClient.checkStock("sku-unreachable", 1))
                .thenThrow(new StatusRuntimeException(Status.UNAVAILABLE.withDescription("inventory-service unreachable")));

        given()
                .contentType("application/json")
                .body("{\"customerId\":\"cust-unreachable\",\"itemSku\":\"sku-unreachable\",\"quantity\":1,\"amount\":9.99}")
                .when().post("/orders")
                .then()
                .statusCode(503);
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

    @Test
    void listOrders_ignoresNonJsonContentType_sinceGetHasNoRequestBody() throws Exception {
        // Regression test for the 415-on-GET defect: a sibling POST method's
        // @Consumes(APPLICATION_JSON) must not leak onto this bodyless GET,
        // or RESTEasy Reactive 415s any client whose Content-Type isn't JSON
        // (e.g. hey's default text/html) instead of serving it. The fix is
        // @Consumes(MediaType.WILDCARD) on the GET methods themselves.
        //
        // NOTE: this must NOT be written with RestAssured's given()/get() --
        // confirmed empirically that RestAssured silently drops a
        // Content-Type header it's told to send on a bodyless GET (no
        // request body means its underlying Apache HttpClient never
        // transmits the header), so a RestAssured-based version of this test
        // passes even when the 415 regression is present (a false pass this
        // replaces). java.net.http.HttpClient sends exactly the headers it's
        // given regardless of body, matching the curl-based live
        // verification this guards.
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(RestAssured.baseURI + ":" + RestAssured.port + "/orders"))
                .header("Content-Type", "text/html")
                .GET()
                .build();
        HttpResponse<Void> response = HttpClient.newHttpClient()
                .send(request, HttpResponse.BodyHandlers.discarding());
        assertEquals(200, response.statusCode(),
                "GET /orders with a non-JSON Content-Type must not 415");
    }
}
