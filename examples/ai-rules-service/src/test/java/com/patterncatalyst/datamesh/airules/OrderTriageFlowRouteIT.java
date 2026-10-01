package com.patterncatalyst.datamesh.airules;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.oneOf;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

/**
 * Behavioral, end-to-end test of the DRQ-014 Quarkus Flow A/B contrast: the
 * same order JSON body {@link OrderTriageRouteIT} posts to {@code /triage}
 * (the Camel path) is posted here to {@code /triage-flow} (the Flow path),
 * which is classified by a live Ollama server ({@code qwen2.5:3b}) and
 * routed through the same embedded Drools engine to produce a
 * {@link TriageDecision}.
 *
 * <p>Deliberately deferred / opt-in, same idiom as {@link OrderTriageRouteIT}:
 * named {@code *IT} (skipped by Surefire's default include patterns, and
 * Failsafe is not bound in this module either way) and additionally gated
 * behind the {@code ollama.tests.enabled} system property.
 *
 * <p>Because an LLM response is not deterministic, this test only asserts
 * that the HTTP call succeeds and that Drools produced one of the three
 * valid decisions -- it does not pin an exact classification.
 *
 * <p>Run with:
 * <pre>
 * ollama pull qwen2.5:3b
 * ollama serve
 * mvn test -Dollama.tests.enabled=true -Dtest=OrderTriageFlowRouteIT -f examples/pom.xml -pl ai-rules-service
 * </pre>
 */
@QuarkusTest
@EnabledIfSystemProperty(named = "ollama.tests.enabled", matches = "true")
class OrderTriageFlowRouteIT {

    @Test
    void triageFlowEndpointReturnsADroolsDecision() {
        given()
            .contentType("application/json")
            .body("{\"customerId\":\"CUST-42\",\"itemSku\":\"LAPTOP-15\",\"quantity\":1,\"amount\":1899.99}")
        .when()
            .post("/api/orders/triage-flow")
        .then()
            .statusCode(200)
            .body("decision", oneOf("FRAUD_HOLD", "EXPEDITE", "ROUTE_TO_WAREHOUSE"))
            .body("reason", org.hamcrest.Matchers.notNullValue());
    }
}
