package com.patterncatalyst.datamesh.aimcp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import jakarta.inject.Inject;

import io.quarkus.test.junit.QuarkusTest;
import org.apache.camel.CamelContext;
import org.apache.camel.Route;
import org.apache.camel.ServiceStatus;
import org.junit.jupiter.api.Test;

/**
 * Wiring test: verifies the Camel routes for the classifier, the order-lookup
 * tool, and the assistant are registered and started, WITHOUT calling any
 * langchain4j endpoint. Deliberately does not require Ollama (or any LLM) to
 * be running.
 *
 * <p>The behavioral, tool-calling assertion (that {@code toolExecutions} comes
 * back non-empty for the assistant) lives in {@link OrderAssistantRouteIT},
 * which is opt-in and requires a live Ollama server -- see this module's
 * README.
 */
@QuarkusTest
class OrderClassifierRouteTest {

    @Inject
    CamelContext camelContext;

    @Test
    void contextStartsWithAllRoutesRegistered() {
        assertNotNull(camelContext);
        assertEquals(ServiceStatus.Started, camelContext.getStatus());

        assertRouteStartedOnEndpoint("classify-order", "direct:classify-order");
        assertRouteStartedOnEndpoint("order-lookup-tool", "ai-tool:order-status");
        assertRouteStartedOnEndpoint("assistant-chat", "direct:assistant-chat");
    }

    private void assertRouteStartedOnEndpoint(String routeId, String expectedUriPrefix) {
        Route route = camelContext.getRoute(routeId);
        assertNotNull(route, () -> "Expected route '" + routeId + "' to be registered");

        ServiceStatus status = camelContext.getRouteController().getRouteStatus(routeId);
        assertTrue(status.isStarted(), () -> "Expected route '" + routeId + "' to be started, was " + status);

        String endpointUri = route.getEndpoint().getEndpointUri();
        assertTrue(endpointUri.startsWith(expectedUriPrefix),
                () -> "Route '" + routeId + "' expected endpoint starting with '" + expectedUriPrefix
                        + "' but was '" + endpointUri + "'");
    }
}
