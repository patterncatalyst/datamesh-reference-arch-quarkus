package com.patterncatalyst.datamesh.airules;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.oneOf;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

/**
 * Behavioral, end-to-end test of the showcase: a real order JSON
 * body is classified by a live Ollama server ({@code qwen2.5:3b}) via
 * {@code langchain4j-chat}, and the resulting classification is routed
 * through the embedded Drools engine to produce a {@link TriageDecision}.
 *
 * <p>Deliberately deferred / opt-in, same idiom as ai-mcp-service's
 * {@code OrderAssistantRouteIT}:
 * <ul>
 *   <li>Named {@code *IT}, not {@code *Test} -- Surefire's default include
 *       patterns skip it, so a plain {@code mvn test} / {@code mvn package}
 *       / {@code mvn verify} never runs it and never needs Ollama.</li>
 *   <li>Additionally gated behind the {@code ollama.tests.enabled} system
 *       property, so even running it through Failsafe or an IDE by class
 *       name requires an explicit opt-in flag. Failsafe is not bound in this
 *       module either way.</li>
 * </ul>
 *
 * <p>Because an LLM response is not deterministic, this test only asserts
 * that the HTTP call succeeds and that Drools produced one of the three
 * valid decisions -- it does not pin an exact classification. The
 * deterministic, per-branch assertions live in {@link OrderTriageDrlTest}.
 *
 * <p>Run with:
 * <pre>
 * ollama pull qwen2.5:3b
 * ollama serve
 * mvn test -Dollama.tests.enabled=true -Dtest=OrderTriageRouteIT -f examples/pom.xml -pl ai-rules-service
 * </pre>
 */
@QuarkusTest
@EnabledIfSystemProperty(named = "ollama.tests.enabled", matches = "true")
class OrderTriageRouteIT {

    @Test
    void triageEndpointReturnsADroolsDecision() {
        given()
            .contentType("application/json")
            .body("{\"customerId\":\"CUST-42\",\"itemSku\":\"LAPTOP-15\",\"quantity\":1,\"amount\":1899.99}")
        .when()
            .post("/api/orders/triage")
        .then()
            .statusCode(200)
            .body("decision", oneOf("FRAUD_HOLD", "EXPEDITE", "ROUTE_TO_WAREHOUSE"))
            .body("reason", org.hamcrest.Matchers.notNullValue());
    }
}
