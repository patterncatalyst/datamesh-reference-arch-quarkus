package com.patterncatalyst.datamesh.review;

import static io.restassured.RestAssured.given;

import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;

/**
 * RBAC regression coverage for {@code DELETE /reviews/{id}} -- code finding
 * H2 (the OIDC authz gap). This is the reactor's ONLY {@code @RolesAllowed}
 * / OIDC demo endpoint (see {@link ReviewResource} class Javadoc and
 * {@code demos/demo-oidc.sh}), so it must be the best-tested path:
 *
 * <ul>
 *   <li>no bearer token -> 401 (quarkus-oidc's own unauthenticated-request
 *       behavior, exercised without {@code @TestSecurity} so the real OIDC
 *       auth mechanism is what's under test for this case);</li>
 *   <li>an authenticated identity without the "admin" role -> 403;</li>
 *   <li>an authenticated identity with the "admin" role -> 204.</li>
 * </ul>
 *
 * <p>{@code @TestSecurity} (from the {@code quarkus-test-security} test
 * dependency added alongside this file) lets the 403/204 cases run as a
 * given user/role set without needing a real Keycloak Dev Services token.
 */
@QuarkusTest
class ReviewDeleteResourceTest {

    @Test
    void delete_returns401_withNoToken() {
        given()
                .when().delete("/reviews/999999")
                .then()
                .statusCode(401);
    }

    @Test
    @TestSecurity(user = "bob", roles = {"user"})
    void delete_returns403_withNonAdminRole() {
        given()
                .when().delete("/reviews/999999")
                .then()
                .statusCode(403);
    }

    @Test
    @TestSecurity(user = "alice", roles = {"admin"})
    void delete_returns204_withAdminRole() {
        Object id = given()
                .contentType("application/json")
                .body("""
                        {"sku":"SKU-DELETE-1","rating":5,"reviewer":"cust-delete-1","comment":"to be deleted"}
                        """)
                .when().post("/reviews")
                .then()
                .statusCode(201)
                .extract().path("id");

        given()
                .when().delete("/reviews/" + id)
                .then()
                .statusCode(204);
    }
}
