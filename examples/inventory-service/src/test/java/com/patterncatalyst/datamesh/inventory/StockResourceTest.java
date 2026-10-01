package com.patterncatalyst.datamesh.inventory;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.jupiter.api.Assertions.assertEquals;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.RestAssured;

/**
 * REST-level tests for {@link StockResource}. Dev Services provisions the
 * Postgres container automatically for @QuarkusTest.
 */
@QuarkusTest
class StockResourceTest {

    @Test
    void seed_createsStock_andEchoesQuantityAndAvailability() {
        given()
                .contentType("application/json")
                .body("{\"sku\":\"sku-seed-create-1\",\"available\":true,\"quantityOnHand\":25}")
                .when().post("/stock")
                .then()
                .statusCode(200)
                .body("sku", equalTo("sku-seed-create-1"))
                .body("quantityOnHand", equalTo(25))
                .body("available", equalTo(true));
    }

    @Test
    void seed_updatesExistingStock_onRepeatedSku() {
        given()
                .contentType("application/json")
                .body("{\"sku\":\"sku-seed-update-1\",\"available\":true,\"quantityOnHand\":5}")
                .when().post("/stock")
                .then()
                .statusCode(200)
                .body("quantityOnHand", equalTo(5));

        given()
                .contentType("application/json")
                .body("{\"sku\":\"sku-seed-update-1\",\"available\":true,\"quantityOnHand\":40}")
                .when().post("/stock")
                .then()
                .statusCode(200)
                .body("sku", equalTo("sku-seed-update-1"))
                .body("quantityOnHand", equalTo(40));
    }

    @Test
    void list_returnsOk() {
        given()
                .when().get("/stock")
                .then()
                .statusCode(200);
    }

    @Test
    void getBySku_returnsStock_whenFound() {
        given()
                .contentType("application/json")
                .body("{\"sku\":\"sku-get-found-1\",\"available\":true,\"quantityOnHand\":7}")
                .when().post("/stock")
                .then()
                .statusCode(200);

        given()
                .when().get("/stock/sku-get-found-1")
                .then()
                .statusCode(200)
                .body("sku", equalTo("sku-get-found-1"))
                .body("quantityOnHand", equalTo(7));
    }

    @Test
    void getBySku_returns404_whenMissing() {
        given()
                .when().get("/stock/does-not-exist")
                .then()
                .statusCode(404);
    }

    @Test
    void list_ignoresNonJsonContentType_sinceGetHasNoRequestBody() throws Exception {
        // Regression test for the 415-on-GET defect (same class of bug as
        // OrderResourceTest's listOrders_ignoresNonJsonContentType_...):
        // a sibling POST method's @Consumes(APPLICATION_JSON) must not leak
        // onto this bodyless GET, or RESTEasy Reactive 415s any client whose
        // Content-Type isn't JSON (e.g. hey's default text/html) instead of
        // serving it. The fix is @Consumes(MediaType.WILDCARD) on the GET
        // methods themselves.
        //
        // NOTE: this must NOT be written with RestAssured's given()/get() --
        // confirmed (see OrderResourceTest) that RestAssured silently drops
        // a Content-Type header it's told to send on a bodyless GET, so a
        // RestAssured-based version of this test passes even when the 415
        // regression is present. java.net.http.HttpClient sends exactly the
        // headers it's given regardless of body.
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(RestAssured.baseURI + ":" + RestAssured.port + "/stock"))
                .header("Content-Type", "text/html")
                .GET()
                .build();
        HttpResponse<Void> response = HttpClient.newHttpClient()
                .send(request, HttpResponse.BodyHandlers.discarding());
        assertEquals(200, response.statusCode(),
                "GET /stock with a non-JSON Content-Type must not 415");
    }
}
