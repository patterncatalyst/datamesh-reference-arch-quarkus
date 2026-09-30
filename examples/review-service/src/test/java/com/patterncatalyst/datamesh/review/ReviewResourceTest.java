package com.patterncatalyst.datamesh.review;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.hamcrest.Matchers.is;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * REST-level tests for the review-service data product. Dev Services
 * provisions the Postgres container automatically for @QuarkusTest.
 *
 * Written per the EXECUTE-phase spec; NOT run as part of this task.
 */
@QuarkusTest
class ReviewResourceTest {

    @Test
    void createReviewSucceedsWithValidRating() {
        given()
                .contentType("application/json")
                .body("""
                        {"sku":"SKU-ABC-42","rating":5,"reviewer":"cust-1001","comment":"Solid, would buy again."}
                        """)
                .when().post("/reviews")
                .then()
                .statusCode(201)
                .body("sku", equalTo("SKU-ABC-42"))
                .body("rating", equalTo(5))
                .body("reviewer", equalTo("cust-1001"));
    }

    @Test
    void createReviewRejectsRatingAboveFive() {
        given()
                .contentType("application/json")
                .body("""
                        {"sku":"SKU-ABC-42","rating":6,"reviewer":"cust-1001","comment":"too high"}
                        """)
                .when().post("/reviews")
                .then()
                .statusCode(400);
    }

    @Test
    void createReviewRejectsRatingBelowOne() {
        given()
                .contentType("application/json")
                .body("""
                        {"sku":"SKU-ABC-42","rating":0,"reviewer":"cust-1001","comment":"too low"}
                        """)
                .when().post("/reviews")
                .then()
                .statusCode(400);
    }

    @Test
    void listReviewsReturnsCreatedReview() {
        given()
                .contentType("application/json")
                .body("""
                        {"sku":"SKU-LIST-1","rating":4,"reviewer":"cust-2002","comment":"Good."}
                        """)
                .when().post("/reviews")
                .then()
                .statusCode(201);

        given()
                .when().get("/reviews")
                .then()
                .statusCode(200)
                .body("size()", greaterThanOrEqualTo(1));
    }

    @Test
    void listReviewsFiltersBySku() {
        given()
                .contentType("application/json")
                .body("""
                        {"sku":"SKU-FILTER-1","rating":3,"reviewer":"cust-3003","comment":"Ok."}
                        """)
                .when().post("/reviews")
                .then()
                .statusCode(201);

        given()
                .queryParam("sku", "SKU-FILTER-1")
                .when().get("/reviews")
                .then()
                .statusCode(200)
                .body("size()", is(greaterThanOrEqualTo(1)))
                .body("sku", org.hamcrest.Matchers.everyItem(equalTo("SKU-FILTER-1")));
    }
}
